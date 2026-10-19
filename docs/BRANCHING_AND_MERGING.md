# Branching, pull requests and merges

How changes reach `master` in this repository, and a record of what was actually merged. The history below comes from `gh pr list` and `git log --first-parent`, not from memory.

## The approach

**Trunk-based with short-lived branches and pull requests.** `master` is always releasable. Nothing is committed to it directly.

```
master ──●───────────────●───────────────●──  (one squash commit per PR)
          \             /
           branch ─●─●─●   commits on the branch, hook runs on each
                        \
                         PR ─► CI "test" must pass ─► squash-merge ─► branch deleted
```

| Rule | How it is enforced |
|---|---|
| No direct pushes to `master` | Branch protection, **including administrators** (`enforce_admins: true`) |
| CI must pass before merge | Required status check `test` (unit tests, build, GUI tests) |
| Tests run before a commit exists | `.githooks\pre-commit` (unit tests, then GUI tests) |
| Changes are described and disclosed | `.github\PULL_REQUEST_TEMPLATE.md` (checklist, AI disclosure, test evidence) |
| One reviewable unit of history per change | Squash-merge, delete branch |

Not enforced today: a required human approval (`required_approving_review_count` is 0), which suits a solo project. A team should raise it to 1 and require code-owner review.

## Branch naming

| Prefix | Use | Example |
|---|---|---|
| `fix/` | bug fixes | `fix/gui-crashes-and-gui-tests` |
| `ci/` | pipeline changes | `ci/gui-diagnostics` |
| `docs-` | documentation only | `docs-roadmap` |
| `dependabot/...` | automatic dependency updates | `dependabot/github_actions/actions/checkout-7` |
| `*-test` | throwaway branches that prove a gate works, then closed unmerged | `ci-red-test`, `merge-block-test` |

## Life of a change (the routine)

1. `git checkout master; git pull` (start from the latest `master`)
2. `git checkout -b fix/<short-name>`
3. Test first, fix, commit in small steps. The hook blocks a commit if tests fail.
4. `git push -u origin <branch>`
5. `gh pr create -R elderdo/PascalSqliteContactsGUI ...` using the PR template
6. CI runs on the PR. Read failures with `gh run view <id> --log-failed`
7. When `test` is green: `gh pr merge <n> -R ... --squash --delete-branch`
8. Sync: `git checkout master; git pull; git branch -D <branch>; git remote prune origin`

Every command is explained in [TESTING_AND_DEBUGGING.md](./TESTING_AND_DEBUGGING.md).

## Why squash-merge

All commits in a PR become one commit on `master`, with the PR number in its title. History stays one-commit-per-change and a whole change reverts with one `git revert`. Cost: the individual commits are only visible on the PR page, and the local branch must be force-deleted (`git branch -D`) because git cannot see it as merged. The co-author trailers of the branch commits are kept in the squash message (checked on `947195c`).

## Merge record

From `gh pr list --state all` and `git log master --first-parent` (dates UTC).

| PR | Branch | Outcome | What it was |
|---|---|---|---|
| #1 | `ci-red-test` | Closed, not merged | Deliberately failing test, to prove CI goes red |
| #2 | `showcase-governance` | Merged (squash), 2026-10-08 | Governance, traceability, AI workflow, release pipeline, demo docs |
| #5 | `dependabot/.../upload-artifact-6` | Closed | Superseded by a newer Dependabot bump |
| #6 | `merge-block-test` | Closed, not merged | Proved a red PR cannot be merged |
| #7 | `docs-validation-results` | Merged (squash), 2026-10-08 | Recorded branch-protection and release validation |
| #8 | `docs-roadmap` | Merged (squash), 2026-10-08 | Roadmap and DI refactoring plan |
| #10 | `fix/gui-crashes-and-gui-tests` | Merged (squash), 2026-10-19, commit `947195c` | `WriteLn` crash fix, commit/dataset fixes, GUI tests, hook and CI step, docs. Seven branch commits became one |
| #11 | `ci/gui-diagnostics` | Open when this was written | GUI log and failure-screenshot artifacts, AI guide, case study |
| #3, #4, #9 | Dependabot action bumps | Open | Not reviewed or merged yet |

The branch protection rule was verified (see [CODE_GUIDE.md](../CODE_GUIDE.md#cicd-pipeline-architecture-and-setup)) by the two closed `*-test` PRs: one showed a red build, the other showed that merge is blocked while it is red.

## Releases

Pushing a tag such as `v0.1.0` runs `release.yml` (tests, full rebuild, zip with SHA-256, build attestation, GitHub release). No release has been cut from the PR #10 work yet; that is a separate, deliberate step.

## Pitfalls seen here

- **Superseded runs are cancelled.** Pushing again while CI is running cancels the older run (it shows "cancelled", and `gh run watch --exit-status` returns 1). It is not a test failure; look at the run for the newest commit.
- **`gh` can pick the wrong repository.** Always pass `-R elderdo/PascalSqliteContactsGUI`.
- **Do not reuse a squash-merged branch.** Delete it and branch fresh from `master`.
- **Locked exe.** A running `hellocontacts.exe` breaks the build and the GUI test; close it first.
