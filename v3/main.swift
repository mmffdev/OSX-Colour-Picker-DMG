import AppKit

// ---------- Pick mode (hotkey-triggered) ----------

func runPickMode() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let sampler = NSColorSampler()
    let semaphore = DispatchSemaphore(value: 0)
    var picked: String?

    sampler.show { color in
        defer { semaphore.signal() }
        guard let color = color, let hex = hexOf(color) else { return }
        playShutter()
        copyToClipboard(Prefs.copyText(hex))
        do {
            try LibraryStore.standard.mutate { $0.addPick(hex) }
        } catch {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        }
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
        let main = MainWindowController(library: library)
        self.main = main
        let bar = menus(for: main)
        Shortcuts.install(on: bar)   // before macOS adds its own items to the Edit menu
        NSApp.mainMenu = bar
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { self.library.sync() } // on open: look for changes from the other Mac
        rehearse(main)
    }

    /// For checking screens during a trial run (MMFFDEV_COLOUR3_HOME set): MMFFDEV_COLOUR3_SHOW may be
    /// "palette:<name>", "build:<hex>,<hex>", "settings:<panel number>", "search:<text>", "labels", "lab", "lab:<hex>", "tags", "tags:bar=<typed text>", "project:new" or "project:templates". Ignored otherwise.
    private func rehearse(_ main: MainWindowController) {
        let env = ProcessInfo.processInfo.environment
        guard env["MMFFDEV_COLOUR3_HOME"] != nil, let ask = env["MMFFDEV_COLOUR3_SHOW"] else { return }
        let parts = ask.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch parts[0] {
            case "palette":
                if let s = self.library.library.swatches.first(where: { $0.name == arg }) { main.show(.palette(s.id)) }
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
            m.addItem(.separator())
            add(m, "Settings\u{2026}", #selector(showSettings), ",", self)
            m.addItem(.separator())
            add(m, "Hide MMFFDev Colour 3", #selector(NSApplication.hide(_:)), "h")
            add(m, "Quit MMFFDev Colour 3", #selector(NSApplication.terminate(_:)), "q")
        }
        menu("File") { m in
            add(m, "Pick Colours", #selector(LibraryController.togglePicking), "p", library)
            m.addItem(.separator())
            add(m, "New Palette", #selector(LibraryController.newPalette), "n", library)
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
            add(m, "cLab", #selector(MainWindowController.showLab), "l", main)
            add(m, "Next Palette", #selector(MainWindowController.nextPalette), "]", main)
            add(m, "Previous Palette", #selector(MainWindowController.previousPalette), "[", main)
            m.addItem(.separator())
            add(m, "Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", nil, [.command, .control])
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
