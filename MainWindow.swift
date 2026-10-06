import AppKit

// ---------- The window: sidebar, content, builder rail, toolbar ----------

private extension NSToolbarItem.Identifier {
    static let pick = NSToolbarItem.Identifier("pick")
    static let sample = NSToolbarItem.Identifier("sample")
    static let newPalette = NSToolbarItem.Identifier("newPalette")
    static let fromImage = NSToolbarItem.Identifier("fromImage")
    static let build = NSToolbarItem.Identifier("build")
    static let history = NSToolbarItem.Identifier("history")
    static let sidebarToggle = NSToolbarItem.Identifier("sidebarToggle")
    static let paste = NSToolbarItem.Identifier("paste")
    static let export = NSToolbarItem.Identifier("export")
    static let share = NSToolbarItem.Identifier("share")
    static let settings = NSToolbarItem.Identifier("settings")
    static let sync = NSToolbarItem.Identifier("sync")
    static let search = NSToolbarItem.Identifier("search")
    /// The search field itself, which takes over the toolbar while a search is under way.
    static let searchField = NSToolbarItem.Identifier("searchField")
    static let lab = NSToolbarItem.Identifier("lab")
}

/// The middle pane: whichever page is showing. Its status bar is the window's footer, which the
/// window lays across its whole width under the sidebar, the page and the rails.
final class ContentViewController: NSViewController {
    let palette: PaletteViewController
    let all: AllSwatchesViewController
    let lab: LabViewController
    let contrast: ContrastViewController
    let typography: TypographyViewController
    let overview: OverviewViewController
    private let library: LibraryController
    private let status = caption("")
    /// Which build this is, at the footer's right: the version and the commit it was made from.
    private let release = caption(ContentViewController.releaseLine)
    /// The footer's switch between light and dark.
    private lazy var themeSwitch = symbolButton("moon", tooltip: "", target: self, action: #selector(themeTapped))

    /// Beside the switch: the background that is on, as its sRGB hex and its red, green and blue.
    private let themeValue = caption("")

    @objc private func themeTapped() { Theme.toggle() }
    @objc private func showThemeSwitch() {
        let dark = Theme.isDark
        themeSwitch.image = symbol(dark ? "sun.max" : "moon", dark ? "Light" : "Dark", size: 12)
        themeSwitch.contentTintColor = .secondaryLabelColor
        themeValue.stringValue = Theme.backgroundNumbers
        themeSwitch.toolTip = (dark ? "Switch To Light" : "Switch To Dark") + ". L Turns The Background Charcoal, Then Black, Then White, Then Off-White, Then Back; Shift-L Shows The Page Alone, Full Screen."
    }
    static var releaseLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let commit = info["ColourBuildCommit"] as? String
        return "Release v\(version)" + (commit.map { "  \($0)" } ?? "")
    }
    /// The footer: a hairline, then the status line. Placed by the window, full width.
    let footer = NSView()
    static let footerHeight: CGFloat = 26
    private let host = NSView()
    private var showing: NSViewController?
    private var cover: (view: NSView, form: NSViewController)?
    private var flashToken = 0

    init(library: LibraryController) {
        self.library = library
        palette = PaletteViewController(library: library)
        all = AllSwatchesViewController(library: library)
        lab = LabViewController(library: library)
        contrast = ContrastViewController(library: library)
        typography = TypographyViewController(library: library)
        overview = OverviewViewController(library: library)
        super.init(nibName: nil, bundle: nil)
        addChild(overview)
        addChild(palette)
        addChild(all)
        addChild(lab)
        addChild(contrast)
        addChild(typography)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let drop = DropTargetView(frame: NSRect(x: 0, y: 0, width: 700, height: 560))
        drop.onDropImage = { [weak self] url in self?.library.importPalette(from: url) }
        view = drop

        host.translatesAutoresizingMaskIntoConstraints = false
        drop.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: drop.topAnchor),
            host.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: drop.bottomAnchor),
        ])

        let line = hairline()
        release.textColor = .tertiaryLabelColor
        release.toolTip = "The Version Of The App, And The Commit This Build Was Made From"
        release.setContentCompressionResistancePriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.lineBreakMode = .byTruncatingTail
        themeValue.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        themeValue.textColor = .tertiaryLabelColor
        themeValue.toolTip = "The Background Now Showing, In sRGB: Its Hex, Then Red, Green And Blue"
        themeValue.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [line, status, themeSwitch, themeValue, release] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(v)
        }
        showThemeSwitch()
        NotificationCenter.default.addObserver(self, selector: #selector(showThemeSwitch), name: .themeDidChange, object: nil)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: footer.topAnchor),
            line.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: PageStyle.side),
            status.trailingAnchor.constraint(lessThanOrEqualTo: themeSwitch.leadingAnchor, constant: -16),
            themeSwitch.trailingAnchor.constraint(equalTo: themeValue.leadingAnchor, constant: -6),
            themeValue.trailingAnchor.constraint(equalTo: release.leadingAnchor, constant: -16),
            themeValue.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            themeSwitch.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            release.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -PageStyle.side),
            release.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            status.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
    }

    /// Lays a form over the whole page, in a column down the middle, until `uncover()`.
    func cover(with form: NSViewController, fills: Bool = false) {
        _ = view
        uncover()
        let back = NSBox()
        back.boxType = .custom
        back.borderWidth = 0
        back.fillColor = Theme.background
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
            // The box runs under the toolbar; the form starts below it, so its header sits where every page's does.
            form.view.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
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
    /// False on a first run: no pane widths have been saved yet, so the starting widths are used.
    private var startWidthsKnown = true
    private var historyItem: NSSplitViewItem!
    private var sideItem: NSSplitViewItem!
    /// rail2, the context rail: right of rail1, showing whatever rail the page has, closed when it has none.
    private var contextItem: NSSplitViewItem!
    private let contextRail = ContextRailController()
    private lazy var historyRail = HistoryRailController(library: library)
    private(set) var selection: Selection = .all
    private weak var pickItem: NSToolbarItem?
    /// The toolbar's items as they were before the search field took their place; nil when not searching.
    private var searchRestore: [NSToolbarItem.Identifier]?
    private lazy var searchBox: NSSearchField = {
        let field = NSSearchField()
        field.placeholderString = "Name, hex or palette"
        field.target = self
        field.action = #selector(searchChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()
    /// The search field's width: the toolbar's room beside the sidebar, kept up to date as the window changes.
    private lazy var searchWidth: NSLayoutConstraint = searchBox.widthAnchor.constraint(equalToConstant: 320)

    private func fitSearchBox() {
        guard let window = window else { return }
        let side = split.splitViewItems.first.map { $0.isCollapsed ? 0 : $0.viewController.view.frame.width } ?? 0
        // Clear of the sidebar and its toggle on one side, and of the window's edge on the other.
        searchWidth.constant = max(220, window.frame.width - max(side, 150) - 48)
        searchWidth.isActive = true
    }

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

        // A plain pane, not a system sidebar: the toolbar runs the full width above it, and it has no chrome of its own.
        let side = NSSplitViewItem(viewController: sidebar)
        sideItem = side
        side.minimumThickness = SidebarViewController.compactWidth   // closed, rail1 is a strip of icons; from 140 up it is the tree
        side.canCollapse = true
        side.holdingPriority = .defaultLow + 2   // the page takes up a change in the window's width, not the sidebar
        contextItem = NSSplitViewItem(viewController: contextRail)
        contextItem.minimumThickness = 200
        contextItem.canCollapse = true
        contextItem.isCollapsed = true
        contextItem.holdingPriority = .defaultLow + 2
        let main = NSSplitViewItem(viewController: content)
        main.minimumThickness = MainWindowController.pageMinimumWidth
        builderItem = NSSplitViewItem(viewController: builder)
        builderItem.minimumThickness = 230
        builderItem.canCollapse = true
        builderItem.isCollapsed = true
        builderItem.holdingPriority = .defaultLow + 1
        historyItem = NSSplitViewItem(viewController: historyRail)
        historyItem.minimumThickness = 230
        historyItem.canCollapse = true
        historyItem.holdingPriority = .defaultLow + 1
        split.addSplitViewItem(side)
        split.addSplitViewItem(contextItem)
        split.addSplitViewItem(main)
        split.addSplitViewItem(builderItem)
        split.addSplitViewItem(historyItem)
        addGrips()
        // The split view above, the footer across the whole width below it.
        let root = NSViewController()
        root.view = NSView()
        root.addChild(split)
        let footer = content.footer
        for v in [split.view, footer] { v.translatesAutoresizingMaskIntoConstraints = false; root.view.addSubview(v) }
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: root.view.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            split.view.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
        ])
        footerHeight = footer.heightAnchor.constraint(equalToConstant: ContentViewController.footerHeight)
        footerHeight.isActive = true
        // The way back from the page alone, full screen: top centre, clear of every page's own title and actions.
        leavePage.isHidden = true
        leavePage.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(leavePage)
        NSLayoutConstraint.activate([
            leavePage.topAnchor.constraint(equalTo: root.view.topAnchor, constant: 8),
            leavePage.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
        ])
        win.contentViewController = root
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.plainKey(event) ? nil : event
        }
        win.setContentSize(NSSize(width: 1080, height: 700))
        // The window takes its saved place first, so the panes' saved widths are laid into a window of the right size.
        restoreFrame()
        startWidthsKnown = preferences.object(forKey: MainWindowController.splitKey) != nil
        split.splitView.autosaveName = "MMFFDevColour3Split2"   // a new name with rail2: widths saved for three panes do not fit four
        builderItem.isCollapsed = true // the rail belongs to the builder; never restore it open
        historyItem.isCollapsed = !Prefs.historyRailShown
        win.center()
        // Cascading would nudge the window onto the main screen on showing, undoing the saved place.
        shouldCascadeWindows = false
        restoreFrame()
        Theme.apply(to: win)
        DispatchQueue.main.async { Theme.apply(to: win) }   // once more after every page has its views

        let toolbar = NSToolbar(identifier: "MMFFDevColour3Toolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar
        ClickAway.install()
        // Always there on opening: the page alone hides it, and a quit from there must not leave it hidden.
        toolbar.isVisible = true
        NotificationCenter.default.addObserver(self, selector: #selector(leavePageFullScreen), name: NSApplication.willTerminateNotification, object: nil)

        // Read before the library loads: loading shows the first page, which would be saved over this.
        let lastPage = preferences.string(forKey: "lastPage")
        wire()
        library.reload()
        // Opens where it was closed: the page last shown, or the palette last looked at.
        let saved = preferences.string(forKey: "lastPalette").flatMap(UUID.init(uuidString:))
        let palette = saved.flatMap { library.library.swatch($0) != nil ? Selection.palette($0) : nil }
        switch lastPage {
        case "lab": show(.lab)
        case "contrast": show(.contrast)
        case "all": show(.all)
        case let page? where page.hasPrefix("tag:"): show(.tag(String(page.dropFirst(4))))
        case let page? where page.hasPrefix("overview:"): show(UUID(uuidString: String(page.dropFirst(9))).map { .overview($0) } ?? .all)
        default: show(palette ?? .all)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func wire() {
        sidebar.onSelect = { [weak self] s in self?.show(s) }
        sidebar.onWantsFull = { [weak self] in self?.setSidebar(compact: false) }
        sidebar.onExport = { [weak self] id in self?.library.export(self?.library.exportPalettes(for: .palette(id)) ?? []) }
        sidebar.onColourPanel = { [weak self] id in self?.library.addToColourPanel(self?.library.exportPalettes(for: .palette(id)) ?? []) }
        sidebar.onAdobe = { [weak self] send in
            guard let self = self, let id = send.palette else { return }
            self.library.addToAdobe(self.library.exportPalettes(for: .palette(id)), at: send.destination)
        }
        sidebar.onDesignPack = { [weak self] sel in self?.library.exportDesignPack(for: sel) }
        content.palette.onPage = { [weak self] d in self?.step(d, fromWheel: true) }
        content.all.onBuilding = { [weak self] on in self?.setBuilder(open: on) }
        content.all.onDraftChanged = { [weak self] in self?.builder.reload() }
        builder.onSave = { [weak self] in self?.content.all.savePalette() }
        builder.onCancel = { [weak self] in self?.content.all.stopBuilding() }

        library.onAsk = { [weak self] title, message, choices in
            guard let self = self else { return }
            ChoiceSheet(title: title, message: message, choices: choices).present(over: self.content.view)
        }
        library.onNewColour = { [weak self] palette, start in
            guard let self = self else { return }
            let chosen = (palette.map { self.library.profile(forPalette: $0).profile } ?? self.library.profile(forPalette: nil).profile).printCondition.press ?? PressProfiles.generic
            NewColourSheet(palette: palette.flatMap { self.library.library.swatch($0)?.name }, press: chosen, start: start) { [weak self] colour in
                self?.library.add(colour: colour, to: palette)
            }.present(over: self.content.view)
        }
        library.onPrompt = { [weak self] prompt in
            guard let self = self else { return }
            PromptSheet(prompt).present(over: self.content.view)
        }
        library.onRevealProject = { [weak self] id in self?.sidebar.reveal(project: id) }
        library.onThemeChange = { [weak self] in self?.sidebar.reload() }
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
        library.onAnalysis = { [weak self] subject, keys in
            guard let self = self, !keys.isEmpty else { return }
            self.content.cover(with: AnalysisViewController(subject: subject, keys: keys) { [weak self] in self?.content.uncover() }, fills: true)
        }
        library.onOpenContrast = { [weak self] palette, style in
            self?.show(.contrast)
            self?.content.contrast.edit(style, in: palette)
        }
        library.onOpenLab = { [weak self] hex in
            self?.show(.lab)
            self?.content.lab.open(with: hex)
        }
        library.onReveal = { [weak self] hex in
            guard let self = self else { return }
            // A pick lands in the target palette, but the page stays where it is, so sampling can
            // carry on from whatever is on screen. The new swatch is shown only if it is on this page.
            switch self.selection {
            case .palette(let id): if id == self.library.library.activeSwatchID { self.content.palette.reveal(hex) }
            default: self.content.all.reveal(hex)
            }
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: library)
        nc.addObserver(self, selector: #selector(projectFilesChanged), name: .projectFilesDidChange, object: library)
        nc.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        nc.addObserver(self, selector: #selector(stateChanged), name: .appStateDidChange, object: library)
        nc.addObserver(self, selector: #selector(prefsChanged), name: .prefsDidChange, object: nil)
        nc.addObserver(self, selector: #selector(statusMessage(_:)), name: .statusMessage, object: library)
    }

    // MARK: What is showing

    func show(_ requested: Selection) {
        content.uncover()   // going somewhere else leaves an open form behind
        content.palette.dismissSheet()
        var s = requested
        if case .palette(let id) = s, library.library.swatch(id) == nil { s = .all }
        if case .overview(let id) = s, library.library.project(id) == nil { s = .all }
        if s != .all, content.all.building { content.all.stopBuilding() }
        if !content.all.building, !builderItem.isCollapsed { builderItem.isCollapsed = true }
        // Contrast offers cLab's wheel as a palette only when it is reached from cLab.
        if s == .contrast, selection != .contrast { content.contrast.arrive(fromLab: selection == .lab) }
        selection = s
        library.current = s
        // rail2 is there for a page that has one: for now, a palette's.
        let rail: NSView? = nil
        // A palette's options are on its own bar now; rail2 waits for the information rail.
        contextRail.show(rail)
        let opening = rail != nil && contextItem.isCollapsed
        contextItem.isCollapsed = rail == nil || pageAlone != nil
        if pageAlone != nil { pageAlone?.context = rail == nil }
        if opening, contextItem.viewController.view.frame.width < contextItem.minimumThickness + 1 {
            DispatchQueue.main.async { [weak self] in if let self = self { self.setWidth(MainWindowController.contextStartWidth, of: self.contextItem) } }
        }
        switch s {
        case .all: preferences.set("all", forKey: "lastPage")
        case .tag(let t): preferences.set("tag:" + t, forKey: "lastPage")
        case .lab: preferences.set("lab", forKey: "lastPage")
        case .contrast: preferences.set("contrast", forKey: "lastPage")
        case .palette: preferences.set("palette", forKey: "lastPage")
        case .overview(let id): preferences.set("overview:" + id.uuidString, forKey: "lastPage")
        }
        switch s {
        case .all:
            content.show(content.all)
            content.all.setTag(nil)
        case .tag(let t):
            content.show(content.all)
            content.all.setTag(t)
        case .palette(let id) where library.library.swatch(id)?.isTypography == true:
            // A Typography palette has a page of its own: its pairings as real examples.
            content.show(content.typography)
            content.typography.show(id)
        case .palette(let id):
            content.show(content.palette)
            content.palette.show(id)
            preferences.set(id.uuidString, forKey: "lastPalette")
        case .overview(let id):
            content.show(content.overview)
            content.overview.show(id)
        case .lab:
            content.show(content.lab)
        case .contrast:
            content.show(content.contrast)
            content.contrast.reload()   // the library may have changed since it was last shown
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
        case .lab:
            window?.title = "Colour Lab" + where_
        case .contrast:
            window?.title = "Contrast" + where_
        case .overview(let id):
            window?.title = (library.library.project(id).map { "\($0.name) \u{2014} Overview" } ?? "Overview") + where_
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
    @objc func showLab() { show(.lab) }
    @objc func showContrast() { show(.contrast) }

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

    // The window's place is kept by the app itself. macOS's own frame autosave drops the window on
    // the main screen when the saved screen's usable area has changed since, as it does with three screens.
    private var frameSettled = false

    /// The side panes' widths on a first run, before the user has dragged them. After that the
    /// widths are whatever they were left at; nothing is fixed but the minimums.
    /// Two rails at these widths leave a 1440-point laptop screen 1000 for the page.
    static let sidebarStartWidth: CGFloat = 220
    static let railStartWidth: CGFloat = 260
    /// The page's narrowest: the rails give way before the page does.
    static let pageMinimumWidth: CGFloat = 560
    private static let splitKey = "NSSplitView Subview Frames MMFFDevColour3Split2"
    static let contextStartWidth: CGFloat = 220

    private func applyStartWidths() {
        split.splitView.layoutSubtreeIfNeeded()
        setWidth(MainWindowController.sidebarStartWidth, of: sideItem)
        if !historyItem.isCollapsed { setWidth(MainWindowController.railStartWidth, of: historyItem) }
    }

    /// Gives a side pane a width by moving the divider on its inner edge. Set, measured and corrected,
    /// since a collapsed pane's dividers can sit between a rail and the page.
    private func setWidth(_ wanted: CGFloat, of item: NSSplitViewItem) {
        let view = split.splitView
        guard let index = split.splitViewItems.firstIndex(of: item), view.arrangedSubviews.indices.contains(index) else { return }
        let width = max(item.minimumThickness, min(wanted, view.bounds.width - MainWindowController.pageMinimumWidth - 240))
        if index == 0 { view.setPosition(width, ofDividerAt: 0); return }
        let pane = view.arrangedSubviews[index]
        // rail2 sits on the left, so it is its right-hand divider that moves.
        if item === contextItem { view.setPosition(pane.frame.minX + width, ofDividerAt: index); return }
        // The divider that moves is the one against the nearest open pane to the left: a collapsed
        // pane in between has no width to give, so its own divider cannot move.
        var divider = index - 1
        while divider > 0, split.splitViewItems[divider].isCollapsed { divider -= 1 }
        for _ in 0..<3 {
            let got = pane.frame.width
            if abs(got - width) < 0.5 { break }
            let at = view.arrangedSubviews[divider].frame.maxX
            view.setPosition(at + (got - width), ofDividerAt: divider)
            view.layoutSubtreeIfNeeded()
        }
    }

    /// A notch on the inner edge of each side pane: drag to resize, double-click for the starting width.
    private func addGrips() {
        for (item, edge, start) in [(sideItem!, PaneGrip.Edge.trailing, MainWindowController.sidebarStartWidth),
                                    (contextItem!, .trailing, MainWindowController.contextStartWidth),
                                    (builderItem!, .leading, MainWindowController.railStartWidth),
                                    (historyItem!, .leading, MainWindowController.railStartWidth)] {
            let grip = PaneGrip(edge: edge)
            grip.width = { item.viewController.view.frame.width }
            grip.onResize = { [weak self] width in self?.setWidth(width, of: item) }
            grip.onReset = { [weak self] in self?.setWidth(start, of: item) }
            grip.attach(to: item.viewController.view)
        }
    }

    /// Puts the window where it was last left, if any of that place is still on a screen.
    private func restoreFrame() {
        guard let win = window, let text = preferences.string(forKey: "mainWindowFrame") else { return }
        let frame = NSRectFromString(text)
        guard frame.width >= win.minSize.width, frame.height >= win.minSize.height else { return }
        let onScreen = NSScreen.screens.contains { $0.frame.intersection(frame).width >= 200 && $0.frame.intersection(frame).height >= 100 }
        guard onScreen else { return }
        if win.frame != frame { win.setFrame(frame, display: true) }
    }

    private func saveFrame() {
        guard frameSettled, let win = window, !win.styleMask.contains(.fullScreen), !win.isMiniaturized else { return }
        preferences.set(NSStringFromRect(win.frame), forKey: "mainWindowFrame")
    }

    /// Showing can move a window; the saved place is put back once it is up, and only then is a move worth keeping.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !frameSettled else { return }
        restoreFrame()
        let firstRun = !startWidthsKnown
        DispatchQueue.main.async {
            self.restoreFrame()
            if firstRun { self.applyStartWidths() }
            self.frameSettled = true
            // Nothing is being typed on opening: the palette's name does not start out selected for editing.
            if self.window?.firstResponder is NSText { self.window?.makeFirstResponder(nil) }
            // For a trial run: one of the palette page's dropdowns opened, or a bucket slid out of rail1's strip.
            let env = ProcessInfo.processInfo.environment
            if let n = env["MMFFDEV_COLOUR3_DROPDOWN"].flatMap({ Int($0) }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.content.palette.rehearseDropdown(n) }
            }
            if let title = env["MMFFDEV_COLOUR3_SLIDE_OUT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.setSidebar(compact: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.sidebar.rehearseSlideOut(title) }
            }
            // For a trial run: rail1 shut to its strip, then opened again.
            if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_RAIL"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.setSidebar(compact: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { self.setSidebar(compact: false) }
            }
            // For a trial run: the page alone, in the window as it stands.
            // For a trial run: the theme changed while the window is up, as the footer's switch does.
            if let to = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_THEME_AFTER"].flatMap(ThemeMode.init(rawValue:)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { Theme.choose(to) }
            }
            if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_PAGE_ALONE"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showPageAlone(fullScreen: false) }
            }
        }
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowWillClose(_ notification: Notification) { saveFrame() }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
        relayout()
        if searchRestore != nil { fitSearchBox() }
    }
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

    func rehearseHalo(choosing ids: [String]) { content.palette.rehearseHalo(choosing: ids) }

    func rehearseSearch(_ text: String) {
        focusSearch()
        searchBox.stringValue = text
        searchChanged(searchBox)
    }

    // MARK: Keeping up

    @objc private func projectFilesChanged() { sidebar.reload() }
    @objc private func themeChanged() { if let w = window { Theme.apply(to: w) } }
    /// L: charcoal, then black, then white, then off-white, then the theme again.
    @objc func stepBackground() { Theme.cycle() }

    // MARK: The page alone, full screen

    /// What was showing before the page was given the whole screen; nil while the window is as usual.
    private var pageAlone: (side: Bool, context: Bool, history: Bool, builder: Bool, toolbar: Bool, wasFullScreen: Bool)?
    private var footerHeight: NSLayoutConstraint!
    private var keys: Any?
    private lazy var leavePage: NSButton = ThemedButton(title: "Leave Full Screen", image: symbol("xmark", "Leave", size: 11, weight: .semibold),
                                                        target: self, action: #selector(leavePageFullScreen))

    /// L and Shift-L, pressed with nothing else held while nothing is being typed; Esc leaves the page alone.
    private func plainKey(_ event: NSEvent) -> Bool {
        guard let win = window, event.window === win, win.attachedSheet == nil,
              event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty,
              !(win.firstResponder is NSText) else { return false }
        if event.keyCode == 53, pageAlone != nil { leavePageFullScreen(); return true }
        guard event.charactersIgnoringModifiers?.lowercased() == "l" else { return false }
        if event.modifierFlags.contains(.shift) { pageFullScreen() } else { stepBackground() }
        return true
    }

    /// Shift-L: the page takes the whole screen, over the toolbar, the rails and the footer. Pressed
    /// again there, it steps the background as L does.
    @objc func pageFullScreen() { showPageAlone(fullScreen: true) }

    /// `fullScreen` is false only for a trial run, which shows the page alone in the window as it stands.
    func showPageAlone(fullScreen: Bool) {
        guard let win = window else { return }
        guard pageAlone == nil else { Theme.cycle(); return }
        pageAlone = (sideItem.isCollapsed, contextItem.isCollapsed, historyItem.isCollapsed, builderItem.isCollapsed,
                     win.toolbar?.isVisible ?? true, win.styleMask.contains(.fullScreen))
        for item in [sideItem, contextItem, historyItem, builderItem] { item?.isCollapsed = true }
        win.toolbar?.isVisible = false
        content.footer.isHidden = true
        footerHeight.constant = 0
        leavePage.isHidden = false
        if fullScreen, !win.styleMask.contains(.fullScreen) { win.toggleFullScreen(nil) }
    }

    @objc func leavePageFullScreen() {
        guard let win = window, let was = pageAlone else { return }
        pageAlone = nil
        leavePage.isHidden = true
        content.footer.isHidden = false
        footerHeight.constant = ContentViewController.footerHeight
        win.toolbar?.isVisible = was.toolbar
        sideItem.isCollapsed = was.side
        contextItem.isCollapsed = was.context
        historyItem.isCollapsed = was.history
        builderItem.isCollapsed = was.builder
        if !was.wasFullScreen, win.styleMask.contains(.fullScreen) { win.toggleFullScreen(nil) }
    }

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
        if case .palette = selection { content.palette.reload() } else if case .overview = selection { content.overview.reload() } else { content.all.reload() }
        content.restStatus()
    }

    @objc private func statusMessage(_ n: Notification) {
        if let text = n.userInfo?["text"] as? String { content.flash(text) }
    }

    func windowDidBecomeKey(_ notification: Notification) { library.windowBecameActive() }

    // MARK: Menu and toolbar actions

    /// rail1 opens to its tree or shuts to its strip of icons; it is never hidden outright.
    @objc func toggleSidebarPane() {
        if sideItem.isCollapsed { sideItem.animator().isCollapsed = false; return }
        setSidebar(compact: !sidebar.isCompact)
    }

    /// Slides rail1 shut to its strip of icons, or open to the width it last had as a tree.
    func setSidebar(compact: Bool) {
        let view = split.splitView, now = sidebar.view.frame.width
        if now >= SidebarViewController.compactBelow { preferences.set(Double(now), forKey: "sidebarOpenWidth") }
        let saved = CGFloat(preferences.double(forKey: "sidebarOpenWidth"))
        let open = saved >= SidebarViewController.compactBelow ? saved : MainWindowController.sidebarStartWidth
        let to = compact ? SidebarViewController.compactWidth : min(open, view.bounds.width - MainWindowController.pageMinimumWidth - 240)
        // A split view's divider does not animate by itself: it is walked there, eased at both ends.
        slide?.invalidate()
        let from = now, began = Date(), length = 0.26
        slide = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            let t = min(1, Date().timeIntervalSince(began) / length)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            view.setPosition(from + (to - from) * CGFloat(eased), ofDividerAt: 0)
            if t >= 1 { timer.invalidate(); self?.slide = nil }
        }
        if let slide = slide { RunLoop.main.add(slide, forMode: .common) }
    }
    private var slide: Timer?

    @objc func toggleHistory() {
        historyItem.animator().isCollapsed.toggle()
        Prefs.historyRailShown = !historyItem.isCollapsed
    }

    @objc func exportShown() { library.export(library.exportPalettes(for: selection)) }
    @objc func exportDesignPack() { library.exportDesignPack(for: selection) }
    @objc func addShownToAdobe(_ sender: NSMenuItem) {
        guard let send = sender.representedObject as? AdobeSend else { return }
        library.addToAdobe(library.exportPalettes(for: send.palette.map { .palette($0) } ?? selection), at: send.destination)
    }
    @objc func addShownToColourPanel() { library.addToColourPanel(library.exportPalettes(for: selection)) }

    // MARK: Search
    //
    // Search rests as a magnifying glass. Pressing it (or ⌘F) clears the toolbar's own buttons and
    // grows a search field across it; Esc on an empty field, or leaving it empty, puts them back.

    @objc func focusSearch() {
        guard let toolbar = window?.toolbar else { return }
        if searchRestore == nil {
            let lead = (toolbar.items.firstIndex { $0.itemIdentifier == .sidebarToggle }).map { $0 + 1 } ?? 0
            searchRestore = toolbar.items.dropFirst(lead).map { $0.itemIdentifier }
            toolbar.autosavesConfiguration = false   // this is a passing state, not the user's arrangement
            while toolbar.items.count > lead { toolbar.removeItem(at: lead) }
            fitSearchBox()
            toolbar.insertItem(withItemIdentifier: .searchField, at: lead)
        }
        window?.makeFirstResponder(searchBox)
    }

    private func endSearch() {
        guard let toolbar = window?.toolbar, let items = searchRestore else { return }
        searchRestore = nil
        searchBox.stringValue = ""
        searchChanged(searchBox)
        if let at = toolbar.items.firstIndex(where: { $0.itemIdentifier == .searchField }) {
            toolbar.removeItem(at: at)
            for (offset, id) in items.enumerated() { toolbar.insertItem(withItemIdentifier: id, at: at + offset) }
        }
        toolbar.autosavesConfiguration = true
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        content.palette.setSearch(sender.stringValue)
        content.all.setSearch(sender.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchBox, selector == #selector(NSResponder.cancelOperation(_:)), searchBox.stringValue.isEmpty else { return false }
        window?.makeFirstResponder(nil)   // Esc on an empty field closes it; on a full one it clears it first
        endSearch()
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Left empty, the field has nothing to show and folds away; with text in it, it stays as the reminder of the filter.
        if (obj.object as? NSSearchField) === searchBox, searchBox.stringValue.isEmpty { DispatchQueue.main.async { [weak self] in self?.endSearch() } }
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
        [.sidebarToggle, .pick, .sample, .newPalette, .lab, .flexibleSpace, .history, .share, .settings, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarToggle, .pick, .sample, .newPalette, .lab, .build, .fromImage, .paste, .export, .share, .history,
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
        case .sidebarToggle:
            return item("Sidebar", "sidebar.leading", "Show or hide the sidebar (\u{2303}\u{2318}S)", self, #selector(toggleSidebarPane))
        case .pick:
            let i = item("Pick", "eyedropper", "Pick colours from the screen (\u{2318}P)", library, #selector(LibraryController.togglePicking))
            if flag { pickItem = i }
            return i
        case .sample:
            return item("Sample", "rectangle.dashed", "Drag over an area of the screen and make a palette of its colours (\u{21E7}\u{2318}P)", library, #selector(LibraryController.sampleArea))
        case .newPalette:
            return item("New Palette", "plus.rectangle.on.rectangle", "Start an empty palette and send picks to it (\u{2318}N)",
                        library, #selector(LibraryController.newPalette))
        case .lab:
            return item("Colour Lab", labSymbolName, "Open Colour Lab, the colour wheel (\u{2318}L)", self, #selector(showLab))
        case .history:
            return item("History", "clock.arrow.circlepath", "Show or hide the History rail (\u{2318}\u{21E7}Y)", self, #selector(toggleHistory))
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
            return item("Search", "magnifyingglass", "Search by name, hex or palette (\u{2318}F)", self, #selector(focusSearch))
        case .searchField:
            let i = NSToolbarItem(itemIdentifier: id)
            i.label = "Search"
            i.view = searchBox
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
