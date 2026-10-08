# Builds and runs the FPCUnit tests. Exit code 0 = all passed.
# Used by the pre-commit hook and the GitHub Actions workflow.

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild -and (Test-Path 'C:\lazarus\lazbuild.exe')) { $lazbuild = 'C:\lazarus\lazbuild.exe' }
if (-not $lazbuild) { Write-Host 'lazbuild not found. Add Lazarus to PATH.'; exit 2 }

& $lazbuild 'tests\hellocontacts_tests.lpi'
if ($LASTEXITCODE -ne 0) { Write-Host 'Test project failed to build.'; exit 1 }

& '.\tests\hellocontacts_tests.exe' --all --format=plain
exit $LASTEXITCODE
