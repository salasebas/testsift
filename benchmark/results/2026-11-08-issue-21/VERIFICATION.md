# Verification

Observed on 2026-11-08 on macOS with MRI 3.3.10, after the final code change:

| Command | Result |
| --- | --- |
| `task lint:ruby` | 261 files, no offenses |
| `task lint:actions lint:yaml check:bundle` | Passed |
| `task security:bundle-audit security:trivy` | Passed |
| `task test:unit` | 2,187 examples, zero failures, two pending LocalStack cases |
| `task test:property` | 25 examples, zero failures |
| `task test:mutation:smoke` | 308 mutations, 93.18% coverage |
| `task test:dogfood` | Passed |
| `task test:integration` | 19 examples, zero failures |
| `task test:integration:parallel` | 7 examples, zero failures |
| `task test:features:ruby` | 12 examples, zero failures |
| `task benchmark:smoke` | Cold p50 0.267 s against 0.451 s; warm p50 0.263 s against 0.404 s |
| `shasum -a 256 -c SHA256SUMS` in this directory | All files passed |

## Tests that guard the change

Each new test was observed failing before it was trusted:

- `spec/engine_spec.rb`, two snapshots per example with loaded-file tracking
  enabled. The pre-change engine made three `Coverage.peek_result` calls.
- `spec/engine_spec.rb`, a file present in the finish snapshot without new line hits
  is attributed to that example. Passing `[]` instead of the finish snapshot's paths
  made it fail.
- `spec/integration/loaded_files_tracking_spec.rb` runs RSpec in a subprocess with
  real Coverage and real `require`, `load`, and `autoload` in hooks, bodies, and
  `before(:context)`. Its expectations come from the loaded-file contract: a file
  first loaded during or before an example belongs to that example and every later
  one, and configured filters exclude it. It passed on the pre-change engine and
  failed both examples when the engine passed `[]` to the tracker.
- `spec/tracker/coverage_adapter_spec.rb` and `spec/engine_spec.rb`, filters are
  evaluated once per path per run. Both failed on the pre-change code. The adapter's
  per-path decision spec failed when the memo used one key for every path; the same
  break in the engine failed 20 existing engine and integration examples.

The removed tracker spec covered a `Coverage` call inside `stop_example` that no
longer exists. The engine's own snapshot at the same boundary still raises first
on that condition, so the failure surface is unchanged.

## Measurement checks

Every campaign exited successfully. The driver exits nonzero on omitted failures,
status mismatches, unexpected warm selections, worker-count mismatches, or missing
independently required paths. The 238 retained rows hold 542 oracle-failure
observations, zero omitted failures, and zero status mismatches.
