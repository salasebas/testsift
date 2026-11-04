# Current-engine costs and executable scale workloads

Measured on 2026-11-04 against the extracted engine at
`e225fbf240f9828e922aa48f8fd59632dfeab4b0`. The imported dataset from
[PR #18](https://github.com/salasebas/testsift/pull/18) remains unchanged.

This report covers controlled Ruby and Rails fixtures and generated executable
workloads. It does not measure RuboCop, Mastodon, or Discourse. The OSS runner in
[#31](https://github.com/salasebas/testsift/issues/31) and the real-project
measurements added to [#20](https://github.com/salasebas/testsift/issues/20) remain
outstanding. These results alone do not complete #20 or establish production-project
performance.

The current Rails fixture takes 11.372 seconds with line reports and
30.286 seconds with branch reports at clean command p50. Warm selection skips
every example but still takes 2.072 seconds with lines. A JSON input change selects
16 of 308 examples; the source edit selects all 308.

Repeated snapshots remain the first experiment. In the Rails branch profile,
snapshot production takes 18.836 of 24.199 seconds, or
77.84%. Graph and index operations take 0.0157 seconds,
0.06% of that command. A graph port cannot meet a 10% complete-command
improvement target on this named full-run workload by eliminating that component.
Larger warm-cache workloads must be evaluated separately.

These are exploratory measurements, not a native adoption result. Each clean
cell has three complete-command repetitions. The main campaigns add one allocator
observation; separate timing passes add one profile without allocator sampling.
Startup cells have no profile. The two optional backend campaigns use timing
profiles directly. The diagnostic timing pass has no clean repetitions.
Nearest-rank p95 is the largest clean sample. Host contention is visible in the
distributions. Use the driver's default 20 clean and three profile repetitions
on a quiet host before accepting close comparisons or claiming stable tail gains.

## Protocol and provenance

The shared Linux desktop has an Intel Core i7-1355U, 12 allowed logical CPUs,
and 40,715,980 KiB visible RAM. The kernel is `6.19.10-300.fc44.x86_64`.
MRI is 3.3.10, revision `343ea05002`. The probe compiler is GCC 16.2.1,
Red Hat build `16.2.1-2`. The experiment changes no CPU governor and drops no OS
page cache. A recorded load observation was 9.64 on this 12-logical-CPU host.
[host.json](host.json) retains OS release, glibc, tool versions, Ruby binary hash,
configure arguments, observed load, and governors.

Campaigns run in series. Cells are shuffled within each round with seed `30031`.
Clean rounds precede profiles. Every fixture and collection mode has its own
prime cache. Warm and edited samples restore that cache's identical bytes outside
the timer. Loading, decoding, graphs, persistence, reports, workers, and exit stay
inside the complete-command timer. Fresh primes contain new execution timestamps;
seed-cache identities identify the reset bytes within each experiment.

Each `metadata.json` pins the engine, exact fixture lockfiles and root lockfile,
driver hashes, coverage owner, command arguments, compiler, hardware, and options.
The stock campaign began before the drivers were committed. The allocator driver
contents are preserved in [09bdc39](https://github.com/salasebas/testsift/tree/09bdc39fc7a6c775b5dce3cb602b67295fdeb799/benchmark/evidence).
The timing and runtime entry points are preserved in
[d3cdc4d](https://github.com/salasebas/testsift/tree/d3cdc4d94705d3a05f02640bca9a228e870bd29f/benchmark/evidence).
Content hashes identify drivers measured before their commit. Raw rows preserve command arrays,
explicit environment changes, order, seed identities, selected IDs, oracle failure
IDs, allocations, peak memory, bytes, and exclusive method counters.

Review corrected one setup-only replay defect after measurement: the current
driver adds optional corpus gems before installing a retained lockfile. The
measured driver commits and their original hashes remain available. The corrected
driver preserves the recorded dependency bytes under frozen Bundler; timed engine
execution and instrumentation are unchanged. [REPLAY.md](REPLAY.md) uses that fix.

The benchmark owns Coverage and starts it before application loading. Rails'
implicit SimpleCov is disabled in the tracer and matched control. Dependency-only
is a benchmark ablation, not a product mode: line collection remains active while
per-example line-report deltas and the final line coverage JSON are omitted.
Lines retain normal reports. Branches add the same current-run branch export to
the control and tracer. Product collection and lifecycle contracts are unchanged.

GNU time supplies complete-command maximum single-process RSS, including native
memory. It does not sum simultaneous workers. Profile-only glibc samples include
Ruby arenas and are lower bounds on used allocator bytes, not exact native-only
peaks. Ruby allocation counts begin at the common bootstrap, exclude earlier
Ruby/Bundler work, and omit the parallel controller. Unwrapped RSpec has no object
counter. The [driver guide](../../evidence/CURRENT_ENGINE.md) defines these scopes.

## Current Ruby and Rails commands

Seconds are clean p50 / p95. Ruby has 38 examples; Rails has 308.

| Ruby case | Dependency | Lines | Branches | Selected |
| --- | ---: | ---: | ---: | ---: |
| plain | 0.472 / 0.537 | 0.462 / 0.634 | 0.381 / 0.582 | 100% |
| matched Coverage control | 0.379 / 0.401 | 0.382 / 0.493 | 0.453 / 0.974 | 100% |
| full | 0.607 / 0.648 | 0.503 / 0.559 | 0.932 / 1.010 | 100% |
| warm | 0.498 / 0.887 | 0.388 / 0.538 | 0.580 / 0.890 | 0% |
| source edit | 0.608 / 0.901 | 0.602 / 0.720 | 0.971 / 1.077 | 100% |
| input edit | 0.565 / 0.605 | 0.454 / 0.601 | 1.125 / 1.181 | 100% |
| invalidation | 0.733 / 1.138 | 0.570 / 0.603 | 1.129 / 1.317 | 100% |
| source defect | 0.601 / 0.625 | 0.493 / 0.611 | 1.217 / 1.338 | 100% |
| input defect | 0.799 / 1.011 | 0.447 / 0.522 | 1.115 / 1.124 | 100% |
| two-worker merge | 1.220 / 1.710 | 1.620 / 1.650 | 1.993 / 2.119 | 100% |

| Rails case | Dependency | Lines | Branches | Selected |
| --- | ---: | ---: | ---: | ---: |
| plain | 7.584 / 9.245 | 6.052 / 6.113 | 5.239 / 5.922 | 100% |
| matched Coverage control | 6.421 / 7.528 | 5.776 / 9.183 | 7.316 / 8.197 | 100% |
| full | 11.788 / 18.538 | 11.372 / 12.911 | 30.286 / 30.625 | 100% |
| warm | 2.198 / 2.203 | 2.072 / 2.200 | 2.004 / 3.688 | 0% |
| source edit | 11.129 / 12.104 | 11.508 / 12.187 | 45.744 / 46.073 | 100% |
| input edit | 3.184 / 4.070 | 2.935 / 4.070 | 5.024 / 5.035 | 5.19% |
| invalidation | 13.028 / 17.793 | 15.949 / 16.098 | 45.512 / 46.188 | 100% |
| source defect | 11.824 / 12.204 | 12.705 / 13.661 | 39.253 / 53.747 | 100% |
| input defect | 2.213 / 2.668 | 2.245 / 3.088 | 5.152 / 5.162 | 5.19% |

Full-run resource medians use clean samples. Exact p50 and p95 values remain in `analysis.json`.

| Fixture / contract | Ruby objects allocated | Peak RSS KiB | Cache bytes | Report bytes |
| --- | ---: | ---: | ---: | ---: |
| Ruby dependency | 244,772 | 42,796 | 54,707 | 116,155 |
| Ruby lines | 246,400 | 42,860 | 67,659 | 117,680 |
| Ruby branches | 1,348,097 | 41,356 | 67,671 | 120,561 |
| Rails dependency | 11,156,253 | 201,112 | 1,867,889 | 2,912,725 |
| Rails lines | 11,172,320 | 198,864 | 2,112,751 | 2,929,239 |
| Rails branches | 76,098,032 | 223,288 | 2,112,767 | 2,954,596 |

## Exclusive component costs

These seconds come from the independent Rails timing pass without allocator sampling. They are
separate from clean wall percentiles and include wrapper overhead. Nested methods
are subtracted from their caller. Unlisted time includes unwrapped boot, application
execution, and instrumentation. Interning is measured once per outer call, including
recursion, rather than probing every node.

| Component | Dependency | Lines | Branches |
| --- | ---: | ---: | ---: |
| Snapshot production | 2.1774 | 2.4327 | 18.8360 |
| Normalization | 0.5710 | 0.6411 | 0.5405 |
| Dependency and report scans | 0.1054 | 0.1451 | 0.1548 |
| Attribution and hooks | 0.3044 | 0.3506 | 0.2638 |
| Stat, hashing, and file discovery | 0.0227 | 0.0250 | 0.0223 |
| Graph, index, and selection | 0.0175 | 0.0201 | 0.0157 |
| Cache decode and interning | 0.0000 | 0.0000 | 0.0000 |
| Cache manifest/load | 0.0000 | 0.0000 | 0.0000 |
| Snapshot building | 0.0522 | 0.0539 | 0.0416 |
| Serialization and save | 0.0055 | 0.0068 | 0.0061 |
| Reports | 0.0429 | 0.0422 | 0.0539 |
| Runner setup and spec discovery | 0.8621 | 0.8920 | 0.8468 |
| Complete profiled command | 7.8846 | 8.3874 | 24.1992 |

The separate allocator pass records maxima of 155,890,992, 154,484,640, and
159,613,552 bytes respectively. These include Ruby arenas and are sampled lower
bounds. Subtracting them
from RSS does not yield native-only or Ruby-only memory.

Allocator sampling can perturb timing because `mallinfo2` traverses allocator
free lists. The large line workload demonstrates the effect:

| Measurement | Complete command (s) | Use |
| --- | ---: | --- |
| Clean large full lines p50 | 32.146 | Latency |
| Allocator-observation large full lines | 68.373 | Memory observations only |
| Independent diagnostic timing pass | 31.630 | Instrumentation check |
| Final independent timing pass | 34.956 | Exclusive cost budgets |

The diagnostic rows are retained in `timing-probe`. Component tables and budgets
use only the independent timing passes. Allocator-pass component counters are
excluded from `analysis.json` rather than interpreted as product costs.

The branch profile makes 928 Coverage snapshots for 308 examples.
Loaded-file tracking requests another snapshot per example. Removing those 308
producer calls targets roughly 25.8% of profiled wall time if snapshot costs
are proportional to call count. This is an experiment budget, not a measured
speedup. A sharing implementation must prove collection ownership, dynamic loads,
independent failures, report semantics, and supported-runtime fallback.

## Scale changes the optimization budget

The generated programs load and call actual Ruby methods and read actual JSON
inputs. Each full or merged cache is checked against independently required source
and input paths derived from the program's example index. Additional conservative
dependencies are allowed and appear in selected ratios. The checks do not use
agreement between storage backends as an oracle.

| Corpus | Ruby files | Branch sites/file | Examples | Source fan-out | Inputs | Eager |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| sparse | 100 | 8 | 1,000 | 1 | 100 | No |
| dense | 100 | 32 | 1,000 | 20 | 500 | No |
| eager | 500 | 32 | 1,000 | 1 | 1,000 | Yes |
| large | 100 | 8 | 10,000 | 1 | 1,000 | No |

Clean command p50 / p95 seconds:

| Corpus | Full dependency | Full lines | Full branches | Warm lines | Input defect selected |
| --- | ---: | ---: | ---: | ---: | ---: |
| sparse | 4.671 / 5.987 | 5.404 / 5.951 | 17.588 / 18.475 | 2.380 / 2.537 | 10/1000 |
| dense | 7.123 / 12.504 | 7.157 / 8.620 | 28.563 / 34.141 | 2.886 / 3.061 | 2/1000 |
| eager | 24.067 / 24.190 | 18.004 / 26.907 | 85.675 / 90.434 | 6.444 / 7.974 | 1/1000 |
| large | 31.479 / 32.215 | 32.146 / 33.127 | 113.682 / 137.663 | 14.202 / 17.040 | 10/10000 |

The 10,000-example workload also repeats matched controls at the same scale:

| Contract | Plain | Matched Coverage | Full recorder | Warm recorder |
| --- | ---: | ---: | ---: | ---: |
| dependency | 1.149 / 1.259 | 1.287 / 1.325 | 31.479 / 32.215 | 13.522 / 16.179 |
| lines | 1.156 / 1.205 | 1.319 / 1.649 | 32.146 / 33.127 | 14.202 / 17.040 |
| branches | 1.096 / 1.394 | 1.350 / 1.439 | 113.682 / 137.663 | 14.596 / 15.014 |

Full-run clean resource medians:

| Corpus / contract | Allocated Ruby objects | Peak RSS KiB | Cache bytes | Report bytes |
| --- | ---: | ---: | ---: | ---: |
| sparse dependency | 10,667,612 | 86,532 | 7,465,475 | 8,435,658 |
| sparse lines | 10,698,363 | 90,192 | 8,036,186 | 8,467,127 |
| sparse branches | 44,131,604 | 89,412 | 8,036,177 | 8,557,140 |
| dense dependency | 13,239,360 | 84,180 | 7,602,960 | 8,590,922 |
| dense lines | 13,959,114 | 133,060 | 20,673,753 | 8,654,452 |
| dense branches | 79,768,175 | 141,108 | 20,673,748 | 8,978,982 |
| eager dependency | 53,327,798 | 206,936 | 33,501,259 | 36,649,930 |
| eager lines | 53,404,352 | 222,180 | 34,428,037 | 36,933,072 |
| eager branches | 274,779,385 | 252,176 | 34,428,045 | 38,483,612 |
| large dependency | 105,906,513 | 534,928 | 74,381,020 | 83,485,217 |
| large lines | 106,153,264 | 536,028 | 80,042,806 | 83,517,564 |
| large branches | 440,893,006 | 531,108 | 80,042,862 | 83,609,457 |

Component times below use independent timing passes with allocator sampling
disabled. Each column is one instrumented process; it is not a clean percentile.
The allocation counts and raw counters remain in `analysis.json`.

| Component | Large full lines (s) | Large warm dependency (s) | Eager warm lines (s) |
| --- | ---: | ---: | ---: |
| Snapshot production | 4.8707 | 0.0002 | 0.0015 |
| Normalization | 5.1170 | 0.0000 | 0.0004 |
| Scans | 1.7733 | 0.0000 | 0.0000 |
| Attribution and hooks | 13.6440 | 0.0464 | 0.0029 |
| Stat/hash/discovery | 0.3007 | 0.0331 | 0.0559 |
| Graph/index/selection | 0.8122 | 11.3003 | 3.9735 |
| Decode/interning | 0.0000 | 0.9197 | 0.4473 |
| Cache load | 0.0000 | 0.0001 | 0.0001 |
| Snapshot building | 2.2400 | 2.4663 | 1.0137 |
| Serialization/save | 0.4080 | 0.4535 | 0.1593 |
| Reports | 2.6647 | 2.7320 | 0.7723 |
| Runner setup/discovery | 0.3493 | 0.2598 | 0.0965 |
| Complete timing pass | 34.9557 | 18.9601 | 6.8375 |

Warm reconstruction is distinct from the tiny full-run graph budget. The engine
seeds an absolute-path graph for current state and builds another graph from
relative cached paths for selection. A single canonical representation is a
Ruby experiment before a native model. It must preserve filters, input kinds,
status precedence, and path identities. Identity construction in the RSpec adapter
is not separately timed by the graph counters.

## Existing storage backends

These cells use the same dense corpus, line/report contract, pinned optional
dependencies, and independent expected-path checks. Backend campaigns are
sequential, not paired or interleaved. They do not qualify a default change on
this busy host.

| Backend | Full p50 / p95 (s) | Warm p50 / p95 (s) | Full cache bytes | Full RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| JSON | 7.157 / 8.620 | 2.886 / 3.061 | 20,673,753 | 133,060 |
| MessagePack + zlib | 4.803 / 4.883 | 2.142 / 2.189 | 2,262,348 | 130,252 |
| SQLite | 13.418 / 13.720 | 11.279 / 11.829 | 273,629,184 | 131,256 |

Codec CPU, model decoding/interning, graph rebuilding, snapshot projection, and
report generation remain separate in the timing rows. JSON and MessagePack use
existing native codecs; SQLite is also native underneath Ruby row construction.
A format rewrite does not remove the surrounding object-model work. Historical
coverage and recovery correctness remain owned by #11 and #14.

## Complete worker exit and merge

Each command waits through worker exit and verifies the merged cache's complete
example count and required source/input paths. The matched sparse workloads use
one, two, and four workers. The large case uses four workers.

| Corpus / workers | Clean p50 / p95 (s) | Peak process RSS KiB | Cache bytes | Max worker wait (s) | Elected merge (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| sparse / 1 | 3.532 / 3.537 | 131,712 | 7,466,056 | 0.0001 | 0.0325 |
| sparse / 2 | 3.096 / 4.503 | 110,384 | 7,330,100 | 0.0001 | 0.0426 |
| sparse / 4 | 3.135 / 3.201 | 106,516 | 7,262,100 | 0.0001 | 0.0350 |
| large / 4 | 16.711 / 20.588 | 465,036 | 72,352,126 | 0.0002 | 0.4465 |

Worker component durations are not summed and divided by command wall time.
Concurrent waits overlap. RSS is the maximum process peak, not simultaneous
aggregate worker memory. Process partitioning also changes conservative loaded-file
attribution, so graph and report byte counts need not match serial output exactly.
The independent required dependency sets must still hold.

## Unwrapped startup and discovery

The full commands below run without tracing; the plain column retains the common
benchmark bootstrap. The unwrapped columns remove it entirely. Dry runs discover
examples and emit formatter output without executing bodies or hooks. Their example
IDs are discovery counts, not selected or executed bodies.

| Fixture | Plain full p50 / p95 (s) | Unwrapped full p50 / p95 (s) | Unwrapped dry p50 / p95 (s) |
| --- | ---: | ---: | ---: |
| ruby | 0.290 / 0.331 | 0.227 / 0.247 | 0.182 / 0.231 |
| rails | 3.344 / 3.648 | 3.400 / 3.451 | 0.705 / 0.741 |
| large / 10000 examples | 1.149 / 1.259 | Unmeasured | 0.577 / 0.603 |

Dry discovery is not a safe empty-selection CLI. Config DSL execution, new files,
ENV inputs, runner options, historical reports, and unknown dependencies still
need a manifest/fallback contract before runner boot can be skipped.

## Cost budgets and the next experiment

These budgets are conditional limits, not predicted speedups. Let `T` be the
complete timing-pass wall time and `C` the component cost. To save 10% of that
command while leaving other work unchanged, all replacement work must fit within
`C - 0.10*T`. A negative allowance is a no-go for that component on that target.
Native initialization, FFI, copies, conversion, reporting, and teardown belong
inside the allowance. Profiles have one sample and include wrapper overhead;
near-threshold decisions require a quiet, repeated, paired experiment.

| Candidate | Named target | Current cost C (s) | T (s) | Share | Replacement allowance (s) | Decision and next check |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| #21: reuse loaded-file snapshot | Rails full branches | 6.2516 | 24.199 | 25.83% | 3.832 | Experiment in Ruby. Reuse the same example-boundary raw keys; retain boot capture, dynamic loads, observers, and report ownership. |
| #22: Ruby normalization/scans/attribution | Large full lines | 20.5344 | 34.956 | 58.74% | 17.039 | Experiment in Ruby first. Remove repeated path metadata, temporary sets, and traversals before choosing a native boundary. |
| #23: producer APIs | Rails full branches | 18.8360 | 24.199 | 77.84% | 16.416 | Adapt/propose a selective or dirty-file producer API. Reject a literal language-only port as a speedup claim; the current producer is already native. |
| #24: optional file-event collector | Large full dependency | 11.5837 | 34.045 | 34.02% | 8.179 | Defer adoption to #7, #8, #9, and #12. Compare existing collectors and lifecycle outputs before a bounded native file-event prototype. |
| #25: batched comparison consumer | Large full lines | 6.8903 | 34.956 | 19.71% | 3.395 | Re-profile after #22. Any native budget must include Ruby/native conversion, returned IDs, and optional line deltas. |
| #26: graph/index model | Large warm dependency | 11.3003 | 18.960 | 59.60% | 9.404 | Experiment with one canonical Ruby graph representation first. Native IDs or a retained model need a new post-Ruby measurement. |
| #27: filesystem/hash bookkeeping | Large full lines | 0.3007 | 34.956 | 0.86% | No-go (-3.195) | No native implementation on this named workload if the budget is below the gate. Larger cold trees need a separate experiment; SHA256 is already native. |
| #28: persistence/model/reports | Large warm dependency | 6.5716 | 18.960 | 34.66% | 4.676 | Use the existing backend comparison, then test direct model projection. A codec port alone does not remove graph and report construction. |
| #29: avoiding runner startup | Rails warm lines | 0.7052 | 1.505 | 46.86% | 0.555 | Defer implementation until a manifest and conservative fallback contract exist. Dry discovery excludes bodies/hooks and is only a startup upper budget. |

The #21 cost is estimated from the 308 duplicate calls among 928 total
snapshots, assuming proportional cost. All other component costs above are direct
exclusive measurements. The #29 row deliberately uses independent unwrapped dry
time as an upper budget; it is not an exclusive tracer-method observation.

The full Rails graph/index cost is only 0.0157 seconds.
That is a no-go for a graph port targeting a 10% improvement in the branch-heavy
full command, even though warm reconstruction is material at scale. Identity
hashing remains in the adapter's unclassified work; no separate identity-port
speedup is established here.

The next implementation experiment is **#21, snapshot reuse in Ruby**. Run it
against the same pinned engine corpus with full, warm, source/input defects,
invalidation, and worker merges. Use at least the default 20 clean paired rounds
on a quiet host. Preserve independent failure and required-path checks.
Then re-profile #22 before deciding whether #24, #25, or #26 still has enough
complete-command cost to justify Rust.

No native implementation or runtime/backend default is adopted by this PR.
Native adoption still requires at least 10% complete-command p50 improvement on
a named representative target, no worse p95 or process/native memory, zero omitted
independent failures, equivalent requested outputs, and the supported Ruby path.
Lower Ruby allocation counts alone do not prove lower total memory. Native-owned
heap attribution and simultaneous aggregate worker RSS remain unmeasured.

Remote restore, outer archive CPU, network transfer, and extraction are
**unmeasured**. These fixtures configure no authorized remote backend. External
seed-copy time is only an experimental reset and cannot justify a remote-cache port.

## Runtime and JIT producer comparison

Producer cost justifies a bounded VM study. These workloads load 200 executable
Ruby files with 32 branch sites each and execute one or 200 files per iteration.
They compare collection off, lines, branches, and a Ruby TracePoint callback.
Every iteration checks actual results and observed/changed file counts.

JIT requests use `--yjit-call-threshold=1`, four executions of every generated
method before sampling, and 20 measured iterations. Both the requested and actual
JIT-enabled state, available runtime stats, binary hashes, activated gem versions,
and configure arguments are retained in `runtime.json`. Snapshot distributions
have 40 samples per row, two per iteration. Complete-command time and peak RSS
include generation, warm-up, compilation, serialization, and exit.

Snapshot p50 / p95 milliseconds:

| Ruby | Collection | Touched files | JIT off | JIT requested | RSS off/on KiB |
| --- | --- | ---: | ---: | ---: | ---: |
| 3.3.10 | lines | 1 | 0.0605 / 0.0843 | 0.0578 / 0.1522 | 27696 / 28360 |
| 3.3.10 | lines | 200 | 0.0600 / 0.1063 | 0.0670 / 0.1579 | 27536 / 28284 |
| 3.3.10 | branches | 1 | 6.4898 / 10.0221 | 6.5062 / 7.8220 | 42652 / 43492 |
| 3.3.10 | branches | 200 | 5.9293 / 7.3523 | 6.1056 / 7.0148 | 42880 / 43640 |
| 3.4.12 | lines | 1 | 0.0610 / 0.0867 | 0.0611 / 0.1893 | 20100 / 22192 |
| 3.4.12 | lines | 200 | 0.0743 / 0.1278 | 0.0786 / 0.2520 | 20224 / 21680 |
| 3.4.12 | branches | 1 | 6.8538 / 9.8389 | 6.4574 / 10.4079 | 36568 / 37832 |
| 3.4.12 | branches | 200 | 5.8315 / 7.3022 | 6.3743 / 8.8600 | 36068 / 37832 |
| 4.0.9 | lines | 1 | 0.0607 / 0.0901 | 0.0650 / 0.3388 | 22384 / 24300 |
| 4.0.9 | lines | 200 | 0.0782 / 0.1032 | 0.0717 / 0.2987 | 22432 / 23948 |
| 4.0.9 | branches | 1 | 6.7898 / 8.7184 | 6.9555 / 8.2763 | 37516 / 38744 |
| 4.0.9 | branches | 200 | 6.1828 / 8.3300 | 6.2548 / 8.0658 | 37860 / 39008 |

Execution p50 milliseconds without requested JIT:

| Ruby | Touched | Collection off | Ruby TracePoint |
| --- | ---: | ---: | ---: |
| 3.3.10 | 1 | 0.0007 | 0.0074 |
| 3.3.10 | 200 | 0.1174 | 1.4135 |
| 3.4.12 | 1 | 0.0007 | 0.0128 |
| 3.4.12 | 200 | 0.1171 | 1.6895 |
| 4.0.9 | 1 | 0.0006 | 0.0068 |
| 4.0.9 | 200 | 0.0732 | 1.4259 |

These microbenchmarks do not establish end-to-end framework compatibility, JIT
benefit in an application, or file-event dependency equivalence. Ruby TracePoint
callbacks are not a native collector prototype. Runtime changes remain separate
from the engine's default behavior and supported-runtime contract.

## Artifact and correctness checks

`runs.jsonl.gz` retains all measured rows. `oracles.tar.gz` retains the independent
full-run formatter payloads, stdout, telemetry, and GNU time files. Every dataset
has its original metadata and summary. `analysis.json` is regenerated with
`benchmark/evidence/summarize.rb`; allocator-observation profiles are explicitly
excluded from component budgets. `host.json` supplies shared host provenance.
These JSON records and dependency lockfiles are generated data; their length is
intentional. `SHA256SUMS` covers the published dataset.

Cold, invalidated, and merged generated caches check independently required paths.
Defect cells require a failing full oracle, no omitted failures, and identical
observed failing IDs. Warm cells select zero examples. Discovery counts and actual
worker counts are checked separately from elapsed time.

The retained campaign has 24 datasets and 491 measured commands, including two
diagnostic timing commands. There are 384 oracle-failure observations, zero omitted
failures, and zero failure-status mismatches. These are repeated observations, not
384 distinct defects. The runtime study adds 48 complete commands. Prime runs,
independent full oracles, and provisioning occur outside those command counts.

## Reproduce the measurements

Use the pinned Ruby and install the bundles first. The measured host sets
`BUNDLE_PATH=/home/sebastian/.cache/testsift-bundle` to a writable gem directory.
Each raw row retains its exact environment and command. Use a new output for
every replay and `--lockfiles` with the matching published metadata to restore
its dependency resolution.

[REPLAY.md](REPLAY.md) contains exact commands for all 24 datasets and the runtime
study. It selects the allocator, timing, or dry-discovery task from each dataset's
entry point and supplies the pinned engine and retained dependency resolution.
For example, replay the main clean/allocator campaign with:

```sh
task benchmark:evidence:memory -- --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/stock/metadata.json --repetitions 3 --profiles 1 --output tmp/issue20-replay-stock
```

The allocator probe build stays outside the application timer:

```sh
cc -shared -fPIC -O2 -o OUTPUT/malloc_probe.so benchmark/evidence/malloc_probe.c
```

The [optimization inventory](../../PERFORMANCE_INVENTORY.md) and
[Coverage/Rust assessment](../../COVERAGE_RUST_RESEARCH.md) retain their imported
source scope. Their lifecycle and adoption constraints still apply. Their old
timings do not replace these current-engine measurements.
