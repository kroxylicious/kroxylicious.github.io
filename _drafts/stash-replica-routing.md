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
