---
layout: post
title: "Stream Branching: Mind the gap"
date: 2026-10-26 15:00:00 +1200
author: "Sam Barker"
author_url: "https://github.com/sambarker"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "routing" ]
---

[Post 2](/TODO-post2-url) established the station network: the routing DAG is a network of stations, the client's stream is the express running down the mainline, and at each station the stationmaster can inspect passing trains. Stream branching is what the stationmaster does next. There are two flavours. In the *substitution* case, the train is quietly re-routed to a different platform — the original destination never sees it. In the *additive* case, the express continues to its primary destination while new trains depart down branch lines. The first is simple. The second is where the sharp edges are, and most of this post is about those edges.

## The simplest branch: Replica routing

If you run Kafka across multiple Availability Zones, you've probably already had this conversation with your finance team. You opened the monthly bill, choked on the cross-AZ data transfer line item, and dutifully turned on Kafka's built-in follower fetching (`client.rack`). The bill plummeted. You closed the Jira ticket, posted a triumphant graph in `#infra-cost-savings`, and moved on.

Then six months later finance knocks on your door again. The cross-AZ tax has silently crept right back up.

Why? Because relying on every client in the company to configure rack awareness is an unwinnable game of whack-a-mole:
- Someone copy-pastes a Helm chart that hardcodes `client.rack=eu-west-1a` into a pod deployed in `eu-west-1b`.
- A data science team spins up a fleet of Python consumers using a library where nobody realised follower fetching requires a specific flag.
- A new microservice goes live with the defaults, happily pulling multi-gigabyte streams across the AZ boundary from whatever partition leader happens to be awake.

Centralised problems need centralised controls. But there's a subtler obstacle. Even if a filter could see that a particular `FetchRequest` belongs in `eu-west-1a`, knowing that isn't enough — the pipe is already nailed to broker 1 in `eu-west-1c`. The filter has nowhere to send it. The Routing API allows you to fix this: the backend connection is no longer fixed at connection time, it can be chosen per request.

A `FetchRequest` payload just says "partition 3, from offset N". The broker ID is encoded by which connection the client sends the request on — that's the seam a custom router can exploit. When the `FetchRequest` arrives on the virtual broker 1 connection, the router inspects the partition's replica set, sees that broker 3 is in the same AZ and fully caught up, and tells the runtime to fulfil the request down a separate backend socket to broker 3 instead:

```
[ Consumer (AZ-a) ] ──Fetch──► [ Kroxylicious (AZ-a) ] ────► [ Broker 3 (AZ-a, Replica) ]
                                       │
                                (Skips AZ tax)
                                       ▼
                              [ Broker 1 (AZ-c, Leader) ]  ← never sees the request
```

The application didn't configure `client.rack`. The request payload is completely untouched. Broker 1 never receives the order, and the cross-AZ charge never reaches the invoice. What made that possible: the proxy is holding two backend sockets, one to the leader and one to the local replica, and choosing between them per request. To the client, that's still one broker on one cluster.

The same per-request dispatch mechanism opens up other possibilities beyond proximity — your custom Bugatti router from post 1 could consider:
- **Replica lag awareness:** Steering reads to the most caught-up follower to avoid trailing-edge staleness.
- **Broker load shedding:** Diverting fetch traffic away from CPU- or IO-bound leaders to give them headroom for critical writes.
- **Tiered storage offloading:** Routing historical backfills to brokers backed by cheap object storage while keeping hot tail-reads on fast NVMe.

Whether those prove practical in production remains to be seen — they require telemetry the router might not easily have — but proximity routing alone solves a very real, very expensive problem right now.

One constraint the dispatcher can't escape: **proxy placement**. If the proxy is in `eu-west-1b` and the consumer is in `eu-west-1a`, pulling from a broker in `eu-west-1a` still costs a cross-AZ hop to reach the dispatcher first. For replica routing to pay off, the proxy fleet must be co-located with the clients it fronts.

---

## The express doesn't wait

Stream branching has one rule, and the rest of this post follows from it:

> **The mainline is the source of truth. Branch lines are best effort.**

The express never waits at a junction for a branch-line train. The client produces a batch. The router sends it to the primary cluster and, at the same time, sends zero or more batches down branch lines to other topics, other clusters, or both. Those can be copies, redacted copies, samples, or new records derived from the payload. The client gets back the primary's `ProduceResponse` and nothing else. Branch writes never add latency to that acknowledgement, never turn a success into an error, and never turn an error into a success.

```
                                   ┌──(mainline)──► [ Primary cluster ]  ──ack──┐
[ Producer ] ──Produce──► [ Router ]                                            │
     ▲                             ├──(branch)────► [ Staging cluster ] (redacted, sampled)
     │                             └──(branch)────► [ audit-events topic ] (derived)
     └──────────────── ProduceResponse (primary's verdict only) ◄───────────────┘
```

The branch writes belong to the router, not the client. The client didn't send them and never sees their responses. The router opens its own connections to the branch targets, sends its own `ProduceRequest`s, and decides what to do when they fail.

This rule is a design choice, not a missing feature. The obvious alternative is to hold the acknowledgement until every branch has landed. That doesn't make the writes atomic. It just ties production to your least reliable cluster, as [Mind the gap](#mind-the-gap) explains.

## What it costs to stop at the station

The cheapest branch is a faithful copy: same records, same batches, sent on to a different place. The router can pass the record batch bytes through with only the header changed (more on which fields later). It never has to decompress anything.

Once the stationmaster needs to look *inside* the carriages, the cost goes up a lot. Redacting PII, deriving an audit record from the payload, or filtering individual records all mean decompressing the batch, deserialising records, transforming them, then re-serialising and recompressing. On a busy topic with `zstd` batches that's real CPU, and it happens inline on the proxy for every batch that takes the branch. Size your proxy fleet for the most expensive station on the line, not for the mainline.

Sampling sits somewhere in the middle. Dropping whole batches is close to free. Dropping individual records means rewriting batches. Which one you want depends on whether "10% of the traffic" means 10% of requests or 10% of records. For load testing it's usually the first, which is lucky.

Keep it stateless. Every station handles each batch on its own. Joins, windows, and aggregations over time need state that survives restarts, rebalances, and late data, and Kafka Streams and Kafka Connect exist to manage exactly that. A router that starts accumulating state across batches has become a badly built stream processor.

## Mind the gap

Here's what you're signing up for.

### There is no undo

A Kafka log only ever appends. When a batch lands on one cluster and fails on the other, nothing can take the successful write back. That leaves four outcomes for any batch:

| Primary | Branch  | What the client sees | What the branch ends up with |
|---------|---------|----------------------|------------------------------|
| ✅      | ✅      | Success              | A copy. The happy path.      |
| ✅      | ❌      | Success              | A hole                       |
| ❌      | ✅      | Error, so it retries | A copy now, and another one after the retry |
| ❌      | ❌      | Error, so it retries | Whatever the retry produces  |

The second row is the one people expect: the branch falls behind and nobody tells the client. The third row is the one that catches people out. The primary returned an error (or the ack timed out), but the branch write already went through. The client retries. The primary deduplicates the retry if the first attempt actually landed, because that's what idempotent producers are for. The branch, though, receives the retried batch as a fresh write from the router. Unless the router has done the extra work described below, the branch now has a duplicate the primary doesn't.

So in normal running the branch both loses data and duplicates it, independently of the primary. If that sentence makes you uncomfortable, stream branching is the wrong tool for that particular job. That isn't a criticism. It's the reason post 1 sent atomic, lossless replication off to MirrorMaker 2 or [KIP-1279](https://cwiki.apache.org/confluence/display/KAFKA/KIP-1279%3A+Cluster+Mirroring) cluster mirroring.

### Waiting for the branch makes the mainline only as reliable as the branch

The obvious way to close the gap is to hold the client's acknowledgement until both writes succeed. It doesn't work.

If the router waits for the branch, the client's produce latency becomes the slower of the two clusters, and the staging cluster you sized on a budget sets the latency of production. If the router *fails* the client whenever the branch fails, an outage on staging becomes an outage on production. You've wired production's reliability to your least reliable cluster. Even if you accept both of those, you still haven't got atomicity: a branch write can succeed while the primary times out, and you're back in row three of the table.

A branch must never back up onto the mainline. Which leads to the next problem.

### Backpressure: drop or block?

The primary is healthy and the staging cluster is struggling. Branch writes start queueing in the proxy. That queue has to have a limit, because proxy memory isn't infinite and running out of it takes the mainline down as well. When the queue is full, the router has two options:

- **Drop.** Throw away branch writes until the branch catches up. The mainline is unaffected and the branch gets a hole. This is the right default for nearly every branching use case, and it's what "best effort" means in practice.
- **Block.** Stop reading from the client until the branch drains. The branch stays complete, and the mainline slows down to match the branch. Now you're coupled again, just more slowly.

Whichever one you choose, make the drops visible. A branch that loses data silently is one you'll eventually trust when you shouldn't. Count what was dropped, per branch, and alert on it, so that when someone asks whether staging saw the batch that triggered the bug, you can actually answer.

### Partitions don't have to line up

The client's partitioner picked a partition based on the *primary* topic's partition count. The branch topic might have a different number of partitions, or might not have partitions that mean the same thing. If the branch is a faithful shadow with the same partition count, partition *n* maps to partition *n* and per-key ordering survives. If not, the router is repartitioning. It has to choose a branch partition itself, which means either re-hashing the key or making some other decision, and the ordering guarantees on the branch are whatever that decision gives you. Derived streams, such as an audit feed keyed by user rather than by order, almost always fall into the second case. That's fine as long as you meant it.

### Duplicates on the branch

Kafka producers use idempotent delivery by default. The broker deduplicates retried writes, so a message is committed exactly once even if the network drops the acknowledgement and the producer retries. This depends on a Producer ID (`PID`) that the broker assigns at initialisation, plus a per-partition sequence number on every batch. If the broker sees a batch it has already committed (same PID, same sequence), it quietly discards the duplicate. The client never needs to know.

**The mainline PID belongs to the client, and it is never translated.** The client negotiated its PID with the primary cluster, and the router passes it through unchanged, exactly as in connection switching. Every write that carries the client's identity goes to the cluster that issued it. Nothing to map, nothing to invent, nothing to lose. Not needing to translate it is a large part of what separates branching from weaving. Once one client identity has to be valid on several clusters at once, the proxy is translating something far less forgiving than a node ID. That's a problem for the weaving posts.

**Branch PIDs belong to the router.** The branch cluster's identity is something the router created. The client doesn't know the branch cluster exists, and nothing downstream will ever try to resume or share that identity. The router sends its own `InitProducerIdRequest` to the branch cluster, rewrites the producer ID and epoch in each record batch header before sending it down the branch, and owns that identity from start to finish. This is safe *because* the client doesn't know about it: an identity the client can't see is one the client can't collide with. (Those header fields are covered by the batch CRC, so rewriting them means recomputing the checksum. It's cheap compared with decompressing anything, but it isn't free.)

That ownership settles who is talking to the branch. It doesn't settle what the branch deduplicates, which brings back row three of the table. There are two ways to handle sequence numbers:

- **Pass the client's sequence numbers through** under the router's PID. If the branch receives exactly the same batches as the primary, in the same order, from the start of the session, then a client retry carries the same sequence number to both clusters and *both* deduplicate it. That closes row three. It only works as long as the branch is a faithful copy. Sample a batch away, drop one under backpressure, or lose one to a branch error, and the branch sees a gap in the sequence and rejects everything after it with `OUT_OF_ORDER_SEQUENCE_NUMBER`. The router then has to notice, bump its epoch on the branch, and start again, and the batches in flight during that recovery are gone.
- **Assign the router's own sequence numbers.** The router numbers branch batches contiguously however it likes, so sampling, dropping, and derived streams all just work. But the branch can no longer recognise the client's retries, because each one is a new batch from the router. Row three now produces duplicates on the branch every time.

Branches that only sample or derive have to use the second approach. Faithful shadows can try the first, as long as you accept that every gap forces a reset, and that it only helps while each partition's traffic stays on one client connection (more on that next). In both cases the branch's deduplication history is separate from the primary's, and writes the primary would have discarded as duplicates may be accepted on the branch.

**The branch identity belongs to a connection, not to the client.** The router's branch PID only lasts as long as the client connection it was negotiated for. When that connection closes, the proxy tears down everything attached to it, branch identity included. And the client has one PID but several connections: a producer opens one to each broker that leads a partition it writes to, and in a horizontally scaled proxy fleet those connections can land on different proxy instances. The routers serving those connections have no way to coordinate, so each one negotiates its own PID with the branch cluster. One client identity on the primary becomes several unrelated identities on the branch.

That's harmless while each partition's traffic stays on one connection. It stops being harmless when the traffic moves, and in Kafka it moves routinely:

- **Leadership changes.** A partition's leader moves from broker 1 to broker 2, so the client starts sending that partition's batches down a different connection, possibly through a different proxy instance. It carries on with the same PID and the next sequence number. On the primary, that's an ordinary continuation. On the branch, the batches arrive under a PID that has never written to that partition. Whatever sequence numbers the router uses, the branch has no history for that PID, so it can't recognise any batch the client retries across the move.
- **Reconnects.** A network blip, an idle timeout, a broker restart, a proxy restart: anything that drops the client's connection drops the branch identity with it. The client reconnects and resends its in-flight batches, some of which had already reached the branch under the old PID. They arrive under a new PID, and the branch accepts them all as new writes. Reconnecting to the same proxy instance doesn't help, because the old connection's state is already gone.

Both are the same failure. The client's retries for a partition move from one branch identity to another, and the branch can only deduplicate within a single identity.

The mainline is unaffected. Its PID belongs to the client, which holds it across every connection, every proxy instance, and every reconnect, so the primary recognises the retries and discards the ones it has already committed. That's the asymmetry working in your favour: the identity that matters is held by the one party that sees all of the client's traffic. But leadership changes, reconnects, and rolling upgrades are routine, so duplicates on the branch are a normal part of running stream branching, not an edge case.

Use shadow data for observability, not for accounting. If someone wants to reconcile the branch against the primary to the last record, the answer is replication, not branching.

### Transactions don't branch

If the client is a transactional producer, the batches it produces are marked transactional, and they're only meaningful together with the `AddPartitionsToTxn` and `EndTxn` calls the client sends to the *primary's* transaction coordinator. The commit and abort markers that tell consumers which records count aren't produced by the client at all. The primary's coordinator writes them. The router never sees them in the produce stream, so it can't copy them.

That leaves the router with two bad options for a transactional branch:

- **Strip the transactional flag** and write the branch batches as plain idempotent writes. They're visible on the branch straight away, *including records from transactions the primary later aborts*. A `read_committed` consumer on the branch will read data that, as far as the primary is concerned, never existed.
- **Run a shadow transaction** on the branch: the router starts its own transaction against the branch cluster's coordinator, adds partitions as the client does, and commits or aborts when the client's `EndTxn` succeeds or fails on the primary. That's a lot of protocol to mirror, and the two commits are still separate. The primary can commit while the branch aborts, and nothing coordinates the two. Post 1 put it bluntly and it still holds: the Kafka protocol has no cross-cluster transaction coordinator, and routing can't create one.

For shadowing and sampling, stripping the flag and documenting that the branch may contain aborted data is usually the honest choice. For derived streams that feed something financial, don't branch from a transactional producer at all.

## Know when to get off the train

Stream branching is a great tool for a specific set of problems, and it's easy to use it for the wrong ones. A rough guide:

- **You want production-shaped traffic somewhere safe, and losing some is fine.** Branch it. Redact it on the way, sample it if staging is small, and watch the drop counters.
- **You want a stream nobody produces yet, derived statelessly from one that already exists.** Branch it. That's the case that makes the proxy worth running: no application team has to deploy anything.
- **You need the derived stream to be stateful**, such as joins, windows, sessionisation, or deduplication across batches. Use Kafka Streams or a Connect pipeline that reads from the primary. They manage state. A proxy shouldn't.
- **You need a complete, ordered, offset-consistent copy of the primary on another cluster.** Use replication: MirrorMaker 2, KIP-1279 cluster mirroring, or your vendor's equivalent. They read the primary's committed log after the fact, so they can't have the asymmetric failures described above.
- **You need writes to two clusters to be atomic.** Nothing at layer 7 can give you that. Redesign so the writes share a cluster.

The pattern works because it's honest about having two tiers: one stream that carries the guarantee and some that don't. Keep that distinction clear in your config, your dashboards, and your conversations with whoever consumes the branch, and stream branching lets you build streams nobody had to code for. Blur it, and sooner or later someone will be surprised by a gap you could have warned them about.

---

Both flow patterns are now covered. Connection switching picks the track. Stream branching adds branch lines. Next we leave the railway for the sorting office: **topic weaving**, where the router no longer just directs streams but decides which topics exist, where they live, and what they're called. Producer identity comes up again there, and this time the client *does* know about every cluster involved.

If you're branching streams already, or want to and have hit a gap this post didn't cover, find us on [GitHub](https://github.com/kroxylicious/kroxylicious), [Slack](https://kroxylicious.slack.com), or [Bluesky](https://bsky.app/profile/kroxylicious.io).
