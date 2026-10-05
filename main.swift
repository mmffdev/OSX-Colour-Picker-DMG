import AppKit
import Sparkle

// ---------- Pick mode (hotkey-triggered) ----------

func runPickMode() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let sampler = NSColorSampler()
    let semaphore = DispatchSemaphore(value: 0)
    var picked: String?

    sampler.show { color in
        defer { semaphore.signal() }
        guard let color = color, let seen = ColourDefinition.picked(color) else { return }
        playShutter()
        var key: String?
        do {
            try LibraryStore.standard.mutate { key = $0.addPick(seen) }
        } catch {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        }
        guard let hex = key else { return }
        copyToClipboard(Prefs.copyText(hex))
        picked = hex
    }

    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    if let h = picked { print(h); exit(0) }
    exit(1)
}

// ---------- The app ----------

final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = LibraryController()
    /// Sparkle: checks the feed named in Info.plist once a day and offers what it finds.
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    var main: MainWindowController?
    var settings: SettingsWindowController?

    /// The standard About panel, with the credit the colour name list's licence asks for.
    @objc func showAbout() {
        let credit = NSAttributedString(string: colourNamesCredit, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credit])
    }

    @objc func showSettings() {
        if settings == nil { settings = SettingsWindowController(library: library) }
        settings?.refresh()
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        library.watchPrintCondition()
        let main = MainWindowController(library: library)
        self.main = main
        let bar = menus(for: main)
        Shortcuts.install(on: bar)   // before macOS adds its own items to the Edit menu
        NSApp.mainMenu = bar
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !Prefs.setupDone, let w = main.window { SetupWindowController.show(over: w) }
        DispatchQueue.main.async { self.library.sync() } // on open: look for changes from the other Mac
        rehearse(main)
    }

    /// For checking screens during a trial run (MMFFDEV_COLOUR3_HOME set): MMFFDEV_COLOUR3_SHOW may be
    /// "palette:<name>", "analysis:<palette name>", "analysis-one:<palette name>", "halo:<palette name>[/<action id>…]", "newcolour:<palette name>", "build:<hex>,<hex>", "settings:<panel number>", "search:<text>", "labels", "lab", "lab:<hex>", "tags", "tags:bar=<typed text>", "project:new" or "project:templates". Ignored otherwise.
    private func rehearse(_ main: MainWindowController) {
        let env = ProcessInfo.processInfo.environment
        guard env["MMFFDEV_COLOUR3_HOME"] != nil, let ask = env["MMFFDEV_COLOUR3_SHOW"] else { return }
        let parts = ask.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch parts[0] {
            case "palette":
                if let s = self.library.library.swatches.first(where: { $0.name == arg }) { main.show(.palette(s.id)) }
            case "analysis", "analysis-one":
                // The Analysis page for a palette, or for its first swatch.
                if let s = self.library.library.swatches.first(where: { $0.name == arg }) {
                    main.show(.palette(s.id))
                    if parts[0] == "analysis" { self.library.analyse(palette: s.id) }
                    else if let first = self.library.hexes(in: s.id).first { self.library.analyse(swatch: first, in: s.id) }
                }
            case "halo":
                // The first swatch's halo, with the rings its listed actions grow.
                let names = arg.split(separator: "/").map(String.init)
                if let s = self.library.library.swatches.first(where: { $0.name == names.first }) {
                    main.show(.palette(s.id))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { main.rehearseHalo(choosing: Array(names.dropFirst())) }
                }
            case "tabs":
                // "tabs:<palette>/<purpose,purpose>/<purpose to show>": a palette given purposes, on one purpose's tab.
                let bits = arg.split(separator: "/").map(String.init)
                if let s = self.library.library.swatches.first(where: { $0.name == bits.first }) {
                    for raw in (bits.count > 1 ? bits[1] : "").split(separator: ",") {
                        if let purpose = Purpose(rawValue: String(raw)) { self.library.setPurpose(purpose, on: true, ofPalette: s.id) }
                    }
                    self.library.show(bits.count > 2 ? Purpose(rawValue: bits[2]) : nil, forPalette: s.id)
                    main.show(.palette(s.id))
                }
            case "newcolour":
                if let p = self.library.library.swatches.first(where: { $0.name == arg }) {
                    main.show(.palette(p.id))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.library.newColour() }
                }
            case "build":
                main.buildPalette()
                main.rehearseBuilder(with: arg.split(separator: ",").map(String.init))
            case "settings":
                self.showSettings()
                self.settings?.showPanel(Int(arg) ?? 0)
            case "search":
                main.rehearseSearch(arg)
            case "tags":
                if arg.hasPrefix("bar") { main.rehearseTagBar(typing: String(arg.dropFirst(4))) } else { self.library.showTagEditor() }
            case "labels":
                main.rehearseLabels()
            case "lab":
                if arg.isEmpty { main.showLab() } else { self.library.onOpenLab?(arg) }
            case "project":
                if arg == "templates" { self.library.manageProjectTemplates() } else { self.library.newProject() }
            default: break
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    private func menus(for main: MainWindowController) -> NSMenu {
        let bar = NSMenu()
        func menu(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem()
            let m = NSMenu(title: title)
            build(m)
            item.submenu = m
            bar.addItem(item)
        }
        func add(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ target: AnyObject? = nil,
                 _ mods: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            m.addItem(item)
        }

        menu("MMFFDev Colour 3") { m in
            add(m, "About MMFFDev Colour 3", #selector(showAbout), "", self)
            add(m, "Check for Updates\u{2026}", #selector(SPUStandardUpdaterController.checkForUpdates(_:)), "", updater)
            m.addItem(.separator())
            add(m, "Settings\u{2026}", #selector(showSettings), ",", self)
            m.addItem(.separator())
            add(m, "Hide MMFFDev Colour 3", #selector(NSApplication.hide(_:)), "h")
            add(m, "Quit MMFFDev Colour 3", #selector(NSApplication.terminate(_:)), "q")
        }
        menu("File") { m in
            add(m, "Pick Colours", #selector(LibraryController.togglePicking), "p", library)
            add(m, "New Colour\u{2026}", #selector(LibraryController.newColour), "k", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "New Palette", #selector(LibraryController.newPalette), "n", library)
            add(m, "New Typography Palette", #selector(LibraryController.newTypography), "", library)
            add(m, "New Project\u{2026}", #selector(LibraryController.newProject), "n", library, [.command, .option])
            add(m, "Project Templates\u{2026}", #selector(LibraryController.manageProjectTemplates), "", library)
            add(m, "Build Palette from Swatches\u{2026}", #selector(MainWindowController.buildPalette), "n", main, [.command, .shift])
            add(m, "New Palette from Image\u{2026}", #selector(LibraryController.paletteFromImage), "i", library)
            add(m, "New Palette from Clipboard", #selector(LibraryController.paletteFromClipboard), "v", library, [.command, .shift])
            m.addItem(.separator())
            let catalogue = NSMenuItem(title: "Catalogue", action: nil, keyEquivalent: "")
            catalogue.submenu = main.catalogueMenu
            m.addItem(catalogue)
            add(m, "Sync Now", #selector(LibraryController.syncNow), "s", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "Export\u{2026}", #selector(MainWindowController.exportShown), "e", main)
            add(m, "Export Design Pack\u{2026}", #selector(MainWindowController.exportDesignPack), "e", main, [.command, .option])
            add(m, "Add to macOS Colour Panel", #selector(MainWindowController.addShownToColourPanel), "", main)
            m.addItem(adobeMenuItem(target: main, action: #selector(MainWindowController.addShownToAdobe(_:))))
            add(m, "Export Library\u{2026}", #selector(LibraryController.exportLibrary), "e", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "Import from MMFFDev Colour 2", #selector(LibraryController.importFromV2), "", library)
        }
        menu("Edit") { m in
            add(m, "Cut", #selector(NSText.cut(_:)), "x")
            add(m, "Copy", #selector(NSText.copy(_:)), "c")
            add(m, "Paste", #selector(NSText.paste(_:)), "v")
            add(m, "Select All", #selector(NSText.selectAll(_:)), "a")
            m.addItem(.separator())
            add(m, "Find", #selector(MainWindowController.focusSearch), "f", main)
        }
        menu("View") { m in
            add(m, "All Swatches", #selector(MainWindowController.showAll), "0", main)
            add(m, "Colour Lab", #selector(MainWindowController.showLab), "l", main)
            add(m, "Contrast", #selector(MainWindowController.showContrast), "l", main, [.command, .shift])
            add(m, "Next Palette", #selector(MainWindowController.nextPalette), "]", main)
            add(m, "Previous Palette", #selector(MainWindowController.previousPalette), "[", main)
            m.addItem(.separator())
            add(m, "Show Sidebar", #selector(MainWindowController.toggleSidebarPane), "s", main, [.command, .control])
            add(m, "Show History", #selector(MainWindowController.toggleHistory), "y", main, [.command, .shift])
            m.addItem(.separator())
            add(m, "Lighter Background", #selector(MainWindowController.lighterBackground), "]", main)
            add(m, "Darker Background", #selector(MainWindowController.darkerBackground), "[", main)
            add(m, "Step Background  (L)", #selector(MainWindowController.stepBackground), "", main)
            add(m, "Page Full Screen  (Shift-L)", #selector(MainWindowController.pageFullScreen), "", main)
            add(m, "Customise Toolbar\u{2026}", #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        }
        menu("Window") { m in
            add(m, "Minimise", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(m, "Zoom", #selector(NSWindow.performZoom(_:)))
            NSApp.windowsMenu = m
        }
        return bar
    }
}

// ---------- Entry point ----------

if CommandLine.arguments.contains("--self-test") {
    runSelfTest()
} else if CommandLine.arguments.contains("--write-project-files") {
    // Writes every project's file now, for scripts and for filling in projects made before the files existed.
    // "--catalogue <name>" picks a catalogue other than the current one.
    let args = CommandLine.arguments
    let named = args.firstIndex(of: "--catalogue").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    let controller = LibraryController(catalogue: named ?? Catalogues.currentName)
    controller.reload()
    controller.writeProjectFiles()
    for p in controller.library.orderedProjects { print(controller.projectFileURL(p.id)?.path ?? p.name) }
    exit(0)
} else if CommandLine.arguments.contains("--pick") {
    runPickMode()
} else if CommandLine.arguments.contains("--halo-demo") {
    runHaloDemo()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
