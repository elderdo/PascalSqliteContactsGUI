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
- [Embedded resources](#embedded-resources)
- [Build and run](#build-and-run)
- [Known quirks and TODOs](#known-quirks-and-todos)

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

### Limits and notes

- **Not covered:** the forms ([unit1.pas](./unit1.pas), [unitaddcontact.pas](./unitaddcontact.pas), [unitaddphone.pas](./unitaddphone.pas)) and `UnitData`'s startup logic. Only `Utils` and database behavior are tested. Moving logic out of the forms and into `Utils` makes more of the app testable.
- **SQLite DLL:** the database tests need `sqlite3.dll` to be findable, just like the app.
- **Windows temp folder:** if a test run is killed mid-way, a leftover `hellocontacts_test_*.db` file may remain in `%TEMP%`. It is safe to delete.
- **Existing data:** tests never change your real database, so the cascade fix does not clean up orphans already there.

## Known quirks and TODOs

- Both dialogs repeat the same edit-mode code. A TODO in [unitaddphone.pas](./unitaddphone.pas) suggests a shared base class.
- SQL for add/edit/delete is assembled with `QuotedStr` / `Format`. Parameterized queries would be safer.
- `Utils.ShowException` only logs to the debug console; the user sees no error dialog.
- The search filter in `ButtonSearchClick` inserts the typed text directly into the filter string.
- The `.lfm` files also set `Position` to center the forms. Stale off-screen `Left`/`Top` values in them are harmless because of `EnsureOnScreen`, but the Lazarus designer can still write odd values back.
- [unit1.pas](./unit1.pas) has hard-coded column indexes in `HideIds`; reordering the query columns will change which columns are hidden.
- The project depends on the `Windows` unit (resource loading), so it is Windows-only as written.
