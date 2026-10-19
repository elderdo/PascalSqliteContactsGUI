# GUI end-to-end test (contacts: Search, Add, Edit, Delete) using Windows UI Automation
# and Win32 messages. Exit code 0 = all checks passed.
#
# It builds the app, drives the real hellocontacts.exe, and verifies the results by
# querying the SQLite file the app uses (%LOCALAPPDATA%\hellocontacts). That file is
# backed up first and restored afterwards (or deleted if it did not exist).
# The DB grids are custom-drawn, so they are checked through the database, not the UI.
# Phone Add/Edit/Delete are not covered: they need a grid-cell click to reveal the phone panel.
#
# HOW IT WORKS (for beginners)
#   1. Build the app and back up the real database.
#   2. Start hellocontacts.exe like a user would.
#   3. "Press" buttons and type text by sending Windows messages to the controls
#      (the same messages the mouse and keyboard produce).
#   4. After each action, look in the SQLite file to see whether the data really changed.
#      Checking the database is more reliable than reading the screen.
#   5. Always put the database back and close the app, even if a check fails.
#
# RULES WHEN RUNNING IT
#   * Close hellocontacts.exe first, and do not touch the mouse/keyboard while it runs
#     (it takes about a minute).
#   * It needs an interactive Windows desktop (a logged-in session).

# Stop at the first unexpected error. Failed *checks* are counted instead (see Check below).
$ErrorActionPreference = 'Stop'

# Load the .NET UI Automation libraries. They let PowerShell find windows and buttons
# of another program.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# Add-Type with C# code lets PowerShell call Windows API functions (user32.dll).
# Each line below declares one function we need:
#   SendMessage  - send a message and wait for it to be handled (used to set text)
#   PostMessage  - send a message and return immediately (used to click; a click that
#                  opens a modal dialog would otherwise never return)
#   SetForegroundWindow / ShowWindow / keybd_event - bring a window to the front
#   GetForegroundWindow - (declared for completeness)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class W32 {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte vk, byte scan, int flags, IntPtr extra);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
}
'@
# Windows message numbers: WM_SETTEXT sets a control's text, BM_CLICK presses a button.
$WM_SETTEXT = 0x0C
$BM_CLICK = 0xF5
# Short alias for the UI Automation "element" type.
$AE = [Windows.Automation.AutomationElement]

# Paths: the repository root, the exe, and the SQLite file the app uses.
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$exe = Join-Path $root 'hellocontacts.exe'
$dbDir = Join-Path $env:LOCALAPPDATA 'hellocontacts'
$db = Join-Path $dbDir 'helloContacts.db'
# Where the user's real database is parked while the test runs.
$bak = "$db.guitest.bak"
# Counters shared by all functions ($script: makes a variable visible inside functions).
$script:failures = 0
$script:appPid = 0

# Prints PASS or FAIL for one check and counts failures. The script exits 1 at the end
# if any check failed.
function Check($name, $ok) {
    if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failures++ }
}

# Runs an SQL statement against the app's database and returns the output text.
# sqlite3.exe if available, otherwise Python's sqlite3 module (present on GitHub runners)
function Sql($query) {
    if (Get-Command sqlite3 -ErrorAction SilentlyContinue) {
        return (sqlite3 $db $query)
    }
    $env:GUITEST_DB = $db
    $env:GUITEST_SQL = $query
    # Python fallback: the query is passed through environment variables to avoid quoting problems.
    return (python -c "import os,sqlite3; c=sqlite3.connect(os.environ['GUITEST_DB']); cur=c.cursor(); [cur.execute(s) for s in os.environ['GUITEST_SQL'].split(';') if s.strip()]; rows=cur.fetchall(); c.commit(); print('\n'.join('|'.join(map(str,r)) for r in rows))")
}

# A filter that matches only windows belonging to the app we started (by process id).
function PidCondition { New-Object Windows.Automation.PropertyCondition $AE::ProcessIdProperty, $script:appPid }

# The app's top-level windows (normally just the main window).
function TopWindows {
    $AE::RootElement.FindAll('Children', (PidCondition))
}

# Dialogs are owned by the main window, so UI Automation lists them under it, not at top level.
# They disappear from the tree when closed.
# Returns the main window plus every named window/dialog inside it.
function AppWindows {
    $main = TopWindows | Where-Object { $_.Current.Name -eq 'Hello Contacts DB' } | Select-Object -First 1
    if ($main) { $main; Descendants $main | Where-Object { $_.Current.ClassName -in 'Window', '#32770' -and $_.Current.Name -ne '' } }
}

# Waits (default up to 10 s, polling 4 times a second) for a window with this title; $null if it never appears.
function WaitWindow($title, $seconds = 10) {
    for ($i = 0; $i -lt ($seconds * 4); $i++) {
        $w = AppWindows | Where-Object { $_.Current.Name -eq $title } | Select-Object -First 1
        if ($w) { return $w }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

# Waits for any dialog (other than the main window) that has the given button
function WaitDialogWithButton($caption, $seconds = 10) {
    for ($i = 0; $i -lt ($seconds * 4); $i++) {
        foreach ($w in (AppWindows | Where-Object { $_.Current.Name -ne 'Hello Contacts DB' })) {
            $b = FindButton $w $caption
            if ($b) { return $w }
        }
        Start-Sleep -Milliseconds 250
    }
    return $null
}

# Every UI element nested anywhere inside a window.
function Descendants($win) { $win.FindAll('Descendants', [Windows.Automation.Condition]::TrueCondition) }

# Finds a button by its caption. '&' is removed because it marks the keyboard shortcut letter.
function FindButton($win, $caption) {
    Descendants $win | Where-Object {
        $_.Current.ClassName -in 'Button','CCPushButton' -and ($_.Current.Name -replace '&', '') -eq $caption
    } | Select-Object -First 1
}

# Edits sorted top to bottom
function FindEdits($win) {
    @(Descendants $win | Where-Object { $_.Current.ClassName -eq 'Edit' } |
        Sort-Object { $_.Current.BoundingRectangle.Top })
}

# Types text into an edit box by sending it a WM_SETTEXT message.
function SetText($el, $text) {
    [W32]::SendMessage([IntPtr]$el.Current.NativeWindowHandle, $WM_SETTEXT, [IntPtr]::Zero, $text) | Out-Null
}

# PostMessage, not SendMessage: a click that opens a modal form would never return
function Click($el) {
    # Message-box buttons have their own handle too, so BM_CLICK works for them
    [W32]::PostMessage([IntPtr]$el.Current.NativeWindowHandle, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

# Clicks the first data row of the people grid (the grid is not exposed by UI Automation), like a user selecting a row
function SelectFirstRow($main) {
    # The grid is the biggest unnamed child window. 0x201/0x202 = left mouse button down/up;
    # the click position (x=60, y=38) falls on the first data row below the header.
    $grid = Descendants $main | Where-Object { $_.Current.ClassName -eq 'Window' -and $_.Current.Name -eq '' } | Sort-Object { $_.Current.BoundingRectangle.Height } -Descending | Select-Object -First 1
    $lparam = [IntPtr]((38 -shl 16) -bor 60)
    [W32]::SendMessage([IntPtr]$grid.Current.NativeWindowHandle, 0x201, [IntPtr]1, $lparam) | Out-Null
    [W32]::SendMessage([IntPtr]$grid.Current.NativeWindowHandle, 0x202, [IntPtr]::Zero, $lparam) | Out-Null
    Start-Sleep -Milliseconds 500
}

# A user returning to the main window triggers its OnActivate, which reopens the queries; do the same here
function ActivateMain {
    $m = TopWindows | Where-Object { $_.Current.Name -eq 'Hello Contacts DB' } | Select-Object -First 1
    $h = [IntPtr]$m.Current.NativeWindowHandle
    # A synthetic Alt key press lifts the foreground lock so SetForegroundWindow is honoured
    [W32]::keybd_event(0x12, 0, 0, [IntPtr]::Zero); [W32]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
    [W32]::SetForegroundWindow($h) | Out-Null
    # Minimize + restore forces a genuine activation, which fires the form's OnActivate
    [W32]::ShowWindow($h, 6) | Out-Null; Start-Sleep -Milliseconds 300
    [W32]::ShowWindow($h, 9) | Out-Null; Start-Sleep -Milliseconds 300
    [W32]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 500
}

# The app's runtime-error box has OK (ignore) and Abort buttons. Record it as a failure and click OK so the app is not killed.
function DismissRuntimeError {
    foreach ($w in (AppWindows | Where-Object { $_.Current.Name -ne 'Hello Contacts DB' })) {
        if (FindButton $w 'Abort') {
            $msg = (Descendants $w | ForEach-Object { $_.Current.Name } | Where-Object { $_ -match 'dataset|Exception|Error' }) -join ' '
            "FAIL  app showed a runtime error: $msg"
            $script:failures++
            Click (FindButton $w 'OK')
            return $true
        }
    }
    return $false
}

# Polls a condition (a script block) up to $seconds; returns $true as soon as it is true, $false on timeout.
# Used instead of fixed sleeps so the test is fast when the app is fast and patient when it is slow.
function WaitFor($scriptBlock, $seconds = 10) {
    for ($i = 0; $i -lt ($seconds * 4); $i++) {
        if (& $scriptBlock) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

# Debug helper: prints every window and control of the app. Called right before the test
# gives up, so the log shows what was on screen.
function ListWindows {
    $p = Get-Process -Id $script:appPid -ErrorAction SilentlyContinue
    "  process running: $([bool]$p)"
    foreach ($w in (TopWindows)) {
        "  window '$($w.Current.Name)'"
        foreach ($d in (Descendants $w)) { "    $($d.Current.ClassName) '$($d.Current.Name)'" }
    }
}

# --- setup ---------------------------------------------------------------------------
# Refuse to run if the app is already open: it would hold the database and fight our clicks.
if (Get-Process hellocontacts -ErrorAction SilentlyContinue) { throw 'Close hellocontacts.exe first' }

# Build the app so we always test the current source code.
$lazbuild = (Get-Command lazbuild -ErrorAction SilentlyContinue).Source
if (-not $lazbuild -and (Test-Path 'C:\lazarus\lazbuild.exe')) { $lazbuild = 'C:\lazarus\lazbuild.exe' }
if (-not $lazbuild) { Write-Host 'lazbuild not found. Add Lazarus to PATH.'; exit 2 }
& $lazbuild hellocontacts.lpi | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'Application failed to build.'; exit 1 }

$dbExisted = Test-Path $db
if ($dbExisted) {
    # Park the user's real data; it is moved back in the finally block at the end.
    Copy-Item $db $bak -Force
}
else {
    # The app creates its database on first start
    $first = Start-Process $exe -PassThru
    $created = WaitFor { Test-Path $db } 15
    Start-Sleep -Seconds 1
    if (-not $first.HasExited) { $first.Kill() }
    Start-Sleep -Milliseconds 500
    if (-not $created) { throw "App did not create its database at $db" }
}

$proc = $null
# try/finally: the finally block below runs even when a check throws, so cleanup always happens.
try {
    # Remove leftovers from an earlier aborted run so the counts below start clean.
    Sql "delete from People where Last in ('Newperson','Edited')" | Out-Null

    # Start the app and wait for its main window.
    $proc = Start-Process $exe -PassThru
    $script:appPid = $proc.Id
    $main = WaitWindow 'Hello Contacts DB' 15
    Check 'main window appears' ($null -ne $main)
    if (-not $main) { throw 'Main window did not appear' }

    # Locate the controls we will drive. The Add button is picked by position because
    # another form also has an "Add" button.
    $search = FindEdits $main | Select-Object -First 1
    $btnSearch = FindButton $main 'Search'
    $btnAdd = @(Descendants $main | Where-Object { $_.Current.ClassName -eq 'Button' -and $_.Current.Name -eq 'Add' } | Sort-Object { $_.Current.BoundingRectangle.Top }) | Select-Object -First 1
    $btnEdit = FindButton $main 'Edit'
    $btnDelete = FindButton $main 'Delete'
    Check 'main controls found' ($search -and $btnSearch -and $btnAdd -and $btnEdit -and $btnDelete)
    if (-not ($search -and $btnSearch -and $btnAdd -and $btnEdit -and $btnDelete)) { ListWindows; throw 'GUI test aborted' }

    # Search runs without error
    SetText $search 'Zzgui'
    Click $btnSearch
    Start-Sleep -Seconds 1
    $proc.Refresh()
    Check 'Search: app still running' (-not $proc.HasExited)

    # Add: the search text "Zzgui Newperson" pre-fills the Add Contact dialog
    SetText $search 'Zzgui Newperson'
    Click $btnAdd
    $dlg = WaitWindow 'Add Contact'
    Check 'Add: dialog opens' ($null -ne $dlg)
    if (-not $dlg) { ListWindows; throw 'GUI test aborted' }
    Click (FindButton $dlg 'Save')
    Check 'Add: dialog closes' (WaitFor { -not (WaitWindow 'Add Contact' 0) })
    ActivateMain
    Check 'Add: row saved in database' ((Sql "select count(*) from People where First='Zzgui' and Last='Newperson'") -eq '1')

    # Edit: search selects the new person, Edit pre-fills the dialog
    SetText $search 'Zzgui'
    Click $btnSearch
    Start-Sleep -Seconds 1
    SelectFirstRow $main
    Click $btnEdit
    $dlg = WaitWindow 'Edit Contact' 5
    if (-not $dlg) { DismissRuntimeError | Out-Null }
    if (-not $dlg) {
        # "No User Selected" is a normal message box, not an exception: report it and dismiss it
        $info = WaitDialogWithButton 'OK' 2
        if ($info) {
            "FAIL  Edit: app reported no row selected ($(@(Descendants $info | ForEach-Object { $_.Current.Name } | Where-Object { $_ -match 'Selected' }) -join ' '))"
            $script:failures++
            Click (FindButton $info 'OK')
        }
    }
    Check 'Edit: dialog opens' ($null -ne $dlg)
    if (-not $dlg) { ListWindows; throw 'GUI test aborted' }
    $edits = FindEdits $dlg
    SetText $edits[2] 'Edited'
    Click (FindButton $dlg 'Save')
    Check 'Edit: dialog closes' (WaitFor { -not (WaitWindow 'Edit Contact' 0) })
    ActivateMain
    Check 'Edit: row updated in database' ((Sql "select count(*) from People where First='Zzgui' and Last='Edited'") -eq '1')
    Check 'Edit: old value gone' ((Sql "select count(*) from People where Last='Newperson'") -eq '0')

    # Delete: cancel keeps the row, OK removes it
    # Delete asks "OK to Delete ...?" first; we answer Cancel and then check the row survived.
    SetText $search 'Zzgui'
    Click $btnSearch
    Start-Sleep -Seconds 1
    SelectFirstRow $main
    Click $btnDelete
    $confirm = WaitDialogWithButton 'Cancel'
    Check 'Delete: confirmation appears' ($null -ne $confirm)
    if (-not $confirm) { ListWindows; throw 'GUI test aborted' }
    Click (FindButton $confirm 'Cancel')
    Check 'Delete: confirmation closes' (WaitFor { -not (WaitDialogWithButton 'Cancel' 0) })
    Start-Sleep -Seconds 1
    Check 'Delete: Cancel keeps the row' ((Sql "select count(*) from People where Last='Edited'") -eq '1')

    # The row selection is lost after the refresh, so select it again before the second attempt.
    SelectFirstRow $main
    Click $btnDelete
    $confirm = WaitDialogWithButton 'OK'
    Check 'Delete: confirmation appears again' ($null -ne $confirm)
    if (-not $confirm) { ListWindows; throw 'GUI test aborted' }
    Click (FindButton $confirm 'OK')
    # Polling the database while the app commits can make the commit fail with SQLITE_BUSY
    Start-Sleep -Seconds 2
    Check 'Delete: row removed from database' (WaitFor { (Sql "select count(*) from People where Last='Edited'") -eq '0' })
    if ((Sql "select count(*) from People where Last='Edited'") -ne '0') { ListWindows; "  people: " + (Sql "select group_concat(Id || ':' || First || ' ' || Last, ' | ') from People"); Start-Sleep 3; "  after 3s: " + (Sql "select count(*) from People") }

    # Final sanity checks: the app survived and no runtime-error box (OK/Abort) is showing.
    $proc.Refresh()
    Check 'app still running at the end' (-not $proc.HasExited)
    $errors = @(AppWindows | Where-Object { $_.Current.Name -match 'Exception|Error|Runtime' -or (FindButton $_ 'Abort') })
    Check 'no error dialog' ($errors.Count -eq 0)
}
finally {
    # Cleanup that always runs: close the app and put the user's database back
    # (or delete the one we created if there was none).
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
    Start-Sleep -Milliseconds 500
    if ($dbExisted) { Move-Item $bak $db -Force } else { Remove-Item $db -Force -ErrorAction SilentlyContinue }
}

# Exit code 1 tells the pre-commit hook / CI that the run failed.
if ($script:failures) { "$($script:failures) check(s) failed"; exit 1 }
'All GUI checks passed'
