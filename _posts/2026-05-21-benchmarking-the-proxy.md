---
layout: post
title:  "Does my proxy look big in this cluster?"
date:   2026-05-21 00:00:00 +0000
author: "Sam Barker"
author_url: "https://github.com/SamBarker"
categories: benchmarking performance
---

Every good benchmarking story starts with a hunch. Mine was that Kroxylicious is cheap to run — I'd stake my career on it, in fact — but it turns out that "trust me, I wrote it" is not a widely accepted unit of measurement. People want proof. Sensibly.

There's a practical question underneath the hunch too. The most common thing operators ask us is some variation of: "How many cores does the proxy need?" Which is really just "is this thing going to slow down my Kafka?" in a polite engineering hat. We'd been giving the classic answer: "it depends on your workload and traffic patterns, so you'll need to test in your environment." Which is true. And also deeply unsatisfying for everyone involved, including us.

So we stopped saying "it depends", and got off the fence: we built something you can run **yourselves** on your own infrastructure with your own workload, and measured it. Here are some representative numbers from ours.

<!-- FIXME: verify all numbers against final benchmark run before publish -->
**TL;DR**: A passthrough Kroxylicious proxy adds ~0.2 ms to average publish latency with no throughput impact. Add record encryption and expect a ~25% throughput reduction and 0.2–3 ms of additional latency at comfortable rates. The throughput ceiling scales linearly with CPU: budget 10 millicores per MB/s of total proxy traffic. The full benchmark harness is open source — run it on your own cluster for numbers that reflect your workload.

## What we measured

We ran three scenarios against the same Apache Kafka® cluster on the same hardware:

- **Baseline** — producers and consumers talking directly to Kafka, no proxy in the path
- **Passthrough proxy** — traffic routed through Kroxylicious with no filter chain configured
- **Record encryption** — traffic through Kroxylicious with AES-256-GCM record encryption enabled, using HashiCorp Vault as the KMS

We used [OpenMessaging Benchmark (OMB)](https://github.com/openmessaging/benchmark) rather than Kafka's own `kafka-producer-perf-test`. OMB is an industry-standard tool that coordinates producers and consumers together, measures end-to-end latency (not just publish latency), and produces structured JSON that makes comparison straightforward. More on why we built a whole harness around it in the [companion engineering post]({% post_url 2026-05-28-benchmarking-the-proxy-under-the-hood %}).

## Test environment

No, we didn't run this on a laptop — it's a realistic deployment: an 8-node OpenShift cluster on Fyre (5 workers, 3 masters), IBM's internal cloud platform — a controlled environment. Kroxylicious ran as a single proxy pod with a 1000m CPU limit.

| Component | Details |
|-----------|---------|
| CPU | AMD EPYC-Rome, 2 GHz |
| Cluster | 8-node OpenShift (5 workers, 3 masters), RHCOS 9.6 |
| Kafka | 3-broker Strimzi cluster, replication factor 3 |
| Kroxylicious | 0.20.0, single proxy pod, 1000m CPU limit |
| KMS | HashiCorp Vault (in-cluster) |

The primary workload used 1 topic, 1 partition, 1 KB messages. We chose single-partition deliberately: it concentrates all traffic on one broker, so you hit ceilings quickly and any proxy overhead is easy to isolate. We also ran 10-topic and 100-topic workloads to make sure the results hold when load is spread more realistically across brokers.

One important caveat: this Kafka cluster is deliberately untuned. We're not trying to squeeze every message-per-second out of Kafka — we're using it as a fixed baseline to measure what the proxy adds on top. Kafka experts will find obvious headroom to improve on our baseline numbers; that's fine and expected. The deltas are what matter here, not the absolutes.

---

## The passthrough proxy: negligible overhead

Good news first. The proxy itself — with no filter chain, just routing traffic — adds almost nothing.

**10 topics, 1 KB messages (5,000 msg/s per topic):**

| Metric | Baseline | Proxy | Delta |
|--------|----------|-------|-------|
| Publish latency avg | 2.62 ms | 2.79 ms | +0.17 ms (+7%) |
| Publish latency p99 | 14.09 ms | 15.17 ms | +1.08 ms (+8%) |
| E2E latency avg | 94.87 ms | 95.34 ms | +0.47 ms (+0.5%) |
| E2E latency p99 | 185.00 ms | 186.00 ms | +1.00 ms (+0.5%) |
| Publish rate | 5,002 msg/s | 5,002 msg/s | 0 |

**100 topics, 1 KB messages (500 msg/s per topic):**

| Metric | Baseline | Proxy | Delta |
|--------|----------|-------|-------|
| Publish latency avg | 2.66 ms | 2.82 ms | +0.16 ms (+6%) |
| Publish latency p99 | 5.54 ms | 6.07 ms | +0.53 ms (+10%) |
| E2E latency avg | 253.16 ms | 253.76 ms | +0.60 ms (+0.2%) |
| E2E latency p99 | 499.00 ms | 499.00 ms | 0 |
| Publish rate | 500 msg/s | 500 msg/s | 0 |

**The headline: ~0.2 ms additional average publish latency. Throughput is unaffected.**

What did I take away from this entirely unsurprising result? Not much, honestly — without filters the proxy boils the latency-sensitive path down to little more than a couple of hops through the TCP stack. We replaced a hunch with data. The remarkable part: the proxy is doing this at Layer 7.

The overhead holding across 10 and 100 topics makes sense for the same reason: the proxy doesn't contend between topics. A Kafka broker juggles disk I/O, partition leaders, and replication across everything it manages; the proxy treats each connection independently. Topics don't contend for shared resources: throughput scales linearly across them, and the connection sweep validates it.

The end-to-end p99 figure is dominated by Kafka consumer fetch timeouts, as it should be. That said, it is reassuring to have a sub-ms impact on the p99.

---

## Record encryption: now we're doing real work

Ok, so let's make the proxy smarter — make it do something people actually care about! [Record encryption](https://kroxylicious.io/documentation/0.20.0/html/record-encryption-guide) uses AES-256-GCM to encrypt each record passing through the proxy. AES-256-GCM is going to ask the CPU to work relatively hard on its own, but it's also going to push the proxy to understand each record it receives, unpack it, copy it, encrypt it, and re-pack it before sending it on to the broker. With all that work going on we expect some impact to latency and throughput. To answer our original question we need to identify two things: the latency when everything is going smoothly, and the reduction in throughput all this work causes. Monitoring latency once we go past the throughput inflection point isn't very helpful — it's dominated by the throughput limits and their erratic impacts on the latency of individual requests (a big hello to batching and buffering effects).

### Latency at sub-saturation rates

A quick note on percentiles for anyone not steeped in performance benchmarking: p99 latency is the value that 99% of requests complete within — meaning 1 in 100 requests takes longer. Averages flatter; the p99 is what your slowest clients actually experience, and it's usually the number that matters.

So we know encryption is doing a lot of work, but to find out the real impact we need to compare it to a plain Kafka cluster (and yes, people do run Kroxylicious without filters — TLS termination, stable client endpoints, virtual clusters — but that's a different post). The table below tells us that above a certain inflection point the numbers get really, really noisy — especially in the p99 range.

**1 topic, 1 KB messages — baseline vs encryption:**

| Rate | Metric | Baseline | Encryption | Delta |
|------|--------|----------|------------|-------|
| 34,000 msg/s | Publish avg | 8.00 ms | 8.19 ms | +0.19 ms (+2%) |
| 34,000 msg/s | Publish p99 | 48.65 ms | 64.01 ms | +15.35 ms (+32%) |
| 36,000 msg/s | Publish avg | 9.38 ms | 10.46 ms | +1.08 ms (+12%) |
| 36,000 msg/s | Publish p99 | 63.92 ms | 88.98 ms | +25.06 ms (+39%) |
| 37,200 msg/s | Publish avg | 9.12 ms | 12.19 ms | +3.07 ms (+34%) |
| 37,200 msg/s | Publish p99 | 74.88 ms | 113.15 ms | +38.27 ms (+51%) |

So we know that somewhere above 34k we're hitting a limit. Time to hunt out exactly where — enter the rate-sweep.

### Throughput ceiling

A rate-sweep is exactly what it sounds like: pick a starting rate, let OMB run long enough to get a stable measurement, then step up by a fixed percentage and repeat until the system can't keep up. We defined "can't keep up" as the sustained throughput dropping by more than 5% below the target rate — at that point, something has saturated.

We started at 34k (right where the latency table started getting interesting) and stepped up in 5% increments. The results:

- **Baseline**: sustained up to ~19,400 msg/s (the ceiling at RF=3 on our test cluster)
- **Encryption**: sustained up to **~14,600 msg/s**, then started intermittently saturating
- **Cost: approximately 25% fewer messages per second per partition**

The transition wasn't a clean cliff edge — the proxy alternated between sustaining and saturating in a narrow band just above the ceiling. That pattern is characteristic of running right at a limit: it's not that it suddenly falls over, it's that small fluctuations (GC pauses, scheduling jitter) are enough to tip it either way. Stay below 14k and you're fine. Creep above it and you'll notice. The numbers are not absolute — they are just what we measured on our cluster; your mileage **will vary**.

### The ceiling scales with CPU budget

The fact the proxy is low latency didn't surprise me, but this did — and it matters when we think about scaling. We maxed out a single connection, but that didn't mean we'd maxed out the proxy.

The single-producer ceiling at RF=3 is Kafka-limited, not proxy-limited — the ISR replication round-trip caps single-partition throughput regardless of how much CPU the proxy has. The proxy still had meaningful headroom: we ran four producers and aggregate throughput climbed higher, while proxy CPU sat at 570m/1000m. The proxy wasn't the constraint.

To find the proxy's real ceiling, you need a workload that doesn't hit the Kafka partition limit first: RF=1, spread across multiple topics. With that workload, the ceiling is squarely in the proxy — and it scales linearly with CPU. The mechanism: CPU limit controls `availableProcessors()`, which controls how many Netty event loop threads the proxy creates. More threads, more concurrent connections handled in parallel, higher aggregate ceiling.

| CPU limit | Comfortable ceiling | Saturation point |
|-----------|--------------------|--------------------|
| 1000m | ~80k msg/s | ~126k msg/s |
| 2000m | ~80k msg/s | above 160k msg/s |
| 4000m | ~160k msg/s | above 321k msg/s |

**The practical implication**: the throughput ceiling is not a fixed number — it's a function of the CPU you allocate. Set `requests` equal to `limits` in your pod spec; this makes the CPU budget deterministic and the ceiling predictable. The companion engineering post has the full story of how we found this, including the workload design choices needed to isolate proxy CPU from Kafka's own limits.

---

## Sizing guidance

Numbers without guidance aren't very useful, so here's how to translate these results into pod specs.

**Passthrough proxy**: size your Kafka cluster as you normally would. The proxy won't be the bottleneck — but if you want to verify that on your own hardware, the rate sweep is exactly the tool for it. Run the baseline and passthrough scenarios back-to-back and you'll have your own numbers.

**With record encryption:**

1. **Throughput budget**: encryption imposes a CPU-driven throughput ceiling. As a planning formula:

   > **`proxy CPU (millicores) = 10 × total proxy throughput (MB/s)`**
   >
   > where *total* = produce MB/s + (each consumer group's consume MB/s independently)

   For a single produce:consume pair this simplifies to `20 × produce MB/s`. Fan-out multiplies: 100 MB/s produce to 3 consumer groups = 100 + 300 = 400 MB/s total → 4,000m. Add ×1.3 headroom for GC pauses and burst. Measured on AMD EPYC-Rome 2 GHz with AES-NI — calibrate on your hardware using the rate sweep.

   Worked example: 100k msg/s at 1 KB, 1 consumer group = 100 MB/s produce + 100 MB/s consume = 200 MB/s × 10 = 2,000m, plus headroom → ~2,600m (~2.6 cores).

2. **Latency budget**: well below saturation, expect 0.2–3 ms additional average publish latency and 15–40 ms additional p99. The overhead scales with how hard you're pushing — give yourself headroom and you'll barely notice it.

3. **Scaling**: set `requests` equal to `limits` in your pod spec — this makes the CPU budget deterministic, which makes the throughput ceiling predictable. To increase throughput, raise the CPU limit. For redundancy, add proxy pods.

4. **KMS overhead**: DEK caching means Vault isn't on the hot path for every record. Our tests triggered only 5–19 DEK generation calls per benchmark run. The KMS is not the thing to worry about.

---

## Caveats and next steps

These are real results from real hardware, but they don't tell a story for your workload. A few things worth knowing before you put these numbers in a slide deck:

- **Message size**: all results use 1 KB messages. The coefficient is message-size-dependent — encryption overhead as a percentage is likely lower for larger messages.
- **Replication factor**: the 1-topic rate sweep ran at RF=3. At that replication factor, Kafka's ISR replication traffic creates a per-partition ceiling that sits close to where proxy CPU also saturates — the two limits are entangled in those results. The sizing coefficient was derived from RF=1 multi-topic workloads specifically to isolate proxy CPU. The [companion engineering post]({% post_url 2026-05-28-benchmarking-the-proxy-under-the-hood %}) has that detail.
- **Horizontal scaling**: linear scaling has been validated across CPU allocations on a single pod; multi-pod horizontal scaling hasn't been measured but is expected to follow the same coefficient.

For the engineering story — why we built a custom harness on top of OMB, what the CPU flamegraphs actually show, and the bugs we found in our own tooling along the way — that's in the [companion post]({% post_url 2026-05-28-benchmarking-the-proxy-under-the-hood %}).

The full benchmark suite, quickstart guide, and sizing reference are in `kroxylicious-openmessaging-benchmarks/` in the [main Kroxylicious repository](https://github.com/kroxylicious/kroxylicious).
