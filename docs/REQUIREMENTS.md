# Requirements and traceability

Each requirement maps to the automated tests that prove it. A requirement with no test is shown as a **gap** instead of being hidden. Update this file in the same pull request as any behavior change.

Test files: [tests/utilstests.pas](../tests/utilstests.pas), [tests/databasetests.pas](../tests/databasetests.pas). Code: [utils.pas](../utils.pas), [unitdata.pas](../unitdata.pas).

| ID | Requirement | Implemented in | Verified by | Status |
|---|---|---|---|---|
| REQ-001 | A person can be added and receives a unique ID | `Utils` SQL helpers | `TPeopleTests.AddUserReturnsNewId`, `AddUserStoresNames` | Automated |
| REQ-002 | Names containing an apostrophe are stored correctly | `Utils` SQL helpers | `TPeopleTests.AddUserHandlesApostrophe` | Automated |
| REQ-003 | A person's first and last name can be edited | `Utils` SQL helpers | `TPeopleTests.EditUserChangesNames` | Automated |
| REQ-004 | A person can be deleted | `Utils` SQL helpers | `TPeopleTests.DeleteUserRemovesRow` | Automated |
| REQ-005 | Deleting a person also deletes their phone numbers (no orphans) | `Utils.EnableForeignKeys`, schema `ON DELETE CASCADE` | `TPhoneTests.DeleteUserDeletesTheirPhones` | Automated (found a real bug, see below) |
| REQ-006 | A phone number can be added to a person | `Utils` SQL helpers | `TPhoneTests.AddPhoneReturnsNewId` | Automated |
| REQ-007 | Only the selected person's numbers are listed | `Utils` SQL helpers | `TPhoneTests.QueryPhonesReturnsOnlySelectedPerson` | Automated |
| REQ-008 | A phone number and its type can be edited | `Utils` SQL helpers | `TPhoneTests.EditPhoneChangesNumberAndType` | Automated |
| REQ-009 | A phone number can be deleted | `Utils` SQL helpers | `TPhoneTests.DeletePhoneRemovesRow` | Automated |
| REQ-010 | Phone types (Cell, Work, Home) exist from the schema | `resources\helloContacts-SCHEMA.sql` | `TPhoneTests.SchemaSeedsPhoneTypes` | Automated |
| REQ-011 | Phone numbers must be exactly 10 digits; formatted, short, long, empty or non-numeric input is rejected | `Utils.ValidatePhone` | `TValidatePhoneTests` (7 tests) | Automated |
| REQ-012 | A full name is split into first and last name; extra words are dropped | `Utils.SplitName` | `TSplitNameTests` (4 tests) | Automated |
| REQ-013 | The database file is created from the embedded schema on first run | `unitdata.EnsureDatabasePresent` | The schema is exercised by the database tests; the first-run file creation itself is not | **Gap**, manual check |
| REQ-014 | Windows always open on a visible monitor | `Utils.EnsureOnScreen` | None | **Gap**, manual check (GUI) |
| REQ-015 | The GUI behaves correctly (grids, dialogs, buttons) | `unit1`, `unitaddcontact`, `unitaddphone` | None | **Gap**, manual check (GUI) |

**Totals:** 22 automated tests cover 12 of 15 requirements. Three are gaps and need a manual check before each release (see [DEMO_SCRIPT.md](./DEMO_SCRIPT.md) for a quick smoke test).

## Case study: a test found a real defect

While writing REQ-005's test, `DeleteUserDeletesTheirPhones` failed. SQLite ignores `ON DELETE CASCADE` unless foreign keys are switched on for each connection, so deleting a person left their phone numbers behind. The fix is `Utils.EnableForeignKeys`, called before connecting. Details are in [CODE_GUIDE.md](../CODE_GUIDE.md#unit-tests). A database created before the fix may still hold orphaned rows; a one-time cleanup is on the roadmap in [README](../README.md#roadmap).

## How to keep this current

1. New behavior gets a new `REQ-` row *before* the code is written.
2. A bug fix adds a test first, then references the existing or new requirement.
3. A pull request that changes behavior but not this file is incomplete (the PR template asks).
