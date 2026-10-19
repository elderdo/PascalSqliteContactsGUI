# Case study: from a crash report to a gated, CI-verified fix with AI assistance

A short, evidence-based account of one real change (pull request #10). It shows a CI/CD pipeline for a Windows desktop GUI app and how an AI assistant was used inside it, including where the AI was wrong and what caught it.

## Context

A Lazarus / Free Pascal desktop contacts app with a SQLite database. Windows only. A solo developer working with GitHub Copilot (CLI agent) under written rules ([AGENTS.md](../AGENTS.md)).

## The problem

1. The app crashed in the IDE with a runtime error at a `WriteLn` call.
2. It would not start from VS Code (wrong debug configuration).
3. The developer wanted Add, Edit and Delete verified automatically before every commit and in CI. A GUI cannot be unit-tested the usual way.

## What was done

| Step | Result |
|---|---|
| Diagnosed the crash | `WriteLn` in a GUI program has no console, so it raises RunError 103. Replaced with `DebugLn` (LazLogger). |
| Fixed the VS Code launch config | First draft used a debugger extension that was not installed; rewritten for `cppdbg` + the gdb bundled with Lazarus. **Not verified end to end in VS Code.** |
| Built a GUI end-to-end test | `scripts/gui-tests.ps1` drives the real exe with Windows UI Automation and Win32 messages, then checks results in the SQLite file. It backs up and restores the user's database. |
| Test-first bug fixes | The GUI test exposed a real bug: `Commit` closed every query on a shared transaction, so the next action raised "inactive dataset". Unit tests were written first (4 of 6 failed), then the fix (`CommitRetaining`). A second bug showed up: deletes were never committed. Also test-first. |
| Chased a flaky test | The Delete step failed about half the time. A stack trace pinned one real fault (a refresh on a closed query, fixed by re-opening the main queries). The remaining flakiness was the test's own `sqlite3` polling colliding with the app's commit; a short wait fixed it. 10 of 10 consecutive runs then passed. |
| Wired it into the gates | Pre-commit hook (unit tests then GUI tests), CI step on a hosted Windows runner. |
| Shipped it | Branch, five small commits, PR with the template and exact test evidence, CI green, squash-merge. |

## Evidence

- Unit tests: 30, all passing (`scripts\run-tests.ps1`). The new tests failed before the fixes.
- GUI test: 17 checks. Passed on the CI runner (see the PR #10 run) and 10 consecutive local runs after the last fix.
- Commit: `947195c` "Fix GUI crashes and add GUI tests (#10)" on `master`.
- The CI GUI step needing no special desktop setup was confirmed by that green run. How reliable it stays over many runs is **not yet measured**.

## Where the AI was wrong, and what caught it

Honest accounting is the point of this section.

- **A wrong dependency.** The first launch configuration used a debugger type that was not installed. The VS Code error messages exposed it; it was rewritten.
- **A wrong guess at the flaky failure.** The first theory was that the test clicked the wrong dialog. Evidence (dumping the dialog text and the database) disproved it before any fix was made, which led to the real causes.
- **A temporary debug change that did not compile** (a duplicate unit in the uses clause). The compiler caught it; the temporary code was removed and verified gone before committing.
- **An edit that dropped two lines** of the test script during a comment pass. Re-reading the file caught it, and a parser check confirmed the final scripts.
- **Not yet proven:** the screenshot-on-failure step in CI has only run on a passing build, where it is skipped.

The pattern: the AI proposed, tests and the compiler verified, the human decided. No claim in the PR said "works" without a command and result next to it.

## What a reader can reuse

- The method: [TESTING_AND_DEBUGGING.md](./TESTING_AND_DEBUGGING.md), including every `gh` and `git` command and why.
- The prompts: [AI_PROMPTS.md](./AI_PROMPTS.md).
- The rules and controls: [AI_WORKFLOW.md](./AI_WORKFLOW.md).
- The pipeline: [CODE_GUIDE.md](../CODE_GUIDE.md#cicd-pipeline-architecture-and-setup) and [ci.yml](../.github/workflows/ci.yml).

## Skills this shows

Test-first bug fixing; GUI test automation on Windows; diagnosing an intermittent failure with evidence; pre-commit and CI quality gates; small reviewable commits and PRs with traceable test evidence; disciplined, disclosed use of AI with written guardrails.

## Limits

Phone Add/Edit/Delete are not covered by the GUI test. The app is Windows only. The AI-assisted claims above describe this one project and are not benchmarks.
