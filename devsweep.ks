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
let gDeleteFilesArmed = 0
let gBrowsePath = ""

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

func paintButton(btn, bg, fg) {
    // NSButton's own backgroundColor is drawn over by its system bezel.
    // A borderless button with a layer background paints reliably.
    msg_1(btn, "setBordered:", 0)
    msg_1(btn, "setWantsLayer:", 1)
    msg_1(msg(btn, "layer"), "setBackgroundColor:", msg(bg, "CGColor"))
    okSetButtonTextColor(btn, fg)
    emit 0
}

func isProtectedPath(path) {
    if contains(path, "/.lima") { emit 1 }
    if contains(path, "com.docker.docker") { emit 1 }
    if contains(path, "/Documents/GitHub") { emit 1 }
    if contains(path, "Dead Island") { emit 1 }
    if contains(path, "CodingAssistant") { emit 1 }
    if contains(path, "iOS DeviceSupport") { emit 1 }
    if contains(path, "@opencodedesktop-updater") { emit 1 }
    if contains(path, "/Caches/com.google.GeminiMacOS") { emit 1 }
    if contains(path, "/Caches/lima") { emit 1 }
    if contains(path, "/CoreSimulator/Volumes") { emit 1 }
    emit 0
}

func noteFor(path) {
    if contains(path, "/.lima") { emit "Protected VM" }
    if contains(path, "com.docker.docker") { emit "Protected VM" }
    if contains(path, "/Documents/GitHub") { emit "Source" }
    if contains(path, "Dead Island") { emit "Protected Game" }
    if endsWith(path, "/Library") || endsWith(path, "/Downloads") || endsWith(path, "/Documents") || endsWith(path, "/.ollama") || endsWith(path, "/CoreSimulator/Volumes") { emit "Root" }
    emit "Inspect"
}

func fillTable(text) {
    clearRows(gTable)
    let tab = fromCharCode(9)
    let rows = 0
    let i = 0
    while i < lineCount(text) {
        let line = getLine(text, i)
        let pos = indexOf(line, tab)
        if pos != "-1" {
            let kb = substring(line, 0, toInt(pos))
            let path = substring(line, toInt(pos) + 1, len(line))
            appendRow(baseName(path), human(kb), path, noteFor(path))
            rows += 1
        }
        i += 1
    }
    okReload(gTable)
    okSelectNone(gTable)
    emit rows
}

func browse(aPath) {
    // du hides plain files unless -a, which cannot be combined with -d.
    // A fixed shell glob lists both files and folders; the path is a literal
    // argv value, never interpolated into the command string.
    let args = okProcessArgs()
    doProcessArg(args, "-c")
    doProcessArg(args, "du -sk \"$1\"/* 2>/dev/null | sort -rn")
    doProcessArg(args, "sh")
    doProcessArg(args, aPath)
    let result = okRunArgvCaptured("/bin/sh", args)
    let text = resultBody(result)
    let rows = fillTable(text)
    gBrowsePath = aPath
    okSetText(gStatus, "Browsing " + aPath + " - " + rows + " items")
    okSetTextView(gLog, text)
    emit 0
}

func parentOf(path) {
    let slash = 0 - 1
    let i = 0
    while i < len(path) {
        if path[i] == "/" { slash = i }
        i += 1
    }
    if slash <= 0 { emit "" }
    emit substring(path, 0, slash)
}

func onOpenFolder(self, command, sender) {
    let selection = okSelection(gTable)
    if okSelectionCount(selection) == 0 {
        okSetText(gStatus, "Select a folder first")
        emit 0
    }
    let row = okSelectionAt(selection, 0)
    let path = nsToStr(okArrayGet(okGet(gTable, "sweep.paths"), row))
    if path == "" {
        okSetText(gStatus, "No path on this row")
        emit 0
    }
    browse(path)
    emit 0
}

func onOpenFolderTable(table) { onOpenFolder(0, 0, 0) emit 0 }

func onUp(self, command, sender) {
    if gBrowsePath == "" {
        okSetText(gStatus, "Already at scan roots")
        emit 0
    }
    let parent = parentOf(gBrowsePath)
    if parent == "" || parent == gBrowsePath {
        onScan(self, command, sender)
        emit 0
    }
    browse(parent)
    emit 0
}

func onHome(self, command, sender) { onScan(self, command, sender) emit 0 }

func onDeleteSelected(self, command, sender) {
    let selection = okSelection(gTable)
    let total = okSelectionCount(selection)
    if total == 0 {
        okSetText(gStatus, "Select one or more rows first")
        emit 0
    }
    if gDeleteFilesArmed != 1 {
        gDeleteFilesArmed = 1
        okSetText(gStatus, "Click Delete Selected again to confirm " + total + " item(s)")
        emit 0
    }
    gDeleteFilesArmed = 0
    let i = 0
    let deleted = 0
    let skipped = 0
    while i < total {
        let row = okSelectionAt(selection, i)
        let path = nsToStr(okArrayGet(okGet(gTable, "sweep.paths"), row))
        let note = nsToStr(okArrayGet(okGet(gTable, "sweep.notes"), row))
        if path == "" || note != "Inspect" || isProtectedPath(path) == 1 {
            skipped += 1
        } else {
            let args = okProcessArgs()
            doProcessArg(args, "-rf")
            doProcessArg(args, "--")
            doProcessArg(args, path)
            let result = okRunArgvCaptured("/bin/rm", args)
            if resultStatus(result) == "0" { deleted += 1 } else { skipped += 1 }
        }
        i += 1
    }
    okSetText(gStatus, "Deleted " + deleted + ", skipped " + skipped + " protected")
    if gBrowsePath == "" { onScan(self, command, sender) } else { browse(gBrowsePath) }
    emit 0
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
    let rows = fillTable(text)
    gBrowsePath = ""
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
    let win = okWindow(app, "DevSweep - Disk Analyzer", 1160, 660)
    gWin = win
    okMinSize(win, 960, 520)
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

    // Cortex for macOS palette (dark roles from PXBridge.m / transmute.ks).
    // Light mode keeps native system colors, matching Cortex's dynamic scheme.
    let canvas = okSystemWindowBg()
    let surface = okSystemTextBg()
    let bodyText = okSystemText()
    let muted = okSystemSecondaryText()
    let accent = okSystemText()
    let blue = okSystemText()
    let amber = okSystemSecondaryText()
    let danger = okRGB(240, 113, 120)    // red in both appearances
    let buttonBg = okSystemTextBg()
    let buttonText = bodyText
    let dark = okDark(win)
    if dark == 1 {
        canvas = okRGB(58, 47, 76)       // tabOn - title bar purple
        surface = okRGB(41, 32, 55)      // surface
        bodyText = okRGB(214, 219, 228)  // text
        muted = okRGB(154, 163, 178)     // muted
        accent = okRGB(199, 146, 234)    // purple
        blue = okRGB(99, 179, 245)       // blue
        amber = okRGB(230, 192, 123)     // amber
        buttonBg = okRGB(46, 37, 61)     // tab - buttons, almost title bar
        buttonText = okRGB(255, 255, 255)
    }
    okSetWindowBg(win, canvas)
    msg_1(win, "setTitlebarAppearsTransparent:", dark)

    let title = okLabel(win, "DevSweep - open a folder to select files; protected items are skipped", 20, 618, 1110, 26)
    okSetFont(title, okMonoFont(13))
    okSetTextColor(title, accent)

    let scanButton = okButton(win, "Scan Home", 20, 580, 110, 30)
    let xcodeButton = okButton(win, "Xcode Sizes", 140, 580, 110, 30)
    let checkButton = okButton(win, "Check Runtimes", 260, 580, 140, 30)
    let deleteButton = okButton(win, "Delete Outdated", 415, 580, 140, 30)
    let derivedButton = okButton(win, "Clear DerivedData", 570, 580, 160, 30)
    let revealButton = okButton(win, "Reveal", 745, 580, 90, 30)
    let deleteSelectedButton = okButton(win, "Delete Selected", 850, 580, 160, 30)

    let openButton = okButton(win, "Open Folder", 20, 546, 110, 30)
    let upButton = okButton(win, "Up", 140, 546, 80, 30)
    let homeButton = okButton(win, "Home", 230, 546, 80, 30)
    paintButton(scanButton, buttonBg, buttonText)
    paintButton(xcodeButton, buttonBg, buttonText)
    paintButton(checkButton, buttonBg, buttonText)
    paintButton(revealButton, buttonBg, buttonText)
    paintButton(derivedButton, buttonBg, buttonText)
    paintButton(deleteButton, buttonBg, danger)
    paintButton(deleteSelectedButton, buttonBg, danger)
    paintButton(openButton, buttonBg, blue)
    paintButton(upButton, buttonBg, blue)
    paintButton(homeButton, buttonBg, blue)

    gStatus = okLabel(win, "Ready", 330, 546, 800, 24)
    okSetTextColor(gStatus, muted)

    gTable = okTable(win, 20, 220, 1110, 280)
    okMultiSelect(gTable, 1)
    okColumn(gTable, "kind", "Location", 210)
    okColumn(gTable, "size", "Size", 100)
    okColumn(gTable, "path", "Path", 500)
    okColumn(gTable, "note", "Note", 88)
    okRowHeight(gTable, 24)
    msg_1(gTable, "setBackgroundColor:", surface)
    let scroll = msg(gTable, "enclosingScrollView")
    okAutoresizing(scroll, 18)
    okSet(gTable, "sweep.labels", okArray())
    okSet(gTable, "sweep.sizes", okArray())
    okSet(gTable, "sweep.paths", okArray())
    okSet(gTable, "sweep.notes", okArray())

    gLog = okTextView(win, 20, 40, 1110, 160)
    okSetTextView(gLog, "Welcome to DevSweep.\nScan to find large folders. Xcode actions only touch build caches and outdated simulator runtimes.\nProtected: .lima VMs, Docker state, game data, CodingAssistant.")
    okSetBg(gLog, surface)
    okSetTextColor(gLog, bodyText)

    okClick(scanButton, funcptr(onScan))
    okClick(xcodeButton, funcptr(onXcodeSizes))
    okClick(checkButton, funcptr(onRuntimeCheck))
    okClick(deleteButton, funcptr(onRuntimeDelete))
    okClick(derivedButton, funcptr(onDerivedClean))
    okClick(revealButton, funcptr(onReveal))
    okClick(deleteSelectedButton, funcptr(onDeleteSelected))
    okClick(openButton, funcptr(onOpenFolder))
    okClick(upButton, funcptr(onUp))
    okClick(homeButton, funcptr(onHome))

    let sourceClass = okClass("DevSweepTableSource")
    okMethod(sourceClass, "numberOfRowsInTableView:", funcptr(sweepRows), "q@:@")
    okMethod(sourceClass, "tableView:objectValueForTableColumn:row:", funcptr(sweepCell), "@@:@@q")
    okRegister(sourceClass)
    let source = okNew(sourceClass)
    okDataSource(gTable, source)
    msg(source, "release")
    okOnDoubleClick(gTable, funcptr(onOpenFolderTable))
    okReload(gTable)

    okShow(win, app)
    okRun(app)
    okDrainPool(pool)
}
