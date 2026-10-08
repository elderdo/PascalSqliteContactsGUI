# Code Guide: Hello Contacts

A Lazarus / Free Pascal desktop app (Windows) that manages contacts and their phone numbers in a local SQLite database. This guide describes how the code is organized and what each source file does, so the source itself can stay lightly commented.

- [Overview](#overview)
- [Project layout](#project-layout)
- [How the pieces fit together](#how-the-pieces-fit-together)
- [Startup sequence](#startup-sequence)
- [Source files](#source-files)
- [Database](#database)
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
| [.vscode/tasks.json](./.vscode/tasks.json) | VS Code build/run tasks |

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
| `FormShow`, `FormActivate` | Activate and refresh queries, hide ID columns, hide the phone panel |
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
- `FormShow`: sets the prompt and caption ("Add Contact" or "Edit Contact").
- `ButtonSaveClick`: requires at least one non-blank name. In edit mode it calls `Utils.EditUser`; otherwise `Utils.AddUser`. It then closes the dialog.
- `ButtonCancelClick`: closes the dialog.

The main form fills in `EditId`, `EditFirst`, and `EditLast` before showing it.

### [unitaddphone.pas](./unitaddphone.pas)

Class `TFrmAddPhone` (global `FrmAddPhone`), a modal dialog to create or edit a phone number. Layout is in [unitaddphone.lfm](./unitaddphone.lfm).

- `FormCreate` → `InitializeTypeDropDown`: fills the type combo box from `QueryPhoneType` and keeps a parallel array (`mPhoneTypeIds`) mapping each combo row to its database `Id`.
- `SetEditMode`, `SetPersonId`, `SetPhoneId`: set state before the dialog is shown.
- `SetPhoneTypeId`: selects the combo row matching a given phone-type `Id`.
- `FormShow`: sets the prompt and caption.
- `ButtonSaveClick`: validates the number with `Utils.ValidatePhone`, then calls `Utils.AddPhone` or `Utils.EditPhone`.

### [utils.pas](./utils.pas)

Helper routines in a unit with no form. Database functions take the query object as a parameter (the callers pass `DataModule1.QueryInsert`).

| Routine | Purpose |
|---|---|
| `SplitName` | Splits a string on spaces into exactly two entries (first, last); extra words are dropped |
| `ValidatePhone` | Returns the number as `Int64` if it is exactly 10 digits, else `-1` |
| `AddUser` / `EditUser` / `DeleteUser` | `INSERT` / `UPDATE` / `DELETE` on `People`; `AddUser` returns the new `Id` or `-1` |
| `QueryPhones` | Reloads the phone query for one person (joined to `PhoneTypes`) |
| `AddPhone` / `EditPhone` / `DeletePhone` | `INSERT` / `UPDATE` / `DELETE` on `PhoneNumbers` |
| `GetLastInsertID` | Runs `SELECT last_insert_rowid()` |
| `ShowException` | Writes the exception class and message to the debug log |

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

## Known quirks and TODOs

- Both dialogs repeat the same edit-mode code. A TODO in [unitaddphone.pas](./unitaddphone.pas) suggests a shared base class.
- SQL for add/edit/delete is assembled with `QuotedStr` / `Format`. Parameterized queries would be safer.
- `Utils.ShowException` only logs to the debug console; the user sees no error dialog.
- The search filter in `ButtonSearchClick` inserts the typed text directly into the filter string.
- The `.lfm` window positions are set to center on screen. Stale off-screen coordinates in these files can hide a window.
- [unit1.pas](./unit1.pas) has hard-coded column indexes in `HideIds`; reordering the query columns will change which columns are hidden.
- The project depends on the `Windows` unit (resource loading), so it is Windows-only as written.
