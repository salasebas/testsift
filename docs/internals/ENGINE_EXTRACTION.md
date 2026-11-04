# Runner-neutral engine extraction

This reference tracks issue [#6](https://github.com/salasebas/testsift/issues/6).
The target is the fork's `testsift` development branch,
`03173c22b32b0accaccf37a5e662487b3bc79c50`, based on upstream rc.1.
Initial characterization also used the workspace's starting revision,
`7c75cc3a1f6e1cd4929a87b77da0b7daa0369685`. The four upstream commits
between these baselines are not imported by this extraction.

## Coupling inventory before extraction

| Area | Baseline dependency | Intended owner |
| --- | --- | --- |
| Installation | `rspec_tracer.rb` requires `rspec/installation`, which requires `rspec/core` and prepends runner and reporter hooks. | RSpec entry point |
| Discovery and execution | `rspec/runner_hook.rb` walks `RSpec.world.filtered_examples`, rewrites groups and descriptions, prunes duplicate identities, and calls RSpec's runner. | RSpec adapter |
| Identity | `example.rb` reads RSpec metadata, parent groups, shared inclusion locations, and unnamed sibling ordinals. Its MD5 determines cache identity. | RSpec adapter, unchanged identity algorithm |
| Lifecycle | `rspec/reporter_hook.rb` receives framework events and sends RSpec execution-result objects into Engine. | RSpec adapter converts results to ordinary hashes |
| Rails suite callbacks | `engine.rb` calls `RSpec.configure` and reads `RSpec.configuration.use_transactional_fixtures`. | RSpec adapter |
| Collection | Engine combines Ruby Coverage deltas, loaded files, I/O buckets, Rails notifications, and declared inputs. | Engine and existing observers |
| Selection | Engine fingerprints files and ENV, restores history, and calls the identifier-based graph and filter. | Engine |
| Configuration | `configuration.rb` includes RSpec-only ignored-spec policy and parallel worker directory scoping. Engine defaults to the global `RSpecTracer` configuration. | Existing DSL stays at the RSpec entry point; Engine accepts an explicit configuration |
| Worker cache | Engine calls global `RSpecTracer.parallel_tests?` to choose a parent read directory. | Adapter supplies the read directory |
| Persistence | Engine builds storage snapshots, keeps skipped coverage, and applies retention through the backend factory. | Engine, unchanged schema |
| Reports | Snapshot reporters use stored RSpec presentation fields. `CoverageJsonReporter` reads the global engine, configuration, and SimpleCov state; parallel merging lives in `rspec/parallel_tests.rb`. | Existing RSpec product orchestration; no report format migration |
| Exit | `rspec_tracer.rb` preserves RSpec's exit and fails duplicates when configured. | RSpec entry point |

The existing `require 'rspec_tracer/engine'` does not itself load RSpec,
but `setup` registers RSpec callbacks if RSpec is present and reads global
parallel state. That is load isolation without a usable isolated lifecycle.

## Behavior evidence

Existing tests own cold and warm caches, file changes, failed and flaky
history, pending examples, duplicate identities, declared ENV, coverage modes,
and failing-run SQLite persistence. The extraction extends these tests only
where the boundary is not exercised. New isolation checks must run in a fresh
Ruby process because the outer test runner has already loaded RSpec.

Before adding a test, its failure, requirement, and missing existing coverage
are recorded here:

| Check | Failure caught | Requirement and gap |
| --- | --- | --- |
| Standalone engine lifecycle | Setup or result recording requires RSpec constants, global configuration, or an RSpec result object. | Issue #6 requires loading and exercising the core without RSpec. Existing engine tests run inside RSpec. |
| RSpec setup, body, and teardown inputs | A lifecycle boundary excludes hooks or an around-hook tail. | Issue #6 requires complete per-test attribution. Existing hook unit tests only check dispatch. |
| Registration ordering | Selection runs before all discovered identifiers and declarations reach the core. | Issue #6 requires registration before selection. Existing ENV tests cover declarations but not the full boundary. |
| Rails suite callback failures | An unavailable observer or missing rspec-rails setting escapes the suite callback or emits misleading schema advice. | The repository requires graceful degradation. The moved eager and late-bind tests did not cover failure while a callback executes. |
| New, pending, skipped, and interrupted tests through RSpec | A new identity is filtered out, deferred outcomes are lost in conversion, or an early exit loses interrupted registrations. | Issue #6 requires these entry-point scenarios. Existing tests constructed core state directly. Astra review S1 identified the missing evidence. |

## Pending inherited defects and limitations

Issues #2 and #3 remain open dependencies of #6. This change records its own
coupling inventory and before/after measurements; it does not claim to finish
the broader feature inventory or performance study.

Additional confirmed baseline defects and verification results are recorded
below as they are reproduced.

- Warm JSON reports show `execution_result.status` as `unknown` for skipped
  passing tests. The cache still contains `passed`. Reproduced on the baseline
  and the extracted engine with the same cold/warm project. JSON decoding
  symbolizes the metadata row but leaves the nested execution-result keys as
  strings; `PayloadBuilder#normalize_execution_result` reads only symbols.
  Follow-up: normalize nested result keys for all storage backends and add a
  report-level regression. This extraction preserves the persisted result.
- The advertised ten-second `task check` budget is already exceeded on this
  machine. The fork baseline ran 2,167 examples in 81.69 seconds, before
  the benchmark. The extraction ran 2,177 in 71.27 seconds. The default unit command includes subprocess integration
  tests. Follow-up: separate the fast suite from subprocess integration tests
  without reducing per-PR checks.
- The imported rc.1 SQLite backend cannot reliably persist a failing run.
  Upstream PR #277 fixes this after the fork's baseline. It is absent from
  `testsift`, as documented in `FORK.md`, and remains pending here. This
  extraction does not port that fix or claim failing-run SQLite parity with
  upstream main.
- Mutation smoke reports a passing percentage despite neutral failures in
  `LoadedFilesTracker::DEFAULT_PEEK`: the test calls real Coverage while
  mutation mode disables coverage startup. Reproduced on the original source
  with `RSPEC_TRACER_DISABLE=1 bundle exec mutant run --use rspec --usage
  opensource --include lib --require rspec_tracer/tracker/loaded_files_tracker
  'RSpecTracer::Tracker::LoadedFilesTracker#build_inputs'`. Follow-up: make
  the test independent of global Coverage state and reject neutral failures
  in the mutation gate. Its percentage is not proof for affected methods.
- The unchanged HTML reporter development lockfile currently fails
  `npm audit --audit-level=high`, with 16 vulnerable dependency entries,
  8 moderate and 8 high. `package.json`, `package-lock.json`, and the
  reporter bundle are unchanged. Follow-up: update and verify the reporter
  toolchain separately. This is a security-check blocker, not an engine
  extraction regression.
- Trivy reports two high-severity advisories for Puma 6.6.1 in the generated
  Rails fixture lockfile, CVE-2026-47736 and CVE-2026-47737. The fixture
  Gemfile still pins Puma 6.x. Follow-up: update the fixture server dependency
  and verify the supported Rails matrix. The configured Trivy command exits
  zero while reporting these findings; that exit does not mean a clean scan.
- Rails 7.1.6 with unconstrained `json` 3.1.0 raises `unknown keyword:
  quirks_mode` while ActiveSupport serializes the existing RSpec identity.
  Both baselines fail on the unchanged `Example.from` implementation.
  Benchmark preparation uses an explicit temporary JSON 2.21.2 bundle.
  Follow-up: establish a compatible dependency policy without changing cached
  identity bytes accidentally.
- The benchmark runner drops failed scenarios with `filter_map`, and the
  long-running fork scenario does not check child exit status. A successful
  command can therefore omit failures. Follow-up: fail the benchmark if any
  scenario or child fails. Retained results below explicitly require all 14
  scenarios with 10 samples each, plus direct Rails behavior checks.

## Core lifecycle contract

Load `rspec_tracer/engine`, then construct
`Engine.new(configuration:, read_cache_path: nil)`. The configuration is an
ordinary Ruby object with the existing engine settings. It does not need the
top-level configuration loader. `read_cache_path` lets a worker restore the
merged cache while writing to its own configured `cache_path`.

1. Call `setup` before application code loads. It starts Ruby Coverage only
   when no owner has started it, installs observers, and restores the cache.
2. Discover tests in the runner. Register every test with
   `register_example(example_id: ..., ...)`, then register each declaration
   with `register_tracks(id, files: Set[...], env: Set[...])`. Records are
   mutable hashes retained by the engine; registration preserves stored
   fields absent from the fresh metadata. The runner constructs identities.
3. After registration completes, call `apply_env_filter_decisions`. Query
   `run_example?(id)` and `run_example_reason(id)`. The engine retains reason
   precedence. Mark filtered tests with `on_example_skipped(id)`.
4. Call `deregister_duplicate_examples` after discovery. The adapter drops
   colliding identities and applies its configured duplicate exit policy.
5. For each selected test, call `example_started` before setup and
   `example_finished(id)` after all teardown, including the tail of around
   hooks. Observations cover this whole window on the executing thread.
6. Record the outcome with `on_example_passed`, `on_example_failed`, or
   `on_example_pending`, passing the id and an ordinary hash containing UTC
   `started_at`, UTC `finished_at`, numeric `run_time`, and string `status`.
   The RSpec adapter converts `ExecutionResult`; the core never reads it.
7. Call `finalize` once at run exit. Registered tests without an outcome
   become interrupted. Completed results and skipped coverage retain the
   existing history and storage schema. Coverage stays running for its owner.
   The runner catches persistence errors and preserves its own exit status.

RSpec pending and explicit skip notifications retain the existing `pending`
outcome, which reruns. `on_example_skipped` denotes selection from a previous
passing cache, not a framework skip. Failed-to-passed transitions become
flaky, and flaky history remains sticky.

Identities are scoped to a runner and project cache. An adapter must use a
separate cache or a runner namespace if another framework can produce the
same id. RSpec's identity bytes remain unchanged, including the documented
positional rule for unnamed examples. Group and suite work outside an example
window retains the existing boot-set and loaded-file attribution policy.

The callback boundaries follow
[RSpec's example lifecycle](https://github.com/rspec/rspec-core/blob/v3.13.6/lib/rspec/core/example.rb).
Coverage peeks follow
[Ruby's non-destructive Coverage API](https://docs.ruby-lang.org/en/3.3/Coverage.html#method-c-peek_result).

`ruby -Ilib spec/core/engine_lifecycle.rb` exercises the isolated contract.
Before extraction it fails in `Engine#build_read_backend` because the global
`RSpecTracer.parallel_tests?` method is unavailable. After extraction it
exercises JSON persistence, cold/warm selection, explicit worker read paths,
changed inputs, normalized results, and interruption without defining RSpec.

## Verification

Verification uses Ruby 3.3.10 on Linux x86_64, Intel Core i7-1355U, with
RSpec Core 3.13.6, expectations 3.13.5, mocks 3.13.8, Docile 1.4.1, and Task
3.45.4. Gems and pinned repository tools were installed for these checks.
LocalStack 4.14.0 and Redis 7 run in dedicated local containers.

| Command | Observed result |
| --- | --- |
| `task check` | 244 Ruby files without lint offenses; 2,177 examples, zero failures, no pending examples; both smoke benchmarks pass unchanged limits. |
| `ruby -Ilib spec/core/engine_lifecycle.rb` | Exit 0; RSpec absent before and after the lifecycle. |
| `bundle exec rspec spec/engine_spec.rb spec/engine_rails_spec.rb spec/engine_isolation_spec.rb spec/rspec spec/integration/engine_boundary_spec.rb` | 228 examples, zero failures with tracer self-instrumentation disabled. |
| `task test:property` | 25 examples, zero failures. |
| `task test:edge-cases` | 109 examples, zero failures. |
| `task test:regressions:plain` | 8 examples, zero failures. |
| `task test:fuzz:full` | 10,000 iterations per harness; no crashes. |
| `task test:features:rails` | 13 examples, zero failures, including golden coverage equality. |
| Rails 7.1.6 fixture with the compatible JSON bundle, `bundle exec rspec --no-color` | 308 examples, zero failures. |
| `task test:dogfood` | Cold and warm fixture runs pass. |
| `task test:integration:parallel` | 7 examples, zero failures, including merged reports and warm selection. |
| `task test:integration:remote-cache` | 14 examples, zero failures against LocalStack. |
| `task test:integration:remote-cache:redis` | 15 examples, zero failures against Redis. |
| `task test:mutation:smoke` | All configured percentage gates pass; see the inherited neutral-failure limitation above. |
| `task test:mutation:rspec` | All gates pass; RunnerHook 88.82%, ReporterHook 98.82%. |
| `task lint:actions`, `task lint:yaml`, `task check:bundle`, `task docs:leak-check` | Pass. |
| `task lint:node`, `task reporters:html:check` | Pass; no generated bundle changes. |
| `task security:bundle-audit` | No vulnerabilities found. |
| `task security:trivy` | Completes and reports two inherited Puma findings in the Rails fixture. |
| `npm audit --audit-level=high` | Fails on the unchanged reporter lockfile; pending above. |

The six entry-point scenarios also pass against the unmodified `testsift`
baseline. Temporary process-local mutations prove the new assertions detect
pending outcomes converted to `failed`, interrupted registrations treated as
passed, and a new identity incorrectly filtered from a warm run. Each
mutation fails its focused scenario; the production code passes all six.

The standalone core test fails before extraction on the global
`parallel_tests?` access. The ordering check fails before extraction because
ENV selection precedes example registration. The reporter conversion check
fails before extraction because the engine receives an RSpec object. These
checks pass after extraction. The Rails callback test also fails when its
error containment is removed in an isolated copy.

The RSpec, Rails, parallel, and remote-cache checks were run before aligning
the branch with `testsift`. Rebase conflicts only removed the callbacks and
tests already moved by this change. The rebased engine and engine test files
match the reviewed extraction; the 228 focused tests and complete
`task check` were rerun on the target branch.

## Before and after overhead

[Raw samples and environment](../../benchmark/engine_extraction.json) contain
14 scenarios, 10 repetitions per side, and 280 timings. Baseline and
implementation checkouts both use btrfs on the same host. Initial tmpfs
measurements are excluded. The measured implementation is `1a77a71`; later
commits only add this evidence.

Each cell below is p50 / p95 in seconds. Measurements include the existing
scenario's process boot, discovery, cache work, and reports. The fork scenario
amortizes Rails boot as documented by the existing benchmark.

| Scenario | Before | After |
| --- | --- | --- |
| Ruby cold | 0.2469 / 0.3366 | 0.2361 / 0.2697 |
| Ruby warm, no change | 0.2253 / 0.2478 | 0.2200 / 0.2281 |
| Two workers, cold | 1.4836 / 1.5242 | 1.5219 / 1.7358 |
| Rails models, cold | 2.5638 / 4.7311 | 2.4861 / 2.5603 |
| Rails full suite, cold | 7.0725 / 11.5290 | 6.7084 / 7.6573 |
| Rails full suite, fork after boot | 4.1093 / 4.2237 | 4.1740 / 4.5629 |

The retained after measurements pass `BenchmarkHarness.compare_to_ratchet`
against the unchanged `benchmark/ratchet.json`: 13 OK, one informational
parallel scenario. Ruby fixture cache identities match across revisions,
schema 5 and run id `62cc4d6690357b3ec61f9512d3050bd6`. Both final Rails fork
reports contain 308 passed examples with no failures or interruptions, and
share run id `2e83f6429509b873e7d62eba337c55a7`.

The command is `ruby benchmark/harness.rb --full --iterations 10 --ratchet
benchmark/ratchet.json --no-enforce`. The three Rails scenarios are replaced
with compatible-bundle measurements using the same
`BenchmarkHarness.run_scenario` calls. The temporary Gemfiles use Bundler's
`eval_gemfile` to load each fixture Gemfile, then add `gem 'json', '~> 2.21.0'`.
Their environment sets `RAILS_VERSION='~> 7.1.0'`,
`RSPEC_RAILS_VERSION='~> 6.1.0'`, `SQLITE3_VERSION='~> 1.4'`, and
`BUNDLE_GEMFILE` to the matching temporary file. Resolved versions are Rails
7.1.6, rspec-rails 6.1.5, sqlite3 1.7.3, and json 2.21.2.

Sequential blocks on a shared workstation include background-load and CPU
frequency variation. The unchanged standalone coverage microbenchmark also
shifted by +25.8%, which limits causal interpretation of small median
differences. ENV mismatch scenarios invalidate only the first measured
iteration, following the existing benchmark. This compares extraction cost;
plain-RSpec overhead and the broader profiling study remain in issue #3.

## Review outcome

Three fresh Astra reviews covered the implementation and evidence. Round 1
requested real RSpec coverage for new, pending, and interrupted tests. Those
scenarios and their deliberate failure checks resolved S1. Round 2 approved
the implementation against `testsift`. Round 3 approved the timing artifact,
ratchet evaluation, and reporting limits. No review findings remain open.
