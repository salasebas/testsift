# Releasing TestSift

TestSift releases are driven by
[release-please](https://github.com/googleapis/release-please). Nobody
edits `CHANGELOG.md` or `TestSift::VERSION` by hand.

## Versioning

TestSift versions independently of the RSpec Tracer baseline it forked
from (`2.0.0.rc.1`). The first release is `0.0.1`: a working build that
claims the `testsift` name on RubyGems and exercises the whole release
pipeline. While the major version is `0`, the public API may still
change:

| Commit type | Before 1.0.0 | From 1.0.0 |
| --- | --- | --- |
| `fix:` / `perf:` | patch | patch |
| `feat:` | patch | minor |
| `feat!:` or a `BREAKING CHANGE:` footer | minor | major |

Users pin the current minor (for example `~> 0.0.1`) to receive fixes
and features without breaking changes. To cut the first feature-complete
release, set `"release-as": "0.1.0"` in `release-please-config.json`,
merge the release PR, then remove the key. TestSift does not publish `.pre` or `.rc` versions: the `0.x`
line is the prerelease phase, and `1.0.0` marks the first stable API.
release-please would write a prerelease as `0.1.0-beta.1`, which
RubyGems rewrites to `0.1.0.pre.beta.1`, so tags and gem versions would
stop matching.

Configuration lives in `release-please-config.json` (release type
`ruby`, `bump-minor-pre-major`, `bump-patch-for-minor-pre-major`,
`initial-version` `0.0.1`) and `.release-please-manifest.json` (the
last released version; empty until the first release).

## Commit messages

release-please reads the commits on `testsift`. Squash-merge pull
requests and give each one a
[Conventional Commit](https://www.conventionalcommits.org/) title;
the `pr-title` workflow checks it. `feat`, `fix`, and `perf` appear in
the changelog; `docs`, `refactor`, `test`, `ci`, and `chore` do not.

## Release flow

1. Every push to `testsift` runs `.github/workflows/release.yml`.
   release-please opens or updates a release pull request
   (`chore(testsift): release …`) that bumps `TestSift::VERSION`,
   prepends the `CHANGELOG.md` entry, and updates the manifest.
2. Approve the release pull request's workflow runs. release-please
   opens it as `github-actions[bot]` with `GITHUB_TOKEN`, so GitHub
   [holds its `ci`, `pr-title`, and `codeql` runs until someone with
   write access approves them](https://github.blog/changelog/2026-06-11-bot-created-pull-requests-can-run-workflows-if-approved/).
   Wait for them to pass. Runs still waiting when the pull request
   merges end as failed without running any job.
3. Before merging it, run the checks that need a human read:

   ```sh
   task release:preflight
   task release:verify
   ```

   `release:verify` builds the gem, installs it into an empty
   `GEM_HOME`, and runs `require 'testsift'`, `testsift --version`,
   and a cold then warm run of `benchmark/fixtures/ruby_app` from that
   install.
4. Merge the release pull request. release-please tags `vX.Y.Z` and
   creates the GitHub release; the `publish` job then checks the tag
   against `TestSift::VERSION`, runs `task release:verify` on the
   tagged commit, and pushes `pkg/testsift-X.Y.Z.gem` to RubyGems.

The release pull request only changes the version, the changelog, and
the manifest. A GitHub App token for release-please would start its
runs without approval; the approval click is kept instead, so the
repository holds no App credentials. `release:verify` in the `publish`
job checks the built artifact either way.

## One-time setup before the first release

- Settings → Actions → General: allow GitHub Actions to create and
  approve pull requests (release-please opens the release PR).
- Settings → General → Pull Requests: allow squash merging and set the
  default squash commit message to the pull request title.
- Settings → Environments: create `rubygems` and add yourself as a
  required reviewer, so every publish waits for approval.
- On rubygems.org, add a pending
  [trusted publisher](https://guides.rubygems.org/trusted-publishing/)
  for the gem `testsift`: repository owner `salasebas`, repository
  `testsift`, workflow `release.yml`, environment `rubygems`. A pending
  publisher expires 12 hours after it is created and does not reserve
  the name, so create it just before merging the first release PR. The
  first successful push turns it into a permanent publisher and makes
  you the gem owner. No API key is stored in the repository. The
  `publish` job names the owning account (`RUBYGEMS_OWNER`, a RubyGems
  handle or numeric user ID); RubyGems requires it to create a new gem.

## If publishing fails

The tag and the GitHub release already exist when `publish` runs.

- If the cause was transient (a network error, a missing approval),
  re-run the failed `publish` job from the Actions tab. A re-run uses
  the workflow file from the release commit.
- If the workflow itself needed a fix, merge the fix, then publish the
  existing tag with the current workflow:

  ```sh
  gh workflow run release.yml --ref testsift -f tag=vX.Y.Z
  ```

If RubyGems already accepted the gem, `gem push` fails on any retry;
the release is complete and nothing else is needed.

## After a release

- [ ] `gem install testsift -v X.Y.Z` works in a clean directory, and
      `ruby -e 'require "testsift"; puts TestSift::VERSION'` prints
      `X.Y.Z`.
- [ ] The GitHub release and the `CHANGELOG.md` entry match.
