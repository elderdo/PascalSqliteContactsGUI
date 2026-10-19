# Testing and debugging strategy

A repeatable recipe for finding, fixing and proving a bug. Follow it for any new bug or feature. It was used to fix the crashes in this project (RunError 103 from `WriteLn`, "inactive dataset" errors, deletes that were never committed).

## The idea in one paragraph

Every change has to pass **two automatic safety nets before it is committed**: fast unit tests of the database code, and a slow end-to-end test that drives the real application. The same two scripts run on every developer machine (pre-commit hook) and in CI (GitHub Actions), so "it works on my machine" and "it works in CI" mean the same thing. Bugs are fixed **test first**: reproduce, prove it fails, fix, prove it passes.

## The tools and what each one is for

| Layer | Script | Speed | Catches | Runs in |
|---|---|---|---|---|
| Unit tests (FPCUnit) | `scripts\run-tests.ps1` | seconds | wrong SQL, missing commits, closed queries | pre-commit, CI |
| GUI end-to-end test | `scripts\gui-tests.ps1` | about 1 minute | crashes and error dialogs in real use of Search, Add, Edit, Delete | pre-commit, CI |
| Debugger | `.vscode\launch.json` (gdb) | manual | stepping through code | your machine only |
| Pre-commit hook | `.githooks\pre-commit` | about 1 minute | blocks a commit when either suite fails | your machine |
| CI | `.github\workflows\ci.yml` | few minutes | same checks on a clean machine | GitHub |

Every script ends with an **exit code**: 0 = pass, anything else = fail. Hooks and CI only look at that number. Both scripts are commented line by line for beginners.

## One-time setup

1. Install Lazarus (default `C:\lazarus`) and make sure `lazbuild` works.
2. `git config core.hooksPath .githooks` (enables the pre-commit hook).
3. Install `sqlite3.exe` or Python (the GUI test reads the database with one of them).
4. For debugging in VS Code, install the Microsoft C/C++ extension (`ms-vscode.cpptools`).

## The bug-fixing loop

1. **Reproduce** the problem by hand and write down the exact message and steps.
2. **Find the cause with evidence, not guesses** (see "Debugging techniques" below).
3. **Write a failing test first.** For database behaviour, add it to `tests\databasetests.pas`. Run `scripts\run-tests.ps1` and confirm it fails *for the right reason*.
4. **Fix the smallest thing** that makes it pass. Do not refactor unrelated code.
5. **Run both suites**: `scripts\run-tests.ps1`, then `scripts\gui-tests.ps1` (close the app first and do not touch the mouse or keyboard while the GUI test runs).
6. **Repeat the GUI test several times in a row.** GUI tests can be flaky; one pass proves little. Aim for 5 to 10 consecutive passes before trusting it.
7. **Update docs** (`CODE_GUIDE.md`, `CHANGELOG.md`, `docs\REQUIREMENTS.md` when behaviour changes).
8. **Commit** on a branch (the hook runs both suites), push, open a pull request with the template, wait for CI, squash-merge.

## How the GUI test works

`scripts\gui-tests.ps1` behaves like a very patient user:

1. Builds the app and **backs up the real database**.
2. Starts `hellocontacts.exe`.
3. Finds windows and buttons with Windows **UI Automation**, types text and presses buttons by sending Windows messages (`WM_SETTEXT`, `BM_CLICK`).
4. After every action it **checks the SQLite file** with SQL. The DB grids are custom-drawn and unreadable by automation, and the database is the truth anyway.
5. Fails if an error dialog (a window with an Abort button) appears.
6. In a `finally` block it always closes the app and **restores the database**.

Covered: Search, Add, Edit, Delete (including Cancel). Not covered: phone Add/Edit/Delete.

### Adding a new GUI step

1. Find the control: print `ListWindows` output (the script does this when a step fails) to see window titles, class names and button captions.
2. Act with `SetText` / `Click` / `SelectFirstRow`.
3. Wait with `WaitWindow`, `WaitDialogWithButton` or `WaitFor` instead of fixed sleeps.
4. Assert with `Check 'name' (condition)`, preferably on a database value.

## Debugging techniques that worked

- **Read the exception text.** "RunError 103" means a file operation on a closed file (`WriteLn` in a program with no console). "Operation cannot be performed on an inactive dataset" means a query was closed (here by `Commit`) and then used.
- **Get a real call stack.** In a temporary build, install an `Application.OnException` handler that writes `BackTraceStrFunc(ExceptAddr)` and every `ExceptFrames[i]` to a file, then build with `lazbuild -B --opt=-gl hellocontacts.lpi` and resolve each address with `gdb -batch -ex "info symbol 0x..." hellocontacts.exe`. The names show which procedure raised the error. **Remove this code before committing.**
- **Check the data from outside the app.** Open the database with another connection (the tests use `CountFromOtherConnection`). It shows whether a change was really committed.
- **Suspect your own test tool.** The Delete test failed about half the time because the test's `sqlite3` polling held a read lock while the app was committing (SQLITE_BUSY, swallowed silently). Waiting a moment before reading fixed it. When a failure is intermittent, ask what in the test environment could be interfering.
- **Print what you cannot see.** When a step fails, dump the dialog text and the database rows before deciding what is wrong.
- **Debug in VS Code.** Press F5 with "Debug hellocontacts (gdb)" (builds first, then starts gdb). The path to `gdb.exe` is in `launch.json`. This configuration has not been verified end to end.
- **Use `DebugLn`, never `WriteLn`,** for diagnostics in the GUI app.

## Safety rules for test runs

- Close `hellocontacts.exe` before running the GUI test; the script refuses to start otherwise.
- Do not click or type during a GUI run.
- After a run, check that `%LOCALAPPDATA%\hellocontacts\helloContacts.db.guitest.bak` does **not** exist. If it does, a run was killed; copy it over `helloContacts.db` to restore your data.
- Never use `git commit --no-verify` unless you have a reason you can state.

## Expediting deployment

The pipeline is: branch, commit (hook runs both suites), push, PR (template with the exact commands and results), CI re-runs everything on a clean machine, squash-merge to `master`. Because the same scripts run in every place, a green CI is a strong signal and no manual re-testing is needed. If the CI GUI step cannot run on a hosted runner (no interactive desktop), make that one step non-blocking and keep the hook as the gate. Whether this is needed has not been confirmed yet.

## Command reference: what was run and why

All commands are run in PowerShell from the repository root.

### Build and test

| Command | What it does and why |
|---|---|
| `lazbuild hellocontacts.lpi` | Compiles the app from the command line (no IDE). `-B` forces a full rebuild; use it when a stale build is suspected. |
| `lazbuild -B --opt=-gl hellocontacts.lpi` | Rebuild with `-gl`, which adds line-number information so a crash can be traced to a source location. Debug builds only. |
| `powershell -NoProfile -File scripts\run-tests.ps1` | Builds and runs the unit tests. `-NoProfile` skips your personal profile so the run behaves the same on every machine. `-File` runs the script and passes its exit code back. |
| `powershell -NoProfile -File scripts\gui-tests.ps1` | Runs the end-to-end GUI test (see above). |
| `$LASTEXITCODE` | PowerShell variable holding the exit code of the last program. 0 = success. Used to confirm each run. |
| `Start-Job { ... }` with `Wait-Job -Timeout 150` | Runs the GUI test in the background with a time limit. If a dialog blocks the app, the run is stopped instead of hanging forever. |
| `Get-Process hellocontacts \| % { $_.Kill() }` | Closes a leftover copy of the app after a timed-out run. It is by name on purpose: only this app is affected. |

### Inspecting data and crashes

| Command | What it does and why |
|---|---|
| `sqlite3 <db> "select count(*) from People"` | Reads the database from outside the app to prove a change was really saved. The DB is at `%LOCALAPPDATA%\hellocontacts\helloContacts.db`. |
| `gdb -batch -ex "info symbol 0x..." hellocontacts.exe` | Turns a raw crash address from the exception logger into a procedure name. `-batch` runs the commands and exits. The `gdb.exe` is bundled with Lazarus under `C:\lazarus\mingw\x86_64-win64\bin`. |

### Git: keeping changes small and safe

| Command | What it does and why |
|---|---|
| `git checkout -b fix/gui-crashes-and-gui-tests` | Creates and switches to a branch so `master` stays untouched until the PR is merged. |
| `git status --short` | One line per changed file. Run before every commit to see exactly what will be included. |
| `git diff --cached --stat` | Summary of what is staged. Confirms each commit contains only its own files. |
| `git add <files>` | Stages specific files. Naming files (not `git add .`) lets one set of changes be split into small commits. |
| `git commit -m "title" -m "body" -m "Co-authored-by: ..."` | Records the commit. Each `-m` adds a paragraph. The last one is the trailer that credits the AI assistant. The pre-commit hook runs here and blocks the commit if tests fail. |
| `git --no-pager log --oneline -6` | Shows recent commits on one line each. `--no-pager` stops git from opening an interactive viewer, which would hang a script. |
| `git push -u origin <branch>` | Uploads the branch. `-u` remembers it, so later a plain `git push` works. |
| `git commit --no-verify` | Skips the hook. **Not used.** It exists, but it defeats the safety net. |

### GitHub CLI (`gh`)

`gh` is GitHub's command-line tool. **Always pass `-R elderdo/PascalSqliteContactsGUI`.** On this machine `gh` can guess the wrong repository, and `-R` removes the guess.

| Command | What it does and why |
|---|---|
| `gh pr create -R elderdo/PascalSqliteContactsGUI --base master --head fix/gui-crashes-and-gui-tests --title "..." --body-file pr-body.md` | Opens the pull request. `--base` is where the change will land, `--head` is your branch. `--body-file` reads the description from a file filled in from `.github\PULL_REQUEST_TEMPLATE.md` (what/why, checklist, AI disclosure, test evidence with exact commands and results). |
| `gh run list -R elderdo/PascalSqliteContactsGUI -b <branch> -L 1 --json status,conclusion,url` | Shows the latest CI run for the branch. `-b` filters by branch, `-L 1` limits to one run, `--json` gives machine-readable output. |
| `gh run watch -R elderdo/PascalSqliteContactsGUI <run-id> --exit-status` | Waits for the run to finish and live-prints progress. `--exit-status` makes the command fail if CI fails, so it can be used in scripts. |
| `gh run view <run-id> --log-failed` | If CI fails, prints only the failing steps' logs (not yet needed). |
| `gh pr merge <number> -R elderdo/PascalSqliteContactsGUI --squash --delete-branch` | After CI is green: squashes the commits into one on `master` and deletes the branch. `master` is protected, so this only works through a PR. |

### Why this order

Branch, small commits, hook, push, PR, CI, squash-merge. Each step is a checkpoint: the hook catches mistakes on your machine, CI catches environment differences, and the PR template records what was tested and what was not.

## Reading CI logs and artifacts

A GUI test on a server cannot be watched, so the CI job records evidence instead. This is the standard approach for GUI apps in CI.

- **Log:** every step's output is in the job log. `gh run view <run-id> -R elderdo/PascalSqliteContactsGUI --log` (finished runs only) or `--log-failed` for failing steps only. In the browser: Actions tab, the run, then the step.
- **Artifact `gui-evidence`:** `gui-tests.log` (full PASS/FAIL output, kept even when the step passes) and, only on failure, `failure.png`, a screenshot of the runner's desktop that shows any dialog left on screen. The upload step uses `if: always()` so the evidence is saved even when the test fails. Download with `gh run download <run-id> -R elderdo/PascalSqliteContactsGUI -n gui-evidence`.
- **Artifact `test-results`:** the unit-test XML.
- **Why:** a failed GUI step otherwise says only "exit code 1". The log tells you which check failed, and the screenshot shows what the app was doing. Not yet exercised on a failing run (the screenshot code has only run on a passing run, where it is skipped).
- Re-run with more detail from the browser: **Re-run jobs**, then "Enable debug logging".

## After a squash-merge: sync your clone

Pull requests here are squash-merged. GitHub replaces the branch's commits with one new commit on `master`, so the local branch is no longer part of `master`'s history. Reusing it would show the old commits as "different" and cause conflicts. The routine, and why:

| Command | Why |
|---|---|
| `git checkout master` | Leave the finished branch. |
| `git pull` | Download the squash commit so local `master` matches GitHub. |
| `git branch -D <branch>` | Delete the local branch. `-D` (force) is needed because git cannot see that a squashed branch was merged; its commits are not in `master`. Only do this after confirming the PR shows MERGED (`gh pr view <n> --json state`). |
| `git remote prune origin` | Forget remote branches that GitHub already deleted (`--delete-branch` removed the remote one). |
| `git checkout -b <new-branch>` | Start the next change from the updated `master`. |

Check the result with `git log -1` (one squash commit, with the Copilot co-author trailers kept) and `git status` (clean).

## Checklist to copy into a PR or ticket

- [ ] Reproduced the bug and noted the exact steps
- [ ] Wrote a failing test and saw it fail
- [ ] Fixed it with the smallest change
- [ ] `scripts\run-tests.ps1` passes
- [ ] `scripts\gui-tests.ps1` passes several runs in a row
- [ ] Temporary debug code removed
- [ ] Docs and changelog updated
- [ ] Test database restored (no `.guitest.bak` left)
