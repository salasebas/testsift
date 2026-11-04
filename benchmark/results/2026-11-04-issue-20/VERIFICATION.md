# Verification of the evidence tooling

Observed locally on MRI 3.3.10 on 2026-11-04:

| Command | Result |
| --- | --- |
| `task check` | 259 Ruby files without lint offenses; 2,179 examples, zero failures, two pending LocalStack cases |
| Smoke benchmark inside the final `task check` | Cold p50 0.3666 s against 0.451 s; warm p50 0.3713 s against 0.404 s |
| `task lint:actions lint:yaml check:bundle` | Passed; dependencies satisfied |
| `task security:bundle-audit` | No vulnerabilities; advisory database commit `516ea4757d5eec778c49af8371c23309c4b70f42` |
| `task security:trivy` | Passed with no security findings |
| `task test:property` | 25 examples, zero failures |
| `task test:mutation:smoke` | All 15 subjects passed their existing 90% minimum |
| `task test:dogfood` | One example, zero failures |
| `task docs:leak-check` | No internal nomenclature in tracked files |
| `sha256sum -c SHA256SUMS` in the issue #3 dataset | All 18 frozen files passed |
| `git diff --check` | Passed |

The final tracer-enabled unit sweep takes 91.11 seconds on this host. This is not a
claim that the full local check meets the documented ten-second target. The
expensive evidence campaigns remain opt-in; this change adds only two small
subprocess specs to the normal sweep. Product code and benchmark limits are
unchanged. Earlier tracer-enabled runs on this checkout also exceeded ten seconds.

Astra approved the final behavior after two review rounds. The single confirmed
finding was the dependency replay ordering corrected below; no findings remain open.

The generator spec catches incorrect generated results and missing real branch
sites. Its expectation comes from three branch sites per file, two real files,
and positive and negative calls. No existing test exercises the new generator.
Changing each increment from one to two produced the observed failure; restoring
the generator made the same spec pass.

The timing-bootstrap spec catches accidental allocator sampling in the timing
pass. It runs three measured calls without a native probe library and requires
three counters, successful exit, and no allocator result. Removing the no-op
allocator override produced a failed child after the first call. Restoring it
made the same spec pass. This test runs on the canonical Linux MRI 3.3 cell;
the evidence tool's platform requirements are documented in its guide.

Publication checks verified all recorded driver hashes against the measured driver
contents retained at the source commits linked in the report, dataset sample counts,
unique example IDs, consistent seed identities, zero warm selections, positive
fault oracles, no omitted failures or status mismatches, no allocator results in
timing passes, and unwrapped dry-run commands without benchmark telemetry.
The runtime study passed 48-cell count, driver/workload/binary hashes, actual JIT
states, iteration counts, and Coverage-file counts.

Clean, allocator, timing, startup, backend, and worker executions are retained in
the dataset rather than inferred from unit tests. Independent oracle artifacts
are retained alongside each dataset. Three clean repetitions and one timing
profile are exploratory evidence, with the limits described in [REPORT.md](REPORT.md).

CI is intentionally not awaited. The OSS runner and production-project measurements
remain outstanding in #31 and #20.

## Frozen dependency replay regression

Astra's first review found that corpus dependencies were appended after the first
Bundler install. That install could discard retained optional dependencies before
the second install resolved them again. The correction moves corpus preparation
before the inherited fixture preparation and avoids the redundant second install
when replaying a lockfile. The imported runner stays unchanged.

This command reproduced the defect, then passed with the same arguments and a new
output directory after the correction:

```sh
BUNDLE_FROZEN=true BUNDLE_PATH=/home/sebastian/.cache/testsift-bundle task benchmark:evidence:current -- --fixtures ruby --corpus sparse --modes dependency --cases warm --repetitions 1 --profiles 0 --lockfiles benchmark/results/2026-11-04-issue-20/sparse/metadata.json --output tmp/issue20-replay-regression-green
```

Before the fix, Bundler rejected the missing `msgpack` and `sqlite3` Gemfile entries
in frozen mode. After the fix, the complete command succeeded and warm selection
ran zero of 1,000 examples. The resulting fixture lockfile SHA256 remained
`5ca532c293c7eef2e9c4b5e3664b5ecad0bef42b8cf32c1c4227f203a3e79812`, identical to
the published sparse lockfile. This verification replay is additional to the
491 published measurement commands.
