# Measure the extracted engine at scale

The current-engine driver extends the imported-baseline driver without changing
its source revision, artifacts, or benchmark limits. It archives the requested
engine revision, prepares isolated fixtures, and runs complete RSpec commands.
Results belong in a new directory. See the
[current-engine report](../results/2026-11-04-issue-20/REPORT.md) for retained samples
and decisions. The [baseline guide](README.md) defines the common timing protocol.

## Prepare the host

Use the pinned MRI 3.3.10, the root bundle, and both fixture bundles. The drivers
run natively on Linux and macOS. `host.rb` owns the platform differences:

| Measurement | Linux | macOS |
| --- | --- | --- |
| Command RSS and CPU | GNU `/usr/bin/time -f` | BSD `/usr/bin/time -l` |
| In-process peak RSS | `/proc/self/status` `VmHWM` | `getrusage` `ru_maxrss` |
| Allocator sample | glibc 2.33+ `mallinfo2` | `malloc_zone_statistics` |
| Host provenance | `/proc`, `taskset` | `sysctl`; no CPU affinity |

Both need `tar` and a C compiler. The tiny malloc probe is benchmark instrumentation.
It is compiled into the output directory and never loaded by the product.
The real-branch generator spec excludes JRuby because its
[Coverage implementation](https://github.com/jruby/jruby/blob/9.4.15.0/core/src/main/java/org/jruby/ext/coverage/CoverageModule.java#L75)
does not support branch coverage. Product runtime support is unchanged.

Use macOS for local iteration and paired before/after comparisons on one machine.
Absolute numbers from different hosts are not comparable. Record publishable
evidence with the same protocol as the retained Linux datasets. On a Mac, or any
machine with Docker, the pinned container provides that host:

```sh
task benchmark:evidence:docker -- task benchmark:evidence:current -- --output tmp/linux-current
```

The container uses `.ruby-version`, mounts the checkout and its Git directory at
their host paths, and keeps Linux gems in the `testsift-evidence-bundle` volume.
Docker Desktop and OrbStack run it inside a Linux VM. Metadata records the VM kernel;
on ARM the CPU model may be absent, so record the physical host separately.

```sh
bundle install
task benchmark:bundle
task benchmark:evidence:current -- --output tmp/current-engine
```

The default engine revision is `e225fbf`, resolved to a full SHA in metadata. The
default campaign has 20 clean repetitions and three additional timing repetitions
per cell. Allocator sampling runs separately because `mallinfo2` can traverse large
allocator free lists and perturb the hot methods being timed. Use `--revision SHA`
to measure another engine. Run one campaign at a
time. Leave other CPU-intensive applications idle where possible.

Metadata includes the engine revision, all driver hashes, compiler, Ruby, OS,
CPU, memory, CPU affinity, coverage owner, fixture lockfile bytes, root lockfile,
command arguments, and explicit options. Raw rows preserve each subprocess command,
environment changes, run order, seed-cache identity, and external reset time.
Generated corpora also have an identity over their complete initial fixture tree.
Driver hashes identify uncommitted driver contents independently of `driver_revision`.

Replay the exact fixture dependencies with a retained metadata file:

```sh
task benchmark:evidence:current -- --lockfiles benchmark/results/2026-11-04-issue-20/stock/metadata.json --repetitions 3 --profiles 1 --output tmp/current-replay
```

## Choose a workload

The default fixtures are Ruby and Rails. All three collection contracts remain
separate: dependency-only is a benchmark ablation, lines retain the default
reports, and branches add the same current-run branch export to the tracer and
matched Coverage control. This does not add a product collection mode or change
SimpleCov's contract.

Select a generated corpus with `--fixtures ruby --corpus NAME`:

| Name | Ruby files | Branch sites per file | Examples | Source fan-out per example | Input files | Eager load |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| sparse | 100 | 8 | 1,000 | 1 | 100 | No |
| dense | 100 | 32 | 1,000 | 20 | 500 | No |
| eager | 500 | 32 | 1,000 | 1 | 1,000 | Yes |
| large | 100 | 8 | 10,000 | 1 | 1,000 | No |

Each example calls actual Ruby methods, checks known branch results, reads a JSON
input through the real I/O hooks, and checks the input's known value. Four spec
files support `--workers 1`, `2`, or `4`. A worker run checks the actual worker
telemetry count, complete example count, and merged cache. It waits through
report generation and worker exit inside the application timer.

For other dimensions, supply `--corpus-file PATH`. Its JSON object has the fields
`files`, `branch_sites`, `examples`, `fanout`, `inputs`, and boolean `eager`. Sizes
must be positive integers, and `fanout` cannot exceed `files`. Generated fixtures
include pinned optional MessagePack and SQLite gems for equivalent backend runs.
Their resolutions are saved with the rest of the fixture lockfile.

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus sparse --modes dependency,lines,branches --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/current-sparse
task benchmark:evidence:current -- --fixtures ruby --corpus large --modes dependency --workers 4 --cases parallel_full --repetitions 3 --profiles 1 --output tmp/current-workers
```

Use the same corpus, modes, cases, and dependencies for backend comparisons:

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus dense --modes lines --cases full,warm --backend json --serializer msgpack --repetitions 3 --profiles 1 --output tmp/current-msgpack
task benchmark:evidence:current -- --fixtures ruby --corpus dense --modes lines --cases full,warm --backend sqlite --repetitions 3 --profiles 1 --output tmp/current-sqlite
```

SQLite comparisons use serial runs. The product's current worker merge requires
the JSON backend. The driver rejects that unsupported benchmark combination and
rejects silent backend or serializer fallback.

## Check selection independently

Every fixture and mode gets a clean seed and two independent full-run oracles.
`fault` changes executable source. `input_fault` changes a JSON value or a Ruby
spec expectation. Each defect must make the full runner fail. Measured defect rows
store oracle failure IDs, selected IDs, omitted failures, and failure-status
mismatches before validation can stop a run. A bad selector result leaves a raw
diagnostic row and exits nonzero.

For generated sources, `changed_source` changes an equivalent branch expression.
`changed_input` changes input bytes without changing its value. Both reset to the
same seed first. `invalidated` changes the whole-suite configuration file.

Full, invalidated, and merged generated runs inspect the persisted graph through
the chosen backend. For example index `i`, the required source set is
`work_((i + offset) % files).rb` for each `offset < fanout`, and the required input
is `input_(i % inputs).json`. This requirement comes from the generated program,
not another backend. Conservative extra dependencies remain allowed and show up
in the selected ratio. This is a bounded oracle, not a completeness proof for
arbitrary Ruby programs.

## Read the measurements

`runs.jsonl` retains clean and profile rows separately. `summary.json` reports
nearest-rank wall p50 and p95, allocation counts, peak RSS, cache and report bytes,
selected ratios, and independent failure observations. With three repetitions,
nearest-rank p95 is the maximum sample. That estimate cannot establish a stable
tail distribution or qualify a native implementation for adoption.

Profiles extend the original exclusive timing stack with graph reconstruction,
inverse-index construction, cache interning and model decoding, I/O hooks,
MessagePack encoding, worker waits, runner setup, and spec-file discovery.
The original labels still separate snapshot production, normalization, dependency
and line-report scans, attribution, stat/hash, snapshot construction, JSON,
persistence, and reports. Nested methods are subtracted from their caller.
Interning is timed once per outer call, including recursion, so counters and
allocator probes do not run for every nested object. Use clean complete
commands for performance comparisons and profiles to choose the next experiment.
Component summaries apply to traced runs. Controls retain their runner/discovery
and branch-export measurements in raw telemetry, but do not install the tracer's
collector probes. Their missing component measurements must not be read as zero
collector cost.

The default task uses `timing.rb`, which disables allocator sampling while retaining
the same engine instrumentation. A timing-only pass can use zero clean repetitions:

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus large --cases full,warm --repetitions 0 --profiles 1 --output tmp/current-timing
```

Use `benchmark:evidence:memory` for the separate allocator observation. Its timing
counters include allocator-probe overhead and are excluded from component budgets.
Clean wall time, allocations, and RSS from that driver remain valid.

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus large --cases full,warm --repetitions 3 --profiles 1 --output tmp/current-memory
```

`unwrapped_plain` runs RSpec without either benchmark bootstrap. It has no Ruby
allocation counter. Compare it with `plain` under the same fixture and mode:

```sh
task benchmark:evidence:current -- --modes lines --cases plain,unwrapped_plain --repetitions 3 --profiles 0 --output tmp/current-startup
```

To separate startup and discovery from example bodies, the startup entry point
adds RSpec's `--dry-run` only to the unwrapped command. Its prime and failing
oracles still execute normally outside the measurement. Metadata marks the dry
run. Its example IDs count discovered examples, not executed or selected bodies.
RSpec documents that [dry runs skip examples and hooks](https://rspec.info/features/3-13/rspec-core/command-line/dry-run/).

```sh
task benchmark:evidence:startup -- --modes lines --cases unwrapped_plain --repetitions 3 --profiles 0 --output tmp/current-discovery
```

`/usr/bin/time` supplies peak process-tree RSS, which includes native allocations. It is
the maximum single-process peak, not simultaneous worker RSS summed together.
Per-worker telemetry also records the process peak (`VmHWM` on Linux, `ru_maxrss` on
macOS). Profile boundaries in the memory pass sample glibc used arena bytes plus used
mmap bytes with `mallinfo2`, or macOS malloc-zone bytes in use. The maximum
sample is a lower bound, includes Ruby heap arenas, and excludes allocations
that appear and disappear between boundaries. It is not native-only peak memory.
GC malloc counters are net increases since collection, not heap peaks. Native-only
live-byte attribution requires a separate allocator profiler before native adoption.
Clean runs do not call the allocator probe.

No remote backend is configured by these fixtures. Remote lookup, archive CPU,
network transfer, and extraction remain unmeasured. The external seed copy is an
experimental reset and must never be described as a production remote restore.

## Compare runtimes when collector cost warrants it

The runtime driver loads and executes real generated Ruby files. It compares
200 files with 32 branch sites each, one versus 200 touched files, collection off,
lines, branches, and Ruby TracePoint, with YJIT requested on and off. Each row saves
the exact binary and command, actual runtime description, actual YJIT-enabled
state, raw iterations, and complete-command peak RSS. Supply installed binaries:

```sh
task benchmark:evidence:runtime -- --rubies /path/to/ruby-3.3.10/bin/ruby,/path/to/ruby-3.4.12/bin/ruby,/path/to/ruby-4.0.9/bin/ruby --output tmp/current-runtime.json
```

This isolated producer experiment does not prove runner compatibility, file-event
dependency equivalence, or an end-to-end JIT benefit. The default Ruby collector
and supported runtime behavior remain unchanged.

The JIT cases explicitly set `--yjit-call-threshold=1` and execute all generated
methods four times before sampling. Their setup and compilation remain inside
the complete-command timer. This follows Ruby's documented
[YJIT call threshold](https://docs.ruby-lang.org/en/3.3/yjit/yjit_md.html#label-Command-Line+Options)
instead of assuming that 20 sampled iterations warm the default threshold.

The measurement contracts follow Ruby's
[Coverage documentation](https://ruby-doc.org/3.3.0/exts/coverage/Coverage.html),
[GC counters](https://ruby-doc.org/3.3.0/GC.html), and glibc's
[allocator statistics](https://sourceware.org/glibc/manual/latest/html_node/Statistics-of-Malloc.html).
