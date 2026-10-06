---
layout: post
title: "Cluster Aliasing: Identity without commitment"
date: 2026-09-11 15:00:00 +1200
author: "Sam Barker"
author_url: "https://github.com/sambarker"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "routing" ]
---

[Post 1]({link) introduced the Routing API and the fundamental shift it brings: a Virtual Kafka Cluster (VKC) is no longer a fixed pipe wired to a single physical cluster on boot. It’s a stable identity. What actually lives behind it is now the proxy's problem, not the client's.

We called the first pattern **Cluster Aliasing**.

Cluster aliasing makes the smallest possible change to Kafka protocol semantics. A connection to a VKC is still a connection to exactly one physical cluster — no fan-out, no merging, no stitching. The broker on the other end behaves like any Kafka broker, because it is one. What the proxy adds is a single degree of freedom: *which* cluster. Think of it in DNS terms: we transform a hardwired A record into a CNAME. The client has a stable name; what it resolves to is now the proxy's problem, not the client's.

## What you can do with it (and the dream it sets up)

### The single front door: Tenant & workload dispatch

Remember that 2am nightmare from post 1? The sales team launches an unannounced viral promotion right as end-of-month financial batch analytics fire up on the same shared cluster.

In the old world, separating those workloads meant a multi-week coordination exercise: provision new hardware, issue new bootstrap URLs, cajole twenty application teams into updating their config repositories, and schedule rolling restarts.

With cluster aliasing, everyone points at `kafka.corp.internal:9092`. When a client connects, the router inspects the authentication context established during handshake—who is knocking on the door?—and dispatches the connection to the appropriate physical cluster behind the scenes:

- High-throughput production services get routed to dedicated, high-IOPS NVMe brokers.
- Heavy batch analytics jobs get dispatched to high-capacity bulk storage clusters.
- General application traffic stays on the shared tier.

Now, let's be honest about the boundaries: migrating a producer pumping ephemeral clickstream data to a new cluster is trivial with aliasing—the platform team updates the route, and the producer begins writing to the new cluster with zero config changes and zero downtime. But what about the downstream analytics consumers that need to process that data? If they need continuous historical context, or if data was split across clusters mid-stream, the downstream consumer story is much more complicated. The proxy solves the connection and routing problem, but physical log replication and consumer offset synchronisation remain out-of-band challenges (more on that reality later). Still, for producers emitting fresh streams or teams operating in clean, discrete domains, cluster aliasing eliminates the connection coordination nightmare entirely.

### Client-change-free cluster migrations and DR failover

Let’s not pretend this is "seamless"—switching a distributed state machine like Kafka between physical backends always carries operational friction. But traditionally, both planned migrations (e.g. major version bumps, moving to KRaft, cloud region shifts) and unplanned Disaster Recovery (DR) failovers share an expensive logistical bottleneck: changing client endpoints.

In a conventional setup, redirecting traffic to a secondary cluster or a freshly provisioned "Green" environment means:
- Coordinating with dozens of independent application teams.
- Updating DNS records (with all the painful quirks as DNS propagates, seemingly at random[^1]) or editing hundreds of configuration maps.
- Bouncing client fleets across an agreed maintenance window—or watching an incident drag out while waiting for client restarts.

Cluster aliasing doesn't solve the hard data replication or consumer offset reconciliation problem, but it **completely eliminates the client-side migration cost**. The bootstrap configuration remains stable (`kafka.corp.internal:9092`).

When executing a planned migration or a DR failover:

1. **The data plane is handled out-of-band:** Topics and offsets are synced beforehand via active replication (MirrorMaker 2, KIP-1279 cluster mirroring), or recovered from storage volume snapshots.
2. **The connection cutover is a control-plane flip:** The proxy updates its route target to the secondary cluster—either globally or tenant-by-tenant.
3. **Rollback is instant:** If the secondary cluster misbehaves under live load, you can revert the routing target in seconds rather than triggering another round of client config rollbacks.

Whether you're doing a planned blue/green transition or invoking DR in an emergency, cluster aliasing transforms a massive cross-team coordination exercise into an internal platform switch.

[^1]: There is always some bit of infra that fails to honour the TTL properly or doesn't understand a CNAME or PTR record.

### Production shadowing without the compliance conversation

You're chasing an elusive bug that only manifests in the sixth hour of a high-volume run. Nobody can figure out which specific record payload triggers it. What you really want is to attach a debugger to the live stream in staging—except this production topic is stuffed full of Personally Identifiable Information (PII), and your compliance team has very reasonable objections.

Because routing stages compose cleanly into a pipeline with standard filters, a duplicating router can shadow live traffic to a staging cluster alias while passing it through a redaction filter on the way. The PII is transformed into gibberish before the bytes ever touch staging disks.

The client never knows. You get the real stream volume, the real cadence, the real record shapes—just not the real customer names.

### The cloud bill from hell: Replica routing

If you run Kafka in the cloud across multiple Availability Zones, you've probably had this exact conversation with your finance team. You opened the monthly AWS bill, choked on the 5-figure line item for cross-AZ data transfer, and dutifully turned on Kafka's built-in follower fetching (`client.rack`).

And it worked! The bill plummeted. You closed the Jira ticket, posted a triumphant graph in `#infra-cost-savings`, and moved on.

Then, six months later, the finance team knocks on your door again. The cross-AZ tax has silently crept right back up.

Why? Because relying on every client in the company to configure rack awareness is an unwinnable game of whack-a-mole:
- Someone copy-pastes a Helm chart that hardcodes `client.rack=eu-west-1a` into a pod deployed in `eu-west-1b`.
- A data science team spins up a fleet of Python consumers using a library where nobody realised follower fetching requires a specific flag.
- A new microservice goes live with the defaults, happily pulling multi-gigabyte streams across the AZ boundary from whatever partition leader happens to be awake.

Kafka's native rack awareness is great, but client compliance is leaky. Centralized problems need centralized controls.

And this isn't just about inspecting frames at Layer 7. If all you have is a filter pipeline on a static 1:1 pipe, understanding that a `Fetch` belongs in `eu-west-1a` doesn't help you—the pipe is already nailed to broker 1 in `eu-west-1c`. The breakthrough comes from the Routing API making the backend connection dynamic.

When a proxy instance deployed in `eu-west-1a` intercepts a `Fetch` request arriving on a virtual connection to the leader over in `eu-west-1c`, it inspects the partition's in-sync replica (ISR) set. If broker 3 is sitting right next door in `eu-west-1a` with a caught-up replica, the proxy doesn't rewrite the frame—it dynamically dispatches that individual request down a separate backend pipe to broker 3:

```
[ Consumer (AZ-a) ] ──Fetch──► [ Kroxylicious (AZ-a) ] ────► [ Broker 3 (AZ-a, Replica) ]
                                       │
                                (Skips AZ tax)
                                       ▼
                              [ Broker 1 (AZ-c, Leader) ]
```

The application didn't configure `client.rack`. The request payload is completely untouched. It simply travelled down a different pipe. Broker 1 never sees the read, and the cross-AZ request never happened so never reaches the invoice.

Rack-local fetching is just leveraging the existing Kafka protocol. In theory, dynamic per-request dispatch opens up other intriguing possibilities to explore in your custom Bugatti router:
- **Replica lag awareness:** Steering reads strictly to the most caught-up followers to avoid trailing-edge staleness.
- **Broker load shedding:** Diverting fetch traffic away from CPU- or IO-bound leaders to give them headroom for critical writes.
- **Tiered storage offloading:** Routing historical backfills to brokers backed by cheap object storage while keeping hot tail-reads on fast NVMe.

Whether those speculative policies prove practical in production remains to be seen—they require telemetry the proxy might not easily have—but proximity routing alone solves a very real, very expensive problem right now.

There is, of course, a hard constraint: **proxy placement**. If a client in `eu-west-1a` talks to a proxy sitting in `eu-west-1b`, which then forwards to a broker in `eu-west-1a`, you’ve just invented a two-hop cross-AZ detour. For replica routing to pay off, your proxy fleet must be co-located with the clients it fronts.

---

## How the proxy makes it work

Making one physical cluster look like a different one at Layer 7 requires more than TCP forwarding. There are three places where the proxy has to do actual work.

### Broker IDs are integers, not names

Kafka wire frames identify brokers by integer `NodeId` — not hostnames. A `MetadataResponse` carries a broker list (node ID, host, port, rack) and maps each partition to its leader and replicas by node ID. The client resolves those node IDs to connections itself. That's fine when there's one physical cluster. When you have multiple physical clusters behind a VKC, you immediately run into a collision problem: broker 2 on cluster A and broker 2 on cluster B are completely different machines, but the proxy can only send one broker list to the client — it cannot have two different entries for node ID 2.

The proxy solves this with a deterministic, stateless mapping applied at every node in the routing DAG. Each router speaks two consistent ID languages: a downstream ID space shared with whatever is below it, and an upstream ID space shared with whatever is above it. Requests flow upstream with IDs translated from downstream to upstream; responses flow downstream with IDs translated from upstream to downstream. The router reads and writes both spaces fluently in both directions. A node can have multiple upstream ID spaces — one per route — all of which must be collapsed into a single, unambiguous downstream space. The mapping is strictly one-to-one in both directions — a bijection, if you want the precise term — so every downstream ID resolves to exactly one upstream ID and route, with no collisions and no ambiguity. No database lookup, no distributed state, just arithmetic: the downstream node ID is the upstream node ID multiplied by the number of routes, plus the route index. For a leaf router, the upstream ID space happens to be the physical IDs coming off the wire from a real broker — but the mapping rule is the same regardless. In theory the upstream could itself be another Kroxylicious instance — the mapping rule is indifferent to what sits above the leaf. The only realistic reason you'd pay that latency tax is Conway's Law: separate teams owning separate proxy tiers with their own trust boundaries and operational responsibilities. The proxy runtime handles the translation at each hop transparently; routers work with opaque `VirtualNode` handles scoped to their own ID space and never need to care about the underlying integer arithmetic.

```
                                                    ◄──(cluster A IDs)──► [ broker1.cluster-a, broker2.cluster-a, ... ]
[ Client ] ◄──(downstream IDs)──► [ Router ]
                                                    ◄──(cluster B IDs)──► [ broker1.cluster-b, broker2.cluster-b, ... ]
```

### Topology discovery happens in-band

The proxy has no independent view of the Kafka topology. It doesn't poll brokers in the background, run health checks, or hold idle connections open just to keep its metadata warm. Clients and routers drive connections; the proxy learns what it needs to know from the traffic that flows through it.

Topology state is cached per-router and shared across all connections using that router — so a second connection to the same virtual cluster benefits from what the first one already discovered. The cache uses additive semantics: entries are added as they are learned, never removed. That matters for safety. A low-privilege connection might get a filtered `MetadataResponse` covering only the topics it can see; an additive cache means it can only *contribute* knowledge, never silently evict entries that a higher-privilege connection established. And cache poisoning doesn't translate into an access control bypass anyway — the cache only influences routing decisions. Brokers enforce ACLs on every request regardless; a misdirected frame gets an error, not someone else's data.

When a client sends a request to a route whose topology the proxy doesn't know yet — on first connection, or after a stale entry — it discovers it on demand. The proxy synthesises a `MetadataRequest` on the active client channel, uses the response to populate its topology cache, and then forwards the original request as normal. Crucially, discovery inherits the client's authenticated context, so there's no privileged out-of-band management channel to secure or misconfigure.

### Idempotent producers and the PID problem

Kafka producers use idempotent delivery by default. The broker deduplicates retried writes so that a message is committed exactly once even if the network drops the acknowledgement and the producer retries. The mechanism relies on a Producer ID (`PID`) that the broker assigns on initialisation, combined with a per-partition sequence number on every batch. If the broker sees a batch it's already committed — same PID, same sequence — it silently discards the duplicate. The client never needs to know.

When you first look at PID management through the proxy, it looks like a problem we already solved. The previous section introduced a bijection for node IDs — a deterministic, stateless mapping between downstream IDs and upstream IDs at each router. PID translation looks like the same pattern, and the surface similarities are convincing: both are integers, both are cluster-scoped, both are assigned by the cluster rather than chosen by the client, and both are opaque values the client simply carries and passes through. So the proxy can just maintain a downstream-to-upstream mapping for both, right? This is the obvious answer. The seams show up quickly, but each one looks stitchable — until you're looking at a patchwork quilt and wondering why it keeps unravelling. The reason is that despite identical protocol syntax, node IDs and producer IDs have completely different semantics within the protocol. A node ID is **spatial** — a label, a coordinate. A PID is **temporal** — not just a label but a claim of active identity. In other words: we can mathematically fake a Node ID because it's just an address. We have to statefully track a Producer ID because it's a weaponised identity claim.

**Node ID translation is transport-scoped.** A `MetadataResponse` tells you where brokers are. The proxy can tell as many lies as it likes here — the broker never sees them, let alone tries to call them out. And the proxy can be forgetful — stateless, even: if it discards its mapping and rebuilds it from the next `MetadataResponse`, it just tells the same lies again. Nothing notices, nothing breaks.

**PID allocation is negotiation-scoped.** Since Kafka 3.0, producers run in idempotent mode by default — you don't have to opt in, it just happens. To support that, the producer calls `InitProducerIdRequest` to ask the broker to allocate it an identity: a (PID, epoch) pair. The broker tracks that identity and uses it to deduplicate retried batches within that session. It will also forcibly evict any connection that presents the same PID with a lower epoch — that is the fencing mechanism, preventing two connections from simultaneously claiming the same identity. If you need that identity to survive across sessions — so a restarted producer can pick up where it left off rather than starting fresh — that is what `transactional.id` is for. A second `InitProducerIdRequest` carrying the same `transactional.id` is treated as a hostile takeover, deliberately: fencing is how Kafka ensures only one producer instance is ever active for a given transactional identity.

Both node IDs and PIDs are cluster-scoped — issued by a specific cluster, honoured within it, meaningless outside it. But the node ID relationship is stateless: if the proxy loses its mapping, it recovers via discovery and rederivation. A PID is unrecoverable. What was negotiated is gone.

All of that is a long way of saying: the proxy cannot manage PIDs globally, and the Routing API makes no attempt to. There is no built-in abstraction that handles this for you — it is left to the team implementing the router to understand what their routing topology implies for producer identity. That is not as bleak as it sounds. There are shapes that work cleanly. If your problem fits one of them, go hard or go home.

**Single physical cluster.** When all routes lead to the same physical cluster, there is nothing to solve. This is just standard Kafka protocol semantics — the proxy is a transparent conduit for a PID relationship that exists entirely between the client and the cluster. No mapping, no invention, no state to lose. Two things to keep in mind: routing decisions must be deterministic at the cluster level (a given producer must always land on the same physical cluster), and if the cluster changes — whether through a failover or a routing reconfiguration — the PID means nothing to the new cluster. Not fenced — a brand new client.

**Duplication routing (traffic shadowing).** The shadow write to the secondary cluster is entirely router-invented — the client does not know Cluster B exists, and nothing downstream will ever attempt to resume or share that identity. The router negotiates its own PID with the shadow cluster and owns it from start to finish. What makes this safe is precisely the client's ignorance: because the shadow identity is invisible to the client, nothing can collide with it. There is one edge case worth naming: the shadow cluster has no knowledge of the primary's deduplication history. Writes the primary would have fenced as duplicates may be accepted on the shadow side, particularly after a proxy restart, when the negotiated PID is lost and a fresh one is issued to the shadow cluster. This is a dual-write pattern — do not use it where total accuracy is required. Shadow data is for observability.

**Multiple active clusters.** This is where the whole quilt unravels — we will pick it up in the union clusters post.

---

## Proxies aren't magic

Layer 7 protocol inspection gives you a lot of leverage. What it doesn't give you is the ability to reach inside a Kafka broker and move its internal state somewhere else. The proxy can route frames to a different cluster. It cannot conjure the state those frames depend on.

### When you flip the target, the state doesn't follow

If the routing target changes while a client is active:

- **Transactional producers:** Kafka treats the Transaction Coordinator as an internal role within the cluster. Transactions are therefore scoped to a single cluster by definition — there is no extension point or API through which an external coordinator could be plugged in. A transaction that starts on cluster A cannot be committed on cluster B; if a routing cutover happens mid-transaction, the subsequent `EndTxnRequest` arrives at the new target and gets back `INVALID_TXN_STATE` or `UNKNOWN_PRODUCER_ID`. That abort needs to be handled cleanly and the transactional loop restarted — the same failure mode as a plain broker restart, which well-written transactional producers already handle. A proxy restart itself is safe: the proxy never invents a PID in the single-cluster case, so the KIP-360 fencing fields the client sends on reconnect are the broker's own real values.

- **Consumer groups:** Offset state lives in `__consumer_offsets` on the physical cluster. The secondary cluster's Group Coordinator has no knowledge of what the primary's consumers have committed. Failing over without a replication pipeline that includes offsets means consumers either re-read data they've already processed, or skip ahead and lose it. Neither is silent.

### Layer 7 can only do so much

Aliasing works because there is a single physical cluster backing it. The proxy isn't maintaining an illusion — it's directing traffic to something real, and real Kafka semantics apply throughout. The moment a router exposes brokers from multiple physical clusters as a unified address space, it has to ensure those semantics stay valid. For some operations that's fine — routing a `Fetch` to a local replica is cheap and safe. But for anything that touches producer identity or coordination — PIDs, epochs, transaction coordinators, consumer group coordinators — the router has taken on the obligation of upholding guarantees the protocol no longer provides on its behalf.

The most immediate consequence is session affinity. The router must maintain a session-scoped mapping between the client's virtual PID and the real (PID, epoch) on each backend cluster. That mapping lives in the proxy instance that negotiated it. If the load balancer routes a reconnecting client to a different proxy replica, the mapping is gone — the router re-negotiates, the epoch bumps, and the backend fences the producer. The proxy can't prevent this. Only sticky L4 routing can.

Friends don't let friends cross that line without knowing exactly what they've signed up for.

### Cutovers are an explicit decision, not a proxy heuristic

Because the proxy can't silently catch up coordinator state, automated failover *inside the proxy* is a deliberate non-goal.

A brief network hiccup and a genuine primary failure look identical from inside the proxy. The cost of getting that call wrong — dropping in-flight transactions, replaying messages, committing offsets against the wrong cluster — isn't the proxy's to bear. That judgement belongs to a human operator or an orchestration playbook that can actually assess cluster health and replication lag.

Kroxylicious gives you the mechanism to flip the routing target without restarting anything. When to pull that trigger is your call.

### Offset continuity requires out-of-band replication

The proxy routes frames; it doesn't replicate log data. If consumers need to pick up where they left off on the secondary cluster, offsets have to line up — which means your replication pipeline ([KIP-1279](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1279%3A+Cluster+Mirroring) or equivalent) needs to be in place and caught up *before* you flip the switch, not after. Flipping the switch is not a substitute for having done that work.

---

Cluster aliasing keeps the operational promise simple: platform teams can change the physical backend without the application teams ever knowing it happened. That's not a small thing.

The next post moves from one-to-one aliasing to stitching multiple physical clusters into a single logical view: **Union Clusters**.
