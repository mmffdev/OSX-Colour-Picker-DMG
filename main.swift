import AppKit
#if !APPSTORE
import Sparkle
#endif

// ---------- Pick mode (hotkey-triggered) ----------

func runPickMode() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    FolderAccess.restoreAll()

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
    lazy var library = LibraryController()
    /// Sparkle: checks the feed named in Info.plist once a day and offers what it finds. Only started inside
    /// a bundle; the bare binary Xcode runs from the build folder has no feed and no bundle to update.
    #if !APPSTORE
    lazy var updater = SPUStandardUpdaterController(startingUpdater: Bundle.main.bundleURL.pathExtension == "app",
                                                    updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    var main: MainWindowController?
    var settings: SettingsWindowController?
    private var splash: SplashWindowController?
    private var setupWindow: NSWindowController?
    private var opening = true
    private var firstOpen = false

    /// The standard About panel, with the credit the colour name list's licence asks for.
    @objc func showAbout() {
        let credit = NSAttributedString(string: colourNamesCredit, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credit])
    }

    @objc func showSettings() {
        // In the Studio window, Settings is a page of its own; the old panels wait for their redesign.
        if let studio = StudioWindowController.shared, studio.window?.isVisible == true { studio.frame.go(.settings); return }
        if settings == nil { settings = SettingsWindowController(library: library) }
        settings?.refresh()
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        let startupMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: Brand.name)
        appMenu.addItem(withTitle: "Quit \(Brand.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; startupMenu.addItem(appItem); NSApp.mainMenu = startupMenu
        FolderAccess.restoreAll()   // the Store build: folders the user chose before stay reachable
        #if APPSTORE
        Store.start()
        #endif
        _ = ScreenAccess.grantedAtLaunch   // read now: macOS applies a grant only to a copy started after it
        // Keep the first-open decision: the wizard marks itself complete before the Studio journey starts.
        firstOpen = !Prefs.assistantDone
        if firstOpen && !preferences.bool(forKey: "permissionsOffered") {
            PermissionGate.show([.screenRecording], screenRecording: true) { [weak self] in self?.openUp() }
        } else if DocumentsAccess.neededAtLaunch || CommandLine.arguments.contains("--gate") {
            PermissionGate.show([Permission.documents]) { [weak self] in self?.openUp() }
        } else {
            openUp()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether this Mac had no catalogue at all when the app opened, read before the library seeds Main at the root.
    private var noCatalogueAtLaunch = false

    /// After the wizard: animated artwork, then the Studio setup journey, then the app.
    private func openUp() {
        noCatalogueAtLaunch = Catalogues.standard.isEmpty
        let splash = SplashWindowController()
        self.splash = splash
        // With no launch artwork the window must exist before the reveal, which comes straight back.
        if !Prefs.splash && !firstOpen { prepareMainWindow() }
        splash.present { [weak self] in
            guard let self = self else { return }
            if self.firstOpen { self.showSetupJourney() } else { self.revealMainWindow() }
        }
        // Let the launch artwork reach the screen before loading the library and editor.
        if Prefs.splash && !firstOpen { DispatchQueue.main.async { [weak self] in self?.prepareMainWindow() } }
    }

    /// One setup surface: locations, the existing nested choices, then a final review/build.
    @objc func runSetupAssistant() { showSetupJourney() }
    @objc func learnHalo() { SetupAssistant.show(from: SetupAssistant.Step.halo) { _ in } }

    private func showSetupJourney() {
        if let existing = setupWindow { existing.showWindow(nil); return }
        let frame = StudioSplash(library: library, startup: true)
        let window = StudioWindow(contentRect: NSRect(origin: .zero, size: Design.App.size),
                                  styleMask: [.resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Set Up Colorgain"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Design.paper
        window.minSize = Design.App.least
        window.contentView = frame
        window.center()
        let controller = NSWindowController(window: window)
        setupWindow = controller
        frame.onDone = { [weak self, weak window] in
            guard let self = self else { return }
            window?.orderOut(nil)
            self.firstOpen = false
            if self.main == nil { self.prepareMainWindow() }
            self.revealMainWindow()
            self.setupWindow = nil
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        frame.begin()
        splash?.close(); splash = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    private func prepareMainWindow() {
        library.watchPrintCondition()
        let main = MainWindowController(library: library)
        self.main = main
        let bar = menus(for: main)
        Shortcuts.install(on: bar)   // before macOS adds its own items to the Edit menu
        NSApp.mainMenu = bar
    }

    private func revealMainWindow() {
        guard let main = main else { return }
        // The Studio window, Colorgain's own, is the window; the old one opens only with --classic, for the few pages not yet redrawn.
        if CommandLine.arguments.contains("--classic") { main.showWindow(nil) } else { StudioWindowController.show(library: library) }
        opening = false
        splash?.close()
        splash = nil
        NSApp.activate(ignoringOtherApps: true)
        if Permission.all.isEmpty { Prefs.setupDone = true }   // nothing to ask: the Store build
        else if !Prefs.setupDone, let w = main.window, w.isVisible { SetupWindowController.show(over: w) }   // the old window only, never dragged into view for a sheet
        DispatchQueue.main.async { self.library.sync() } // on open: look for changes from the other Mac
        rehearse(main)
        // No catalogue on this Mac, the setup skipped or every one removed, and nothing seeded from an earlier
        // version either: nothing works without one, so it is asked for now.
        // On a first open the startup splash over the Studio window is what sets the catalogue up, so nothing is asked here.
        let lib = library.library
        if Prefs.assistantDone && noCatalogueAtLaunch && lib.colours.isEmpty && lib.swatches.isEmpty && lib.projects.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.askForCatalogue() }
        }
    }

    /// The word that there is no catalogue, with one way on: the assistant from its Catalogue step, which makes one.
    private func askForCatalogue() {
        SwissConfirm.require(over: NSApp.keyWindow ?? NSApp.mainWindow, title: "No Catalogue Yet",
                             note: "Colorgain keeps everything, colours, palettes and members, in a catalogue, and there is none on this Mac. Make one now: its name, where it lives and how it is organised.",
                             action: "Create Catalogue") { [weak self] in
            SetupAssistant.show(from: SetupAssistant.Step.catalogue) { name in
                guard let self = self else { return }
                if name != self.library.catalogue { self.library.open(catalogue: name) } else { self.library.reload() }
                // The empty Main the launch seeded at the root is not wanted beside the catalogue just made.
                if name != Catalogues.mainName { Catalogues.standard.dropEmptyMain() }
            }
        }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { !opening }

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

        menu(Brand.name) { m in
            add(m, "About \(Brand.name)", #selector(showAbout), "", self)
            add(m, "Set Up A Catalogue\u{2026}", #selector(runSetupAssistant), "", self)
            add(m, "Learn The Halo\u{2026}", #selector(learnHalo), "", self)
            #if !APPSTORE
            add(m, "Check for Updates\u{2026}", #selector(SPUStandardUpdaterController.checkForUpdates(_:)), "", updater)
            #endif
            m.addItem(.separator())
            add(m, "Settings\u{2026}", #selector(showSettings), ",", self)
            m.addItem(.separator())
            add(m, "Hide \(Brand.name)", #selector(NSApplication.hide(_:)), "h")
            add(m, "Quit \(Brand.name)", #selector(NSApplication.terminate(_:)), "q")
        }
        menu("File") { m in
            add(m, "Pick Colours", #selector(LibraryController.togglePicking), "p", library)
            add(m, "Sample An Area", #selector(LibraryController.sampleArea), "P", library)
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
            add(m, "Export Palette File\u{2026}", #selector(MainWindowController.exportShownPaletteFile), "", main)
            add(m, "Export Design Pack\u{2026}", #selector(MainWindowController.exportDesignPack), "e", main, [.command, .option])
            add(m, "Add to macOS Colour Panel", #selector(MainWindowController.addShownToColourPanel), "", main)
            m.addItem(adobeMenuItem(target: main, action: #selector(MainWindowController.addShownToAdobe(_:))))
            add(m, "Export Library\u{2026}", #selector(LibraryController.exportLibrary), "e", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "Import Palette Files\u{2026}", #selector(MainWindowController.importPaletteFilesShown), "", main)
            add(m, "Import CSS Tokens\u{2026}", #selector(MainWindowController.importTokensShown), "", main)
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
            add(m, "Next Background  (L)", #selector(MainWindowController.stepBackground), "", main)
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

// --new-user: a first open, clean, as a brand-new user sees it. Tick it in Xcode under Product ▸
// Scheme ▸ Edit Scheme ▸ Run ▸ Arguments; tools/open.sh new passes it to the installed app. A throwaway
// home and settings of its own, wiped on every such launch, so your own catalogues are never touched.
// Set before anything reads the preferences, which pick their domain from MMFFDEV_COLOUR3_HOME.
if CommandLine.arguments.contains("--new-user") {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("colorgain-new-user")
    let trial = UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3.trial")!
    let resuming = CommandLine.arguments.contains("--resume-new-user") || trial.bool(forKey: "resumeNewUserAfterDebuggerRestart")
    trial.removeObject(forKey: "resumeNewUserAfterDebuggerRestart")
    if !resuming { try? fm.removeItem(at: home) }
    try? fm.createDirectory(at: home, withIntermediateDirectories: true)
    if !resuming { UserDefaults.standard.removePersistentDomain(forName: "com.mmffdev.mmffdevcolour3.trial") }
    setenv("MMFFDEV_COLOUR3_HOME", home.path, 1)
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTest()
} else if CommandLine.arguments.contains("--write-project-files") {
    // Writes every project's file now, for scripts and for filling in projects made before the files existed.
    // "--catalogue <name>" picks a catalogue other than the current one.
    let args = CommandLine.arguments
    let named = args.firstIndex(of: "--catalogue").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    let controller = LibraryController(catalogue: named ?? Catalogues.currentName)
    controller.reload()
    for p in controller.library.orderedProjects { print(controller.memberFolderURL(p.id)?.path ?? p.name) }
    exit(0)
} else if let at = CommandLine.arguments.firstIndex(of: "--bring-across"), CommandLine.arguments.indices.contains(at + 1) {
    // Brings the catalogue in the given folder across to the catalogue file of version 3, with its backup beside it, and says
    // what is there afterwards. For checking a copy of a catalogue before the app opens the real one: never run on a folder
    // the app has open.
    let dir = URL(fileURLWithPath: CommandLine.arguments[at + 1])
    let store = LibraryStore(directory: dir, legacyURL: nil, name: CatalogueFiles.anyIndex(in: dir)?.deletingPathExtension().lastPathComponent ?? dir.lastPathComponent)
    do {
        let lib = try store.load()
        if let r = store.takeMigration() { print("brought across: \(r.members) members, \(r.palettes) palettes; backup at \(r.backup.path)") } else { print("already version 3: nothing brought across") }
        print("collections: \(store.schema.collections.map { $0.name })")
        print("members: \(lib.projects.map { $0.name })")
        print("palettes: \(lib.swatches.count), of which in the Library: \(lib.palettes(in: nil).count); colours: \(lib.colours.count)")
        for n in store.notes { print("note: \(n)") }
        exit(0)
    } catch { print("could not bring it across: \(error.localizedDescription)"); exit(1) }
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
