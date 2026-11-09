# Changelog

All notable changes to TestSift. release-please writes each entry from
the Conventional Commit messages merged since the previous release.

## [0.1.0](https://github.com/salasebas/testsift/compare/v0.0.1...v0.1.0) (2026-11-09)


### ⚠ BREAKING CHANGES

* remove the reports_s3_path and use_local_aws shims that read unpublished TESTSIFT_ variables ([#46](https://github.com/salasebas/testsift/issues/46))

### Bug Fixes

* report 0 re-run on warm runs instead of counting cached examples ([#45](https://github.com/salasebas/testsift/issues/45)) ([68f3ec5](https://github.com/salasebas/testsift/commit/68f3ec5256d91565cdc64456888e0dfaea29fc8b))


### Code Refactoring

* remove the reports_s3_path and use_local_aws shims that read unpublished TESTSIFT_ variables ([#46](https://github.com/salasebas/testsift/issues/46)) ([2e53b2a](https://github.com/salasebas/testsift/commit/2e53b2accc30167cce0b734848f73e53ddf63f6a))

## 0.0.1 (2026-11-09)


### Features

* ship TestSift as its own gem, released by release-please ([04ced03](https://github.com/salasebas/testsift/commit/04ced03513b6c67379c1c50f06cef834590ccffd))


### Performance Improvements

* cut Ruby recorder costs at scale and fix SQLite red-run persistence ([#32](https://github.com/salasebas/testsift/issues/32)) ([1793288](https://github.com/salasebas/testsift/commit/1793288ddaba25bf18cbf658c6a9ac1de50f3853))
* identify real Coverage costs before a Rust port ([e225fbf](https://github.com/salasebas/testsift/commit/e225fbf240f9828e922aa48f8fd59632dfeab4b0))

## [Upstream history](docs/upstream/CHANGELOG.md)

TestSift started from RSpec Tracer `v2.0.0.rc.1`. Upstream releases up to
that point are preserved in [docs/upstream/CHANGELOG.md](docs/upstream/CHANGELOG.md).
