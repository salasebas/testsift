# Shared example-boundary snapshot and per-run filter decisions

Measured on 2026-11-08. This dataset compares three engine revisions with the same
driver, fixtures, and dependency resolution:

| Label | Revision | Change |
| --- | --- | --- |
| baseline | `e225fbf` | Engine measured in the [issue #20 report](../2026-11-04-issue-20/REPORT.md) |
| shared snapshot | `fb36816` | Loaded-file tracking reads the example-finish snapshot ([#21](https://github.com/salasebas/testsift/issues/21)) |
| per-run decisions | `bb26fc3` | Filters decided once per path, file names reused, native line-array comparison ([#22](https://github.com/salasebas/testsift/issues/22), first slice) |

The issue #20 and issue #3 datasets are unchanged. Absolute times here are not
comparable with them: this is a different host. Only rows inside this dataset are
compared with each other.

## Protocol and provenance

Every campaign ran in the pinned Linux container from
`task benchmark:evidence:docker` (MRI 3.3.10, `aarch64-linux`) on OrbStack 2.2.5
with Docker 29.8.2. The physical host is an Apple M5 Pro MacBook with 18 logical CPUs
and 48 GiB of memory running macOS 26.7.2. Metadata records the VM kernel
`7.2.12-orbstack` and affinity `0-17`; the ARM VM exposes no CPU model name. The
host was also used interactively, so load varied between campaigns.

Each cell has three clean repetitions and one exclusive timing profile, except the
warm confirmation datasets, which have five clean repetitions and no profile.
Nearest-rank p95 is the largest clean sample. Rails runs replay the dependency
resolution retained in `../2026-11-04-issue-20/stock/metadata.json`. Each
`metadata.json` pins the engine revision, driver hashes, lockfiles, and command.
Campaigns ran in series in this order: Rails for `e225fbf` and `fb36816`,
then large for both; Rails and large for `bb26fc3`, a second large baseline, then sparse
for `bb26fc3` and `e225fbf`; finally warm confirmation for `bb26fc3`, `e225fbf`,
and `bb26fc3` again.

The 12 datasets have 238 measured commands, including 30 warm confirmation
commands. They also hold 542 repeated oracle-failure observations, with zero omitted
failures and zero status mismatches. Generated full runs pass the independent
required-path checks. Every warm cell selects zero examples.

## Snapshots per example

| Workload | `e225fbf` | `fb36816` | `bb26fc3` |
| --- | ---: | ---: | ---: |
| Rails, 308 examples, full branches | 928 | 620 | 620 |
| Sparse, 1,000 examples, full lines | 3,003 | — | 2,003 |
| Large, 10,000 examples, full lines | 30,003 | 20,003 | 20,003 |

These are actual `Coverage.peek_result` call counts from the timing profiles.
Boot capture, the example-start snapshot, the example-finish snapshot, and the
coverage report remain; only the duplicate loaded-file snapshot is gone.

## Complete commands

Seconds are clean p50 / p95. The selected column is identical for every revision.

| Workload | Selected | `e225fbf` | `fb36816` | `bb26fc3` | Change |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rails full branches | 308 | 11.31 / 11.43 | 8.17 / 8.17 | 8.43 / 9.24 | −25.5% |
| Rails source defect, branches | 308 | 12.14 / 12.88 | 8.32 / 8.33 | 8.61 / 9.58 | −29.1% |
| Rails input change, branches | 16 | 1.50 / 1.71 | 1.22 / 1.23 | 1.22 / 1.31 | −19.0% |
| Rails full lines | 308 | 3.63 / 3.71 | 3.19 / 3.22 | 2.90 / 3.23 | −20.1% |
| Rails source defect, lines | 308 | 3.65 / 3.66 | 3.20 / 3.20 | 3.08 / 3.17 | −15.5% |
| Rails warm lines | 0 | 0.88 / 0.99 | 0.81 / 0.81 | 0.89 / 0.90 | +1.4% |
| Large full lines | 10,000 | 17.77 / 17.84 | 16.83 / 16.89 | 10.38 / 11.14 | −41.6% |
| Sparse full lines | 1,000 | 1.86 / 1.95 | — | 1.02 / 1.03 | −45.3% |
| Sparse full branches | 1,000 | 5.59 / 5.95 | — | 3.39 / 3.45 | −39.4% |
| Sparse two-worker merge, lines | 1,000 | 2.40 / 2.47 | — | 1.96 / 1.97 | −18.3% |
| Sparse two-worker merge, branches | 1,000 | 4.14 / 4.30 | — | 2.97 / 3.02 | −28.2% |

Change compares the unrounded `bb26fc3` and `e225fbf` medians. The second large
baseline measured 18.39 / 18.58 seconds for full lines, so the large improvement is
not host drift. Every p95 in the table also improves.

Peak single-process RSS medians move between −7.3% and +8.4% against the baseline.
Full commands move at most +6.4% (Rails branches: 222,640 KiB against 209,244 KiB)
and +4.0% (sparse branches); the two-worker merge cells move +8.4% (lines) and
−7.3% (branches). Seven cells have three-sample ranges that do not overlap the
baseline: four higher (Rails defect branches, sparse full lines and branches,
sparse merge lines) and three lower (Rails input change lines, Rails warm lines,
sparse merge branches). The new per-run tables hold one small entry per observed
path, a few hundred on these fixtures, so they do not account for megabyte
shifts. This dataset does not attribute the RSS changes. A quiet host with more
repetitions is required before any memory claim, and a native candidate's
no-worse-RSS gate must be measured against this revision.

## Allocations

Ruby objects allocated per complete full command, clean medians:

| Workload | `e225fbf` | `fb36816` | `bb26fc3` |
| --- | ---: | ---: | ---: |
| Large full lines | 106,395,503 | 101,087,919 | 36,872,501 |

Large warm commands allocate 43,777,4xx objects on all three revisions, which
shows that they execute the same work.

## Warm runs

The first large campaign measured warm lines at 7.39 s for `e225fbf` and 8.16 s for
`bb26fc3`. No changed method runs in a warm command: every example is skipped, so
neither snapshot normalization nor attribution executes. The largest profile
component change is 0.22 s in reports, and the allocation counts above are equal.
The interleaved confirmation ran `bb26fc3`, `e225fbf`, and `bb26fc3` again
with five repetitions each:

| Pass | Warm p50 (s) | Warm samples (s) |
| --- | ---: | --- |
| `bb26fc3` first | 9.74 | 7.78, 9.41, 9.74, 9.82, 10.68 |
| `e225fbf` | 9.10 | 8.34, 8.41, 9.10, 10.24, 10.38 |
| `bb26fc3` second | 8.02 | 8.00, 8.02, 8.02, 8.07, 8.20 |

Host load changed during these passes, and the distributions overlap. These
measurements do not show a warm regression or a warm improvement. A quiet,
paired host is still required for any stable warm-tail claim.

## Component costs

Exclusive seconds from the large full-lines timing profiles. Labels match the
issue #20 report.

| Label | `e225fbf` | `fb36816` | `bb26fc3` |
| --- | ---: | ---: | ---: |
| Snapshot production | 2.36 | 1.73 | 2.50 |
| Normalization | 2.70 | 2.78 | 0.84 |
| File attribution | 5.89 | 6.02 | 0.99 |
| Dependency delta scan | 0.69 | 0.68 | 0.30 |
| Report delta scan | 0.24 | 0.24 | 0.27 |
| Loaded-file attribution | 0.21 | 0.21 | 0.24 |
| Example boundary | 0.40 | 0.44 | 0.51 |

Snapshot production in the `bb26fc3` profile has the same 20,003 calls as
`fb36816`; its single profiled sample is higher, and the clean wall times above
are the comparison of record. With line coverage, snapshot production is not the
largest remaining cost at this scale. With branch coverage it still dominates:
it takes 5.46 s of the 8.18 s `fb36816` Rails full-branches profile (67%), against
8.54 s of 11.37 s (75%) before.

## Decisions

- **#21: adopt.** The shared snapshot removes one producer call per example,
  keeps selected IDs, independent failure observations, and required dependency
  paths unchanged, and needs no native code.
- **#22: first slice adopted.** Per-run filter decisions and file names remove most
  normalization and attribution time. Remaining Ruby work in this area is
  per-example Set construction in the example boundary and loaded-file
  attribution, now under 1 s together on the large workload.
- **Native work.** On the Rails branch target, Coverage snapshot production is
  still about two thirds of the profiled command. A Ruby-side consumer port cannot remove
  it, so #23 (selective producer APIs) is the next measurement that can change
  the branch budget. #25 and #26 need fresh profiles on this revision before any
  Rust prototype: their prior budgets came from the costs removed here.

## Reproduce

[REPLAY.md](REPLAY.md) lists the commands. `SHA256SUMS` covers every published file.
