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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        FileEditAccess.releaseOwned()
        StudioWindowController.shared?.frame.saveWorkspaceSession(flush:true)
        if main != nil || StudioWindowController.shared != nil {library.finishWorkspaceSession()}
        FileHandlerNativeQA.cleanup()
    }
    lazy var library = LibraryController()
    /// Sparkle: checks the feed named in Info.plist once a day and offers what it finds. Only started inside
    /// a bundle; the bare binary Xcode runs from the build folder has no feed and no bundle to update.
    #if !APPSTORE
    lazy var updater = SPUStandardUpdaterController(startingUpdater: Bundle.main.bundleURL.pathExtension == "app",
                                                    updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    var main: MainWindowController?
    private let classicMenuSentinel=NSObject()
    private var classicMenuActions:[ObjectIdentifier:Selector]=[:]
    private let lazyCatalogueMenu=NSMenu(title:"Catalogue")
    var settings: SettingsWindowController?
    private var splash: SplashWindowController?
    private var setupWindow: NSWindowController?
    private var simpleSetup: SimpleSetupController?
    private var opening = true
    private var workspaceStartup: WorkspaceStartupController?
    private var pendingWorkspace: URL?
    private var pendingDocuments: [URL] = []
    private var didLaunch = false
    private var libraryPrepared=false

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
    @objc func showMetadataSettings() {
        showSettings()
        settings?.showMetadata()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        SwissBlockTextField.installGlobalCursor()
        NSApp.setActivationPolicy(.regular)
        installStartupMenu()
        FolderAccess.restoreAll()   // the Store build: folders the user chose before stay reachable
        #if APPSTORE
        Store.start()
        #endif
        _ = ScreenAccess.grantedAtLaunch   // read now: macOS applies a grant only to a copy started after it
        didLaunch=true
        let initialWorkspace = pendingWorkspace; pendingWorkspace = nil
        if preferences.bool(forKey:SimpleSetupController.requestKey) || initialWorkspace == nil && !FileManager.default.fileExists(atPath:AppDataStore(root:Catalogues.standard.root).url.path) {
            showSimpleSetup()
        } else { showWorkspaceChooser(selection: initialWorkspace) }
        NSApp.activate(ignoringOtherApps:true)
    }

    /// Resolve app data and catalogue availability before constructing LibraryController or seeding any catalogue.
    private func showWorkspaceChooser(selection: URL? = nil, chooseWorkspace: Bool = false) {
        opening=true
        installStartupMenu()
        if let workspaceStartup {
            workspaceStartup.showWindow(nil)
            if let selection { workspaceStartup.content.initialSelection=selection;workspaceStartup.content.start() }
            else if chooseWorkspace { workspaceStartup.content.showWorkspaceSelection() }
            return
        }
        let args=CommandLine.arguments
        let requested=selection ?? args.firstIndex(of:"--workspace").flatMap { args.indices.contains($0+1) ? URL(fileURLWithPath:args[$0+1]) : nil }
        let controller=WorkspaceStartupController(root:FolderAccess.held[Catalogues.standard.root.standardizedFileURL.path] ?? Catalogues.standard.root,selection:requested,ready: { [weak self] root,entry in
            self?.openWorkspace(root:root,name:entry.name,id:entry.id)
        },create: { [weak self] root,name in
            guard let self else{return}
            self.workspaceStartup?.finishClosing();self.workspaceStartup=nil
            self.showSimpleSetup(home:root,name:name)
        },cancel: { [weak self] in
            guard let self else { return }
            self.workspaceStartup=nil
            if self.main != nil || StudioWindowController.shared != nil {
                NSApp.mainMenu=self.menus(for:self.classicMenuSentinel);Shortcuts.install(on:NSApp.mainMenu!)
                StudioWindowController.shared?.showWindow(nil);self.opening=false
            } else if let setup=self.setupWindow { setup.showWindow(nil) }
            else { NSApp.terminate(nil) }
        })
        controller.content.onWorkspaceSelected = { [weak self] root in
            if self?.main == nil && StudioWindowController.shared == nil && self?.setupWindow == nil { Catalogues.home=root }
        }
        workspaceStartup=controller;controller.start(chooseWorkspace: chooseWorkspace)
    }

    private func prepareWorkspace(root:URL,name:String) {
        if main != nil || StudioWindowController.shared != nil {
            library.finishWorkspaceSession()
            StudioWindowController.closeWorkspace();main?.close();main=nil
            settings?.close();settings=nil
        }
        setupWindow?.close();setupWindow=nil
        Catalogues.home=root
        library=LibraryController(catalogue:name)
        library.reload()
        libraryPrepared=true
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
        AppleMenubar.shared.bind(to: library) {
            StudioWindowController.shared?.showWindow(nil)
            StudioWindowController.shared?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        let splash=SplashWindowController();self.splash=splash
        if !Prefs.splash { prepareMainWindow() }
        splash.present { [weak self] in self?.revealMainWindow() }
        if Prefs.splash { DispatchQueue.main.async { [weak self] in self?.prepareMainWindow() } }
    }

    func application(_ application:NSApplication,open urls:[URL]) {
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if ["coldata", "colcat"].contains(url.pathExtension.lowercased()) || values?.isDirectory == true {
                if pendingWorkspace == nil { pendingWorkspace = url }
                else { pendingDocuments.append(url) }
            } else { pendingDocuments.append(url) }
        }
        if didLaunch {
            if let url = pendingWorkspace { pendingWorkspace = nil; showWorkspaceChooser(selection: url) }
            else { openPendingDocument() }
        }
    }

    @objc private func openPendingDocument() {
        guard let window = StudioWindowController.shared?.window ?? main?.window, let view = window.contentView,
              let url = pendingDocuments.first else { return }
        let modal = SwissFocusModal(title: "Open Document", message: "\(url.lastPathComponent)\n\(pendingDocuments.count) document(s) waiting. Remaining files stay queued under Open Remaining Documents in the app menu.")
        modal.button("Review Document", primary: true) {
            self.pendingDocuments.removeFirst(); modal.dismissOverlay()
            do {
                let ext = url.pathExtension.lowercased()
                if ["colshr", "colshare", "zip"].contains(ext) { StudioWindowController.shared?.frame.startImport(url: url) }
                else if ext == "collib" { MyLibraryFile.reviewImport(url,library:self.library,over:view) }
                else if ext == "colqr" { QRSharing.review(try ColourQR.document(Handler_File_Manager.shared.read(url)), library: self.library, over: view) }
                else if ["colcat", "coldata"].contains(ext) || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { self.showWorkspaceChooser(selection: url) }
                else if ["colpal", "colpalette", "coltyp", "colswatch"].contains(ext) {
                    let bytes = try Handler_File_Manager.shared.read(url)
                    let imported: ImportedPalette
                    if ext == "colswatch" {
                        let document = try SwatchDocument.read(bytes)
                        let swatch = Swatch(id: UUID(), name: document.name, createdAt: Date(), entries: [document.entry])
                        let palette = PaletteDocument(project: nil, palette: swatch, colours: [document.colour])
                        guard let decoded = PaletteImport.paletteDocument(try ColourFiles.encoder().encode(palette)) else { throw failure("This swatch could not be decoded.") }
                        imported = decoded
                    } else {
                        guard let decoded = PaletteImport.paletteDocument(bytes) else { throw failure("This palette could not be decoded.") }
                        imported = decoded
                    }
                    let confirm = SwissFocusModal(title: "Import Palette?", message: "Add “\(imported.name)” with \(imported.colours.count) colours to the current catalogue. The original file is retained.")
                    confirm.button("Import Palette", primary: true) {
                        if self.library.apply("Import Palette", { _ = $0.merge([imported], into: nil) }) { confirm.dismissOverlay(); self.openPendingDocument() }
                    }
                    confirm.button("Cancel") { confirm.dismissOverlay(); self.openPendingDocument() }; confirm.present(over: view)
                } else if ["colpro", "colcal", "colkeys"].contains(ext) {
                    let bytes = try Handler_File_Manager.shared.read(url)
                    let confirm = SwissFocusModal(title: "Import Document?", message: "Add “\(url.lastPathComponent)” to this workspace. The original is retained. A keyboard profile is added without changing your active shortcuts.")
                    confirm.button("Import Document", primary: true) {
                        do {
                            try Handler_File_Manager.shared.withTransaction(home: Catalogues.standard.root) {
                                if ext == "colpro" { _ = try SavedPrintProfiles.importProfile(bytes) }
                                else if ext == "colcal" { _ = try ProofConfigurationStore.save(ProofConfiguration.decode(bytes), root: self.library.store.root) }
                                else { _ = try KeyProfiles.copyIn(ColourFiles.decoder().decode(KeyProfile.self, from: bytes)) }
                            }
                            confirm.dismissOverlay(); self.openPendingDocument()
                        } catch { FileRecoveryPresenter.showFailure(error, over: window) }
                    }
                    confirm.button("Cancel") { confirm.dismissOverlay(); self.openPendingDocument() }; confirm.present(over: view)
                } else {
                    throw failure("This file is managed inside a catalogue. Use its matching Import or Locate action in Colorgain. The original is unchanged: " + url.path)
                }
            } catch { FileRecoveryPresenter.showFailure(error, over: window) }
        }
        modal.button("Skip This Document") { self.pendingDocuments.removeFirst(); modal.dismissOverlay(); self.openPendingDocument() }
        modal.button("Keep For Later") { modal.dismissOverlay() }; modal.present(over: view)
    }

    private func installStartupMenu() {
        let bar=NSMenu(),item=NSMenuItem(),menu=NSMenu(title:Brand.name)
        let open=NSMenuItem(title:"Open Workspace…",action:#selector(runSetupAssistant),keyEquivalent:"o")
        open.target=self;menu.addItem(open);menu.addItem(.separator())
        menu.addItem(withTitle:"Quit \(Brand.name)",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=menu;bar.addItem(item)
        let helpItem=NSMenuItem();let helpMenu=Help_Handler.shared.menu();helpItem.submenu=helpMenu;bar.addItem(helpItem);NSApp.helpMenu=helpMenu
        bar.addItem(developmentMenu());NSApp.mainMenu=bar
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
    @objc func runSetupAssistant() { showWorkspaceChooser(chooseWorkspace: true) }
    @objc func showCatalogueStructure() {
        showSettings();settings?.showPanel(5)
    }
    @objc func fileCreatorDetails() { if let window = StudioWindowController.shared?.window ?? main?.window { FileRecoveryPresenter.creatorDetails(over: window) } }
    @objc func learnHalo() { SetupAssistant.show(from: SetupAssistant.Step.halo) { _ in } }
    @objc func editSelectedMetadata(){StudioWindowController.shared?.frame.editMetadata()}

    func showSimpleSetup(home:URL?=nil,name:String="") {
        if let simpleSetup {simpleSetup.showWindow(nil);return}
        StudioWindowController.shared?.frame.saveWorkspaceSession(flush:true)
        let wizard=SimpleSetupController(home:home,name:name,done:{[weak self] made in
            guard let self else{return};self.simpleSetup=nil
            self.openWorkspace(root:made.home,name:made.name,id:made.id)
        },cancel:{[weak self] in self?.simpleSetup=nil;self?.showWorkspaceChooser(chooseWorkspace:true)},openExisting:{[weak self] url in self?.simpleSetup=nil;self?.showWorkspaceChooser(selection:url)})
        simpleSetup=wizard;wizard.showWindow(nil);wizard.window?.makeKeyAndOrderFront(nil)
    }

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
        if !libraryPrepared{library.reload();libraryPrepared=true}
        let bar = menus(for: classicMenuSentinel)
        Shortcuts.install(on: bar)   // before macOS adds its own items to the Edit menu
        NSApp.mainMenu = bar
    }

    private func classicWindow() -> MainWindowController {
        if let main{return main}
        let studioWindow=StudioWindowController.shared?.window
        let made=MainWindowController(library:library)
        main=made
        if let studioWindow{library.window=studioWindow}
        return made
    }
    @objc private func forwardClassicMenu(_ sender:NSMenuItem) {
        guard let action=classicMenuActions[ObjectIdentifier(sender)] else{return}
        _ = NSApp.sendAction(action,to:classicWindow(),from:sender)
    }
    private func routeClassicMenuItems(_ menu:NSMenu) {
        for item in menu.items {
            if item.target === classicMenuSentinel,let action=item.action {
                classicMenuActions[ObjectIdentifier(item)]=action
                item.target=self;item.action=#selector(forwardClassicMenu(_:))
            }
            if let submenu=item.submenu{routeClassicMenuItems(submenu)}
        }
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        guard menu === lazyCatalogueMenu else{return}
        menu.removeAllItems()
        for name in library.availableCatalogues() {
            let item=menu.addItem(withTitle:name,action:#selector(catalogueChosen(_:)),keyEquivalent:"")
            item.target=self;item.state=name == library.catalogue ? .on:.off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle:"New Catalogue…",action:#selector(LibraryController.newCatalogue),keyEquivalent:"").target=library
        menu.addItem(withTitle:"Rename \(library.catalogue)…",action:#selector(LibraryController.renameCatalogue),keyEquivalent:"").target=library
        menu.addItem(withTitle:"Open Catalogue File…",action:#selector(LibraryController.openCatalogueFile),keyEquivalent:"").target=library
    }
    @objc private func catalogueChosen(_ item:NSMenuItem){library.open(catalogue:item.title)}

    private func revealMainWindow() {
        // The Studio window, Colorgain's own, is the window; the old one opens only with --classic, for the few pages not yet redrawn.
        if CommandLine.arguments.contains("--classic") { classicWindow().showWindow(nil) } else { StudioWindowController.show(library: library) }
        opening = false
        splash?.close()
        splash = nil
        NSApp.activate(ignoringOtherApps: true)
        if Permission.all.isEmpty { Prefs.setupDone = true }   // nothing to ask: the Store build
        else if !Prefs.setupDone, let w = main?.window, w.isVisible { SetupWindowController.show(over: w) }   // the old window only, never dragged into view for a sheet
        DispatchQueue.main.async { self.library.sync() } // on open: look for changes from the other Mac
        if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_SHOW"] != nil {rehearse(classicWindow())}
        openPendingDocument()
        FileHandlerNativeQA.present(library: library, window: StudioWindowController.shared?.window ?? main?.window)
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
        if let simpleSetup {simpleSetup.showWindow(nil);simpleSetup.window?.makeKeyAndOrderFront(nil);return false}
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

    private var assetImportMenu: WorkspaceImportMenu?
    private func menus(for main: AnyObject) -> NSMenu {
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
            add(m, "Open Remaining Documents\u{2026}", #selector(openPendingDocument), "", self)
            add(m, "File Creator Details\u{2026}", #selector(fileCreatorDetails), "", self)
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
        assetImportMenu = WorkspaceImportMenu(controller: library)
        assetImportMenu?.onWorkspace = { [weak self] url in self?.showWorkspaceChooser(selection: url) }
        menu("File") { m in
            add(m, "Open Workspace…", #selector(runSetupAssistant), "o", self)
            m.addItem(.separator())
            add(m, "Pick Colours", #selector(LibraryController.togglePicking), "p", library)
            add(m, "Sample An Area", #selector(LibraryController.sampleArea), "P", library)
            add(m, "New Colour…", #selector(LibraryController.newColour), "k", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "New Palette", #selector(LibraryController.newPalette), "n", library)
            add(m, "New Typography Palette", #selector(LibraryController.newTypography), "", library)
            add(m, "New Project…", #selector(LibraryController.newProject), "n", library, [.command, .option])
            add(m, "Project Templates…", #selector(LibraryController.manageProjectTemplates), "", library)
            add(m, "Build Palette from Swatches…", #selector(MainWindowController.buildPalette), "n", main, [.command, .shift])
            add(m, "New Palette from Image…", #selector(LibraryController.paletteFromImage), "i", library)
            add(m, "New Palette from Clipboard", #selector(LibraryController.paletteFromClipboard), "v", library, [.command, .shift])
            m.addItem(.separator())
            let catalogue = NSMenuItem(title: "Catalogue", action: nil, keyEquivalent: "")
            lazyCatalogueMenu.delegate=self
            catalogue.submenu = lazyCatalogueMenu
            m.addItem(catalogue)
            add(m, "Sync Now", #selector(LibraryController.syncNow), "s", library, [.command, .shift])
            m.addItem(.separator())
            add(m, "Export…", #selector(MainWindowController.exportShown), "e", main)
            add(m, "Export Palette File…", #selector(MainWindowController.exportShownPaletteFile), "", main)
            add(m, "Export Design Pack…", #selector(MainWindowController.exportDesignPack), "e", main, [.command, .option])
            add(m, "Add to macOS Colour Panel", #selector(MainWindowController.addShownToColourPanel), "", main)
            m.addItem(adobeMenuItem(target: main, action: #selector(MainWindowController.addShownToAdobe(_:))))
            add(m, "Export Library…", #selector(LibraryController.exportLibrary), "e", library, [.command, .shift])
            m.addItem(.separator())
            assetImportMenu?.appendImportItems(to: m)
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
        // These are additional routes. File retains its established commands and shortcuts.
        func planned(_ m: NSMenu, _ titles: [String]) {
            for title in titles {
                let item = NSMenuItem(title: "! " + title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = "Planned. This command is not connected yet."
                m.addItem(item)
            }
        }
        func group(_ m: NSMenu, _ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title); build(child); item.submenu = child; m.addItem(item)
        }
        func route(_ m: NSMenu, _ title: String, _ place: StudioFrame.Place) {
            m.addItem(ApplicationCommandItem(title, enabled: { StudioWindowController.shared != nil }) {
                StudioWindowController.shared?.frame.go(place)
            })
        }
        let assetFrame: () -> StudioFrame? = { StudioWindowController.shared?.frame.activeAssetFrame }
        let selectedPalettes: () -> [UUID] = { assetFrame()?.commandPalettes ?? [] }
        let editablePalette: () -> Bool = { assetFrame()?.canEditCommandPalettes == true }
        func paletteAction(_ m: NSMenu, _ title: String, editing: Bool = true, singleOnly: Bool = false, _ run: @escaping (UUID) -> Void) {
            m.addItem(ApplicationCommandItem(title, enabled: {
                let ids=selectedPalettes()
                return !ids.isEmpty && (!singleOnly || ids.count == 1) && (!editing || editablePalette())
            }) {
                let ids=selectedPalettes()
                for id in ids { run(id) }
            })
        }
        menu("Catalogue") { m in
            route(m, "Show Catalogue", .catalogue)
            route(m, "Manage Catalogues…", .settings)
            add(m, "New Catalogue…", #selector(LibraryController.newCatalogue), "", library)
            add(m, "Clients And Work Items…", #selector(showCatalogueStructure), "", self)
            add(m, "Rename Catalogue…", #selector(LibraryController.renameCatalogue), "", library)
            m.addItem(ApplicationCommandItem("Show Catalogue in Finder") { [weak library] in
                if let url = library?.store.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            })
            m.addItem(.separator())
            add(m, "Edit Catalogue Structure…", #selector(showCatalogueStructure), "", self)
            add(m, "New Member…", #selector(LibraryController.newProject), "", library)
            add(m, "Member Templates…", #selector(LibraryController.manageProjectTemplates), "", library)
            planned(m, ["New Smart Collection…", "New Saved Search…"])
            m.addItem(.separator())
            add(m, "Find…", #selector(MainWindowController.focusSearch), "", main)
            group(m, "Filters") { planned($0, ["Filter by Rating", "Filter by Flag", "Filter by Asset Type", "Filter by Metadata", "Show Assets in Nested Folders", "Clear All Filters"]) }
            m.addItem(.separator())
            add(m, "Sync Now", #selector(LibraryController.syncNow), "", library)
            add(m, "Export Library…", #selector(LibraryController.exportLibrary), "", library)
            planned(m, ["Find Missing Assets…", "Relink Missing Assets…", "Validate Catalogue…", "Back Up Catalogue…", "Restore Catalogue Backup…"])
        }
        menu("Assets") { m in
            if let imports = assetImportMenu?.assetMenuItem() { m.addItem(imports) }
            group(m, "Create") { sub in
                add(sub, "New Colour…", #selector(LibraryController.newColour), "", library)
                add(sub, "New Palette", #selector(LibraryController.newPalette), "", library)
                add(sub, "New Typography Palette", #selector(LibraryController.newTypography), "", library)
                add(sub, "Palette from Image…", #selector(LibraryController.paletteFromImage), "", library)
                add(sub, "Palette from Clipboard", #selector(LibraryController.paletteFromClipboard), "", library)
                add(sub, "Palette from Swatches…", #selector(MainWindowController.buildPalette), "", main)
            }
            m.addItem(.separator())
            m.addItem(ApplicationCommandItem("Show Selected Palettes in Finder",enabled:{!selectedPalettes().isEmpty}) { [weak library] in
                guard let library else{return}
                let urls=selectedPalettes().compactMap { id -> URL? in
                    if let source=library.store.linkedPalettes.sources[id] {return try? source.record.url(in:source.index.deletingLastPathComponent())}
                    return library.paletteFileURL(id)
                }
                if !urls.isEmpty {NSWorkspace.shared.activateFileViewerSelecting(urls)}
            })
            m.addItem(ApplicationCommandItem("Duplicate Selected Palettes", enabled: { !selectedPalettes().isEmpty }) { [weak library] in
                guard let library else {return};let ids=selectedPalettes()
                library.apply("Duplicate \(ids.count) Selected Palettes") { lib in
                    for id in ids { guard let source=lib.swatch(id),let copy=lib.copyPalette(id,to:source.projectID,withNotes:true) else {continue};lib.renameSwatch(copy,to:source.name+" copy") }
                }
            })
            m.addItem(ApplicationCommandItem("Toggle Selected Favourites", enabled: editablePalette) { [weak library] in
                guard let library else {return};let ids=selectedPalettes();let value = !ids.allSatisfy { library.library.swatch($0)?.favourite == true }
                library.apply("Set Selected Favourites") { lib in for id in ids {lib.setFavourite(id,value)} }
            })
            planned(m, ["Rename Assets…", "Go to Containing Folder", "Create Virtual Copy", "Open in Reference View", "Show on Second Display"])
            m.addItem(.separator())
            group(m, "Set Palette Rating") { sub in
                for value in 0...5 {
                    sub.addItem(ApplicationCommandItem(value == 0 ? "No Rating":"\(value) Star"+(value == 1 ? "":"s"),enabled:editablePalette) { [weak library] in
                        let ids=selectedPalettes();library?.apply("Rate \(ids.count) Selected Palettes") { lib in for id in ids {PaletteAssetHandler.setRating(value,on:id,in:&lib)} }
                    })
                }
            }
            group(m, "Set Palette Flag") { sub in
                for flag in [nil] + PaletteReview.Flag.allCases.map(Optional.some) {
                    sub.addItem(ApplicationCommandItem(flag?.title ?? "No Flag",enabled:editablePalette) { [weak library] in
                        let ids=selectedPalettes();library?.apply("Flag \(ids.count) Selected Palettes") { lib in for id in ids {PaletteAssetHandler.setFlag(flag,on:id,in:&lib)} }
                    })
                }
            }
            m.addItem(.separator())
            group(m, "Edit In") { planned($0, ["Choose External Editor…", "Adobe Lightroom…", "Adobe Photoshop…"]) }
            group(m, "Image Adjustments") { planned($0, ["Rotate Left", "Rotate Right", "Flip Horizontal", "Flip Vertical", "Restore Original Orientation", "Enhance…", "Merge HDR…", "Merge Panorama…", "Reset Adjustments…"]) }
            group(m, "Stacking") { planned($0, ["Group into Stack", "Ungroup Stack", "Expand All Stacks", "Collapse All Stacks"]) }
            group(m, "Previews") { planned($0, ["Build Standard Previews", "Build Full Resolution Previews", "Discard Previews", "Update DNG Preview…"]) }
            m.addItem(.separator())
            add(m, "Export…", #selector(MainWindowController.exportShown), "", main)
            add(m, "Export Palette File…", #selector(MainWindowController.exportShownPaletteFile), "", main)
            m.addItem(adobeMenuItem(target: main, action: #selector(MainWindowController.addShownToAdobe(_:))))
            planned(m, ["Convert to DNG…"])
            m.addItem(.separator())
            m.addItem(ApplicationCommandItem("Delete Selected Assets…", enabled: {assetFrame()?.canDeleteGridSelection == true || editablePalette()}) { [weak library] in
                guard let frame=assetFrame() else {return}
                if !frame.page.grid.selectedItems.isEmpty {frame.deleteGridSelection()}
                else {library?.delete(palettes:Set(selectedPalettes()))}
            })
            planned(m, ["Remove Assets from Catalogue…", "Move Original Files to Trash…", "Remove Rejected Assets…"])
        }
        menu("Metadata") { m in
            route(m, "Manage Tags…", .tags)
            add(m,"Edit Asset Metadata…",#selector(editSelectedMetadata),"",self)
            add(m,"Metadata Settings…",#selector(showMetadataSettings),"",self)
            m.addItem(ApplicationCommandItem("Edit Selected Tags…", enabled: { editablePalette() || (assetFrame()?.canDeleteGridSelection == true && assetFrame()?.page.grid.selectedItems.allSatisfy{$0.hex != nil} == true) }) { [weak library] in
                guard let library,let frame=assetFrame() else {return}
                let ids=selectedPalettes()
                if !ids.isEmpty {TagPanel.palettes(ids,library:library,over:frame.window)}
                else {TagPanel.colours(frame.page.grid.selectedItems.compactMap(\.hex),library:library,over:frame.window)}
            })
            planned(m, ["Inspect Asset Metadata…", "Show Metadata for Selected Asset Only"])
            m.addItem(.separator())
            group(m, "Keywords") { planned($0, ["Set Keyword Shortcut…", "Apply Keyword Shortcut", "Edit Keyword Sets…", "Import Keywords…", "Export Keywords…", "Purge Unused Keywords…"]) }
            group(m, "Presets") { presets in
                add(presets,"Manage Metadata Presets…",#selector(showMetadataSettings),"",self)
            }
            m.addItem(.separator())
            planned(m, ["Copy Metadata…", "Paste Metadata…", "Synchronise Metadata…", "Enable Automatic Metadata Sync"])
            m.addItem(.separator())
            planned(m, ["Edit IPTC and Copyright…", "Edit Capture Time…", "Restore Original Capture Time", "Edit Location…"])
            m.addItem(.separator())
            planned(m, ["Save Metadata to File", "Read Metadata from File", "Resolve Metadata Conflicts…", "Manage XMP and Sidecars…", "View Asset History…", "Create Copy from History…"])
            add(m,"Manage Keywords…",NSSelectorFromString("showTagEditor"),"",library)
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
        let helpItem=NSMenuItem();let helpMenu=Help_Handler.shared.menu()
        helpItem.submenu=helpMenu;bar.addItem(helpItem);NSApp.helpMenu=helpMenu
        bar.addItem(developmentMenu())
        routeClassicMenuItems(bar)
        return bar
    }
}

/// A native menu command validates its current context both when opening and invoking.
private final class ApplicationCommandItem: NSMenuItem, NSMenuItemValidation {
    private let canPerform: () -> Bool
    private let run: () -> Void
    init(_ title: String, enabled: @escaping () -> Bool = { true }, run: @escaping () -> Void) {
        self.canPerform = enabled; self.run = run
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canPerform() }
    @objc private func invoke() { guard canPerform() else { return }; run() }
}

// ---------- Entry point ----------

FileHandlerNativeQA.prepare()

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
} else if let at=CommandLine.arguments.firstIndex(of:"--migrate-simple-catalogue"),CommandLine.arguments.indices.contains(at+1) {
    do {
        let args=CommandLine.arguments,root=URL(fileURLWithPath:args[at+1],isDirectory:true)
        guard let homeAt=args.firstIndex(of:"--app-data"),args.indices.contains(homeAt+1) else{throw failure("Supply --app-data <workspace folder>.")}
        let home=URL(fileURLWithPath:args[homeAt+1],isDirectory:true)
        let backup=try SimpleCatalogue.migrate(root:root,home:home)
        print(backup.map{"Converted with recovery copy: \($0.path)"} ?? "Already uses the simplified structure")
        if let archiveAt=args.firstIndex(of:"--archive-to"),args.indices.contains(archiveAt+1) {
            let cats=Catalogues(root:home,legacyURL:nil)
            guard let name=cats.names().first(where:{cats.directory(for:$0).standardizedFileURL == root.standardizedFileURL}) else{throw failure("The converted catalogue is not registered in this workspace.")}
            let destination=URL(fileURLWithPath:args[archiveAt+1])
            try Handler_File_Manager.shared.createCatalogueArchive(name:name,catalogues:cats,to:destination,includeShared:true)
            print("Portable catalogue with My Library: \(destination.path)")
        }
        exit(0)
    }catch{print(error.localizedDescription);exit(1)}
} else if CommandLine.arguments.contains("--pick") {
    runPickMode()
} else if CommandLine.arguments.contains("--halo-demo") {
    runHaloDemo()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    delegate.library.finishWorkspaceSession()
    FileHandlerNativeQA.cleanup()
}
