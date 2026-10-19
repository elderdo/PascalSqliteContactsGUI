# PowerShell patterns used in this project

The automation here (tests, GUI driving, CI steps, merging) is written in PowerShell, which ships with Windows. This page collects the reusable patterns, why each is used, and where to see it. Every pattern comes from a script in this repository, and the scripts carry beginner-level comments.

| Script | Purpose |
|---|---|
| [scripts/run-tests.ps1](../scripts/run-tests.ps1) | Build and run the unit tests |
| [scripts/gui-tests.ps1](../scripts/gui-tests.ps1) | Drive the real app and verify results in the database |
| [scripts/merge-when-green.ps1](../scripts/merge-when-green.ps1) | Wait for CI, squash-merge, sync the clone |
| [.githooks/pre-commit](../.githooks/pre-commit) | A shell hook that calls the scripts above |

## Running a script

```powershell
powershell -NoProfile -File scripts\run-tests.ps1
```

- `-NoProfile` skips your personal startup file, so the run behaves the same on every machine and in CI.
- `-File` runs the script and returns **its** exit code to the caller. (`-Command` can hide the code.)
- If scripts are blocked by policy, add `-ExecutionPolicy Bypass` for that one run; the pre-commit hook does this. It does not change the machine setting.
- Windows PowerShell 5.1 is `powershell`; PowerShell 7 is `pwsh`. CI uses `shell: pwsh`. The scripts avoid 7-only syntax so they run on both.

## Pattern 1: exit codes are the contract

Programs return a number when they finish. **0 means success; anything else means failure.** Git hooks, CI and other scripts only look at that number.

```powershell
& $lazbuild 'tests\hellocontacts_tests.lpi'      # '&' runs the program stored in a variable
if ($LASTEXITCODE -ne 0) { Write-Host 'Test project failed to build.'; exit 1 }
& '.\tests\hellocontacts_tests.exe' --all --format=plain
exit $LASTEXITCODE                                # pass the test runner's result upward
```

`$LASTEXITCODE` holds the exit code of the last *external program* (not of PowerShell commands). Check it right after the program runs. Use distinct codes where it helps: `run-tests.ps1` returns 2 when `lazbuild` is missing and 1 for build or test failures.

## Pattern 2: make the script location-independent

```powershell
Set-Location (Join-Path $PSScriptRoot '..')       # go to the repo root
```

`$PSScriptRoot` is the folder containing the script, so relative paths work wherever you start from. Build paths with `Join-Path`, not string concatenation.

## Pattern 3: find a tool, with a fallback, and fail clearly

```powershell
$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild -and (Test-Path 'C:\lazarus\lazbuild.exe')) { $lazbuild = 'C:\lazarus\lazbuild.exe' }
if (-not $lazbuild) { Write-Host 'lazbuild not found. Add Lazarus to PATH.'; exit 2 }
```

Look on `PATH` first, then the default install folder, then stop with a message that says what to do. The same idea picks `sqlite3.exe` or falls back to Python's `sqlite3` module in `gui-tests.ps1`.

## Pattern 4: error handling, and one Windows gotcha

```powershell
$ErrorActionPreference = 'Stop'      # in gui-tests.ps1: any unexpected error ends the script
```

`'Stop'` is right for scripts that run only PowerShell commands. **In Windows PowerShell 5.1, external programs that write to stderr (as `gh` does for "no checks reported") become script errors under `'Stop'`** when stderr is redirected with `2>&1`. `merge-when-green.ps1` therefore uses `'Continue'` and checks `$LASTEXITCODE` explicitly. Choose the mode per script and say why in a comment.

## Pattern 5: always clean up (`try / finally`)

```powershell
try {
    # drive the app, run checks
}
finally {
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    # restore the user's database, even if a check threw
}
```

`finally` runs on success, on failure and on `throw`. It is how the GUI test guarantees your real database is restored. Back up before, restore in `finally`, and say so at the top of the script.

## Pattern 6: wait for a condition, do not guess with sleeps

```powershell
function WaitFor($scriptBlock, $seconds = 10) {
    for ($i = 0; $i -lt ($seconds * 4); $i++) {
        if (& $scriptBlock) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}
WaitFor { Test-Path $db } 15
```

A script block (`{ ... }`) is passed in and re-evaluated. This is fast when the thing is ready and patient when it is not, and it returns a clear true or false. The same shape waits for windows, dialogs and CI checks.

## Pattern 7: run something with a time limit

```powershell
$j = Start-Job { Set-Location $using:PWD; powershell -NoProfile -File scripts\gui-tests.ps1 2>&1 | Out-String }
if (Wait-Job $j -Timeout 150) { $out = Receive-Job $j } else { $out = 'TIMEOUT'; Stop-Job $j }
```

A background job plus `Wait-Job -Timeout` means a blocked dialog cannot hang your terminal forever. `$using:` passes a variable into the job. Afterwards, close any leftover process by its **id** (`Stop-Process -Id <pid>`), not by name, so you cannot kill something unrelated.

## Pattern 8: count, do not trust one run

```powershell
$pass = 0
for ($i = 1; $i -le 10; $i++) {
    $out = powershell -NoProfile -File scripts\gui-tests.ps1 | Out-String
    if ($out -match 'All GUI checks passed') { $pass++ } else { $out; break }
}
"passed $pass of $i"
```

A flaky test needs a pass count. This stops at the first failure and prints its output.

## Pattern 9: call Windows APIs and UI Automation

```powershell
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes   # load a .NET library
Add-Type @'
using System.Runtime.InteropServices;
public static class W32 {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
}
'@
```

`Add-Type` with C# declares a Windows API (`user32.dll`) that PowerShell can then call as `[W32]::PostMessage(...)`. The pattern is: find a control with UI Automation, act with a Win32 message, then verify the effect somewhere that does not depend on the screen (here, the SQLite file). `PostMessage` returns immediately; `SendMessage` waits and would hang if the click opens a modal dialog. Details are in the comments of [gui-tests.ps1](../scripts/gui-tests.ps1).

## Pattern 10: pass data safely

- **Single-quoted strings** (`'...'`) are literal. Use them for paths and SQL unless you need variables.
- **Double-quoted strings** (`"..."`) expand `$variables` and `$( ... )`.
- **Here-strings** (`@' ... '@`) hold multi-line text. The closing `'@` must start in column 0. PowerShell has no `<<EOF`.
- Prefer environment variables to cram data into another program's command line (the Python SQL fallback does this) to avoid quoting problems.

## Pattern 11: check a script without running it

```powershell
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path scripts\gui-tests.ps1), [ref]$null, [ref]$errors)
"parse errors: $($errors.Count)"
```

This syntax check ran after every edit of the large scripts and caught a mistake early. It does not run the code.

## Pattern 12: wrap a CLI and decide from structured output

```powershell
$info = gh pr view $Pr -R $Repo --json state,mergeable,headRefName | ConvertFrom-Json
if ($info.state -ne 'OPEN' -or $info.mergeable -ne 'MERGEABLE') { exit 1 }
```

Ask a CLI for JSON (`--json`) and parse it with `ConvertFrom-Json` instead of matching on human-readable text, which can change and behaves differently when redirected. The wait-for-checks logic in `merge-when-green.ps1` was changed for exactly this reason (see [RUNBOOK.md](./RUNBOOK.md#when-something-goes-wrong)).

## Conventions for new scripts

1. **Header comment:** what it does, how to run it, what exit codes mean, what it changes on the machine.
2. **Explain the non-obvious lines**, not every line. Pattern comments belong near the pattern.
3. **Fail loudly and early** with a message that says what to do next.
4. **Clean up in `finally`.** Never leave test data, processes or backup files behind.
5. **Take parameters** (`param(...)`) instead of hard-coding values that change, and give them safe defaults.
6. **Do not use `Invoke-Expression`**, and do not build commands from untrusted text.
7. **Run it three ways before you trust it:** the parse check, a normal run, and a deliberate failure (to see that the exit code really is non-zero).
8. **Say what was not tested** in the PR.

## Where PowerShell is *not* used

The pre-commit hook is a `sh` script because Git runs hooks through its bundled shell on Windows; it calls `powershell.exe` for the real work. GitHub Actions steps use `shell: pwsh`.
