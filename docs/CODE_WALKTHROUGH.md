# Code walkthrough: temporary debugging code and the refactors that stayed

Real code from the fix in PR #10 (`git diff 269403f 947195c`). Part 1 is code that was written to find a problem and then **deleted before commit**. Part 2 is code that **changed and stayed**, with the reasoning. Part 3 is the test that proves it. Read it together with [TESTING_AND_DEBUGGING.md](./TESTING_AND_DEBUGGING.md) and [CASE_STUDY.md](./CASE_STUDY.md).

## Part 1: temporary code (written to investigate, then removed)

Rule: temporary code goes in, answers one question, and comes out **before** the commit. `git diff` and `git status` are how you check it is really gone.

### 1a. Exception logger with call stack (removed from `hellocontacts.lpr`)

**Question:** the app showed "Operation cannot be performed on an inactive dataset", but where was it raised? The error dialog gives no source line.

```pascal
type
  TTmpTrace = class
    procedure OnExc(Sender: TObject; E: Exception);
  end;

procedure TTmpTrace.OnExc(Sender: TObject; E: Exception);
var
  F: TextFile;
  I: Integer;
begin
  AssignFile(F, 'C:\Users\Douglas\AppData\Local\Temp\hc_trace.log');
  if FileExists('C:\Users\Douglas\AppData\Local\Temp\hc_trace.log') then Append(F) else Rewrite(F);
  WriteLn(F, E.ClassName, ': ', E.Message);
  WriteLn(F, BackTraceStrFunc(ExceptAddr));
  for I := 0 to ExceptFrameCount - 1 do
    WriteLn(F, BackTraceStrFunc(ExceptFrames[I]));
  CloseFile(F);
  Application.ProcessMessages;
end;

var
  Tmp: TTmpTrace;

begin
  Tmp := TTmpTrace.Create;
  Application.OnException := @Tmp.OnExc;   // route every unhandled exception to the logger
  ...
```

**How it was used:** build with `lazbuild -B --opt=-gl hellocontacts.lpi` (adds line info), run the GUI test until the error appeared, then turn each logged address into a name:

```powershell
gdb -batch -ex "info symbol 0x1001EF470" .\hellocontacts.exe
```

**Result:** the frames named `TDataSet.Refresh`, called from `TFormContacts.ButtonDeleteClick`. So a `Refresh` in a `finally` block was hitting a closed query.

**Why it was removed:** it hard-codes a personal path (against the repo rules), swallows the normal error dialog, and exists only to answer one question. `git checkout -- hellocontacts.lpr` restored the original file.

**Mistake along the way:** the first attempt added `lnfodwrf` to the `uses` clause and the build failed with "Duplicate identifier LNFODWRF", because the `-gl` option already links it. The two runs after that silently used the *old* exe. Lesson: after any change, confirm the build actually succeeded before trusting a test run.

### 1b. Diagnostic lines inside the GUI test (removed from `scripts\gui-tests.ps1`)

**Question:** the Delete step failed intermittently. Was the test clicking the wrong dialog, or did the app not delete?

```powershell
# print what the second dialog really contains before clicking OK
"  dialog2: " + ((Descendants $confirm | % { $_.Current.ClassName + ':' + $_.Current.Name }) -join ' ; ')

# when the check fails, dump the database state
if ((Sql "select count(*) from People where Last='Edited'") -ne '0') {
    ListWindows
    "  people: " + (Sql "select group_concat(Id || ':' || First || ' ' || Last, ' | ') from People")
    Start-Sleep 3
    "  after 3s: " + (Sql "select count(*) from People")
}
```

**Result:** the dialog text was the correct "OK to Delete Zzgui Edited?" so the click was right, and the row was still in the database even 3 seconds later. That ruled out the "wrong dialog" theory and pointed at the database layer.

**What fixed it:** the test itself polled the database with `sqlite3` while the app was committing, which can hold a lock and make the app's commit fail silently. The fix stayed in the test, with a comment:

```powershell
Click (FindButton $confirm 'OK')
# Polling the database while the app commits can make the commit fail with SQLITE_BUSY
Start-Sleep -Seconds 2
Check 'Delete: row removed from database' (WaitFor { (Sql "select count(*) ...") -eq '0' })
```

After that: 10 of 10 consecutive passes. Before it: about half.

**Why the diagnostics were removed:** they printed noise on every run. The permanent `ListWindows` helper stayed because it is useful whenever a step aborts.

### 1c. Throwaway run loops (typed in the terminal, never saved)

```powershell
for ($i=1; $i -le 10; $i++) {
  $j = Start-Job { Set-Location $using:PWD; powershell -NoProfile -File scripts\gui-tests.ps1 2>&1 | Out-String }
  if (Wait-Job $j -Timeout 150) { $o = Receive-Job $j } else { $o = 'TIMEOUT'; Stop-Job $j }
  Get-Process hellocontacts -ea 0 | % { $_.Kill() }
  if ($o -notmatch 'All GUI checks passed') { $o; break }
}
```

A flaky test needs a **count**, not one result. This loop runs the test repeatedly with a time limit, kills a stuck app, and stops at the first failure to show its output. Nothing was committed; the same idea is recommended in the docs as "run it 5 to 10 times".

## Part 2: refactors that stayed, and why

Each change is minimal and was driven by a failing test (see Part 3).

### 2a. `Commit` to `CommitRetaining` (in `AddUser`, `EditUser`, `AddPhone`, `EditPhone`)

```pascal
// before
TSQLTransaction(Q.Transaction).Commit();

// after
// CommitRetaining keeps other open queries (the grids) on this transaction open
TSQLTransaction(Q.Transaction).CommitRetaining();
```

**Rationale.** The people grid, the phone grid and the insert query all share one `SQLTransaction1`. A plain `Commit` ends the transaction **and closes every query attached to it**. The next click then touched a closed grid query and raised "inactive dataset". `CommitRetaining` writes the data to disk (it is durable) but keeps the transaction and its queries open.

**Trade-off.** A retaining commit starts a new transaction immediately and leaves it open, so this is not a pattern for long-running servers or many connections. For a single-user desktop app it is the smallest correct change. The roadmap in [CODE_GUIDE.md](../CODE_GUIDE.md) (DI refactor, one transaction per operation) is the bigger fix; it was deliberately **not** done here.

### 2b. Deletes now commit, and roll back on error (`DeleteUser`, `DeletePhone`)

```pascal
// before
Q.execSql;
// Delete query is automatically committed, no need for Transaction.commit
except
    on E: Exception do
    begin
        ShowException(E);
    end;

// after
Q.execSql;
if (Q.Transaction.Active) then
    TSQLTransaction(Q.Transaction).CommitRetaining();
except
    on E: Exception do
    begin
        if (Q.Transaction.Active) then
            TSQLTransaction(Q.Transaction).Rollback();
        ShowException(E);
    end;
```

**Rationale.** The old comment was wrong. SQLite deletes inside a transaction are not committed until you commit. The app *looked* correct because the same connection could see its own uncommitted delete, so the row vanished from the grid. A second connection (or restarting the app) would still see the row. The `except` branch also never rolled back, so a failed delete left a half-open transaction. Misleading comments are bugs waiting to happen; the wrong comment was removed along with the behaviour.

### 2c. Re-open the main queries before refreshing (`unit1.pas`)

```pascal
finally
    DataModule1.EnsureMainQueriesActive();   // added
    DataModule1.QueryPeople.Refresh();
    DBGridPeople.Refresh();
    HideIds();
end;
```

(Added in `ButtonDeleteClick`, `ButtonDeletePhoneClick`, `DBGridPeopleCellClick`.)

**Rationale.** `TDataSet.Refresh` raises if the dataset is closed. These `finally` blocks run after every action, including failed ones, so they must not assume the queries are open. `EnsureMainQueriesActive` already existed and does exactly the check; calling it first is defence in depth, a small, local change rather than a redesign.

### 2d. `WriteLn` to `DebugLn` (`unit1.pas`, `unitaddphone.pas`)

```pascal
// before: raises RunError 103 in a GUI app because there is no console
WriteLn(FilterString);

// after: LazLogger writes to the IDE's debug output or a log file, never crashes
DebugLn(FilterString);
```

**Rationale.** A GUI program has no standard output, so `WriteLn` fails at runtime. `DebugLn` keeps the diagnostic output for development and is harmless in a release. It needs `LazLogger` in the `uses` clause.

## Part 3: the test that proves it

Test first: these were written and run **before** the fix, and 4 of the 6 failed.

```pascal
procedure TOpenQueryTests.DeleteUserKeepsOtherQueryOpen;
var
  Id: Integer;
begin
  Id := AddUser(FQuery, 'Ada', 'Lovelace');
  OpenGrid;                       // a second query on the same transaction, like the grid
  DeleteUser(FQuery, Id);
  AssertTrue('grid query still open', FGrid.Active);
end;
```

It reproduces the user's bug (an action closes the grid's query) without any GUI, in milliseconds. A separate test, `DeleteUserIsCommitted`, uses `CountFromOtherConnection` (a second database connection) to prove the delete really reached the file. The GUI test then confirms the same thing through the real application.

## How to reuse this pattern

1. State the question the temporary code must answer.
2. Write the smallest throwaway code that answers it. Keep it on a branch or uncommitted.
3. Record the **result** (here: in this doc), not the code, in the repository history.
4. Remove it and prove it is gone: `git status`, `git diff`, and a clean rebuild.
5. Replace the guess with a test that fails for the right reason, then make the smallest fix.
6. Explain *why* in docs, not in code comments (the repo rule: sparse comments, explanations in the guide).
