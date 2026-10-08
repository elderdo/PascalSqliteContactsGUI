# Code Guide: Hello Contacts

A Lazarus / Free Pascal desktop app (Windows) that manages contacts and their phone numbers in a local SQLite database. This guide describes how the code is organized and what each source file does, so the source itself can stay lightly commented.

- [Overview](#overview)
- [Project layout](#project-layout)
- [How the pieces fit together](#how-the-pieces-fit-together)
- [Startup sequence](#startup-sequence)
- [Source files](#source-files)
- [Window placement](#window-placement-ensureonscreen)
- [Database](#database)
- [Unit tests](#unit-tests)
  - [Automated checks (pre-commit hook and CI)](#automated-checks-pre-commit-hook-and-ci)
- [CI/CD pipeline: architecture and setup](#cicd-pipeline-architecture-and-setup)
- [Embedded resources](#embedded-resources)
- [Build and run](#build-and-run)
- [Known quirks and TODOs](#known-quirks-and-todos)
- [Roadmap (to-do list)](#roadmap-to-do-list)

## Overview

| Item | Value |
|---|---|
| Language / IDE | Free Pascal (`{$mode objfpc}`), Lazarus LCL |
| Database | SQLite via `SQLite3Conn` / `SQLDB` |
| UI | One main form (contact list + phone list) and two modal dialogs |
| Database file | `helloContacts.db` in the user's app-config folder (`GetAppConfigDir(False)`) |

## Project layout

| File | Role |
|---|---|
| [hellocontacts.lpr](./hellocontacts.lpr) | Program entry point |
| [hellocontacts.lpi](./hellocontacts.lpi) | Lazarus project file (units, packages, build options) |
| [unit1.pas](./unit1.pas) / [unit1.lfm](./unit1.lfm) | Main window (`TFormContacts`) |
| [unitdata.pas](./unitdata.pas) / [unitdata.lfm](./unitdata.lfm) | Data module: connection, queries, data sources (`TDataModule1`) |
| [unitaddcontact.pas](./unitaddcontact.pas) / [unitaddcontact.lfm](./unitaddcontact.lfm) | Add/Edit contact dialog (`TFrmAddContact`) |
| [unitaddphone.pas](./unitaddphone.pas) / [unitaddphone.lfm](./unitaddphone.lfm) | Add/Edit phone dialog (`TFrmAddPhone`) |
| [utils.pas](./utils.pas) | Non-visual helpers: input parsing, SQL insert/update/delete |
| [resources.rc](./resources.rc) | Resource script: embeds the icon image and SQL schema |
| [resources/helloContacts-SCHEMA.sql](./resources/helloContacts-SCHEMA.sql) | Database schema, run on first launch |
| [.vscode/tasks.json](./.vscode/tasks.json) | VS Code build/test/run tasks |
| [tests/](./tests) | FPCUnit test project (see [Unit tests](#unit-tests)) |
| [.githooks/pre-commit](./.githooks/pre-commit), [scripts/run-tests.ps1](./scripts/run-tests.ps1) | Git pre-commit hook and the script that builds and runs the tests |
| [.github/workflows/ci.yml](./.github/workflows/ci.yml) | GitHub Actions workflow (see [Automated checks](#automated-checks-pre-commit-hook-and-ci)) |

Each `.pas` form unit has a matching `.lfm` file holding the form's visual layout and component properties (the Lazarus designer reads and writes these).

## How the pieces fit together

```
                        hellocontacts.lpr
                  (creates the data module and forms)
                               |
        +----------------------+----------------------+
        |                      |                      |
   unit1.pas              unitaddcontact.pas     unitaddphone.pas
   Main window            Add/Edit contact       Add/Edit phone
        |                      |                      |
        +----------+-----------+----------+-----------+
                   |                      |
              utils.pas              unitdata.pas
        (SQL write helpers,       (SQLite connection,
         validation, parsing)      queries, data sources)
                                          |
                                  helloContacts.db
                      (created from the embedded SCHEMA.sql)
```

Responsibilities:

- **Forms** handle user interaction and call into `Utils` or the data module.
- **`UnitData`** owns the database connection and the queries that feed the grids and the phone-type drop-down.
- **`Utils`** performs inserts, updates, and deletes through the shared `QueryInsert` query.
- The main form's grids show data through `DSPeople` and `DSPhones`, which are bound to `QueryPeople` and `QueryPhones`.

## Startup sequence

From [hellocontacts.lpr](./hellocontacts.lpr):

1. Resources are compiled in (`{$R resources.rc}`) and the project icon is loaded (`{$R *.res}`).
2. `Application.CreateForm` creates, in order: `DataModule1`, `FormContacts`, `FrmAddContact`, `FrmAddPhone`.
3. `DataModule1.OnCreate` runs `EnsureDatabasePresent` (create the DB and tables if missing) and `InitializePhoneTypesQuery`.
4. `FormContacts.OnCreate` loads the logo image from the embedded resource.
5. `FormContacts.OnActivate` activates the queries, refreshes the grids, and hides ID columns.
6. `Application.Run` starts the event loop.

The data module must be created first, because every form uses it.

## Source files

### [hellocontacts.lpr](./hellocontacts.lpr)

The program file. It lists the units, enables scaling (`Application.Scaled`), and creates the data module and all three forms. It contains the note about restarting the IDE when resources don't compile.

### [unitdata.pas](./unitdata.pas)

Class `TDataModule1` (global `DataModule1`). A non-visual container for the database components declared in [unitdata.lfm](./unitdata.lfm):

| Component | Purpose |
|---|---|
| `SQLite3Connection1` | The SQLite connection |
| `SQLTransaction1` | Shared transaction |
| `QueryPeople` | `SELECT Id, First || ' ' || Last AS Name FROM People ORDER BY First`; feeds the contact grid |
| `QueryPhones` | Phone numbers joined to `PhoneTypes`; feeds the phone grid |
| `QueryPhoneType` | Reads the phone-type list for the drop-down |
| `QueryInsert` | General-purpose query used by `Utils` for writes |
| `DSPeople`, `DSPhones` | Data sources bound to the grids |

Methods:

- `DataModuleCreate`: calls `EnsureDatabasePresent` then `InitializePhoneTypesQuery`.
- `EnsureDatabasePresent`: builds the DB path in the app-config folder, creating the folder if needed. If the file doesn't exist, it connects (which creates it), then reads the embedded `DATABASE_SCHEMA` resource and executes it one statement per line, committing after each.
- `InitializePhoneTypesQuery`: runs `SELECT Id, Type FROM PhoneTypes`.
- `EnsureMainQueriesActive`: re-opens `QueryPeople` and `QueryPhones` if they were closed.
- `RefreshAllData`: refreshes both queries and their data sets.

### [unit1.pas](./unit1.pas)

Class `TFormContacts` (global `FormContacts`), the main window. Layout is in [unit1.lfm](./unit1.lfm): a contact grid (`DBGridPeople`), a details panel with a phone grid (`DBGridPhones`), a search box, and Add / Edit / Delete buttons for both contacts and phones.

| Handler / method | What it does |
|---|---|
| `FormCreate` | Loads the `CONTACTS_ICON` resource into `Image1` |
| `FormShow` | Calls `Utils.EnsureOnScreen` so the window is visible, then hides ID columns |
| `FormActivate` | Activates and refreshes queries, hides ID columns, hides the phone panel |
| `ButtonSearchClick` | Applies a server-side filter (`Name Like '%text%'`) on `QueryPeople` |
| `ButtonAddClick` | Splits the search text into first/last name, pre-fills the Add Contact dialog, shows it modally |
| `ButtonEditClick` | Opens the dialog in edit mode for the selected contact |
| `ButtonDeleteClick` | Confirms, then calls `Utils.DeleteUser` (phones are removed by `ON DELETE CASCADE`) |
| `DBGridPeopleCellClick` | Shows the phone panel and loads that person's phones via `Utils.QueryPhones` |
| `ButtonAddPhoneClick`, `ButtonEditPhoneClick`, `ButtonDeletePhoneClick` | Same pattern for phone numbers |
| `ShowDBGridPhones` | Shows or hides the phone panel and sets its caption |
| `GetSelectedId` | Returns the `Id` of the selected grid row, or `-1` |
| `GetSelectedFieldByName` | Returns any field of the selected row as a string |
| `HideIds` | Hides the ID columns in both grids |

### [unitaddcontact.pas](./unitaddcontact.pas)

Class `TFrmAddContact` (global `FrmAddContact`), a modal dialog to create or edit a contact. Layout is in [unitaddcontact.lfm](./unitaddcontact.lfm).

- `SetEditMode` / `GetEditMode`: switch between add and edit.
- `FormShow`: calls `Utils.EnsureOnScreen`, then sets the prompt and caption ("Add Contact" or "Edit Contact").
- `ButtonSaveClick`: requires at least one non-blank name. In edit mode it calls `Utils.EditUser`; otherwise `Utils.AddUser`. It then closes the dialog.
- `ButtonCancelClick`: closes the dialog.

The main form fills in `EditId`, `EditFirst`, and `EditLast` before showing it.

### [unitaddphone.pas](./unitaddphone.pas)

Class `TFrmAddPhone` (global `FrmAddPhone`), a modal dialog to create or edit a phone number. Layout is in [unitaddphone.lfm](./unitaddphone.lfm).

- `FormCreate` → `InitializeTypeDropDown`: fills the type combo box from `QueryPhoneType` and keeps a parallel array (`mPhoneTypeIds`) mapping each combo row to its database `Id`.
- `SetEditMode`, `SetPersonId`, `SetPhoneId`: set state before the dialog is shown.
- `SetPhoneTypeId`: selects the combo row matching a given phone-type `Id`.
- `FormShow`: calls `Utils.EnsureOnScreen`, then sets the prompt and caption.
- `ButtonSaveClick`: validates the number with `Utils.ValidatePhone`, then calls `Utils.AddPhone` or `Utils.EditPhone`.

### [utils.pas](./utils.pas)

Helper routines in a unit with no form. Database functions take the query object as a parameter (the callers pass `DataModule1.QueryInsert`).

| Routine | Purpose |
|---|---|
| `EnsureOnScreen` | Moves a form fully inside the nearest monitor's work area (see [Window placement](#window-placement-ensureonscreen)) |
| `EnableForeignKeys` | Turns on SQLite foreign keys (needed for `ON DELETE CASCADE`); call before connecting |
| `SplitName` | Splits a string on spaces into exactly two entries (first, last); extra words are dropped |
| `ValidatePhone` | Returns the number as `Int64` if it is exactly 10 digits, else `-1` |
| `AddUser` / `EditUser` / `DeleteUser` | `INSERT` / `UPDATE` / `DELETE` on `People`; `AddUser` returns the new `Id` or `-1` |
| `QueryPhones` | Reloads the phone query for one person (joined to `PhoneTypes`) |
| `AddPhone` / `EditPhone` / `DeletePhone` | `INSERT` / `UPDATE` / `DELETE` on `PhoneNumbers` |
| `GetLastInsertID` | Runs `SELECT last_insert_rowid()` |
| `ShowException` | Writes the exception class and message to the debug log |

## Window placement (`EnsureOnScreen`)

`Utils.EnsureOnScreen(F: TForm)` in [utils.pas](./utils.pas) is called at the start of `FormShow` in all three forms ([unit1.pas](./unit1.pas), [unitaddcontact.pas](./unitaddcontact.pas), [unitaddphone.pas](./unitaddphone.pas)).

**What it does:** it finds the monitor nearest the form (`Screen.MonitorFromRect(..., mdNearest)`), takes that monitor's usable work area (excluding the taskbar), and nudges the form so all four edges are inside it. If the form is already fully visible, it does nothing.

**Why it exists:** the `.lfm` files store each form's `Left` and `Top` in one desktop-wide coordinate grid. The primary monitor's top-left corner is 0,0, and monitors to its left or above it use negative values. If the saved numbers point to a monitor that is no longer there (unplugged, rearranged, or a different PC), the LCL opens the window at exactly those numbers.

**What happens without it:**
- The app starts and shows a button on the taskbar, but the window is off-screen and cannot be seen.
- The user cannot click, drag, or close the window normally. This is how the project's off-screen problem appeared (saved values like `Top = -910`).
- The user would have to move the window blindly with Alt+Space → Move and the arrow keys, or edit the `.lfm` files and rebuild.

**How it makes the app more user friendly:**
- The window always opens somewhere visible, whatever the monitor setup (laptops docked and undocked, remote desktop, changed resolution, or a different PC).
- No user action or file editing is needed to recover.
- It also covers the Add/Edit dialogs and any future feature that remembers window positions.
- Positions that are valid are left alone, so a window the user placed deliberately stays where it is.

It works with the `Position` setting in the `.lfm` files. `poScreenCenter` and `poMainFormCenter` choose a sensible starting spot, and `EnsureOnScreen` is the safety net for anything that still ends up out of bounds.

## Database

Defined in [resources/helloContacts-SCHEMA.sql](./resources/helloContacts-SCHEMA.sql), one statement per line:

| Table | Columns |
|---|---|
| `People` | `Id` (PK, autoincrement), `First`, `Last` |
| `PhoneNumbers` | `Id` (PK), `PersonId` → `People(Id)` (`ON DELETE CASCADE`), `PhoneTypeId` → `PhoneTypes`, `Number` |
| `PhoneTypes` | `Id` (PK), `Type`; seeded with `Cell`, `Work`, `Home` |

The schema file must keep **one SQL statement per line**, because `ExecSQL` runs a single statement at a time.

### Where the database file lives

The file is **not** in the project folder. [unitdata.pas](./unitdata.pas) builds the path with `GetAppConfigDir(False)` plus the file name `helloContacts.db`. On Windows this resolves to the per-user local app-data folder, named after the executable:

```
C:\Users\<you>\AppData\Local\hellocontacts\helloContacts.db
```

(`%LOCALAPPDATA%\hellocontacts\helloContacts.db`.) The path is also written to the debug log at startup (`DataBase File: ...`). On other platforms `GetAppConfigDir` returns the OS-standard config location, but this project is Windows-only as written.

### How the database gets created

This happens once, in `TDataModule1.EnsureDatabasePresent`, when the data module is created at startup:

1. Build the full path as above.
2. If the config folder doesn't exist, create it.
3. Point `SQLite3Connection1` at that path and attach `SQLTransaction1`.
4. **If the file already exists:** just connect. Nothing else changes, and existing data is kept.
5. **If the file doesn't exist:** connecting makes SQLite create an empty file. The code then loads the `DATABASE_SCHEMA` resource (the embedded copy of [helloContacts-SCHEMA.sql](./resources/helloContacts-SCHEMA.sql)) into a string list and runs each line with `ExecSQL`, committing after each. This creates the three tables, the indexes, and the `Cell`, `Work`, and `Home` phone types.

Because the schema only runs when the file is missing, editing the `.sql` file does **not** change an existing database.

**To reset to a fresh database:** close the app, delete `helloContacts.db` from the folder above, and start the app again. All contacts are lost.

**To inspect it:** open the file with any SQLite tool, such as DB Browser for SQLite or the `sqlite3` command line.

## Embedded resources

[resources.rc](./resources.rc) embeds two files into the executable as `RCDATA`:

| Resource name | Source file | Used by |
|---|---|---|
| `CONTACTS_ICON` | `resources/contacts_dialer_icon.png` | `TFormContacts.FormCreate` |
| `DATABASE_SCHEMA` | `resources/helloContacts-SCHEMA.sql` | `TDataModule1.EnsureDatabasePresent` |

Edit the `.sql` or `.png` and rebuild to change them. Use **Clean and Build** if the change doesn't appear.

## Build and run

From the project folder (see [.vscode/tasks.json](./.vscode/tasks.json)):

```
lazbuild hellocontacts.lpi        # build
lazbuild -B hellocontacts.lpi     # clean and build
.\hellocontacts.exe               # run
```

In VS Code, use **Terminal → Run Build Task** (Ctrl+Shift+B) or **Terminal → Run Task**: Build, Clean, Clean and Build, Clean Build and Run, Run.

## Unit tests

### Why tests matter here

Unit tests are not optional polish for this project. They are how we find out that code does what we *believe* it does. The clearest example is already in the history of this repo:

> **Case study: the "delete contact" bug.** The delete dialog tells the user *"All of their phone numbers will be deleted!"*, the schema declares `ON DELETE CASCADE`, and the code looked correct. The code looked correct, and nothing in the app would reveal the problem unless someone inspected the database afterwards. The very first test run, `DeleteUserDeletesTheirPhones`, failed: after deleting a contact, **their phone numbers were still in the database**. Orphaned rows silently pile up and the user is told something false.

**Root cause:** SQLite ignores `FOREIGN KEY` constraints, including `ON DELETE CASCADE`, unless `PRAGMA foreign_keys = ON` is set **on every connection**. It is off by default, and the app never turned it on. The SQL was right; the connection setup was missing.

**Fix:** `Utils.EnableForeignKeys` sets the `foreign_keys=ON` connection parameter. It must be called **before** `Connected := True`. In my first attempt, running the pragma after connecting did not fix the failing test, while the connection parameter did (probably because SQLite ignores this pragma once a transaction is open). `TDataModule1.EnsureDatabasePresent` and the test setup both call it. Phone numbers already orphaned in an existing database are not removed by the fix.

What the case study shows:
- **Reading code is not verification.** This bug survived because the code *looked* right. Only running it against a real database exposed it.
- **Silent failures are the dangerous ones.** No error, no crash, just wrong data. Tests are the cheapest way to catch these.
- **Tests that touch the real database layer pay off most.** A pure-logic test could never have found this; it needed a real SQLite file and the real schema.
- **A failing test is a to-do list.** Write the test for the behavior you promised users, watch it fail, then fix the code.

**Working rules for this project:**
1. Every new routine in [utils.pas](./utils.pas) gets tests, including edge cases (empty input, boundaries, apostrophes in names).
2. Every bug fix starts with a test that reproduces the bug, so it cannot come back unnoticed.
3. Anything the UI promises the user (such as "all phone numbers will be deleted") should have a database-level test behind it.
4. Run the full suite before committing. All tests must pass.

### Framework and layout

Tests use **FPCUnit**, the standard Free Pascal / Lazarus test framework (shipped with Lazarus), run through its console runner. They live in [tests/](./tests) as a **separate project**, so test code never ends up in the app.

```
tests/
├── hellocontacts_tests.lpi      Lazarus project for the test program
├── hellocontacts_tests.lpr      Entry point: starts the FPCUnit console runner
├── utilstests.pas               Pure-logic tests (no database)
├── databasetests.pas            Tests against a real temporary SQLite database
└── lib/                         Compiler output (git-ignored)
```

How the project is wired together:

```
hellocontacts_tests.lpr
        |  uses
        +--> Interfaces ........ links the LCL widgetset (needed because Utils uses Forms)
        +--> consoletestrunner .. FPCUnit console runner (command-line options, exit code)
        +--> UtilsTests ......... registers its tests when the unit is loaded
        +--> DatabaseTests ...... registers its tests when the unit is loaded
                 |
                 +--> Utils (from the parent folder, via OtherUnitFiles = "..")
```

- **Shared code, not copies.** The test project compiles the app's own [utils.pas](./utils.pas) directly (search path `..`), so tests exercise the real code.
- **Self-registering tests.** Each test unit calls `RegisterTest(...)` in its `initialization` section. Adding the unit to the `.lpr` `uses` clause is all it takes for the runner to find it.
- **Packages.** The test project requires `FPCUnitConsoleRunner`, `SQLDBLaz`, and `LCL`.

### Test files

| File | Test classes | What they cover |
|---|---|---|
| [tests/utilstests.pas](./tests/utilstests.pas) | `TSplitNameTests` | Empty string, one word, two words, extra words dropped |
| | `TValidatePhoneTests` | Accepts 10 digits and the lowest/highest 10-digit numbers; rejects 9 digits, 11 digits, letters, empty string, formatted numbers like `916-849-0226` |
| [tests/databasetests.pas](./tests/databasetests.pas) | `TPeopleTests` | `AddUser` returns new ids and stores names; apostrophes (`O'Brien`) are handled; `EditUser` changes the row without adding one; `DeleteUser` removes only that person |
| | `TPhoneTests` | Schema seeds Cell/Work/Home; `AddPhone` returns an id; `QueryPhones` returns only the selected person's numbers; `EditPhone`; `DeletePhone`; **deleting a user deletes their phones** (the cascade bug) |

Total: 22 tests.

### How the database tests are built

`TDatabaseTestCase` in [tests/databasetests.pas](./tests/databasetests.pas) is a base class that `TPeopleTests` and `TPhoneTests` inherit from. FPCUnit runs `SetUp` before **every** test and `TearDown` after it, so each test starts from a clean state:

| Step | What happens |
|---|---|
| `SetUp` | Picks a temp file name (`hellocontacts_test_<processid>.db` in the Windows temp folder), creates a connection, transaction, and query, calls `Utils.EnableForeignKeys`, connects, and runs every line of the real [schema file](./resources/helloContacts-SCHEMA.sql) (found at `..\resources\` relative to the test exe) |
| *the test* | Calls a `Utils` routine through `FQuery`, then verifies the result with the helpers below |
| `TearDown` | Frees the objects and deletes the temp database file |

Helpers available to every database test:
- `FQuery`: the query object passed to `Utils` routines, matching how the app passes `DataModule1.QueryInsert`.
- `ScalarInt(sql)` and `ScalarStr(sql)`: run a one-value `SELECT` and return it, so tests can check what really landed in the tables.

Because every test gets a brand-new database built from the real schema, tests cannot affect each other, run in any order, and never touch your real contacts file in `%LOCALAPPDATA%\hellocontacts`. A schema change is also tested automatically, since the tests load the same `.sql` file the app embeds.

### Running the tests

From the project folder:

```
lazbuild tests\hellocontacts_tests.lpi
.\tests\hellocontacts_tests.exe --all --format=plain
```

Or in VS Code, run the **Test** task (Terminal → Run Test Task, or Terminal → Run Task → Test). It builds the test project and runs it.

The runner exits with code **0** when every test passes and **1** if any fails, so it works in scripts and CI. Useful runner options: `--all` (run everything), `--suite=TPhoneTests` (one class), `--format=plain|xml|latex`, `--help`.

Example of a failing run (this is what the cascade bug looked like):

```
TPhoneTests Time:00.205 N:6 E:0 F:1 I:0
  00.036  DeleteUserDeletesTheirPhones  Failed: "phones left behind" expected: <0> but was: <2>
```

### Adding a test

1. **To an existing class:** add a procedure under `published` and implement it using `AssertEquals`, `AssertTrue`, and the other `Assert*` methods from `fpcunit`.
2. **Database test:** inherit from `TDatabaseTestCase` and use `FQuery`, `ScalarInt`, and `ScalarStr`.
3. **New test unit:** create a unit with a `TTestCase` descendant, call `RegisterTest(YourClass)` in `initialization`, add the unit to the `uses` clause of [tests/hellocontacts_tests.lpr](./tests/hellocontacts_tests.lpr), and add it to the `.lpi` if you use the Lazarus IDE.
4. **Name tests for behavior** (`DeleteUserDeletesTheirPhones`, not `Test5`), so a failure message explains the problem by itself.

### Automated checks (pre-commit hook and CI)

Tests only help if they actually run. Two layers make that automatic:

| Layer | When it runs | What it does | Can it be bypassed? |
|---|---|---|---|
| **Pre-commit hook** ([.githooks/pre-commit](./.githooks/pre-commit)) | On your machine, at `git commit` | Builds and runs the tests; **aborts the commit** if any test fails | Yes: `git commit --no-verify` |
| **GitHub Actions CI** ([.github/workflows/ci.yml](./.github/workflows/ci.yml)) | On GitHub, for every push to `main`/`master` and every pull request | Installs Lazarus on a clean Windows machine, runs the tests, builds the app | No: the result is recorded on the commit or pull request |

The hook gives fast feedback before a bad commit exists. CI is the safety net, because it runs on a clean machine (catching "works on my machine" problems) and cannot be skipped by accident.

#### Local pre-commit hook

Git does not copy hooks when you clone, so the hook lives in the repo in [.githooks/](./.githooks) and each clone must switch it on **once**:

```
git config core.hooksPath .githooks
```

(This is already set in your current clone.)

How it works:
1. `git commit` runs [.githooks/pre-commit](./.githooks/pre-commit) first.
2. If none of the staged files are `.pas`, `.lpr`, `.lpi`, `.lfm`, `.sql`, or `.rc`, it skips the tests (so doc-only commits stay fast).
3. Otherwise it runs [scripts/run-tests.ps1](./scripts/run-tests.ps1), which finds `lazbuild` (on PATH, or `C:\lazarus`), builds [tests/hellocontacts_tests.lpi](./tests/hellocontacts_tests.lpi), and runs the test exe.
4. A non-zero exit code aborts the commit, and the failing test is printed.

I verified it by temporarily breaking `ValidatePhone`: `git commit` printed `TValidatePhoneTests.NineDigitsIsRejected` as a failure, then `tests failed, commit aborted.`, and no commit was created.

Notes:
- The hook only tests what you have in your working folder, not strictly what is staged.
- It takes a few seconds, because it compiles first.
- Use `git commit --no-verify` only for an emergency or work-in-progress commit. CI will still run.
- `scripts/run-tests.ps1` can also be run by hand: `powershell -File scripts\run-tests.ps1`.

#### GitHub Actions CI

[.github/workflows/ci.yml](./.github/workflows/ci.yml) defines one job on `windows-latest`:

1. Check out the code.
2. Install Lazarus with Chocolatey (`choco install lazarus`) and put `C:\lazarus` on PATH.
3. Download the official SQLite DLL into `tests/`, since the runner has no `sqlite3.dll` of its own.
4. Run `scripts/run-tests.ps1` (build and run the tests).
5. Build the application with `lazbuild hellocontacts.lpi`.

View results on GitHub under the repository's **Actions** tab, or as a check mark or red X next to each commit and pull request.

**Status:** the first run on `master` passed (all steps green, about 3 minutes). If a later run fails, open it in the Actions tab and read the failing step's log. The Lazarus install and the SQLite download URL are the steps most likely to break if an upstream package or link changes.

#### Making it enforce quality

- **Block merging on failure:** in GitHub, go to Settings → Branches → add a branch protection rule for `main`/`master` and require the **test** check to pass before merging. Without this, CI reports failures but does not stop anyone.
- **Developer workflow:** commit locally (hook runs) → push (CI runs) → fix anything red before merging.

### Limits and notes

- **Not covered:** the forms ([unit1.pas](./unit1.pas), [unitaddcontact.pas](./unitaddcontact.pas), [unitaddphone.pas](./unitaddphone.pas)) and `UnitData`'s startup logic. Only `Utils` and database behavior are tested. Moving logic out of the forms and into `Utils` makes more of the app testable.
- **SQLite DLL:** the database tests need `sqlite3.dll` to be findable, just like the app.
- **Windows temp folder:** if a test run is killed mid-way, a leftover `hellocontacts_test_*.db` file may remain in `%TEMP%`. It is safe to delete.
- **Existing data:** tests never change your real database, so the cascade fix does not clean up orphans already there.

## CI/CD pipeline: architecture and setup

### Architecture

**CI (Continuous Integration)** means every change is automatically built and tested, on a clean machine, as soon as it is shared. **CD (Continuous Delivery/Deployment)** means a change that passes is automatically packaged, and optionally released. This project has **CI and a tag-driven release workflow** (CD in the "continuous delivery" sense: a tagged version is tested, built, packaged, checksummed and published automatically; nothing is deployed to users' machines).

```
  Developer machine                              GitHub (remote)
 ┌────────────────────────────────┐        ┌──────────────────────────────────────┐
 │ edit code in VS Code / Lazarus │        │                                      │
 │            │                   │        │  GitHub Actions runner (Windows)     │
 │            ▼                   │        │   1. checkout                        │
 │  git commit                    │  git   │   2. install Lazarus                 │
 │   └─ pre-commit hook  ◄──┐     │  push  │   3. get sqlite3.dll                 │
 │       run-tests.ps1      │     │ ─────► │   4. run-tests.ps1  (FPCUnit)        │
 │       tests fail? ──► commit │  │        │   5. lazbuild  (build the app)       │
 │                       blocked │  │        │            │                         │
 │       tests pass ─────────────┘  │        │            ▼                         │
 │            │                   │        │   green check / red X on the commit  │
 │            ▼                   │        │            │                         │
 │       commit created           │        │            ▼                         │
 └────────────────────────────────┘        │   branch protection: merge allowed   │
        LAYER 1: fast, local                │   only if green   (LAYER 2: gate)    │
                                            │            │                         │
                                            │            ▼   (on a v* tag)         │
                                            │   release.yml: test, build, zip,     │
                                            │   SHA-256, attestation, GitHub release│
                                            └──────────────────────────────────────┘
```

| Stage | Where | Tool | Status |
|---|---|---|---|
| Write and run locally | Your PC | VS Code tasks / Lazarus | Done |
| Pre-commit check | Your PC | [.githooks/pre-commit](./.githooks/pre-commit) → [scripts/run-tests.ps1](./scripts/run-tests.ps1) | Done (verified) |
| Source control | GitHub | Git | Done |
| Build and test on a clean machine | GitHub | [.github/workflows/ci.yml](./.github/workflows/ci.yml) | Done: passes on good code, fails on bad (validated), uploads `test-results.xml` |
| Merge gate | GitHub | Branch protection on `master` (`test` required, applies to admins) | Done and validated: direct push rejected, red PR cannot merge |
| Package and release the exe | GitHub | [.github/workflows/release.yml](./.github/workflows/release.yml) | Done: `v0.1.0` published with checksum and attestation (verified) |

Design choices:
- **One script, two callers.** [scripts/run-tests.ps1](./scripts/run-tests.ps1) is used by both the hook and CI, so "passes locally" and "passes in CI" mean the same thing.
- **Hook for speed, CI for trust.** The hook catches mistakes in seconds, but anyone can skip it with `--no-verify` or may not have enabled it. CI cannot be skipped.
- **A clean machine is the point.** CI installs everything from scratch, so it exposes hidden dependencies (such as the SQLite DLL) that happen to exist on your PC.
- **The tests are the contract.** The pipeline is only as good as the tests it runs; see [Why tests matter here](#why-tests-matter-here).

### Setup steps

Everything below is already done for this repository, except where marked. Follow these steps to set it up in a new clone, or to recreate it in another project.

**1. Prerequisites**
- Git, Lazarus (with `lazbuild`), and a GitHub repository for the project.
- The [`gh` CLI](https://cli.github.com/) is optional but handy for checking runs.

**2. Test project**
- Create the FPCUnit project in [tests/](./tests) as described in [Framework and layout](#framework-and-layout).
- Confirm it passes: `lazbuild tests\hellocontacts_tests.lpi` then `.\tests\hellocontacts_tests.exe --all --format=plain`.

**3. Test script**
- Keep [scripts/run-tests.ps1](./scripts/run-tests.ps1). It must return exit code 0 on success and non-zero on failure. That exit code is what the hook and CI both read.

**4. Pre-commit hook** (once per clone)
```
git config core.hooksPath .githooks
```
Check it with `git config core.hooksPath` (should print `.githooks`).

**5. CI workflow**
- Keep [.github/workflows/ci.yml](./.github/workflows/ci.yml) in the repository, on the default branch.
- Commit and push:
  ```
  git add .githooks scripts .github
  git commit -m "Add CI pipeline"
  git push
  ```

**6. Watch the first run**
- Open the repository on GitHub → **Actions** tab → the **CI** run, or use `gh run list` and `gh run view --log-failed`.
- Expect to adjust the workflow on the first run. The Lazarus install step and the SQLite download are the most likely to need a tweak. Read the failing step's log, fix [.github/workflows/ci.yml](./.github/workflows/ci.yml), and push again until it is green.

**7. Require passing checks before merging** (done through the `gh` CLI; the same can be set in Settings → Branches)

```powershell
@'
{
  "required_status_checks": { "strict": true, "contexts": ["test"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 0, "require_code_owner_reviews": false },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
'@ | gh api -X PUT repos/elderdo/PascalSqliteContactsGUI/branches/master/protection --input -
```

- **`contexts: ["test"]`** is the job name in `ci.yml`; the check must be green to merge. **`strict`** also requires the branch to be up to date.
- **`enforce_admins: true`** means the owner is bound too, so even I use pull requests.
- Approvals are set to 0 because a solo maintainer cannot approve their own pull request. With a team, set `required_approving_review_count` to 1 and `require_code_owner_reviews` to true so [CODEOWNERS](./.github/CODEOWNERS) is enforced.
- Without this step, CI only reports problems; it does not stop anyone.

**8. Verify the whole chain**
- Locally: break a test on purpose, stage it, run `git commit`; it should be aborted. Restore the code.
- On GitHub: open a pull request with a deliberately failing test; the check should turn red and block the merge (done, see below).

**9. Releases (CD)**
[release.yml](./.github/workflows/release.yml) runs when a `v*` tag is pushed: it runs the tests, does a full rebuild, zips `hellocontacts.exe` with `sqlite3.dll`, writes a SHA-256 file, records a build attestation, and publishes a GitHub release. The version comes from the tag, so every released exe maps to an exact commit.

```powershell
git tag -a v0.2.0 -m "v0.2.0: what changed"
git push origin v0.2.0
gh release view v0.2.0 -R elderdo/PascalSqliteContactsGUI
```

To check a downloaded release:

```powershell
gh release download v0.2.0 -R elderdo/PascalSqliteContactsGUI
Get-FileHash .\hellocontacts-v0.2.0-win64.zip -Algorithm SHA256     # compare with the .sha256 file
gh attestation verify .\hellocontacts-v0.2.0-win64.zip --repo elderdo/PascalSqliteContactsGUI   # exit code 0 = verified
```

### Validating the pipeline

A pipeline that has never been seen to fail proves nothing. A check that always passes looks identical to a check that works, so it has to be shown to **fail when it should**, not only to pass. Each layer was validated like this:

| # | Check | How it was done | Result |
|---|---|---|---|
| 1 | Tests pass on clean code | Ran `scripts\run-tests.ps1` directly | 22 tests, 0 failures, exit code 0 |
| 2 | Hook stays out of the way for non-code changes | Ran the hook with no `.pas`/`.lpi`/`.sql` files staged | Printed "no Pascal/schema changes staged, skipping tests", exit 0 |
| 3 | **Hook blocks a bad commit** | Temporarily changed `ValidatePhone` (`<= 999999999` to `<= 99999999`), staged it, ran a real `git commit` | `TValidatePhoneTests.NineDigitsIsRejected` failed, "tests failed, commit aborted", exit 1, **no commit created** |
| 4 | Working tree restored after the failure test | Restored `utils.pas`, ran `git status` and re-ran the tests | No leftover changes; 22 tests, 0 failures |
| 5 | CI runs from a clean checkout | Committed, pushed to `master`, watched the run with `gh run watch -R elderdo/PascalSqliteContactsGUI` | **Passed** (run 37831780687, about 3 minutes): checkout, Lazarus install, SQLite download, unit tests, and app build all succeeded |

Check 3 is the one that matters most. It proves the hook can actually stop a commit, and that the failing test is named so the cause is obvious.

**Validated after the first pass:**
- **Branch protection** (2026-10-08). A direct `git push origin master` was rejected: `Required status check "test" is expected ... protected branch hook declined`. A deliberately broken pull request went red, and `gh pr merge` refused: `the base branch policy prohibits the merge` (merge state `BLOCKED`). A good pull request (#2) merged normally. Not tried: whether the `--admin` override works; with `enforce_admins` on it should not, but that is unconfirmed.
- **Release workflow.** Tagging `v0.1.0` ran the tests, built, packaged and published the release. The downloaded zip's SHA-256 matched the `.sha256` file, `gh attestation verify` exited 0, and the zip held `hellocontacts.exe`, `sqlite3.dll`, `README.md` and `CODE_GUIDE.md`. The exe was **not** launched from the zip; do that on a clean machine before a real release.
- **CI failure path.** A deliberately broken pull request turned CI red and the revert turned it green (see "Worked example: CI failure on a pull request"). Only the failing-test case was exercised in CI; a failing download or install step was not.
- **Test evidence.** The `test-results` artifact is uploaded on every run (881 bytes, with run counts, failures and timings).

**Not yet validated:**
- **Fresh clone.** Clone the repository into a new folder, run `git config core.hooksPath .githooks`, and make a commit, to prove the setup steps work for someone who is not you.
- **Dependabot updates.** It has opened pull requests for newer action versions; each should go through the same CI before merging. The release workflow only runs on a tag, so a bump to its actions is not tested until the next release.

**Problem found while validating:** `gh` was pointed at a different repository (`SteveSchilz/PascalHelloLazarusDatabase`, the original project this one derives from) and returned a 404. Pass the repository explicitly, for example `gh run list -R elderdo/PascalSqliteContactsGUI`, or set it once with `gh repo set-default elderdo/PascalSqliteContactsGUI`. A tool pointed at the wrong repository can look like "CI is not running" when the real problem is the target.

#### Commands used, step by step

Run these from the project root in PowerShell. Each step says what it does and what you should see.

**1. Green path: run the tests directly**

```powershell
powershell -NoProfile -File scripts\run-tests.ps1
$LASTEXITCODE
```

The script builds the test project with `lazbuild`, runs it, and passes on the test runner's exit code. Expect the plain-text test report ending with no failures, and `0` from `$LASTEXITCODE`. Any non-zero value means at least one failure.

**2. Skip path: run the hook with nothing relevant staged**

```powershell
git status --short
& "C:\Program Files\Git\bin\sh.exe" .githooks/pre-commit
$LASTEXITCODE
```

Git runs the hook through its bundled `sh`, so calling it the same way tests the real thing. With no `.pas`, `.lpr`, `.lpi`, `.lfm`, `.sql` or `.rc` files staged, expect "no Pascal/schema changes staged, skipping tests" and `0`.

**3. Red path: break the code on purpose and try to commit**

Open [utils.pas](./utils.pas), find `ValidatePhone`, and change the upper limit from `999999999` to `99999999` (one fewer 9). Then:

```powershell
git add utils.pas
git commit -m "temporary: deliberately broken, should be blocked"
$LASTEXITCODE
git log --oneline -1
```

Expect the hook to run the tests, `TValidatePhoneTests.NineDigitsIsRejected` to fail, the message "tests failed, commit aborted", and a non-zero exit code. `git log` should still show your previous commit, which proves nothing was committed.

**4. Clean up: undo the deliberate break**

```powershell
git reset
git checkout -- utils.pas
git status --short
powershell -NoProfile -File scripts\run-tests.ps1
```

`git reset` unstages the file, and `git checkout -- utils.pas` discards the edit (if you had other uncommitted changes in that file, undo the one-line edit by hand instead). `git status` should show nothing left over, and the tests should pass again.

**5. CI path: push and watch the GitHub run**

```powershell
git push
gh run list -R elderdo/PascalSqliteContactsGUI --limit 3
gh run watch <run-id> -R elderdo/PascalSqliteContactsGUI
gh run view <run-id> -R elderdo/PascalSqliteContactsGUI
```

`gh run list` shows the newest runs and their ids, `gh run watch` follows one live, and `gh run view` lists each step with a tick or cross. If a step fails, add `--log-failed` to `gh run view` to print only the failing log. The `-R` option is needed because `gh` otherwise targets the wrong repository (see above).

**6. Optional: check the SQLite download link CI depends on**

```powershell
curl.exe -I https://www.sqlite.org/2024/sqlite-dll-win-x64-3450100.zip
```

Expect `HTTP/1.1 200 OK`. A 404 here means the CI download step will fail.

**7. Optional: prove CI turns red**

```powershell
git switch -c ci-red-test
# make the same deliberate break as in step 3, then:
git commit -am "temporary: prove CI fails" --no-verify
git push -u origin ci-red-test
gh pr create -R elderdo/PascalSqliteContactsGUI --title "Temporary: CI should fail" --body "Do not merge"
gh pr checks -R elderdo/PascalSqliteContactsGUI
```

`--no-verify` skips the local hook so the bad commit reaches GitHub and CI gets a chance to catch it. Expect the check to fail. When done, close the pull request and delete the branch:

```powershell
gh pr close ci-red-test -R elderdo/PascalSqliteContactsGUI --delete-branch
git switch master
```

#### How to repeat the validation

Do this after any change to the hook, the script, the workflow, or the tests:

1. **Green path:** `powershell -File scripts\run-tests.ps1`, then check that the exit code is 0 (`$LASTEXITCODE`).
2. **Red path (local):** break a line of code the tests cover, stage it, and run `git commit`. Confirm the commit is aborted and the right test fails. Restore the code afterwards and confirm with `git status`.
3. **Red path (CI):** push a branch with a deliberately failing test and confirm the check is red. Use `gh run view --log-failed -R elderdo/PascalSqliteContactsGUI` to read why.
4. **Green path (CI):** fix it and confirm the check turns green.
5. **Clean up:** remove the broken branch and make sure no temporary edits remain.

#### Why validating the pipeline is important

- **A silent pipeline is worse than none.** If a check never runs, runs the wrong thing, or ignores its exit code, everyone believes the code is protected when it is not. The false confidence is the danger.
- **The failure path is the whole purpose.** A pipeline exists to stop bad changes. Only deliberately feeding it a bad change shows that it does.
- **Pipelines have bugs too.** Typical ones are a script that returns 0 even when tests fail, a hook that was never enabled (`core.hooksPath` unset), a workflow that never triggers on the branch you use, or a tool aimed at the wrong repository, as happened here.
- **Environment differences show up late.** CI starts from nothing, so a missing DLL, a missing install step, or a hard-coded path appears only there. Better to find it now than during a release.
- **It builds trust.** When a check turns red later, the team will act on it, because it has been seen to catch real problems.
- **Do it again after changes.** Every edit to the hook, the script, or the workflow can break the safety net without anyone noticing, so repeat the red and green checks above.

### Troubleshooting: failures, how to force them, and how to fix them

Seeing a failure on purpose, while you are calm and know the cause, is the best way to learn to read one at 5 pm on a release day. The first two cases below, and the CI worked example, were run for this guide and the output is real (trimmed). The rest are described from how the tools behave and were **not** all reproduced; where output is shown as "expect", treat it as a guide.

#### Good vs bad output at a glance

| Layer | Good | Bad |
|---|---|---|
| `scripts\run-tests.ps1` | `Number of failures:  0`, exit code `0` | `Number of failures:  1` and a "List of failures", exit code `1` |
| Pre-commit hook | Commit goes through, or "skipping tests" | `pre-commit: tests failed, commit aborted.`, no commit created |
| GitHub Actions | Green tick on every step | Red cross on the failing step; later steps are skipped |

**Good run (real output):**

```text
Number of run tests: 22
Number of errors:    0
Number of failures:  0
```
Exit code: `0`.

**Failing test (real output, forced by changing `<= 999999999` to `<= 99999999` in `ValidatePhone`):**

```text
Number of run tests: 22
Number of errors:    0
Number of failures:  1

List of failures:
  Failure:
    Message:           TValidatePhoneTests.NineDigitsIsRejected:  expected: <-1> but was: <999999999>
    Exception class:   EAssertionFailedError
        at ... NineDigitsIsRejected,  line 94 of utilstests.pas
```
Exit code: `1`. Through the hook the same text appears, followed by `pre-commit: tests failed, commit aborted.` and `git log` is unchanged.

**How to read it:**
- `TValidatePhoneTests.NineDigitsIsRejected` is *class.test*, so open `tests\utilstests.pas` at the line shown (94).
- `expected: <-1> but was: <999999999>` means the test expected the code to reject the number (`-1`) but it was accepted.
- `Failure` means an assertion was wrong. `Errors` (a separate count) means the test crashed with an exception, such as a missing DLL or a database error. Start with errors, because they often hide the real problem.
- Decide which side is wrong, the code or the test. If the code is wrong, fix it. If the requirement changed, update the test deliberately and say so in the commit message.

#### Failure catalogue

| # | Symptom | Likely cause | How to debug | Fix |
|---|---|---|---|---|
| 1 | `Number of failures: N` | Code or test is wrong | Read the "List of failures" block; open the named test and line | Fix the code, or update the test if the rule truly changed |
| 2 | `Number of errors: N` on the database tests, message mentions `sqlite3` or "could not load library" | `sqlite3.dll` not found. Locally it must be on `PATH` or in `tests\`; CI downloads it | `where.exe sqlite3.dll` (empty means missing) | Copy a 64-bit `sqlite3.dll` into `tests\` (it is git-ignored). Check that CI's download step is green |
| 3 | Build fails: "Fatal: Can't find unit ..." or "Error: Identifier not found" | A unit was renamed, a package is missing from the test `.lpi`, or `Interfaces` is missing from the test `.lpr` | Run `lazbuild tests\hellocontacts_tests.lpi` by itself and read the first error | Add the unit or package, or fix the path. The test project compiles `utils.pas` through `OtherUnitFiles=..` |
| 4 | `lazbuild is not recognized` or the script says it cannot find lazbuild | Lazarus is not installed or not on `PATH` | `where.exe lazbuild`; check `C:\lazarus\lazbuild.exe` exists | Install Lazarus, or add `C:\lazarus` to `PATH` |
| 5 | Commit goes through with no test run at all | The hook is not enabled in this clone | `git config core.hooksPath` (should print `.githooks`) | `git config core.hooksPath .githooks`. Git never copies hooks when cloning |
| 6 | Hook says "skipping tests" when you did change code | Only non-code files are staged (the hook looks at `.pas`, `.lpr`, `.lpi`, `.lfm`, `.sql`, `.rc`) | `git diff --cached --name-only` | Stage the code files too, or add the missing extension to the hook |
| 7 | Hook blocks a commit and you must commit anyway (for example, to push a work-in-progress branch) | Failing test | Fix it first if you can | `git commit --no-verify` skips the hook. CI still runs, so a bad commit will turn the PR red |
| 8 | Hook passes locally but CI is red | Something on your machine hides a problem: a file that exists only locally, an uncommitted change (the hook tests the working tree, not the staged snapshot), or a different Lazarus version | Compare `git status` with what was pushed; read the failing CI step | Commit the missing file; `git stash` unrelated edits and re-run the tests |
| 9 | CI step "Install Lazarus" fails | The Chocolatey package or mirror was unavailable, or the version changed | `gh run view <id> -R elderdo/PascalSqliteContactsGUI --log-failed` | Re-run the job (`gh run rerun <id> --failed -R ...`); if it keeps failing, pin a version in `ci.yml` |
| 10 | CI step "Download SQLite DLL" fails | The URL changed or returned 404 | `curl.exe -I https://www.sqlite.org/2024/sqlite-dll-win-x64-3450100.zip` | Find the current link on sqlite.org/download.html and update `ci.yml` |
| 11 | CI never starts after a push | The branch is not in the `on:` list, the workflow file is invalid YAML, or Actions is disabled | `gh workflow list -R elderdo/PascalSqliteContactsGUI`; check the repo's Actions tab for a YAML error | Fix the YAML or branch filter; enable Actions in the repository settings |
| 12 | `gh` gives 404 or shows the wrong repository's runs | `gh` is pointed at the upstream repository | `gh repo view` shows which repo it is using | Add `-R elderdo/PascalSqliteContactsGUI`, or `gh repo set-default elderdo/PascalSqliteContactsGUI` |
| 13 | A red check but the merge button still works | Branch protection is not turned on | Repository Settings, Branches | Add a rule requiring the `test` check to pass before merging |

#### Forcing failures on purpose

Always do this on a throwaway branch or restore the file afterwards, and never leave a deliberate break on `master`.

**A. Force a failing test (cases 1 and 7).** This is the one run for this guide:

```powershell
(Get-Content utils.pas -Raw).Replace('<= 999999999','<= 99999999') | Set-Content utils.pas -NoNewline
powershell -NoProfile -File scripts\run-tests.ps1   # expect exit code 1
git add utils.pas
git commit -m "tmp"                                  # expect: commit aborted
git reset; git checkout -- utils.pas                 # undo
```

**B. Force the hook to be skipped (case 5).** Show what a missing hook looks like, then restore it:

```powershell
git config core.hooksPath ""            # hook disabled; the next commit runs no tests
git config core.hooksPath .githooks     # re-enable
```

**C. Force a compile error (case 3).** Add a deliberate typo, such as `xyz;` on its own line in `utils.pas`, then run `scripts\run-tests.ps1`. Expect an `Error:` line from the compiler with the file and line number, no test report, and a non-zero exit code. Remove the line afterwards.

**D. Force a missing DLL (case 2).** Temporarily rename the DLL where Windows finds it (for example `tests\sqlite3.dll`) and run the tests. Expect the database tests to report errors rather than failures while the pure-logic tests still pass. Rename it back.

**E. Force CI to fail (cases 8 to 10).** Done for real, see "Worked example: CI failure on a pull request" below. To rehearse a bad download, change the SQLite URL in `ci.yml` on a throwaway branch to one with a typo, open a pull request, and read the log with `gh run view <id> --log-failed`. Expect the "Download SQLite DLL" step to turn red and the later steps to be skipped (not yet run).

**F. Force a blocked merge (case 13).** Done for real: with branch protection on, open a pull request from a broken branch, wait for red, then run `gh pr merge <n> -R elderdo/PascalSqliteContactsGUI --squash`. Result: `Pull request ... is not mergeable: the base branch policy prohibits the merge.` On the web page the merge button is disabled with "Required statuses must pass". Also try `git push origin master` directly: `protected branch hook declined`.

#### Worked example: CI failure on a pull request, and the fix (real run)

This is the exercise from "Forcing failures", case E, carried out for real on 2026-10-08.

**1. Break it on a throwaway branch and push it (the local hook is skipped on purpose, so CI is the only gate):**

```powershell
git switch -c ci-red-test
# change '<= 999999999' to '<= 99999999' in ValidatePhone (utils.pas)
git commit --no-verify -am "TEMP: deliberately break ValidatePhone to prove CI fails"
git push -u origin ci-red-test
gh pr create -R elderdo/PascalSqliteContactsGUI --base master --head ci-red-test --title "TEMP: CI should fail (do not merge)" --body "Deliberate failure"
```

The workflow only triggers on pushes to `main`/`master` and on pull requests, so the pull request is what starts CI for this branch. Pushing the branch alone does nothing.

**2. Watch it fail:**

```powershell
gh run list -R elderdo/PascalSqliteContactsGUI --branch ci-red-test --limit 1
gh run watch <run-id> -R elderdo/PascalSqliteContactsGUI --exit-status
```

Real result (about 2m51s):

```text
X test in 2m51s
  ✓ Set up job
  ✓ Run actions/checkout@v4
  ✓ Install Lazarus
  ✓ Download SQLite DLL
  X Build and run unit tests
  - Build application            <- skipped, because an earlier step failed
  ✓ Post Run actions/checkout@v4
X Process completed with exit code 1.
```

`--exit-status` makes `gh run watch` return a non-zero exit code when the run fails, which is handy in scripts. Steps before the red one are fine; the `-` step was skipped. That tells you which stage broke before you read any log.

**3. Read why:**

```powershell
gh run view <run-id> -R elderdo/PascalSqliteContactsGUI --log-failed
gh pr checks <pr-number> -R elderdo/PascalSqliteContactsGUI
```

The failed-step log contains exactly what you saw locally:

```text
NineDigitsIsRejected  Failed:  expected: <-1> but was: <999999999>
  at ... NineDigitsIsRejected,  line 94 of utilstests.pas
Number of run tests: 22
Number of errors:    0
Number of failures:  1
##[error]Process completed with exit code 1.
```

`gh pr checks` shows `test  fail  2m51s` with a link to the run. The same failure appears as a red cross on the pull request page on GitHub.

**4. Fix it.** Here the cause was the deliberate break, so the fix was to undo it. A revert keeps the history honest, and CI re-runs on the new push:

```powershell
git revert --no-edit HEAD
git push
gh run watch <run-id> -R elderdo/PascalSqliteContactsGUI --exit-status
gh pr checks <pr-number> -R elderdo/PascalSqliteContactsGUI
```

Real result: every step green (`✓ test in 2m55s`) and `gh pr checks` printed `test  pass  2m55s`. For a genuine bug the fix is the same loop: read the failing test, reproduce it locally with `scripts\run-tests.ps1`, fix the code, push, and wait for green.

**5. Clean up:**

```powershell
gh pr close <pr-number> -R elderdo/PascalSqliteContactsGUI --delete-branch
git switch master
git branch -D ci-red-test
```

Nothing from the exercise was merged, so `master` was untouched.

**What this proved:**
- CI really fails when a test fails (a gate that cannot fail would be worthless).
- It fails on the right step, with a log that names the test and line.
- The failure is visible from the command line and on the pull request.
- Fixing the code turns it green again, so a green check can be trusted.

**Merge blocking: now proven.** Branch protection was turned on and a red pull request could not be merged (`the base branch policy prohibits the merge`); see "Validated after the first pass" above.

#### A debugging routine that works for every case

1. **Find the first failure**, not the last. Later errors are usually fallout.
2. **Reproduce locally.** `scripts\run-tests.ps1` runs the same thing CI does.
3. **Read the whole message** and note the file and line.
4. **Change one thing, re-run, and check the exit code.**
5. **If it only fails in CI**, compare environments: tool versions, files that are git-ignored (DLLs, `lib\`), and paths.
6. **After fixing, make sure the test would have caught it.** If the bug had no test, write one first (see "Adding a test").

### Why a production app needs tests *and* a pipeline

Neither is enough alone:

| | Tests only | Pipeline only | Tests + pipeline |
|---|---|---|---|
| Runs automatically | No, depends on someone remembering | Yes | Yes |
| Checks anything meaningful | Yes | No: it only proves the code compiles | Yes |
| Catches "works on my machine" | No | Partly | Yes |
| Blocks bad changes from reaching users | No | Only if there are tests | Yes |

Why it matters once real users depend on the app:
- **Data is the product.** This app stores people's contacts. The cascade bug described in [Why tests matter here](#why-tests-matter-here) silently left orphaned rows behind, with no error. In a production app that kind of silent data corruption is what loses user trust, and only a test against the real database found it.
- **Every change is a risk.** The more the app grows, the more likely a fix in one place breaks another. A fast automated suite lets you change code confidently instead of fearfully.
- **Humans forget; pipelines don't.** A rule such as "run the tests before releasing" fails the first busy day. A pipeline runs on every change, including at 2 a.m. and on someone else's laptop.
- **Releases become repeatable.** A release built by CI from a tagged commit is identical every time. A release built by hand on one PC depends on that PC's state and the person's memory.
- **Bugs are cheaper earlier.** A failure at commit time costs seconds; in CI, minutes; after release, user-visible damage, support time, and often a data cleanup that code cannot fix (the orphaned rows already in a database are not removed by the code fix).
- **Regressions stay fixed.** A bug fix that comes with a test can never silently return.
- **It documents behavior.** The tests state precisely what the app promises (for example, "deleting a contact deletes their phone numbers").

In short: **the tests define what "working" means, and the pipeline makes sure no change ships unless it still meets that definition.** For a production application, that combination is the minimum bar for changing code safely and releasing it with confidence.

### Governance, evidence and releases

The pipeline above is extended with change-control and evidence practices, documented separately:

- **Test evidence:** each CI run uploads `test-results.xml` (the **test-results** artifact, kept 90 days).
- **Releases:** pushing a tag such as `v0.1.0` runs [release.yml](./.github/workflows/release.yml): tests, a full rebuild, a zip with a SHA-256 file, a build attestation, then a GitHub release.
- **Change control:** [pull request template](./.github/PULL_REQUEST_TEMPLATE.md), [code owners](./.github/CODEOWNERS), and protected `master`.
- **Traceability:** [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md). **Compliance gaps:** [docs/COMPLIANCE.md](./docs/COMPLIANCE.md). **AI use:** [docs/AI_WORKFLOW.md](./docs/AI_WORKFLOW.md). **Demo:** [docs/DEMO_SCRIPT.md](./docs/DEMO_SCRIPT.md).

## Known quirks and TODOs

- Both dialogs repeat the same edit-mode code. A TODO in [unitaddphone.pas](./unitaddphone.pas) suggests a shared base class.
- SQL for add/edit/delete is assembled with `QuotedStr` / `Format`. Parameterized queries would be safer.
- `Utils.ShowException` only logs to the debug console; the user sees no error dialog.
- The search filter in `ButtonSearchClick` inserts the typed text directly into the filter string.
- The `.lfm` files also set `Position` to center the forms. Stale off-screen `Left`/`Top` values in them are harmless because of `EnsureOnScreen`, but the Lazarus designer can still write odd values back.
- [unit1.pas](./unit1.pas) has hard-coded column indexes in `HideIds`; reordering the query columns will change which columns are hidden.
- The project depends on the `Windows` unit (resource loading), so it is Windows-only as written.

## Roadmap (to-do list)

Ordered by value. Items marked **Showcase** make the project stronger for a review; the rest improve the product. Each item should go through the normal flow: a requirement in [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md), a test first, a pull request, green CI.

### Next up

- [ ] **Parameterized SQL (Showcase).** Replace `QuotedStr` / `Format` string-building in [utils.pas](./utils.pas) with `TSQLQuery.Params`. Add tests that insert SQL metacharacters (for example `Robert'); DROP TABLE People;--`) and confirm the data is stored literally. Also fix the search filter in `ButtonSearchClick`.
- [ ] **Orphaned phone rows cleanup.** A one-time migration that deletes `PhoneNumbers` rows whose `PersonId` no longer exists, run at startup after foreign keys are enabled. Test it against a database seeded with orphans. Back up the file before changing it.
- [ ] **Show errors to the user.** `Utils.ShowException` only logs. Show a message and keep the log.
- [ ] **Merge the Dependabot PRs** one at a time (each must pass CI). The release workflow's action bumps are untested until the next tag; cut a test tag afterwards.
- [ ] **Fresh-clone check.** Clone into a new folder, follow the README quick start, and confirm the hook and tests work for someone else.
- [ ] **Launch the released exe** from the downloaded zip on a clean machine and add the result to [Validating the pipeline](#validating-the-pipeline).
- [ ] **Test the `--admin` merge override** with branch protection on, and record whether `enforce_admins` blocks it.

### Pipeline and quality

- [ ] **Code coverage report** published as a CI artifact (FPC supports `-Cc`/gcov-style tools; check what works with Lazarus on Windows).
- [ ] **Static analysis / warnings as errors** in the test and app builds.
- [ ] **GUI smoke test** (for example scripted launch and window-visible check) to close the REQ-013 to REQ-015 gaps in [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md).
- [ ] **Secret scanning and code scanning** enabled in repository settings.
- [ ] **Two-person review.** With a second maintainer, set required approvals to 1 and require code owner review so [CODEOWNERS](./.github/CODEOWNERS) is enforced.
- [ ] **Copilot coding agent** on labelled issues, gated by the same checks. It needs a setup workflow that installs Lazarus, so it can build and run `scripts\run-tests.ps1`.
- [ ] **AI-drafted release notes / PR summaries**, always reviewed by a human before publishing.

### Regulated-data readiness (see [docs/COMPLIANCE.md](./docs/COMPLIANCE.md))

- [ ] Audit trail (who, when, old and new value), user authentication, electronic signatures, encryption at rest, backup and retention.
- [ ] Validation plan, risk assessment, and IQ/OQ/PQ protocols using CI results as evidence.

### Refactoring: dependency injection (planned, not started)

**Why.** Today the forms call a global, `DataModule1` in [unitdata.pas](./unitdata.pas), directly: [unit1.pas](./unit1.pas), [unitaddcontact.pas](./unitaddcontact.pas) and [unitaddphone.pas](./unitaddphone.pas) all reference it, and [hellocontacts.lpr](./hellocontacts.lpr) creates it with `Application.CreateForm`. The forms are therefore coupled to SQLite and cannot be tested without a database. Putting interfaces between the UI and the data layer lets us test the logic with a fake, and lets a different database be added without touching the forms.

**Approach: a manual composition root, no DI framework.** Free Pascal interfaces plus plain constructors are enough, and this keeps the Lazarus Form Designer working. Form classes are created by `Application.CreateForm`, so they cannot take constructor arguments; use property or method injection (`InjectDependencies`) right after creation.

Planned steps, each one a small pull request with all tests green:

1. [ ] **Define contracts** in a new `unitinterfaces.pas`, for example `ILoggerService` and `IDatabaseService`, each with a GUID. Design the interface around what the forms actually need (people, phones, phone types) instead of exposing a raw dataset.
2. [ ] **Move database code** from `DataModule1` into a `TSQLiteDatabaseService` (`TInterfacedObject, IDatabaseService`) that takes the logger in its constructor. Keep the existing DB location (`GetAppConfigDir`, see [Database](#database)), `Utils.EnableForeignKeys`, and schema-creation behavior; do not switch to a path next to the exe.
3. [ ] **Add a composition root** (`TAppContainer`) that builds the logger and database service and is the only place that names concrete classes. Call it from `hellocontacts.lpr`.
4. [ ] **Inject into the forms** with `InjectDependencies(...)`, and replace each `DataModule1.` reference. Do this one form at a time and run the app after each, because the forms' data-aware grids are bound to `DataModule1` data sources in the `.lfm` files and need re-pointing.
5. [ ] **Remove the global** `DataModule1` once nothing references it.
6. [ ] **Add fakes and tests.** An in-memory fake `IDatabaseService` for form-logic tests, plus the existing real-SQLite tests run against the new service. Update [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md) and this guide.

**Things to get right** (the sketch this plan came from has gaps worth fixing first):
- Interface lifetime: `TInterfacedObject` is reference-counted, so do not mix object and interface references to the same instance, and keep `Container` alive for the whole run.
- Returning a live `TDataSet` from `GetPeopleDataSet` leaks the implementation (SQLDB) through the interface. Either accept that as a stepping stone for the data-aware grids, or return plain records or lists and bind the grids to a local dataset.
- Every placeholder needs a real implementation before use: there is no `TFileLogger` yet, and `ExecuteInsert` is an empty stub. Fix the sketch's typo `TTSQLiteDatabaseService` too.
- Use parameterized SQL in the new service (see "Next up"); do not copy the string-built pattern.
- Do not hard-code the database path as in the sketch (`ExtractFilePath(ParamStr(0))`); that would move users' data and break existing databases.

**Swapping databases.** A new database needs a new class that implements `IDatabaseService` and one changed line in the container. In practice also expect differences in SQL dialect, auto-increment, transactions, and driver setup, so a second implementation (for example Oracle through SQLDB) needs its own tests and is more than a one-line change. Do not claim it works until a second implementation has actually been built and tested.