---
layout: post
title:  "How hard can it be??? Maxing out a Kroxylicious instance"
date:   2026-05-28 00:00:00 +0000
author: "Sam Barker"
author_url: "https://github.com/SamBarker"
categories: benchmarking performance engineering
---

How hard can it be? We started with a laptop, a codebase, and a lot of confidence it was fast. We ended up with a benchmark harness, a six-node cluster, and a much more nuanced answer.

Harder than expected. More interesting too.

We gave everyone [the numbers]({% post_url 2026-05-21-benchmarking-the-proxy %}) in a bland, but slide worthy way, already. This one is the engineering story: how we built the harness, what the flamegraphs actually show, the workload design choices that changed the answers, and the bugs we found in our own tooling.

## Why not Kafka's own tools?

Kafka ships with `kafka-producer-perf-test` and `kafka-consumer-perf-test`. We'd used them before. The problems:

- **Too noisy**: individual runs produced widely varying results depending on JVM warm-up, scheduling jitter, and GC behaviour. Results were hard to trust and harder to compare across scenarios.
- **Producer-only view**: `kafka-producer-perf-test` gives you publish latency, but nothing about the consumer side. You can't see end-to-end latency — which is something operators actually care about.
- **Awkward to sweep**: running parametric rate sweeps requires scripting around these tools, and comparing results across scenarios requires manual work.
- Coordinated omission: under load, kafka-producer-perf-test only measures requests it actually sends! So when things start loading up and applying back pressure the send rate drops and the latency stays looking nice and healthy. Only it's not healthy in reality, things are queuing up in your producer. 

And critically, it's never heard of Kroxylicious... You have though, you're here!

[OpenMessaging Benchmark (OMB)](https://github.com/openmessaging/benchmark) is a better fit. It's an industry-standard tool used by Confluent, the Pulsar team, and others for their published performance comparisons - so who am I to argue? OMB coordinates producers and consumers across separate worker pods, runs a configurable warmup phase before taking measurements, takes its latency tracking seriously by tracking coordinated omission, and outputs structured JSON that's straightforward to process programmatically. What's not to like? 

Using OMB also means our methodology is directly comparable to other published Kafka benchmarks. The numbers aren't comparable of course it's not the same hardware, network conditions or phase of the moon. 

## What we built on top of OMB

So we just fire up OMB and get some numbers, right? Errr no. OMB just does the measurement part. I work really hard at being lazy, I hate clicking things with a mouse and I knew these tests needed to be repeatable. So we scripted deployment (of all the things) teardown (for isolation), diagnostic collection (WHAT BROKE NOW??), and last but not least result processing (what does this wall of JSON mean?)

So now all of that lives in [`kroxylicious-openmessaging-benchmarks`](https://github.com/kroxylicious/kroxylicious/tree/main/kroxylicious-openmessaging-benchmarks) in the main tree (mono repo FTW).

So we have a tool and we think Kroxylicious is fast — but how do we turn that into something we can actually show management? "Fast" is shorthand for "low impact", and the impact of a proxy shows up along two dimensions:

- **Latency**: how much extra time does this additional hop add?
- **Throughput**: how much does routing traffic through the proxy cost my topic throughput?

Two dimensions, two questions — and it turns out they need quite different experimental approaches to answer.

**Rate sweep — where does latency start to bite?**
`scripts/rate-sweep.sh` holds the connection count fixed and steps the producer rate up in fixed increments, letting the cluster stabilise at each step. We defined saturation as the sustained throughput dropping more than 5% below the target rate. The rate sweep tells you where the cliff edge is and what latency looks like as you approach it.

**Connection sweep — is the ceiling per-connection or per-pod?**
`scripts/connection-sweep.sh` holds the per-producer rate fixed and steps up the number of producers (1, 2, 4, 8, 16 by default) — consumers scale to match. This tells you the aggregate throughput ceiling of a single proxy pod (need more? help out!): the point where adding more connections stops increasing total throughput.

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

Each benchmark run produces a blob of structured JSON. Useful in principle; a wall of noise in practice. Three [JBang](https://www.jbang.dev/)-runnable Java programs (I'm a died in the wool java dev, sue me) pull out the signal:

- **`RunMetadata`**: captures the run context — git commit, timestamp, cluster node specs (architecture, CPU, RAM), and on OpenShift, NIC speed read from the host via the MachineConfigDaemon pod. Generates `run-metadata.json` alongside each result so you can always tell what conditions produced a number. This is what makes run-to-run comparisons meaningful — and when a run takes 12 hours, trust me, you don't want to re-run it without good reason.
- **`ResultComparator`**: answers "did this change hurt?" — reads two scenario result directories and produces a markdown comparison table. Baseline vs encryption is the obvious use, but the tool is generic. Already running a proxy? proxy-no-filters vs encryption tells you the cost of the filter itself, not the proxy hop. Building your own filter? That's your comparison — measure the chain with and without it.
- **`ResultSummariser`**: answers "where does it fall over?" — reads a rate-sweep result directory and prints a summary table: target rate, achieved rate, p99, and whether the probe saturated. Where ResultComparator compares two scenarios at a fixed rate, ResultSummariser tracks one scenario across a range of rates.

Getting NIC speed from a Kubernetes node turned out to be non-trivial — you need host filesystem access to read `/sys/class/net/<iface>/speed`. On OpenShift, the MachineConfigDaemon pods mount the host at `/rootfs`, so we `kubectl exec` into the MCD pod and `chroot /rootfs` to read the speed file without creating any new privileged resources. Fiddly, but worth it — knowing your NIC speed is the difference between "the ceiling was the NIC" and "the ceiling wasn't the NIC".

## Workload design

Benchmarks are artificial constructs. Your traffic patterns are never stable — message sizes vary, topic counts grow, producers burst — so there's always a tension between numbers that are *representative* and numbers that are actually *repeatable*. We leaned towards repeatable.

The primary workload will make Kafka experts wince *(I had to squirm to type it)* — **1 topic, 1 partition, 1 KB messages**. Concentrating everything onto a single TopicPartition means we hit the limits earlier, at lower absolute volumes, which makes the proxy's contribution easier to isolate. Isolating the proxy is, after all, the goal.

But Kafka is often described as a distributed append-only log, and we can't ignore the word "distributed" when it comes to latency. With RF=1, the proxy doubles the sequential hops in the critical path: one becomes two. That's not wrong, but it's not a fair picture either — nobody runs RF=1 in production. With RF=3, the leader waits for ISR acknowledgements before confirming the produce, so there's already replication latency in the critical path. The proxy adds a real, sequential hop — we're not trying to bury that — but it lands alongside a cost that's already there. One extra hop on top of a multi-hop round trip is a different picture from doubling a single-hop one. Three brokers, hot partition replicated across all of them.

We leaned towards repeatable — but we didn't abandon representative entirely. The multi-topic runs (10 and 100 topics) are the reconnection point: load spread across more topics, closer to what production actually looks like, at rates well below any saturation point. You're measuring the proxy's baseline tax — the cost you always pay, not just the cost when you're pushing hard. It holds.


That covers the first dimension — the proxy's latency tax at normal load. For the second, throughput, the question is: how much does routing through the proxy reduce your maximum sustainable rate? That needs a different approach. We used rate sweeps: hold the connection count fixed, step the rate up incrementally, and watch what happens. Below the ceiling, achieved throughput tracks the target — the system keeps up. Above it, it can't, and falls behind. The point where achieved throughput diverges from the target rate — where we defined that as dropping below 95% — is the saturation point. That's the knee of the curve, and that's what we were hunting.

## The flamegraph: where the CPU actually goes

We captured CPU profiles using async-profiler attached to the proxy JVM via `jcmd JVMTI.agent_load`, during the steady-state measurement phase at 36,000 msg/s. These are self-time percentages — where the CPU is actually spending cycles, not inclusive call-tree time.

The flamegraphs below are fully interactive: hover over a frame to see its name and percentage, click to zoom in, Ctrl+F to search. Scroll within the frame to explore the full stack depth.

### No-filter proxy

<figure>
<iframe src="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/proxy-no-filters-cpu-profile.html' | relative_url }}"
        width="100%" height="600"
        style="border: 1px solid #ddd; border-radius: 4px;"
        title="CPU flamegraph: no-filter proxy at 36,000 msg/s">
</iframe>
<figcaption>CPU flamegraph — passthrough proxy (no filters), 36,000 msg/s, 1 topic, 1 KB messages. <a href="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/proxy-no-filters-cpu-profile.html' | relative_url }}" target="_blank">Open full screen ↗</a></figcaption>
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

### Encryption proxy (same 36,000 msg/s rate)

<figure>
<iframe src="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/encryption-cpu-profile-36k.html' | relative_url }}"
        width="100%" height="600"
        style="border: 1px solid #ddd; border-radius: 4px;"
        title="CPU flamegraph: encryption proxy at 36,000 msg/s">
</iframe>
<figcaption>CPU flamegraph — encryption proxy (AES-256-GCM), 36,000 msg/s, 1 topic, 1 KB messages. <a href="{{ '/assets/blog/flamegraphs/benchmarking-the-proxy/encryption-cpu-profile-36k.html' | relative_url }}" target="_blank">Open full screen ↗</a></figcaption>
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

## Following the ceiling

We had a rate-sweep result. On our test cluster, the encryption scenario hit a ceiling — the proxy was saturating around 37k msg/s. We'd maxed out the proxy, right?

Well. The proxy had spare CPU cycles.

That's interesting. If the proxy isn't CPU-saturated, then whatever we hit isn't the proxy's ceiling — it's something else's. Time to work out what.

### What were we actually hitting?

Our initial sweeps ran with replication factor 3 — the standard production default, and for good reason. But RF=3 means every message the Kafka leader receives gets replicated to 2 followers. At 37k msg/s with 1 KB messages, that's ~111 MB/s of replication traffic outbound from the leader alone. The Fyre nodes have 10 GbE NICs so the network wasn't saturated, but RF=3 creates a real per-partition I/O ceiling on the Kafka leader — and it sits right around where we were measuring.

The ceiling on our hardware wasn't the proxy. It was Kafka.

The fix: RF=1, 10-topic workload. Drop replication overhead; spread load across 10 partitions so no single partition hits its ceiling. We validated it with the passthrough proxy: at 160k msg/s total the proxy matched baseline, and the sweep scaled past 640k before hitting some uninvestigated ceiling far above where encryption constrains anything.

### We maxed out the proxy, right?

With a clean workload that actually isolates proxy CPU, we looked again. The connection sweep answered the question: with 4 producers at a fixed per-producer rate, aggregate throughput climbed well past the single-producer ceiling — and proxy CPU still had headroom. Kafka's partition ran out first.

So the single-producer ceiling on our cluster isn't the pod ceiling. It's what one connection could push on that hardware. The proxy had more to give.

### How much more?

We swept the CPU limit: 1000m, 2000m, 4000m. The throughput ceiling scaled linearly with the CPU budget:

| CPU limit | Encryption ceiling |
|-----------|-------------------|
| 1000m | ~40k msg/s |
| 2000m | ~80k msg/s |
| 4000m | ~160k msg/s |

At 4000m: comfortable at 160k msg/s (p99: 447 ms), catastrophic at 320k (p99: 537,000 ms). The proxy isn't hitting a fixed architectural wall — it's hitting a CPU budget wall, and that wall moves when you give it more CPU.

One thing we noticed along the way: the proxy ran 4 Netty event loop threads regardless of CPU limit. The throughput scaling isn't explained by thread count changing — it doesn't. What changes is the CPU time budget available to those threads. The relationship between CPU limit, thread scheduling, and throughput ceiling is more subtle than a simple thread-count model; what we can say empirically is that throughput scales linearly with the CPU limit.

Deriving the coefficient: at 4000m and 160k msg/s with 1 KB messages —

```
160k msg/s × 1 KB = 160 MB/s produce throughput
With matched consumer load: 160 MB/s encrypt + 160 MB/s decrypt
→ 4000 mc / 320 MB/s bidirectional ≈ 12–13 mc per MB/s bidirectional
→ equivalently: 4000 mc / 160 MB/s produce ≈ 25 mc per MB/s produce
```

We measured the coefficient at mid-utilisation (80k msg/s, 2000m) at ~10 mc/MB/s bidirectional — lower, because fixed per-connection overhead gets amortised at higher load. The operator-facing formula uses 20 mc/MB/s of produce throughput, which sits between mid-utilisation and saturation and gives inherent conservatism.

### The prediction

Rather than just report the results, we used the 1-core ceiling to make a falsifiable prediction: if the ceiling scales linearly with CPU budget, a 2-core pod should saturate at ~80k msg/s.

The 2-core sweep:

| Rate | p99 | Verdict |
|------|-----|---------|
| 40k msg/s | 626 ms | Comfortable |
| 80k msg/s | 1,660 ms | Elevated — right at predicted ceiling |
| 160k msg/s | 175,277 ms | Catastrophic |

The prediction held. The ceiling is real, linear, and predictable — which is exactly what you want from a sizing model.

Setting `requests` equal to `limits` is what makes this practical: a pod that can burst above its CPU limit introduces headroom uncertainty that breaks the model. With `requests == limits`, the CPU budget is fixed, the ceiling is fixed, and your capacity planning can rely on the coefficient.

## Bugs we found in our own tooling

During the 4-producer rate sweep, we noticed that JFR recordings and flamegraphs from probes 2 onwards all looked identical to probe 1. They were stale copies. Three bugs.

**Bug 1 — wrong JFR settings**: When restarting JFR for a subsequent probe in `--skip-deploy` mode, the script was using `settings=default` instead of `settings=profile`. The default profile omits I/O events including `jdk.NetworkUtilization` — the event we were using to read network throughput from JFR. Fixed to always use `settings=profile`.

**Bug 2 — async-profiler not restarted**: The restart block restarted JFR but never restarted async-profiler. All probes after the first had a flamegraph from probe 1 only.

**Bug 3 — wrong guard variable**: The async-profiler restart was guarded by checking `AGENT_LIB` (the path to the native library). `AGENT_LIB` is always set when the library exists on the image — even when profiling was intentionally skipped on clusters where the `Unconfined` seccomp profile couldn't be applied. The correct guard is `ASYNC_PROFILER_FLAGS`, which is only set when the seccomp patch was successfully applied.

Spotting these required noticing that two different probe flamegraphs were pixel-for-pixel identical, then working back through the restart logic. The lesson: when reusing a deployed cluster across multiple probes, validate that diagnostic collection is actually running fresh for each one.

## Run it yourself

Everything is in `kroxylicious-openmessaging-benchmarks/` in the [main Kroxylicious repository](https://github.com/kroxylicious/kroxylicious). See `QUICKSTART.md` for step-by-step instructions. You'll need a Kubernetes or OpenShift cluster, the Kroxylicious operator installed, and Helm 3. Minikube works for local runs — the quickstart covers recommended CPU and memory settings.

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
