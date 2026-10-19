# Builds and runs the FPCUnit tests. Exit code 0 = all passed.
# Used by the pre-commit hook and the GitHub Actions workflow.

# Beginner notes:
#   * Run it from anywhere:  powershell -NoProfile -File scripts\run-tests.ps1
#   * "Exit code" is the number a program hands back when it ends. 0 means success,
#     anything else means failure. Git hooks and CI read that number to decide pass/fail.
#   * Exit codes used here: 0 = tests passed, 1 = build or tests failed, 2 = lazbuild missing.

# Stop the script at the first unexpected error instead of carrying on.
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is the folder this script lives in (scripts\). Go one level up to the
# repository root so relative paths like tests\... work no matter where we were started.
Set-Location (Join-Path $PSScriptRoot '..')

# Find lazbuild (the Lazarus command-line compiler): first on PATH, then the default
# install folder. If neither works there is nothing we can do, so exit with code 2.
$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild -and (Test-Path 'C:\lazarus\lazbuild.exe')) { $lazbuild = 'C:\lazarus\lazbuild.exe' }
if (-not $lazbuild) { Write-Host 'lazbuild not found. Add Lazarus to PATH.'; exit 2 }

# Compile the test project. '&' runs the program stored in the variable.
# $LASTEXITCODE holds the exit code of the last program that ran.
& $lazbuild 'tests\hellocontacts_tests.lpi'
if ($LASTEXITCODE -ne 0) { Write-Host 'Test project failed to build.'; exit 1 }

# Run every FPCUnit test and print plain text. Its exit code becomes ours, so a failing
# test makes this script (and therefore the commit or CI job) fail.
& '.\tests\hellocontacts_tests.exe' --all --format=plain
exit $LASTEXITCODE
