# Demo script (about 10 minutes)

Goal: show how a small Pascal app is run like a production system. Rehearse once. Every command below has been run on this project, including the blocked merge in step 7 (see "Validated after the first pass" in the guide).

**Setup before the demo:** VS Code open on the repo, a PowerShell terminal in the project root, the GitHub repository open in a browser, `core.hooksPath` set (`git config core.hooksPath` prints `.githooks`).

## 1. The product (1 min)

Run the app (task **Run**, or `.\hellocontacts.exe`). Add a person, add a phone number, delete the person. Say: "A deliberately simple contacts app. The point is everything around it."

Manual smoke test for the areas automation does not cover (see the gaps in [REQUIREMENTS.md](./REQUIREMENTS.md)): the window appears on screen, the grids load, Add/Edit/Delete dialogs open and close.

## 2. The map (1 min)

Open [CODE_GUIDE.md](../CODE_GUIDE.md) and the CI/CD architecture diagram. Show [REQUIREMENTS.md](./REQUIREMENTS.md): "every requirement points at the tests that prove it, and the gaps are listed openly."

## 3. Green path locally (1 min)

```powershell
powershell -NoProfile -File scripts\run-tests.ps1
$LASTEXITCODE
```

Expect 22 tests, 0 failures, exit code 0.

## 4. Gate one: the pre-commit hook (2 min)

Break a rule on purpose: in [utils.pas](../utils.pas), change `<= 999999999` to `<= 99999999` in `ValidatePhone`.

```powershell
git switch -c demo-break
git add utils.pas
git commit -m "demo: break phone validation"
```

Expect: `NineDigitsIsRejected` fails, "tests failed, commit aborted", nothing committed. Say: "The bad change never left my machine."

## 5. Gate two: CI (3 min)

Skip the hook to simulate a developer who did not install it, then let the server catch it:

```powershell
git commit --no-verify -m "demo: break phone validation"
git push -u origin demo-break
gh pr create -R elderdo/PascalSqliteContactsGUI --base master --title "DEMO: broken change" --body "Demo"
gh pr checks -R elderdo/PascalSqliteContactsGUI --watch
```

Expect the `test` check to go red (about 3 minutes; talk through the governance docs while it runs: [COMPLIANCE.md](./COMPLIANCE.md), [AI_WORKFLOW.md](./AI_WORKFLOW.md)). Then show the failed log:

```powershell
gh run list -R elderdo/PascalSqliteContactsGUI --branch demo-break --limit 1
gh run view <run-id> -R elderdo/PascalSqliteContactsGUI --log-failed
```

## 6. Evidence (30 s)

On the run page, open the **test-results** artifact: "retained test evidence for every run."

## 7. Gate three: merge is blocked (30 s)

On the pull request page, show the disabled merge button ("Required statuses must pass"). Say: "Applies to me as the owner too."

## 8. Fix and go green (1 min of talking, 3 of waiting)

```powershell
git revert --no-edit HEAD
git push
```

The check turns green and the merge button enables. Close the demo PR without merging:

```powershell
gh pr close demo-break -R elderdo/PascalSqliteContactsGUI --delete-branch
git switch master
git branch -D demo-break
```

## 9. Releases and AI (2 min)

- Show a published release: the zip, the `.sha256` file and the attestation, built only after tests passed ([release.yml](../.github/workflows/release.yml)).
- Show [AI_WORKFLOW.md](./AI_WORKFLOW.md): AI proposes, the pipeline verifies, a human approves. Point at the real example where AI's first fix failed and the test caught it.

## Tips

- The CI run takes about 3 minutes (installing Lazarus is most of it). Start it early and use the wait to talk.
- If the network is unreliable, show a previous failed run from the Actions tab instead of creating a new one.
- Be ready for "is this Delphi?": no, it is Lazarus / Free Pascal. The ideas carry over (FPCUnit maps to DUnitX, `lazbuild` to MSBuild/`dcc`); the workflows would need Delphi tooling and licences.
- Be ready for "is this compliant?": see [COMPLIANCE.md](./COMPLIANCE.md). The process is the foundation; the app lacks audit trail, authentication and signatures.
