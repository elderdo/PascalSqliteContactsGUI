# Runbook: repeatable debugging and CI/CD process

The one-page procedure for taking a problem from "something is broken" to "fixed, verified and merged", with the tools it needs. Every step has a command you can copy. Background and reasoning are in the linked docs.

Repository: `elderdo/PascalSqliteContactsGUI`. Windows, PowerShell, run from the repository root.

## The loop at a glance

```
1 Reproduce  ->  2 Find the cause  ->  3 Failing test  ->  4 Smallest fix
      ->  5 Verify locally  ->  6 Branch + commit (hook gates)  ->  7 PR
      ->  8 Wait for CI  ->  9 Merge  ->  10 Sync and clean up
```

## Tools used, and what each is for

| Tool | Used for | Notes |
|---|---|---|
| **Lazarus / Free Pascal**, `lazbuild` | Building the app and the test project from the command line | `C:\lazarus`. `-B` forces a full rebuild |
| **FPCUnit** | Unit tests in `tests\` | Run by `scripts\run-tests.ps1` |
| **PowerShell 5+** | All scripts | Use `-NoProfile` so runs match on every machine |
| **Windows UI Automation + Win32 messages** | Driving the real app in the GUI test | Needs an interactive desktop |
| **SQLite** (`sqlite3.exe`, or Python's `sqlite3`) | Checking the real database from outside the app | Proves a change was committed |
| **gdb** (`C:\lazarus\mingw\x86_64-win64\bin\gdb.exe`) | Turning crash addresses into procedure names; stepping in VS Code | `info symbol 0x...` |
| **VS Code** + C/C++ extension (`ms-vscode.cpptools`) | Debugging with `.vscode\launch.json` | Launch config not verified end to end |
| **Git** + `.githooks\pre-commit` | Branches, commits, and the local gate | Enable with `git config core.hooksPath .githooks` |
| **GitHub CLI (`gh`)** | PRs, CI runs, logs, merges | Always pass `-R elderdo/PascalSqliteContactsGUI` |
| **GitHub Actions** (`ci.yml`, `release.yml`) | CI on a clean Windows runner; releases | Artifacts: `test-results`, `gui-evidence` |
| **Branch protection** | Blocks merging unless the `test` check passes, including for admins | Set in repo settings |
| **Dependabot** | Proposes action updates as PRs | Group related ones into one PR |
| **GitHub Copilot (CLI agent)** | Investigation, edits, running commands, drafting PRs | Rules in `AGENTS.md`; prompts in [AI_PROMPTS.md](./AI_PROMPTS.md) |

Setup once: install Lazarus and Python or `sqlite3`, run `git config core.hooksPath .githooks`, install `gh` and run `gh auth login`.

## Step by step

### 1. Reproduce
Write down the exact error text and the clicks that cause it. No reproduction, no fix.

### 2. Find the cause with evidence
Prefer facts to guesses. Read the exception; get a call stack if needed; check the data from outside the app. Techniques and the temporary code used are in [CODE_WALKTHROUGH.md](./CODE_WALKTHROUGH.md). Temporary debugging code never gets committed.

### 3. Write a failing test first
Add it to `tests\databasetests.pas` for database behaviour, then run:

```powershell
powershell -NoProfile -File scripts\run-tests.ps1
```
Exit code 0 = pass. Confirm it fails *for the right reason* before fixing.

### 4. Make the smallest fix
One problem, one change. Do not refactor unrelated code.

### 5. Verify locally
```powershell
powershell -NoProfile -File scripts\run-tests.ps1     # unit tests
powershell -NoProfile -File scripts\gui-tests.ps1     # end-to-end; close the app, hands off the mouse
```
GUI tests can be flaky, so repeat the GUI run 5 to 10 times (a loop is shown in [TESTING_AND_DEBUGGING.md](./TESTING_AND_DEBUGGING.md)). Afterwards check the test database was restored: `helloContacts.db.guitest.bak` must not exist.

### 6. Branch and commit
```powershell
git checkout master; git pull
git checkout -b fix/short-name        # prefixes: fix/ ci/ docs/
git add <specific files>              # name files; do not use 'git add .'
git commit -m "Title" -m "Why" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
The pre-commit hook runs both test suites when Pascal files are staged, and blocks the commit on failure. It is skipped for docs-only commits. Do not use `--no-verify`.

### 7. Open the pull request
```powershell
git push -u origin fix/short-name
gh pr create -R elderdo/PascalSqliteContactsGUI --base master --head fix/short-name `
  --title "..." --body-file pr-body.md
```
Fill the body from `.github\PULL_REQUEST_TEMPLATE.md`: what and why, checklist, AI disclosure, and **test evidence with the exact commands and results**. State what was *not* tested.

### 8. Wait for CI (the repeatable way to wait)

CI takes about 3 minutes. Do not guess; wait on the result.

```powershell
gh pr checks <n> -R elderdo/PascalSqliteContactsGUI --watch --interval 15
```
Exit code: **0** all checks passed, **1** a check failed, **8** still pending (when not using `--watch`).

Things that trip people up:

- **"no checks reported"** right after a push is normal for a few seconds; wait and retry.
- **A cancelled run is not a failure.** Pushing again while CI is running cancels the older run. Look at the run for the newest commit (`gh run list -R ... -b <branch> -L 3`).
- **Do not push while waiting** unless you want to restart the clock.
- If a check fails: `gh run view <run-id> -R elderdo/PascalSqliteContactsGUI --log-failed`, then fix on the same branch and push (the PR updates itself).
- Evidence: `gh run download <run-id> -R elderdo/PascalSqliteContactsGUI -n gui-evidence` (the GUI log, plus a screenshot only on failure).

### 9. Merge when green
Only merge when the required `test` check is green and you have reviewed the diff.

```powershell
powershell -NoProfile -File scripts\merge-when-green.ps1 -Pr <n>
```
The script does steps 8 to 10: waits for CI (and registers the late-starting checks), refuses to merge on failure or if the PR is not mergeable, runs `gh pr merge <n> --squash --delete-branch`, then syncs. Its exit code is 0 only when the PR merged. Squash-merge means all branch commits become one commit on `master` (see [BRANCHING_AND_MERGING.md](./BRANCHING_AND_MERGING.md)).

### 10. Sync and clean up
(The script does this too.)
```powershell
git checkout master; git pull
git branch -D <branch>        # -D because a squashed branch looks unmerged to git
git remote prune origin       # forget remote branches GitHub deleted
git status                    # should be clean
```
Then start the next change from the updated `master`. Never reuse a squash-merged branch.

## When something goes wrong

| Symptom | Likely cause | Action |
|---|---|---|
| Build fails with a file-in-use error | `hellocontacts.exe` is still running | Close it (`Get-Process hellocontacts` then `Stop-Process -Id <pid>`) |
| GUI test says "Close hellocontacts.exe first" | Same | Same |
| GUI test fails about half the time | A flaky interaction, often the test itself | Run 10 times, dump what is on screen and the DB, find the cause before changing the app |
| `gh` acts on the wrong repo | `gh` guessing | Pass `-R elderdo/PascalSqliteContactsGUI` |
| Merge button blocked | `test` not green, or branch out of date | Read the failing step; update the branch if needed |
| `gh run watch` exits 1 but nothing failed | The run was cancelled by a newer push | Watch the newest run |
| `helloContacts.db.guitest.bak` exists | A GUI run was killed | Copy it over `helloContacts.db` to restore your data |

## What to record in the PR (copy this)

- [ ] Reproduced, with the exact steps
- [ ] Failing test written first, and seen failing
- [ ] Smallest fix; no unrelated changes
- [ ] `run-tests.ps1` and `gui-tests.ps1` results with commands
- [ ] Temporary debug code removed
- [ ] Docs and changelog updated
- [ ] Not tested: (list it)
- [ ] AI assistance disclosed
