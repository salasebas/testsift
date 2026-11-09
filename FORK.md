# TestSift baseline

TestSift starts as a fork of [avmnu-sng/rspec-tracer](https://github.com/avmnu-sng/rspec-tracer).
The fork was created on November 3, 2026.

| Item | Value |
| --- | --- |
| Repository | [salasebas/testsift](https://github.com/salasebas/testsift) |
| Development branch | `testsift` |
| Upstream release | `v2.0.0.rc.1` |
| Upstream commit | `f13851f7b3393aaafa7c7df088c1605747f07ce5` |
| Release status | Prerelease, published July 13, 2026 |
| Imported gem version | `2.0.0.rc.1` |
| Imported gem and namespace | `rspec-tracer`, `RSpecTracer` |
| TestSift gem and namespace | `testsift`, `TestSift` |
| TestSift initial version | `0.1.0` |
| License | MIT. The upstream copyright notice stays in [LICENSE](LICENSE) next to TestSift's. |

The development branch starts from the tagged commit. The fork's `main`
branch preserves the upstream main branch captured at fork creation.
Upstream main was four commits ahead of the tag at this point.

The initial import preserved the upstream gem name, namespace, executable,
and cache format so the starting implementation could be checked first.
[Issue #5](https://github.com/salasebas/testsift/issues/5) then renamed
the whole public surface to TestSift: the `testsift` gem and executable,
`require 'testsift'`, the `TestSift` namespace, the `.testsift` config
file, `TESTSIFT_*` environment variables, and `testsift_*` cache and
report directories. [UPGRADING.md](UPGRADING.md) maps every old name.
TestSift does not read rspec-tracer caches; the first run is cold.

TestSift versions independently from `0.1.0` and releases through
release-please ([RELEASING.md](RELEASING.md)). No `testsift` gem has been
published yet. Upstream's changelog, roadmap, 1.x upgrade guide, and 1.x
design narrative are kept unchanged under [docs/upstream/](docs/upstream/);
measurements and benchmark results recorded before the rename keep the
names that were current when they were taken.

## Initial direction

Start with working RSpec selection and SimpleCov interoperability. Measure
the imported behavior before extracting runner-specific code. Keep the
dependency engine separate from runner adapters, then evaluate Rust for
measured bottlenecks. Add Minitest after the RSpec flow works through that
interface. These are development intentions, not implemented fork features.

The [TestSift roadmap](https://github.com/salasebas/testsift/issues/1) records
the implementation order, acceptance criteria, and dependencies. The
[upstream inventory](https://github.com/salasebas/testsift/issues/2) separates
inherited capabilities from unfinished upstream work. TestSift's own
packaging and versioning are tracked in [issue #5](https://github.com/salasebas/testsift/issues/5).

Keep tests executed in the current run distinct from historical coverage
carried forward for skipped tests. A preserved percentage alone does not
establish that the current run measured the complete suite.

## Upstream changes to assess

As of November 3, 2026, upstream has not published `2.0.0` final. The
maintainer opened an observation period at rc.1 and planned shadow mode
for rc.2. The public roadmap still lists audit and adoption work before
final. No later public explanation for the missed release target was
found in the inspected releases, issues, milestones, and discussions.
That absence does not establish a hidden defect or project abandonment.

- [Public release roadmap](https://github.com/avmnu-sng/rspec-tracer/blob/7c75cc3a1f6e1cd4929a87b77da0b7daa0369685/ROADMAP.md)
- [Open shadow-mode work](https://github.com/avmnu-sng/rspec-tracer/issues/233)

The tagged baseline excludes the four later commits on upstream main.
One is a SQLite persistence correction for failing suites: the old path
could leave a zero-byte database and force subsequent cold runs. Review
that correction against this fork's current behavior before porting it.
The initial import makes no claim that this issue is fixed.

- [Tag release notes](https://github.com/avmnu-sng/rspec-tracer/releases/tag/v2.0.0.rc.1)
- [Tag-to-main comparison at fork creation](https://github.com/avmnu-sng/rspec-tracer/compare/f13851f7b3393aaafa7c7df088c1605747f07ce5...7c75cc3a1f6e1cd4929a87b77da0b7daa0369685)
- [SQLite persistence correction](https://github.com/avmnu-sng/rspec-tracer/pull/277)

## Local verification

The upstream development instructions are in [AGENTS.md](AGENTS.md) and
[CLAUDE.md](CLAUDE.md). The standard quick check is `task check`. This import
retains the upstream `.ruby-version` pin of `3.3.10`.

Bootstrap verification on November 3, 2026 used Ruby `4.0.9` and Task
`3.54.0`, with gems installed locally under `vendor/bundle`. `task check`
passed: 236 Ruby files without lint offenses, 2167 examples with zero
failures and two pending examples, and passing `cold_ruby` and `warm_noop`
smoke benchmarks. This is the quick check, not the full CI matrix.
