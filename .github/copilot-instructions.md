# Copilot instructions

Follow the rules in [AGENTS.md](../AGENTS.md) at the repository root. In short:

- Lazarus / Free Pascal, SQLite, Windows only. Build with `lazbuild hellocontacts.lpi`; test with `scripts\run-tests.ps1`.
- Small, focused changes. A bug fix starts with a failing FPCUnit test in `tests\`.
- Do not claim anything works unless it was run. Mark untested items.
- Use parameterized SQL in new code. Keep code comments sparse; explain in `CODE_GUIDE.md`.
- Update `docs/REQUIREMENTS.md` and `CODE_GUIDE.md` with behavior changes.
- Changes go through pull requests; disclose AI assistance in the PR template.
