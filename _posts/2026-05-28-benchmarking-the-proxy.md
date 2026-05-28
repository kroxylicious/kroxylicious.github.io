---
layout: post
title:  "Does my proxy look big in this cluster?"
date:   2026-05-28 02:30:00 +0000
author: "Sam Barker"
author_url: "https://github.com/SamBarker"
categories: benchmarking performance
---

Every good benchmarking story starts with a hunch. Mine was that Kroxylicious is cheap to run — I'd stake my career on it, in fact — but it turns out that "trust me, I wrote it" is not a widely accepted unit of measurement. People want proof. Sensibly.

There's a practical question underneath the hunch too. The most common thing operators ask us is some variation of: "How many cores does the proxy need?" Which translates, from polite engineering into plain English, as: "is this thing going to slow down my Kafka?" We'd been giving the classic answer: "it depends on your workload and traffic patterns, so you'll need to test in your environment." Which is true. And also deeply unsatisfying for everyone involved, including us.

So we stopped saying "it depends" — we built something you can run **yourselves** on your own infrastructure with your own workload, and measured it. Here are some representative numbers from ours.

**TL;DR**:
- A passthrough proxy adds negligible overhead: publish latency impact is below measurement noise, E2E adds ~2 ms at moderate topic rates, throughput unaffected
- Add record encryption and expect a ~25% throughput reduction; at comfortable rates, E2E latency stays within measurement noise and publish latency adds up to ~10 ms
- The throughput ceiling scales linearly with CPU: budget ~25 mc per MB/s of total proxy traffic (conservative; a companion post, coming soon, has the full sizing formula)
- The full benchmark harness is open source — run it on your own cluster for numbers that reflect your workload

## What we measured

We ran three scenarios against the same Apache Kafka® cluster on the same hardware:

- **Baseline** — producers and consumers talking directly to Kafka, no proxy in the path
- **Passthrough proxy** — traffic routed through Kroxylicious with no filter chain configured
- **Record encryption** — traffic through Kroxylicious with AES-256-GCM record encryption enabled, using HashiCorp Vault as the KMS

We used [OpenMessaging Benchmark (OMB)](https://github.com/openmessaging/benchmark) rather than Kafka's own `kafka-producer-perf-test`. OMB is an industry-standard tool that coordinates producers and consumers together, measures end-to-end latency (not just publish latency), and produces structured JSON that makes comparison straightforward. More on why we built a whole harness around it in a companion engineering post, coming soon.

## Test environment

No, we didn't run this on a laptop — it's a realistic deployment: an 11-node OpenShift cluster on Fyre (8 workers, 3 masters), IBM's internal cloud platform — a controlled environment. Kroxylicious ran as a single proxy pod with a 1000m CPU limit. The cluster is sized so that the Kafka brokers, the proxy, and the benchmark workers each run on separate nodes, ensuring traffic crosses real network links rather than looping back on the same host.

| Component | Details |
|-----------|---------|
| CPU | AMD EPYC-Rome, 2 GHz |
| Memory | 16 GiB per node |
| Cluster | 11-node OpenShift 4.21 (8 workers, 3 masters), RHCOS 9.6 |
| Kafka | 3-broker Strimzi 0.51.0 (Kafka 3.9) cluster, replication factor 3 |
| Kroxylicious | 0.21.0, single proxy pod |
| KMS | HashiCorp Vault 2.0.0 (in-cluster) |

The primary workload used 1 topic, 1 partition, 1 KB messages. We chose single-partition deliberately: it concentrates all traffic on one broker, so you hit ceilings quickly and any proxy overhead is easy to isolate. We also ran 10-topic and 100-topic workloads to make sure the results hold when load is spread more realistically across brokers.

One important caveat: this Kafka cluster is deliberately untuned. We're not trying to squeeze every message-per-second out of Kafka — we're using it as a fixed baseline to measure what the proxy adds on top. Kafka experts will find obvious headroom to improve on our baseline numbers; that's fine and expected. The deltas are what matter here, not the absolutes.

---

## The passthrough proxy: negligible overhead

Good news first. The proxy itself — with no filter chain, just routing traffic — adds almost nothing. The tables below show all three scenarios side by side.

A quick note on percentiles for anyone not steeped in performance benchmarking: p99 latency is the value that 99% of requests complete within — meaning 1 in 100 requests takes longer. Averages flatter; the p99 is what your slowest clients actually experience, and it's usually the number that matters.

Two latency metrics appear in the tables. **Publish latency** is measured from the record's intended send time — as dictated by the target producer rate — to when the producer receives the broker's acknowledgement. That means it captures any producer-side delay (backpressure, client queuing, batch accumulation) alongside the network round-trip and ISR replication (we run with `acks=all`). **End-to-end (E2E) latency** is measured from that same intended send time to when the consumer receives the record, adding consumer-side fetch batching on top of everything publish latency already covers.

**10 topics, 1 KB messages (~5,000 msg/s per topic):**

| Metric | Baseline | Proxy (no filters) | Encryption |
|--------|----------|--------------------|------------|
| Publish latency avg | 4.3 ms | 4.5 ms (+0.2 ms) | 14.3 ms (+10.0 ms) |
| Publish latency p99 | 22.4 ms | 19.6 ms (−2.7 ms) | 36.3 ms (+13.9 ms) |
| E2E latency avg | 96.9 ms | 99.0 ms (+2.1 ms) | 97.4 ms (+0.5 ms) |
| E2E latency p99 | 193 ms | 190 ms (−3 ms) | 182 ms (−11 ms) |
| Throughput | 5,000 msg/s | 5,000 msg/s | 5,000 msg/s |

*Negative deltas for proxy-no-filters publish latency are within measurement noise — they indicate the proxy is indistinguishable from baseline, not that it improves latency.*

The passthrough proxy is not adding measurable per-record overhead at this rate. E2E average overhead is +2.1 ms (p<0.001), but practically negligible for any sizing decision.

Encryption adds significant publish latency (+10 ms avg, +13.9 ms p99, p<0.001), as you'd expect for per-record AES-256-GCM. The E2E result is counterintuitive: both proxy scenarios have *lower* E2E p99 than direct Kafka (−3 ms and −11 ms respectively, both p<0.001). E2E latency includes consumer behaviour — fetch timeouts, batch accumulation, scheduling jitter. At 5k msg/s per topic, the proxy's processing of each record slightly regularises delivery timing, damping the consumer-side spikes that drive tail latency in direct Kafka.

**100 topics, 1 KB messages (~500 msg/s per topic):**

| Metric | Baseline | Proxy (no filters) | Encryption |
|--------|----------|--------------------|------------|
| Publish latency avg | 2.9 ms | 4.1 ms (+1.2 ms) | 4.7 ms (+1.8 ms) |
| Publish latency p99 | 6.4 ms | 8.1 ms (+1.7 ms) | 12.1 ms (+5.7 ms) |
| E2E latency avg | 256.7 ms | 254.6 ms (−2.1 ms) | 256.3 ms (−0.4 ms) |
| E2E latency p99 | 502 ms | 501 ms (−1 ms) | 502 ms (≈0) |
| Throughput | 500 msg/s | 500 msg/s | 500 msg/s |

Publish latency overhead is statistically significant at 100 topics (proxy-no-filters p99 +27%, encryption p99 +90%, both p<0.001). But publish latency at 500 msg/s per topic is a small fraction of E2E, and the E2E picture is what operators care about: average and p99 differences are within measurement noise.

**The headline: negligible passthrough overhead — throughput unaffected across all three scenarios.**

What did I take away from this? We replaced a hunch with data. The remarkable part: the proxy is doing this at Layer 7. Most proxies operate on Kafka at Layer 4 — they shuffle bytes without ever understanding what those bytes mean. Kroxylicious works at Layer 7, parsing every Kafka message, yet still adds only a few milliseconds at the E2E average. That's the design working.

The overhead staying flat across 10 and 100 topics makes sense for the same reason: the proxy doesn't contend between topics. Think of the proxy as independent circuits on a distribution board — switching the breaker for lights doesn't cut power to the fridge. A Kafka broker is more like the mains supply itself — every circuit draws from the same source, so heavy load anywhere reduces what's available everywhere. Topics don't contend for shared resources: throughput scales linearly across them, and this data validates it.

---

## Record encryption: now we're doing real work

Ok, so let's make the proxy smarter — make it do something people actually care about! [Record encryption](https://kroxylicious.io/documentation/0.20.0/html/record-encryption-guide) uses AES-256-GCM to encrypt each record passing through the proxy. AES-256-GCM is going to ask the CPU to work relatively hard on its own, but it's also going to push the proxy to parse each record it receives, unpack it, copy it, encrypt it, and re-pack it before sending it on to the broker. With all that work going on we expect some impact to latency and throughput. To answer our original question we need to identify two things: the latency when everything is going smoothly, and the reduction in throughput all this work causes. Monitoring latency once we go past the throughput inflection point isn't very helpful — it's dominated by the throughput limits and their erratic impacts on the latency of individual requests (a big hello to batching and buffering effects).

### Latency at sub-saturation rates

So we know encryption is doing a lot of work, but to find out the real impact we need to compare it to a plain Kafka cluster (and yes, people do run Kroxylicious without filters — TLS termination, stable client endpoints, virtual clusters — but that's a different post). The table below tells us that above a certain inflection point the numbers get really, really noisy — especially in the p99 range.

**1 topic, 1 KB messages — baseline vs encryption (selected rates from rate sweep):**

| Rate | Metric | Baseline | Encryption | Delta |
|------|--------|----------|------------|-------|
| 14,300 msg/s | Publish avg | 5.4 ms | 7.6 ms | +2.2 ms (+41%) |
| 14,300 msg/s | Publish p99 | 16.3 ms | 19.2 ms | +2.9 ms (+18%) |
| 17,100 msg/s | Publish avg | 6.3 ms | 8.9 ms | +2.6 ms (+41%) |
| 17,100 msg/s | Publish p99 | 12.5 ms | 21.9 ms | +9.4 ms (+75%) |
| 18,500 msg/s | Publish avg | 10.5 ms | 13.7 ms | +3.2 ms (+30%) |
| 18,500 msg/s | Publish p99 | 22.0 ms | 106.0 ms | +84.0 ms (+382%) |

The table shows encryption's p99 spiking sharply at 18,500 msg/s — but that ~18k figure is roughly where the forwarding proxy itself saturates (close to the bare Kafka baseline of ~19,400). Encryption gives out earlier. The rate sweep finds exactly where.

### Throughput ceiling

A rate-sweep is exactly what it sounds like: pick a starting rate, let OMB run long enough to get a stable measurement, then step up by a fixed increment and repeat until the system can't keep up. We defined "can't keep up" as the sustained throughput dropping by more than 5% below the target rate — at that point, something has saturated.

We stepped up from 8k to 22k msg/s in 700 msg/s increments, looking for where throughput drops more than 5% below target. The results:

- **Baseline**: sustained up to ~19,400 msg/s (the ceiling at RF=3 on our test cluster)
- **Encryption**: sustained up to **~14,600 msg/s**, then started intermittently saturating
- **Cost: approximately 25% fewer messages per second per partition**

The transition wasn't a clean cliff edge — the proxy alternated between sustaining and saturating in a narrow band just above the ceiling. That pattern is characteristic of running right at a limit: it's not that it suddenly falls over, it's that small fluctuations (GC pauses, scheduling jitter) are enough to tip it either way. Stay below 14k and you're fine. Creep above it and you'll notice. The numbers are not absolute — they are just what we measured on our cluster; your mileage **will vary**.

### The ceiling scales with CPU budget

The fact the proxy is low latency didn't surprise me, but this did — and it matters when we think about scaling. We maxed out a single connection, but that didn't mean we'd maxed out the proxy.

The single-producer ceiling at RF=3 is Kafka-limited, not proxy-limited — the ISR replication round-trip caps single-partition throughput regardless of how much CPU the proxy has. The proxy still had meaningful headroom: we ran four producers and aggregate throughput climbed higher, while proxy CPU sat at 570m/1000m. The proxy wasn't the constraint.

To find the proxy's real ceiling, you need a workload that doesn't hit the Kafka partition limit first: RF=1, spread across multiple topics. With that workload, the ceiling is squarely in the proxy — and it scales linearly with CPU. The mechanism: CPU limit controls `availableProcessors()`, which controls how many Netty event loop threads the proxy creates. More threads, more concurrent connections handled in parallel, higher aggregate ceiling.

**The practical implication**: the throughput ceiling is not a fixed number — it's a function of the CPU you allocate. Set `requests` equal to `limits` in your pod spec; this makes the CPU budget deterministic and the ceiling predictable. A companion engineering post, coming soon, has the full story of how we found this, including the workload design choices needed to isolate proxy CPU from Kafka's own limits.

---

## Sizing guidance

Numbers without guidance aren't very useful, so here's how to translate these results into pod specs.

**Passthrough proxy**: size your Kafka cluster as you normally would. The proxy won't be the bottleneck — but if you want to verify that on your own hardware, the rate sweep — which steps the producer rate up incrementally until the system can't keep up — is exactly the tool for it. Run the baseline and passthrough scenarios back-to-back and you'll have your own numbers.

**With filters (record encryption is the representative example here):**

1. **Throughput budget**: record encryption — among the most CPU-intensive filters we can imagine — imposes a CPU-driven throughput ceiling. As a planning formula:

   > **`CPU (mc) = k × (P + N × C)`**
   >
   > where *k* = sizing coefficient (mc/MB/s), *P* = produce throughput (MB/s), *N* = number of consumer groups, *C* = consume throughput per group (MB/s)

   On our hardware (AMD EPYC-Rome 2 GHz with AES-NI), we measured *k* = 25 mc/MB/s on a 10-topic workload with record encryption — a conservative estimate: more realistic deployments with 100+ topics show *k* = 4–8 mc/MB/s, roughly 3× lower. Simpler filters will be cheaper still. *k* is measured from real workloads, so measure your throughput and validate on your own hardware. The companion post (coming soon) has the full coefficient grid across topic counts and core allocations.

   *1:1 (100k msg/s at 1 KB, 1 consumer group)*: k=25, P=100, N=1, C=100 → 25 × (100 + 1 × 100) = 5,000m (~5 cores)

   *Fan-out (same rate, 3 consumer groups)*: k=25, P=100, N=3, C=100 → 25 × (100 + 3 × 100) = 10,000m (~10 cores)

2. **Latency budget**: well below saturation, expect 2–3 ms additional average publish latency and up to ~15 ms additional p99. The overhead scales with how hard you're pushing — give yourself headroom and you'll barely notice it.

3. **Scaling**: set `requests` equal to `limits` in your pod spec — this makes the CPU budget deterministic, which makes the throughput ceiling predictable. To increase throughput, raise the CPU limit. For redundancy, add proxy pods.

4. **KMS overhead**: DEK caching means Vault isn't on the hot path for every record. Our tests triggered only 5–19 DEK generation calls per benchmark run. The KMS is not the thing to worry about.

---

## Caveats and next steps

These are real results from real hardware, but they don't tell a story for your workload. A few things worth knowing before you put these numbers in a slide deck:

- **Message size**: all results use 1 KB messages. The coefficient is message-size-dependent — encryption overhead as a percentage is likely lower for larger messages.
- **Replication factor**: the encryption numbers assume traffic isn't already hitting Kafka's own replication limits — a companion post, coming soon, explains why that matters.
- **Horizontal scaling**: linear scaling has been validated across CPU allocations on a single pod; multi-pod horizontal scaling hasn't been measured but is expected to follow the same coefficient.
- **Memory**: the workloads tested here are CPU-bound before they become memory-bound — we kept container memory settings consistent across all runs (2 Gi request / 4 Gi limit at the pod level) and it was never the constraint. If you're running larger messages or larger batches, revisit this assumption.

For the engineering story — why we built a custom harness on top of OMB, what the CPU flamegraphs actually show, and the bugs we found in our own tooling along the way — that's in a companion post, coming soon.

The full benchmark suite, quickstart guide, and sizing reference are in `kroxylicious-openmessaging-benchmarks/` in the [main Kroxylicious repository](https://github.com/kroxylicious/kroxylicious).
