# Changelog

All notable changes. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Governance and showcase documents: requirements traceability, compliance considerations, AI-assisted workflow, demo script.
- Pull request template, code owners, security policy, Dependabot, AI agent instructions.
- CI now retains test results as an artifact; release workflow with checksum and build attestation.

## [0.1.0]

### Added
- FPCUnit test suite (22 tests), pre-commit hook, GitHub Actions CI, and a code guide.
- `EnsureOnScreen` so windows always open on a visible monitor.

### Fixed
- Deleting a person left their phone numbers behind (SQLite foreign keys were off). Found by a new test.
- Windows saved with off-screen positions no longer open invisibly.
