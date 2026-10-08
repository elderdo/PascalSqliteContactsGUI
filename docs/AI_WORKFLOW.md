# AI-assisted development

This project was built with an AI coding assistant (GitHub Copilot, using the Copilot SDK in VS Code) working under a human engineer's direction. This page explains how AI is used, the rules it follows, and why the pipeline makes that safe. It is deliberately specific about what AI did and what it did not.

## Principle

**AI proposes, the pipeline verifies, a human approves.** AI output is treated like code from a new contractor: useful, fast, and never trusted without checks.

## What AI did on this project (real examples)

| Task | What happened | How it was verified |
|---|---|---|
| Diagnose an off-screen window | Found stale `Left`/`Top` values in the `.lfm` files pointing at a monitor that no longer existed | Human ran the app and confirmed the window appeared |
| Add `EnsureOnScreen` | Wrote the helper and wired it into the three forms | Build passed; human checked on a three-monitor setup |
| Create the test suite | Wrote 22 FPCUnit tests with a throwaway SQLite database | Tests run locally and in CI |
| **Find a real bug** | A new test showed deleting a person left phone numbers behind (SQLite foreign keys off by default). The first fix attempt did not work; a second did | The test failed before the fix and passed after; recorded in [CODE_GUIDE.md](../CODE_GUIDE.md#unit-tests) |
| Build the pipeline | Wrote the hook, script and workflows | Deliberate failures proved each gate can block (see [Validating the pipeline](../CODE_GUIDE.md#validating-the-pipeline)) |
| Write documentation | Drafted the guide, requirements and this page | Human review; statements about untested items are marked as such |

The "first fix did not work" row matters. AI is wrong sometimes, and a test suite is what catches it.

## Rules the AI follows

Written down in [AGENTS.md](../AGENTS.md) and [.github/copilot-instructions.md](../.github/copilot-instructions.md), so any assistant picks them up automatically:

1. Make small, surgical changes; do not refactor unrelated code.
2. A bug fix starts with a failing test.
3. Run `scripts\run-tests.ps1` before proposing a commit.
4. Do not claim something works unless it was run; mark untested items as such.
5. Never commit secrets, and never bypass the hook (`--no-verify`) without saying why.
6. Update the docs and [REQUIREMENTS.md](./REQUIREMENTS.md) with the code.
7. Prefer parameterized SQL for new code.

## Controls that make AI use safe

| Risk | Control |
|---|---|
| Plausible but wrong code | Automated tests, local hook, CI |
| Silent regressions | Same tests on every pull request, protected `master` |
| Unreviewed changes | Pull request template with an AI disclosure section, code owner review |
| Overclaiming ("it works") | Rule 4; documentation marks gaps and unvalidated items |
| Secrets or data leakage | No secrets in the repo; the AI is told never to commit them; data stays local |
| Unknown provenance | Git history shows every change; releases carry a checksum and attestation |
| Skipping the safeguards | Branch protection applies to the owner as well |

## Using AI inside the workflow (practical tips)

- **Ask for the test first.** "Write a failing test for X, then fix it" produces better and safer changes than "fix X".
- **Give it the guardrails.** `AGENTS.md` and `copilot-instructions.md` are read automatically, so the rules above do not have to be repeated.
- **Have it explain failures.** Paste the `--log-failed` output from CI and ask for the root cause. Then reproduce locally before accepting the fix.
- **Use AI review as an extra reader, not the approver.** Copilot code review on a pull request can catch things a tired human misses, but approval stays with the code owner.
- **Disclose.** Fill in the "AI assistance" section of every pull request.

## What AI is *not* trusted to do

- Approve or merge its own changes.
- Decide that something is validated or compliant. See [COMPLIANCE.md](./COMPLIANCE.md).
- Run unattended against `master`.

## Possible next steps (not implemented)

- Copilot coding agent working on labelled issues, with its pull requests gated by the same checks (needs a setup workflow that installs Lazarus).
- An AI-assisted pull request summary or release-note draft, reviewed by a human before publishing.
- AI-generated test ideas for the GUI-less logic gaps listed in [REQUIREMENTS.md](./REQUIREMENTS.md).
