# Changelog

All notable changes. Versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-08

### Added
- Governance and showcase documents: requirements traceability, compliance considerations, AI-assisted workflow, demo script.
- Pull request template, code owners, security policy, Dependabot, AI agent instructions.
- CI retains test results as an artifact; tag-driven release workflow with checksum and build attestation.
- Branch protection on `master` (including admins).
- FPCUnit test suite (22 tests), pre-commit hook, GitHub Actions CI, and a code guide.
- `EnsureOnScreen` so windows always open on a visible monitor.

### Fixed
- Deleting a person left their phone numbers behind (SQLite foreign keys were off). Found by a new test.
- Windows saved with off-screen positions no longer open invisibly.
