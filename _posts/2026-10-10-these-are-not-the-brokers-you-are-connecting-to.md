---
layout: post
title: "These are not the brokers you are connecting to"
date: 2026-10-10 15:00:00 +0100
author: "Sam Barker"
author_url: "https://github.com/sambarker"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "routing" ]
---

Back in May, Tom wrote about [a proof of concept for routing]({% post_url 2026-05-21-topic-routing %}) — Kafka clients producing and consuming from topics scattered across multiple clusters, with no idea that's what they're doing. The proxy handles the fan-out, the response merging, the session state. The client just sees topics.

That POC has been quietly maturing. We're now in the process of turning it into something you can actually run in production, and in a few weeks we'll be talking about it at [Current in San Francisco](https://current.confluent.io/san-francisco/sessions#session-SESS-165). In a session called *"These are not the brokers you are connecting to"* — my employer does not condone lying, but the proxy will quite happily tell your clients whatever you need it to.

This post is the first in a short series leading up to that talk. The goal here is to establish some vocabulary and get into the gory details I won't have time for onstage. I've been thinking about the design space routing enables and I'm convinced there are a handful of distinct patterns worth naming separately. There are no hard boundaries between the patterns, they all leverage the same underlying infrastructure, but they are distinct because they trade off different aspects of the problem space. The names are mine and while I'll happily accept better ones, we need something to start a conversation (plus I'm right 😉).

The deeper dives on each pattern will follow in subsequent posts.

## Pick your poison

If you've tried to migrate a live Kafka workload between clusters, consolidate regional deployments, or shift cloud providers, you will have run into the same core problem: Kafka is not HTTP-based (stop rolling your eyes at the back). Kafka clients are genuinely indifferent to geography — they'll talk to a broker in the same pod just as happily as one in Timbuktu. What they care about, deeply and lastingly, is *which* broker they're talking to. Broker 1 is Broker 1. You can't quietly swap it out, move it between availability zones, or retire it without a lot of fuss. The load balancer doesn't get a say. Most proxies can only manage Kafka as a layer 4 protocol — and layer 4 is BOOOOORRRRING (I will not listen to arguments from the network engineer in the corner).

So when you need to reshape the underlying infrastructure without breaking application teams, you usually end up picking which operational headache you dislike the least.

**Application-level dual writes** look clean in architecture diagrams. In production, network blips cause asymmetric failures, message ordering drifts, and duplicate delivery becomes every application team's problem. Getting twenty teams to deploy matching code changes on the same timeline is an exercise in cat-herding that usually ends with someone's Friday afternoon becoming someone else's out of hours page.

**Replication pipelines** (MirrorMaker 2, et al.) work great for asynchronous backup, but for live consolidation knowing whether you're in sync is a very difficult question, not to mention doubling storage and network costs, and asking consumers to deal with offset translation. You're running twice as much hardware to move bytes you already owned, fine if the migration ever actually ends.

**Maintenance windows** are conceptually simple right up until a legacy service ignores DNS TTLs, holds onto stale sockets, and drops messages silently when the old brokers finally go dark. Sunday 2am is when the core reporting pipeline splutters to a halt.

## What a Layer 7 proxy buys you

Jumping up to Layer 7 changes the game. Rather than blindly punting TCP bytes around, the proxy speaks Kafka. It knows a `Metadata` response from a `Produce` request, and it can answer a client's question about where the brokers live with whatever answer you need.

From day one, Kroxylicious gave you a Virtual Kafka Cluster (VKC) — a stable endpoint for your clients. But until recently, it was an opinionated pipe. That was a compliment: it did real work. It could encrypt records, enforce auth, rewrite headers — all without the client noticing. But it was still a fixed pipe: one client socket in, one backend socket out, wired to whatever cluster you pointed it at on boot. The filters were stateless with respect to the broker topology: an encryption filter might talk out-of-band to a KMS for keys, but it didn't care which physical cluster lived behind the socket.

Think of it like the horse in the late 19th century. A horse gets you from A to B across familiar ground without needing a national highway project. You feed it, you mount it, and you go. Horses were great.

[Proposal 70](https://github.com/kroxylicious/design/blob/main/proposals/070-routing-api.md), the Routing API, is our combustion engine. The filters haven't gone anywhere — encryption, auth enforcement, and header rewriting all ride along inside the car. But the platform underneath can now make routing decisions on the fly. As a project, we provide the API so *any* car is possible, but we only supply the Model T — apocryphally in any colour you like, so long as it's black. If you need a bespoke Bentley or Bugatti router, you can build it.

The trade-off is the same one history made. A horse rider and a car driver both pick their own destination. But while the horse is happy on grass, the car only delivers that speed and range if there are roads, fuel stops, and mechanics.

Routing is the exact same trade: more range, more power, but you depend on the world outside the proxy. Kroxylicious can't and shouldn't make your business policy decisions — it doesn't know which tenant belongs on which tier or when a cluster swap is safe. Those decisions belong to you. What the proxy gives you is the steering wheel, the throttle, and a much bigger map.

We get it: running a proxy is operational overhead. We wish swapping a CNAME was enough as much as you do — but to a Kafka client, a CNAME flip is an unexpected divorce. That's why we're all here.

## Name them we must

After reviewing the [routing design proposal](https://github.com/kroxylicious/design/pull/70) and thinking through the problem space, I think there are multiple distinct deployment patterns worth naming. As with all patterns the boundaries are fuzzy and often more than one applies at once. The thing that convinces me they're real is that they have descriptive power — each one has its own tradeoffs, failure modes, and a distinct place on the spectrum from the clear(ish) waters of connection switching to the mangrove swamp of partition weaving. Like all good abstractions, they're useful.

You can deploy the proxy on either side of the network boundary: helping traffic egress from the client domain (forward proxy territory), or managing ingress into the broker domain (reverse proxy territory). We prefer *egress* and *ingress* because they describe traffic flows from your perspective rather than abstract networking theory. Some patterns land far more naturally on one side than the other, and we'll call that out as we go, but the underlying mechanics are the same.

If you're reaching for the [Enterprise Integration Patterns](https://www.enterpriseintegrationpatterns.com/patterns/messaging/MessageRoutingIntro.html) book right now — well done for being as old as I am, the rest of you just Googled it. It describes what happens to individual messages, which is interesting, but I'm talking about whole streams. Those patterns are what makes all this possible under the hood; what I'm describing sits a layer or two higher.

The patterns do build on each other in terms of what the proxy has to understand about the Kafka protocol — each one introduces a new class of work the router stage has to own. But the complexity doesn't compound when you compose them, because the routing pipeline is a DAG: each stage is narrowly scoped to its own job and doesn't need to know what the stages around it are doing. A topology-aware routing stage doesn't care whether the topic it's directing traffic to is a virtual topic or a plain one. A virtual topic stage doesn't care whether the cluster it's dispatching to is an alias or a physical cluster. You pay the cost of each stage once, and only if you need it.


### Connection switching

Until recently a VKC provided a 1:1 mapping between the thing the client addressed and the thing the proxy dialled. The routing API breaks that constraint — one VKC can now connect to one or more physical backends, and the target isn't fixed. The VKC is stable; what's behind it doesn't have to be.

Every organisation has a cage it can't close. The CFO wants it gone, but somewhere upstream is "the Thing" nobody dares touch that still talks to the Kafka cluster inside it. The cluster is full. The cage is full. You need more capacity, and you can't get it here.

Before routing, that means updating `bootstrap.servers` in half a million places — and crucially, touching the Thing.

With connection switching, you leave a Kroxylicious instance in the cage and point it at a new cluster wherever you actually have headroom. Every client still connects to the same address. The proxy dials the new cluster behind the scenes. When you're ready, update the route. When the cage is empty, tell the CFO. Nobody had to touch the Thing.

Before routing, Kroxylicious was a pipe with opinions — it could inspect and rewrite the stream, but it was inherently connection-oriented. One client socket, one backend, straight through. Connection switching breaks the static part of that: the backend can now change. The routing decision is made once at connection time — the points are thrown before the train departs, and after that it's a straight run to the destination. It's still 1:1; the interesting thing is that the 1 on the right side is now chosen, not fixed.

### Stream branching

You're chasing an issue in the reporting pipeline that only shows up in the sixth hour of the run and nobody can figure out which record trips it up. You've been there, right? What you really want is access to the live data with a debugger. Alas, this job is stuffed full of Personally Identifiable Information — so you're out of luck. You've been there and got *that* t-shirt. What now? You build a router that shadows production traffic to a staging cluster, piping it through a redaction filter on the way so the PII becomes gibberish before it touches staging brokers. The client is still producing to one VKC. But the proxy is now opening *two* backend connections — one to the primary cluster, one to staging — and writing every record to both. The acknowledgement the client gets back is from the primary; the shadow write happens on the side. One stream in, two streams out. If you've got your EIP book off the shelf already, yes — it's a Wire Tap with a Message Translator on the diverted stream.

That's one flavour of stream branching — the secondary stream is a copy of the primary, diverted somewhere and the client never realises. But the diverted branch doesn't have to be a copy. Every record passes through the routing DAG before it hits the broker. Something in that DAG can inspect the payload, compute something from it — consumer lag, record counts by key, an audit trail your compliance team needs — and emit that derived data to a topic anywhere the routing config points — a different topic on the same cluster, or a cluster the client has never heard of. The primary stream is untouched. The additional streams just appear, derived from the original client's activity. The clients don't change. Which means anything that previously required every application to cooperate — the audit trail, the telemetry, the thing all but one of your clients never supported — you can now just invent that stream yourself.

What the routing layer has to own here is the fan-out. It has to manage the additional backend connections, generate the rewritten requests for each branch, and decide what to do if a secondary destination is slow or unavailable. Stream branching is in the category of dual writes, and dual writes have sharp edges. How sharply they cut depends entirely on your use case — the post on stream branching gets into it.

### Topic weaving

Your New York application team wants to consume `london_orders`, `tokyo_orders`, and `newyork_orders`. Those topics live on three different clusters — one in each region, provisioned by three different teams at three different points in time. Without topic weaving, the NY team needs bootstrap addresses for all three clusters, separate client configurations for all three, and the operational joy of managing credentials and failover for all three. With topic weaving, you point them at one VKC. The routing layer stitches the backing clusters together into a single logical view. The client asks for metadata and gets back a broker list that includes all brokers from all regions as part of the same cluster. As far as the client belives they all live in its local cluster. 

That's the common case: different topics, different clusters, one coherent view for the client. Your router is what holds the map — which topic lives where, which broker list to return, what gets dispatched where. Because the proxy controls what gets returned in a metadata response, you decide which brokers are visible, under what names, and what maps where.

There's a subtler case. What if two of your clusters both host a topic called `orders`? Think of it like a sorting office: you write *George Street* on the parcel and drop it at the counter. The sorting office decides whether you mean George Street, Edinburgh or George Street, Dunedin — a city in New Zealand that Scottish settlers named after Edinburgh, gave the same street names, and promptly scrambled the layout. (Guess why I know.) The sender doesn't need to know both exist. Neither does your client. Because the proxy controls what gets returned in a metadata response, your router decides which topics are visible and under what names — which means in principle it can arbitrate which names reach clients, or whether the duplicate surfaces at all.

You look after a gaggle of Kafka clusters. You know how they got there. You're not proud of all of them. You can't herd them — geese are worse than cats, they honk back — but you don't have to admit to anyone else how many geese there actually are, or what they're called.

Two things to keep in mind. Consumer group co-ordination stays pinned to physical clusters — that's almost always fine, because a group's offset state is tied to the topic-partitions it's consuming and those live on one backend, but it's worth knowing the seam is there. And transactions don't cross cluster boundaries: a transaction that writes to topics on two different backing clusters is two independent transactions, and there is no way to make it otherwise — the Kafka protocol has no cross-cluster transaction coordinator and routing can't invent one. If cross-topic atomicity matters, those topics need to share a physical cluster.

### Partition weaving

A single logical topic whose partitions are composed from physical topics on multiple clusters — which don't even need to share a name. A client asks for metadata for `topic-x` and gets back 32 partitions; partitions 0–15 are sourced from `topic-x` on `us-east`, 16–31 from `topic-eu` on `eu-west`. A `ProduceRequest` for partition 20 gets routed to `eu-west` transparently, with partition numbers rewritten to match the physical layout. The client sees one topic. It has no idea.

The motivating example here is one topic weaving can't solve. Your reporting pipeline in `us-east` is hardcoded to read from `topic-x`. It has always read from `topic-x`. It will continue to read from `topic-x`. The problem is on the producer side: your business is growing in Europe, and sending every EU event across the Atlantic to land on the `us-east` cluster is expensive, slow, and fragile. The EU team provisions `topic-eu` on a cluster local to them, sized for their producer load. The router presents both physical topics as one logical `topic-x` to every client. EU producers write locally. The reporting pipeline reads the full partition space without a config change. Nobody crosses the Atlantic unnecessarily.

What the proxy has to do here is more demanding than in any of the previous patterns: partition numbers must be rewritten consistently across every Kafka RPC that mentions them — `Metadata`, `Produce`, `Fetch`, `OffsetCommit`, `OffsetFetch`, `ListOffsets`, group coordinator lookups. That's the essential complexity of the pattern, not incidental overhead. It's a lot of surfaces to get right. The operational contract also shifts: both physical topics have to honour the mapping, and the router config is now the source of truth for what `topic-x` means. Transactions don't cross cluster boundaries here either — same caveat as topic weaving, but worth repeating because with partition weaving it's easier to forget the seam is there.

---

These four patterns give us a working vocabulary for the rest of the series. The posts that follow take each one in turn — what it can do, what it can't, and why. Some of the limits are ours and will close over time. Some are the Kafka protocol's: transactions have no external coordinator, and no amount of clever routing changes that. And some would require the proxy to grow a consensus layer of its own — which is a whole different animal, and not one we're planning to domesticate any time soon.

If you're thinking about Kafka topology problems, have a use case that doesn't fit cleanly into any of these patterns, or want to tell us where the vocabulary breaks down — find us on [GitHub](https://github.com/kroxylicious/kroxylicious), [Slack](https://kroxylicious.slack.com), or [Bluesky](https://bsky.app/profile/kroxylicious.io).
