# Measure real OSS suites

`task benchmark:oss` runs the pinned test suites of RuboCop, Mastodon, and
Discourse with plain RSpec, with Coverage alone, with
[rspec-tracer](https://github.com/avmnu-sng/rspec-tracer) `2.0.0.rc.1` (the
release TestSift forked from), and with TestSift. Every traced selection is
checked against an independent plain run of the same source tree. The runner
reuses the [evidence driver](../evidence/README.md)'s protocol: complete
subprocess timing, nearest-rank percentiles, seed caches restored outside the
timer, and failing-change oracles.

These runs take from minutes (one RuboCop smoke) to hours (a corpus with
repetitions). They are opt-in and never run in `task check` or per-PR CI.

## Prepare the host

The runner supports Linux and macOS, like the evidence driver. It needs:

- The Ruby each project pins in [corpus.yml](corpus.yml), installed under rv,
  rbenv, asdf, mise, chruby, or `/opt/rubies`. The runner looks for the exact
  version and fails if it is missing.
- Docker with Compose for Mastodon and Discourse. [services.yml](services.yml)
  starts their PostgreSQL and Redis containers on loopback ports.
- The tools each project lists under `requires`. The runner checks PATH before
  setup and names anything missing. On macOS:

  ```sh
  brew install vips libidn ffmpeg imagemagick oxipng pngquant jpegoptim gifsicle optipng libpq redis
  export PATH="$(brew --prefix libpq)/bin:$PATH"   # psql, which Discourse's schema load uses
  ```

  Mastodon also needs Node 22 or later; Discourse needs Node and pnpm. Discourse's
  parallel test boot starts a local `redis-server` per worker, so it needs the
  binary even though its shared Redis runs in Docker.

Workspaces and project bundles live under `--workdir`, default
`/var/tmp/testsift-oss`, outside this repository. A workspace inside this
checkout would inherit its `.rubocop.yml`, and RuboCop's own specs fail under
any hidden path component such as `~/.cache`, so the runner rejects one.

## Run it

```sh
task benchmark:oss -- --projects rubocop --suite smoke --repetitions 1 --output tmp/oss/rubocop-smoke
task benchmark:oss -- --projects rubocop --cases full,warm --repetitions 20 --output tmp/oss/rubocop
task benchmark:oss -- --projects rubocop,mastodon,discourse --output tmp/oss/corpus
```

Compare plain RSpec, rspec-tracer, and the released TestSift gem on the same
suite (issue #51):

```sh
task benchmark:oss -- --projects rubocop --tracers testsift,rspec-tracer --testsift-version 0.0.1 --output tmp/oss/compare
```

| Option | Meaning |
| --- | --- |
| `--projects LIST` | Projects from corpus.yml. Default: all, one after another. |
| `--suite NAME` | `full` (default) or a fixed subset named in corpus.yml, such as `subset` or `smoke`. |
| `--cases LIST` | Default: all cases below. |
| `--tracers LIST` | `testsift`, `rspec-tracer`, or both. Default: `testsift`. |
| `--revision REV` | TestSift Git revision to archive and measure. Default: `HEAD`. |
| `--testsift-version V` | Measure a released TestSift gem instead of a revision. |
| `--runner NAME` | Runner named in corpus.yml. Default: each project's `default_runner`. |
| `--workers N` | Override the runner's worker count. |
| `--repetitions N` | Measured rounds. Default: 5. |
| `--seed N` | Shuffle seed and RSpec `--seed`. Default: 30031. |
| `--lockfiles METADATA` | Replay the benchmark lockfiles saved in an earlier `metadata.json`. |
| `--workdir PATH` | Workspace and bundle root. Default: `/var/tmp/testsift-oss`. |
| `--output PATH` | New directory for results. Existing directories are rejected. |

## What a campaign does

For each project, in order:

1. **Setup.** Clone with `--filter=blob:none`, check that the tag resolves to
   the pinned commit, check out that commit, and write the benchmark files:
   `Gemfile.benchmark`, which `eval_gemfile`s the project's Gemfile and adds
   both tracers with `require: false`; its lockfile, copied from the project's
   lockfile and resolved conservatively; and `.testsift` / `.rspec-tracer`.
   The runner fails if adding the tracers changes any locked project gem.
   Every case uses this one bundle, so plain and traced runs load the same
   gems. Then it starts the services and runs the project's setup commands.
   These durations go to `metadata.json`, outside every sample.
2. **Preflight.** Two plain runs of the pinned tree must pass and execute the
   same example IDs. A failing, empty, or unrepeatable baseline stops the
   project.
3. **Oracles.** One plain run of every changed revision and of the fault. The
   fault oracle must fail.
4. **Prime.** One full traced run per tracer from an empty cache. Its outputs
   become the seed that every warm, changed, invalidated, and fault sample
   restores.
5. **Rounds.** Every cell runs once per round, shuffled with `--seed`.

Before each sample the runner restores every file a mutation touched, with its
original mtime, deletes all tracer output, runs the project's `reset` commands
(Redis `FLUSHALL`), and requires an empty `git status`. Database tables keep the
state the project's setup left; the suites roll back their own transactions.

| Case | State and change |
| --- | --- |
| `plain` | No tracer, no Coverage. |
| `coverage_control` | No tracer. The preload starts `Coverage` in lines mode, the tracers' default. |
| `full` | Empty cache, traced. |
| `warm` | Seed cache, no change. |
| `changed` | Seed cache plus one real upstream commit after the pin, applied as `git diff C^ C`. One cell per change in corpus.yml. |
| `invalidated` | Seed cache plus a changed tracer config file. Every example must run. |
| `fault` | Seed cache plus a one-line source defect. |

## How a sample is measured

[boot.rb](boot.rb) is preloaded through `RUBYOPT` in every case. It acts only in
processes that run RSpec: `rspec` itself or `bundle exec rspec`, which Bundler
loads in its own process. There it starts the tracer or the Coverage control
before the project loads, records each example that RSpec reports as finished,
and writes one telemetry file per process at exit. Wall time comes from the
parent's monotonic clock around the whole command, including boot, discovery,
cache load and save, reports, and every worker's exit. `/usr/bin/time` supplies
peak RSS (the largest single process in the tree) and CPU time. Allocations are
Ruby objects allocated after the preload, summed over RSpec processes.

Selected counts come from these RSpec notifications, not from the tracer's
terminal summary, which miscounts partial runs
([#42](https://github.com/salasebas/testsift/issues/42)).

## Validation

A row is a measurement only if every check passes:

- the runner's command started `workers + extra_processes` RSpec processes,
  each finished, and no example ran in two of them;
- traced rows loaded the requested tracer version from the requested path;
- the exit status matches the failing examples;
- no example is missing from the plain oracle of the same tree;
- `plain`, `coverage_control`, `full`, and `invalidated` executed every oracle
  example, except examples the tracer itself reports as duplicate identities;
- the persisted cache holds every oracle example the tracer could track.

Invalid rows stay in `runs.jsonl` with their errors and never enter a
percentile. Separately, every traced row lists oracle failures it did not run
(`missed_failures`) and selected examples whose status differs from the oracle
(`status_mismatches`). Either one, any invalid row, or a project that failed
setup makes the campaign exit 1. Agreement between rspec-tracer and TestSift is
reported, but it is not evidence that either selection is correct.

## Outputs

| File | Content |
| --- | --- |
| `metadata.json` | Driver revision and hashes, command, options, host, Docker, TestSift and rspec-tracer sources, and per project: commit, Ruby, Bundler, env, runner, service images, tool versions, setup durations, and the full benchmark lockfile. |
| `runs.jsonl` | One row per subprocess, including preflight, oracle, and prime rows: case, round, order, argv, env, exit, wall, CPU, peak RSS, allocations, executed and failing IDs, oracle comparison, cache and report bytes, seed restore time, errors. |
| `summary.json` | Per cell: valid samples, p50/p95 wall, p50 RSS and allocations, executed and selected ratio, missed failures, cache bytes. Tracer comparisons and determinism per case. |
| `report.md` | The summary as Markdown tables. |
| `projects/<name>/runs/*/` | Each sample's output log, executed example IDs, and per-process telemetry. |
| `projects/<name>/seeds/`, `patches/` | Seed caches and the exact replayed diffs. |

Keep campaigns under the ignored `tmp/`. Publish curated tables, not raw output.
