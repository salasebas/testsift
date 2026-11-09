# Measure selector cost on the imported TestSift baseline

Use this benchmark to compare complete RSpec processes, including Bundler,
boot, discovery, selection, cache reads and writes, report generation, and process
exit. It extracts the requested Git revision into a new workspace under the output
directory. It never changes the original fixture sources or the production library.
The default source revision is the imported `v2.0.0.rc.1`,
`f13851f7b3393aaafa7c7df088c1605747f07ce5`.

## Run the experiment

Use the repository's pinned Ruby and install the root bundle first. This benchmark
runs on Linux and macOS; see [Prepare the host](CURRENT_ENGINE.md#prepare-the-host)
for platform tools and the pinned Linux container.

```sh
bundle install
task benchmark:evidence -- --output tmp/evidence-stock
```

The task installs the fixture bundles. The driver creates and prepares the Rails
test database before timing. The default run performs 20 repetitions per cell,
then three additional repetitions with method instrumentation. Within each round,
cells run in a deterministic shuffled order with seed `30031`. Run one benchmark
at a time and avoid other CPU-intensive work.

For a shorter check of the Ruby fixture:

```sh
task benchmark:evidence -- --fixtures ruby --modes lines --repetitions 1 --profiles 1 --output tmp/evidence-smoke
```

To replay a published dependency resolution, supply its `metadata.json`. The driver
writes its saved fixture lockfiles into the extracted workspace and installs those
bundles before timing:

```sh
task benchmark:evidence -- --lockfiles benchmark/results/2026-11-04-issue-3/stock/metadata.json --output tmp/evidence-replay
```

A one-repetition check is a correctness check, not a useful p95 estimate. The p50
and p95 use the nearest-rank definition, with rank `ceil(n * p)`. Keep the raw
samples when comparing hosts.

## Interpret the cases

| Case | Starting state and execution |
| --- | --- |
| `plain` | No tracer and no Coverage collection. Run all examples. |
| `coverage_control` | No tracer. Start Coverage with the same modes and timing as the instrumented counterpart. |
| `full` | Empty tracer cache. Run the complete instrumented suite. |
| `warm` | Restore the same seed cache, with no source changes. |
| `changed_source` | Restore the seed, then make an equivalent executable Ruby expression change. |
| `changed_input` | Restore the seed, then change bytes in a Ruby spec or Rails JSON input. |
| `invalidated` | Restore the seed, then change `.rspec-tracer` bytes. The entire suite must run. |
| `fault` | Restore the seed, then introduce a source defect. Compare selected and failing example IDs against an independent full RSpec run of that defect. |
| `parallel_full` | Ruby fixture only. Run two workers from an empty cache, wait for exit and merge, and verify the merged cache contains all examples. |

Each fixture and mode has an independently primed seed. Every warm or changed
sample starts from the exact same seed bytes. Seed creation and the experimental
copy that resets state are outside the application timer. The copy duration is
recorded separately as `external_seed_restore_seconds`. Production cache loading,
including lazy decoding and finalization, remains inside the timer. These fixtures
do not configure a remote cache, so this experiment makes no network-restore claim.

The source changes replace `100.0` with `100.00` in Ruby's discount calculation
and `== true` with `== (true)` in Rails' feature flag service. The fault changes
replace those expressions with `50.0` and `== false`, respectively. The oracle must
fail. Every measured fault run must select every oracle failure and reproduce the
same failing IDs. This is a bounded regression check, not a proof that arbitrary
Ruby dependencies are complete.

## Keep collection modes separate

| Mode | Collection and reports |
| --- | --- |
| `dependency` | Collect ordinary line counts. Benchmark-only overrides omit per-example line-report deltas and the final coverage JSON. Dependency reports and cache persistence still run. |
| `lines` | Ordinary line collection, per-example line deltas, and the tracer's default terminal, JSON, HTML, and coverage reports. |
| `branches` | Lines plus branches, the same tracer reports, and a JSON export of the current project's full Coverage result. The coverage control writes the same branch export. |

`dependency` is an ablation in the benchmark bootstrap. The imported gem has no
public switch that removes line-report recording while retaining dependency
selection. It is not a claim that the product already offers that configuration.
The tracer's legacy coverage JSON remains line-only even in branch mode. The
additional branch export supplies real branch reporting without introducing
SimpleCov into only one side of a comparison.

The bootstrap starts Coverage before either fixture loads application code, with
the Rails fixture's implicit SimpleCov setup disabled. This keeps collection
modes and load timing comparable. SimpleCov formatting and its merge lifecycle
are separate from this controlled comparison.

## Check semantic input changes

The main fault case changes executable source. A companion probe flips Rails'
`comments_enabled` JSON value or changes a Ruby spec expectation. It records
selected IDs, independent full-suite failure IDs, omitted failures, and any
failure-status differences among selected examples. It completes the requested
samples before exiting nonzero if omissions or status differences were found.
It diagnoses the imported selector; it does not change library behavior.

```sh
task benchmark:evidence:input-fault -- --modes lines --cases fault --repetitions 20 --profiles 0 --output tmp/evidence-input-fault
```

## Read the artifacts

`metadata.json` records revisions, driver hashes, Ruby, hardware, affinity, seed,
options, and exact fixture lockfile contents. `runs.jsonl` records execution order,
commands, explicit environment changes, exit codes, example IDs, failing IDs,
selected ratios, cache identities and sizes, wall time, CPU time, memory, allocations,
and optional per-method measurements. `summary.json` separates instrumented and
uninstrumented repetitions. Individual stdout, RSpec JSON, and worker telemetry
remain in `runs/`. The extracted source and seed caches also remain available.

Wall time comes from the parent monotonic clock around the entire subprocess.
`peak_rss_kib` is the maximum resident set of a process in the command's
waited tree. For parallel runs it is not the sum of simultaneous worker memory.
Allocations count Ruby objects after the bootstrap begins through the final exit
callbacks, summed across workers. They exclude the parallel controller, Ruby
startup before the bootstrap, and native allocations. They are not allocated bytes.

Profiles wrap real `Coverage.peek_result` calls and actual library methods.
Coverage dimensions are populated only on profiled rows. Their zero placeholders
on clean rows do not mean that the collector observed zero files or lines.
Durations and allocations are exclusive of nested measured methods, so a Coverage
snapshot is charged to `coverage_snapshot`, not also to loaded-file attribution.
They include wrapper overhead and should explain a result, not replace the clean
wall-time samples. The profile-only final Coverage inspection is excluded from
method counters and allocation totals but remains in profiled process wall time.
Never combine profiled and clean samples in a percentile.

## Test sharing the loaded-file snapshot

The optional bootstrap variant lets `LoadedFilesTracker#stop_example` use keys
from the adapter's most recent snapshot. Boot-set capture retains its original
collector. This is an experiment, not a change to `lib/`.

```sh
task benchmark:evidence -- --variants stock,share_snapshot --fixtures rails --modes lines,branches --cases full,changed_input,fault --repetitions 20 --profiles 3 --output tmp/evidence-shared
```

The two variants run in the same shuffled rounds and share the same seed caches.
Use `--variant share_snapshot` to run only that variant.
Use `--cases` to narrow a follow-up, `--revision` to select an archived source,
`--seed` to change the shuffled order, and a new `--output` for every run. Existing
output directories are rejected. A successful sharing experiment establishes a
measurement lead; it does not establish safe snapshot ownership for every observer,
load hook, or interpreter.

## Isolate the VM snapshot cost

The standalone workload generates and loads real Ruby methods with executable
branches. Setup executes every method and verifies its result. Each iteration
executes `TOUCHED` methods, one by default, and checks that exactly that many
files' actual Coverage line counts changed. It measures full
snapshot creation, line-array comparison, keys from an existing snapshot, and an
additional snapshot requested only for its keys.
It also compares equivalent normalizations with `Hash#each_with_object` and
`Hash#each_pair`, checking that both return the same path-to-lines map.

```sh
FILES=500 BRANCH_SITES=60 ITERATIONS=20 MODE=lines task benchmark:coverage:real
FILES=500 BRANCH_SITES=60 ITERATIONS=20 MODE=branches task benchmark:coverage:real
FILES=500 BRANCH_SITES=60 ITERATIONS=20 MODE=off task benchmark:coverage:real
FILES=500 BRANCH_SITES=60 ITERATIONS=20 MODE=tracepoint task benchmark:coverage:real
```

`BRANCH_SITES` controls executable branch sites per generated file. The workload includes
additional declaration lines. Set `TOUCHED=500` to execute every generated method
in the 500-file workload. The equality scan uses Ruby's built-in Array comparison;
the fixture profiles measure the actual adapter's Ruby scan separately.
The `tracepoint` mode uses a Ruby line-event callback and a file set instead of
Coverage. It checks the observed file count on the same generated methods. This
illustrates event cost for sparse and dense execution; it does not establish
dependency equivalence for a real application or predict a native callback's speed.
It is a scaling experiment, not an end-to-end Rails
prediction. Run the same script with another installed Ruby binary to compare VM
snapshot behavior without changing TestSift's code or dependency resolution.
