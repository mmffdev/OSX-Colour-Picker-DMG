import AppKit

// ---------- The window: sidebar, content, builder rail, toolbar ----------

private extension NSToolbarItem.Identifier {
    static let pick = NSToolbarItem.Identifier("pick")
    static let newPalette = NSToolbarItem.Identifier("newPalette")
    static let fromImage = NSToolbarItem.Identifier("fromImage")
    static let build = NSToolbarItem.Identifier("build")
    static let paste = NSToolbarItem.Identifier("paste")
    static let export = NSToolbarItem.Identifier("export")
    static let share = NSToolbarItem.Identifier("share")
    static let settings = NSToolbarItem.Identifier("settings")
    static let sync = NSToolbarItem.Identifier("sync")
    static let search = NSToolbarItem.Identifier("search")
}

/// The middle pane: whichever page is showing, with the status bar beneath it.
final class ContentViewController: NSViewController {
    let palette: PaletteViewController
    let all: AllSwatchesViewController
    private let library: LibraryController
    private let status = caption("")
    private let host = NSView()
    private var showing: NSViewController?
    private var cover: (view: NSView, form: NSViewController)?
    private var flashToken = 0

    init(library: LibraryController) {
        self.library = library
        palette = PaletteViewController(library: library)
        all = AllSwatchesViewController(library: library)
        super.init(nibName: nil, bundle: nil)
        addChild(palette)
        addChild(all)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let drop = DropTargetView(frame: NSRect(x: 0, y: 0, width: 700, height: 560))
        drop.onDropImage = { [weak self] url in self?.library.importPalette(from: url) }
        view = drop

        let line = hairline()
        status.font = NSFont.systemFont(ofSize: 11)
        for v in [host, line, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            drop.addSubview(v)
        }
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: drop.topAnchor),
            host.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: line.topAnchor),
            line.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: drop.bottomAnchor, constant: -26),
            status.leadingAnchor.constraint(equalTo: drop.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(lessThanOrEqualTo: drop.trailingAnchor, constant: -20),
            status.centerYAnchor.constraint(equalTo: drop.bottomAnchor, constant: -13),
        ])
    }

    /// Lays a form over the whole page, in a column down the middle, until `uncover()`.
    func cover(with form: NSViewController, fills: Bool = false) {
        _ = view
        uncover()
        let back = NSBox()
        back.boxType = .custom
        back.borderWidth = 0
        back.fillColor = .windowBackgroundColor
        back.translatesAutoresizingMaskIntoConstraints = false
        form.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(form)
        back.addSubview(form.view)
        host.addSubview(back)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: host.topAnchor),
            back.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            back.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            back.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            form.view.topAnchor.constraint(equalTo: back.topAnchor),
            form.view.bottomAnchor.constraint(equalTo: back.bottomAnchor),
        ] + (fills ? [form.view.leadingAnchor.constraint(equalTo: back.leadingAnchor),
                      form.view.trailingAnchor.constraint(equalTo: back.trailingAnchor)]
                   : [form.view.centerXAnchor.constraint(equalTo: back.centerXAnchor)]))
        cover = (back, form)
    }

    func uncover() {
        cover?.form.removeFromParent()
        cover?.view.removeFromSuperview()
        cover = nil
    }

    func show(_ page: NSViewController) {
        _ = view
        guard showing !== page else { return }
        showing?.view.removeFromSuperview()
        showing = page
        page.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.topAnchor.constraint(equalTo: host.topAnchor),
            page.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            page.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    /// The resting text: what the library holds and where picks go.
    func restStatus() {
        flashToken += 1
        let lib = library.library
        if library.picking {
            let into = lib.activeSwatch.map { " into \($0.name)" } ?? ""
            status.stringValue = "Picking\(into) \u{2014} press Esc or click this window to stop"
            status.textColor = .labelColor
            return
        }
        var parts = [plural(lib.colours.count, "Swatch", "Swatches"), plural(lib.swatches.count, "Palette")]
        parts.append(lib.activeSwatch.map { "Picks go to \($0.name)" } ?? "Picks go to the library only")
        parts.append("Click copies \(Prefs.copyFormat.label)")
        if library.catalogue != Catalogues.mainName { parts.insert(library.catalogue, at: 0) }
        status.stringValue = parts.joined(separator: "  \u{00B7}  ")
        status.textColor = .secondaryLabelColor
    }

    func flash(_ text: String) {
        flashToken += 1
        let token = flashToken
        status.stringValue = text
        status.textColor = .labelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self = self, self.flashToken == token else { return }
            self.restStatus()
        }
    }
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate,
                                  NSSharingServicePickerToolbarItemDelegate, NSMenuDelegate, NSWindowDelegate {
    let library: LibraryController
    /// Filled by the File ▸ Catalogue submenu each time it opens.
    let catalogueMenu = NSMenu(title: "Catalogue")

    private let split = NSSplitViewController()
    private let sidebar: SidebarViewController
    private let content: ContentViewController
    private let builder: BuilderViewController
    private var builderItem: NSSplitViewItem!
    private(set) var selection: Selection = .all
    private weak var pickItem: NSToolbarItem?

    init(library: LibraryController) {
        self.library = library
        sidebar = SidebarViewController(library: library)
        content = ContentViewController(library: library)
        builder = BuilderViewController(draft: content.all.draft)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init(window: win)
        win.minSize = NSSize(width: 760, height: 460)
        win.titleVisibility = .hidden   // the page shows its own name; the title is kept for the Window menu
        win.toolbarStyle = .unified
        win.delegate = self
        library.window = win
        catalogueMenu.delegate = self

        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 236 // room for a palette name, its count and star
        side.maximumThickness = 340
        side.canCollapse = true
        let main = NSSplitViewItem(viewController: content)
        main.minimumThickness = 420
        builderItem = NSSplitViewItem(viewController: builder)
        builderItem.minimumThickness = 230
        builderItem.maximumThickness = 340
        builderItem.canCollapse = true
        builderItem.isCollapsed = true
        builderItem.holdingPriority = .defaultLow + 1
        split.addSplitViewItem(side)
        split.addSplitViewItem(main)
        split.addSplitViewItem(builderItem)
        win.contentViewController = split
        win.setContentSize(NSSize(width: 1080, height: 700))
        split.splitView.autosaveName = "MMFFDevColour3Split"
        builderItem.isCollapsed = true // the rail belongs to the builder; never restore it open
        win.center()
        win.setFrameAutosaveName("MMFFDevColour3MainWindow")

        let toolbar = NSToolbar(identifier: "MMFFDevColour3Toolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar

        wire()
        library.reload()
        // Opens on the palette last looked at, even if All Swatches was visited since.
        let saved = preferences.string(forKey: "lastPalette").flatMap(UUID.init(uuidString:))
        show(saved.flatMap { library.library.swatch($0) != nil ? .palette($0) : nil } ?? .all)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func wire() {
        sidebar.onSelect = { [weak self] s in self?.show(s) }
        sidebar.onExport = { [weak self] id in self?.library.export(self?.library.exportPalettes(for: .palette(id)) ?? []) }
        sidebar.onColourPanel = { [weak self] id in self?.library.addToColourPanel(self?.library.exportPalettes(for: .palette(id)) ?? []) }
        sidebar.onDesignPack = { [weak self] sel in self?.library.exportDesignPack(for: sel) }
        content.palette.onPage = { [weak self] d in self?.step(d, fromWheel: true) }
        content.all.onBuilding = { [weak self] on in self?.setBuilder(open: on) }
        content.all.onDraftChanged = { [weak self] in self?.builder.reload() }
        builder.onSave = { [weak self] in self?.content.all.savePalette() }
        builder.onCancel = { [weak self] in self?.content.all.stopBuilding() }

        library.onShow = { [weak self] s, rename in
            guard let self = self else { return }
            self.show(s)
            if rename, case .palette = s {
                DispatchQueue.main.async { self.content.palette.beginRenaming() }
            }
        }
        library.onCover = { [weak self] form, fills in
            if let form = form { self?.content.cover(with: form, fills: fills) } else { self?.content.uncover() }
        }
        library.onReveal = { [weak self] hex in
            guard let self = self else { return }
            // A pick lands in the target palette; follow it there, unless the user is looking at everything.
            if let id = self.library.library.activeSwatchID, self.selection != .all { self.show(.palette(id)) }
            if case .palette = self.selection { self.content.palette.reveal(hex) } else { self.content.all.reveal(hex) }
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: library)
        nc.addObserver(self, selector: #selector(stateChanged), name: .appStateDidChange, object: library)
        nc.addObserver(self, selector: #selector(prefsChanged), name: .prefsDidChange, object: nil)
        nc.addObserver(self, selector: #selector(statusMessage(_:)), name: .statusMessage, object: library)
    }

    // MARK: What is showing

    func show(_ requested: Selection) {
        content.uncover()   // going somewhere else leaves an open form behind
        var s = requested
        if case .palette(let id) = s, library.library.swatch(id) == nil { s = .all }
        if s != .all, content.all.building { content.all.stopBuilding() }
        if !content.all.building, !builderItem.isCollapsed { builderItem.isCollapsed = true }
        selection = s
        library.current = s
        switch s {
        case .all:
            content.show(content.all)
            content.all.setTag(nil)
        case .tag(let t):
            content.show(content.all)
            content.all.setTag(t)
        case .palette(let id):
            content.show(content.palette)
            content.palette.show(id)
            preferences.set(id.uuidString, forKey: "lastPalette")
        }
        sidebar.select(s)
        retitle()
        content.restStatus()
    }

    private func retitle() {
        let where_ = library.catalogue == Catalogues.mainName ? "" : " \u{2014} \(library.catalogue)"
        switch selection {
        case .all:
            window?.title = "All Swatches" + where_
        case .palette(let id):
            window?.title = (library.library.swatch(id)?.name ?? "Palette") + where_
        case .tag(let t):
            window?.title = "Tagged \(t)" + where_
        }
    }

    /// Moves to the next or previous palette, in sidebar order.
    func step(_ direction: Int, fromWheel: Bool = false) {
        let order = library.paletteOrder.map { $0.id }
        guard !order.isEmpty else { return }
        guard case .palette(let id) = selection, let i = order.firstIndex(of: id) else {
            if !fromWheel { show(.palette(direction > 0 ? order[0] : order[order.count - 1])) }
            return
        }
        let next = i + direction
        guard order.indices.contains(next) else {
            content.flash(direction > 0 ? "That\u{2019}s the last palette" : "That\u{2019}s the first palette")
            return
        }
        show(.palette(order[next]))
        content.flash("\(next + 1) of \(order.count)  \u{00B7}  \(library.library.swatch(order[next])?.name ?? "")")
    }

    @objc func nextPalette() { step(1) }
    @objc func previousPalette() { step(-1) }
    @objc func showAll() { show(.all) }

    private func setBuilder(open: Bool) {
        // Not animated: an animated split leaves the grid sized for a width part-way through.
        builderItem.isCollapsed = !open
        builder.reload()
        split.view.layoutSubtreeIfNeeded()
        relayout()
    }

    private func relayout() {
        content.all.relayout()
        content.palette.relayout()
    }

    func windowDidResize(_ notification: Notification) { relayout() }
    func windowDidEndLiveResize(_ notification: Notification) { relayout() }

    @objc func buildPalette() {
        show(.all)
        content.all.startBuilding()
    }

    func rehearseBuilder(with hexes: [String]) {
        content.all.rehearse(name: "Launch page", hexes: hexes)
    }

    /// Opens the tag bar on the first palette that sits in a project (or the one showing) and types into it.
    func rehearseTagBar(typing text: String) {
        if let inProject = library.paletteOrder.first(where: { $0.projectID != nil }) { show(.palette(inProject.id)) }
        content.palette.rehearseTagBar(typing: text)
    }

    func rehearseLabels() {
        if case .palette = selection { content.palette.rehearseLabels() } else { content.all.rehearseLabels() }
    }

    func rehearseSearch(_ text: String) {
        content.palette.setSearch(text)
        content.all.setSearch(text)
    }

    // MARK: Keeping up

    @objc private func libraryChanged() {
        sidebar.reload()
        if case .tag(let t) = selection, !library.library.allTags.contains(where: { $0.lowercased() == t.lowercased() }) { selection = .all }
        show(selection) // falls back to All Swatches if the open palette has gone
    }

    @objc private func stateChanged() {
        pickItem?.label = library.picking ? "Stop" : "Pick"
        pickItem?.image = symbol(library.picking ? "stop.circle" : "eyedropper", "Pick a colour")
        retitle()
        content.restStatus()
    }

    @objc private func prefsChanged() {
        if case .palette = selection { content.palette.reload() } else { content.all.reload() }
        content.restStatus()
    }

    @objc private func statusMessage(_ n: Notification) {
        if let text = n.userInfo?["text"] as? String { content.flash(text) }
    }

    func windowDidBecomeKey(_ notification: Notification) { library.windowBecameActive() }

    // MARK: Menu and toolbar actions

    @objc func exportShown() { library.export(library.exportPalettes(for: selection)) }
    @objc func exportDesignPack() { library.exportDesignPack(for: selection) }
    @objc func addShownToColourPanel() { library.addToColourPanel(library.exportPalettes(for: selection)) }

    @objc func focusSearch() {
        guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == .search }) as? NSSearchToolbarItem else { return }
        item.beginSearchInteraction()
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        content.palette.setSearch(sender.stringValue)
        content.all.setSearch(sender.stringValue)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === catalogueMenu else { return }
        menu.removeAllItems()
        for name in library.availableCatalogues() {
            let item = menu.addItem(withTitle: name, action: #selector(catalogueChosen(_:)), keyEquivalent: "")
            item.target = self
            item.state = name == library.catalogue ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Catalogue\u{2026}", action: #selector(LibraryController.newCatalogue), keyEquivalent: "").target = library
        menu.addItem(withTitle: "Rename \u{201C}\(library.catalogue)\u{201D}\u{2026}", action: #selector(LibraryController.renameCatalogue), keyEquivalent: "").target = library
        menu.addItem(withTitle: "Open Catalogue File\u{2026}", action: #selector(LibraryController.openCatalogueFile), keyEquivalent: "").target = library
    }

    @objc private func catalogueChosen(_ sender: NSMenuItem) { library.open(catalogue: sender.title) }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .pick, .newPalette, .flexibleSpace, .share, .settings, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .pick, .newPalette, .build, .fromImage, .paste, .export, .share,
         .sync, .settings, .search, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func item(_ label: String, _ icon: String, _ tip: String, _ target: AnyObject, _ action: Selector) -> NSToolbarItem {
            let i = NSToolbarItem(itemIdentifier: id)
            i.label = label
            i.paletteLabel = label
            i.toolTip = tip
            i.image = symbol(icon, label)
            i.isBordered = true
            i.target = target
            i.action = action
            return i
        }
        switch id {
        case .pick:
            let i = item("Pick", "eyedropper", "Pick colours from the screen (\u{2318}P)", library, #selector(LibraryController.togglePicking))
            if flag { pickItem = i }
            return i
        case .newPalette:
            return item("New Palette", "plus.rectangle.on.rectangle", "Start an empty palette and send picks to it (\u{2318}N)",
                        library, #selector(LibraryController.newPalette))
        case .build:
            return item("Build Palette", "rectangle.stack.badge.plus", "Choose swatches from the library to make a palette",
                        self, #selector(buildPalette))
        case .fromImage:
            return item("From Image", "photo", "Make a palette from an image", library, #selector(LibraryController.paletteFromImage))
        case .paste:
            return item("Paste Colours", "doc.on.clipboard", "Make a palette from the hex colours on the clipboard",
                        library, #selector(LibraryController.paletteFromClipboard))
        case .export:
            return item("Export", "square.and.arrow.down.on.square", "Export what is showing", self, #selector(exportShown))
        case .sync:
            return item("Sync", "arrow.triangle.2.circlepath", "Check the sync folder now", library, #selector(LibraryController.syncNow))
        case .settings:
            return item("Settings", "gearshape", "Settings (\u{2318},)", NSApp.delegate as AnyObject, #selector(AppDelegate.showSettings))
        case .share:
            let i = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            i.label = "Share"
            i.paletteLabel = "Share"
            i.toolTip = "Share what is showing"
            i.delegate = self
            return i
        case .search:
            let i = NSSearchToolbarItem(itemIdentifier: id)
            i.label = "Search"
            i.paletteLabel = "Search"
            i.searchField.placeholderString = "Name, hex or palette"
            i.searchField.target = self
            i.searchField.action = #selector(searchChanged(_:))
            i.searchField.sendsSearchStringImmediately = true
            i.searchField.sendsWholeSearchString = false
            return i
        default:
            return nil
        }
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        let items = library.shareItems(for: selection)
        if items.isEmpty { library.flash("Nothing to share yet") }
        return items
    }
}
