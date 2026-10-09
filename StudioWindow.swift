import AppKit
import UniformTypeIdentifiers

// ---------- The Studio window: the app itself on Colorgain's own grid ----------
//
// Colorgain's main window as the design guide draws it (c_c_c_design_grid_app.md, c_c_design_elements.md):
// a 64 header, the library rail, the context rail, the page, the history rail and a 48 footer, on
// twelve columns inside 24 margins with 16 gutters. Everything is placed by frame from the grid and
// drawn in the ten text styles; no macOS control is on the window but the search field. It opens
// the window the app opens since 2026-10-08; the old window opens only with --classic. Begun 2026-10-07
// on Rick's free run: the library and palettes views only, their assets' layout and presentation.

final class StudioWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// A click anywhere that is not a field ends whatever field was being typed in, the search above all: otherwise the
    /// quick keys, 1 and 2, go on typing into it and the page is filtered by "22" while the picks land elsewhere.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, firstResponder is NSText, let content = contentView {
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            var inField = false, v = hit
            while let view = v { if view is NSTextField || view is NSTextView { inField = true; break }; v = view.superview }
            if !inField { makeFirstResponder(content) }
        }
        super.sendEvent(event)
    }
}

final class StudioWindowController: NSWindowController {
    static var shared: StudioWindowController?
    let frame: StudioFrame

    init(library: LibraryController) {
        frame = StudioFrame(library: library)
        let w = StudioWindow(contentRect: NSRect(origin: .zero, size: Design.App.size),
                             styleMask: [.closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = Brand.edition
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false   // a press on the page is a press on the page, never a drag of the window
        w.collectionBehavior = [.fullScreenPrimary, .managed]   // a borderless window goes full screen only when told it may
        w.backgroundColor = Design.paper
        w.minSize = Design.App.least
        // A resize moves by whole units, so the rows always end on the beat above the footer.
        w.resizeIncrements = NSSize(width: 1, height: Design.App.unit)
        w.contentView = frame
        w.center()
        w.setFrameAutosaveName("StudioWindow")
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static var gridKey: Any?

    static func show(library: LibraryController) {
        let c = shared ?? StudioWindowController(library: library)
        shared = c
        // --palettes opens on the palettes view, --palette "<name>" on that palette, for looking at a screen straight away.
        let args = CommandLine.arguments
        let named = args.firstIndex(of: "--palette").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let project = args.firstIndex(of: "--project").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        if let name = named, let s = library.library.swatches.first(where: { $0.name == name }) { c.frame.go(.palette(s.id)) }
        else if let name = project, let p = library.library.projects.first(where: { $0.name == name }) { c.frame.go(.project(p.id)) }
        else {
            let views: [(String, StudioFrame.Place)] = [("--settings", .settings), ("--schema", .schema), ("--shortcuts", .shortcuts), ("--halo", .halo), ("--tags", .tags), ("--lab", .lab), ("--contrast", .contrast), ("--projects", .projects), ("--palettes", .palettes), ("--share", .share)]
            c.frame.go(views.first { args.contains($0.0) }?.1 ?? .catalogue)
        }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        library.window = c.window   // errors and prompts come up on this window
        // --snap <file> writes the page that is showing, whole, as a PNG and quits: for measuring a screen below the fold without scrolling it.
        if let i = args.firstIndex(of: "--snap"), args.indices.contains(i + 1) {
            let to = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let png = c.frame.page.snapshot()?.representation(using: .png, properties: [:]) { try? png.write(to: to) }
                NSApp.terminate(nil)
            }
        }
        // The backslash key turns Master Inner on and off, whenever no words are being typed.
        if gridKey == nil {
            gridKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c, weak library] e in
                guard let c = c, e.window === c.window, !(c.window?.firstResponder is NSText), !Overlays.any else { return e }
                if c.window?.firstResponder is ShortcutsSettings { return e }   // a key being recorded is not a key being used
                if e.characters == "\\" { c.frame.toggleGrid(); return nil }
                // The quick keys: single keys that work anywhere in the window.
                switch QuickKeys.command(for: e) {
                case "newPalette"?: library?.newPalette(); return nil
                case "pick"?: library?.togglePicking(); return nil
                case "sample"?: library?.sampleArea(); return nil
                default: return e
                }
            }
        }
        // The controller's questions come up on the window's own panels, not the old window's.
        library.onPrompt = { [weak c] p in
            SwissConfirm.name(over: c?.window, title: p.title, note: p.message, placeholder: p.placeholder, confirm: p.confirm, check: p.check) { p.done($0) }
        }
        library.onAsk = { [weak c] title, message, choices in
            SwissConfirm.choose(over: c?.window, title: title, note: message, choices: choices.map { $0.title }) { i in if choices.indices.contains(i) { choices[i].run() } }
        }
        library.onOpenContrast = { [weak c] palette, style in
            c?.frame.go(.contrast)
            c?.frame.contrastPage.edit(style, in: palette)
        }
        library.onShow = { [weak c] s, _ in
            switch s {
            case .overview(let id): c?.frame.go(.project(id))
            case .palette(let id): c?.frame.go(.palette(id))
            default: break
            }
        }
        c.window?.makeFirstResponder(c.frame)   // not the search field: nothing blinks until it is wanted
    }
}

// MARK: - Drawing on the baseline

/// Text is placed by its baseline, never its box, so a row of different sizes sits level (the
/// guide's first law). All the window's views are flipped: y grows downwards, as the grid reads.
extension NSAttributedString {
    var baselineFont: NSFont { length > 0 ? attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Design.Text.body.font() : Design.Text.body.font() }
    func draw(x: CGFloat, baseline: CGFloat) { if length > 0 { draw(at: NSPoint(x: x, y: baseline - baselineFont.ascender)) } }
    func draw(right: CGFloat, baseline: CGFloat) { draw(x: right - size().width, baseline: baseline) }
    /// Draws on one line, cut with an ellipsis where it would pass `width`.
    func draw(x: CGFloat, baseline: CGFloat, width: CGFloat) {
        if size().width <= width { draw(x: x, baseline: baseline); return }
        let m = NSMutableAttributedString(attributedString: self)
        while m.length > 1 && m.size().width > width { m.deleteCharacters(in: NSRange(location: m.length - 1, length: 1)); }
        m.deleteCharacters(in: NSRange(location: max(0, m.length - 1), length: min(1, m.length)))
        m.append(NSAttributedString(string: "\u{2026}", attributes: attributes(at: 0, effectiveRange: nil)))
        m.draw(x: x, baseline: baseline)
    }
}

func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }
func hairline(x: CGFloat, y: CGFloat, width: CGFloat, _ c: NSColor = Design.rule) { fill(NSRect(x: x, y: y, width: width, height: 1), c) }

/// "Just now", "12 min", "3 hr", "Yesterday", then the day.
private func when(_ d: Date) -> String {
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "Just now" }
    if s < 3600 { return "\(Int(s / 60)) min" }
    if s < 86400 { return "\(Int(s / 3600)) hr" }
    if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: d)
}

// MARK: - The frame

final class StudioFrame: NSView {
    typealias A = Design.App
    let library: LibraryController

    /// What the page shows and the rails point at. The levels are the schema's: a collection, a folder
    /// in it where it groups its members, a member (the app's project), and the palettes inside.
    /// A group inside a member, by the member and the group: Palettes, Typography, Information, or any of the member's own.
    enum Place: Hashable { case catalogue, collection(UUID), folder(UUID, UUID), project(UUID), group(UUID, UUID), palette(UUID), palettes, projects, settings, schema, shortcuts, halo, tags, lab, contrast, share }
    private(set) var place: Place = .catalogue
    private(set) var chosenHex: String?

    let header = StudioHeader()
    let rail1 = LibraryRail()
    let rail2 = PaletteTable()
    let page = StudioPage()
    let history = HistoryRail()
    let footer = StudioFooter()
    /// Master Inner over everything: the columns and the beat, in the grid's orange, when it is on.
    let overlay = GridOverlay()
    /// The invisible strip across the top, around the window's three buttons: a press on it drags the window, and the pointer says so.
    let strip = TitleStrip()
    /// Contrast, drawn on the page's columns; kept here so the window can open it on a typography palette.
    let contrastPage: ContrastPage
    /// Export and Import as a wizard in the page (StudioShare.swift), begun from a palette's halo, a page's Export or the catalogue settings.
    let sharePage: SharePage
    /// How open each panel is, 0 to 1, and where each is going: the frame is laid out from these, and the clock slides them.
    private var open = (rail1: CGFloat(1), rail2: CGFloat(1), history: CGFloat(0))
    private var goal = (rail1: CGFloat(1), rail2: CGFloat(1), history: CGFloat(0))
    private var slideClock: Timer?
    private var lastSlide = Date()
    private var expanded = false

    init(library: LibraryController) {
        self.library = library
        contrastPage = ContrastPage(library: library)
        sharePage = SharePage(library: library)
        super.init(frame: NSRect(origin: .zero, size: A.size))
        wantsLayer = true
        layer?.backgroundColor = Design.paper.cgColor
        for v in [header, rail1, rail2, page, history, footer, strip, overlay] { addSubview(v) }
        header.onTab = { [weak self] i in self?.go([Place.catalogue, .palettes, .lab, .contrast, .projects][i]) }
        header.onSettings = { [weak self] in self?.go(.settings) }
        header.onSearch = { [weak self] _ in self?.fillPage() }
        page.onAcross = { [weak self] n in self?.page.grid.across = n }
        rail1.onPick = { [weak self] p in self?.go(p) }
        rail1.onArrow = { [weak self] in guard let self = self else { return }; self.goal.rail1 = self.goal.rail1 < 1 ? 1 : 0; self.slide() }
        rail2.arrow = .none
        history.arrow = .close
        history.onArrow = { [weak self] in self?.goal.history = 0; self?.slide() }
        header.onHistory = { [weak self] in guard let self = self else { return }; self.goal.history = self.goal.history < 1 ? 1 : 0; self.slide() }
        page.onArrow = { [weak self] in
            guard let self = self else { return }
            // The page takes the whole width: the history goes, rail2 goes, rail1 shuts; the arrow back gives the rails their width.
            self.expanded.toggle()
            self.page.expanded = self.expanded
            if self.expanded { self.goal = (0, 0, 0) } else { self.goal = (1, self.railTwo, self.goal.history) }
            self.slide()
        }
        // A palette dropped on a member moves into its Palettes, and rail2 turns to that member to show it there.
        rail1.onDrop = { [weak self] palette, member in
            guard let self = self else { return }
            // Into another member it is a copy, as agreed: the original stays; within its own member it is a move.
            self.library.move(palette: palette, to: member, index: 0)
            self.go(.project(member))
        }
        // A name typed over its words on either rail, written once the typing ends: a palette, a member, or a folder.
        let rename: (StudioFrame.Place, String) -> Void = { [weak self] p, name in
            guard let self = self else { return }
            switch p {
            case .palette(let id): self.library.rename(id, to: name)
            case .project(let id): self.library.apply("Rename Member") { $0.renameProject(id, to: name) }
            case .folder(let c, let f): SchemaTrial.changeCollection(c) { col in if let i = col.folders.firstIndex(where: { $0.id == f }) { col.folders[i].name = name } }
            default: break
            }
        }
        rail1.onRename = rename
        rail2.onRename = rename
        rail1.onFavourite = { [weak self] id in self?.library.toggleFavourite(id) }
        rail1.onTarget = { [weak self] id in guard let self = self else { return }; self.library.setTarget(self.library.library.activeSwatchID == id ? nil : id) }
        rail1.onGear = { [weak self] id, view, rect in self?.openHalo(for: id, from: view, rect: rect) }
        // A bucket opened or shut on either rail is remembered for this catalogue; rail2 is built from the state, so it is filled again.
        rail1.onShut = { [weak self] key, shut in guard let self = self else { return }; Prefs.setRailShut(key, shut, in: self.library.catalogue) }
        rail2.onShut = { [weak self] key, shut in guard let self = self else { return }; Prefs.setRailShut(key, shut, in: self.library.catalogue); self.fillContextRail() }
        // On the Contrast page a row chooses the palette the pair is picked from; everywhere else it opens the place.
        rail2.onPick = { [weak self] p in
            guard let self = self else { return }
            if self.place == .contrast, self.contrastPage.pick(p) { return }
            self.go(p)
        }
        contrastPage.onPaletteChange = { [weak self] in if self?.place == .contrast { self?.fillContextRail() } }
        page.grid.onPick = { [weak self] hex in self?.choose(hex) }
        page.grid.onCopy = { [weak self] text in copyToClipboard(text); self?.library.flash("Copied \(text)") }
        page.grid.onHalo = { [weak self] hex, rect in self?.openColourHalo(hex, rect: rect) }
        page.onFormat = { [weak self] in self?.reload() }
        header.onPick = { [weak self] in self?.library.togglePicking() }
        header.onSample = { [weak self] in self?.library.sampleArea() }
        page.grid.onOpen = { [weak self] id in
            guard let self = self else { return }
            self.go(self.library.library.project(id) != nil ? .project(id) : .palette(id))
        }
        page.settings.library = library
        page.settings.onChange = { [weak self] in self?.reload() }
        page.schema.library = library
        page.schema.onChange = { [weak self] in self?.reload() }
        // The New button makes a member where members are listed; on a member's Typography page, a typography palette, opened in Contrast for its first pairing.
        page.onNew = { [weak self] in self?.newFromPage() }
        page.add(ShortcutsSettings(), as: .shortcuts)
        page.add(HaloSettings(), as: .halo)
        // Tags: every tag with its colour, name, scope and what wears it, the one place for all of them (StudioTags.swift).
        page.add(TagsSettings(library: library), as: .tags)
        page.add(LabPage(library: library), as: .lab)
        page.add(contrastPage, as: .contrast)
        page.add(sharePage, as: .share)
        sharePage.onLeave = { [weak self] in self?.go(.catalogue) }
        page.onExport = { [weak self] in self?.exportFromPage() }
        page.settings.onImport = { [weak self] in self?.startImport() }
        page.settings.onExport = { [weak self] in guard let self = self else { return }; self.startExport(.catalogue, subject: nil, name: self.library.catalogue) }
        history.onPick = { [weak self] hex in self?.choose(hex) }
        footer.onAct = { [weak self] i in self?.act(i) }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .schemaDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(historyChanged), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(flashed(_:)), name: .statusMessage, object: nil)
        library.onReveal = { [weak self] hex in self?.choose(hex) }
    }
    @objc private func flashed(_ n: Notification) { if let t = n.userInfo?["text"] as? String { footer.flash(t) } }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    @objc private func libraryChanged() { reload() }
    @objc private func historyChanged() { fillHistory() }

    /// Slides every panel towards where it is going, a quarter of a second for the whole way, eased; stops when all have arrived.
    private func slide() {
        header.historyOpen = goal.history > 0
        guard slideClock == nil else { return }
        lastSlide = Date()
        slideClock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let now = Date(), step = CGFloat(now.timeIntervalSince(self.lastSlide) / 0.25)
            self.lastSlide = now
            func toward(_ v: CGFloat, _ g: CGFloat) -> CGFloat { v < g ? min(g, v + step) : max(g, v - step) }
            self.open = (toward(self.open.rail1, self.goal.rail1), toward(self.open.rail2, self.goal.rail2), toward(self.open.history, self.goal.history))
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
            self.needsDisplay = true
            if self.open == self.goal { t.invalidate(); self.slideClock = nil }
        }
        RunLoop.main.add(slideClock!, forMode: .common)
    }

    // The regions, from the grid: rails of two columns each side, the page in the six between, each as open as it is.
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame = NSRect(x: 0, y: 0, width: w, height: A.header)
        footer.frame = NSRect(x: 0, y: h - A.footer, width: w, height: A.footer)
        let top = A.header + 1, bodyH = h - A.header - A.footer - 2
        func ease(_ v: CGFloat) -> CGFloat { v <= 0 ? 0 : v >= 1 ? 1 : 1 - pow(1 - v, 3) }
        // The dividers stand in the middle of the area gutters, after columns 2 and 4; the history's is a column gutter.
        let r1Full = A.column(3, in: w) - A.areaGutter / 2, r1Min = LibraryRail.collapsedWidth
        let r2Full = A.column(5, in: w) - A.areaGutter / 2 - r1Full - 1
        let hFull = w - A.column(11, in: w) + A.gutter / 2
        let r1W = (r1Min + (r1Full - r1Min) * ease(open.rail1)).rounded(), r2W = (r2Full * ease(open.rail2)).rounded(), hW = (hFull * ease(open.history)).rounded()
        header.railEdge = r1W
        rail1.frame = NSRect(x: 0, y: top, width: r1W, height: bodyH)
        rail1.collapsed = open.rail1 < 0.5
        rail1.arrow = goal.rail1 < 1 ? .open : .close
        rail2.frame = NSRect(x: rail1.frame.maxX + 1, y: top, width: r2W, height: bodyH)
        rail2.isHidden = r2W < 2
        // The history slides in from the right edge, and off it completely, its width never changing.
        history.frame = NSRect(x: w - hW, y: top, width: hFull, height: bodyH)
        history.isHidden = hW < 1
        page.frame = NSRect(x: rail2.frame.maxX + (rail2.isHidden ? 0 : 1), y: top, width: w - hW - (history.isHidden ? 0 : 1) - rail2.frame.maxX - (rail2.isHidden ? 0 : 1), height: bodyH)
        header.grid = (A.column(1, in: w), A.columnWidth(in: w))
        footer.grid = (A.column(1, in: w), A.columnWidth(in: w), A.column(5, in: w))
        // Every area's words sit exactly on its columns: the left edge on the first, the right edge at the end of the last; the page's edges
        // are half a gutter, which is a column's edge whichever columns it covers.
        func edges(_ v: NSView, _ from: Int, _ to: Int) -> (CGFloat, CGFloat) {
            (A.column(from, in: w) - v.frame.minX, v.frame.maxX - (A.column(to, in: w) + A.columnWidth(in: w)))
        }
        (rail1.inset, rail1.insetRight) = (A.column(1, in: w), A.areaGutter / 2)
        (rail2.inset, rail2.insetRight) = (A.areaGutter / 2 - 1, A.areaGutter / 2)
        (page.inset, page.insetRight) = (A.areaGutter / 2 - 1, open.history > 0 ? A.gutter / 2 - 1 : A.margin)
        overlay.page = NSRect(x: page.frame.minX + page.inset, y: 0, width: page.frame.width - page.inset - page.insetRight, height: 0)
        (history.inset, history.insetRight) = (A.gutter / 2, A.margin)
        strip.frame = NSRect(x: 0, y: 0, width: w, height: TitleStrip.height)
        overlay.frame = bounds
        overlay.isHidden = !A.masterGrid
        overlay.needsDisplay = true
    }

    /// The backslash key: Master Inner on and off.
    func toggleGrid() { A.masterGrid.toggle(); overlay.isHidden = !A.masterGrid; overlay.needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // The hairlines that edge the regions: under the header, over the footer, beside each rail.
        let w = bounds.width
        hairline(x: 0, y: A.header, width: w)
        hairline(x: 0, y: bounds.height - A.footer - 1, width: w)
        var lines = [rail1.frame.maxX]
        if !rail2.isHidden { lines.append(rail2.frame.maxX) }
        if !history.isHidden { lines.append(history.frame.minX - 1) }
        for x in lines { fill(NSRect(x: x, y: A.header + 1, width: 1, height: rail1.frame.height), Design.rule) }
    }

    // MARK: What is shown

    func go(_ p: Place) {
        if p == .contrast && place != .contrast { contrastPage.arrive(fromLab: place == .lab) }
        place = p
        reload()
    }

    /// The Lab has no rail2: its columns go to the page. Contrast keeps it, as the list of palettes to pick the pair from.
    private var railTwo: CGFloat { expanded || place == .lab ? 0 : 1 }

    private func choose(_ hex: String) {
        chosenHex = hex
        page.grid.chosenHex = hex
        fillFooter()
    }

    /// Every colour as it is drawn, from its master, worked out once a reload.
    private var shade: [String: NSColor] = [:]
    /// Rebuilds every region from the library and the schema. Cheap enough to do whole on any change.
    func reload() {
        let lib = library.library
        shade = lib.displayTable()
        // A place that is gone goes back to the catalogue.
        switch place {
        case .palette(let id) where lib.swatch(id) == nil: place = .catalogue
        case .project(let id) where lib.project(id) == nil: place = .catalogue
        case .group(let id, _) where lib.project(id) == nil: place = .catalogue
        case .collection(let id) where !SchemaTrial.collections.contains(where: { $0.id == id }): place = .catalogue
        case .folder(let c, let f) where !(SchemaTrial.collections.first { $0.id == c }?.folders.contains { $0.id == f } ?? false): place = .catalogue
        default: break
        }
        if goal.rail2 != railTwo {
            goal.rail2 = railTwo
            // Before the window is on screen the rail is simply shut; after, it slides.
            if window?.isVisible == true { slide() } else { open.rail2 = railTwo; needsLayout = true }
        }
        fillLibraryRail()
        fillContextRail()
        fillPage()
        fillHistory()
        fillFooter()
        header.live = { switch place { case .catalogue, .palette: return 0; case .settings, .schema, .shortcuts, .halo, .tags, .share: return nil; case .group: return 0; case .lab: return 2; case .contrast: return 3; case .projects: return 4; default: return 1 } }()
    }

    private func palettes(_ list: [Swatch]) -> [Swatch] { list.filter { !$0.isTypography } }

    // MARK: Sharing

    /// The wizard on a level of the catalogue: the whole catalogue from its settings, a collection or member from its page, a palette from its halo.
    func startExport(_ level: ShareLevel, subject: UUID?, name: String) {
        sharePage.beginExport(level: level, subject: subject, name: name)
        go(.share)
    }
    func startImport() {
        sharePage.beginImport()
        go(.share)
    }
    private func exportFromPage() {
        switch place {
        case .project(let id): startExport(.workGroup, subject: id, name: library.library.project(id)?.name ?? "Member")
        case .folder(let cid, let fid):
            let name = SchemaTrial.collections.first { $0.id == cid }?.folders.first { $0.id == fid }?.name ?? "Group"
            startExport(.workGroup, subject: fid, name: name)
        case .collection(let id): startExport(.collection, subject: id, name: SchemaTrial.collections.first { $0.id == id }?.name ?? "Collection")
        default: startExport(.catalogue, subject: nil, name: library.catalogue)
        }
    }

    // MARK: The palette's halo

    private var halo: HaloMenu?

    /// The old window's palette menu as a halo over the gear: rename, favourite, picks here, duplicate, copy to a member or a new one, move to a
    /// collection's member on a second ring, copy all, export, delete.
    private func openHalo(for id: UUID, from view: NSView, rect: NSRect) {
        let lib = library.library
        guard let s = lib.swatch(id) else { return }
        let library = self.library
        func group(_ id: String, _ label: String, _ symbol: String, _ inner: @escaping () -> [HaloAction]) -> HaloAction { HaloAction(id: id, label: label, symbol: symbol, children: inner) }
        var actions: [HaloAction] = [
            HaloAction(id: "rename", label: "Rename", symbol: "pencil", edit: (s.name, "Palette name", "Return keeps it", { library.rename(id, to: $0) })),
            HaloAction(id: "fav", label: s.favourite ? "Remove From Favourites" : "Add To Favourites", symbol: "star", checked: s.favourite) { library.toggleFavourite(id) },
            HaloAction(id: "target", label: lib.activeSwatchID == id ? "Stop Sending Picks Here" : "Send Picks Here", symbol: "scope", checked: lib.activeSwatchID == id) { library.setTarget(lib.activeSwatchID == id ? nil : id) },
            HaloAction(id: "tags", label: "Tags\u{2026}", symbol: "tag", onSelect: { [weak self] in self?.tag(palette: id) }),
            HaloAction(id: "duplicate", label: "Duplicate", symbol: "plus.square.on.square") { library.duplicate(id) },
            group("copy-to", "Copy To Member", "folder.badge.plus") {
                var inner: [HaloAction] = lib.orderedProjects.filter { $0.id != s.projectID }.map { p in HaloAction(id: p.id.uuidString, label: p.name, symbol: "folder") { library.move(palette: id, to: p.id, index: Int.max) } }
                if s.projectID != nil { inner.append(HaloAction(id: "loose", label: "Palettes, Outside Any Member", symbol: "tray") { library.move(palette: id, to: nil, index: Int.max) }) }
                inner.append(HaloAction(id: "new", label: "New Member\u{2026}", symbol: "plus") { library.startProject(moving: id) })
                return inner
            },
            group("collections", "Add To Collection", "square.grid.2x2") {
                // The second ring: each collection, and inside it a third ring of its members.
                SchemaTrial.collections.map { c in
                    HaloAction(id: c.id.uuidString, label: c.name, symbol: "folder", children: {
                        let places = SchemaTrial.places, all = SchemaTrial.collections
                        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == c.id }
                            .map { p in HaloAction(id: p.id.uuidString, label: p.name, symbol: "folder") { library.move(palette: id, to: p.id, index: Int.max) } }
                    })
                }
            },
            HaloAction(id: "copy-all", label: "Copy All", symbol: "doc.on.doc") { library.copy(lib.hexes(inSwatch: id, by: .oldest), from: s.name) },
            HaloAction(id: "export", label: "Export Palette\u{2026}", symbol: "square.and.arrow.up", onSelect: { [weak self] in self?.startExport(.palette, subject: id, name: s.name) }),
            HaloAction(id: "delete", label: "Delete Palette", symbol: "trash", confirmation: ("Slide to delete", "Hold the arrow key")) { library.delete(palette: id) },
        ]
        if s.projectID != nil { actions.insert(HaloAction(id: "open", label: "Open Member", symbol: "arrow.up.right", onSelect: { [weak self] in if let p = s.projectID { self?.go(.project(p)) } }), at: 0) }
        let h = halo ?? HaloMenu(label: "Palette", hint: "Scroll to turn, click to choose", actions: [])
        halo = h
        h.label = s.name
        h.actions = actions
        h.open(centredOn: rect, in: view)
    }

    /// The halo on a colour: the old swatch ring, over the tile that was clicked.
    private var colourHalo: HaloMenu?
    private func openColourHalo(_ hex: String, rect: NSRect) {
        let inPalette: UUID? = { if case .palette(let id) = place { return id }; return nil }()
        let h = colourHalo ?? HaloMenu(label: "Colour", hint: "Scroll to turn, click to choose", actions: [])
        colourHalo = h
        h.label = colourName(hex)
        h.caption = page.format.text(hex, lowercase: Prefs.lowercaseHex)
        h.actions = SwatchMenu.ring(for: hex, in: inPalette, library: library, editTags: { [weak self] hexes in self?.tag(swatches: hexes) })
        h.open(centredOn: rect, in: page.grid)
    }
    /// Tags typed on the window's own panel, separated by commas, with the scope a new one takes (StudioTags.swift).
    private func tag(swatches hexes: [String]) { TagPanel.colours(hexes, library: library, over: window) }
    private func tag(palette id: UUID) { TagPanel.palette(id, library: library, over: window) }

    /// New on the page: on a member's Typography group, a typography palette in that member, opened in Contrast for its first pairing; anywhere else, a member.
    private func newFromPage() {
        if case .group(let pid, let nid) = place, let node = SchemaTrial.rows(of: SchemaTrial.schema(for: pid)).first(where: { $0.node.id == nid })?.node,
           SchemaTrial.role(of: node) == .typography {
            var made: UUID?
            library.apply("New Typography Palette") { made = $0.createTypography(in: pid) }
            guard let id = made, library.library.swatch(id) != nil else { return }
            go(.contrast)
            contrastPage.edit(nil, in: id)
            return
        }
        newMember()
    }

    /// A member made where the page stands: in the collection or folder in view, else the first collection, made now if there is none; named on the window's own panel.
    private func newMember() {
        let all = SchemaTrial.collections
        var c = all.first ?? SchemaTrial.SchemaFile.fresh.collections[0], folder: UUID? = nil
        switch place {
        case .collection(let id): c = all.first { $0.id == id } ?? c
        case .folder(let id, let f): c = all.first { $0.id == id } ?? c; folder = f
        default: break
        }
        library.startProject(moving: nil, called: SchemaTrial.memberName(of: c), in: c) { [weak self] id in
            if !SchemaTrial.collections.contains(where: { $0.id == c.id }) { c = SchemaTrial.homeForNewMember() }
            SchemaTrial.place(id, in: c.id, folder: folder)
            self?.go(.project(id))
        }
    }

    /// The members of a collection, in rail1's order; with `folder`, those in that folder, or those in none when nil.
    private func members(of c: SchemaCollection, folder: UUID?? = .none) -> [Project] {
        let all = SchemaTrial.collections, places = SchemaTrial.places
        return library.library.orderedProjects.filter { p in
            guard SchemaTrial.collection(of: p.id, among: all, places: places).id == c.id else { return false }
            if case .some(let f) = folder { return SchemaTrial.folder(of: p.id, among: all, places: places) == f }
            return true
        }
    }

    private func fillLibraryRail() {
        let lib = library.library
        var rows: [LibraryRail.Row] = [.group("Catalogue", key: "catalogue"), .row("All Colours", lib.colours.count, .catalogue, 0)]
        func two(_ s: Swatch, in project: UUID? = nil, indent: Int = 0) -> LibraryRail.Row {
            .palette(LibraryRail.PaletteRow(id: s.id, name: s.name, count: s.entries.count, colours: s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) },
                                            favourite: s.favourite, target: lib.activeSwatchID == s.id, project: project, indent: indent))
        }
        /// A member, then its stack as the schema lays it out, each group one step in with what it holds: the palettes
        /// under the Palettes group and the typography palettes under Typography, each with its icons, so picks can be
        /// sent to any of them from here; a member whose stack has no groups lists its palettes straight beneath it.
        func memberRows(_ p: Project, indent: Int) -> [LibraryRail.Row] {
            let held = lib.palettes(in: p.id), colours = palettes(held), type = held.filter { $0.isTypography }
            var out: [LibraryRail.Row] = [.row(p.name, colours.count, .project(p.id), indent)]
            let stack = SchemaTrial.rows(of: SchemaTrial.schema(for: p.id)).filter { $0.level >= 2 }
            if stack.isEmpty { return out + colours.map { two($0, in: p.id, indent: indent + 1) } }
            for (node, level) in stack {
                let at = indent + level - 1
                switch SchemaTrial.role(of: node) {
                case .palettes?:
                    out.append(.node(node.name, colours.count, p.id, at, true, node.id))
                    out += colours.map { two($0, in: p.id, indent: at + 1) }
                case .typography?:
                    out.append(.node(node.name, type.count, p.id, at, false, node.id))
                    out += type.map { two($0, in: p.id, indent: at + 1) }
                case .tags?:
                    // The member's own tags beneath the group, each with the colours wearing it, then the way to the editor.
                    let own = lib.allTags.filter { lib.project(ofTag: $0) == p.id }
                    out.append(.node(node.name, own.count, p.id, at, false, node.id))
                    out += own.map { t in .tag(t, lib.colours.filter { $0.tags?.contains(t) == true }.count, p.id, at + 1) }
                    out.append(.tag("Edit Tags", -1, p.id, at + 1))
                case .information?, nil:
                    out.append(.node(node.name, 0, p.id, at, false, node.id))
                }
            }
            return out
        }
        let favourites = palettes(lib.orderedFavourites)
        if !favourites.isEmpty {
            rows.append(.group("Favourites", key: "favourites"))
            rows += favourites.map { two($0) }
        }
        // Level 0: each collection is a heading. Level 1: its folders, where it has them, each holding its
        // members. Then the member itself, the app's project, with its palettes counted.
        for c in SchemaTrial.collections {
            rows.append(.group(c.name, key: "collection:\(c.id.uuidString)"))
            if c.folderName != nil {
                for f in c.folders {
                    let inside = members(of: c, folder: .some(f.id))
                    rows.append(.row(f.name, inside.count, .folder(c.id, f.id), 0))
                    rows += inside.flatMap { memberRows($0, indent: 1) }
                }
            }
            // A member in no folder sits beside the folders, straight in its collection, so the tree's lines tie it to the
            // collection and not to the last folder above it, and shutting that folder leaves it showing.
            rows += members(of: c, folder: .some(nil)).flatMap { memberRows($0, indent: 0) }
        }
        let loose = palettes(lib.palettes(in: nil))
        rows.append(.group("Palettes", key: "palettes"))
        rows += loose.map { two($0) }
        rows.append(.row("All Palettes", palettes(lib.swatches).count, .palettes, 0))
        rail1.shut = Prefs.railShut(in: library.catalogue)
        rail1.set(rows: rows, chosen: place)
    }

    /// rail2 follows the place: the palettes of the catalogue or a project's level, or, for a member, its
    /// whole stack as the schema lays it out: Information, Palettes, Typography, Tags and any group of its own.
    private func fillContextRail() {
        let lib = library.library
        func paletteRow(_ s: Swatch, indent: Int = 0) -> PaletteTable.Row {
            .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, place == .palette(s.id), indent)
        }
        func memberRows(_ list: [Project]) -> [PaletteTable.Row] {
            list.map { .item($0.name, "\(palettes(lib.palettes(in: $0.id)).count)", 0, .project($0.id), place == .project($0.id)) }
        }
        // A group that holds rows carries its caret and is open unless shut for this catalogue; a shut one's rows are left out.
        let shut = Prefs.railShut(in: library.catalogue)
        func fold(_ key: String, holds: Bool) -> (key: String, open: Bool)? { holds ? (key, !shut.contains(key)) : nil }
        /// A folder of a collection as a group with its members under it; the members in no folder come first, straight under the
        /// collection, so none sits under the last folder's heading looking like one of its own.
        func folderRows(_ c: SchemaCollection, indent: Int) -> [PaletteTable.Row] {
            var out = memberRows(members(of: c, folder: .some(nil)))
            guard c.folderName != nil else { return out }
            for f in c.folders {
                let inside = memberRows(members(of: c, folder: .some(f.id))), key = "r2.folder:\(f.id.uuidString)"
                let state = fold(key, holds: !inside.isEmpty)
                out.append(.group(f.name, indent, fold: state))
                if state?.open ?? false { out += inside }
            }
            return out
        }
        var heading = "Palettes", labels = ("Palette", "Colours"), rows: [PaletteTable.Row] = []
        switch place {
        case .catalogue, .palettes:
            rows = palettes(lib.listedPalettes).map { paletteRow($0) }
        case .palette(let id):
            if let p = lib.swatch(id)?.projectID, let project = lib.project(p) { return fillStack(of: project, in: lib) }
            rows = palettes(lib.palettes(in: nil)).map { paletteRow($0) }
        case .collection(let id):
            guard let c = SchemaTrial.collections.first(where: { $0.id == id }) else { return }
            heading = c.name; labels = (SchemaTrial.memberName(of: c), "Palettes")
            rows = folderRows(c, indent: 0)
        case .folder(let cid, let fid):
            guard let c = SchemaTrial.collections.first(where: { $0.id == cid }), let f = c.folders.first(where: { $0.id == fid }) else { return }
            heading = f.name; labels = (SchemaTrial.memberName(of: c), "Palettes")
            rows = memberRows(members(of: c, folder: .some(fid)))
        case .project(let id), .group(let id, _):
            guard let project = lib.project(id) else { return }
            return fillStack(of: project, in: lib)
        case .settings, .schema, .shortcuts, .halo, .tags, .share:
            heading = "Settings"; labels = ("Section", "")
            rows = [.item("Catalogues", nil, 0, .settings, place == .settings), .item("Schema", nil, 0, .schema, place == .schema),
                    .item("Shortcuts", nil, 0, .shortcuts, place == .shortcuts), .item("Halo", nil, 0, .halo, place == .halo), .item("Tags", nil, 0, .tags, place == .tags)]
        case .lab:
            return   // no rail2: the page has its columns
        case .contrast:
            // The palettes the pair is picked from: the Lab's wheel when it is on offer, Favourites, each member's, then every palette; colours only.
            let chosen = contrastPage.state.palette
            if contrastPage.wheelOffered, let wheel = library.labPalette {
                rows.append(.item("Colour Lab Wheel", "\(wheel.colours.count)", 0, .lab, chosen == nil))
            }
            func group(_ title: String, key: String, _ list: [Swatch]) {
                let colours = palettes(list)
                guard !colours.isEmpty else { return }
                let state = fold("r2.contrast:\(key)", holds: true)
                rows.append(.group(title, 0, fold: state))
                guard state?.open ?? false else { return }
                rows += colours.map { s in .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, chosen == s.id, 1) }
            }
            group("Favourites", key: "favourites", library.favourites)
            for p in lib.orderedProjects { group(p.name, key: "project.\(p.id.uuidString)", lib.palettes(in: p.id)) }
            group("Palettes", key: "palettes", lib.listedPalettes)
        case .projects:
            heading = "Members"; labels = ("Collection", "Palettes")
            for c in SchemaTrial.collections {
                let inside = folderRows(c, indent: 1), state = fold("r2.collection:\(c.id.uuidString)", holds: !inside.isEmpty)
                rows.append(.group(c.name, 0, fold: state))
                if state?.open ?? false { rows += inside }
            }
        }
        rail2.set(heading: heading, labels: labels, rows: rows)
    }

    /// A member's stack in rail2: each group of the schema in its order, the app's own four holding
    /// what they always have, any other a label with its own groups inside it.
    private func fillStack(of project: Project, in lib: Library) {
        let schema = SchemaTrial.schema(for: project.id)
        let held = lib.palettes(in: project.id)
        let own = lib.allTags.filter { lib.project(ofTag: $0) == project.id }
        var rows: [PaletteTable.Row] = []
        let shut = Prefs.railShut(in: library.catalogue)
        // A group with a role holds what it always has, wherever the pattern puts it; any other group is a label with its own beneath.
        // A group that holds rows carries its caret; shut, its rows and the groups inside it are left out.
        func walk(_ group: SchemaNode, _ indent: Int) {
            let here = StudioFrame.Place.group(project.id, group.id)
            var name = group.name, inner: [PaletteTable.Row] = []
            switch SchemaTrial.role(of: group) {
            case .information?:
                if name.isEmpty { name = "Information" }
                inner.append(.item("Overview", nil, indent, .project(project.id), place == .project(project.id)))
            case .palettes?:
                if name.isEmpty { name = "Palettes" }
                let colours = held.filter { !$0.isTypography }
                func row(_ s: Swatch) -> PaletteTable.Row { .palette(s.id, s.name, s.entries.count, s.entries.map { shade[$0.hex] ?? Design.hex($0.hex) }, place == .palette(s.id), indent) }
                // This week's arrivals first, parted from the rest by a word on a hairline, when there are both.
                let week = Date().addingTimeInterval(-7 * 24 * 3600)
                let fresh = colours.filter { ($0.placedAt ?? $0.createdAt) >= week }, older = colours.filter { ($0.placedAt ?? $0.createdAt) < week }
                if !fresh.isEmpty && !older.isEmpty {
                    inner.append(.divider("Just Added")); inner += fresh.map(row)
                    inner.append(.divider("Earlier")); inner += older.map(row)
                } else { inner += colours.map(row) }
                if colours.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case .typography?:
                if name.isEmpty { name = "Typography" }
                let type = held.filter { $0.isTypography }
                inner += type.map { .item($0.name, "\($0.styles?.count ?? 0)", indent, nil, false) }
                if type.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case .tags?:
                if name.isEmpty { name = "Tags" }
                inner += own.map { .item($0, nil, indent, nil, false) }
                if own.isEmpty { inner.append(.item("None found", nil, indent, nil, false)) }
            case nil:
                break
            }
            let key = "r2.node:\(project.id.uuidString):\(group.id.uuidString)", open = !shut.contains(key)
            let holds = !inner.isEmpty || !group.children.isEmpty
            rows.append(.group(name, indent, here, place == here, fold: holds ? (key, open) : nil))
            guard open else { return }
            rows += inner
            for child in group.children { walk(child, indent + 1) }
        }
        for group in schema.children { walk(group, 0) }
        let c = SchemaTrial.collection(of: project.id)
        rail2.set(heading: project.name, labels: (SchemaTrial.memberName(of: c), "Items"), rows: rows)
    }

    private func fillPage() {
        let lib = library.library
        let search = header.search.lowercased()
        func keep(_ name: String, _ hex: String?) -> Bool { search.isEmpty || name.lowercased().contains(search) || (hex?.lowercased().contains(search) ?? false) }
        // A colour's words: its name, and its value in the model the page's header has chosen.
        func tiles(_ hexes: [String], in palette: UUID?) -> [TileGrid.Item] {
            hexes.compactMap { hex in
                let name = lib.name(of: hex, in: palette)
                return keep(name, hex) ? TileGrid.Item(title: name, caption: page.format.text(hex, lowercase: Prefs.lowercaseHex), colours: [shade[hex] ?? Design.hex(hex)], hex: hex, id: nil) : nil
            }
        }
        func cards(_ list: [Swatch]) -> [TileGrid.Item] {
            list.compactMap { s in
                keep(s.name, nil) ? TileGrid.Item(title: s.name, caption: "\(s.entries.count) " + (s.entries.count == 1 ? "colour" : "colours"), colours: s.entries.prefix(8).map { shade[$0.hex] ?? Design.hex($0.hex) }, hex: nil, id: s.id) : nil
            }
        }
        func cardsOf(_ projects: [Project]) -> ([TileGrid.Item], Int) {
            let list = projects.flatMap { palettes(lib.palettes(in: $0.id)) }
            return (cards(list), list.reduce(0) { $0 + $1.entries.count })
        }
        var items: [TileGrid.Item] = [], title = "", meta = ("", "")
        page.show(.tiles)
        page.grid.note = nil
        // A new member can be made wherever members are listed: the Members view, a collection, a folder.
        func newWord(_ c: SchemaCollection) -> String { "New " + SchemaTrial.memberName(of: c) }
        func memberCards(_ list: [Project]) -> [TileGrid.Item] {
            list.compactMap { p in
                let own = palettes(lib.palettes(in: p.id))
                var seen = Set<String>(), hexes: [String] = []
                for h in own.flatMap({ $0.entries.map { $0.hex } }) where !seen.contains(h) { seen.insert(h); hexes.append(h) }
                return keep(p.name, nil) ? TileGrid.Item(title: p.name, caption: plural(own.count, "palette"), colours: hexes.prefix(8).map { shade[$0] ?? Design.hex($0) }, hex: nil, id: p.id) : nil
            }
        }
        switch place {
        case .projects:
            let all = SchemaTrial.collections
            items = memberCards(lib.orderedProjects)
            title = "Members"; meta = (plural(items.count, "member"), plural(all.count, "collection"))
            page.showNew(newWord(all.first ?? SchemaTrial.SchemaFile.fresh.collections[0]))
        case .schema:
            let all = SchemaTrial.collections
            title = "Schema"; meta = (plural(all.count, "collection"), plural(lib.projects.count, "member"))
            page.show(.schema)
        case .shortcuts:
            title = "Shortcuts"; meta = ("\(QuickKeys.commands.count) quick keys", plural(Shortcuts.commands.count, "command"))
            page.show(.shortcuts)
        case .halo:
            title = "Halo"; meta = ("Scrolling", "Colours")
            page.show(.halo)
        case .tags:
            title = "Tags"; meta = (plural(lib.allTags.count, "tag"), "Global and scoped")
            page.show(.tags)
        case .share:
            title = "Share"; meta = ("Export and import", "One checked file")
            page.show(.share)
        case .lab:
            title = "Colour Lab"; meta = ("The wheel", "Build on a colour")
            page.show(.lab)
        case .contrast:
            title = "Contrast"; meta = ("Check a pair", "WCAG 2 \u{00B7} APCA")
            page.show(.contrast)
        case .catalogue:
            items = tiles(lib.catalogueHexes(by: library.paletteSort), in: nil)
            title = "All Colours"; meta = ("\(items.count) colours", library.paletteSort.title)
        case .palette(let id):
            let s = lib.swatch(id)
            items = tiles(lib.hexes(inSwatch: id, by: library.paletteSort), in: id)
            title = s?.name ?? "Palette"
            meta = ("\(items.count) colours", s?.projectID.flatMap { lib.project($0)?.name } ?? "No project")
        case .project(let id):
            let list = palettes(lib.palettes(in: id))
            items = cards(list)
            title = lib.project(id)?.name ?? "Project"
            meta = ("\(items.count) palettes", "\(list.reduce(0) { $0 + $1.entries.count }) colours")
        case .group(let id, let nid):
            // A group's page: what it holds in the member. Palettes and Typography as cards; Information and Tags their words; a group of the member's own, the palettes beneath it.
            let tree = SchemaTrial.schema(for: id)
            let node = SchemaTrial.rows(of: tree).first { $0.node.id == nid }?.node
            let held = lib.palettes(in: id), member = lib.project(id)?.name ?? "Member"
            title = node?.name ?? "Group"
            switch node.flatMap({ SchemaTrial.role(of: $0) }) {
            case .palettes?:
                let list = palettes(held); items = cards(list)
                meta = (plural(list.count, "palette"), member)
            case .typography?:
                // A typography palette holds styles, not colours: its card says how many, and the button makes another in this member.
                let list = held.filter { $0.isTypography }
                items = list.compactMap { s in keep(s.name, nil) ? TileGrid.Item(title: s.name, caption: plural(s.styles?.count ?? 0, "style"), colours: [], hex: nil, id: s.id) : nil }
                meta = (plural(list.count, "typography palette"), member)
                page.showNew("New Typography Palette")
            case .tags?:
                let own = lib.allTags.filter { lib.project(ofTag: $0) == id }
                items = own.map { t in TileGrid.Item(title: t, caption: plural(lib.hexes(tagged: t).count, "colour"), colours: lib.hexes(tagged: t).prefix(8).map { shade[$0] ?? Design.hex($0) }, hex: nil, id: nil) }
                meta = (plural(own.count, "tag"), member)
            case .information?:
                // The member's notes as the page's words, under the rule; the Labels say only whether there are any.
                let notes = (lib.project(id)?.details?[ProjectField.notes.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                items = []
                meta = (notes.isEmpty ? "No notes yet" : "Notes", member)
                page.grid.note = notes.isEmpty ? "No notes yet. Describe this member under Settings, Schema." : notes
            case nil:
                // A group of the member's own holds its palettes for now.
                let list = palettes(held); items = cards(list)
                meta = (plural(list.count, "palette"), member)
            }
        case .collection(let id):
            guard let c = SchemaTrial.collections.first(where: { $0.id == id }) else { return }
            let m = members(of: c)
            let (made, colours) = cardsOf(m)
            items = made; title = c.name
            meta = ("\(m.count) " + SchemaTrial.plural(SchemaTrial.memberName(of: c)).lowercased(), "\(colours) colours")
        case .folder(let cid, let fid):
            guard let c = SchemaTrial.collections.first(where: { $0.id == cid }), let f = c.folders.first(where: { $0.id == fid }) else { return }
            let m = members(of: c, folder: .some(fid))
            let (made, colours) = cardsOf(m)
            items = made; title = f.name
            meta = ("\(m.count) " + SchemaTrial.plural(SchemaTrial.memberName(of: c)).lowercased(), "\(colours) colours")
        case .palettes:
            let list = palettes(lib.listedPalettes)
            items = cards(list)
            title = "All Palettes"; meta = ("\(items.count) palettes", "\(lib.orderedProjects.count) projects")
        case .settings:
            let n = library.availableCatalogues().count
            title = "Catalogues"; meta = (library.catalogue, "\(n) " + (n == 1 ? "catalogue" : "catalogues"))
            page.show(.catalogues)
        }
        switch place {
        case .collection(let id): if let c = SchemaTrial.collections.first(where: { $0.id == id }) { page.showNew(newWord(c)); page.showExport("Export Collection\u{2026}") }
        case .folder(let cid, _): if let c = SchemaTrial.collections.first(where: { $0.id == cid }) { page.showNew(newWord(c)); page.showExport("Export \(c.folderName ?? "Group")\u{2026}") }
        case .project(let id): page.showExport("Export \(SchemaTrial.memberName(of: SchemaTrial.collection(of: id)))\u{2026}")
        default: break
        }
        page.set(title: title, meta: meta, items: items)
        page.grid.chosenHex = chosenHex
    }

    /// Every step the catalogue took, newest first, each with what it did: the colours that came or went, by name, and the
    /// member it touched. On a member, or one of its palettes or groups, only that member's own steps: each has a history of its own.
    private func fillHistory() {
        let lib = library.library, steps = library.history.steps
        var member: UUID?
        switch place {
        case .project(let id), .group(let id, _): member = id
        case .palette(let id): member = lib.swatch(id)?.projectID
        default: break
        }
        var rows: [HistoryRail.Row] = []
        for i in steps.indices.reversed() {
            let step = steps[i]
            if let m = member, step.project != m { continue }
            let change = library.history.change(at: i)
            var parts: [String] = []
            if !change.added.isEmpty { parts.append(change.added.prefix(2).map { lib.name(of: $0, in: nil) }.joined(separator: ", ") + (change.added.count > 2 ? " +\(change.added.count - 2)" : "") + " added") }
            if !change.removed.isEmpty { parts.append(change.removed.prefix(2).map { lib.name(of: $0, in: nil) }.joined(separator: ", ") + (change.removed.count > 2 ? " +\(change.removed.count - 2)" : "") + " removed") }
            if let p = step.project.flatMap({ lib.project($0)?.name }) { parts.append(p) }
            let chips = Array((change.added + change.removed).prefix(4))
            rows.append(HistoryRail.Row(symbol: stepSymbol(for: step.title), title: step.title, detail: parts.joined(separator: "  \u{00B7}  "), time: when(step.date),
                                        chips: chips.map { shade[$0] ?? Design.hex($0) }, hex: chips.first))
            if rows.count >= 120 { break }
        }
        history.set(rows: rows)
    }

    private func fillFooter() {
        let lib = library.library
        let hex = chosenHex ?? lib.colours.max { $0.pickedAt < $1.pickedAt }?.hex ?? Brand.masterHex
        let name = hex == Brand.masterHex && chosenHex == nil && lib.colours.isEmpty ? Brand.masterName : lib.name(of: hex, in: nil)
        footer.set(hex: hex, name: name)
    }

    private func act(_ i: Int) {
        let hex = footer.hex
        switch i {
        case 0: copyToClipboard(hex)
        case 1: copyToClipboard(footer.name)
        default: copyToClipboard(ColourFormat.cssRGB.text(hex))
        }
    }
}

// MARK: - The header, 64 high

/// The wordmark, the tabs, Search, the tile-size slider and the avatar, all on one baseline.
final class StudioHeader: NSView, Overlay, NSTextFieldDelegate {
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    var grid: (x: CGFloat, column: CGFloat) = (24, 96) { didSet { needsLayout = true; needsDisplay = true } }
    var live: Int? = 0 { didSet { needsDisplay = true } }
    private var settingsRect = NSRect.zero
    var onTab: ((Int) -> Void)?
    /// The picker and the rectangle picker, two clean marks after the wordmark, standing inside rail1's edge.
    var railEdge: CGFloat = 248 { didSet { needsDisplay = true } }
    var onPick: (() -> Void)?
    var onSample: (() -> Void)?
    private var pickRects: [NSRect] = []
    /// The clock: the history slides in or out; it is drawn in ink while the history is in.
    var onHistory: (() -> Void)?
    var historyOpen = false { didSet { needsDisplay = true } }
    /// The three window marks at the top of column 1, where macOS would put its buttons: close, minimise, and arrange, which drops its menu.
    private var markRects: [NSRect] = []
    private var markHover: Int?
    private var dropped: SwissDropdown.MenuPanel?
    var onSettings: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onAcross: ((Int) -> Void)?
    var search: String { field.stringValue }
    private let tabs = ["Library", "Palettes", "Lab", "Contrast", "Projects"]
    private var tabRects: [NSRect] = []
    private let field = NSTextField(string: "")
    static let baseline: CGFloat = 40

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Design.Text.body.font()
        field.textColor = Design.ink
        field.placeholderAttributedString = Design.attributed("Search", .body, colour: Design.soft)
        field.target = self
        field.action = #selector(searched)
        field.delegate = self
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        addSubview(field)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let g = Design.App.gutter
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        // Law 1: the field's text on the baseline.
        field.frame = NSRect(x: col(7) - 2, y: Self.baseline - 16, width: span(3) + 4, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = Design.App.gutter, b = Self.baseline
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        Logo.draw(x: col(1), baseline: b)   // the mark, as everywhere
        // The picker, then the rectangle picker, right-aligned to the rail's edge less the margin; the quick keys 2 and shift-2.
        pickRects = []
        for (k, name) in ["eyedropper", "rectangle.dashed"].enumerated() {
            let x = railEdge - Design.App.margin - 16 - CGFloat(1 - k) * 28
            RowMark.draw(name, x: x, baseline: b - 2, colour: Design.quiet)
            pickRects.append(NSRect(x: x - 6, y: b - 24, width: 28, height: 32))
        }
        // The tabs from column 3, 24 apart; the live one Medium in ink, the rest quiet. Lab and Projects wait for their redesign.
        var x = col(3)
        tabRects = []
        for (i, t) in tabs.enumerated() {
            let a = Design.attributed(t, i == live ? .bodyStrong : .body, colour: i == live ? Design.ink : Design.quiet)
            a.draw(x: x, baseline: b)
            let w = a.size().width
            tabRects.append(NSRect(x: x - 8, y: 0, width: w + 16, height: bounds.height))
            if i == live { fill(NSRect(x: x, y: b + 7, width: w, height: 1), Design.ink) }
            x += w + 24
        }
        // Search on a hairline across columns 7 to 9.
        hairline(x: col(7), y: b + 7, width: span(3), field.currentEditor() != nil ? Design.ink : Design.rule)
        // Settings as a quiet word before the window marks.
        let right = col(12) + grid.column
        let settings = Design.attributed("Settings", live == nil ? .bodyStrong : .body, colour: live == nil ? Design.ink : Design.quiet)
        let sx = right - 24 - 3 * 36 - 24 - settings.size().width
        settings.draw(x: sx, baseline: b)
        settingsRect = NSRect(x: sx - 8, y: 0, width: settings.size().width + 16, height: bounds.height)
        // The four window marks at the right end, each a clean 24 glyph hung from the baseline, no box: the clock that
        // slides the history in and out, the arrow that arranges, the dash that minimises, the cross that closes.
        markRects = []
        for i in 0..<4 {
            let r = NSRect(x: right - 24 - CGFloat(3 - i) * 36, y: b - 24, width: 24, height: 24)
            let c = markHover == i || (i == 0 && historyOpen) ? Design.ink : Design.quiet
            c.setStroke()
            let p = NSBezierPath(); p.lineWidth = 1.3; p.lineCapStyle = .butt
            let g = r.insetBy(dx: 5, dy: 5)
            switch i {
            case 3: p.move(to: NSPoint(x: g.minX, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.maxY)); p.move(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.minX, y: g.maxY))
            case 2: p.move(to: NSPoint(x: g.minX, y: g.midY)); p.line(to: NSPoint(x: g.maxX, y: g.midY))
            case 1: p.move(to: NSPoint(x: g.minX, y: g.maxY)); p.line(to: NSPoint(x: g.maxX, y: g.minY)); p.move(to: NSPoint(x: g.minX + 4, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.maxY - 4))
            default:
                p.appendOval(in: g)
                p.move(to: NSPoint(x: g.midX, y: g.minY + 3)); p.line(to: NSPoint(x: g.midX, y: g.midY)); p.line(to: NSPoint(x: g.midX + 3.5, y: g.midY + 2))
            }
            p.stroke()
            markRects.append(r.insetBy(dx: -6, dy: -6))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = markRects.firstIndex { $0.contains(p) }
        if over != markHover { markHover = over; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if markHover != nil { markHover = nil; needsDisplay = true } }

    /// The arrange menu: the window to the left or right half, centred, full screen, or on another display.
    private func arrange() {
        guard let win = window else { return }
        var items = ["Left Half", "Right Half", "Centre", "Full Screen"]
        let others = NSScreen.screens.filter { $0 != win.screen }
        items += others.map { "Move To \($0.localizedName)" }
        let panel = SwissDropdown.MenuPanel(items: items, chosen: "", width: 220) { [weak self] i in
            self?.closeMenu()
            guard let v = win.screen?.visibleFrame else { return }
            switch i {
            case 0: win.setFrame(NSRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height), display: true, animate: true)
            case 1: win.setFrame(NSRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height), display: true, animate: true)
            case 2: win.center()
            case 3: win.toggleFullScreen(nil)
            default:
                let s = others[i - 4].visibleFrame, f = win.frame
                win.setFrame(NSRect(x: s.midX - f.width / 2, y: s.midY - f.height / 2, width: min(f.width, s.width), height: min(f.height, s.height)), display: true, animate: true)
            }
        }
        let origin = win.convertToScreen(convert(NSRect(x: markRects[1].maxX - 220, y: markRects[1].maxY, width: 1, height: 1), to: nil)).origin
        panel.place(below: NSPoint(x: origin.x, y: origin.y - 2))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }
    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = markRects.firstIndex(where: { $0.contains(p) }) {
            switch i {
            case 3: window?.performClose(nil)
            case 2: window?.miniaturize(nil)
            case 1: arrange()
            default: onHistory?()
            }
            return
        }
        if let i = tabRects.firstIndex(where: { $0.contains(p) }) { onTab?(i); return }
        if let i = pickRects.firstIndex(where: { $0.contains(p) }) { if i == 0 { onPick?() } else { onSample?() }; return }
        if settingsRect.contains(p) { onSettings?(); return }
        super.mouseDown(with: event)
    }
    @objc private func searched() { onSearch?(field.stringValue) }
    /// Escape in the search clears it and lets go, so the page is whole again and the quick keys work.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.cancelOperation(_:)) else { return false }
        field.stringValue = ""
        searched()
        window?.makeFirstResponder(window?.contentView)
        return true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: field, queue: .main) { [weak self] _ in self?.searched() }
        NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: field, queue: .main) { [weak self] _ in
            (self?.field.currentEditor() as? NSTextView)?.insertionPointColor = Design.ink
            self?.needsDisplay = true
        }
        NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: field, queue: .main) { [weak self] _ in self?.needsDisplay = true }
    }
}

/// The mini slider: a hairline track and an 8 square knob. Here it sets how many tiles sit across the page.
final class MiniSlider: NSView {
    var value: CGFloat = 0.5 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let y = bounds.midY
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        fill(NSRect(x: 0, y: y, width: bounds.width * value, height: 1), Design.ink)
        fill(NSRect(x: (bounds.width - 8) * value, y: y - 4, width: 8, height: 8), Design.ink)
    }
    override func mouseDown(with event: NSEvent) { track(event) }
    override func mouseDragged(with event: NSEvent) { track(event) }
    private func track(_ e: NSEvent) {
        let x = convert(e.locationInWindow, from: nil).x
        value = max(0, min(1, (x - 4) / (bounds.width - 8)))
        onChange?(value)
    }
}

// MARK: - A rail

/// A Card with 22 top padding and a heading row with the arrow; rows below are drawn by the subclass.
/// The rail scrolls when its rows pass its height, the scroller hidden until the wheel moves.
class StudioRail: NSView {
    var inset: CGFloat = 24 { didSet { needsLayout = true } }
    var insetRight: CGFloat = 24 { didSet { needsLayout = true } }
    /// The arrow in the header, and what a press on it does.
    var arrow = AreaHeader.Arrow.open { didSet { needsDisplay = true } }
    var onArrow: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if arrow != .none, AreaHeader.arrowRect(in: bounds, insetRight: insetRight).insetBy(dx: -8, dy: -8).contains(p) { onArrow?(); return }
        super.mouseDown(with: event)
    }
    static let top: CGFloat = 22
    let scroll = NSScrollView()
    let body: RailBody
    var heading = "" { didSet { needsDisplay = true } }
    /// The two Labels under the heading.
    var labels: (String, String) = ("", "") { didSet { needsDisplay = true } }

    init(body: RailBody) {
        self.body = body
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = body
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    /// The header stays put; only the rows scroll, under the Rule.
    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: AreaHeader.height, width: bounds.width, height: bounds.height - AreaHeader.height)
        body.inset = inset
        body.insetRight = insetRight
        body.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(scroll.frame.height, body.height))
        // Rows that fit do not scroll at all; only a longer list moves under the header.
        scroll.verticalScrollElasticity = body.height > scroll.frame.height ? .allowed : .none
        body.needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        AreaHeader.draw(heading: heading, left: labels.0, right: labels.1, in: bounds, inset: inset, insetRight: insetRight, arrow: arrow)
    }

    class RailBody: NSView {
        var inset: CGFloat = 24, insetRight: CGFloat = 24
        override var isFlipped: Bool { true }
        var height: CGFloat { 0 }
        /// Master Inner: a row's top at a count of units from the rule, and the line its text sits on.
        static var unit: CGFloat { Design.App.unit }
        static var line: CGFloat { Design.App.textBaseline }
    }
}

/// The header of an area, drawn the same in rail1, rail2, the page and the history rail: the Heading
/// with the arrow on its baseline, a row of two Labels under it, and the Rule beneath, at one height in
/// every area so the rule reads as one line across the window broken only by each area's side padding.
/// It never scrolls; what is under it does.
enum AreaHeader {
    static let headingBaseline: CGFloat = StudioRail.top + 14
    static let labelBaseline: CGFloat = headingBaseline + 33
    static let rule: CGFloat = StudioRail.top + 14 + 16 + 27
    /// Where an area's own content starts: a unit of air under the Rule, in every rail and on every page (Rick, 2026-10-09).
    static var height: CGFloat { rule + 1 + Design.App.unit }
    /// The arrow at the right: none; "open", the stroke up and right, pressed to open or widen; "close", turned 180, pressed to close.
    enum Arrow { case none, open, close }
    static func arrowRect(in bounds: NSRect, insetRight: CGFloat) -> NSRect { NSRect(x: bounds.width - insetRight - 16, y: headingBaseline - 13, width: 16, height: 16) }
    static func draw(heading: String, left: String, right: String, in bounds: NSRect, inset: CGFloat, insetRight: CGFloat? = nil, arrow: Arrow = .open) {
        let r = bounds.width - (insetRight ?? inset)
        Design.attributed(heading, .heading).draw(x: inset, baseline: headingBaseline, width: r - inset - 24)
        if arrow != .none { Design.arrow(16, back: arrow == .close).draw(in: arrowRect(in: bounds, insetRight: insetRight ?? inset), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        // Each Label keeps to its half, cut short rather than running into the other: the words are written to fit, never the box.
        let half = ((r - inset) / 2 - 8).rounded(.down)
        Design.attributed(left, .label, colour: Design.quiet).draw(x: inset, baseline: labelBaseline, width: half)
        let rightText = Design.attributed(right, .label, colour: Design.quiet)
        rightText.draw(x: r - min(rightText.size().width, half), baseline: labelBaseline, width: half)
        hairline(x: inset, y: rule, width: r - inset, Design.rule)
    }
}

/// The library rail: groups of rows, the name left and a tabular count right; a row one step in sits
/// inside the row above it, as a member sits in its folder.
final class LibraryRail: StudioRail {
    /// A group label; a row with its count; a palette on two lines, its name over its colours with the count on the second line.
    /// A palette row: its name, count, colours, whether it is a favourite and the picks' target, and the member it sits in, at an indent.
    struct PaletteRow { let id: UUID; let name: String; let count: Int; let colours: [NSColor]; let favourite: Bool; let target: Bool; let project: UUID?; let indent: Int }
    /// A group of a member's stack: its name, what it holds, the member, its indent, and whether a palette can be dropped on it.
    /// A tag of a member, under its Tags group: the tag, how many colours wear it, the member, the indent; or the link to edit them.
    /// A group's key is what its open or shut state is kept under; nil keys it by its title.
    enum Row { case group(String, key: String? = nil), row(String, Int, StudioFrame.Place, Int), palette(PaletteRow), node(String, Int, UUID, Int, Bool, UUID), tag(String, Int, UUID, Int) }
    var onPick: ((StudioFrame.Place) -> Void)?
    /// The buckets shut, by key, and a bucket opened or shut by its caret: its key, and whether it is now shut.
    var shut: Set<String> { get { list.shut } set { list.shut = newValue; needsLayout = true } }
    var onShut: ((String, Bool) -> Void)?
    /// A name typed over where it is drawn: the place renamed, and the new name.
    var onRename: ((StudioFrame.Place, String) -> Void)?
    /// A palette dropped on a member: the palette, then the member it lands in.
    var onDrop: ((UUID, UUID) -> Void)?
    /// The three icons on a palette row: the star, the picks' target, and the gear, which opens the halo over the icon's rect in the body's coordinates.
    var onFavourite: ((UUID) -> Void)?
    var onTarget: ((UUID) -> Void)?
    var onGear: ((UUID, NSView, NSRect) -> Void)?
    private var list: Body { body as! Body }
    /// Shut to a narrow strip: the arrow to open it, then a mark for each of its groups, the chosen one's filled.
    var collapsed = false { didSet { scroll.isHidden = collapsed; needsDisplay = true } }
    static let collapsedWidth: CGFloat = 48
    private var markHits: [(NSRect, StudioFrame.Place)] = []
    init() {
        super.init(body: Body()); heading = "Library"; labels = ("Name", "Count")
        list.onPick = { [weak self] p in self?.onPick?(p) }
        list.onRename = { [weak self] p, n in self?.onRename?(p, n) }
        list.onDrop = { [weak self] s, m in self?.onDrop?(s, m) }
        list.onFavourite = { [weak self] id in self?.onFavourite?(id) }
        list.onTarget = { [weak self] id in self?.onTarget?(id) }
        list.onGear = { [weak self] id, v, r in self?.onGear?(id, v, r) }
        list.onShut = { [weak self] key, shut in self?.needsLayout = true; self?.onShut?(key, shut) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row], chosen: StudioFrame.Place) { list.rows = rows; list.chosen = chosen; needsLayout = true; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard collapsed else { super.draw(dirtyRect); return }
        let x = (Self.collapsedWidth - 16) / 2
        Design.arrow(16).draw(in: NSRect(x: x, y: AreaHeader.headingBaseline - 13, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        hairline(x: x, y: AreaHeader.rule, width: 16, Design.rule)
        // One icon per group on the unit's line, in the house stroke: the catalogue a grid of four, favourites a star, a collection a
        // folder, palettes three bands. Ink for the group holding the chosen place, quiet for the rest.
        markHits = []
        var y = AreaHeader.height, groupPlace: StudioFrame.Place? = nil, groupHas = false, groupName = ""
        var marks: [(StudioFrame.Place, Bool, String)] = []
        for r in list.rows {
            switch r {
            case .group(let title, _):
                if let p = groupPlace { marks.append((p, groupHas, groupName)) }
                groupPlace = nil; groupHas = false; groupName = title
            case .row(_, _, let p, _):
                if groupPlace == nil { groupPlace = p }
                if p == list.chosen { groupHas = true }
            case .palette(let pr):
                if groupPlace == nil { groupPlace = .palette(pr.id) }
                if .palette(pr.id) == list.chosen { groupHas = true }
            case .node(_, _, let pid, _, _, _), .tag(_, _, let pid, _):
                if groupPlace == nil { groupPlace = .project(pid) }
            }
        }
        if let p = groupPlace { marks.append((p, groupHas, groupName)) }
        for (p, on, name) in marks {
            let g = NSRect(x: (Self.collapsedWidth - 16) / 2, y: y + Design.App.textBaseline - 13, width: 16, height: 16)
            (on ? Design.ink : Design.quiet).setStroke()
            let path = NSBezierPath(); path.lineWidth = 1.2; path.lineJoinStyle = .miter
            switch name {
            case "Catalogue":
                for (dx, dy) in [(0, 0), (9, 0), (0, 9), (9, 9)] as [(CGFloat, CGFloat)] { path.appendRect(NSRect(x: g.minX + dx + 0.5, y: g.minY + dy + 0.5, width: 6, height: 6)) }
            case "Favourites":
                let c = NSPoint(x: g.midX, y: g.midY + 0.5), r1: CGFloat = 7.5, r2: CGFloat = 3
                for k in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * CGFloat.pi / 5, r = k % 2 == 0 ? r1 : r2
                    let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { path.move(to: pt) } else { path.line(to: pt) }
                }
                path.close()
            case "Palettes":
                for dx in [0, 5.5, 11] as [CGFloat] { path.appendRect(NSRect(x: g.minX + dx + 0.5, y: g.minY + 0.5, width: 4, height: 15)) }
            default:
                // A folder: the tab, then the body.
                path.move(to: NSPoint(x: g.minX + 0.5, y: g.maxY - 0.5)); path.line(to: NSPoint(x: g.minX + 0.5, y: g.minY + 2.5)); path.line(to: NSPoint(x: g.minX + 6, y: g.minY + 2.5))
                path.line(to: NSPoint(x: g.minX + 8, y: g.minY + 5)); path.line(to: NSPoint(x: g.maxX - 0.5, y: g.minY + 5)); path.line(to: NSPoint(x: g.maxX - 0.5, y: g.maxY - 0.5)); path.close()
            }
            path.stroke()
            markHits.append((NSRect(x: 0, y: y, width: Self.collapsedWidth, height: Design.App.unit), p))
            y += Design.App.unit
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard collapsed else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if p.y < AreaHeader.height { onArrow?(); return }
        if let m = markHits.first(where: { $0.0.contains(p) }) { onArrow?(); onPick?(m.1) }
    }

    final class Body: RailBody, NSDraggingSource {
        /// Every row the rail has, open or shut; `shown` is what is drawn.
        var rows: [Row] = [] { didSet { rebuild() } }
        /// The buckets shut, by key: what is inside them is not shown.
        var shut: Set<String> = [] { didSet { rebuild() } }
        var chosen: StudioFrame.Place = .catalogue
        var onPick: ((StudioFrame.Place) -> Void)?
        var onRename: ((StudioFrame.Place, String) -> Void)?
        var onDrop: ((UUID, UUID) -> Void)?
        var onFavourite: ((UUID) -> Void)?
        var onTarget: ((UUID) -> Void)?
        var onGear: ((UUID, NSView, NSRect) -> Void)?
        var onShut: ((String, Bool) -> Void)?
        /// The icons on palette rows, with what a press on each does.
        private var iconHits: [(NSRect, Int, UUID)] = []
        /// The carets, each with the key of the bucket it opens and shuts.
        private var caretHits: [(NSRect, String)] = []
        /// The Edit Tags rows, each with the member it is under.
        private var tagLinks: [(NSRect, UUID)] = []
        static var row: CGFloat { unit }
        static var two: CGFloat { unit * 2 }
        static var groupAbove: CGFloat { unit }
        static let step: CGFloat = 16
        /// After a row's 14 mark, the caret's slot, then the words: mark, caret, words, on every row so the words of a level align
        /// whether or not the row holds anything. A group heading has no mark: its caret stands on the column, its words where its rows' marks are.
        static let caretSlot: CGFloat = 14
        static var words: CGFloat { 14 + caretSlot }
        static let headingWords: CGFloat = 12
        private var hits: [(NSRect, StudioFrame.Place)] = []
        /// Every name that can be renamed where it is: its rect, with the line at `line` into it, its place, its words and its style.
        private var nameHits: [(NSRect, StudioFrame.Place, String, Design.Text)] = []
        /// The place whose name is being typed over, so the drawn name stays out of the field's way.
        private var renaming: StudioFrame.Place?
        /// The palette under the mouse at mouseDown, so a drag can take it; the member a drag is over.
        private var pressed: (UUID, String, [NSColor])?
        /// Where and when the mouse went down, so a drag starts only once the pointer has clearly left the press.
        private var pressedAt: (NSPoint, TimeInterval) = (.zero, 0)
        private var target: UUID?

        override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([PaletteDrag.type]) }
        required init?(coder: NSCoder) { fatalError() }

        // MARK: Open and shut

        /// A row as drawn: its level in the tree (a group 0, a row one more than its indent), the key its state is kept
        /// under, and whether it holds rows, which is what earns it a caret.
        struct Shown { let row: Row; let level: Int; let key: String; let holds: Bool }
        private(set) var shown: [Shown] = []
        static func level(of r: Row) -> Int {
            switch r {
            case .group: return 0
            case .row(_, _, _, let i), .node(_, _, _, let i, _, _), .tag(_, _, _, let i): return i + 1
            case .palette(let pr): return pr.indent + 1
            }
        }
        /// A stable key for a bucket: a collection, folder, member or group by its id; the catalogue's own headings by name.
        static func key(of r: Row) -> String {
            switch r {
            case .group(let title, let key): return key ?? "group:" + title
            case .row(let name, _, let place, _):
                switch place {
                case .folder(_, let f): return "folder:\(f.uuidString)"
                case .project(let id): return "member:\(id.uuidString)"
                default: return "row:" + name
                }
            case .node(_, _, let pid, _, _, let nid): return "node:\(pid.uuidString):\(nid.uuidString)"
            case .tag(let name, _, let pid, _): return "tag:\(pid.uuidString):" + name
            case .palette(let pr): return "palette:\(pr.id.uuidString)"
            }
        }
        /// What is shown: every row, less those inside a shut bucket. A row holds the rows after it that are deeper than it.
        private func rebuild() {
            var out: [Shown] = [], hideBelow: Int? = nil
            for (i, r) in rows.enumerated() {
                let level = Self.level(of: r)
                if let h = hideBelow, level > h { continue }
                hideBelow = nil
                let key = Self.key(of: r), holds = i + 1 < rows.count && Self.level(of: rows[i + 1]) > level
                out.append(Shown(row: r, level: level, key: key, holds: holds))
                if holds && shut.contains(key) { hideBelow = level }
            }
            shown = out
            needsDisplay = true
        }
        private func toggle(_ key: String) {
            let shutNow = !shut.contains(key)
            if shutNow { shut.insert(key) } else { shut.remove(key) }
            onShut?(key, shutNow)
        }

        /// The first group's header sits on the first-order line, the first row under the rule; every later group has a unit of air above it.
        override var height: CGFloat {
            var h: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: h += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row, .node, .tag: h += Self.row
                case .palette: h += Self.two
                }
            }
            return h + Self.unit
        }

        /// A 16 icon in the house stroke: the star, the picks' target, the gear. `on` fills the star or the target's centre.
        private func icon(_ which: Int, in g: NSRect, on: Bool, colour: NSColor) {
            colour.setStroke(); colour.setFill()
            let path = NSBezierPath(); path.lineWidth = 1.1; path.lineJoinStyle = .miter
            switch which {
            case 0:
                let c = NSPoint(x: g.midX, y: g.midY + 0.5), r1: CGFloat = 7, r2: CGFloat = 2.8
                for k in 0..<10 {
                    let a = -CGFloat.pi / 2 + CGFloat(k) * CGFloat.pi / 5, r = k % 2 == 0 ? r1 : r2
                    let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { path.move(to: pt) } else { path.line(to: pt) }
                }
                path.close()
                if on { path.fill() } else { path.stroke() }
            case 1:
                path.appendOval(in: g.insetBy(dx: 1.5, dy: 1.5))
                path.stroke()
                if on { NSBezierPath(ovalIn: g.insetBy(dx: 5.5, dy: 5.5)).fill() }
                else { let dot = NSBezierPath(ovalIn: g.insetBy(dx: 6.5, dy: 6.5)); dot.lineWidth = 1; dot.stroke() }
            default:
                // The halo: its own mark, a ring with a ring inside.
                Design.haloMark(in: g, colour: colour)
            }
        }

        /// A row's caret, in the slot after its mark, when the row holds others; the slot is kept empty otherwise.
        private func caret(_ s: Shown, mark mx: CGFloat, top y: CGFloat, colour: NSColor) {
            guard s.holds else { return }
            Caret.draw(open: !shut.contains(s.key), centre: NSPoint(x: mx + 14 + Self.caretSlot / 2, y: y + Self.line - 5), colour: colour)
            caretHits.append((NSRect(x: mx + 14, y: y, width: Self.caretSlot, height: Self.row), s.key))
        }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            hits = []; iconHits = []; nameHits = []; caretHits = []; tagLinks = []
            let right = bounds.width - insetRight
            /// A member lit while a palette is dragged over it, or a group of its stack that takes the drop: a one-point ink edge.
            func edge(_ box: NSRect) {
                Design.ink.setStroke()
                let e = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            }
            // The grounds first, then the tree's lines over them, then every row's mark and words.
            var grounds: [(NSRect, NSColor)] = [], tree: [TreeLines.Row] = []
            var yy: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group:
                    if i > 0 { yy += Self.groupAbove }
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: 0, anchor: inset + 5, markLeft: inset, baseline: Self.line))
                    yy += Self.row
                case .row(_, _, let place, let indent):
                    if place == chosen { grounds.append((NSRect(x: 0, y: yy, width: bounds.width, height: Self.row), Design.mist)) }
                    let mx = inset + 12 + CGFloat(indent) * Self.step
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.row
                case .node(_, _, _, let indent, _, _), .tag(_, _, _, let indent):
                    let mx = inset + 12 + CGFloat(indent) * Self.step
                    tree.append(TreeLines.Row(top: yy, height: Self.row, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.row
                case .palette(let pr):
                    if .palette(pr.id) == chosen { grounds.append((NSRect(x: 0, y: yy, width: bounds.width, height: Self.two), Design.mist)) }
                    let mx = inset + 12 + CGFloat(pr.indent) * Self.step
                    tree.append(TreeLines.Row(top: yy, height: Self.two, level: s.level, anchor: mx + 7, markLeft: mx, baseline: Self.line))
                    yy += Self.two
                }
            }
            for (box, colour) in grounds { fill(box, colour) }
            TreeLines.draw(tree, colour: Design.rule)
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group(let title, _):
                    if i > 0 { y += Self.groupAbove }
                    // A first-order header: Title Case, the body weight, on the line every area shares. Its caret stands on the
                    // column where the tree's stem hangs from, its words over its rows' marks; the whole heading opens and shuts it.
                    if s.holds {
                        Caret.draw(open: !shut.contains(s.key), centre: NSPoint(x: inset + 4.5, y: y + Self.line - 5), colour: Design.quiet)
                        caretHits.append((NSRect(x: 0, y: y, width: bounds.width, height: Self.row), s.key))
                    }
                    Design.attributed(title, .body).draw(x: inset + Self.headingWords, baseline: y + Self.line, width: right - inset - Self.headingWords)
                    y += Self.row
                case .row(let name, let count, let place, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let on = place == chosen
                    // Rows sit one small step in from their group's header, so the groups read as groups; the mark, the caret, then the words.
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let mark: String
                    switch place {
                    case .folder: mark = "building.2"
                    case .project: mark = "folder"
                    case .catalogue: mark = "square.grid.2x2"
                    case .palettes: mark = "swatchpalette"
                    default: mark = "folder"
                    }
                    RowMark.draw(mark, x: mx, baseline: b, colour: on ? Design.ink : Design.quiet)
                    caret(s, mark: mx, top: y, colour: on ? Design.ink : Design.quiet)
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let countW = countText.size().width
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body), nameW = right - x - countW - 12
                    if renaming != place {
                        nameText.draw(x: x, baseline: b, width: nameW - (on ? 10 : 0))
                        if on { fill(NSRect(x: x + min(nameText.size().width, right - x - countW - 22) + 6, y: b - 6, width: 4, height: 4), Design.ink) }
                    }
                    switch place {
                    case .project, .folder: nameHits.append((NSRect(x: x, y: y, width: nameW, height: Self.row), place, name, on ? .bodyStrong : .body))
                    default: break
                    }
                    countText.draw(right: right, baseline: b)
                    if case .project(let id) = place, id == target { edge(box) }
                    hits.append((box, place))
                    y += Self.row
                case .node(let name, let count, let pid, let indent, let drop, let nid):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let on = chosen == .group(pid, nid)
                    if on { fill(box, Design.mist) }
                    // The old sidebar's marks for a member's groups: palettes, information, typography, tags, and a dashed square for one of your own.
                    let role = SchemaTrial.role(of: SchemaNode(name: name))
                    let mark = role == .palettes ? "swatchpalette" : role == .information ? "info.circle" : role == .typography ? "textformat" : role == .tags ? "tag" : "square.dashed"
                    RowMark.draw(mark, x: mx, baseline: b, colour: Design.quiet)
                    caret(s, mark: mx, top: y, colour: Design.quiet)
                    let countText = Design.attributed(count > 0 ? String(count) : "", .caption, colour: Design.quiet)
                    Design.attributed(name, on ? .bodyStrong : .body).draw(x: x, baseline: b, width: right - x - countText.size().width - 12)
                    countText.draw(right: right, baseline: b)
                    if drop, pid == target { edge(box) }
                    hits.append((box, .group(pid, nid)))
                    y += Self.row
                case .tag(let name, let count, let pid, let indent):
                    // A tag with its mark and how many colours wear it; the last row the way to the editor, a quiet word.
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, mx = inset + 12 + CGFloat(indent) * Self.step, x = mx + Self.words
                    let link = count < 0
                    RowMark.draw(link ? "slider.horizontal.3" : "tag", x: mx, baseline: b, colour: Design.quiet)
                    let countText = Design.attributed(count > 0 ? String(count) : "", .caption, colour: Design.quiet)
                    Design.attributed(name, .body, colour: link ? Design.quiet : Design.ink).draw(x: x, baseline: b, width: right - x - countText.size().width - 12)
                    countText.draw(right: right, baseline: b)
                    hits.append((box, link ? .tags : .project(pid)))
                    if link { tagLinks.append((box, pid)) }
                    y += Self.row
                case .palette(let pr):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.two)
                    let place = StudioFrame.Place.palette(pr.id)
                    let on = place == chosen
                    let mx = inset + 12 + CGFloat(pr.indent) * Self.step, x = mx + Self.words
                    RowMark.draw("swatchpalette", x: mx, baseline: y + Self.line, colour: on ? Design.ink : Design.quiet)
                    let nameText = Design.attributed(pr.name, on ? .bodyStrong : .body)
                    if renaming != place {
                        nameText.draw(x: x, baseline: y + Self.line, width: right - x - (on ? 10 : 0))
                        if on { fill(NSRect(x: x + min(nameText.size().width, right - x - 10) + 6, y: y + Self.line - 6, width: 4, height: 4), Design.ink) }
                    }
                    nameHits.append((NSRect(x: x, y: y, width: right - x, height: Self.row), place, pr.name, on ? .bodyStrong : .body))
                    // The second line: the colours as a strip half the row's width, then, from the right, the count and the three icons before it.
                    let countText = Design.attributed(String(pr.count), .caption, colour: Design.quiet)
                    let b2 = y + Self.unit + Self.line
                    countText.draw(right: right, baseline: b2)
                    // The star under the palette's mark, then the strip; from the right, the count, then the halo and the picks' target before it.
                    let star = NSRect(x: mx - 1, y: b2 - 13, width: 16, height: 16)
                    icon(0, in: star, on: pr.favourite, colour: pr.favourite ? Design.ink : Design.quiet)
                    iconHits.append((star.insetBy(dx: -4, dy: -4), 0, pr.id))
                    var ix = right - countText.size().width - 12
                    for which in [2, 1] {
                        ix -= 16
                        let g = NSRect(x: ix, y: b2 - 13, width: 16, height: 16)
                        let lit = which == 1 && pr.target
                        icon(which, in: g, on: lit, colour: lit ? Design.ink : Design.quiet)
                        iconHits.append((g.insetBy(dx: -4, dy: -4), which, pr.id))
                        ix -= 8
                    }
                    let strip = NSRect(x: x, y: b2 - 10, width: ((right - x) / 2).rounded(), height: 10)
                    if pr.colours.isEmpty { fill(strip, Design.mist) }
                    else {
                        let bw = strip.width / CGFloat(pr.colours.count)
                        for (k, c) in pr.colours.enumerated() { fill(NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: k == pr.colours.count - 1 ? strip.width - CGFloat(k) * bw : bw + 0.5, height: strip.height), c) }
                    }
                    hits.append((box, place))
                    y += Self.two
                }
            }
        }

        private func palette(at p: NSPoint) -> (UUID, String, [NSColor])? {
            var y: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: y += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row, .node, .tag: y += Self.row
                case .palette(let pr):
                    if NSRect(x: 0, y: y, width: bounds.width, height: Self.two).contains(p) { return (pr.id, pr.name, pr.colours) }
                    y += Self.two
                }
            }
            return nil
        }

        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            // An icon acts on the release, not the press: the halo opens under the pointer, and a press that opened it must not be the click that chooses on it.
            if let h = iconHits.first(where: { $0.0.contains(p) }) { pressedIcon = h; return }
            // A caret opens or shuts its bucket and goes nowhere; the words beside it still go where they always have.
            if let c = caretHits.first(where: { $0.0.contains(p) }) { toggle(c.1); return }
            if event.clickCount == 2, let h = nameHits.first(where: { $0.0.contains(p) }) { rename(h, at: p); return }
            pressed = palette(at: p); pressedAt = (event.locationInWindow, event.timestamp)
            // Edit Tags under a member opens Settings, Tags filtered to that member.
            if let l = tagLinks.first(where: { $0.0.contains(p) }) { TagsSettings.pendingScope = .member(l.1) }
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
        /// A double-click on a name: the cursor goes into the words where they are, and the name is written when the typing ends.
        private func rename(_ h: (NSRect, StudioFrame.Place, String, Design.Text), at p: NSPoint) {
            renaming = h.1; needsDisplay = true
            InlineName.edit(h.2, style: h.3, in: self, x: h.0.minX, baseline: h.0.minY + Self.line, width: h.0.width, at: p) { [weak self] name in
                self?.renaming = nil; self?.needsDisplay = true
                if let n = name, n != h.2 { self?.onRename?(h.1, n) }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (id, name, colours) = pressed, PaletteDrag.counts(event, from: pressedAt) else { return }
            pressed = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        private var pressedIcon: (NSRect, Int, UUID)?
        override func mouseUp(with event: NSEvent) {
            pressed = nil
            if let h = pressedIcon {
                pressedIcon = nil
                if h.0.contains(convert(event.locationInWindow, from: nil)) {
                    switch h.1 {
                    case 0: onFavourite?(h.2)
                    case 1: onTarget?(h.2)
                    default: onGear?(h.2, self, h.0)
                    }
                }
            }
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

        // MARK: A palette dropped on a member, or on one of the member's own palettes

        private func member(at p: NSPoint) -> UUID? {
            var y: CGFloat = 0
            for (i, s) in shown.enumerated() {
                switch s.row {
                case .group: y += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row(_, _, let place, _):
                    if case .project(let id) = place, NSRect(x: 0, y: y, width: bounds.width, height: Self.row).contains(p) { return id }
                    y += Self.row
                case .node(_, _, let pid, _, let drop, _):
                    if drop, NSRect(x: 0, y: y, width: bounds.width, height: Self.row).contains(p) { return pid }
                    y += Self.row
                case .tag: y += Self.row
                case .palette(let pr):
                    if let m = pr.project, NSRect(x: 0, y: y, width: bounds.width, height: Self.two).contains(p) { return m }
                    y += Self.two
                }
            }
            return nil
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let over = member(at: convert(sender.draggingLocation, from: nil))
            if over != target { target = over; needsDisplay = true }
            return over == nil ? [] : .move
        }
        override func draggingExited(_ sender: NSDraggingInfo?) { target = nil; needsDisplay = true }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { target = nil; needsDisplay = true }
            guard let m = member(at: convert(sender.draggingLocation, from: nil)), let s = PaletteDrag.palette(on: sender.draggingPasteboard) else { return false }
            onDrop?(s, m)
            return true
        }
    }
}

/// A palette on the pasteboard while it is dragged between the rails: its id under a type of the app's own.
enum PaletteDrag {
    static let type = NSPasteboard.PasteboardType("com.mmffdev.colorgain.palette")

    /// A drag begins only once the pointer is a clear distance from where the mouse went down and a beat has passed,
    /// so a click, or the small wobble in one, never lifts a palette.
    static let threshold: CGFloat = 8, beat: TimeInterval = 0.12
    static func counts(_ event: NSEvent, from press: (NSPoint, TimeInterval)) -> Bool {
        hypot(event.locationInWindow.x - press.0.x, event.locationInWindow.y - press.0.y) >= threshold && event.timestamp - press.1 >= beat
    }

    static func palette(on board: NSPasteboard) -> UUID? {
        board.pasteboardItems?.first?.string(forType: type).flatMap { UUID(uuidString: $0) }
    }

    /// Starts the drag from a rail: the drag image is the palette's strip with its name, as the rails draw it.
    static func begin(_ id: UUID, name: String, colours: [NSColor], event: NSEvent, in view: NSView & NSDraggingSource) {
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: type)
        let size = NSSize(width: 180, height: 24)
        let image = NSImage(size: size, flipped: true) { r in
            Design.card.setFill(); r.fill()
            let strip = NSRect(x: 4, y: 7, width: 44, height: 10)
            if colours.isEmpty { Design.mist.setFill(); strip.fill() }
            else {
                let bw = strip.width / CGFloat(colours.count)
                for (k, c) in colours.enumerated() { c.setFill(); NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: bw + 0.5, height: strip.height).fill() }
            }
            Design.attributed(name, .body).draw(at: NSPoint(x: 56, y: 4))
            Design.rule.setStroke()
            let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            return true
        }
        let drag = NSDraggingItem(pasteboardWriter: item)
        let p = view.convert(event.locationInWindow, from: nil)
        drag.setDraggingFrame(NSRect(x: p.x - 20, y: p.y - 12, width: size.width, height: size.height), contents: image)
        view.beginDraggingSession(with: [drag], event: event, source: view)
    }
}

/// The context rail: a table. A palette row carries a strip of every colour in it before its name and
/// its count at the right; a group row is a Label, one step in for each level down; an item row is a
/// name with a detail at the right, going somewhere when it has a place.
final class PaletteTable: StudioRail {
    enum Row {
        /// A group's heading, with the place its page is and whether that page is showing; `fold`, when it holds rows, the key
        /// its open or shut state is kept under and whether it is open. A shut group's rows are left out by whoever fills the rail.
        case group(String, Int, StudioFrame.Place? = nil, Bool = false, fold: (key: String, open: Bool)? = nil)
        case palette(UUID, String, Int, [NSColor], Bool, Int)
        case item(String, String?, Int, StudioFrame.Place?, Bool)
        /// A word on a hairline between runs of rows, as "Just Added" parts this week's palettes from the rest.
        case divider(String)
    }
    var onPick: ((StudioFrame.Place) -> Void)?
    var onRename: ((StudioFrame.Place, String) -> Void)?
    /// A group's caret pressed: its key, and whether it is now shut.
    var onShut: ((String, Bool) -> Void)?
    private var table: Body { body as! Body }
    init() {
        super.init(body: Body()); labels = ("Palette", "Colours")
        table.onPick = { [weak self] p in self?.onPick?(p) }
        table.onRename = { [weak self] p, n in self?.onRename?(p, n) }
        table.onShut = { [weak self] k, s in self?.onShut?(k, s) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(heading: String, labels: (String, String), rows: [Row]) {
        self.heading = heading; self.labels = labels; table.rows = rows; needsLayout = true
        // The chosen row is brought into view when it is out of it, which the eye expects when it was chosen elsewhere;
        // a row already in view, clicked here, leaves the list exactly where it is.
        var y: CGFloat = 0
        for r in rows {
            let h = Body.height(of: r)
            switch r {
            case .palette(_, _, _, _, true, _), .item(_, _, _, _, true):
                layoutSubtreeIfNeeded()
                let row = NSRect(x: 0, y: y, width: 1, height: h)
                if !body.visibleRect.contains(row) { body.scrollToVisible(NSRect(x: 0, y: max(0, y - h), width: 1, height: h * 3)) }
                return
            default: y += h
            }
        }
    }

    final class Body: RailBody, NSDraggingSource {
        var rows: [Row] = [] { didSet { rollover.settle() } }
        var onPick: ((StudioFrame.Place) -> Void)?
        var onRename: ((StudioFrame.Place, String) -> Void)?
        var onShut: ((String, Bool) -> Void)?
        static var row: CGFloat { unit }
        static var group: CGFloat { unit }
        static var divider: CGFloat { unit }
        static let step: CGFloat = 16, strip: CGFloat = 44
        /// A group's caret stands where its words would, on the column; the words follow it.
        static let caretSlot: CGFloat = 12
        private var hits: [(NSRect, StudioFrame.Place)] = []
        private var caretHits: [(NSRect, String, Bool)] = []
        private var nameHits: [(NSRect, StudioFrame.Place, String, Design.Text)] = []
        private var renaming: StudioFrame.Place?
        private var pressed: (UUID, String, [NSColor])?
        /// Where and when the mouse went down, so a drag starts only once the pointer has clearly left the press.
        private var pressedAt: (NSPoint, TimeInterval) = (.zero, 0)
        /// The schema page's rollover: the pane flies out under the pointer and stays out on the chosen row, over its Mist ground.
        private let rollover = Rollover<StudioFrame.Place>()
        static func height(of r: Row) -> CGFloat {
            switch r { case .group: return group; case .divider: return divider; default: return row }
        }
        override var height: CGFloat { rows.reduce(0) { $0 + Self.height(of: $1) } + Self.unit }

        override init(frame: NSRect) {
            super.init(frame: frame)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
            rollover.keys = { [weak self] in self?.rows.compactMap { Self.place(of: $0).map { $0.0 } } ?? [] }
            rollover.locked = { [weak self] k in self?.rows.contains { Self.place(of: $0).map { $0.0 == k && $0.1 } ?? false } ?? false }
            rollover.redraw = { [weak self] in self?.needsDisplay = true }
        }
        required init?(coder: NSCoder) { fatalError() }

        /// Where a row goes, and whether that is the place showing; nil for a row that goes nowhere.
        static func place(of r: Row) -> (StudioFrame.Place, Bool)? {
            switch r {
            case .group(_, _, let p?, let chosen, _): return (p, chosen)
            case .palette(let id, _, _, _, let chosen, _): return (.palette(id), chosen)
            case .item(_, _, _, let p?, let chosen): return (p, chosen)
            default: return nil
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let right = bounds.width - insetRight
            hits = []; nameHits = []; caretHits = []
            // Where each row's words begin and how far they run, so the rollover's pane can reach a step past them.
            func lead(_ r: Row) -> (x: CGFloat, words: NSAttributedString, room: CGFloat)? {
                switch r {
                case .group(let name, let indent, _, let chosen, _):
                    let x = inset + CGFloat(indent) * Self.step + Self.caretSlot
                    return (x, Design.attributed(name, chosen ? .bodyStrong : .body), right - x)
                case .palette(_, let name, let count, _, let chosen, let indent):
                    let x = inset + CGFloat(indent) * Self.step + Self.strip + 10
                    return (x, Design.attributed(name, chosen ? .bodyStrong : .body), right - x - Design.attributed(String(count), .caption).size().width - 12)
                case .item(let name, let detail, let indent, _, let chosen):
                    let x = inset + CGFloat(indent) * Self.step
                    return (x, Design.attributed(name, chosen ? .bodyStrong : .body), right - x - Design.attributed(detail ?? "", .caption).size().width - 12)
                case .divider: return nil
                }
            }
            // The grounds and the panes first, as the schema page lays them: the chosen row's Mist from a point over the rule
            // above it, then each pane as far out as it has flown, to a step past the words; the rows' words and rules go over them.
            var y: CGFloat = 0
            for r in rows {
                let h = Self.height(of: r), box = NSRect(x: 0, y: y, width: bounds.width, height: h)
                if let (p, chosen) = Self.place(of: r) {
                    if chosen { fill(NSRect(x: 0, y: box.minY - 1, width: bounds.width, height: box.height + 1), Design.mist) }
                    if let l = lead(r) { rollover.pane(p, box: box, reach: l.x + min(l.words.size().width, l.room) + Self.step) }
                }
                y += h
            }
            y = 0
            for r in rows {
                switch r {
                case .group(let name, let indent, let place, let chosen, let fold):
                    // A first-order header: Title Case, the body weight, on the shared line; the one whose page is showing on the ground.
                    // When it holds rows its caret leads it, on the column; a heading that goes nowhere opens and shuts on a click anywhere.
                    let x = inset + CGFloat(indent) * Self.step, b = y + Self.line
                    if let f = fold {
                        Caret.draw(open: f.open, centre: NSPoint(x: x + 4.5, y: b - 5), colour: chosen ? Design.ink : Design.quiet)
                        let hit = place == nil ? NSRect(x: 0, y: y, width: bounds.width, height: Self.group) : NSRect(x: x - 6, y: y, width: Self.caretSlot + 6, height: Self.group)
                        caretHits.append((hit, f.key, f.open))
                    }
                    Design.attributed(name, chosen ? .bodyStrong : .body).draw(x: x + Self.caretSlot, baseline: b, width: right - x - Self.caretSlot)
                    if let p = place { hits.append((NSRect(x: 0, y: y, width: bounds.width, height: Self.group), p)) }
                    y += Self.group
                case .palette(let id, let name, let count, let colours, let chosen, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, x = inset + CGFloat(indent) * Self.step
                    // The whole palette as a strip, each colour an equal band, its foot on the line; an empty one is Mist.
                    let strip = NSRect(x: x, y: b - 10, width: Self.strip, height: 10)
                    if colours.isEmpty { fill(strip, Design.mist) }
                    else {
                        let bw = strip.width / CGFloat(colours.count)
                        for (k, c) in colours.enumerated() { fill(NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: k == colours.count - 1 ? strip.width - CGFloat(k) * bw : bw + 0.5, height: strip.height), c) }
                    }
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let nameX = x + Self.strip + 10, nameW = right - nameX - countText.size().width - 12
                    if renaming != .palette(id) { Design.attributed(name, chosen ? .bodyStrong : .body).draw(x: nameX, baseline: b, width: nameW) }
                    nameHits.append((NSRect(x: nameX, y: y, width: nameW, height: Self.row), .palette(id), name, chosen ? .bodyStrong : .body))
                    countText.draw(right: right, baseline: b)
                    hairline(x: inset, y: y + Self.row - 1, width: right - inset, Design.mist)
                    hits.append((box, .palette(id)))
                    y += Self.row
                case .item(let name, let detail, let indent, let place, let chosen):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let b = y + Self.line, x = inset + CGFloat(indent) * Self.step
                    let detailText = Design.attributed(detail ?? "", .caption, colour: Design.quiet)
                    let dim = place == nil && detail == nil && name == "None found"
                    let nameW = right - x - detailText.size().width - 12
                    if renaming == nil || renaming != place { Design.attributed(name, chosen ? .bodyStrong : .body, colour: dim ? Design.soft : Design.ink).draw(x: x, baseline: b, width: nameW) }
                    if case .project? = place { nameHits.append((NSRect(x: x, y: y, width: nameW, height: Self.row), place!, name, chosen ? .bodyStrong : .body)) }
                    if detail != nil { detailText.draw(right: right, baseline: b) }
                    hairline(x: inset, y: y + Self.row - 1, width: right - inset, Design.mist)
                    if let p = place { hits.append((box, p)) }
                    y += Self.row
                case .divider(let word):
                    Design.attributed(word, .label, colour: Design.quiet).draw(x: inset, baseline: y + Self.line)
                    hairline(x: inset, y: y + Self.divider - 1, width: right - inset, Design.rule)
                    y += Self.divider
                }
            }
            if rows.isEmpty { Design.attributed("Nothing found", .caption, colour: Design.soft).draw(x: inset, baseline: y + Self.line) }
        }

        // MARK: The pointer

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            rollover.moved(hits.first { $0.0.contains(p) }?.1)
        }
        override func mouseExited(with event: NSEvent) { rollover.moved(nil) }

        private func palette(at p: NSPoint) -> (UUID, String, [NSColor])? {
            var y: CGFloat = 0
            for r in rows {
                if case .palette(let id, let name, _, let colours, _, _) = r, NSRect(x: 0, y: y, width: bounds.width, height: Self.row).contains(p) { return (id, name, colours) }
                y += Self.height(of: r)
            }
            return nil
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            // A caret opens or shuts its group and goes nowhere; the group's words still open its page.
            if let c = caretHits.first(where: { $0.0.contains(p) }) { onShut?(c.1, c.2); return }
            if event.clickCount == 2, let h = nameHits.first(where: { $0.0.contains(p) }) {
                renaming = h.1; needsDisplay = true
                InlineName.edit(h.2, style: h.3, in: self, x: h.0.minX, baseline: h.0.minY + Self.line, width: h.0.width, at: p) { [weak self] name in
                    self?.renaming = nil; self?.needsDisplay = true
                    if let n = name, n != h.2 { self?.onRename?(h.1, n) }
                }
                return
            }
            pressed = palette(at: p); pressedAt = (event.locationInWindow, event.timestamp)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (id, name, colours) = pressed, PaletteDrag.counts(event, from: pressedAt) else { return }
            pressed = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        override func mouseUp(with event: NSEvent) { pressed = nil }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    }
}

/// The history rail: a step on two units. The first line, the step's mark where a row's mark stands, its title, and when at
/// the right; the second, the colours it touched as small squares standing on the line, then what it did to whom.
final class HistoryRail: StudioRail {
    /// A step: its mark and title on the first line with when it was, the colours it touched and what it did on the second.
    struct Row { let symbol: String; let title: String; let detail: String; let time: String; let chips: [NSColor]; let hex: String? }
    var onPick: ((String) -> Void)?
    private var list: Body { body as! Body }
    init() { super.init(body: Body()); heading = "History"; labels = ("Step", "When"); list.onPick = { [weak self] h in self?.onPick?(h) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row]) { list.rows = rows; needsLayout = true }

    final class Body: RailBody {
        var rows: [Row] = [] { didSet { needsDisplay = true } }
        var onPick: ((String) -> Void)?
        static var row: CGFloat { unit * 2 }
        /// The mark's 14 and the gap to the words, as rail1's rows have it; a chip is 10 square, 4 apart, 8 clear of the words.
        static let words: CGFloat = 20, chip: CGFloat = 10, chipGap: CGFloat = 4
        private var hits: [(NSRect, String)] = []
        override var height: CGFloat { CGFloat(rows.count) * Self.row + Self.unit }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - insetRight
            hits = []
            for r in rows {
                let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                let b1 = y + Self.line, b2 = y + Self.unit + Self.line, x0 = inset + Self.words
                // The step's mark where a row's mark stands, the title after it, the time at the right.
                RowMark.draw(r.symbol, x: inset, baseline: b1, colour: Design.quiet)
                let time = Design.attributed(r.time, .caption, colour: Design.quiet)
                Design.attributed(r.title, .body).draw(x: x0, baseline: b1, width: right - x0 - time.size().width - 12)
                time.draw(right: right, baseline: b1)
                // The second line, under the title: the chips, their feet on the caption's line, then what it did to whom.
                var x = x0
                for c in r.chips { fill(NSRect(x: x, y: b2 - Self.chip, width: Self.chip, height: Self.chip), c); x += Self.chip + Self.chipGap }
                if !r.chips.isEmpty { x += 8 - Self.chipGap }
                Design.attributed(r.detail, .caption, colour: Design.quiet).draw(x: x, baseline: b2, width: right - x)
                hairline(x: inset, y: box.maxY - 1, width: right - inset, Design.mist)
                if let h = r.hex { hits.append((box, h)) }
                y += Self.row
            }
            if rows.isEmpty { Design.attributed("Nothing found", .caption, colour: Design.soft).draw(x: inset, baseline: y + Self.line) }
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
    }
}

// MARK: - The page

/// The page: 34 clear, then a Split header on its own six columns, a hairline, 22 clear, and the grid of tiles.
final class StudioPage: NSView, Overlay {
    var inset: CGFloat = 8 { didSet { needsLayout = true } }
    var insetRight: CGFloat = 8 { didSet { needsLayout = true } }
    let grid = TileGrid()
    let settings = CatalogueSettings()
    let schema = SchemaSettings()
    private let scroll = NSScrollView()
    /// The settings scroll as one piece, the open accordion and all, when they outgrow the page.
    private let settingsScroll = NSScrollView(), schemaScroll = NSScrollView()
    /// The way to make a member, under the header when the page lists members.
    private let newButton = SwissButton("New Project", .primary)
    var onNew: (() -> Void)?
    /// Export beside New, where a page shows a level that can go out as one file.
    private let exportButton = SwissButton("Export\u{2026}", .secondary)
    var onExport: (() -> Void)?
    /// How many tiles sit across: the slider in the page's header, right-aligned before the arrow and centred on it, shown with the tiles.
    private let slider = MiniSlider()
    var onAcross: ((Int) -> Void)?
    /// The colour model the tiles' captions are in, chosen on the menu before the slider.
    var format: ColourFormat = .hex { didSet { needsDisplay = true } }
    var onFormat: (() -> Void)?
    private var formatRect = NSRect.zero
    private var dropped: SwissDropdown.MenuPanel?
    static let models: [ColourFormat] = [.hex, .rgb, .hsl, .hsv, .cmyk, .p3, .adobeRGB, .rec2020, .lab, .lch, .luv, .oklch, .oklab, .xyz, .float, .linear]
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeFormats() }
    private func closeFormats() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }
    private func openFormats() {
        guard let win = window else { return }
        closeFormats()
        let items = Self.models.map { $0.label }
        let panel = SwissDropdown.MenuPanel(items: items, chosen: format.label, width: 160) { [weak self] i in
            guard let self = self else { return }
            self.closeFormats()
            self.format = Self.models[i]
            self.onFormat?()
        }
        let s = win.convertToScreen(convert(formatRect, to: nil))
        panel.place(below: NSPoint(x: s.maxX - 160, y: s.minY - 4))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }
    enum Section: Hashable { case tiles, catalogues, schema, shortcuts, halo, tags, lab, contrast, share }
    private var section = Section.tiles
    /// The sections beyond the tiles, the catalogues and the schema, each in a scroll of its own, laid out like the catalogues.
    private var extras: [Section: (view: PageSection, scroll: NSScrollView)] = [:]
    func add(_ view: PageSection, as s: Section) {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = view
        scroll.isHidden = true
        addSubview(scroll)
        view.onResize = { [weak self] in self?.needsLayout = true }
        extras[s] = (view, scroll)
    }
    /// Taking the whole width: the arrow turns to "close", and a press on it gives the rails back.
    var expanded = false { didSet { needsDisplay = true } }
    var onArrow: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if AreaHeader.arrowRect(in: bounds, insetRight: insetRight).insetBy(dx: -8, dy: -8).contains(p) { onArrow?(); return }
        if !slider.isHidden, formatRect.contains(p) { openFormats(); return }
        super.mouseDown(with: event)
    }
    private var title = ""
    private var meta: (String, String) = ("", "")
    /// The area header, then 16 clear before the tiles.
    static var headerHeight: CGFloat { AreaHeader.height }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = grid
        addSubview(scroll)
        settingsScroll.drawsBackground = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.scrollerStyle = .overlay
        settingsScroll.documentView = settings
        settingsScroll.isHidden = true
        addSubview(settingsScroll)
        schemaScroll.drawsBackground = false
        schemaScroll.hasVerticalScroller = true
        schemaScroll.autohidesScrollers = true
        schemaScroll.scrollerStyle = .overlay
        schemaScroll.documentView = schema
        schemaScroll.isHidden = true
        addSubview(schemaScroll)
        newButton.isHidden = true
        newButton.target = self; newButton.action = #selector(makeNew)
        addSubview(newButton)
        exportButton.isHidden = true
        exportButton.target = self; exportButton.action = #selector(exportPressed)
        addSubview(exportButton)
        slider.onChange = { [weak self] v in self?.onAcross?(4 + Int((v * 4).rounded())) }
        addSubview(slider)
        grid.onResize = { [weak self] in self?.needsLayout = true }
        settings.onResize = { [weak self] in self?.needsLayout = true }
        schema.onResize = { [weak self] in self?.needsLayout = true }
    }

    /// What the page shows: the tiles, the Catalogues settings or the Schema settings, one in place of the others.
    func show(_ s: Section) {
        section = s
        scroll.isHidden = s != .tiles
        settingsScroll.isHidden = s != .catalogues
        schemaScroll.isHidden = s != .schema
        for (k, e) in extras { e.scroll.isHidden = k != s; if k == s { e.view.reload() } }
        if s == .catalogues { settings.reload() }
        if s == .schema { schema.reload() }
        newButton.isHidden = true
        exportButton.isHidden = true
        needsLayout = true
    }
    /// The page that is showing, whole, at the screen's scale: what --snap writes.
    func snapshot() -> NSBitmapImageRep? {
        let v: NSView
        switch section {
        case .tiles: v = grid
        case .catalogues: v = settings
        case .schema: v = schema
        default: guard let e = extras[section], let view = e.view as? NSView else { return nil }; v = view
        }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }
    /// The Export button beside New; nil takes it away.
    func showExport(_ title: String?) {
        exportButton.isHidden = title == nil
        if let t = title { exportButton.title = t; exportButton.invalidateIntrinsicContentSize() }
        needsLayout = true
    }
    @objc private func exportPressed() { onExport?() }
    /// The New button under the header, with its word; nil takes it away.
    func showNew(_ title: String?) {
        newButton.isHidden = title == nil
        if let t = title { newButton.title = t; newButton.invalidateIntrinsicContentSize() }
        needsLayout = true
    }
    @objc private func makeNew() { onNew?() }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func set(title: String, meta: (String, String), items: [TileGrid.Item]) {
        self.title = title; self.meta = meta
        grid.items = items
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var top = Self.headerHeight
        let u = Design.App.unit
        // The slider: one column wide, its track through the arrow's centre, ending a step before the arrow.
        slider.isHidden = section != .tiles
        let arrowCentre = AreaHeader.headingBaseline - 5
        let column = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        slider.frame = NSRect(x: bounds.width - insetRight - 16 - 24 - column, y: arrowCentre - 8, width: column, height: 16)
        if !newButton.isHidden || !exportButton.isHidden {
            // The buttons stand on the second unit's foot, clear of the rule above it; the tiles a unit below.
            var x = inset
            if !newButton.isHidden { newButton.frame = NSRect(x: x, y: top + 2 * u - 32, width: newButton.intrinsicContentSize.width, height: 32); x += newButton.frame.width + 12 }
            if !exportButton.isHidden { exportButton.frame = NSRect(x: x, y: top + 2 * u - 32, width: exportButton.intrinsicContentSize.width, height: 32) }
            top += 2 * u
        }
        let tilesTop = top + (section == .tiles ? u : 0)
        scroll.frame = NSRect(x: inset, y: tilesTop, width: bounds.width - inset - insetRight, height: bounds.height - tilesTop)
        settingsScroll.frame = NSRect(x: inset, y: top, width: scroll.frame.width, height: bounds.height - top)
        let sh = settings.height(forWidth: scroll.frame.width)
        settings.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, sh))
        settingsScroll.verticalScrollElasticity = sh > scroll.frame.height ? .allowed : .none
        // The schema's scroll starts at the page's edge, so a row's ground can reach the rail's divider; its words start a column in.
        schemaScroll.frame = NSRect(x: 0, y: top, width: inset + scroll.frame.width, height: bounds.height - top)
        schema.leading = inset
        let kh = schema.height(forWidth: inset + scroll.frame.width)
        schema.frame = NSRect(x: 0, y: 0, width: inset + scroll.frame.width, height: max(schemaScroll.frame.height, kh))
        schemaScroll.verticalScrollElasticity = kh > scroll.frame.height ? .allowed : .none
        for (_, e) in extras {
            e.scroll.frame = settingsScroll.frame
            let eh = e.view.height(forWidth: scroll.frame.width)
            e.view.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(e.scroll.frame.height, eh))
            // Tags is laid out as the schema is: from the page's edge, its words a column in.
            if let t = e.view as? TagsSettings {
                e.scroll.frame = schemaScroll.frame
                t.leading = inset
                t.frame = NSRect(x: 0, y: 0, width: schemaScroll.frame.width, height: max(e.scroll.frame.height, eh))
            } else if let sp = e.view as? SharePage {
                e.scroll.frame = schemaScroll.frame
                sp.leading = inset
                sp.frame = NSRect(x: 0, y: 0, width: schemaScroll.frame.width, height: max(e.scroll.frame.height, eh))
            }
            e.scroll.verticalScrollElasticity = eh > e.scroll.frame.height ? .allowed : .none
        }
        grid.width = scroll.frame.width
        grid.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, grid.height))
        scroll.verticalScrollElasticity = grid.height > scroll.frame.height ? .allowed : .none
        grid.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The same header as the rails: the name as the Heading, its two facts as the Labels, the Rule under.
        AreaHeader.draw(heading: title, left: meta.0, right: meta.1, in: bounds, inset: inset, insetRight: insetRight, arrow: expanded ? .close : .open)
        // The colour model before the slider, a quiet word with its chevron, on the heading's line.
        formatRect = .zero
        if !slider.isHidden {
            let b = AreaHeader.headingBaseline
            let t = Design.attributed(format.label, .caption, colour: Design.quiet)
            let right = slider.frame.minX - 24
            t.draw(right: right - 14, baseline: b)
            Design.quiet.setStroke()
            let c = NSBezierPath(); c.lineWidth = 1
            c.move(to: NSPoint(x: right - 9, y: b - 6)); c.line(to: NSPoint(x: right - 5, y: b - 2)); c.line(to: NSPoint(x: right - 1, y: b - 6))
            c.stroke()
            formatRect = NSRect(x: right - 14 - t.size().width - 8, y: b - 20, width: t.size().width + 24, height: 28)
        }
    }
}

/// The tiles: `across` to a row, or as many as there are when fewer, 16 apart and justified to the block
/// so the first and last meet the Rule's ends; each a Card with its colour block 116 high over a name and
/// a caption. A colour tile carries one colour and its hex; a palette card a strip of its colours
/// and its count, and opens the palette.
final class TileGrid: NSView {
    struct Item { let title: String; let caption: String; let colours: [NSColor]; let hex: String?; let id: UUID? }
    var items: [Item] = [] { didSet { onResize?() } }
    /// Words shown in place of tiles when there are none, as a member's notes on its Information page; nil says Nothing Found.
    var note: String? { didSet { needsDisplay = true } }
    var across = 6 { didSet { onResize?() } }
    var width: CGFloat = 600
    var chosenHex: String? { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onResize: (() -> Void)?
    /// A click on the colour itself copies the caption's value; the halo mark at the right of the caption opens the halo over it.
    var onCopy: ((String) -> Void)?
    var onHalo: ((String, NSRect) -> Void)?
    private var markHits: [(NSRect, Int)] = []
    /// On the beat: a block of five units, two units of words with the title and the caption on their lines, a unit between rows; across, the page's own gutter.
    static var block: CGFloat { Design.App.unit * 5 }
    static var words: CGFloat { Design.App.unit * 2 }
    static var rowGap: CGFloat { Design.App.unit }
    static let gap: CGFloat = 16
    override var isFlipped: Bool { true }

    /// How many tiles a row holds: the slider's count, or fewer when there are fewer tiles, so one row always fills the block.
    private var columns: Int { max(1, min(across, max(items.count, 1))) }
    /// A column's left edge: the row justified to the block, every edge on a whole point, the last tile's right edge on the block's.
    private func left(_ c: Int) -> CGFloat { (CGFloat(c) * (width + Self.gap) / CGFloat(columns)).rounded() }
    var height: CGFloat {
        let rows = (items.count + columns - 1) / columns
        return CGFloat(rows) * (Self.block + Self.words + Self.rowGap)
    }
    private func rect(_ i: Int) -> NSRect {
        let c = i % columns, x = left(c)
        return NSRect(x: x, y: CGFloat(i / columns) * (Self.block + Self.words + Self.rowGap), width: left(c + 1) - Self.gap - x, height: Self.block + Self.words)
    }

    override func draw(_ dirtyRect: NSRect) {
        markHits = []
        for (i, it) in items.enumerated() {
            let r = rect(i)
            if let hex = it.hex, hex != "" {
                // The halo mark on the caption's line, at the right, for the value beside it.
                let capB = r.minY + Self.block + Design.App.unit + Design.App.textBaseline
                let g = NSRect(x: r.maxX - 6 - 16, y: capB - 13, width: 16, height: 16)
                markHits.append((g.insetBy(dx: -4, dy: -4), i))
            }
            guard r.intersects(dirtyRect) else { continue }
            // No box: the colour block, the words on the ground beneath it, and nothing drawn around them.
            let block = NSRect(x: r.minX, y: r.minY, width: r.width, height: Self.block)
            if it.colours.isEmpty { fill(block, Design.mist) }
            else {
                // A palette's colours share the block as equal bands, a single colour takes it whole.
                let bw = block.width / CGFloat(it.colours.count)
                for (k, c) in it.colours.enumerated() { fill(NSRect(x: block.minX + CGFloat(k) * bw, y: block.minY, width: k == it.colours.count - 1 ? block.width - CGFloat(k) * bw : bw + 0.5, height: block.height), c) }
            }
            Design.attributed(it.title, .bodyStrong).draw(x: r.minX + 6, baseline: block.maxY + Design.App.textBaseline, width: r.width - 12)
            let capB = block.maxY + Design.App.unit + Design.App.textBaseline
            Design.attributed(it.caption, .caption, colour: Design.quiet).draw(x: r.minX + 6, baseline: capB, width: r.width - 12 - (it.hex == nil ? 0 : 24))
            if it.hex != nil { Design.haloMark(in: NSRect(x: r.maxX - 6 - 16, y: capB - 13, width: 16, height: 16), colour: Design.quiet) }
            if let h = it.hex, h == chosenHex {
                // The chosen tile: a one-point ring in the Rule, the same grey that edges the panels.
                Design.rule.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
            }
        }
        if items.isEmpty, let n = note {
            // Words in place of tiles, a member's notes: the Lead, no wider than 34em, every line on the beat and the first on the first unit's line.
            let font = Design.Text.lead.font(), p = NSMutableParagraphStyle()
            p.minimumLineHeight = Design.App.unit; p.maximumLineHeight = Design.App.unit
            let text = NSAttributedString(string: n, attributes: [.font: font, .foregroundColor: Design.ink, .kern: Design.Text.lead.size * Design.Text.lead.tracking, .paragraphStyle: p])
            // A fixed line sets its glyphs at its foot, the descender clear of it: the first line's top is where that puts the baseline on the line.
            let top = Design.App.textBaseline - (Design.App.unit + font.descender)
            text.draw(with: NSRect(x: 0, y: top, width: min(bounds.width, Design.Text.lead.size * 34), height: bounds.height - top), options: [.usesLineFragmentOrigin])
        } else if items.isEmpty { Design.attributed("Nothing found", .lead, colour: Design.soft).draw(x: 0, baseline: Design.App.textBaseline) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let m = markHits.first(where: { $0.0.contains(p) }), let h = items[m.1].hex { onPick?(h); onHalo?(h, m.0); return }
        guard let i = items.indices.first(where: { rect($0).contains(p) }) else { return }
        if let h = items[i].hex {
            onPick?(h)
            // The colour block itself copies its value; the words beneath only choose.
            let block = NSRect(x: rect(i).minX, y: rect(i).minY, width: rect(i).width, height: Self.block)
            if block.contains(p) { onCopy?(items[i].caption) }
        }
        else if let id = items[i].id, event.clickCount == 2 { onOpen?(id) }
        else if let id = items[i].id { onOpen?(id) }
    }
}

// MARK: - Settings: Catalogues

/// The Catalogues settings on the page. The actions along the top, then one row per catalogue: Set
/// Active before a small static square, the catalogue's colour once it has one, then its name; a click
/// on Set Active swaps the open catalogue without opening the row, a click on the row opens it like an
/// accordion, everything in it on the row's own left edge. About, with the notes kept in the catalogue's
/// file on a hairline; All Colours, the count; Directory, its folder; Contents, the catalogue as rail1
/// lists it, every member and palette with a square to tick, its colours as a strip, and Duplicate,
/// Relocate and Remove on its right; once something is ticked, a bar with Relocate and Remove for all
/// of it. Relocate drops the list of other catalogues. Then the hue strip while a colour is being
/// chosen, and Assign Colour, Duplicate and Remove for the catalogue itself at the right, Main like any
/// other while another catalogue is on the list. Remove asks
/// on the window's own confirm panel, with what the catalogue holds and the choice of moving all of it
/// to another catalogue first. The page scrolls as one piece.
final class CatalogueSettings: NSView, NSTextViewDelegate, Overlay {
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    private var names: [String] = []
    private var expanded: String?
    /// How far open each row's panel is, 0 to 1; a row not here is shut. Driven towards its target by the clock.
    private var openness: [String: CGFloat] = [:]
    private var clock: Timer?
    private var hover: String?
    private var lineHover: Item?
    private var picking = false
    /// What the open catalogue holds, listed as rail1 lists it, and what is ticked.
    private var contents: Library?
    private var lines: [Line] = []
    private var ticked = Set<Item>()
    private var rowHits: [(NSRect, String)] = [], activeHits: [(NSRect, String)] = [], actionHits: [(NSRect, Int)] = []
    private var lineHits: [(NSRect, Item)] = [], lineActionHits: [(NSRect, Item, Int)] = [], barHits: [(NSRect, Int)] = [], addHits: [(NSRect, UUID, String)] = []
    private var spectrum = NSRect.zero
    private var dropped: SwissDropdown.MenuPanel?
    private let openButton = SwissButton("Open Catalogue\u{2026}", .primary)
    private let newButton = SwissButton("New Catalogue", .secondary)
    private let finderButton = SwissButton("Show In Finder", .secondary)
    private let importButton = SwissButton("Import\u{2026}", .secondary)
    private let exportButton = SwissButton("Export Catalogue\u{2026}", .secondary)
    var onImport: (() -> Void)?
    var onExport: (() -> Void)?
    private let aboutScroll = NSScrollView()
    private let about = NSTextView()
    /// On the beat: every row a unit, the notes three, the hue strip two; text on the unit's line.
    static var u: CGFloat { Design.App.unit }
    static var lineY: CGFloat { Design.App.textBaseline }
    static var row: CGFloat { u }
    static var strip: CGFloat { u * 2 }
    static var notes: CGFloat { u * 3 }
    static var line: CGFloat { u }
    static var bar: CGFloat { u }
    static let square: CGFloat = 12, step: CGFloat = 24
    /// The catalogue row: Set Active and its circle take the first 92 points, then the square, then the name.
    private static let activeWidth: CGFloat = 92
    /// Inside the open row, top down: About and its notes on a hairline; All Colours; Directory; Contents and its rule; the lines.
    private static var aboutLabel: CGFloat { lineY }
    private static var aboutBox: CGFloat { u }
    private static var coloursLabel: CGFloat { 4 * u + lineY }
    private static var coloursValue: CGFloat { 5 * u + lineY }
    private static var directoryLabel: CGFloat { 6 * u + lineY }
    private static var directory: CGFloat { 7 * u + lineY }
    private static var contentsLabel: CGFloat { 8 * u + lineY }
    private static var contentsRule: CGFloat { 9 * u - 1 }
    private static var linesTop: CGFloat { 9 * u }
    private static var actions: CGFloat { u }
    /// A line's parts: the square, then its colours as a strip, then the name.
    private static let inset: CGFloat = 16, stripWidth: CGFloat = 72, stripHeight: CGFloat = 12
    private static let coloursKey = "catalogue.colours"

    private enum Item: Hashable { case project(UUID), palette(UUID) }
    /// One line of the contents: a heading; a thing with its colours and a count, tickable when it is a member or a palette; or a warning that a collection is empty.
    private struct Line { var text: String; var count: String; var item: Item?; var indent: Int; var heading: Bool; var warning = false; var hexes: [String] = []; var collection: UUID? = nil; var member = "" }

    init() {
        super.init(frame: .zero)
        openButton.target = self; openButton.action = #selector(openCatalogue)
        newButton.target = self; newButton.action = #selector(newCatalogue)
        finderButton.target = self; finderButton.action = #selector(showInFinder)
        importButton.target = self; importButton.action = #selector(importPressed)
        exportButton.target = self; exportButton.action = #selector(exportPressed)
        aboutScroll.documentView = about
        aboutScroll.hasVerticalScroller = true
        aboutScroll.autohidesScrollers = true
        aboutScroll.drawsBackground = false
        aboutScroll.borderType = .noBorder
        aboutScroll.isHidden = true
        about.font = Design.Text.body.font()
        about.textColor = Design.ink
        about.drawsBackground = false
        about.insertionPointColor = Design.ink
        // No inset: the words start on the row's own left edge, under the heading.
        about.textContainerInset = .zero
        about.textContainer?.lineFragmentPadding = 0
        about.isRichText = false
        about.delegate = self
        about.autoresizingMask = [.width]
        about.isVerticallyResizable = true
        about.textContainer?.widthTracksTextView = true
        for v in [openButton, newButton, finderButton, importButton, exportButton, aboutScroll] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        names = library?.availableCatalogues() ?? []
        if let e = expanded, !names.contains(e) { expanded = nil; picking = false; openness = [:] }
        loadContents()
        refresh()
    }

    private func refresh() { needsLayout = true; needsDisplay = true; onResize?() }

    // MARK: A catalogue's own colour, kept with the settings by its name; its notes, kept in its file.

    private static var colours: [String: String] {
        get { preferences.dictionary(forKey: coloursKey) as? [String: String] ?? [:] }
        set { preferences.set(newValue, forKey: coloursKey) }
    }
    private func colour(of name: String) -> NSColor? { Self.colours[name].map { Design.hex($0) } }
    private func index(of name: String) -> URL { Catalogues.standard.store(for: name).url }

    private func loadAbout() {
        guard let e = expanded else { return }
        about.string = CatalogueFiles.about(index: index(of: e))
    }
    private func saveAbout() {
        guard let e = expanded, FileManager.default.fileExists(atPath: index(of: e).path) else { return }
        try? CatalogueFiles.setAbout(about.string, index: index(of: e))
    }
    func textDidEndEditing(_ notification: Notification) { saveAbout() }
    func textDidChange(_ notification: Notification) { needsDisplay = true }

    // MARK: What a catalogue holds

    /// The library of a catalogue: the open one's as it stands, any other's read from its file.
    private func libraryFor(_ name: String) -> Library? {
        if let lib = library, lib.catalogue == name { return lib.library }
        return try? Catalogues.standard.store(for: name).load()
    }

    /// A change to a catalogue: through the controller for the open one, so it is a step in the history; on the file for any other.
    private func edit(_ name: String, _ title: String, _ body: (inout Library) -> Void) throws {
        if let lib = library, lib.catalogue == name { lib.apply(title, body); return }
        let store = Catalogues.standard.store(for: name)
        var l = try store.load()
        body(&l)
        try store.save(l)
    }

    private func loadContents() {
        ticked = []
        guard let e = expanded, let lib = libraryFor(e) else { contents = nil; lines = []; return }
        contents = lib
        lines = Self.lines(of: lib, schema: SchemaTrial.read(in: Catalogues.standard.directory(for: e)))
    }

    /// The catalogue as rail1 lists it: Favourites; each collection with its folders and members, or a word that it is empty; the loose palettes.
    private static func lines(of lib: Library, schema: SchemaTrial.SchemaFile) -> [Line] {
        var out: [Line] = []
        func palette(_ s: Swatch, _ indent: Int) -> Line {
            Line(text: s.name, count: "\(s.entries.count)", item: .palette(s.id), indent: indent, heading: false, hexes: s.entries.map { $0.hex })
        }
        let favourites = lib.orderedFavourites
        if !favourites.isEmpty {
            out.append(Line(text: "Favourites", count: "", item: nil, indent: 0, heading: true))
            out += favourites.map { palette($0, 0) }
        }
        let all = schema.collections, places = schema.places
        func members(of c: SchemaCollection, folder: UUID?) -> [Project] {
            lib.orderedProjects.filter { p in
                SchemaTrial.collection(of: p.id, among: all, places: places).id == c.id && SchemaTrial.folder(of: p.id, among: all, places: places) == folder
            }
        }
        func member(_ p: Project, _ indent: Int) -> Line {
            let own = lib.palettes(in: p.id)
            var seen = Set<String>(), hexes: [String] = []
            for h in own.flatMap({ $0.entries.map { $0.hex } }) where !seen.contains(h) { seen.insert(h); hexes.append(h) }
            return Line(text: p.name, count: "\(own.count)", item: .project(p.id), indent: indent, heading: false, hexes: hexes)
        }
        for c in all {
            out.append(Line(text: c.name, count: "", item: nil, indent: 0, heading: true))
            var any = false
            if c.folderName != nil {
                for f in c.folders {
                    let inside = members(of: c, folder: f.id)
                    out.append(Line(text: f.name, count: "\(inside.count)", item: nil, indent: 0, heading: false))
                    out += inside.map { member($0, 1) }
                    any = true
                }
            }
            let loose = members(of: c, folder: nil)
            out += loose.map { member($0, 0) }
            if !any && loose.isEmpty {
                // The member's own word from the schema, "Project" or "Client": "No clients", and Add First Client at the right.
                let what = c.stack.name.isEmpty ? "Member" : c.stack.name
                out.append(Line(text: "No \(SchemaTrial.plural(what).lowercased())", count: "", item: nil, indent: 0, heading: false, warning: true, collection: c.id, member: what))
            }
        }
        out.append(Line(text: "Palettes", count: "", item: nil, indent: 0, heading: true))
        out += lib.palettes(in: nil).map { palette($0, 0) }
        return out
    }

    // MARK: Where things are

    /// The three buttons sit in the first two units, their words on the second line; the rule closes the third.
    private var rowsTop: CGFloat { 3 * Self.u - 1 }
    private var others: [String] { names.filter { $0 != expanded } }
    /// The panel's full height, and its height now, part way through opening or closing.
    private func fullPanelHeight(for name: String) -> CGFloat {
        var h = Self.linesTop + CGFloat(lines.count) * Self.line
        if !ticked.isEmpty { h += Self.bar }
        h += Self.u
        if name == expanded && picking { h += Self.strip + Self.u }
        return h + Self.actions + Self.u
    }
    private func panelHeight(for name: String) -> CGFloat { (fullPanelHeight(for: name) * (openness[name] ?? 0)).rounded() }

    /// The whole view's height at a width: the actions, the rows with their panels, the caption.
    func height(forWidth width: CGFloat) -> CGFloat {
        var y = rowsTop + 1
        for n in names { y += Self.row + panelHeight(for: n) }
        return y + Self.u + 3 * Self.u + Self.u
    }

    /// Opens or shuts rows over a quarter of a second, eased, the way a drawer moves.
    private func animate() {
        guard clock == nil else { return }
        let started = Date()
        let from = openness
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let f = min(1, Date().timeIntervalSince(started) / 0.25)
            let eased = CGFloat(1 - pow(1 - f, 3))
            var done = true
            for n in Set(from.keys).union(self.expanded.map { [$0] } ?? []) {
                let target: CGFloat = n == self.expanded ? 1 : 0
                let start = from[n] ?? 0
                // Snap to the target on the last tick: the easing's arithmetic lands a hair short of 1 otherwise.
                let now = f >= 1 ? target : start + (target - start) * eased
                self.openness[n] = now
                if now != target { done = false }
            }
            if done {
                t.invalidate(); self.clock = nil
                self.openness = self.openness.filter { $0.value > 0 }
            }
            self.refresh()
        }
        RunLoop.main.add(clock!, forMode: .common)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for b in [openButton, newButton, finderButton, importButton, exportButton] {
            let w = b.intrinsicContentSize.width
            b.frame = NSRect(x: x, y: Self.u + Self.lineY - 22, width: w, height: 32)
            x += w + 12
        }
        let open = expanded.map { openness[$0] ?? 0 } ?? 0
        aboutScroll.isHidden = open < 1
        if let e = expanded {
            var y = rowsTop + 1
            for n in names { if n == e { break }; y += Self.row + panelHeight(for: n) }
            aboutScroll.frame = NSRect(x: 0, y: y + Self.row + Self.aboutBox, width: bounds.width, height: Self.notes)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var y = rowsTop
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        y += 1
        rowHits = []; activeHits = []; actionHits = []; lineHits = []; lineActionHits = []; barHits = []; addHits = []
        spectrum = .zero
        let current = library?.catalogue
        for n in names {
            let row = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
            let b = y + Self.lineY
            let active = n == current
            // Set Active: a circle, filled for the open catalogue, and the word; a click here swaps without opening the row.
            let c = NSRect(x: 1, y: b - 9, width: 10, height: 10)
            let circle = NSBezierPath(ovalIn: c.insetBy(dx: 0.5, dy: 0.5)); circle.lineWidth = 1
            if active { Design.ink.setFill(); circle.fill() } else { (hover == n ? Design.ink : Design.quiet).setStroke(); circle.stroke() }
            Design.attributed(active ? "Active" : "Set Active", .caption, colour: active ? Design.ink : Design.quiet).draw(x: 18, baseline: b)
            if !active { activeHits.append((NSRect(x: -6, y: y, width: Self.activeWidth, height: Self.row), n)) }
            // The square: the catalogue's colour, or Card; a static mark now.
            let sq = NSRect(x: Self.activeWidth, y: b - 10, width: Self.square, height: Self.square)
            let own = colour(of: n)
            fill(sq, own ?? Design.card)
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            let nx = Self.activeWidth + Self.step
            Design.attributed(n, active ? .bodyStrong : .body).draw(x: nx, baseline: b, width: bounds.width - nx)
            let open = openness[n] ?? 0
            // A shut row ends on its divider; an open one is a container, and the divider moves down to close it.
            if open == 0 { hairline(x: 0, y: y + Self.row - 1, width: bounds.width, Design.mist) }
            rowHits.append((row, n))
            y += Self.row
            if open > 0 {
                let shown = panelHeight(for: n)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: shown)).addClip()
                drawPanel(n, at: y, live: n == expanded && open == 1, own: own)
                NSGraphicsContext.restoreGraphicsState()
                y += shown
                hairline(x: 0, y: y - 1, width: bounds.width, Design.mist)
            }
        }
        y += Self.u
        Design.attributed("A catalogue is a separate library with its own colours, palettes and projects. Open Catalogue puts one on the list where it is, from its .colcatalogue file, or makes one from a library.json; nothing is copied or changed. Tick what a catalogue holds to relocate it to another catalogue or remove it; Remove on the catalogue moves its whole folder to the Bin.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: y, width: min(bounds.width, 560), height: 3 * Self.u))
    }

    /// A palette's colours as a strip, every colour an equal band, the way rail2 draws one.
    private func strip(_ hexes: [String], in r: NSRect) {
        guard !hexes.isEmpty else {
            Design.rule.setStroke()
            let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            return
        }
        let band = r.width / CGFloat(hexes.count)
        for (i, h) in hexes.enumerated() { fill(NSRect(x: r.minX + CGFloat(i) * band, y: r.minY, width: band + 0.5, height: r.height), Design.hex(h)) }
    }

    /// The open row's panel, on the row's own left edge. `live` is a fully open panel, the one that takes clicks.
    private func drawPanel(_ n: String, at y: CGFloat, live: Bool, own: NSColor?) {
        let w = bounds.width
        Design.attributed("About", .header).draw(x: 0, baseline: y + Self.aboutLabel)
        if about.string.isEmpty {
            Design.attributed("Add catalogue notes\u{2026}", .body, colour: Design.soft).draw(at: NSPoint(x: 0, y: y + Self.aboutBox))
        }
        hairline(x: 0, y: y + Self.aboutBox + Self.notes, width: w, Design.rule)
        Design.attributed("All Colours", .header).draw(x: 0, baseline: y + Self.coloursLabel)
        Design.attributed(contents.map { plural($0.colours.count, "colour") } ?? "", .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.coloursValue)
        Design.attributed("Directory", .header).draw(x: 0, baseline: y + Self.directoryLabel)
        let dir = Catalogues.standard.directory(for: n)
        Design.attributed((dir.path as NSString).abbreviatingWithTildeInPath, .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.directory, width: w)
        // Contents: the catalogue as rail1 lists it, a square before each thing that can be ticked, its colours, its name.
        Design.attributed("Contents", .header).draw(x: 0, baseline: y + Self.contentsLabel)
        hairline(x: 0, y: y + Self.contentsRule, width: w, Design.rule)
        var ly = y + Self.linesTop
        for l in lines {
            let lb = ly + Self.lineY
            if l.heading {
                Design.attributed(l.text, .body).draw(x: 0, baseline: lb)
            } else if l.warning {
                // An empty collection: a small orange triangle and the word.
                let t = NSBezierPath()
                t.move(to: NSPoint(x: Self.inset + 6, y: lb - 10)); t.line(to: NSPoint(x: Self.inset + 12, y: lb)); t.line(to: NSPoint(x: Self.inset, y: lb)); t.close()
                Design.orange.setFill(); t.fill()
                Design.attributed(l.text, .body, colour: Design.quiet).draw(x: Self.inset + Self.step, baseline: lb)
                // The way on, at the right: a plus and "Add First Client".
                let add = Design.attributed("Add First \(l.member)", .caption, colour: Design.quiet)
                let ax = w - add.size().width
                add.draw(x: ax, baseline: lb)
                icon(4, at: NSPoint(x: ax - 14, y: lb - 9), colour: Design.quiet, own: nil, small: true)
                if live, let c = l.collection { addHits.append((NSRect(x: ax - 20, y: ly, width: add.size().width + 24, height: Self.line), c, l.member)) }
            } else {
                let x = Self.inset + CGFloat(l.indent) * Self.step
                if let item = l.item {
                    let on = ticked.contains(item)
                    let sq = NSRect(x: x, y: lb - 10, width: Self.square, height: Self.square)
                    fill(sq, on ? Design.ink : lineHover == item ? Design.mist : Design.card)
                    Design.ink.setStroke()
                    let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
                    strip(l.hexes, in: NSRect(x: x + 20, y: lb - 10, width: Self.stripWidth, height: Self.stripHeight))
                    // The line's own triggers at the right, from the edge leftwards, then its count.
                    var ax = w
                    for (title, glyph) in [("Remove", 2), ("Relocate", 3), ("Duplicate", 1)] {
                        let t = Design.attributed(title, .caption, colour: Design.quiet)
                        ax -= t.size().width
                        t.draw(x: ax, baseline: lb)
                        ax -= 14
                        icon(glyph, at: NSPoint(x: ax, y: lb - 9), colour: Design.quiet, own: nil, small: true)
                        if live { lineActionHits.append((NSRect(x: ax - 4, y: ly, width: t.size().width + 24, height: Self.line), item, glyph)) }
                        ax -= 20
                    }
                    let count = Design.attributed(l.count, .caption, colour: Design.quiet)
                    count.draw(right: ax - 8, baseline: lb)
                    let nameX = x + 20 + Self.stripWidth + 12
                    Design.attributed(l.text, .body, colour: on ? Design.ink : Design.quiet).draw(x: nameX, baseline: lb, width: ax - 8 - count.size().width - 12 - nameX)
                    if live { lineHits.append((NSRect(x: 0, y: ly, width: ax - 8, height: Self.line), item)) }
                } else {
                    Design.attributed(l.text, .body, colour: Design.quiet).draw(x: x, baseline: lb, width: w - x - 48)
                    Design.attributed(l.count, .caption, colour: Design.quiet).draw(right: w, baseline: lb)
                }
            }
            ly += Self.line
        }
        if !ticked.isEmpty {
            // The bar for what is ticked: the count at the left, Relocate and Remove at the right.
            hairline(x: 0, y: ly, width: w, Design.mist)
            let bb = ly + Self.lineY
            Design.attributed("\(ticked.count) Selected", .body, colour: Design.quiet).draw(x: Self.inset, baseline: bb)
            var ax = w
            for (title, glyph) in [("Remove", 2), ("Relocate", 3)] {
                let t = Design.attributed(title, .body, colour: Design.quiet)
                ax -= t.size().width
                t.draw(x: ax, baseline: bb)
                ax -= 16
                icon(glyph, at: NSPoint(x: ax, y: bb - 10), colour: Design.quiet, own: nil)
                if live { barHits.append((NSRect(x: ax - 4, y: ly, width: t.size().width + 28, height: Self.bar), glyph)) }
                ax -= 24
            }
            ly += Self.bar
        }
        var ay = ly + Self.u
        if n == expanded && picking {
            // The hue strip, the whole way across and above the actions: each click gives the catalogue that colour.
            if live { spectrum = NSRect(x: 0, y: ay, width: w, height: Self.strip) }
            for px in stride(from: 0, to: w, by: 1) {
                NSColor(hue: px / w, saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
                NSRect(x: px, y: ay, width: 1.5, height: Self.strip).fill()
            }
            ay += Self.strip + Self.u
        }
        // The actions from the right edge leftwards; the live one underlined, never bold, so nothing moves.
        let ab = ay + Self.lineY
        var ax = w
        for (title, glyph) in [("Remove", 2), ("Duplicate", 1), ("Assign Colour", 0)] {
            let on = glyph == 0 && picking
            let t = Design.attributed(title, .body, colour: on ? Design.ink : Design.quiet)
            ax -= t.size().width
            t.draw(x: ax, baseline: ab)
            if on { hairline(x: ax, y: ab + 4, width: t.size().width, Design.ink) }
            ax -= 16
            icon(glyph, at: NSPoint(x: ax, y: ab - 10), colour: on ? Design.ink : Design.quiet, own: own)
            if live { actionHits.append((NSRect(x: ax - 4, y: ay, width: t.size().width + 28, height: Self.actions), glyph)) }
            ax -= 24
        }
    }

    /// The small marks: a square for a colour, two squares for a copy, a cross for the end, an arrow for a move. `small` is the 10-point size beside a caption.
    private func icon(_ which: Int, at p: NSPoint, colour: NSColor, own: NSColor?, small: Bool = false) {
        colour.setStroke()
        let s: CGFloat = small ? 9 : 11
        switch which {
        case 0:
            let r = NSRect(x: p.x + 0.5, y: p.y + 0.5, width: s, height: s)
            if let own = own { own.setFill(); r.fill() }
            let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
        case 1:
            for (dx, dy) in [(3, 0), (0, 3)] {
                let r = NSRect(x: p.x + CGFloat(dx) + 0.5, y: p.y + CGFloat(dy) + 0.5, width: s - 3, height: s - 3)
                Design.card.setFill(); r.fill()
                let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
            }
        case 4:
            let m = (s + 1) / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x, y: p.y + m)); path.line(to: NSPoint(x: p.x + s, y: p.y + m))
            path.move(to: NSPoint(x: p.x + m, y: p.y)); path.line(to: NSPoint(x: p.x + m, y: p.y + s))
            path.lineWidth = 1.2; path.stroke()
        case 3:
            let m = (s + 1) / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x, y: p.y + m)); path.line(to: NSPoint(x: p.x + s, y: p.y + m))
            path.move(to: NSPoint(x: p.x + s - 4, y: p.y + m - 4)); path.line(to: NSPoint(x: p.x + s, y: p.y + m)); path.line(to: NSPoint(x: p.x + s - 4, y: p.y + m + 4))
            path.lineWidth = 1.2; path.stroke()
        default:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x + 1, y: p.y + 1)); path.line(to: NSPoint(x: p.x + s, y: p.y + s))
            path.move(to: NSPoint(x: p.x + s, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 1, y: p.y + s))
            path.lineWidth = 1.2; path.stroke()
        }
    }

    // MARK: The pointer

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = rowHits.first { $0.0.contains(p) }?.1
        let overLine = lineHits.first { $0.0.contains(p) }?.1
        if over != hover || overLine != lineHover { hover = over; lineHover = overLine; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; lineHover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spectrum.contains(p), let e = expanded {
            // The strip stays open: each click is the catalogue's colour until the strip is put away.
            let c = NSColor(hue: max(0, min(1, p.x / spectrum.width)), saturation: 0.85, brightness: 0.95, alpha: 1)
            var all = Self.colours
            all[e] = hexOf(c) ?? "#000000"
            Self.colours = all
            needsDisplay = true
            return
        }
        if let a = actionHits.first(where: { $0.0.contains(p) }) {
            switch a.1 {
            case 0: picking.toggle()
            case 1: duplicateExpanded()
            default: askToRemove()
            }
            refresh()
            return
        }
        if let b = barHits.first(where: { $0.0.contains(p) }) {
            if b.1 == 3 { relocateMenu(for: ticked, below: b.0) } else { askToRemove(ticked) }
            return
        }
        if let a = addHits.first(where: { $0.0.contains(p) }) { addFirst(in: a.1, called: a.2); return }
        if let la = lineActionHits.first(where: { $0.0.contains(p) }) {
            switch la.2 {
            case 1: duplicate(la.1)
            case 3: relocateMenu(for: [la.1], below: la.0)
            default: askToRemove([la.1])
            }
            return
        }
        if let l = lineHits.first(where: { $0.0.contains(p) }) {
            if ticked.contains(l.1) { ticked.remove(l.1) } else { ticked.insert(l.1) }
            refresh()
            return
        }
        if let s = activeHits.first(where: { $0.0.contains(p) }), let lib = library {
            if s.1 != lib.catalogue { lib.open(catalogue: s.1); onChange?() }
            return
        }
        if let r = rowHits.first(where: { $0.0.contains(p) }) {
            saveAbout()
            expanded = expanded == r.1 ? nil : r.1
            picking = false
            loadAbout()
            loadContents()
            animate()
            refresh()
        }
    }

    // MARK: The list of other catalogues, dropped under Relocate

    private func relocateMenu(for items: Set<Item>, below r: NSRect) {
        guard let win = window, !items.isEmpty else { return }
        let places = others + ["New Catalogue\u{2026}"]
        let panel = SwissDropdown.MenuPanel(items: places, chosen: "", width: 240) { [weak self] i in
            guard let self = self else { return }
            self.closeMenu()
            if i == places.count - 1 {
                do { self.relocate(items, to: try Catalogues.standard.create(Self.freshName())) } catch { self.library?.show(error) }
            } else { self.relocate(items, to: places[i]) }
        }
        let origin = win.convertToScreen(convert(NSRect(x: r.maxX - 240, y: r.maxY, width: 1, height: 1), to: nil)).origin
        panel.place(below: NSPoint(x: origin.x, y: origin.y - 2))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }

    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }

    // MARK: Moving, copying and removing what is ticked

    private static func freshName() -> String {
        let taken = Catalogues.standard.names()
        var n = 1
        while taken.contains("Catalogue \(n)") { n += 1 }
        return "Catalogue \(n)"
    }

    /// What the items come to: the members, with every palette of theirs, and the palettes ticked on their own.
    private func gather(_ items: Set<Item>, in lib: Library) -> (projects: [Project], palettes: [Swatch]) {
        var projects: [Project] = [], palettes: [Swatch] = []
        for case .project(let id) in items {
            if let p = lib.project(id) { projects.append(p); palettes += lib.palettes(in: id) }
        }
        for case .palette(let id) in items where !palettes.contains(where: { $0.id == id }) {
            if let s = lib.swatch(id) { palettes.append(s) }
        }
        return (projects, palettes)
    }

    /// The same thing under a new id and name: through its file form, so every field travels.
    private func copy<T: Codable>(_ v: T, named name: String) -> (T, UUID)? {
        guard let data = try? ColourFiles.encoder().encode(v), var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let id = UUID()
        obj["id"] = id.uuidString
        obj["name"] = name
        guard let out = try? JSONSerialization.data(withJSONObject: obj), let made = try? ColourFiles.decoder().decode(T.self, from: out) else { return nil }
        return (made, id)
    }

    /// Puts members and palettes into a library. One already there, by id or by name, goes in as a copy, suffixed (Copy).
    private func put(projects: [Project], palettes: [Swatch], into dst: inout Library) {
        var remap: [UUID: UUID] = [:]
        for p in projects {
            if dst.project(p.id) == nil && !dst.projects.contains(where: { $0.name == p.name }) { dst.projects.append(p); continue }
            if let (c, id) = copy(p, named: p.name + " (Copy)") { dst.projects.append(c); remap[p.id] = id }
        }
        for s in palettes {
            var s = s
            if let pid = s.projectID {
                if let new = remap[pid] { s.projectID = new } else if dst.project(pid) == nil { s.projectID = nil }
            }
            let taken = dst.swatch(s.id) != nil || dst.swatches.contains { $0.name == s.name && $0.projectID == s.projectID }
            if !taken { dst.swatches.append(s); continue }
            if let (c, _) = copy(s, named: s.name + " (Copy)") { dst.swatches.append(c) }
        }
    }

    /// Copies the members and palettes into the target with the colours, profiles and tags they use, then takes them out of the source.
    private func move(projects: [Project], palettes: [Swatch], from source: String, to target: String, in lib: Library) throws {
        let hexes = Set(palettes.flatMap { $0.entries.map { $0.hex } })
        let colours = lib.colours.filter { hexes.contains($0.hex) }
        let profiles = lib.colourProfiles.filter { pr in projects.contains { $0.profile == pr.id } }
        let ids = Set(projects.map { $0.id })
        let tags = lib.tagInfo.filter { $0.projectID.map { ids.contains($0) } ?? false }
        try edit(target, "Relocate In") { dst in
            self.put(projects: projects, palettes: palettes, into: &dst)
            for c in colours where !dst.colours.contains(where: { $0.hex == c.hex }) { dst.colours.append(c) }
            for pr in profiles where !dst.colourProfiles.contains(where: { $0.id == pr.id }) { dst.colourProfiles.append(pr) }
            for t in tags where !dst.tagInfo.contains(where: { $0.name == t.name && $0.projectID == t.projectID }) { dst.tagInfo.append(t) }
        }
        try edit(source, "Relocate Out") { src in
            for s in palettes { src.deleteSwatch(s.id) }
            for p in projects { src.deleteProject(p.id) }
        }
    }

    private func relocate(_ items: Set<Item>, to target: String) {
        guard let e = expanded, let lib = contents, !items.isEmpty, target != e else { return }
        let picked = gather(items, in: lib)
        do { try move(projects: picked.projects, palettes: picked.palettes, from: e, to: target, in: lib) } catch { library?.show(error) }
        names = library?.availableCatalogues() ?? names
        loadContents(); refresh(); onChange?()
    }

    /// The collection's first member, named for what the schema calls one, placed in the collection; it is renamed on its Overview.
    private func addFirst(in collection: UUID, called kind: String) {
        guard let e = expanded else { return }
        var made: UUID?
        do { try edit(e, "New \(kind)") { lib in made = lib.createProject(named: "\(kind) 1") } } catch { library?.show(error) }
        if let id = made { SchemaTrial.place(id, in: collection, folder: nil, catalogue: Catalogues.standard.directory(for: e)) }
        loadContents(); refresh(); onChange?()
    }

    /// A copy beside the original, suffixed (Copy); a member's palettes come with it.
    private func duplicate(_ item: Item) {
        guard let e = expanded, let lib = contents else { return }
        let picked = gather([item], in: lib)
        do {
            try edit(e, "Duplicate") { src in
                var remap: [UUID: UUID] = [:]
                for p in picked.projects { if let (c, id) = self.copy(p, named: p.name + " (Copy)") { src.projects.append(c); remap[p.id] = id } }
                for s in picked.palettes {
                    guard let (c, _) = self.copy(s, named: s.name + " (Copy)") else { continue }
                    var made = c
                    if let pid = s.projectID, let new = remap[pid] { made.projectID = new }
                    src.swatches.append(made)
                }
            }
        } catch { library?.show(error) }
        loadContents(); refresh(); onChange?()
    }

    private func askToRemove(_ items: Set<Item>) {
        guard let e = expanded, let lib = contents, !items.isEmpty else { return }
        let picked = gather(items, in: lib)
        // The title is the act and its object; the note names what, then what it means.
        let title = picked.projects.isEmpty ? (picked.palettes.count == 1 ? "Remove Palette" : "Remove Palettes")
            : items.count == picked.projects.count ? (picked.projects.count == 1 ? "Remove Member" : "Remove Members") : "Remove Items"
        let names = (picked.projects.map { $0.name } + picked.palettes.filter { s in !picked.projects.contains { $0.id == s.projectID } }.map { $0.name })
        let listed = names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
        SwissConfirm.ask(over: window, title: title,
                         note: "You are about to remove \(listed) from \(e). It goes for good, a member's palettes with it; the colours stay in the catalogue. Slide across to go on.",
                         commit: "Remove") { [weak self] in
            guard let self = self else { return }
            do {
                try self.edit(e, "Remove") { src in
                    for s in picked.palettes { src.deleteSwatch(s.id) }
                    for p in picked.projects { src.deleteProject(p.id) }
                }
            } catch { self.library?.show(error) }
            self.loadContents(); self.refresh(); self.onChange?()
        }
    }

    // MARK: The catalogue's own actions

    private func duplicateExpanded() {
        guard let e = expanded, let lib = library else { return }
        saveAbout()
        do {
            let copy = try Catalogues.standard.store(for: e).load()
            let name = try Catalogues.standard.create(e + " (Copy)", holding: copy)
            try? CatalogueFiles.setAbout(about.string, index: index(of: name))
            if let c = Self.colours[e] { var all = Self.colours; all[name] = c; Self.colours = all }
        } catch { lib.show(error) }
        reload(); onChange?()
    }

    private func askToRemove() {
        guard let e = expanded else { return }
        if names.count == 1 {
            SwissConfirm.tell(over: window, title: "The Only Catalogue",
                              note: "Colorgain keeps one catalogue open, and this is the only one. Make another with New Catalogue first; then this one can go.")
            return
        }
        let lib = libraryFor(e)
        let held = lib.map { "\(e) holds \(plural($0.projects.count, "member")), \(plural($0.swatches.count, "palette")) and \(plural($0.colours.count, "colour")). " } ?? ""
        let targets = others
        SwissConfirm.ask(over: window, title: "Remove Catalogue",
                         note: "You are about to remove \(e). " + held + "The catalogue's folder goes to the Bin with everything still in it, and it comes off the list. Choose where its contents go, then slide across.",
                         commit: "Remove",
                         options: ["Bin Everything With The Folder"] + targets.map { "Move Everything To \($0)" }) { [weak self] choice in
            guard let self = self else { return }
            if choice > 0, let lib = lib {
                let all = Set(lib.projects.map { Item.project($0.id) } + lib.palettes(in: nil).map { Item.palette($0.id) })
                let picked = self.gather(all, in: lib)
                do { try self.move(projects: picked.projects, palettes: picked.palettes, from: e, to: targets[choice - 1], in: lib) } catch { self.library?.show(error); return }
            }
            self.removeExpanded()
        }
    }

    /// Moves the catalogue to the Bin and takes it off the list, Main like any other; the open one hands over to another first.
    private func removeExpanded() {
        guard let e = expanded, let lib = library, names.count > 1 else { return }
        if lib.catalogue == e, let other = names.first(where: { $0 != e }) { lib.open(catalogue: other) }
        do { try Catalogues.standard.bin(e) } catch { lib.show(error) }
        var all = Self.colours; all[e] = nil; Self.colours = all
        expanded = nil
        reload(); onChange?()
    }

    @objc private func openCatalogue() {
        guard let lib = library, let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: ColourFiles.catalogue), UTType(filenameExtension: ColourFiles.legacyCatalogue), .json].compactMap { $0 }
        panel.prompt = "Open"
        panel.message = "Choose a catalogue's .colcatalogue file to open it where it is, or a library.json to make a catalogue from it."
        panel.beginSheetModal(for: w) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let name = [ColourFiles.catalogue, ColourFiles.legacyCatalogue].contains(url.pathExtension.lowercased()) ? try Catalogues.standard.adopt(url) : try Catalogues.standard.importFile(url)
                lib.open(catalogue: name)
            } catch { lib.show(error) }
            self?.onChange?()
        }
    }

    @objc private func importPressed() { onImport?() }
    @objc private func exportPressed() { onExport?() }
    @objc private func newCatalogue() {
        guard let lib = library else { return }
        do { lib.open(catalogue: try Catalogues.standard.create(Self.freshName())) } catch { lib.show(error) }
        onChange?()
    }

    @objc private func showInFinder() {
        guard let lib = library else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lib.store.url])
    }
}

// MARK: - The title strip

/// Nothing to see: a full-width band across the top of the window, the height of the title bar, around
/// Apple's three buttons, which keep their own menus. A press on it moves the window, and over it the
/// pointer is the open hand.
final class TitleStrip: NSView {
    static let height: CGFloat = 24
    override var mouseDownCanMoveWindow: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

// MARK: - Master Inner, drawn over the window

/// The grid over everything: the twelve columns as faint bands with their edges, the two margins, the
/// header's baseline, the area header's lines, then the beat under the rule, every unit, with the
/// line text sits on in each. In the grid's orange, light enough to read through. Takes no clicks.
final class GridOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    /// The page's content, left edge and width: its columns are drawn as the page lays them, from its own width.
    var page = NSRect.zero { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        typealias A = Design.App
        let w = bounds.width, h = bounds.height, c = A.gridColour
        let cw = A.columnWidth(in: w)
        func column(_ x: CGFloat, _ width: CGFloat) {
            fill(NSRect(x: x, y: 0, width: width, height: h), c.withAlphaComponent(0.05))
            fill(NSRect(x: x, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
            fill(NSRect(x: x + width - 1, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
        }
        // The window's columns up to the page, then the page's own, then the window's again past it.
        for i in 1...A.columns {
            let x = A.column(i, in: w)
            if page.width > 0, x + cw > page.minX, x < page.maxX { continue }
            column(x, cw)
        }
        if page.width > 0 {
            let own = A.pageColumns(width: page.width, in: w)
            for x in own.x { column(page.minX + x, own.width) }
        }
        // The header's baseline, the area header's heading and label lines and its rule.
        let strong = c.withAlphaComponent(0.6), faint = c.withAlphaComponent(0.25)
        fill(NSRect(x: 0, y: StudioHeader.baseline, width: w, height: 1), strong)
        let top = A.header + 1
        for y in [AreaHeader.headingBaseline, AreaHeader.labelBaseline, AreaHeader.rule] { fill(NSRect(x: 0, y: top + y, width: w, height: 1), strong) }
        // The beat: a unit line and, within each unit, the line text sits on.
        var y = top + AreaHeader.height
        let bottom = h - A.footer
        while y < bottom {
            fill(NSRect(x: 0, y: y, width: w, height: 1), faint)
            fill(NSRect(x: 0, y: y + A.textBaseline, width: w, height: 1), strong)
            y += A.unit
        }
        fill(NSRect(x: 0, y: h - A.footer + StudioFooter.baseline, width: w, height: 1), strong)
    }
}

// MARK: - The footer, 48 high

/// Left: a 10 square of the current colour, its name, its hex. Centre: three text actions. Right: the release line.
final class StudioFooter: NSView {
    var grid: (x: CGFloat, column: CGFloat, centre: CGFloat) = (24, 96, 480) { didSet { needsDisplay = true } }
    private(set) var hex = Brand.masterHex
    private(set) var name = Brand.masterName
    var onAct: ((Int) -> Void)?
    /// A word from the controller, "Picked Hemlock", in the actions' place for four seconds.
    private var flash: String?
    private var flashTimer: Timer?
    func flash(_ text: String) {
        flash = text; needsDisplay = true
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.flash = nil; self?.needsDisplay = true }
    }
    private let actions = ["Copy Hex", "Copy Name", "Copy RGB"]
    /// The action last used; none until one is.
    private var live: Int? = nil
    private var hits: [NSRect] = []
    static let baseline: CGFloat = 30

    init() { super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = Design.card.cgColor }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func set(hex: String, name: String) { self.hex = hex; self.name = name; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let b = Self.baseline
        fill(NSRect(x: grid.x, y: b - 9, width: 10, height: 10), Design.hex(hex))
        let n = Design.attributed(name, .body)
        n.draw(x: grid.x + 18, baseline: b, width: grid.centre - grid.x - 100)
        Design.attributed(hex, .caption, colour: Design.quiet).draw(x: grid.x + 18 + min(n.size().width, grid.centre - grid.x - 100) + 10, baseline: b)
        // The actions as text from the page's left edge, the live one Medium; a flash takes their place while it lasts.
        var x = grid.centre
        hits = []
        if let f = flash { Design.attributed(f, .body).draw(x: x, baseline: b, width: grid.x + 12 * grid.column + 11 * Design.App.gutter - 200 - x) }
        for (i, a) in actions.enumerated() where flash == nil {
            let t = Design.attributed(a, i == live ? .bodyStrong : .body, colour: i == live ? Design.ink : Design.quiet)
            t.draw(x: x, baseline: b)
            hits.append(NSRect(x: x - 8, y: 0, width: t.size().width + 16, height: bounds.height))
            x += t.size().width + 24
        }
        Design.attributed(ContentViewController.releaseLine, .caption, colour: Design.quiet).draw(right: grid.x + 12 * grid.column + 11 * Design.App.gutter, baseline: b)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = hits.firstIndex(where: { $0.contains(p) }) else { return }
        live = i
        needsDisplay = true
        onAct?(i)
    }
}
