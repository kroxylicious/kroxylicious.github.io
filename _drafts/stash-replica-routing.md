# Stash: replica routing pattern

Removed from `routing-post1.md` — to be picked up in post 2 (cluster aliasing) as an intra-cluster optimisation.

## Why it's not a peer pattern

The other three patterns (cluster aliasing, union clusters, virtual topics) all answer "which cluster/topic does this request go to". Replica routing answers a different question: "given we've already decided which cluster, which broker within it serves this fetch". It's a different level of abstraction, and it only meaningfully applies to `Fetch` requests — produce requires the leader, and most admin operations that are partition-aware could use it but it's not the primary motivation.

## The pattern

- Client is connected to a VKC backed by, say, the DE cluster
- Client sends a `Fetch` for a partition whose leader is broker 1 in `eu-west-1c`
- The proxy is sitting in `eu-west-1a`, where broker 3 holds a valid in-sync replica of that partition
- Rather than forwarding down the existing pipe to broker 1, the proxy routes the request down a separate connection to broker 3
- Broker 1 never sees the request. The client never knows there was a choice.

The key implementation detail: the proxy doesn't rewrite the request and send it to a different address on the same connection. It has a separate backend connection to broker 3 and routes the `Fetch` down that pipe instead. The request itself is unchanged — what changes is which pipe it travels down.

## Why this needs Layer 7

A Layer 4 proxy sees "connection to broker 1" and can only forward or drop. A Layer 7 proxy reads the `Fetch` request, understands which partition is being requested, knows the replica set and where each replica sits, and can choose which backend connection to use. The routing decision happens at the Kafka protocol level, not the TCP level.

## Relationship to Kafka's built-in rack awareness

This is a complement to rack awareness, not a replacement. `client.rack` + follower fetching works — when clients set it, and set it correctly. Replica routing extends the same idea: the proxy knows its own position in the topology and can apply locality policy centrally, covering clients that haven't configured rack awareness without requiring them to change anything.

## Naming considered

- **Topology-aware routing** — too tied to the implementation word "topology", was the original name
- **Locality routing** — too narrow, implies proximity is the only policy
- **Broker aliasing** — implies a static mapping, but the choice is dynamic
- **Replica routing** — landed here: names the thing being chosen between (replicas), leaves the policy open (proximity, lag, load, cost), intra-cluster by definition

## Other policies beyond proximity

- Replica lag — prefer the most caught-up replica
- Load — prefer the least busy broker
- Cost — prefer replicas on cheaper storage tiers

None of these are proximity, which is why the name shouldn't bake in "locality".

## Failure mode

Proxy placement. A client in `us-east-1a` hitting a proxy in `us-east-1b` that then routes to a broker in `us-east-1a` adds a cross-AZ hop instead of eliminating one. The proxy fleet has to be co-located with clients for locality savings to materialise.

---

# Stash: PID section from post 2

Removed from `routing-post2.md` — the full treatment belongs in the stream branching or topic weaving post where PIDs across multiple clusters actually bite. Connection switching stays in the single-cluster safe zone so the detail isn't earned here.

### Idempotent producers and the PID problem

Kafka producers use idempotent delivery by default. The broker deduplicates retried writes so that a message is committed exactly once even if the network drops the acknowledgement and the producer retries. The mechanism relies on a Producer ID (`PID`) that the broker assigns on initialisation, combined with a per-partition sequence number on every batch. If the broker sees a batch it's already committed — same PID, same sequence — it silently discards the duplicate. The client never needs to know.

When you first look at PID management through the proxy, it looks like a problem we already solved. The previous section introduced a bijection for node IDs — a deterministic, stateless mapping between downstream IDs and upstream IDs at each router. PID translation looks like the same pattern, and the surface similarities are convincing: both are integers, both are cluster-scoped, both are assigned by the cluster rather than chosen by the client, and both are opaque values the client simply carries and passes through. So the proxy can just maintain a downstream-to-upstream mapping for both, right? This is the obvious answer. The seams show up quickly, but each one looks stitchable — until you're looking at a patchwork quilt and wondering why it keeps unravelling. The reason is that despite identical protocol syntax, node IDs and producer IDs have completely different semantics within the protocol. A node ID is **spatial** — a label, a coordinate. A PID is **temporal** — not just a label but a claim of active identity. In other words: we can mathematically fake a Node ID because it's just an address. We have to statefully track a Producer ID because it's a weaponised identity claim.

**Node ID translation is transport-scoped.** A `MetadataResponse` tells you where brokers are. The proxy can tell as many lies as it likes here — the broker never sees them, let alone tries to call them out. And the proxy can be forgetful — stateless, even: if it discards its mapping and rebuilds it from the next `MetadataResponse`, it just tells the same lies again. Nothing notices, nothing breaks.

**PID allocation is negotiation-scoped.** Since Kafka 3.0, producers run in idempotent mode by default — you don't have to opt in, it just happens. To support that, the producer calls `InitProducerIdRequest` to ask the broker to allocate it an identity: a (PID, epoch) pair. The broker tracks that identity and uses it to deduplicate retried batches within that session. It will also forcibly evict any connection that presents the same PID with a lower epoch — that is the fencing mechanism, preventing two connections from simultaneously claiming the same identity. If you need that identity to survive across sessions — so a restarted producer can pick up where it left off rather than starting fresh — that is what `transactional.id` is for. A second `InitProducerIdRequest` carrying the same `transactional.id` is treated as a hostile takeover, deliberately: fencing is how Kafka ensures only one producer instance is ever active for a given transactional identity.

Both node IDs and PIDs are cluster-scoped — issued by a specific cluster, honoured within it, meaningless outside it. But the node ID relationship is stateless: if the proxy loses its mapping, it recovers via discovery and rederivation. A PID is unrecoverable. What was negotiated is gone.

All of that is a long way of saying: the proxy cannot manage PIDs globally, and the Routing API makes no attempt to. There is no built-in abstraction that handles this for you — it is left to the team implementing the router to understand what their routing topology implies for producer identity. That is not as bleak as it sounds. There are shapes that work cleanly. If your problem fits one of them, go hard or go home.

**Single physical cluster.** When all routes lead to the same physical cluster, there is nothing to solve. This is just standard Kafka protocol semantics — the proxy is a transparent conduit for a PID relationship that exists entirely between the client and the cluster. No mapping, no invention, no state to lose. Two things to keep in mind: routing decisions must be deterministic at the cluster level (a given producer must always land on the same physical cluster), and if the cluster changes — whether through a failover or a routing reconfiguration — the PID means nothing to the new cluster. Not fenced — a brand new client.

**Multiple active clusters.** This is where connection switching ends. The full treatment — what can be made to work, what can't, and at what cost — is in the post on topic weaving. But the boundary is worth drawing clearly here before we get there: see *Layer 7 can only do so much* below.

**Duplication routing (traffic shadowing).** One pattern that stays cleanly within the connection switching boundary: the shadow write to the secondary cluster is entirely router-invented — the client does not know Cluster B exists, and nothing downstream will ever attempt to resume or share that identity. The router negotiates its own PID with the shadow cluster and owns it from start to finish. What makes this safe is precisely the client's ignorance: because the shadow identity is invisible to the client, nothing can collide with it. There is one edge case worth naming: the shadow cluster has no knowledge of the primary's deduplication history. Writes the primary would have fenced as duplicates may be accepted on the shadow side, particularly after a proxy restart, when the negotiated PID is lost and a fresh one is issued to the shadow cluster. This is a dual-write pattern — do not use it where total accuracy is required. Shadow data is for observability. There will be other safe patterns depending on your topology — the constraint is client visibility, not the number of physical clusters involved.
