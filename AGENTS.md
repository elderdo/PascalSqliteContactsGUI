# Instructions for AI coding agents

Project: a Lazarus / Free Pascal desktop app with a SQLite database. See [CODE_GUIDE.md](./CODE_GUIDE.md) for the structure and [docs/AI_WORKFLOW.md](./docs/AI_WORKFLOW.md) for why these rules exist.

## Build and test

- Build: `lazbuild hellocontacts.lpi` (use `-B` for a full rebuild). Lazarus is at `C:\lazarus` on the author's machine.
- Test: `powershell -NoProfile -File scripts\run-tests.ps1`. Exit code 0 means all tests passed. This is the same script the pre-commit hook and CI use.
- Windows only (the app uses the `Windows` unit). Use PowerShell, not bash, for paths with backslashes.

## Rules

1. Make small, focused changes. Do not refactor unrelated code.
2. For a bug fix, write the failing test first, then fix it.
3. Run the tests before proposing a commit, and say what you actually ran.
4. Never state that something works, or is validated, unless you ran it. Mark anything untested.
5. Do not commit secrets or personal paths. Do not use `git commit --no-verify` unless the user asks.
6. Update [CODE_GUIDE.md](./CODE_GUIDE.md) and [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md) when behavior or structure changes.
7. Use parameterized SQL in new code. Existing string-built SQL is a known issue (see the guide), not a pattern to copy.
8. Keep comments sparse; put explanations in the guide.
9. Changes reach `master` by pull request only. Disclose AI assistance in the PR.

## Layout

- Application units and forms in the repo root; SQL helpers in `utils.pas`; DB setup in `unitdata.pas`.
- Tests in `tests\` (FPCUnit). The test project compiles `utils.pas` directly and uses a temporary SQLite database built from `resources\helloContacts-SCHEMA.sql`.
- Pipeline: `.githooks\pre-commit`, `scripts\run-tests.ps1`, `.github\workflows\`.

## Gotchas

- SQLite foreign keys must be enabled per connection, before connecting, via `Utils.EnableForeignKeys`.
- The test project needs the `Interfaces` unit because `Utils` uses `Forms`.
- `gh` may target the wrong repository: pass `-R elderdo/PascalSqliteContactsGUI`.
