---
layout: post
title: "Connection Switching: Identity without commitment"
date: 2026-09-11 15:00:00 +1200
author: "Sam Barker"
author_url: "https://github.com/sambarker"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "routing" ]
---

[Post 1]({% post_url 2026-10-12-these-are-not-the-brokers-you-are-connecting-to %}) introduced the Routing API and the fundamental shift it brings: a Virtual Kafka Cluster (VKC) is no longer a fixed pipe wired to a single physical cluster on boot. It's a stable identity. What actually lives behind it is now the proxy's problem, not the client's.

We called the first pattern **Connection Switching**.

Connection switching makes the smallest possible change to Kafka protocol semantics. A connection to a VKC is still a connection to exactly one physical cluster — no fan-out, no merging, no weaving. The broker on the other end behaves like any Kafka broker, because it is one. What the proxy adds is a single degree of freedom: *which* cluster. Think of it in DNS terms: we transform a hardwired A record into a CNAME. The client has a stable name; what it resolves to is now the proxy's problem, not the client's.

## What you can do with it (and the dream it sets up)

### The single front door: Tenant & workload dispatch

Workload collision is one of Kafka's classic growing pains. When operations eventually wants to separate workloads onto dedicated hardware — high-IOPS brokers for latency-sensitive services, bulk storage for batch analytics, a shared tier for everything else — the old world makes it a multi-week coordination exercise: provision new hardware, issue new bootstrap URLs, cajole twenty application teams into updating their config repositories, and schedule rolling restarts.

With connection switching, everyone bootstraps at `kafka.corp.internal:9092`. When a client connects, the router inspects the authentication context established during handshake—who is knocking on the door? — and dispatches the connection to the appropriate physical cluster behind the scenes:

- High-throughput production services get routed to dedicated, high-IOPS NVMe brokers.
- Heavy batch analytics jobs get dispatched to the spinning rust cluster.
- General application traffic stays on the shared tier.

Now, let's be honest about the boundaries: migrating a producer pumping ephemeral clickstream data to a new cluster is trivial with connection switching—the platform team updates the route, and the producer begins writing to the new cluster with zero config changes and zero downtime. But what about the downstream analytics consumers that need to process that data? If they need continuous historical context, or if data was split across clusters mid-stream, the downstream consumer story is much more complicated. The proxy solves the connection and routing problem, but physical log replication and consumer offset synchronisation remain out-of-band challenges (the migrations section below gets into what that actually requires). Still, for producers emitting fresh streams or teams operating in clean, discrete domains, connection switching eliminates the connection coordination nightmare entirely.

### Client-change-free cluster migrations and DR failover

Let’s not pretend this is "seamless"—switching a distributed state machine like Kafka between physical backends always carries operational friction. But traditionally, both planned migrations (e.g. major version bumps, moving to KRaft, cloud region shifts) and unplanned Disaster Recovery (DR) failovers share an expensive logistical bottleneck: changing client endpoints.

In a conventional setup, redirecting traffic to a secondary cluster or a freshly provisioned "Green" environment means:
- Coordinating with dozens of independent application teams.
- Updating DNS records (with all the painful quirks as DNS propagates, seemingly at random[^1]) or editing hundreds of configuration maps.
- Bouncing client fleets across an agreed maintenance window—or watching an incident drag out while waiting for client restarts.

Connection switching doesn't solve the hard data replication or consumer offset reconciliation problem, but it **completely eliminates the client-side migration cost**. The bootstrap configuration remains stable (`kafka.corp.internal:9092`).

When executing a planned migration or a DR failover:

1. **The data plane is handled out-of-band:** Topics and offsets are synced beforehand via active replication (MirrorMaker 2, KIP-1279 cluster mirroring, or your vendor's equivalent), or recovered from storage volume snapshots.
2. **The connection cutover is a control-plane flip:** The proxy updates its route target to the secondary cluster—either globally or tenant-by-tenant.
3. **Rollback is instant:** If the secondary cluster misbehaves under live load, you can revert the routing target in seconds rather than triggering another round of client config rollbacks.

Whether you're doing a planned blue/green transition or invoking DR in an emergency, connection switching takes client coordination off the critical path. The data still has to be in sync — that's on you — but at least the cutover itself isn't a multi-team event.

## How the proxy makes it work

Making one physical cluster look like a different one at Layer 7 requires more than TCP forwarding. There are three places where the proxy has to do actual work.

### When is 2 != 2?

When broker 2 on cluster A and broker 2 on cluster B are both behind the same VKC.

Kafka identifies brokers by an integer called `NodeId` — not hostnames. A `MetadataResponse` carries a broker list (node ID, host, port, rack) and maps each partition to its leader and replicas by node ID. The client resolves those node IDs to connections itself. That's fine when there's one physical cluster. When you have multiple physical clusters behind a VKC, you immediately run into a collision problem: broker 2 on cluster A and broker 2 on cluster B are completely different machines, but the proxy can only send one broker list to the client — it cannot have two different entries for node ID 2.

The proxy solves this with a deterministic, stateless mapping applied at every node in the routing DAG. Each router speaks two consistent ID languages: a downstream ID space shared with whatever is below it, and an upstream ID space shared with whatever is above it. Requests flow upstream with IDs translated from downstream to upstream; responses flow downstream with IDs translated from upstream to downstream. The router reads and writes both spaces fluently in both directions. A node can have multiple upstream ID spaces — one per route — all of which must be collapsed into a single, unambiguous downstream space. The mapping is strictly one-to-one in both directions — a bijection, if you want the precise term — so every downstream ID resolves to exactly one upstream ID and route, with no collisions and no ambiguity. No database lookup, no distributed state, just arithmetic: the downstream node ID is the upstream node ID multiplied by the number of routes, plus the route index. For a leaf router, the upstream ID space happens to be the physical IDs coming off the wire from a real broker — but the mapping rule is the same regardless. In theory the upstream could itself be another Kroxylicious instance — the mapping rule is indifferent to what sits above the leaf. The only realistic reason you'd pay that latency tax is Conway's Law: separate teams owning separate proxy tiers with their own trust boundaries and operational responsibilities. The proxy runtime handles the translation at each hop transparently; routers work with opaque `VirtualNode` handles scoped to their own ID space and never need to care about the underlying integer arithmetic.

```
                                                    ◄──(cluster A IDs)──► [ broker1.cluster-a, broker2.cluster-a, ... ]
[ Client ] ◄──(downstream IDs)──► [ Router ]
                                                    ◄──(cluster B IDs)──► [ broker1.cluster-b, broker2.cluster-b, ... ]
```

A router could in principle choose which brokers it exposes to the client — but the moment you start hiding brokers, you own the consequences for partition leadership, replica placement, and fetch routing. That's a deep rabbit hole, and the current API doesn't give you a way in: the bijection and topology discovery are handled by the runtime, not the router.

### Topology discovery happens in-band

The proxy has no independent view of the Kafka topology. It doesn't poll brokers in the background, run health checks, or hold idle connections open just to keep its metadata warm. Clients and routers drive connections; the proxy learns what it needs to know from the traffic that flows through it.

Topology state is cached per-router and shared across all connections using that router — so a second connection to the same virtual cluster benefits from what the first one already discovered. The cache uses additive semantics: entries are added as they are learned, never removed. That matters for safety. A low-privilege connection might get a filtered `MetadataResponse` covering only the topics it can see; an additive cache means it can only *contribute* knowledge, never silently evict entries that a higher-privilege connection established. And cache poisoning doesn't translate into an access control bypass either — the cache only influences routing decisions. Brokers enforce ACLs on every request regardless; a misdirected frame gets an error, not someone else's data.

When a client sends a request to a route whose topology the proxy doesn't know yet — on first connection, or after a stale entry — it discovers it on demand. The proxy synthesises a `MetadataRequest` on the active client channel, uses the response to populate its topology cache, and then forwards the original request as normal. Crucially, discovery inherits the client's authenticated context, so there's no privileged out-of-band management channel to secure or misconfigure.

---

## Proxies aren't magic

Layer 7 protocol inspection gives you a lot of leverage. What it doesn't give you is the ability to reach inside a Kafka broker and move its internal state somewhere else. The proxy can route frames to a different cluster. It cannot conjure the state those frames depend on.

### When you flip the target, the state doesn't follow

If the routing target changes while a client is active:

- **Transactional producers:** Kafka treats the Transaction Coordinator as an internal role within the cluster. Transactions are therefore scoped to a single cluster by definition — there is no extension point or API through which an external coordinator could be plugged in. A transaction that starts on cluster A cannot be committed on cluster B; if a routing cutover happens mid-transaction, the subsequent `EndTxnRequest` arrives at the new target and gets back `INVALID_TXN_STATE` or `UNKNOWN_PRODUCER_ID`. That abort needs to be handled cleanly and the transactional loop restarted — the same failure mode as a plain broker restart, which well-written transactional producers already handle. A proxy restart itself is safe: the proxy never invents a PID in the single-cluster case, so the KIP-360 fencing fields the client sends on reconnect are the broker's own real values. But if the cluster itself changes — through a failover or routing reconfiguration — the PID the client holds is meaningless to the new cluster. Not fenced; simply unknown. The producer reconnects as a stranger.

- **Consumer groups:** Offset state lives in `__consumer_offsets` on the physical cluster. The secondary cluster's Group Coordinator has no knowledge of what the primary's consumers have committed. Failing over without a replication pipeline that includes offsets means consumers either re-read data they've already processed, or skip ahead and lose it. Neither is silent.

- **Idempotent producers:** Producer IDs are issued by a specific cluster and are meaningless to any other. Any time a route targets a new cluster — planned migration, DR failover, or routing reconfiguration — every active producer starts fresh. The new cluster has no deduplication history; retried batches that the old cluster would have silently discarded may be accepted and committed. For producers that care about exactly-once semantics, this is a consideration to plan for, not a surprise to discover in production.

### Layer 7 can only do so much

Connection switching works because there is a single physical cluster backing it. The proxy isn't maintaining an illusion — it's directing traffic to something real, and real Kafka semantics apply throughout. The moment a router exposes brokers from multiple physical clusters as a unified address space, it has to ensure those semantics stay valid. For some operations that's fine — routing a `Fetch` to a local replica is cheap and safe. But for anything that touches producer identity or coordination — PIDs, epochs, transaction coordinators, consumer group coordinators — the router has taken on the obligation of upholding guarantees the protocol no longer provides on its behalf.

The most immediate consequence is that producer identity becomes connection-scoped. The router must maintain a mapping between the client's virtual PID and the real (PID, epoch) on each backend cluster, and that mapping lives with the client connection that negotiated it. Kafka connections are long-lived, but they aren't forever: when one drops, the proxy tears down everything attached to it, mapping included. Reconnecting doesn't help — not even to the same proxy instance — the router re-negotiates, and whatever sequence or epoch continuity the client was relying on is gone. Nor is there only one mapping to lose. A client holds a connection per leader broker, possibly spread across proxy instances that know nothing of each other, so a single client PID can end up fronting several unrelated backend identities. Sticky L4 routing doesn't fix that; the state isn't anywhere a load balancer can point at.

Friends don't let friends cross that line without knowing exactly what they've signed up for.

### Cutovers are an explicit decision, not a proxy heuristic

Because the proxy can't silently catch up coordinator state, automated failover *inside the proxy* is a deliberate non-goal.

A brief network hiccup and a genuine primary failure look identical from inside the proxy. The cost of getting that call wrong — dropping in-flight transactions, replaying messages, committing offsets against the wrong cluster — isn't the proxy's to bear. That judgement belongs to a human operator or an orchestration playbook that can actually assess cluster health and replication lag.

Kroxylicious gives you the mechanism to flip the routing target without restarting anything. When to pull that trigger is your call.

### Offset continuity requires out-of-band replication

The proxy routes frames; it doesn't replicate log data. If consumers need to pick up where they left off on the secondary cluster, offsets have to line up — which means your replication pipeline ([KIP-1279](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1279%3A+Cluster+Mirroring) or equivalent) needs to be in place and caught up *before* you flip the switch, not after. Flipping the switch is not a substitute for having done that work.

---

## Egress, ingress, or does it matter?

Post 1 promised we'd call out where each pattern lands on the egress/ingress axis. From a protocol standpoint connection switching is neutral — the mechanics work either side of the wire. In practice, your use case has a strong opinion about placement.

When talking about DR failover it's obvious once you say it out loud. If the proxy lives in the broker domain — in front of the brokers, a reverse proxy — and the primary site goes down, so does the proxy. Your switch just went boom along with the primary site... The secondary site's ingress proxy was never in the traffic path to begin with; you can't flip a routing target on a proxy your clients weren't talking to. You'd still need to redirect clients to a different address, which is exactly the coordination problem connection switching was supposed to eliminate.

Thus for DR, the proxy needs to sit on the client side of the link as an egress deployment. The proxy isn't collocated with what failed. It's still in the traffic path. You can flip the routing target, and clients never notice.

Connection switching also sits quite happily on the ingress side of the fence. If your goal is to give every team in the organisation a single `kafka.corp.internal:9092` and route their connections to the right tenant cluster behind the scenes, the proxy will most likely sit in front of the brokers — the platform team controls that domain and the stable endpoint is theirs to publish. You could run tenant dispatch egress-side, but now you're managing a fleet of client-side proxies, one per team or workload, and keeping them all pointed at the same routing config. That's a lot of instances to babysit for a problem the platform team already owns.

So what happens when you need to perform a failover of a multi-tenant system? You put a proxy at both ends of the link — egress on the client side, ingress on the broker side. What makes this work cleanly is that each proxy is completely indifferent to what sits behind it: it dials what it's told, speaks Kafka, and has no idea whether the thing on the other end is a broker or another Kroxylicious instance. There's no shared state between them, no coordination protocol, no handshake. That's the pay-off from being a native layer 7 proxy.

---

Connection switching keeps the operational promise simple: platform teams can change the physical backend without the application teams ever knowing it happened. That's not a small thing.

The next post moves from one-to-one connection switching to fanning out traffic and assembling secondary streams on the fly: **Stream Branching**.

[^1]: There is always some bit of infra that fails to honour the TTL properly or doesn't understand a CNAME or PTR record.
