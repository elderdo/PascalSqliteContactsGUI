<#
  Waits for a pull request's CI to finish, then squash-merges it and syncs your clone.
  Usage:  powershell -NoProfile -File scripts\merge-when-green.ps1 -Pr 14

  Stops without merging if CI fails or the PR is not mergeable. Exit code 0 = merged.
  See docs\RUNBOOK.md for the full process and why each step exists.

  Prerequisites: the GitHub CLI (gh) is installed and signed in (gh auth status).
  Run it from a clone whose checked-out branch contains this script, and do not edit files
  or switch branches while it waits, because step 5 changes branches.
  Exit codes: 0 = merged and synced, 1 = stopped without merging (the message says why).
#>
param(
    [Parameter(Mandatory)][int]$Pr,
    # gh can guess the wrong repository, so the repo is always passed explicitly
    [string]$Repo = 'elderdo/PascalSqliteContactsGUI'
)
# Native commands write to stderr in normal operation (for example "no checks reported"), and
# 'Stop' would turn that into a script error, so exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'

# 1. Right after a push GitHub needs a few seconds to register the checks. Count them from the
#    PR's JSON instead of matching message text, which is not a stable interface.
for ($i = 0; $i -lt 30; $i++) {
    $count = gh pr view $Pr -R $Repo --json statusCheckRollup -q '.statusCheckRollup | length' 2>$null
    if ($count -and [int]$count -gt 0) { break }
    Start-Sleep -Seconds 10
}
if (-not $count -or [int]$count -eq 0) {
    Write-Host "No CI checks appeared for PR $Pr after 5 minutes. Not merging."
    exit 1
}

# 2. Wait for the checks. Exit code 0 = all passed, anything else = failed or error.
#    If you push again while this waits, GitHub cancels the old run and the newest one is shown.
gh pr checks $Pr -R $Repo --watch --interval 15
if ($LASTEXITCODE -ne 0) {
    Write-Host "CI did not pass for PR $Pr. Not merging. Read the failure with:"
    Write-Host "  gh run list -R $Repo -L 3   then   gh run view <run-id> -R $Repo --log-failed"
    exit 1
}

# 3. Confirm the PR is still open and mergeable (no conflicts, protection satisfied).
$info = gh pr view $Pr -R $Repo --json state,mergeable,headRefName | ConvertFrom-Json
if ($info.state -ne 'OPEN' -or $info.mergeable -ne 'MERGEABLE') {
    Write-Host "PR $Pr is $($info.state) / $($info.mergeable). Not merging."
    exit 1
}

# 4. Squash-merge and delete the remote branch.
gh pr merge $Pr -R $Repo --squash --delete-branch
if ($LASTEXITCODE -ne 0) {
    # Typical cause: master moved on while CI ran ("head branch is not up to date").
    Write-Host 'Merge failed. If the branch is behind master, run: git fetch origin; git merge origin/master; git push'
    Write-Host 'then run this script again (CI restarts on the new push).'
    exit 1
}

# 5. Sync the local clone. -D is needed because a squashed branch is not seen as merged by git.
git checkout master
git pull
git branch -D $info.headRefName 2>$null
git remote prune origin | Out-Null
git --no-pager log --oneline -1
Write-Host "PR $Pr merged and local master synced."
