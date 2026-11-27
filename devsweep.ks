// DevSweep - disk analyzer with Xcode-focused cleanup.
// macOS arm64, built with Krypton/Objective-K (k:okui).
// Direct distribution: cleanup commands are fixed strings, never built from
// user input. Protected areas (.lima VMs, Docker state, game data, Xcode
// CodingAssistant) are never touched.

import "k:okui"
import "k:objk_process_macos"

let gTable = 0
let gLog = 0
let gStatus = 0
let gApp = 0
let gWin = 0
let gDeleteArmed = 0

func resultBody(result) {
    let nl = indexOf(result, "\n")
    if nl == "-1" { emit result }
    emit substring(result, toInt(nl) + 1, len(result))
}

func resultStatus(result) {
    let nl = indexOf(result, "\n")
    if nl == "-1" { emit "-1" }
    emit substring(result, 0, toInt(nl))
}

func human(kbText) {
    let kb = toInt(kbText)
    if kb < 1024 { emit kbText + " KB" }
    let mb = kb / 1024
    if mb < 1024 { emit mb + " MB" }
    emit (mb / 1024) + " GB"
}

func baseName(path) {
    let slash = 0 - 1
    let i = 0
    while i < len(path) {
        if path[i] == "/" { slash = i }
        i += 1
    }
    if slash < 0 { emit path }
    emit substring(path, slash + 1, len(path))
}

func appendRow(label, size, path, note) {
    okArrayAdd(okGet(gTable, "sweep.labels"), nsString(label))
    okArrayAdd(okGet(gTable, "sweep.sizes"), nsString(size))
    okArrayAdd(okGet(gTable, "sweep.paths"), nsString(path))
    okArrayAdd(okGet(gTable, "sweep.notes"), nsString(note))
    emit 0
}

func clearRows(table) {
    okSet(table, "sweep.labels", okArray())
    okSet(table, "sweep.sizes", okArray())
    okSet(table, "sweep.paths", okArray())
    okSet(table, "sweep.notes", okArray())
    okSelectNone(table)
    okReload(table)
    emit 0
}

func onQuit(self, command, sender) {
    okQuit(gApp)
    emit 0
}

func onReveal(self, command, sender) {
    let selection = okSelection(gTable)
    if okSelectionCount(selection) == 0 {
        okSetText(gStatus, "Select a row first")
        emit 0
    }
    let row = okSelectionAt(selection, 0)
    let path = nsToStr(okArrayGet(okGet(gTable, "sweep.paths"), row))
    if path == "" {
        okSetText(gStatus, "No path on this row")
        emit 0
    }
    okOpenPath(path)
    okSetText(gStatus, "Revealed: " + path)
    emit 0
}

func onScan(self, command, sender) {
    okSetText(gStatus, "Scanning... this can take a moment")
    clearRows(gTable)
    let cmd = "du -kd 1 \"$HOME/Library\" \"$HOME/Downloads\" \"$HOME/Documents\" \"$HOME/.lima\" \"$HOME/.ollama\" \"/Library/Developer/CoreSimulator/Volumes\" 2>/dev/null | sort -rn | head -40"
    let result = okRunCaptured(cmd)
    let text = resultBody(result)
    let tab = fromCharCode(9)
    let rows = 0
    let i = 0
    while i < lineCount(text) {
        let line = getLine(text, i)
        let pos = indexOf(line, tab)
        if pos != "-1" {
            let kb = substring(line, 0, toInt(pos))
            let path = substring(line, toInt(pos) + 1, len(line))
            let note = "Inspect"
            if contains(path, "/.lima") { note = "Protected VM" }
            if contains(path, "com.docker.docker") { note = "Protected VM" }
            if contains(path, "/Documents/GitHub") { note = "Source" }
            appendRow(baseName(path), human(kb), path, note)
            rows += 1
        }
        i += 1
    }
    okReload(gTable)
    okSetText(gStatus, "Scanned " + rows + " locations")
    okSetTextView(gLog, text)
    emit 0
}

func onXcodeSizes(self, command, sender) {
    okSetText(gStatus, "Reading Xcode storage...")
    let cmd = "du -sh -d 1 \"$HOME/Library/Developer/Xcode\" 2>/dev/null"
    let result = okRunCaptured(cmd)
    let text = resultBody(result)
    okSetTextView(gLog, "Xcode storage:\n" + text)
    okSetText(gStatus, "Xcode storage ready")
    emit 0
}

func onRuntimeCheck(self, command, sender) {
    okSetText(gStatus, "Checking simulator runtimes...")
    let result = okRunCaptured("xcrun simctl runtime delete --outdated --dry-run 2>&1")
    let text = resultBody(result)
    okSetTextView(gLog, "Outdated runtime preview:\n" + text)
    okSetText(gStatus, "Runtime check done")
    emit 0
}

func onRuntimeDelete(self, command, sender) {
    if gDeleteArmed != 1 {
        gDeleteArmed = 1
        okSetText(gStatus, "Click Delete Outdated again to confirm runtime deletion")
        emit 0
    }
    gDeleteArmed = 0
    okSetText(gStatus, "Deleting outdated runtimes...")
    let result = okRunCaptured("xcrun simctl runtime delete --outdated 2>&1")
    let text = resultBody(result)
    okSetTextView(gLog, "Runtime delete (status " + resultStatus(result) + "):\n" + text)
    okSetText(gStatus, "Runtime cleanup finished")
    emit 0
}

func onDerivedClean(self, command, sender) {
    okSetText(gStatus, "Clearing stale DerivedData...")
    let cmd = "if pgrep -f \"/Applications/Xcode.app/Contents/MacOS/Xcode\" >/dev/null 2>&1; then echo 'Xcode is running - skipped'; else find \"$HOME/Library/Developer/Xcode/DerivedData\" -mindepth 1 -maxdepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null; echo 'Stale DerivedData cleared'; fi"
    let result = okRunCaptured(cmd)
    let text = resultBody(result)
    okSetTextView(gLog, "DerivedData:\n" + text)
    okSetText(gStatus, "DerivedData cleanup finished")
    emit 0
}

func sweepRows(self, command, table) {
    emit okArrayCount(okGet(table, "sweep.labels"))
}

func sweepCell(self, command, table, column, row) {
    let id = nsToStr(msg(column, "identifier"))
    if id == "size" { emit okArrayGet(okGet(table, "sweep.sizes"), row) }
    if id == "path" { emit okArrayGet(okGet(table, "sweep.paths"), row) }
    if id == "note" { emit okArrayGet(okGet(table, "sweep.notes"), row) }
    emit okArrayGet(okGet(table, "sweep.labels"), row)
}

just run {
    let pool = okAutoreleasePool()
    let app = okApp()
    gApp = app
    let win = okWindow(app, "DevSweep - Disk Analyzer", 940, 660)
    gWin = win
    okMinSize(win, 760, 520)
    okSetWindowBg(win, okSystemWindowBg())
    msg_1(win, "setReleasedWhenClosed:", 0)

    let bar = okMenuBar(app)
    let appMenu = okMenuAdd(bar, "DevSweep")
    okMenuAction(appMenu, "Quit", "q", funcptr(onQuit))
    let editMenu = okMenuAdd(bar, "Edit")
    okMenuSelector(editMenu, "Cut", "x", "cut:")
    okMenuSelector(editMenu, "Copy", "c", "copy:")
    okMenuSelector(editMenu, "Paste", "v", "paste:")
    okMenuSelector(editMenu, "Select All", "a", "selectAll:")

    let title = okLabel(win, "DevSweep - scan large folders, then clean Xcode safely", 20, 618, 900, 26)
    okSetTextColor(title, okSystemText())

    let scanButton = okButton(win, "Scan Home", 20, 580, 120, 30)
    let xcodeButton = okButton(win, "Xcode Sizes", 150, 580, 120, 30)
    let checkButton = okButton(win, "Check Runtimes", 280, 580, 140, 30)
    let deleteButton = okButton(win, "Delete Outdated", 430, 580, 150, 30)
    let derivedButton = okButton(win, "Clear DerivedData", 590, 580, 170, 30)
    let revealButton = okButton(win, "Reveal", 770, 580, 100, 30)

    gStatus = okLabel(win, "Ready", 20, 546, 900, 24)
    okSetTextColor(gStatus, okSystemSecondaryText())

    gTable = okTable(win, 20, 250, 900, 286)
    okMultiSelect(gTable, 0)
    okColumn(gTable, "kind", "Location", 210)
    okColumn(gTable, "size", "Size", 100)
    okColumn(gTable, "path", "Path", 500)
    okColumn(gTable, "note", "Note", 88)
    okRowHeight(gTable, 24)
    let scroll = msg(gTable, "enclosingScrollView")
    okAutoresizing(scroll, 18)
    okSet(gTable, "sweep.labels", okArray())
    okSet(gTable, "sweep.sizes", okArray())
    okSet(gTable, "sweep.paths", okArray())
    okSet(gTable, "sweep.notes", okArray())

    gLog = okTextView(win, 20, 40, 900, 190)
    okSetTextView(gLog, "Welcome to DevSweep.\nScan to find large folders. Xcode actions only touch build caches and outdated simulator runtimes.\nProtected: .lima VMs, Docker state, game data, CodingAssistant.")
    okSetTextColor(gLog, okSystemText())

    okClick(scanButton, funcptr(onScan))
    okClick(xcodeButton, funcptr(onXcodeSizes))
    okClick(checkButton, funcptr(onRuntimeCheck))
    okClick(deleteButton, funcptr(onRuntimeDelete))
    okClick(derivedButton, funcptr(onDerivedClean))
    okClick(revealButton, funcptr(onReveal))

    let sourceClass = okClass("DevSweepTableSource")
    okMethod(sourceClass, "numberOfRowsInTableView:", funcptr(sweepRows), "q@:@")
    okMethod(sourceClass, "tableView:objectValueForTableColumn:row:", funcptr(sweepCell), "@@:@@q")
    okRegister(sourceClass)
    let source = okNew(sourceClass)
    okDataSource(gTable, source)
    msg(source, "release")
    okReload(gTable)

    okShow(win, app)
    okRun(app)
    okDrainPool(pool)
}
