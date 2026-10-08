# Compliance considerations

This is a showcase of an engineering process, **not a validated system**. This page says plainly what the process already supports for a regulated (GxP / FDA) environment and what would still be needed. Nothing here claims compliance.

## What the process already provides

| Expectation | How it is addressed here | Where |
|---|---|---|
| Documented requirements | Numbered requirements | [REQUIREMENTS.md](./REQUIREMENTS.md) |
| Requirements traced to verification | Each requirement lists its tests; gaps are shown | [REQUIREMENTS.md](./REQUIREMENTS.md) |
| Repeatable, automated testing | FPCUnit suite, same script locally and in CI | [CODE_GUIDE.md](../CODE_GUIDE.md#unit-tests) |
| Change control | Pull requests with a checklist, code owner review, protected `master` | [PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md), [CODEOWNERS](../.github/CODEOWNERS) |
| Retained test evidence | CI uploads `test-results.xml` for 90 days per run | [ci.yml](../.github/workflows/ci.yml) |
| Controlled, identifiable releases | Version tags, a release workflow that runs the tests first, SHA-256 checksum and build attestation | [release.yml](../.github/workflows/release.yml) |
| Audit trail of changes | Git history; every merge is tied to a pull request and its CI run | GitHub |
| Pipeline itself is verified | Documented red/green validation of hook and CI | [CODE_GUIDE.md](../CODE_GUIDE.md#validating-the-pipeline) |
| Supply-chain hygiene | Dependabot, least-privilege workflow permissions | [dependabot.yml](../.github/dependabot.yml), [SECURITY.md](../SECURITY.md) |
| Disclosed use of AI | AI use is declared per pull request and governed by written rules | [AI_WORKFLOW.md](./AI_WORKFLOW.md) |

## What the application does **not** have

If the app were handling regulated data (for example 21 CFR Part 11 electronic records, or data-integrity expectations such as ALCOA+), these would be required and are **not present**:

- **No user authentication or roles.** Anyone who can open the program can change any record.
- **No audit trail.** Edits and deletes are not logged with who, when and why, and old values are not kept.
- **No electronic signatures.**
- **No encryption at rest.** The data is a plain SQLite file under `%LOCALAPPDATA%`.
- **No backup or retention policy.**
- **No GUI test automation.** See the gaps in [REQUIREMENTS.md](./REQUIREMENTS.md).
- **No formal IQ/OQ/PQ** (installation, operational and performance qualification) or validation plan.

## What validating a real system would add

1. A validation plan and risk assessment (GAMP 5 category and criticality).
2. User requirements and a formal specification with approval signatures.
3. The missing controls above, each with its own requirement and tests.
4. IQ/OQ/PQ protocols with executed, signed evidence, with the CI results used as supporting evidence.
5. Periodic review and a documented process for patches and for upgrading the toolchain (Lazarus, FPC, SQLite).

## Honest summary

The *process* shown here (traceability, automated verification, protected change control, evidence retention and provenance) is the foundation a validated pipeline needs. The *product* is a small demo that would need the controls above before it touched regulated data.
