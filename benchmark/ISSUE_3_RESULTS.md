# Real selector costs and the next Rust experiment

Optimize snapshot production before porting the graph or cache. The imported Rails
fixture takes **6.588 s with lines** and **22.335 s with branches** at p50.
Actual `Coverage.peek_result` calls consume **17.209 s** median exclusive time in
the branch profile, about **77.8% of the profiled process wall time**. MRI already
implements the collector and snapshot production in C.

A benchmark-only snapshot reuse reduces the paired branch median **23.8%**, from
**21.881 to 16.672 s**, while selecting the same 308 examples. The most relevant Rust
prototype is a public native file-event collector for an explicit dependency-only
contract. A literal Coverage language port retains the global snapshot work.

See the [component inventory](PERFORMANCE_INVENTORY.md) and
[Coverage/Rust assessment](COVERAGE_RUST_RESEARCH.md) for all candidates, maintained
projects, fork options, source evidence, compatibility, and adoption gates.

## Source and protocol

- Measured implementation: imported `v2.0.0.rc.1`,
  `f13851f7b3393aaafa7c7df088c1605747f07ce5`.
- Authoring checkout: TestSift `03173c22b32b0accaccf37a5e662487b3bc79c50`.
  The supplied worktree was four upstream commits newer. Its exploratory measurements
  are excluded.
- Host: Intel Core i7-1355U, 12 allowed logical CPUs, 40,715,980 KiB visible RAM.
  Shared Linux desktop, no fixed CPU governor, no cold OS-page-cache reset.
- Main runtime: MRI 3.3.10, RSpec 3.13.2 / rspec-core 3.13.6, Rails 7.2.4,
  rspec-rails 6.1.5, sqlite3 1.7.3, Bundler 2.5.22. Exact fixture lockfiles and
  per-process activated gem versions are retained.
- Each clean cell has 20 separate command repetitions. Three further repetitions
  collect profiles. Cells are shuffled within rounds with seed 30031.
- Each experiment extracts a fresh Git archive. Every warm or changed sample resets
  to the same seed bytes before its change. Cold means an empty tracer cache, with
  OS and framework caches warmed by previous runs.
- Controlled Coverage starts before fixture/framework loading. The matched control
  uses the same modes and start point. Rails' implicit SimpleCov is disabled.
  Branch mode adds the same current-run branch JSON export to traced and control runs.
  This differs from the legacy benchmark's default SimpleCov startup.

Drivers were uncommitted when measured. Their SHA256 values identify exact contents.
`driver_revision` records the authoring checkout; it does not claim that the driver
already existed in that commit. Published source files match those hashes.

```sh
task benchmark:evidence -- --output tmp/evidence-stock-final-20261104
task benchmark:evidence -- --fixtures rails --modes lines,branches --cases full --variants stock,share_snapshot --repetitions 20 --profiles 3 --output tmp/evidence-paired-final-20261104
task benchmark:evidence:input-fault -- --modes lines --cases fault --repetitions 20 --profiles 0 --output tmp/evidence-input-fault-final-20261104
```

To replay dependency resolution, add
`--lockfiles benchmark/results/2026-11-04-issue-3/stock/metadata.json` and use a new
output directory. The [driver guide](evidence/README.md) defines setup, modes, memory,
allocation scope, profiling, and platform requirements.

Wall time includes Bundler, boot, discovery, cache loading/saving, reports, and exit.
Seed creation and experimental reset/copy are outside the application timer.
Production cache loading remains inside it. These fixtures configure no remote cache;
there is no claim about network restore time.

## Complete process timings

Seconds use nearest-rank p50/p95. Ruby has 38 examples; Rails has 308. The plain row
includes the common bootstrap, without tracer or Coverage collection. Profiled and
clean samples are never combined.

### Ruby fixture

| Case | Dependency p50 / p95 | Lines p50 / p95 | Branches p50 / p95 | Selected |
| --- | --- | --- | --- | --- |
| plain | 0.260 / 0.299 | 0.257 / 0.294 | 0.260 / 0.310 | 100.00% |
| coverage_control | 0.258 / 0.375 | 0.265 / 0.333 | 0.269 / 0.309 | 100.00% |
| full | 0.334 / 0.348 | 0.338 / 0.381 | 0.601 / 0.792 | 100.00% |
| warm | 0.297 / 0.376 | 0.312 / 0.350 | 0.330 / 0.428 | 0.00% |
| changed_source | 0.345 / 0.374 | 0.339 / 0.388 | 0.604 / 0.978 | 100.00% |
| changed_input | 0.338 / 0.358 | 0.347 / 0.378 | 0.615 / 0.773 | 100.00% |
| invalidated | 0.345 / 0.364 | 0.353 / 0.393 | 0.616 / 0.699 | 100.00% |
| fault | 0.346 / 0.426 | 0.355 / 0.410 | 0.624 / 0.905 | 100.00% |
| parallel_full | 1.430 / 1.527 | 1.432 / 1.458 | 1.537 / 1.568 | 100.00% |

### Rails fixture

| Case | Dependency p50 / p95 | Lines p50 / p95 | Branches p50 / p95 | Selected |
| --- | --- | --- | --- | --- |
| plain | 2.899 / 2.986 | 2.906 / 3.518 | 2.936 / 3.200 | 100.00% |
| coverage_control | 3.656 / 4.080 | 3.686 / 4.357 | 3.839 / 4.864 | 100.00% |
| full | 6.587 / 7.357 | 6.588 / 7.270 | 22.335 / 24.457 | 100.00% |
| warm | 1.403 / 1.467 | 1.446 / 1.631 | 1.583 / 1.836 | 0.00% |
| changed_source | 6.856 / 7.969 | 6.883 / 8.180 | 22.198 / 25.793 | 100.00% |
| changed_input | 1.560 / 1.889 | 1.584 / 1.680 | 2.492 / 2.568 | 5.19% |
| invalidated | 6.786 / 7.350 | 6.984 / 7.252 | 22.233 / 23.491 | 100.00% |
| fault | 6.909 / 7.352 | 6.917 / 7.707 | 22.216 / 23.028 | 100.00% |

## Memory, allocations, and cache size

| Fixture | Mode | Case | RSS MiB p50 | Ruby allocations, millions p50 | Cache MiB min-max |
| --- | --- | --- | --- | --- | --- |
| rails | branches | full | 219.39 | 76.119 | 2.028-2.028 |
| rails | branches | warm | 163.32 | 2.369 | 2.039-2.039 |
| rails | dependency | full | 197.89 | 11.171 | 1.782-1.782 |
| rails | dependency | warm | 135.84 | 2.010 | 1.793-1.793 |
| rails | lines | full | 196.45 | 11.187 | 2.028-2.028 |
| rails | lines | warm | 139.14 | 2.031 | 2.039-2.039 |
| ruby | branches | full | 40.61 | 1.349 | 0.065-0.065 |
| ruby | branches | warm | 40.22 | 0.211 | 0.067-0.067 |
| ruby | dependency | full | 42.23 | 0.244 | 0.052-0.052 |
| ruby | dependency | warm | 36.59 | 0.160 | 0.054-0.054 |
| ruby | lines | full | 42.10 | 0.246 | 0.065-0.065 |
| ruby | lines | warm | 36.99 | 0.162 | 0.067-0.067 |

RSS is GNU time's maximum per-process resident set, including waited descendants,
not simultaneous aggregate worker memory. Allocations are Ruby object counts after
bootstrap startup through exit, not native bytes. Cache sizes include retained files
and the manifest.

No-change selection is zero. Equivalent executable Ruby edits select the entire suite.
The Rails JSON byte change selects 16/308, or 5.19%; changing the Ruby spec selects
38/38. Dependency-only and line-mode Rails full medians both round to 6.59 s: removing
line-report output alone shows no clear saving while global snapshots remain.

## Direct RSpec control

Another 20 repetitions per fixture/launch are shuffled in common rounds. Both run
all examples without tracer or Coverage collection. The direct command is
`bundle exec rspec`; the bootstrap command uses `bundle exec ruby -r ... -S rspec`
and the main experiment's telemetry.

| Fixture / launch | p50 / p95, s |
| --- | --- |
| rails / direct bundle exec rspec | 2.880 / 2.967 |
| rails / common bootstrap | 2.793 / 2.838 |
| ruby / direct bundle exec rspec | 0.178 / 0.187 |
| ruby / common bootstrap | 0.246 / 0.264 |

There is no universal overhead to subtract. Ruby shows a material launch difference;
Rails performs much more framework work. The tiny Ruby fixture has no demonstrated
warm-run advantage over normal RSpec. Zero selected tests does not imply a faster
complete command. Rails' no-change time is about half the direct RSpec time, while
source edits trigger a costly complete instrumented run.

Exact commands/environment are in the plain-control rows. They use the archived
fixture helper with tracer loading disabled. Original orchestration scripts retain
the original local paths; adjust repository/output paths to rerun them elsewhere.

## Actual method costs

Median exclusive milliseconds per command across three diagnostic profiles follow.
Child measurements are subtracted, so a loaded-tracker snapshot is charged to Coverage.
These figures include wrapper overhead and explain the clean timings.

| Exclusive work | Lines full, ms | Branches full, ms | Lines warm, ms |
| --- | --- | --- | --- |
| Coverage snapshots | 1867.060 | 17209.195 | 5.553 |
| Root/filter normalization | 455.775 | 514.647 | 0.577 |
| Dependency delta scan | 80.424 | 109.408 | 0.000 |
| Line-report delta | 25.944 | 32.087 | 0.000 |
| Loaded-set bookkeeping | 27.149 | 38.259 | 0.388 |
| Input/file attribution | 217.265 | 157.618 | 0.000 |
| Filesystem stat, process-wide | 11.981 | 15.831 | 0.583 |
| SHA256, process-wide | 1.665 | 1.861 | 1.011 |
| Digest cache bookkeeping | 4.580 | 5.516 | 0.461 |
| New-file detector | 0.000 | 0.000 | 0.013 |
| Declared globs | 0.668 | 0.779 | 0.478 |
| Graph registration/query | 9.134 | 8.598 | 11.490 |
| Filter selection | 0.000 | 0.000 | 0.114 |
| Cache load wrapper | 0.015 | 0.021 | 0.066 |
| Cache field decode/interning | 0.000 | 0.000 | 18.485 |
| Cache JSON parsing | 0.007 | 0.007 | 7.937 |
| Cache JSON encoding | 3.546 | 3.729 | 2.482 |
| Cache save/write | 2.050 | 2.066 | 4.426 |
| Snapshot construction/projection | 44.666 | 41.591 | 58.343 |
| Default reports | 34.786 | 39.157 | 36.121 |
| Other JSON encoding | 3.502 | 3.681 | 2.993 |
| Coverage report bookkeeping | 1.427 | 1.253 | 3.156 |
| Branch export bookkeeping | 0.000 | 1.860 | 0.000 |
| Finalize bookkeeping | 0.162 | 0.195 | 0.177 |

Branch full runs make **928** snapshots; line full runs make **927**. Loaded-set
bookkeeping is about 38 ms exclusive, but the extra snapshot requested for keys is
much more expensive. An array-returning observer cannot establish that collection cost.

Profiles see **2,303 instrumented files and 391,674 line slots**, versus **63 project
files**. Filtering occurs after the global result exists. The fixture executes real
code: the full profile records 304 executed application lines, and source defects
cause independent full RSpec failures.

Graph registration/query is a narrow label. Reverse-index projection and graph copies
remain in snapshot construction. Their combined upper bound is still small relative
to snapshots here. Cache JSON parsing/encoding is separate from Ruby decoding/interning
and writes. The JSON parser and SHA256 implementation are already native.

Remaining time includes framework startup, discovery, test bodies, and unwrapped
adapter work. Boot/discovery are included in total wall time; this experiment does
not claim a separately isolated Rails boot duration.

Two-worker Ruby commands include controller startup, both exits, merge, and reports.
The merged cache must contain all 38 examples. Summed worker profile seconds can
overlap and do not describe the parent's critical path.

## Randomized snapshot-sharing comparison

Each mode/variant has 20 clean repetitions and three profiles. Both variants run in
the same shuffled rounds. The override changes loaded-file observation in the bootstrap;
the production selector is unchanged.

| Mode / variant | p50 / p95, s | Allocations, millions p50 | RSS MiB p50 |
| --- | --- | --- | --- |
| branches / share_snapshot | 16.672 / 17.285 | 53.201 | 219.55 |
| branches / stock | 21.881 / 22.424 | 76.119 | 218.25 |
| lines / share_snapshot | 5.983 / 6.162 | 9.793 | 194.06 |
| lines / stock | 6.630 / 7.156 | 11.187 | 196.61 |

Branch allocations fall **30.1%**, but peak RSS does not improve. The line median falls
**9.8%**. Both variants execute 308 examples. Separate full/input/fault sharing smoke
checks reproduce oracle failure IDs. Dynamic loading and snapshot ownership still need
broader parity tests before production adoption.

## Semantic changes and omitted failures

The main source-fault runs compare selected and failing IDs against independent full
RSpec oracles. All measured source-fault cases have zero omitted oracle failures.

The extra input probe changes a Ruby expected value and flips Rails' `comments_enabled`
JSON value. In 20 repetitions per fixture, Ruby selects 38/38 and reproduces one expected
failure; Rails selects 16/308 and reproduces one expected failure. There are **zero
omitted failures and zero status mismatches**. Rails' probe p50/p95 is **1.478 / 1.507 s**.

This is bounded evidence for the exercised mutations. It does not prove completeness
for arbitrary Ruby, memoized external state, metaprogramming, undeclared ENV, new dynamic
examples, or concurrent tests.

## Real Coverage scaling and Ruby releases

The standalone workload loads executable methods and executes every file during setup.
Each iteration touches one file by default and verifies its result and the exact changed
file count. Every file has 60 branch sites. Each case has 20 iterations, with before/after
snapshot samples. YJIT is explicitly disabled.

```sh
FILES=500 BRANCH_SITES=60 TOUCHED=1 ITERATIONS=20 MODE=branches ruby --disable-yjit benchmark/evidence/coverage.rb
```

The matrix, command arrays, environment, orchestration, and every micro-sample are saved.

| MRI | Line snapshot p50 / p95, ms | Branch snapshot p50 / p95, ms | Branch allocations p50 |
| --- | --- | --- | --- |
| 3.3.10 | 0.076 / 0.208 | 21.328 / 33.091 | 121501 |
| 3.4.12 | 0.084 / 0.650 | 21.189 / 29.079 | 121501 |
| 4.0.9 | 0.085 / 0.186 | 19.748 / 25.493 | 121501 |

All releases allocate **121,501 objects per 500-file branch snapshot** at p50. Updating
the runtime does not remove this structural cost in the releases tested. Development
head improvements described in the research must not be assumed present in these builds.

On MRI 3.3.10, 100, 500, and 2,000 tracked files give branch snapshot p50 values of
**4.509, 21.328, and 82.797 ms**, while only one file executes per iteration.
At 500 files, existing-snapshot keys cost **2.04 microseconds**; another snapshot
requested only for keys costs **18.571 ms**.

Equivalent normalization takes **176.54 microseconds and 502 allocations** with
`each_with_object` versus **60.53 microseconds and one allocation** with `each_pair`.
Both return the same map. This is a loop comparison, not a measured complete-adapter
speedup.

Ruby TracePoint demonstrates an event-volume tradeoff. One-file execution takes
**10.13 microseconds**, versus **0.80** without collection. Touching all 500 files takes
**5.512 ms** with TracePoint, **0.420 ms** without collection, and **1.025 ms** for the
line-coverage body before its snapshot/scan costs. This collector does not supply
per-example line history or establish real-application dependency equivalence.

## Ranked decision

1. **Remove the redundant loaded-file snapshot.** The paired complete-command result
   supports this first. Define ownership and prove dynamic-load/failure-path parity.
2. **Remove normalization allocations and repeated attribution work.** The actual-result
   loop comparison identifies a concrete Ruby candidate. Measure the full change before
   assigning it an end-to-end percentage.
3. **Prototype an optional Rust file-event collector through public TracePoint APIs.**
   Start with explicit dependency-only output. Retain Ruby fallback and the existing
   line-delta path when historical line outputs require it. No native extension was built.
4. **Pursue producer-side mode/file filtering with the runtime owner.** Calling unfiltered
   `peek_result` from Rust retains the principal cost. Private VM layouts or a required
   custom MRI fork are no-go for the default gem.
5. **Gate graph/cache/native-consumer ports on larger real workloads.** Their present
   measured costs do not justify first priority. Require at least 10% complete-run
   improvement including conversion/FFI, no worse p95/RSS, exact behavior parity, and
   working engine fallback. The [inventory](PERFORMANCE_INVENTORY.md) gives the checks.

Do not port Coverage merely to change C counters into Rust counters. Supercov combines
Rust probe planning with Ruby Coverage/probes and is a reference, not a compatible
replacement. Magnus and rb-sys provide bindings. rbspy samples stacks and cannot
guarantee complete per-example dependencies. None of the inspected candidates was
validated here as a drop-in collector for the entire supported interpreter matrix.

## Artifacts and verification

- [Stock metadata and exact locks](results/2026-11-04-issue-3/stock/metadata.json);
  [stock summary](results/2026-11-04-issue-3/stock/summary.json).
- [Paired summary](results/2026-11-04-issue-3/paired/summary.json).
- [Semantic-input summary](results/2026-11-04-issue-3/input-fault/summary.json).
- [Direct RSpec summary](results/2026-11-04-issue-3/plain/summary.json).
- [VM measurements](results/2026-11-04-issue-3/vm/summary.json).
- Each dataset contains `runs.jsonl.gz`. [SHA256SUMS](results/2026-11-04-issue-3/SHA256SUMS)
  covers the published evidence.

```sh
gzip -dc benchmark/results/2026-11-04-issue-3/stock/runs.jsonl.gz
cd benchmark/results/2026-11-04-issue-3
sha256sum -c SHA256SUMS
```

Observed local verification on Ruby 3.3.10:

| Command | Result |
| --- | --- |
| `task check` | Passed; 2,167 examples, 0 failures, 2 pending; cold/warm smoke ratchets passed |
| `bundle exec rubocop benchmark/evidence --format simple` | Four files inspected, no offenses |
| `task lint:actions lint:yaml check:bundle` | Passed |
| `task reporters:html:build lint:node` | Build, ESLint, and formatting passed |
| `task docs:leak-check reporters:html:check` | Tracked-document scan and deterministic bundle drift check passed |
| `npm audit --audit-level=high` in the HTML frontend | Passed; 0 high, 7 moderate advisories |

The property checks, 15-subject mutation smoke, and dogfood check also passed during
this investigation. The independent source/spec and semantic-input fault runs in
the published evidence found no omitted failing examples or exit-status mismatches.
The discovery guard was observed failing with an intentionally misplaced observer
(`0 != 38`), then passing for full, warm, fault, and two-worker executions.

The authorized frontend dependency refresh upgrades Vite from 8.0.16 to 8.3.5,
the current stable release in the [regularly patched Vite branch](https://vite.dev/releases).
The committed JavaScript bundle was rebuilt. An actual generated Ruby-fixture report
was served over local HTTP and checked in Chrome: hydration, text filtering, dependency
tabs, and column sorting worked, with no browser errors or console messages.
The [captured reporter](results/2026-11-04-issue-3/reporter-vite-8.3.5.png) shows the
rebuilt frontend. Local `file:` loading showed the static fallback; the interactive
check used HTTP so browser module restrictions did not mask the build.

The root bundle advisory check passed using the pinned audit tool with an explicit
writable advisory database (`bundle-audit check --update --database
/home/sebastian/.cache/testsift-ruby-advisory-db`). The canonical local task could not
update its default database in the read-only home path. Trivy completed and reported
two inherited Puma 6.6.1 advisories in fixture locks (CVE-2026-47736 and
CVE-2026-47737). These fixture versions remain part of the frozen measurement input.
No production collector or Rust extension is implemented by this evidence PR.
