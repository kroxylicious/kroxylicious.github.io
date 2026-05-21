---
layout: post
title:  "How hard can it be??? Maxing out a Kroxylicious instance"
date:   2026-05-28 00:00:00 +0000
author: "Sam Barker"
author_url: "https://github.com/SamBarker"
categories: benchmarking performance engineering
---

How hard can it be? We started with a laptop, a codebase, and a lot of confidence it was fast. We ended up with a benchmark harness, an eight-node cluster, and a much more nuanced answer.

Harder than expected. More interesting too.

We gave everyone [the numbers]({% post_url 2026-05-21-benchmarking-the-proxy %}) in a bland, but slide worthy way, already. This one is the engineering story: how we built the harness, what the flamegraphs actually show, the workload design choices that changed the answers, and the bugs we found in our own tooling.

## Why not Kafka's own tools?

Kafka ships with `kafka-producer-perf-test` and `kafka-consumer-perf-test`. We'd used them before. The problems:

- **Too noisy**: individual runs produced widely varying results depending on JVM warm-up, scheduling jitter, and GC behaviour. Results were hard to trust and harder to compare across scenarios.
- **Producer-only view**: `kafka-producer-perf-test` gives you publish latency, but nothing about the consumer side. You can't see end-to-end latency — which is something operators actually care about.
- **Awkward to sweep**: running parametric rate sweeps requires scripting around these tools, and comparing results across scenarios requires manual work.
- **Coordinated omission**: under load, kafka-producer-perf-test only measures requests it actually sends! So when things start loading up and applying back pressure the send rate drops and the latency stays looking nice and healthy. Only it's not healthy in reality, things are queuing up in your producer. 

And critically, it's never heard of Kroxylicious... You have though, you're here!

[OpenMessaging Benchmark (OMB)](https://github.com/openmessaging/benchmark) is a better fit. It's an industry-standard tool used by Confluent, the Pulsar team, and others for their published performance comparisons — so who am I to argue? OMB coordinates producers and consumers across separate worker pods, runs a configurable warmup phase before taking measurements, takes latency tracking seriously — correcting for coordinated omission, and outputs structured JSON that's straightforward to process programmatically. What's not to like? 

Using OMB also means our methodology is directly comparable to other published Kafka benchmarks. The numbers aren't comparable, of course — it's not the same hardware, network conditions or phase of the moon. 

## What we built on top of OMB

So we just fire up OMB and get some numbers, right? Errr no. OMB just does the measurement part. I work really hard at being lazy, I hate clicking things with a mouse and I knew these tests needed to be repeatable. So we scripted deployment (of all the things) teardown (for isolation), diagnostic collection *(WHAT BROKE NOW??)*, and last but not least result processing (what does this wall of JSON mean?)

So now all of that lives in [`kroxylicious-openmessaging-benchmarks`](https://github.com/kroxylicious/kroxylicious/tree/main/kroxylicious-openmessaging-benchmarks) in the main tree *(mono repo FTW)*.

So we have a tool and we think Kroxylicious is fast — but how do we turn that into something we can actually show management? "Fast" is shorthand for "low impact", and the impact of a proxy shows up along two dimensions:

- **Latency**: how much extra time does this additional hop add?
- **Throughput**: how much does routing traffic through the proxy cost my topic throughput?

Two dimensions, two questions — and it turns out they need quite different experimental approaches to answer.

**Rate sweep — where does latency start to bite?**
`scripts/rate-sweep.sh` holds the connection count fixed and steps the producer rate up in fixed increments, letting the cluster stabilise at each step. We defined saturation as the sustained throughput dropping more than 5% below the target rate. The rate sweep tells you where the cliff edge is and what latency looks like as you approach it.

**Connection sweep — is the ceiling per-connection or per-pod?**
`scripts/connection-sweep.sh` holds the per-producer rate fixed and steps up the number of producers (1, 2, 4, 8, 16 by default) — consumers scale to match. This tells you the aggregate throughput ceiling of a single proxy pod *(need more? help out!)*: the point where adding more connections stops increasing total throughput.

Both sweeps use `scripts/run-benchmark.sh` under the hood, which:

1. Deploys the Helm chart for the requested scenario
2. Waits for the OMB Job to complete
3. Collects results: OMB JSON, a JFR recording, an async-profiler flamegraph, and a Prometheus metrics snapshot
4. Tears down

The `--skip-deploy` flag lets you re-run a probe against an already-deployed cluster — both sweep scripts deploy once and probe many times.

### Banishing click-ops

Coming from Red Hat, my instinct is to reach for an operator — but operators are great at managing cohesive things. The stack we needed to deploy is anything but cohesive: an OMB coordinator, worker pods, a Strimzi-managed Kafka cluster, the Kroxylicious operator, the proxy itself, and HashiCorp Vault for the KMS. It's less "managed application" and more *all your ~~base~~ CRs belong to us*.

We could have dumped some YAML in a directory and used `kustomize apply`. But I am lazy, and that's a lot of typing. Helm handles this beautifully — one chart, scenario-specific overrides, and a single command to deploy the whole thing. Scenario-specific configuration lives in `helm/kroxylicious-benchmark/scenarios/` as YAML overrides — the base chart stays stable and each scenario adds only what it needs:

| Scenario file | What it deploys |
|---------------|-----------------|
| `baseline-values.yaml` | Direct Kafka, no proxy |
| `proxy-no-filters-values.yaml` | Proxy with no user filters |
| `encryption-values.yaml` | Proxy with AES-256-GCM encryption and Vault |
| `rate-sweep-values.yaml` | Extended run profiles for sweep experiments |

If you have your own KMS — and you will run this on your own infrastructure, right?! — you can swap Vault out without touching the base chart.

### JSON always comes in megabytes

Each benchmark run produces a blob of structured JSON. Useful in principle; a wall of noise in practice. Three [JBang](https://www.jbang.dev/)-runnable Java programs *(I'm a dyed in the wool java dev, sue me)* pull out the signal:

- **`RunMetadata`**: captures the run context — git commit, timestamp, cluster node specs (architecture, CPU, RAM), and on OpenShift, NIC speed read from the host via the MachineConfigDaemon pod. Generates `run-metadata.json` alongside each result so you can always tell what conditions produced a number. This is what makes run-to-run comparisons meaningful — and when a run takes 12 hours, trust me, you don't want to re-run it without good reason.
- **`ResultComparator`**: answers "did this change hurt?" — reads two scenario result directories and produces a markdown comparison table. Baseline vs encryption is the obvious use, but the tool is generic. Already running a proxy? proxy-no-filters vs encryption tells you the cost of the filter itself, not the proxy hop. Building your own filter? That's your comparison — measure the chain with and without it.
- **`ResultSummariser`**: answers "where does it fall over?" — reads a rate-sweep result directory and prints a summary table: target rate, achieved rate, p99, and whether the probe saturated. Where ResultComparator compares two scenarios at a fixed rate, ResultSummariser tracks one scenario across a range of rates.

Getting NIC speed from a Kubernetes node turned out to be non-trivial — you need host filesystem access to read `/sys/class/net/<iface>/speed`. On OpenShift, the MachineConfigDaemon pods mount the host at `/rootfs`, so we `kubectl exec` into the MCD pod and `chroot /rootfs` to read the speed file without creating any new privileged resources. Fiddly, but worth it — knowing your NIC speed is the difference between "the ceiling was the NIC" and "the ceiling wasn't the NIC".

## Workload design

Benchmarks are artificial constructs. Your traffic patterns are never stable — message sizes vary, topic counts grow, producers burst — so there's always a tension between numbers that are *representative* and numbers that are actually *repeatable*. We leaned towards repeatable.

The primary workload makes Kafka experts wince *(I had to squirm to type it)* — **1 topic, 1 partition, 1 KB messages**. Concentrating everything onto a single TopicPartition means we hit the limits earlier, at lower absolute volumes, which makes the proxy's contribution easier to isolate. Isolating the proxy is, after all, the goal.

But Kafka is often described as a distributed append-only log, and we can't ignore the word "distributed" when it comes to latency. With RF=1, the proxy doubles the sequential hops in the critical path: one becomes two. That's not wrong, but it's not a fair picture either — nobody runs RF=1 in production. With RF=3, the leader waits for ISR acknowledgements before confirming the produce, so there's already replication latency in the critical path. The proxy adds a real, sequential hop — we're not trying to bury that — but it lands alongside a cost that's already there. One extra hop on top of a multi-hop round trip is a different picture from doubling a single-hop one. Three brokers, hot partition replicated across all of them.

But we didn't abandon representative entirely. The multi-topic runs (10 and 100 topics) are the reconnection point: load spread across more topics, closer to what production actually looks like, at rates well below any saturation point. You're measuring the proxy's baseline tax — the cost you always pay, not just the cost when you're pushing hard. It holds.


That covers the first dimension — the proxy's latency tax at normal load. For the second, throughput, the question is: how much does routing through the proxy reduce your maximum sustainable rate? That needs a different approach. We used rate sweeps: hold the connection count fixed, step the rate up incrementally, and watch what happens. Below the ceiling, achieved throughput tracks the target — the system keeps up. Above it, it can't, and falls behind. The point where achieved throughput diverges from the target rate — where we defined that as dropping below 95% — is the saturation point. That's the knee of the curve, and that's what we were hunting.

## False summit

The rate-sweep result was in: the encryption scenario hit a ceiling on our original cluster at around 37k msg/s. Summit reached.

Except — the proxy had spare CPU cycles. Not a little: meaningful headroom. If the proxy isn't CPU-saturated, whatever we hit isn't the proxy's ceiling.

**Was it the NIC?** At 37k msg/s and 1 KB messages, produce traffic alone is 37 MB/s. Add RF=3 replication: the leader ships two copies outbound, ~74 MB/s more. 111 MB/s total — fine for 10 GbE, obviously broken for 1 GbE. If the NICs had been gigabit, replication traffic would have saturated them long before we got to 37k. Network eliminated.

**Was it the proxy pod, or just one connection?** The rate sweep runs with a single producer. We ran four at the same per-producer rate. Aggregate throughput climbed higher than one producer alone could push — the pod had headroom the single connection wasn't using. We checked proxy metrics: back pressure was minimal. The proxy wasn't the constraint. Whatever was limiting one connection, it wasn't us.

### We tried anti-affinity

Then a curveball: could it be node saturation? The original cluster had three worker nodes — and three Kafka brokers. Strimzi, being sensible, spreads brokers evenly: one per node. If the proxy had landed on the same node as a busy broker, that node could be the bottleneck rather than the proxy pod itself.

We added a hard anti-affinity rule to keep the proxy off broker nodes. It wouldn't schedule.

The penny drops: three worker nodes, three brokers, one per node — there is nowhere for the proxy to go that isn't already co-located with a broker. Obvious in hindsight. We needed a bigger cluster.

We provisioned one: five workers, three masters, 16 vCPU per node.

### The baseline shock

Baseline first. Direct Kafka, no proxy.

~17,000 msg/s. The original cluster had been sustaining ~50,000.

The proxy wasn't in the picture. We checked the obvious suspects: disk I/O — fine, local and unsaturated. OMB worker scaling — correct. Broker CPU: ~1.2 vCPU. Nothing was at a limit.

The answer was in the pipeline arithmetic. A Kafka producer has a maximum number of in-flight requests — batches sent but not yet acknowledged. With real round-trip times between nodes, that in-flight window bounds throughput. We measured: 0.87 ms between worker nodes, with three replication hops before the leader can confirm a produce at RF=3 — roughly 3–4 ms total. Five in-flight requests across that round trip gives a ceiling that matched ~17k msg/s almost exactly.

On the original cluster, those nodes were almost certainly co-located on the same physical host. Inter-node RTTs at that scale are sub-millisecond — effectively free. The original cluster's 50k baseline wasn't what a 3-broker Kafka cluster does. It was what a 3-broker Kafka cluster does when the network is a memcpy.

The new cluster was genuinely distributed. Real latency, real pipeline limits, real Kafka — and the cluster we used for everything from here.

*(The ~37k ceiling is the only figure in this post from the original cluster. Everything that follows — the coefficient, the CPU sweep, the prediction — was measured on the new cluster. The physics are part of what makes those numbers honest.)*

Another penny dropped. We'd had the same scheduling problem with OMB all along. The producer and consumer worker pods were landing on broker nodes — and when pods share a node, the SDN detects that traffic doesn't need to leave the node and bypasses the NIC entirely. The producers and consumers weren't paying for network transit at all.

The proxy pod was on a different node, but on a 3-node cluster where every node already had a broker, the odds of those nodes sharing a physical host on Fyre were high. Almost certainly getting the same benefit, just one layer down.

### Now push harder

The new cluster had an honest baseline — but RF=3 pipeline limits meant we couldn't push a single topic past ~17k msg/s. There was no room to find the proxy's CPU ceiling when Kafka's pipeline hits the wall first.

RF=1, 10 topics. With no replication hops, the round-trip drops to producer→leader only: 0.87 ms. Spread across 10 partitions, no single one becomes the bottleneck before the proxy does. We validated the workload with the passthrough proxy: throughput scaled well past anything encryption constrains. The ceiling we were now measuring was proxy CPU.

### How much more?

The RF=1 10-topic workload spread load across partitions. At 1000m, the run tells us: safe at 80k msg/s (91 ms p99), saturating at around 126k. The coefficient comes from JFR CPU data across the non-saturated probes:

```
Measured: 9.7 mc per MB/s of total proxy traffic (±6.6 stdev, n=4 non-saturated probes)
→ operator formula: 10 mc per MB/s of total proxy traffic
→ for 1:1 produce:consume at 1 KB: 20 mc per MB/s of produce throughput
```

I was proudly showing off some early numbers — baseline vs proxy, looking good — when one of the computer science PhDs on the team asked, "is the difference real?" Best answer I could come up with at the time: "Good question." So I went and added statistical significance testing.

`check-significance.sh` runs Mann-Whitney U at p < 0.05, comparing per-window p99 latency samples between baseline and candidate at each rate step. OMB slices the test phase into time windows and records a p99 per window — ~30 samples per 5-minute run — so MWU has enough data to distinguish real signal from noise. It's not perfect: those per-window samples aren't entirely uncorrelated — a GC pause can drag multiple adjacent windows — but it gives a principled answer to "is this overhead real, or am I chasing noise?"

The coefficient is a different matter. It's derived from JFR CPU data across n=4 non-saturated probes; the ±6.6 stdev reflects measurement noise, not a tested confidence interval. It holds at 1, 2, and 4 cores — the linear scaling claim is consistent — but its validity across message sizes or workload shapes is untested.

The mechanism: `cpu: 1000m → availableProcessors()=1 → one Netty event loop thread`. At 4000m that's four threads, each handling its share of connections in parallel. If the ceiling scales linearly with thread count, a 4-core pod should handle roughly four times as much. We ran it.

| CPU limit | Rate | p99 | Verdict |
|-----------|------|-----|---------|
| 1000m | 80k msg/s | 91 ms | Comfortable |
| 1000m | ~126k msg/s | — | Saturating |
| 4000m | 160k msg/s | 247 ms | Comfortable |
| 4000m | 321k msg/s | 1,706 ms | Elevated |
| 4000m | above 321k | — | Saturated |

At 4000m: comfortable at 160k (p99: 247 ms), elevated at 321k (p99: 1,706 ms). Above that — 64 producers matched 32-producer throughput: ceiling reached. The proxy isn't hitting a fixed architectural wall — it's hitting a CPU budget wall, and that wall moves when you give it more CPU.

### The prediction

One validated scaling point isn't a sizing model. The coefficient predicts that 2-core should sustain well past 80k msg/s and not saturate until well above 160k. We ran 2-core next.

| Rate       | p99     | Verdict                                          |
|------------|---------|--------------------------------------------------|
| 80k msg/s  | 850 ms  | Comfortable                                      |
| 160k msg/s | 720 ms  | Sustaining — not yet saturated                   |

At 160k across 10 partitions, each partition carries 16k msg/s — well within the budget of a single Netty thread. The 2-core saturation point sits above 160k; the model is consistent.

Setting `requests` equal to `limits` makes this practical: a pod that can burst above its CPU limit introduces headroom uncertainty that breaks the model. Fix the CPU budget; fix the ceiling.

## The flamegraph: where the CPU actually goes

I care deeply that the proxy does as little work as possible on the hot path. Optimization is often less about swapping algorithms — if you only ever have five items, who cares how you sort them — and more about realising what work not to do, or finding a better time to do it. [Amdahl's law](https://en.wikipedia.org/wiki/Amdahl%27s_law) governs this: the maximum speedup you can get from optimizing a component is bounded by how much of total execution time that component actually owns. If the proxy accounts for 2% of CPU, you can't optimize your way to a 10% win — not there.

That framing is exactly why flamegraphs matter to me. Not as a debugging tool, but as a way of seeing the shape of the work. I was also hoping to tell a fuller story here — profiles across the full rate sweep, watching the mix shift as the proxy approaches saturation. Getting stable, reproducible numbers turned out to be harder than expected, and the bugs described in the next section cost us more runs than I'd like. So these are two snapshots at a single rate, not the sweep-correlated picture I had in mind. Still enough to see where the CPU goes. I hope to revisit this properly in the future — but right now the proxy's performance is good enough that I'm focused on functionality, and the benchmarking harness itself still has room to mature.

We captured CPU profiles using async-profiler attached to the proxy JVM via `jcmd JVMTI.agent_load`, during the steady-state measurement phase. These are self-time percentages — where the CPU is actually spending cycles, not inclusive call-tree time.

The flamegraphs below are fully interactive: hover over a frame to see its name and percentage, click to zoom in, Ctrl+F to search. Scroll within the frame to explore the full stack depth.

### No-filter proxy

<figure>
<iframe src="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/proxy-no-filters-cpu-profile.html' | relative_url }}"
        width="100%" height="600"
        style="border: 1px solid #ddd; border-radius: 4px;"
        title="CPU flamegraph: no-filter proxy at FIXME msg/s">
</iframe>
<figcaption>CPU flamegraph — passthrough proxy (no filters), FIXME msg/s, 1 topic, 1 KB messages. <a href="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/proxy-no-filters-cpu-profile.html' | relative_url }}" target="_blank">Open full screen ↗</a></figcaption>
</figure>

| Category | CPU share |
|----------|-----------|
| Syscalls (send/recv) | 59.2% |
| Native/VM | 16.7% |
| Netty I/O | 10.5% |
| Memory operations | 4.7% |
| JDK libraries | 2.9% |
| Kroxylicious proxy | 1.4% |
| GC | 0.1% |

The proxy is overwhelmingly I/O-bound. 59% of CPU is in `send`/`recv` syscalls — the inherent cost of maintaining two TCP connections (client→proxy, proxy→Kafka) with data flowing through the JVM. The proxy itself accounts for 1.4% — and understanding *why* that number is so small is the interesting part.

Kroxylicious decodes Kafka RPCs selectively: each filter declares which API keys it cares about, and the proxy only deserialises messages that at least one filter needs. Even in the no-filter scenario, the default infrastructure filters are doing genuine L7 work — broker address rewriting, API version negotiation, topic name caching — which means metadata, FindCoordinator, and API version exchanges are fully decoded. But the high-volume produce and consume traffic? The decode predicate skips full deserialisation for those entirely, passing them through at close to L4 speed.

The 1.4% is the cost of a proxy that is *selectively* L7: doing real Kafka protocol work where it matters, and treating the hot path like a TCP relay where it doesn't. That's not a side-effect — it's what the decode predicate design is for, and this flamegraph validates it.

### Encryption proxy (same FIXME msg/s rate)

<figure>
<iframe src="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/encryption-cpu-profile-FIXME.html' | relative_url }}"
        width="100%" height="600"
        style="border: 1px solid #ddd; border-radius: 4px;"
        title="CPU flamegraph: encryption proxy at FIXME msg/s">
</iframe>
<figcaption>CPU flamegraph — encryption proxy (AES-256-GCM), FIXME msg/s, 1 topic, 1 KB messages. <a href="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/encryption-cpu-profile-FIXME.html' | relative_url }}" target="_blank">Open full screen ↗</a></figcaption>
</figure>

| Category | No-filters | Encryption | Delta |
|----------|-----------|------------|-------|
| Syscalls (send/recv) | 59.2% | 23.5% | −35.7%* |
| Native/VM | 16.7% | 18.9% | +2.2% |
| JCA/AES-GCM crypto | 0.0% | 11.3% | **+11.3%** |
| Memory operations | 4.7% | 10.4% | **+5.8%** |
| JDK libraries | 2.9% | 9.3% | **+6.4%** |
| GC / JVM housekeeping | 0.1% | 5.0% | **+4.9%** |
| Netty I/O | 10.5% | 5.1% | −5.4%* |
| Kafka protocol re-encoding | 0.4% | 3.5% | **+3.1%** |
| Kroxylicious encryption filter | 0.0% | 2.0% | **+2.0%** |

*\* Send/recv and Netty I/O appear to shrink as a percentage share because encryption adds CPU work that grows the total pie. The absolute I/O cost is similar in both scenarios.*

The direct crypto cost is 13.3% (11.3% AES-GCM + 2.0% Kroxylicious filter logic). But encryption adds indirect costs too:

- **Buffer management (+5.8%)**: encrypted records need to be read into buffers, encrypted, and written to new buffers — more allocation, more copying
- **GC pressure (+4.9%)**: more short-lived objects from encryption buffers and crypto operations
- **JDK security infrastructure (+6.4%)**: security provider lookups, key spec handling, parameter generation
- **Kafka protocol re-encoding (+3.1%)**: encrypted records are different sizes and must be re-serialised into Kafka protocol format

Total additional CPU: ~33%. This aligns closely with the ~26% throughput reduction.

If you wanted to optimise this, the highest-impact areas would be: reducing buffer copies (encrypt in-place or use composite buffers), pooling encryption buffers to reduce GC pressure, and caching `Cipher` instances to reduce per-record JDK security overhead.

There are wins inside the proxy we haven't chased yet — serialisation and deserialisation we could avoid, buffer copies imposed by how memory records are structured. Some would be straightforward; others would require rethinking how Kafka records are modelled in memory. We haven't gone after them. But to put it plainly: we can optimise all we like inside the proxy, and we're still not going to make AES faster.

## Bugs we found in our own tooling

During the 4-producer rate sweep, we noticed that JFR recordings and flamegraphs from probes 2 onwards all looked identical to probe 1. They were stale copies. Three bugs.

**Bug 1 — wrong JFR settings**: When restarting JFR for a subsequent probe in `--skip-deploy` mode, the script was using `settings=default` instead of `settings=profile`. The default profile omits I/O events including `jdk.NetworkUtilization` — the event we were using to read network throughput from JFR. Fixed to always use `settings=profile`.

**Bug 2 — async-profiler not restarted**: The restart block restarted JFR but never restarted async-profiler. All probes after the first had a flamegraph from probe 1 only.

**Bug 3 — wrong guard variable**: The async-profiler restart was guarded by checking `AGENT_LIB` (the path to the native library). `AGENT_LIB` is always set when the library exists on the image — even when profiling was intentionally skipped on clusters where the `Unconfined` seccomp profile couldn't be applied. The correct guard is `ASYNC_PROFILER_FLAGS`, which is only set when the seccomp patch was successfully applied.

Spotting these required noticing that two different probe flamegraphs were pixel-for-pixel identical, then working back through the restart logic. The lesson: when reusing a deployed cluster across multiple probes, validate that diagnostic collection is actually running fresh for each one.

## Run it yourself

We're an open source project — we share our workings. The raw OMB result JSON, JFR recordings, and flamegraph files that back this post are available [TODO: link to raw data]. If you want to verify the numbers, reproduce the analysis, or compare against your own runs, everything you need is there.

If you want to run it against your own cluster, everything is in `kroxylicious-openmessaging-benchmarks/` in the [main Kroxylicious repository](https://github.com/kroxylicious/kroxylicious). See `QUICKSTART.md` for step-by-step instructions. You'll need a Kubernetes or OpenShift cluster, the Kroxylicious operator installed, and Helm 3. Minikube works for local runs — the quickstart covers recommended CPU and memory settings.

I got so bored re-evaluating everything as I explored anti-affinity that I even scripted the whole exercise for this post — but brace yourself, it has about a 18 hour runtime. tmux and a control node or jump host are your friends here. The [full blog post script](https://gist.github.com/SamBarker/19fd06ac9a8614cc6be89b76a90e006a) is available as a gist if you want to reproduce the exact run.

```bash
# Run a baseline vs encryption comparison
./scripts/run-benchmark.sh --scenario baseline
./scripts/run-benchmark.sh --scenario encryption

# Compare results
jbang src/main/java/io/kroxylicious/benchmarks/results/ResultComparator.java \
  results/baseline results/encryption
```

## What's still open

The coefficient is validated at 1, 2, and 4 cores for 1 KB messages. Known gaps:

- **Message size variation**: larger messages should show lower overhead as a percentage; smaller messages may show higher. 1 KB is a reasonable middle ground but not the whole picture.
- **Horizontal scaling**: multiple proxy pods haven't been measured; linear scaling is expected but not confirmed.
- **Multi-pass sweeps**: each rate point was measured once. Running each probe three times and taking the median would give tighter bounds in the saturation transition zone.

The operator-facing sizing reference and all the key tables are in `SIZING-GUIDE.md` in the benchmarks directory.
