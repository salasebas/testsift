# Ruby-side optimization before native work

Measured on 2026-11-08 and 2026-11-09 against three engine revisions with one
driver, fixture set, and dependency resolution:

| Label | Revision | Change |
| --- | --- | --- |
| baseline | `e225fbf` | Engine of the [issue #20 report](../2026-11-04-issue-20/REPORT.md) |
| first slice | `bb26fc3` | Shared finish snapshot (#21), per-path filter decisions in attribution and normalization (#22) |
| optimized | `7d95a29` | Memoized path, absolute-path, and filter helpers; graph sets built once; no Set copies in snapshot projection; identical `@all_files` entries kept; project-path list reused across snapshots (removed after review, see below); spec-file lookup built once per report |

No native code is added. Review removed one `7d95a29` change after these
measurements: `CoverageAdapter#normalize` reused its list of project paths while
the snapshot's key count was unchanged. A restarted Coverage can replace files
without changing that count, so the list could miss a dependency. Normalization
walks every key again; on the large full run it took 0.84 s at `bb26fc3`,
against 0.51 s with the cache, so expect about 0.3 s (2.5%) more there than the
`7d95a29` rows show. The [issue #21 report](../2026-11-08-issue-21/REPORT.md)
covers the first slice alone. Absolute times from different reports are not
comparable: hosts and load differ.

## Protocol

All campaigns ran in `task benchmark:evidence:docker` (MRI 3.3.10,
`aarch64-linux`, OrbStack VM kernel `7.2.12`) on an Apple M5 Pro with 18 logical
CPUs and 48 GiB. The host was shared and its load average reached 6–12 during
these campaigns. Each cell has three clean repetitions and one exclusive timing
profile; nearest-rank p95 is the largest clean sample. Rails replays the
dependency resolution in `../2026-11-04-issue-20/stock/metadata.json`.

Campaign order: large for `7d95a29`, `e225fbf`, then `bb26fc3`; then Rails,
sparse, and eager for `7d95a29` followed by `e225fbf`. The nine main datasets hold 180
measured commands and 328 oracle-failure observations, with zero omitted failures
and zero status mismatches. Generated full and merged runs pass the independent
required-path checks. Every warm cell selects zero examples.

## Complete commands

Clean p50 / p95 seconds. Change compares the `7d95a29` and `e225fbf` medians.

| Workload | Selected | `e225fbf` | `7d95a29` | Change |
| --- | ---: | ---: | ---: | ---: |
| Large 10,000 examples, full lines | 10,000 | 22.60 / 24.72 | 12.34 / 12.78 | −45.4% |
| Large warm lines | 0 | 9.24 / 9.85 | 4.22 / 4.59 | −54.3% |
| Large input defect | 10 | 8.91 / 10.44 | 4.73 / 5.49 | −46.9% |
| Eager 500 files, full lines | 1,000 | 8.92 / 9.24 | 3.29 / 3.66 | −63.1% |
| Eager warm lines | 0 | 3.75 / 3.85 | 1.59 / 1.60 | −57.6% |
| Sparse full lines | 1,000 | 2.21 / 2.42 | 1.19 / 1.24 | −45.9% |
| Sparse full branches | 1,000 | 6.22 / 6.41 | 4.24 / 4.55 | −31.9% |
| Sparse warm lines | 0 | 1.17 / 1.45 | 0.55 / 0.56 | −52.9% |
| Sparse two-worker merge, lines | 1,000 | 2.40 / 2.51 | 1.98 / 2.02 | −17.7% |
| Sparse two-worker merge, branches | 1,000 | 3.30 / 3.93 | 3.21 / 3.23 | −2.8% |
| Rails full branches | 308 | 11.63 / 13.21 | 10.07 / 11.99 | −13.4% |
| Rails source defect, branches | 308 | 14.01 / 14.80 | 9.68 / 11.80 | −30.9% |
| Rails source defect, lines | 308 | 4.48 / 4.51 | 3.74 / 4.05 | −16.5% |
| Rails full lines | 308 | 3.73 / 4.03 | 3.81 / 4.26 | +2.1% |
| Rails input change, branches | 16 | 1.66 / 1.69 | 1.51 / 1.58 | −9.0% |
| Rails input change, lines | 16 | 0.94 / 0.98 | 0.97 / 1.36 | +2.6% |
| Rails warm branches | 0 | 0.99 / 1.03 | 0.88 / 1.20 | −10.7% |
| Rails warm lines | 0 | 0.90 / 1.09 | 1.07 / 1.38 | +18.5% |

The large campaigns ran in the order `7d95a29`, `e225fbf`, `bb26fc3` under a
load average of 6–12. The quieter [issue #21 campaign](../2026-11-08-issue-21/REPORT.md)
measured the same baseline command at 17.77 s; that value comes from a different
campaign and does not bound this comparison. `bb26fc3` measured 12.32 / 12.58 s
for large full lines and 8.57 / 9.83 s for large warm, right after the baseline:
the new commit leaves full runs at that level and halves warm runs.

Three Rails lines cells got slower in that single pass while their allocations
fell by 37–40%. An interleaved confirmation ran Rails lines full and warm with
five clean repetitions per pass, in the order `7d95a29`, `e225fbf`, `7d95a29`,
`e225fbf`:

| Pass | Full p50 (s) | Warm p50 (s) | Full allocations |
| --- | ---: | ---: | ---: |
| `7d95a29` first | 5.03 | 1.05 | 7,006,773 |
| `e225fbf` first | 5.48 | 1.08 | 11,141,259 |
| `7d95a29` second | 4.75 | 0.97 | 7,006,875 |
| `e225fbf` second | 6.83 | 1.20 | 11,141,304 |

Every optimized pass is at least as fast as the baseline pass next to it. Host
load raised all four above the earlier campaign, so these values do not give the
size of the Rails improvement. They show no regression.

## Allocations

Ruby objects allocated per complete command, clean medians. Allocation counts
are deterministic for a given revision and workload, so they confirm the work
removed independently of host load.

| Workload | `e225fbf` | `7d95a29` | Change |
| --- | ---: | ---: | ---: |
| Large full lines | 106,395,504 | 17,018,984 | −84.0% |
| Large warm lines | 43,777,466 | 5,238,632 | −88.0% |
| Eager full lines | 53,430,598 | 4,228,581 | −92.1% |
| Sparse full lines | 10,724,604 | 1,843,181 | −82.8% |
| Sparse full branches | 44,779,909 | 24,563,568 | −45.1% |
| Rails full lines | 11,141,417 | 7,006,700 | −37.1% |
| Rails full branches | 76,398,060 | 50,630,343 | −33.7% |
| Rails warm lines | 2,035,073 | 1,277,710 | −37.2% |

Peak single-process RSS medians move between −5.9% and +6.0% against the
baseline: 12 cells lower and 9 higher. The largest increases are Rails cells:
full branches +5.9%, input change lines +6.0%, and defects +3.3% to +3.4%. The
large workloads move by less than 2%. Fewer Ruby objects do not by themselves
lower peak RSS; collection timing changes with allocation volume. This dataset
does not attribute RSS changes, and a native candidate's no-worse-RSS gate must
be measured against this revision.

## Where the time goes now

Exclusive seconds from one timing profile per cell, grouped with the issue #20
labels. Unclassified time is boot, application code, RSpec, and
instrumentation outside the wrapped methods.

| Component | Large full | Large warm | Eager full | Rails full branches | Rails full lines |
| --- | ---: | ---: | ---: | ---: | ---: |
| Profiled command | 13.31 | 4.10 | 3.97 | 12.48 | 4.05 |
| Snapshot production (`Coverage.peek_result`) | 3.61 (27%) | — | 0.58 (15%) | 8.70 (70%) | 1.07 (26%) |
| Normalization | 0.51 (4%) | — | 0.34 (8%) | 0.05 | 0.02 |
| Dependency and report scans | 0.72 (5%) | — | 0.37 (9%) | 0.05 | 0.04 |
| Attribution and hooks | 2.18 (16%) | 0.03 | 0.96 (24%) | 0.09 | 0.06 |
| Stat, hash, discovery inputs | 0.43 (3%) | 0.09 (2%) | 0.24 (6%) | 0.04 | 0.03 |
| Graph, index, restore | 0.77 (6%) | 0.78 (19%) | 0.34 (9%) | 0.02 | 0.02 |
| Cache decode and interning | — | 0.60 (15%) | — | — | — |
| Snapshot building | 0.28 (2%) | 0.29 (7%) | 0.11 (3%) | 0.01 | 0.01 |
| Serialization and save | 0.31 (2%) | 0.17 (4%) | 0.09 (2%) | — | — |
| Reports | 1.20 (9%) | 1.64 (40%) | 0.37 (9%) | 0.03 | 0.03 |
| Runner setup and spec discovery | 0.20 (1%) | 0.12 (3%) | 0.09 (2%) | 0.49 (4%) | 0.50 (12%) |
| Unclassified | 3.10 (23%) | 0.39 (9%) | 0.49 (12%) | 2.99 (24%) | 2.27 (56%) |

The same profiles on `e225fbf` show what was removed:

| Component | Large full | Large warm | Eager full |
| --- | --- | --- | --- |
| Attribution and hooks | 7.92 → 2.18 | — | 3.81 → 0.96 |
| Normalization | 3.17 → 0.51 | — | 1.75 → 0.34 |
| Graph, index, restore | — | 4.44 → 0.78 | — |
| Snapshot building | 1.12 → 0.28 | 1.09 → 0.29 | 0.43 → 0.11 |

## Ruby runtime study

`task benchmark:evidence:runtime` on the host, without Docker, compared
interpreters on 200 files with 32 branch sites each. Values are
`Coverage.peek_result` p50 / p95 milliseconds over 40 snapshots without JIT, plus
the objects each snapshot allocates.
[runtime-macos.json.gz](runtime-macos.json.gz) holds every row.

| Ruby | Lines snapshot | Branches snapshot | Branch allocations |
| --- | ---: | ---: | ---: |
| 3.3.10 | 0.024 / 0.032 | 2.631 / 2.962 | 26,201 |
| 3.4.12 | 0.024 / 0.037 | 2.610 / 3.063 | 26,201 |
| 4.0.9 | 0.023 / 0.047 | 2.679 / 3.354 | 26,201 |
| 4.1.0-preview1 | 0.023 / 0.076 | 0.197 / 1.678 | 7,001 |

Ruby 4.1.0-preview1 (`2d08b5f42f`) contains
[ruby/ruby#18406](https://github.com/ruby/ruby/pull/18406), merged for
[Bug #22250](https://bugs.ruby-lang.org/issues/22250). It caches the branch and
method result templates so each peek fills counters instead of rebuilding keyed
hashes. Branch snapshots are 13× faster at p50 on this workload, and lines are
unchanged. The `only:` keyword that issue proposed was closed in favor of that
change. The corpus could not run end to end on the preview: sqlite3 2.10.2 has
no build for it. Projecting the microbenchmark onto the Rails branch profile is
an estimate, not a measurement: if snapshot production fell by the same factor,
the Rails full-branches command would lose about 8 of its 12.5 profiled seconds.

## Decisions and remaining budgets

Budgets use the rule from the issue #20 report: to save 10% of a command of
length `T`, replacement work must fit within `C − 0.10 T`. Negative means no-go
for that component on that target.

| Issue | Target | C (s) | T (s) | Allowance (s) | Decision |
| --- | --- | ---: | ---: | ---: | --- |
| #22 Ruby normalization, scans, attribution | Large full | 3.41 | 13.31 | 2.08 | **Done in Ruby.** Remaining native target below (#25). |
| #23 Producer APIs | Rails full branches | 8.70 | 12.48 | 7.45 | **Adopt upstream.** Ruby 4.1's template cache removes most branch snapshot cost; there is no TestSift-side producer port. |
| #24 Optional file-event collector | Large full | 4.84 | 13.31 | 3.51 | **Defer** to #12's collector comparison. A file-event set cannot produce line reports, so it only fits a dependency-only mode. |
| #25 Batched native consumer | Large full | 3.41 | 13.31 | 2.08 | **Defer.** Still above the gate at 10,000 examples, but Ruby/native conversion of every snapshot must fit in 2.1 s. Prototype only after #7, #8, and #9. |
| #26 Graph and identities | Large warm | 0.78 | 4.10 | 0.37 | **Ruby step done** (4.44 → 0.78 s). Native IDs have a small budget; re-measure after #28. |
| #27 Filesystem and hashing | Large full | 0.43 | 13.31 | −0.90 | **No-go** on these workloads; SHA256 and stat are already native. A large cold tree was not measured. |
| #28 Persistence, model, reports | Large warm | 2.41 | 4.10 | 2.00 | **Next Ruby experiment.** Reports build the same payload once per reporter; sharing it needs a reporter-contract change. |
| #29 Empty-selection CLI | Rails warm lines | 0.71 | 1.51 | 0.56 | **Defer** until a manifest and fallback contract exist (#7, #9, #10, #11). |

#28's `C` is reports, cache decode and interning, and serialization on the warm
profile. #29 keeps the issue #20 dry-discovery upper budget: no warm Rails
profile in this dataset isolates runner startup from host load.

## Where Rust could help

Rust only helps where Ruby objects are the cost and a narrow, copy-free boundary
exists:

1. **Per-example dependency bookkeeping (#25).** At 10,000 examples, normalization,
   scans, and attribution still take 3.4 s (26%). They repeat the same loaded set
   for every example. A native core that keeps file IDs and previous counters and
   returns only changed IDs would remove most of those objects. Its cost is the
   per-snapshot handoff from `Coverage.peek_result`'s Ruby hash.
2. **Cache model and reports (#26, #28).** The warm path decodes, rebuilds, and
   re-serializes a 1.1 M-edge graph and builds a report payload over the same
   edges: about 3.5 of 4.1 s. A native ID-based graph with direct serialization would
   avoid most Ruby objects, after the cheaper Ruby step of sharing one payload.
3. **Not the Coverage producer (#23).** `peek_result` is already C; upstream's
   template cache removes 92% of branch snapshot time on Ruby 4.1. Porting it
   would need private VM layouts, which the default gem must not depend on.
4. **Not stat or hashing (#27).** These are already native and below 4%.

## Reproduce

[REPLAY.md](REPLAY.md) lists the commands. `SHA256SUMS` covers every published
file.
