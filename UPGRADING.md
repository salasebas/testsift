# Moving from rspec-tracer to TestSift

TestSift started from RSpec Tracer `2.0.0.rc.1`. The behavior is the
same; every public name changed, and caches start cold. If you are
still on rspec-tracer 1.x, the upstream 1.x → 2.0 guide is preserved in
[docs/upstream/UPGRADING.md](docs/upstream/UPGRADING.md).

## Renamed surface

| What | rspec-tracer | TestSift |
| --- | --- | --- |
| Gem | `rspec-tracer` | `testsift` |
| Require path | `require 'rspec_tracer'` | `require 'testsift'` |
| Rails preset | `require 'rspec_tracer/rails'` | `require 'testsift/rails'` |
| Namespace | `RSpecTracer` | `TestSift` |
| Executable | `rspec-tracer` | `testsift` |
| Rake tasks | `rspec_tracer:remote_cache:*` | `testsift:remote_cache:*` |
| Project config file | `.rspec-tracer` | `.testsift` |
| Environment variables | `RSPEC_TRACER_*` | `TESTSIFT_*` |
| Cache directory | `rspec_tracer_cache/` | `testsift_cache/` |
| Coverage directory | `rspec_tracer_coverage/` | `testsift_coverage/` |
| Report directory | `rspec_tracer_report/` | `testsift_report/` |
| Lock file | `rspec_tracer.lock` | `testsift.lock` |
| SQLite database | `rspec_tracer.sqlite3` | `testsift.sqlite3` |
| Default Redis key prefix | `rspec-tracer` | `testsift` |

Old environment variables are not read. Rename each one, for example
`RSPEC_TRACER_RUN_ALL_EXAMPLES` → `TESTSIFT_RUN_ALL_EXAMPLES`.

## Caches start cold

TestSift does not read rspec-tracer caches. The first TestSift run
records every example again, and later runs are warm. No migration
step exists, by design:

- Default cache, coverage, and report directories have new names, so
  an old `rspec_tracer_cache/` is never found.
- The whole-suite fingerprint includes the tracer gem's name and
  version. A cache directory pointed at old rspec-tracer data still
  re-runs the whole suite, because the stored fingerprint names
  `rspec-tracer`.
- Redis remote caches use the `testsift` key prefix by default. For S3,
  choose a new `prefix:` (or a new bucket path in
  `TESTSIFT_REMOTE_CACHE_URI`) so TestSift and rspec-tracer never share
  archives during a transition.

Once the switch is done, delete the old `rspec_tracer_*` directories,
update `.gitignore`, and change any CI cache keys that mention
rspec-tracer (see [docs/CI_RECIPES.md](docs/CI_RECIPES.md)).

## Steps

1. Replace the gem in your `Gemfile` (see the README quick start).
2. Rename `.rspec-tracer` to `.testsift` and change
   `RSpecTracer.configure` to `TestSift.configure` inside it.
3. In `spec_helper.rb` / `rails_helper.rb`, change
   `require 'rspec_tracer'` and `RSpecTracer.start` to
   `require 'testsift'` and `TestSift.start`.
4. In your `Rakefile`, rename `rspec_tracer:remote_cache:*` task
   references to `testsift:remote_cache:*`.
5. Rename `RSPEC_TRACER_*` variables in CI and local environments.
6. Update `.gitignore` for the new directory names.
