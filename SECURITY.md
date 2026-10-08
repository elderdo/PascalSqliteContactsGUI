# Security policy

This is a demonstration project, not a supported product. Even so, it is run as if it were one.

## Reporting a vulnerability

Please use GitHub's private reporting: **Security, then Report a vulnerability** on this repository. Do not open a public issue for a vulnerability.

## What is in place

- **Dependabot** keeps GitHub Actions versions current (see [.github/dependabot.yml](./.github/dependabot.yml)).
- **Least-privilege workflows:** CI runs with read-only repository permissions. Only the release workflow can write, and only when a version tag is pushed.
- **Branch protection** on `master`: changes arrive by pull request, and the `test` check must pass.
- **Signed provenance and checksums** are published with each release (SHA-256 file plus a build attestation).

## Known weaknesses (tracked, not hidden)

See "Known quirks and TODOs" in [CODE_GUIDE.md](./CODE_GUIDE.md). The main one: some SQL is built by string concatenation (apostrophes are escaped, but parameterized queries are the proper fix). The database is a local, unencrypted SQLite file with no user authentication.
