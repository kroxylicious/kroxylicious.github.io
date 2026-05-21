---
layout: post
title: "A proof of concept for Routing"
date: 2026-05-21 00:00:00 +0000
author: "Tom Bentley"
author_url: "https://github.com/tombentley"
# noinspection YAMLSchemaValidation
categories: blog kroxylicious-proxy
tags: [ "kroxylicious-proxy" ]
---

**tl;dr**: We've built a proof-of-concept (POC) routing capability that allows Kafka clients to produce and consume records to topics in multiple clusters. In other words, clients don't need to know where their topics live.

Here's a demo:

**TODO Video**

You can run this for yourself; check out the [routing POC branch](https://github.com/tombentley/kproxy/tree/routing/) on GitHub.

## What's the backstory?

Nearly a year ago, I had an idea which I wrote up in what's become known as [The Routing Proposal](https://github.com/tombentley/kroxylicious-design/blob/8378acd7ef4c194cce5b60419bf92c8e8c7d8ea3/proposals/004-routing-api.md).
(You know something might be important if it gets initial caps).
While a few people commented and it felt like a good concept, it was also a long way from the reality of the proxy codebase at that time. 
And anyway, it's not as if this is the only good idea that we had, or the only thing we had to work on.
So it got put on The Back Burner, where many an idea sits until its time comes, or it gets forgotten about.

However, for this particular idea it was hard to forget about it for long. Engineers from various companies showed up on our slack channel asking about it. They had use cases similar to some of the use cases described in the proposal. They wanted to know: Was it being worked on? Some were even uttering those words that are music to an open source project's ears: "How can we help?"

Some of our amazing contributors started the process with some initial refactorings. 
Now, nearly a year later, we've found the time (and, I admit the tokens) to throw at building a proof of concept.

Right now the proof of concept (POC) branch is an interleaved mishmash of commits in each of these three areas. However, the take-away is that we believe we have an API which is capable of supporting a non-trivial router.

The router we've implemented allows clients to talk to multiple clusters. 

## How does it work?

At its core, the router maintains a map of which topics belong to which cluster. These mappings are validated to be non-overlapping, so there's never any ambiguity about where a request should go.

When a producer sends a `PRODUCE` request, the router groups the topic partitions by their target cluster, fans the request out to each cluster in parallel, then merges the responses back into a single reply. `FETCH` requests are handled similarly for consumers. This all happens transparently to the client. 

To support incremental `FETCH` (where the broker remembers which topic partitions a consumer cares about, saving the consumer from re-sending that list on every poll), the router maintains per-connection session state for both the client-proxy and proxy-broker sides of each connection. This is more complex under the hood, but invisible to the consumer.

Transactions and consumer groups work differently. Both rely on a broker to act as a "coordinator" for multiple participants (brokers or clients) to work together. At the moment the router supports these Kafka features in a more limited way, by only allowing these client interactions when all the topics involved reside in the same target cluster. The target cluster is determined from the client's authenticated identity - a constraint imposed by how the protocol works. We have a good idea about how this could be solved in a more general way, but for now our focus is on getting the POC into something which could actually run in production.


## Why is this useful?

There are two dimensions to this:

* Building a topic router is useful in itself for helping address a number of real-life headaches for Kafka users. It means that clients don't need to know where their topics actually live, and it means Kafka service providers can move topics between clusters without bothering users. The holy grail would be to do this completely transparently. Our POC router has limitations which make it somewhat apparent to users, but it's a big step forward from where we were.

* Building a topic router is a great way to validate the Router API itself: That the runtime is providing the right services to the Router implementation, through appropriate abstractions. 

## What happens next?

This is at a POC stage. This blog post is announcing that we're in the middle phase of the transition from Vapourware to Software. What's that called? Condensationware?

The big picture of what we've done breaks down like this:

1. Preparatory internal refactoring to break apart a single state machine into two: One state machine for the client-proxy interaction, and a separate one for the proxy-broker interaction.

2. The work to add the Router API, and implement the runtime support for it.

3. The work to implement the Topic Router plugin using that API.

This is where the Kroxylicious community comes in  - turning those three big pieces into something that's actually usable and supportable.

At this stage none of this is set in stone and we have no idea how long it's likely to take for us to turn this from a POC into released software that you can actually use. Hopefully it will be less than the year it's taken to go from idea to POC though, but the truth is no one can say. 

Nor can we guarantee that we'll eventually be able to handle the full gamut of the Kafka protocol. We need to investigate some of the newer functionality (e.g. Two phase commit, Share Groups, and so on). And the whole time the Apache Kafka community are powering onwards adding _more_ functionality.

## So why all the hullabaloo?

We think this is pretty cool, and we wanted to let people know that we're actively working on this. And being open source, we wanted to remind people that they can [join us](/join-us/) and get involved in any of the following ways:

* Tell us how you'd use the Router API: We have some ideas for other routers we want to build, but maybe you have an idea that only makes sense in your company. That's OK — not every router needs to be general-purpose. Kroxylicious is built for exactly that kind of bespoke use case.
* Tell us how you'd use a topic router. What Kafka features does it need to support? What functionality does it need for operators?
* Engage with our process for ironing out all the kinks in the API.
* Help us test this thing! We're especially interested to hear from people who can test at scale on real workloads.
