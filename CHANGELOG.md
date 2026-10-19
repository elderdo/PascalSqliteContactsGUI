# Changelog

All notable changes. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- GUI tests (`scripts\gui-tests.ps1`) for Search, Add, Edit and Delete, run by the pre-commit hook and CI.
- Unit tests that check writes keep other open queries open and that deletes are committed (30 tests total).

### Fixed
- `WriteLn` debug prints crashed the GUI app with RunError 103 (no console). They now use `DebugLn`.
- Add/Edit closed the people and phone queries, causing "Operation cannot be performed on an inactive dataset". Commits now use `CommitRetaining`.
- Deleting a person or phone was never committed, so it came back after the app closed.

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
