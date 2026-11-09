# Upstream inventory

TestSift imports [rspec-tracer](https://github.com/avmnu-sng/rspec-tracer) at
`v2.0.0.rc.1` (`f13851f7`, MIT). This page separates what that baseline already
does, what upstream fixed after the tag, and what upstream still plans. Upstream
milestones and version numbers are inputs, not TestSift release requirements.

Sources, all public: the
[rc.1 release](https://github.com/avmnu-sng/rspec-tracer/releases/tag/v2.0.0.rc.1),
the [post-tag comparison](https://github.com/avmnu-sng/rspec-tracer/compare/f13851f7b3393aaafa7c7df088c1605747f07ce5...7c75cc3a1f6e1cd4929a87b77da0b7daa0369685),
and the [milestones](https://github.com/avmnu-sng/rspec-tracer/milestones),
read on 2026-11-08. Upstream `main` was still `7c75cc3a1f`.

Statuses:

- **Adopt:** keep as shipped.
- **Adapt:** keep the goal, redesign it for this fork.
- **Defer:** not in the current TestSift scope.
- **Exclude:** out of scope for an engineering repository.

## Inherited features

Each verification command runs on the pinned MRI from the repository root; the
2026-11-08 results follow the table. Feature names are not guarantees; the
limitation column states what the check does not cover.

| Feature | Baseline implementation | Verification | Limitations | TestSift status |
| --- | --- | --- | --- | --- |
| Dependency graph and SHA256 invalidation | `lib/testsift/tracker/dependency_graph.rb`, `file_digest.rb`, `filter.rb` | `bundle exec rspec spec/tracker/dependency_graph_spec.rb spec/tracker/filter_spec.rb spec/properties` | Selection is only as complete as the observed inputs | Adopt; engine extracted in #6 |
| Coverage-diff and loaded-file attribution | `tracker/coverage_adapter.rb`, `tracker/loaded_files_tracker.rb` | `bundle exec rspec spec/integration/loaded_files_tracking_spec.rb spec/integration/constants_regression_spec.rb` | Code executed between examples outside a load is not attributed | Adopt; snapshot shared in #21 |
| File, glob, and ENV declarations | `tracker/declared_globs.rb`, `env_snapshot.rb`, `rspec/metadata.rb` | `bundle exec rspec spec/tracker/declared_globs_spec.rb spec/tracker/env_snapshot_spec.rb spec/integration/per_example_dsl_spec.rb` | Undeclared ENV branches are invisible | Adopt |
| I/O read hooks | `tracker/io_hooks/` | `bundle exec rspec spec/tracker/io_hooks spec/properties/io_hooks_thread_safety_spec.rb` | Native extensions reading files bypass the hooks | Adopt |
| Rails observers and presets | `lib/testsift/rails/` | `task test:features:rails` | Eager loading over-approximates dependencies | Adapt in #13 |
| RSpec and parallel_tests integration | `rspec/runner_hook.rb`, `rspec/reporter_hook.rb`, `rspec/parallel_tests.rb` | `task test:integration:parallel` | Only parallel_tests is validated as a worker runner | Adopt; worker reuse in #11 |
| JSON storage | `storage/json_backend.rb` | `bundle exec rspec spec/storage spec/contracts` | Whole-cache rewrite on every run | Adopt; cost measured in #28 |
| SQLite storage | `storage/sqlite_backend.rb` | `bundle exec rspec spec/storage/sqlite_backend_spec.rb spec/integration/sqlite_failing_run_spec.rb` | MRI only; sqlite3 1.x re-raised a pending exit (fixed in #4) | Adopt with the #4 fix |
| Remote caches (S3, filesystem, Redis) | `lib/testsift/remote_cache/` | `bundle exec rspec spec/remote_cache` | S3 and Redis need their services; CI covers them with LocalStack and Redis | Adopt; coherence in #11 |
| Flaky-result history | `engine.rb` (`flaky_history?`), `reporters/` | `bundle exec rspec spec/integration/flaky_detection_spec.rb` | Sticky flag, no trend | Adopt |
| Diagnostics CLI (`doctor`, `explain`, `blast-radius`, `cache:*`) | `lib/testsift/cli/` | `bundle exec rspec spec/cli` | Reads the local cache only | Adopt |
| Reports (terminal, JSON, HTML, coverage JSON) | `lib/testsift/reporters/` | `bundle exec rspec spec/reporters` | HTML and JSON each build the shared payload | Adopt; payload sharing follows #28 |
| SimpleCov interoperability | `reporters/coverage_json_reporter.rb` (`SimpleCovInterop`) | `bundle exec rspec spec/reporters/coverage_json_reporter_spec.rb` | Lifecycle ownership is not yet specified | Adapt in #8 |

Results on 2026-11-08 (macOS, MRI 3.3.10, sqlite3 2.10.2), in table order:

| Verification | Result |
| --- | --- |
| Graph, filter, properties | 77 examples, 0 failures |
| Loaded-file attribution | 10 examples, 0 failures |
| Declarations and per-example DSL | 57 examples, 0 failures |
| I/O hooks | 24 examples, 0 failures |
| `task test:features:rails` | 13 examples, 0 failures |
| `task test:integration:parallel` | 7 examples, 0 failures |
| JSON storage and contracts | 252 examples, 0 failures |
| SQLite storage and red-run persistence | 41 examples, 0 failures |
| Remote caches | 385 examples, 0 failures |
| Flaky detection | 2 examples, 0 failures |
| CLI | 168 examples, 0 failures |
| Reporters | 224 examples, 0 failures |
| Coverage JSON and SimpleCov interop | 26 examples, 0 failures |

The red-run SQLite spec fails only with sqlite3 1.x, the Ruby 3.1 pin. With
sqlite3 1.7.3 forced outside Bundler, three consecutive red runs on the unfixed
library printed no at-exit summary after the first run and left the `meta`
timestamp unchanged; with the fix, every run persisted.

## Post-tag upstream commits

| Commit | Classification | TestSift decision |
| --- | --- | --- |
| [`ab9fef2414`](https://github.com/avmnu-sng/rspec-tracer/commit/ab9fef2414) docs: rewrite double-hyphen prose | Documentation | Defer; style-only |
| [`d19a20a4dc`](https://github.com/avmnu-sng/rspec-tracer/commit/d19a20a4dc) ci: release stub install version | Harness | Defer to #5, which owns the fork's release workflow |
| [`f44b48e142`](https://github.com/avmnu-sng/rspec-tracer/commit/f44b48e142) fix(storage): sqlite cache on failing runs | Runtime fix | Adapt in #4: reproduced on this fork with sqlite3 1.7.3 as a stale cache and missing at-exit summary, not as a zero-byte file. The fix isolates every SQLite connection from a pending exception and does not copy upstream's other changes. |
| [`7c75cc3a1f`](https://github.com/avmnu-sng/rspec-tracer/commit/7c75cc3a1f) fix(soak): cycle-aware memory baseline | Harness | Defer; the soak job is not a TestSift release gate |

## Open upstream work

### rc.2

| Upstream item | Decision | Reason and follow-up |
| --- | --- | --- |
| [#232](https://github.com/avmnu-sng/rspec-tracer/issues/232) `safety_mode` preset DSL | Defer | Presets need the shadow-run evidence from #9 to choose defaults |
| [#233](https://github.com/avmnu-sng/rspec-tracer/issues/233) Shadow mode, minimal | Adapt | Owned by #9, which checks proposed skips against full-suite results |
| [#234](https://github.com/avmnu-sng/rspec-tracer/issues/234) Flaky auto-quarantine | Defer | Changes test outcomes; no TestSift follow-up yet |
| [#235](https://github.com/avmnu-sng/rspec-tracer/issues/235) Flaky-test trending | Defer | Reporting feature; no TestSift follow-up yet |
| [#236](https://github.com/avmnu-sng/rspec-tracer/issues/236) Cost-calculator helper | Defer | Depends on measured savings from #16 |

### rc.3

| Upstream item | Decision | Reason and follow-up |
| --- | --- | --- |
| [#237](https://github.com/avmnu-sng/rspec-tracer/issues/237) Full shadow mode with missed-regression metric | Adapt | #9 owns shadow execution; the metric belongs to its report |
| [#239](https://github.com/avmnu-sng/rspec-tracer/issues/239) `track_class_attribution` (TracePoint) | Adapt | Collector choice belongs to #12, Rails precision to #13 |
| [#240](https://github.com/avmnu-sng/rspec-tracer/issues/240) Confidence scoring | Defer | Needs shadow-run data from #9 |
| [#241](https://github.com/avmnu-sng/rspec-tracer/issues/241) rc.1 and rc.2 polish | Exclude | Catch-all for upstream observation feedback |
| [#249](https://github.com/avmnu-sng/rspec-tracer/issues/249) Auto-fallback on low confidence | Defer | Depends on #240's score; TestSift already falls back on unknown or invalid state |

### 2.0.0 final

| Upstream item | Decision | Reason and follow-up |
| --- | --- | --- |
| [#238](https://github.com/avmnu-sng/rspec-tracer/issues/238) Soundness ledger on OSS Rails suites | Adapt | #20 and #31 run the OSS corpus; #16 owns real-project validation |
| [#250](https://github.com/avmnu-sng/rspec-tracer/issues/250) Reference adopter and case study | Defer | Follows #16 |
| [#251](https://github.com/avmnu-sng/rspec-tracer/issues/251) Conference talks | Exclude | Outreach |
| [#252](https://github.com/avmnu-sng/rspec-tracer/issues/252) Blog series and newsletter | Exclude | Outreach |
| [#253](https://github.com/avmnu-sng/rspec-tracer/issues/253) Community channels | Exclude | Outreach |

### 2.1.0

| Upstream item | Decision | Reason and follow-up |
| --- | --- | --- |
| [#242](https://github.com/avmnu-sng/rspec-tracer/issues/242)–[#244](https://github.com/avmnu-sng/rspec-tracer/issues/244) Anti-pattern detection | Defer | Analysis features after selection is validated |
| [#245](https://github.com/avmnu-sng/rspec-tracer/issues/245) Dependency graph CLI and HTML view | Defer | `explain` and `blast-radius` cover the current need |
| [#246](https://github.com/avmnu-sng/rspec-tracer/issues/246) DatabaseCleaner-aware narrowing | Adapt | Rails precision in #13 |

## Bugs and limitations

- **Fixed historical bugs:** the duplicate-example drop for nested groups (upstream
  #262, fixed in rc.1).
- **Confirmed baseline defects:**
  - SQLite persistence during a failing run's exit, fixed in #4.
  - An empty traced run returned `nil` from `RSpec::Core::Runner.run`, fixed with #21.
- **Published limitations:** the soundness tiers in `ARCHITECTURE.md`: undeclared
  ENV, native file reads, eager-load over-approximation, and refinements in
  unexecuted files.
- **Unexplained release delays:** rc.2 has no closed issues since rc.1 opened its
  observation period on 2026-07-13. Upstream gives no reason, and TestSift
  draws no conclusion from the gap.
