# Pascal SQLite Contacts: a production-minded Pascal project

[![CI](https://github.com/elderdo/PascalSqliteContactsGUI/actions/workflows/ci.yml/badge.svg)](https://github.com/elderdo/PascalSqliteContactsGUI/actions/workflows/ci.yml)

A small contacts app (people and phone numbers in a SQLite database) written in Object Pascal with the free, open source [Lazarus](https://www.lazarus-ide.org/) IDE and the [Free Pascal Compiler](https://www.freepascal.org/). The app is deliberately simple. **The point is the engineering around it:** automated tests, enforced quality gates, a CI/CD pipeline, requirements traceability, governed use of AI, and documentation that says what is and is not proven.

It began as a "Hello World" for SQLite in Pascal, for two reasons:
 1. Because I was interviewing for a job requiring the use of Pascal (in 2023!)
 2. I wanted to review SQL databases.

## What this project demonstrates

| Practice | Where to look |
|---|---|
| Automated unit tests (22 FPCUnit tests; one found a real bug) | [CODE_GUIDE.md: Unit tests](./CODE_GUIDE.md#unit-tests) |
| Local quality gate (pre-commit hook runs the tests) | [.githooks/pre-commit](./.githooks/pre-commit) |
| CI on every push and pull request, with retained test evidence | [ci.yml](./.github/workflows/ci.yml) |
| Verified pipeline (red and green paths shown for real) | [CODE_GUIDE.md: Validating the pipeline](./CODE_GUIDE.md#validating-the-pipeline) |
| Requirements traced to tests, with gaps shown | [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md) |
| Change control (PR template, code owners, protected `master`) | [.github/](./.github) |
| Tagged releases with checksum and build attestation | [release.yml](./.github/workflows/release.yml) |
| AI-assisted development with written guardrails | [docs/AI_WORKFLOW.md](./docs/AI_WORKFLOW.md), [AGENTS.md](./AGENTS.md) |
| Regulated-environment thinking, including the honest gaps | [docs/COMPLIANCE.md](./docs/COMPLIANCE.md) |
| A rehearsed 10-minute walkthrough | [docs/DEMO_SCRIPT.md](./docs/DEMO_SCRIPT.md) |

**Features of the app:** basic CRUD on a relational SQL database, including auto-creating the database file from an embedded `.sql` resource; Lazarus forms and database-aware components; multiple units and classes; windows that always open on a visible monitor.

**Design:** three relational tables: People, PhoneNumbers and PhoneTypes. You can add, edit and delete people and phone numbers.

![Screenshot](./images/helloContactsScreenshot.png) 

## Quick start (Windows)

```powershell
git clone https://github.com/elderdo/PascalSqliteContactsGUI.git
cd PascalSqliteContactsGUI
git config core.hooksPath .githooks          # enable the pre-commit test gate
lazbuild hellocontacts.lpi                   # build (Lazarus must be installed)
powershell -File scripts\run-tests.ps1       # run the unit tests
.\hellocontacts.exe                          # run the app (needs sqlite3.dll on PATH or beside the exe)
```

## Documentation

* [Code Guide](./CODE_GUIDE.md): code structure, startup sequence, what each source file does, the tests, and the CI/CD pipeline with troubleshooting.
* [Requirements and traceability](./docs/REQUIREMENTS.md)
* [Compliance considerations](./docs/COMPLIANCE.md)
* [AI-assisted development](./docs/AI_WORKFLOW.md)
* [Demo script](./docs/DEMO_SCRIPT.md)
* [Security policy](./SECURITY.md) and [Changelog](./CHANGELOG.md)
* [DevLog](./DevLog.MD): development notes.

## Roadmap

Honest list of what is not done yet:

- Parameterized SQL instead of string-built statements (see known quirks in the guide).
- One-time cleanup for orphaned phone rows in databases created before the foreign-key fix.
- Audit trail, user authentication and electronic signatures (needed for regulated data; see [COMPLIANCE.md](./docs/COMPLIANCE.md)).
- GUI test automation and code coverage reporting.
- Copilot coding agent setup for labelled issues, gated by the same checks.
- Windows only for now (the code uses the `Windows` unit).


## What I Learned

Although the IDE was sometimes glitchy, requiring restarts in order to create new form event methods, overall it was a decent programming experience.   Cross-platform support is present, such as resource files for images, and ability to create the database file in an OS-Recommended location

The Pascal Language is a capable object oriented languge, and the "drag and drop" design experience is Familiar to anyone that has used Borland programming environments (Turbo-C anyone?) or Windows Forms. 

While these environments are fun to program in, they tend to mash together UI code and core logic unless care is taken.   I approached this as follows

* Minimize USE of SQL in the component designer and form files
* Instead, place most SQL in a separate "Utils" module 

## Attributions 

 * Contacts Icon from [Stephen Hutchings Typicons-2](https://www.iconfinder.com/iconsets/typicons-2) icon pack on [IconFinder.com](https://www.iconfinder.com/)
   * License is [Creative Commons Attribution-Sharalike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/)
   * No Changes were made to the icon.
