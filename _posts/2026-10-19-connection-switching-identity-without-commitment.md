---
layout: post
title: "Connection Switching: Identity without commitment"
date: 2026-10-19 15:00:00 +1200
author: "Sam Barker"
author_url: "https://github.com/sambarker"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "routing" ]
---

[Post 1]({% post_url 2026-10-12-these-are-not-the-brokers-you-are-connecting-to %}) introduced the Routing API and the fundamental shift it brings: a Virtual Kafka Cluster (VKC) is no longer a fixed pipe wired to a single physical cluster on boot. It's a stable identity. What actually lives behind it is now the proxy's problem, not the client's.

We called the first pattern **Connection Switching**.

Connection switching makes the smallest possible change to Kafka protocol semantics. A connection to a VKC is still a connection to exactly one physical cluster — no fan-out, no merging, no weaving. The broker on the other end behaves like any Kafka broker, because it is one. What the proxy adds is a single degree of freedom: *which* cluster. Think of it in DNS terms: we transform a hardwired A record into a CNAME. The client has a stable name; where the traffic actually lands is entirely up to the proxy.

Post 1 framed it as throwing points before the train departs: the routing decision is made once at connection time, and after that it's a straight run to the destination. That's still the right picture. This post is about what the stationmaster has to do to make the points throw cleanly — and what falls off the back of the train when they do.

## What you can do with it (and the dream it sets up)

### The single front door: Tenant & workload dispatch

Workload collision is one of Kafka's classic growing pains. When operations eventually wants to separate workloads onto dedicated hardware — high-IOPS brokers for latency-sensitive services, bulk storage for batch analytics, a shared tier for everything else — the old world makes it a multi-week coordination exercise: provision new hardware, issue new bootstrap URLs, cajole twenty application teams into updating their config repositories, and schedule rolling restarts.

With connection switching, everyone bootstraps at `kafka.corp.internal:9092`. When a client connects, the router inspects the authentication context established during handshake—who is knocking on the door? — and dispatches the connection to the appropriate physical cluster behind the scenes:

- High-throughput production services get routed to dedicated, high-IOPS NVMe brokers.
- Heavy batch analytics jobs get dispatched to the spinning rust cluster.
- General application traffic stays on the shared tier.

Now, let's be honest about the boundaries: migrating a producer pumping ephemeral clickstream data to a new cluster is trivial with connection switching—the platform team updates the route, and the producer begins writing to the new cluster with zero config changes and zero downtime. But what about the downstream analytics consumers that need to process that data? If they need continuous historical context, or if data was split across clusters mid-stream, the downstream consumer story is much more complicated. The proxy solves the connection and routing problem, but physical log replication and consumer offset synchronisation remain out-of-band challenges (the DR and migrations section below gets into what that actually requires). Still, for producers emitting fresh streams or teams operating in clean, discrete domains, connection switching eliminates the connection coordination nightmare entirely.

### Client-change-free cluster migrations and DR failover

Let’s not pretend this is "seamless"—switching a distributed state machine like Kafka between physical backends always carries operational friction. But traditionally, both planned migrations (e.g. major version bumps, moving to KRaft, cloud region shifts) and unplanned Disaster Recovery (DR) failovers share an expensive logistical bottleneck: changing client endpoints.

In a conventional setup, redirecting traffic to a secondary cluster or a freshly provisioned "Green" environment means:
- Coordinating with dozens of independent application teams.
- Updating DNS records (with all the painful quirks as DNS propagates, seemingly at random[^1]) or editing hundreds of configuration maps.
- Bouncing client fleets across an agreed maintenance window—or watching an incident drag out while waiting for client restarts.

Connection switching doesn't solve the hard data replication or consumer offset reconciliation problem, but it **completely eliminates the client-side migration cost**. The bootstrap configuration remains stable (`kafka.corp.internal:9092`).

When executing a planned migration or a DR failover:

- **The data plane is handled out-of-band:** Topics and offsets are synced beforehand via active replication (MirrorMaker 2, KIP-1279 cluster mirroring, or your vendor's equivalent), or recovered from storage volume snapshots.
- **The connection cutover is a control-plane flip:** The proxy updates its route target to the secondary cluster and drops active downstream client connections. Rather than attempting to hand over in-flight state, we let Kafka clients do what they were built to do: reconnect to the stable bootstrap address, issue a fresh `MetadataRequest`, discover the secondary cluster's virtual broker endpoints, and resume from where they left off.
- **Rollback is instant:** If the secondary cluster misbehaves under live load, you can revert the routing target in seconds rather than triggering another round of client config rollbacks.

Whether you're doing a planned blue/green transition or invoking DR in an emergency, connection switching takes client coordination off the critical path. The data still has to be in sync — that's on you — but at least the cutover itself isn't a multi-team event.

## How the proxy makes it work

Post 1 established that Kafka clients care intensely about broker identity: *Broker 1 is Broker 1*. When a client bootstraps, it asks for a cluster map and manages direct connections to each broker at the address advertised for its `NodeId`.

To switch what sits behind those connections without triggering that "unexpected divorce", the proxy runtime has to solve two concrete problems:

1. **In-band topology discovery:** The proxy needs to learn which brokers exist in the target cluster without running out-of-band polling loops or requiring separate management credentials. By design, Kroxylicious discovers this on the fly directly from client traffic.
2. **Broker identity virtualisation:** Once the proxy knows the underlying topology, it has to prevent collisions. If cluster A and cluster B both contain a "broker 2" (and they almost certainly will), presenting both behind the same virtual cluster requires deterministically translating node IDs so the client never sees a clash.

Here's what's actually happening under the hood.

### Topology discovery happens in-band

What's the point of being a Layer 7 protocol proxy if you don't take advantage of the protocol? Kafka already advertises the broker layout as part of every `MetadataResponse`—so the proxy simply listens in.

Doing discovery in-band means we don't need background polling loops, synthetic health checks, or separate privileged admin credentials to keep an out-of-band cluster map warm. When a route's topology is unknown, discovery inherits the client's authenticated connection, and the proxy harvests the broker layout from the traffic that flows through.

Topology state is cached per-router and shared across all connections using that router — so a second connection to the same virtual cluster benefits from what the first one already discovered. The cache uses additive semantics: entries are added as they are learned, never removed. That matters for safety. A low-privilege connection might get a filtered `MetadataResponse` covering only the topics it can see; an additive cache means it can only *contribute* knowledge, never silently evict entries that a higher-privilege connection established. And cache poisoning doesn't translate into an access control bypass either — the cache only influences routing decisions. Brokers enforce ACLs on every request regardless; a misdirected frame gets an error, not someone else's data.

When a client sends a request to a route whose topology the proxy doesn't know yet — on first connection, or after a stale entry — it discovers it on demand. The proxy synthesises a `MetadataRequest` on the active client channel, uses the response to populate its topology cache, and then forwards the original request as normal.

This is all proven technology from the pre-routing world, but routing throws us a curve ball.

### When is 2 != 2?

When broker 2 on cluster A and broker 2 on cluster B are both managed behind the same router.

A single connection only ever talks to one cluster at a time — so a client will never see a `MetadataResponse` containing brokers from both. But the router configuration covers both routes simultaneously, and the proxy runtime maintains a shared topology cache across all of them. During a cutover, a client might also hold cached metadata or open connections referencing Broker 2 from the old cluster while the new cluster's Broker 2 is coming into view. Those two things can't share an ID.

To understand the full picture, look at what the proxy has always done. From day one, Kroxylicious has rewritten broker addresses in `MetadataResponse` frames — how else would a client connect to the proxy instead of the real broker? But the insight routing gave us was realising that we are dealing with two distinct pools of broker IDs:

1. The **downstream ID space** facing the client.
2. The **upstream ID space** facing the physical cluster.

In the pre-routing world, the proxy ran a simple identity mapping between them: Broker 2 upstream was presented as Broker 2 downstream; only the advertised socket address changed.

Routing breaks that simplicity by introducing **multiple upstream ID pools**. That would be trivial if those pools were provably disjoint — if Cluster A only ever used IDs `0..99` and Cluster B used `100..199`. But in the real world, almost every Kafka cluster starts numbering its brokers from 0 or 1.

To keep the runtime's shared topology cache unambiguous and to prevent collisions across a cutover, we have to collapse multiple upstream ID pools into a single downstream space:

```
                                                    ◄──(cluster A IDs)──► [ broker1.cluster-a, broker2.cluster-a, ... ]
[ Client ] ◄──(downstream IDs)──► [ Router ]
                                                    ◄──(cluster B IDs)──► [ broker1.cluster-b, broker2.cluster-b, ... ]
```

The proxy solves this with a stateless and deterministic mapping function applied at each step in the routing DAG — technically speaking, a bijection. No database lookup, no distributed coordinator — just integer arithmetic:

`downstreamId = (upstreamId * numRoutes) + routeIndex`

If Cluster A is route index 0 and Cluster B is route index 1 across two routes:
- Broker 2 on Cluster A becomes virtual Node ID `(2 * 2) + 0` = **4**
- Broker 2 on Cluster B becomes virtual Node ID `(2 * 2) + 1` = **5**

Requests flowing upstream have their node IDs translated from downstream to upstream; responses flowing downstream have them translated back. The mapping is strictly one-to-one in both directions, so every downstream ID resolves to exactly one physical broker and route with zero ambiguity.

Unusually for the routing capabilities in this series, this isn't logic the router author has to build—the Kroxylicious runtime maintains the mapping for you at every hop.

Because the rule is purely local to each router, routers compose cleanly without coordinating with each other. A router doesn't need to know what the rest of the graph looks like or whether an upstream target is a physical cluster or another router in the DAG. The runtime handles the integer translation transparently on the wire, leaving custom routers to work with clean `VirtualNode` handles and focus solely on routing decisions.

## Proxies aren't magic

Layer 7 protocol inspection gives you a lot of leverage. What it doesn't give you is the ability to reach inside a Kafka broker and move its internal state somewhere else. The proxy can route frames to a different cluster. It cannot conjure the state those frames depend on.

### When you flip the target, the state doesn't follow

If the routing target changes while a client is active:

- **Transactional producers:** Kafka treats the Transaction Coordinator as an internal role within the cluster. Transactions are therefore scoped to a single cluster by definition — there is no extension point or API through which an external coordinator could be plugged in. A transaction that starts on cluster A cannot be committed on cluster B; if a routing cutover happens mid-transaction, the subsequent `EndTxnRequest` arrives at the new target and gets back `INVALID_TXN_STATE` or `UNKNOWN_PRODUCER_ID`. That abort needs to be handled cleanly and the transactional loop restarted — the same failure mode as a plain broker restart, which well-written transactional producers already handle. A proxy restart itself is safe: the proxy never invents a PID in the single-cluster case, so the KIP-360 fencing fields the client sends on reconnect are the broker's own real values. But if the cluster itself changes — through a failover or routing reconfiguration — the PID the client holds is meaningless to the new cluster. Not fenced; simply unknown. The producer reconnects as a stranger.

- **Consumer groups:** Offset state lives in `__consumer_offsets` on the physical cluster. The secondary cluster's Group Coordinator has no knowledge of what the primary's consumers have committed. Failing over without a replication pipeline that includes offsets means consumers either re-read data they've already processed, or skip ahead and lose it. Neither is silent.

- **Idempotent producers:** Deduplication state lives in the broker. For each partition, the leader remembers the recent sequence numbers it has accepted from each producer (PID and epoch), and that's how it recognises a retried batch and discards it. Producer IDs are handed out by a specific cluster, so when the route changes that history stays behind. The new cluster has never heard of the client's PID: at best the producer is told to start over, and at worst a batch that was in flight across the cutover (already committed on the old cluster) is accepted a second time, because nothing on the new cluster can tell it's a retry. The proxy has no way to inject that state into the new cluster. Idempotence holds within each cluster, but not across the switch: a cutover is a boundary the guarantee doesn't cross. If you depend on it, treat the cutover as a known risk, and either quiesce producers first or make sure downstream consumers can tolerate the odd duplicate. If that isn't good enough, extreme measures exist: a filter could track what it has forwarded and reject re-submitted batches itself. That behaviour is specific to your deployment and would require a custom filter. You know your business better than we do, but it's not a filter we'd expect to ship as a project.

### Cutovers are an explicit decision, not a proxy heuristic

Because the proxy can't silently catch up coordinator state, automated failover *inside the proxy* is a deliberate non-goal.

A brief network hiccup and a genuine primary failure look identical from inside the proxy. The cost of getting that call wrong — dropping in-flight transactions, replaying messages, committing offsets against the wrong cluster — isn't the proxy's to bear. That judgement belongs to a human operator or an orchestration playbook that can actually assess cluster health and replication lag.

Kroxylicious gives you the mechanism to flip the routing target without restarting anything. When to pull that trigger is your call.

### Offset continuity requires out-of-band replication

The proxy routes frames; it doesn't replicate log data. If consumers need to pick up where they left off on the secondary cluster, offsets have to line up — which means your replication pipeline ([KIP-1279](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1279%3A+Cluster+Mirroring) or equivalent) needs to be in place and caught up *before* you flip the switch, not after. Flipping the switch is not a substitute for having done that work.

### Layer 7 can only do so much

Every failure mode above shares the same root: the proxy routed a frame to a new cluster, and something on that cluster had no memory of the client. That isn't a proxy bug. It's the definition of where connection switching ends. Post 1 framed the four patterns around a single axis: how deep into the Kafka protocol the router has to reach. Connection switching is the shallow end — it makes one decision, which door to open, and then steps back. The session that follows belongs to the broker.

The patterns deeper on that axis — topic weaving, partition weaving — require the proxy to maintain protocol-level continuity across clusters: intercepting coordinator requests, translating partition spaces, bridging producer identity across backends. That's a different contract. Not a harder version of connection switching; a different pattern, because the axis moved.

## Egress, ingress, or does it matter?

Post 1 promised we'd call out where each pattern lands on the egress/ingress axis. From a protocol standpoint connection switching is neutral — the mechanics work either side of the wire. In practice, your use case has a strong opinion about placement.

When talking about DR failover it's obvious once you say it out loud. If the proxy lives in the broker domain — in front of the brokers, a reverse proxy — and the primary site goes down, so does the proxy. Your switch just went boom along with the primary site... The secondary site's ingress proxy was never in the traffic path to begin with; you can't flip a routing target on a proxy your clients weren't talking to. You'd still need to redirect clients to a different address, which is exactly the coordination problem connection switching was supposed to eliminate.

Thus for DR, the proxy needs to sit on the client side of the link as an egress deployment. The proxy isn't collocated with what failed. It's still in the traffic path. You can flip the routing target, and clients never notice.

Connection switching also sits quite happily on the ingress side of the fence. If your goal is to give every team in the organisation a single `kafka.corp.internal:9092` and route their connections to the right tenant cluster behind the scenes, the proxy will most likely sit in front of the brokers — the platform team controls that domain and the stable endpoint is theirs to publish. You could run tenant dispatch egress-side, but now you're managing a fleet of client-side proxies, one per team or workload, and keeping them all pointed at the same routing config. That's a lot of instances to babysit for a problem the platform team already owns.

So what happens when you need to perform a failover of a multi-tenant system? You put a proxy at both ends of the link — egress on the client side, ingress on the broker side. What makes this work cleanly is that each proxy is completely indifferent to what sits behind it: it dials what it's told, speaks Kafka, and has no idea whether the thing on the other end is a broker or another Kroxylicious instance. There's no shared state between them, no coordination protocol, no handshake. That's the pay-off from being a native layer 7 proxy.

Connection switching keeps the operational promise simple: platform teams can change the physical backend without the application teams ever knowing it happened. That's not a small thing.

The next post moves from one-to-one connection switching to fanning out traffic and assembling secondary streams on the fly: **Stream Branching**.

[^1]: There is always some bit of infra that fails to honour the TTL properly or doesn't understand a CNAME or PTR record.
