# Which AI to use, and prompts that work

Companion to [AI_WORKFLOW.md](./AI_WORKFLOW.md) (the rules and controls). This page is the practical part: which kind of AI to use for each job on this project, and prompts you can copy. Every prompt follows the same loop: **evidence, then test, then fix, then proof**.

## Which AI to use

**Recommended for this project: GitHub Copilot in agent mode** (Copilot CLI, or Copilot Chat in VS Code with the Copilot SDK). Reasons:

- It can run commands (`lazbuild`, the test scripts, `git`, `gh`), read your files and edit them, so it can reproduce a bug and check its own fix. A chat box that only sees pasted code cannot do that.
- It reads [AGENTS.md](../AGENTS.md) and [.github/copilot-instructions.md](../.github/copilot-instructions.md) automatically, so the project rules apply without repeating them.
- It works with GitHub (`gh`), so pull requests, CI logs and issues are in reach.

**Model choice.** Pick by task, not by brand. Model names and rankings change often and I have not benchmarked them here, so treat this as a rule of thumb and check what your Copilot plan currently offers (the model picker in VS Code or `/model` in the CLI):

| Job | What to pick | Why |
|---|---|---|
| Hard debugging, intermittent failures, design decisions | The strongest "reasoning" model available | Needs multi-step investigation (the "inactive dataset" bug took several rounds) |
| Routine edits, comments, docs, renames | A fast, cheaper model | Low risk, easy to review |
| Reviewing a pull request | A different model than the one that wrote the code | A second opinion catches different mistakes |
| Searching a big codebase | An agent with search tools, not a plain chat | Reads files instead of guessing |

Premium models cost more of your Copilot allowance. Start with the default, and move up only when a task stalls.

**Not suitable:** plain chat without tool access for anything that must be run (it will guess), and any tool that sends the repository to a service your organization has not approved.

## Prompt recipe

A good prompt has five parts. Missing parts are the usual cause of poor answers.

1. **Goal**: one sentence.
2. **Evidence**: the exact error text, steps to reproduce, log or file names.
3. **Constraints**: "small change", "test first", "do not touch X".
4. **Proof required**: which commands must pass.
5. **Output**: what you want back (a diff, a summary, a PR).

## Copy-paste prompts

### Fix a crash

> I get this error when I click Delete: "Operation cannot be performed on an inactive dataset" (paste the exact text). Steps: search, select a row, click Delete, choose OK. First find the cause with evidence (a stack trace or a failing test), not a guess. Then write a failing FPCUnit test in `tests\`, fix the smallest thing, run `scripts\run-tests.ps1` and `scripts\gui-tests.ps1`, and tell me exactly what you ran and what passed.

### Intermittent or flaky failure

> The GUI test passes about half the time and fails at "Delete: row removed from database". Run it 10 times in a row and report the pass count. When it fails, capture what is on screen and the database rows. Tell me whether the app or the test is at fault, with evidence, before changing anything.

### Add a feature

> Add a "Phone type" filter to search. Update `docs\REQUIREMENTS.md` and `CODE_GUIDE.md`. Use parameterized SQL. Write unit tests first, then implement. Do not refactor unrelated code. Show me the plan before editing.

### Add a GUI test step

> Extend `scripts\gui-tests.ps1` to cover Edit Phone. Follow the existing helper style (`WaitWindow`, `Check`, SQL verification). Comment the new code for a beginner. Run it 5 times and report the results. Restore the user database afterwards.

### Diagnose a CI failure

> CI run <id> failed. Run `gh run view <id> -R elderdo/PascalSqliteContactsGUI --log-failed`, and if present download the `gui-evidence` artifact. Explain the root cause, say whether I can reproduce it locally, and propose a fix. Do not change anything yet.

### Review before merging

> Review the diff of this branch for bugs and risky changes only (not style). For each finding give file, line, why it matters and how confident you are. Say what you could not verify.

### Explain code or an error to a beginner

> Explain `scripts\gui-tests.ps1` step by step as if I have never used PowerShell. Then list which parts would break if Windows or the app changed.

### Commit and PR

> Split these changes into small commits, in a sensible order, each with a clear message. Create a branch, push it, open a PR using `.github\PULL_REQUEST_TEMPLATE.md` with the exact test commands and results, wait for CI, and tell me the result before merging.

## Habits that save time

- **Paste exact error text and logs**, not a paraphrase.
- **Ask for the plan first** on anything larger than a few lines, and approve it.
- **Ask it to say what it did not run.** Untested claims are the main risk (see rule 4 in [AI_WORKFLOW.md](./AI_WORKFLOW.md)).
- **Keep one task per conversation**, with small commits, so a wrong turn is cheap to undo.
- **Tell it about the machine** when it matters: Windows only, PowerShell not bash, Lazarus at `C:\lazarus`, `gh` needs `-R elderdo/PascalSqliteContactsGUI`. These live in `AGENTS.md`, so update that file when you find a new gotcha.
- **Say when to stop.** "Do not merge", "do not push" and "ask me before deleting" are respected.
- **You decide.** AI proposes; the tests verify; a human approves and merges.

## Anti-patterns

| Do not | Do instead |
|---|---|
| "Fix the app" | State the symptom, steps and exact error |
| Accept "this should work" | Require the commands run and their results |
| Let it use `--no-verify` to get past the hook | Fix what the hook found |
| Paste secrets or customer data | Use dummy data; the GUI test already uses throwaway rows |
| Ask it to approve or merge its own PR | Review it yourself |
