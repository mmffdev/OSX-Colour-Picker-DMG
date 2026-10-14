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
    private var workspaceStartup: WorkspaceStartupController?
    private var pendingWorkspace: URL?
    private var didLaunch = false

    /// The standard About panel, with the credit the colour name list's licence asks for.
    @objc func showAbout() {
        let credit = NSAttributedString(string: colourNamesCredit, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
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
        installStartupMenu()
        FolderAccess.restoreAll()   // the Store build: folders the user chose before stay reachable
        #if APPSTORE
        Store.start()
        #endif
        _ = ScreenAccess.grantedAtLaunch   // read now: macOS applies a grant only to a copy started after it
        didLaunch=true
        showWorkspaceChooser(selection:pendingWorkspace)
        NSApp.activate(ignoringOtherApps:true)
    }

    /// Resolve app data and catalogue availability before constructing LibraryController or seeding any catalogue.
    private func showWorkspaceChooser(selection: URL? = nil) {
        opening=true
        installStartupMenu()
        if let workspaceStartup {
            workspaceStartup.showWindow(nil)
            if let selection { workspaceStartup.content.initialSelection=selection;workspaceStartup.content.start() }
            return
        }
        let args=CommandLine.arguments
        let requested=selection ?? args.firstIndex(of:"--workspace").flatMap { args.indices.contains($0+1) ? URL(fileURLWithPath:args[$0+1]) : nil }
        let controller=WorkspaceStartupController(root:FolderAccess.held[Catalogues.standard.root.standardizedFileURL.path] ?? Catalogues.standard.root,selection:requested,ready: { [weak self] root,entry in
            self?.openWorkspace(root:root,name:entry.name,id:entry.id)
        },create: { [weak self] root,name in
            guard let self else { return }
            do {
                try AppDataStore(root:root).update { manifest in
                    var settings=manifest["settings"] as? [String:Any] ?? [:]
                    settings[Catalogues.currentKey]=name
                    let id=WorkspaceInventory.probe(name:name,folder:root.appendingPathComponent("Catalogues").appendingPathComponent(name)).id?.uuidString
                    if let id { settings["currentCatalogueID"]=id }
                    var preferred: [String:Any] = ["name":name]
                    if let id { preferred["id"]=id }
                    manifest["defaultCatalogue"]=preferred
                    settings["assistantDone"]=false;settings["setupDone"]=false
                    manifest["settings"]=settings
                }
            } catch { NSApp.presentError(error);return }
            self.prepareWorkspace(root:root,name:name)
            self.showSetupJourney(workspacePrepared:true,createdCatalogue:name)
            self.workspaceStartup?.finishClosing();self.workspaceStartup=nil
        },cancel: { [weak self] in
            guard let self else { return }
            self.workspaceStartup=nil
            if let main=self.main {
                NSApp.mainMenu=self.menus(for:main);Shortcuts.install(on:NSApp.mainMenu!)
                StudioWindowController.shared?.showWindow(nil);self.opening=false
            } else if let setup=self.setupWindow { setup.showWindow(nil) }
            else { NSApp.terminate(nil) }
        })
        controller.content.onWorkspaceSelected = { [weak self] root in
            if self?.main == nil && self?.setupWindow == nil { Catalogues.home=root }
        }
        workspaceStartup=controller;controller.start()
    }

    private func prepareWorkspace(root:URL,name:String) {
        if main != nil {
            library.finishWorkspaceSession()
            StudioWindowController.closeWorkspace();main?.close();main=nil
            settings?.close();settings=nil
        }
        setupWindow?.close();setupWindow=nil
        Catalogues.home=root
        library=LibraryController(catalogue:name)
        library.reload()
    }

    private func openWorkspace(root:URL,name:String,id:UUID?) {
        do {
            try AppDataStore(root:root).update { manifest in
                var settings=manifest["settings"] as? [String:Any] ?? [:]
                settings[Catalogues.currentKey]=name
                settings["currentCatalogueID"]=id?.uuidString
                var preferred: [String:Any] = ["name":name]
                if let id { preferred["id"]=id.uuidString }
                manifest["defaultCatalogue"]=preferred
                settings["assistantDone"]=true;settings["setupDone"]=true
                manifest["settings"]=settings
            }
        } catch { NSApp.presentError(error);return }
        prepareWorkspace(root:root,name:name)
        openUp()
        workspaceStartup?.finishClosing();workspaceStartup=nil
    }

    private func openUp() {
        #if APPSTORE
        AppleMenubar.shared.bind(to: library) {
            StudioWindowController.shared?.showWindow(nil)
            StudioWindowController.shared?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
        let splash=SplashWindowController();self.splash=splash
        if !Prefs.splash { prepareMainWindow() }
        splash.present { [weak self] in self?.revealMainWindow() }
        if Prefs.splash { DispatchQueue.main.async { [weak self] in self?.prepareMainWindow() } }
    }

    func application(_ application:NSApplication,open urls:[URL]) {
        guard let url=urls.first else { return }
        pendingWorkspace=url
        if didLaunch { showWorkspaceChooser(selection:url) }
    }

    private func installStartupMenu() {
        let bar=NSMenu(),item=NSMenuItem(),menu=NSMenu(title:Brand.name)
        let open=NSMenuItem(title:"Open Workspace…",action:#selector(runSetupAssistant),keyEquivalent:"o")
        open.target=self;menu.addItem(open);menu.addItem(.separator())
        menu.addItem(withTitle:"Quit \(Brand.name)",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=menu;bar.addItem(item);bar.addItem(developmentMenu());NSApp.mainMenu=bar
    }

    private func developmentMenu() -> NSMenuItem {
        let item=NSMenuItem(title:"Development",action:nil,keyEquivalent:"")
        let menu=NSMenu(title:"Development")
        let toggle=NSMenuItem(title:"Resume Workspace Automatically",action:#selector(toggleDevelopment(_:)),keyEquivalent:"")
        toggle.target=self;toggle.state=DevelopmentLaunch.enabled ? .on : .off
        toggle.toolTip="Remembered on this Mac. Resume only a completed workspace whose last catalogue validates."
        menu.addItem(toggle);item.submenu=menu;return item
    }
    @objc private func toggleDevelopment(_ sender:NSMenuItem) {
        DevelopmentLaunch.setEnabled(!DevelopmentLaunch.enabled);sender.state=DevelopmentLaunch.enabled ? .on : .off
    }

    /// One setup surface: locations, the existing nested choices, then a final review/build.
    @objc func runSetupAssistant() { showWorkspaceChooser() }
    @objc func learnHalo() { SetupAssistant.show(from: SetupAssistant.Step.halo) { _ in } }

    private func showSetupJourney(workspacePrepared:Bool = false,createdCatalogue:String? = nil) {
        if let existing = setupWindow { existing.showWindow(nil); return }
        let frame = StudioSplash(library: library, startup: true,workspacePrepared:workspacePrepared,createdCatalogue:createdCatalogue)
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
            Catalogues.currentName=self.library.catalogue
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

    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        if !hasVisibleWindows {
            if let studio=StudioWindowController.shared,main != nil { studio.showWindow(nil);studio.window?.makeKeyAndOrderFront(nil) }
            else { showWorkspaceChooser() }
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool {
        #if APPSTORE
        return false // The menu tools remain available; Quit is explicit.
        #else
        return !opening
        #endif
    }

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
            add(m, "Open Workspace\u{2026}", #selector(runSetupAssistant), "", self)
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
            add(m, "Open Workspace\u{2026}", #selector(runSetupAssistant), "o", self)
            m.addItem(.separator())
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
        menu("Help") { m in
            NSApp.helpMenu = m
            let guide = NSMenuItem(title: "Colorgain Help", action: nil, keyEquivalent: "")
            guide.isEnabled = false
            guide.toolTip = "The macOS Help book is being prepared."
            m.addItem(guide)
        }
        bar.addItem(developmentMenu())
        return bar
    }
}

// ---------- Entry point ----------

// --new-user: a first open, clean, as a brand-new user sees it. Tick it in Xcode under Product ▸
// Scheme ▸ Edit Scheme ▸ Run ▸ Arguments; tools/open.sh new passes it to the installed app. A throwaway
// home and settings of its own, wiped on every such launch, so your own catalogues are never touched.
// Set before anything reads the preferences, which pick their domain from MMFFDEV_COLOUR3_HOME.
if !CommandLine.arguments.contains("--self-test") { DevelopmentLaunch.configure(Array(CommandLine.arguments.dropFirst())) }

if CommandLine.arguments.contains("--new-user") {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("colorgain-new-user")
    let trial = UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3.trial")!
    let resuming = CommandLine.arguments.contains("--resume-new-user") || DevelopmentLaunch.enabled || trial.bool(forKey: "resumeNewUserAfterDebuggerRestart")
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
