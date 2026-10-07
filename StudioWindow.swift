import AppKit
import UniformTypeIdentifiers

// ---------- The Studio window: the app itself on Colorgain's own grid ----------
//
// Colorgain's main window as the design guide draws it (c_c_c_design_grid_app.md, c_c_design_elements.md):
// a 64 header, the library rail, the context rail, the page, the history rail and a 48 footer, on
// twelve columns inside 24 margins with 16 gutters. Everything is placed by frame from the grid and
// drawn in the ten text styles; no macOS control is on the window but the search field. It opens
// beside the old window with --studio (tools/open.sh studio) until it replaces it. Begun 2026-10-07
// on Rick's free run: the library and palettes views only, their assets' layout and presentation.

final class StudioWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
        w.isMovableByWindowBackground = true
        w.backgroundColor = Design.paper
        w.minSize = Design.App.least
        w.contentView = frame
        w.center()
        w.setFrameAutosaveName("StudioWindow")
        super.init(window: w)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func show(library: LibraryController) {
        let c = shared ?? StudioWindowController(library: library)
        shared = c
        // --palettes opens on the palettes view, --palette "<name>" on that palette, for looking at a screen straight away.
        let args = CommandLine.arguments
        let named = args.firstIndex(of: "--palette").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        let project = args.firstIndex(of: "--project").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        if let name = named, let s = library.library.swatches.first(where: { $0.name == name }) { c.frame.go(.palette(s.id)) }
        else if let name = project, let p = library.library.projects.first(where: { $0.name == name }) { c.frame.go(.project(p.id)) }
        else { c.frame.go(args.contains("--settings") ? .settings : args.contains("--palettes") ? .palettes : .catalogue) }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        library.window = c.window   // errors and prompts come up on this window
        c.window?.makeFirstResponder(c.frame)   // not the search field: nothing blinks until it is wanted
    }
}

// MARK: - Drawing on the baseline

/// Text is placed by its baseline, never its box, so a row of different sizes sits level (the
/// guide's first law). All the window's views are flipped: y grows downwards, as the grid reads.
private extension NSAttributedString {
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

private func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }
private func hairline(x: CGFloat, y: CGFloat, width: CGFloat, _ c: NSColor = Design.rule) { fill(NSRect(x: x, y: y, width: width, height: 1), c) }

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
    enum Place: Equatable { case catalogue, collection(UUID), folder(UUID, UUID), project(UUID), palette(UUID), palettes, settings }
    private(set) var place: Place = .catalogue
    private(set) var chosenHex: String?

    let header = StudioHeader()
    let rail1 = LibraryRail()
    let rail2 = PaletteTable()
    let page = StudioPage()
    let history = HistoryRail()
    let footer = StudioFooter()

    init(library: LibraryController) {
        self.library = library
        super.init(frame: NSRect(origin: .zero, size: A.size))
        wantsLayer = true
        layer?.backgroundColor = Design.paper.cgColor
        for v in [header, rail1, rail2, page, history, footer] { addSubview(v) }
        header.onTab = { [weak self] i in self?.go(i == 0 ? .catalogue : .palettes) }
        header.onSettings = { [weak self] in self?.go(.settings) }
        header.onSearch = { [weak self] _ in self?.fillPage() }
        header.onAcross = { [weak self] n in self?.page.grid.across = n }
        rail1.onPick = { [weak self] p in self?.go(p) }
        rail2.onPick = { [weak self] p in self?.go(p) }
        page.grid.onPick = { [weak self] hex in self?.choose(hex) }
        page.grid.onOpen = { [weak self] id in self?.go(.palette(id)) }
        page.settings.library = library
        page.settings.onChange = { [weak self] in self?.reload() }
        history.onPick = { [weak self] hex in self?.choose(hex) }
        footer.onAct = { [weak self] i in self?.act(i) }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .schemaDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    @objc private func libraryChanged() { reload() }

    // The regions, from the grid: rails of two columns each side, the page in the six between.
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame = NSRect(x: 0, y: 0, width: w, height: A.header)
        footer.frame = NSRect(x: 0, y: h - A.footer, width: w, height: A.footer)
        let top = A.header + 1, bodyH = h - A.header - A.footer - 2
        rail1.frame = NSRect(x: 0, y: top, width: A.column(3, in: w) - A.gutter / 2, height: bodyH)
        rail2.frame = NSRect(x: rail1.frame.maxX + 1, y: top, width: A.column(5, in: w) - A.gutter / 2 - rail1.frame.maxX - 1, height: bodyH)
        history.frame = NSRect(x: A.column(11, in: w) - A.gutter / 2, y: top, width: w - A.column(11, in: w) + A.gutter / 2, height: bodyH)
        page.frame = NSRect(x: rail2.frame.maxX + 1, y: top, width: history.frame.minX - rail2.frame.maxX - 2, height: bodyH)
        header.grid = (A.column(1, in: w), A.columnWidth(in: w))
        footer.grid = (A.column(1, in: w), A.columnWidth(in: w), page.frame.minX + A.gutter / 2)
        rail1.inset = A.column(1, in: w)
        rail2.inset = A.column(3, in: w) - rail2.frame.minX
        page.inset = A.gutter
        history.inset = A.column(11, in: w) - history.frame.minX
    }

    override func draw(_ dirtyRect: NSRect) {
        // The hairlines that edge the regions: under the header, over the footer, beside each rail.
        let w = bounds.width
        hairline(x: 0, y: A.header, width: w)
        hairline(x: 0, y: bounds.height - A.footer - 1, width: w)
        for x in [rail1.frame.maxX, rail2.frame.maxX, history.frame.minX - 1] { fill(NSRect(x: x, y: A.header + 1, width: 1, height: rail1.frame.height), Design.rule) }
    }

    // MARK: What is shown

    func go(_ p: Place) {
        place = p
        reload()
    }

    private func choose(_ hex: String) {
        chosenHex = hex
        page.grid.chosenHex = hex
        fillFooter()
    }

    /// Rebuilds every region from the library and the schema. Cheap enough to do whole on any change.
    func reload() {
        let lib = library.library
        // A place that is gone goes back to the catalogue.
        switch place {
        case .palette(let id) where lib.swatch(id) == nil: place = .catalogue
        case .project(let id) where lib.project(id) == nil: place = .catalogue
        case .collection(let id) where !SchemaTrial.collections.contains(where: { $0.id == id }): place = .catalogue
        case .folder(let c, let f) where !(SchemaTrial.collections.first { $0.id == c }?.folders.contains { $0.id == f } ?? false): place = .catalogue
        default: break
        }
        fillLibraryRail()
        fillContextRail()
        fillPage()
        fillHistory()
        fillFooter()
        header.live = { switch place { case .catalogue, .palette: return 0; case .settings: return nil; default: return 1 } }()
    }

    private func palettes(_ list: [Swatch]) -> [Swatch] { list.filter { !$0.isTypography } }

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
        var rows: [LibraryRail.Row] = [.group("Catalogue"), .row("All Colours", lib.colours.count, .catalogue, 0)]
        let favourites = palettes(lib.orderedFavourites)
        if !favourites.isEmpty {
            rows.append(.group("Favourites"))
            rows += favourites.map { .row($0.name, $0.entries.count, .palette($0.id), 0) }
        }
        // Level 0: each collection is a heading. Level 1: its folders, where it has them, each holding its
        // members. Then the member itself, the app's project, with its palettes counted.
        for c in SchemaTrial.collections {
            rows.append(.group(c.name))
            if c.folderName != nil {
                for f in c.folders {
                    let inside = members(of: c, folder: .some(f.id))
                    rows.append(.row(f.name, inside.count, .folder(c.id, f.id), 0))
                    rows += inside.map { .row($0.name, palettes(lib.palettes(in: $0.id)).count, .project($0.id), 1) }
                }
            }
            rows += members(of: c, folder: .some(nil)).map { .row($0.name, palettes(lib.palettes(in: $0.id)).count, .project($0.id), 0) }
        }
        let loose = palettes(lib.palettes(in: nil))
        rows.append(.group("Palettes"))
        rows += loose.map { .row($0.name, $0.entries.count, .palette($0.id), 0) }
        rows.append(.row("All Palettes", palettes(lib.swatches).count, .palettes, 0))
        rail1.set(rows: rows, chosen: place)
    }

    /// rail2 follows the place: the palettes of the catalogue or a project's level, or, for a member, its
    /// whole stack as the schema lays it out: Information, Palettes, Typography, Tags and any group of its own.
    private func fillContextRail() {
        let lib = library.library
        func paletteRow(_ s: Swatch, indent: Int = 0) -> PaletteTable.Row {
            .palette(s.id, s.name, s.entries.count, s.entries.map { Design.hex($0.hex) }, place == .palette(s.id), indent)
        }
        func memberRows(_ list: [Project]) -> [PaletteTable.Row] {
            list.map { .item($0.name, "\(palettes(lib.palettes(in: $0.id)).count)", 0, .project($0.id), place == .project($0.id)) }
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
            if c.folderName != nil {
                for f in c.folders {
                    rows.append(.group(f.name, 0))
                    rows += memberRows(members(of: c, folder: .some(f.id)))
                }
            }
            rows += memberRows(members(of: c, folder: .some(nil)))
        case .folder(let cid, let fid):
            guard let c = SchemaTrial.collections.first(where: { $0.id == cid }), let f = c.folders.first(where: { $0.id == fid }) else { return }
            heading = f.name; labels = (SchemaTrial.memberName(of: c), "Palettes")
            rows = memberRows(members(of: c, folder: .some(fid)))
        case .project(let id):
            guard let project = lib.project(id) else { return }
            return fillStack(of: project, in: lib)
        case .settings:
            heading = "Settings"; labels = ("Section", "")
            rows = [.item("Catalogues", nil, 0, .settings, true)]
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
        func label(_ group: SchemaNode, _ indent: Int) {
            rows.append(.group(group.name, indent))
            for child in group.children { label(child, indent + 1) }
        }
        for group in schema.children {
            switch SchemaTrial.role(of: group) {
            case .information?:
                rows.append(.group(group.name.isEmpty ? "Information" : group.name, 0))
                rows.append(.item("Overview", nil, 0, .project(project.id), place == .project(project.id)))
            case .palettes?:
                rows.append(.group(group.name.isEmpty ? "Palettes" : group.name, 0))
                let colours = held.filter { !$0.isTypography }
                rows += colours.map { .palette($0.id, $0.name, $0.entries.count, $0.entries.map { Design.hex($0.hex) }, place == .palette($0.id), 0) }
                if colours.isEmpty { rows.append(.item("None yet", nil, 0, nil, false)) }
            case .typography?:
                rows.append(.group(group.name.isEmpty ? "Typography" : group.name, 0))
                let type = held.filter { $0.isTypography }
                rows += type.map { .item($0.name, "\($0.styles?.count ?? 0)", 0, nil, false) }
                if type.isEmpty { rows.append(.item("None yet", nil, 0, nil, false)) }
            case .tags?:
                rows.append(.group(group.name.isEmpty ? "Tags" : group.name, 0))
                rows += own.map { .item($0, nil, 0, nil, false) }
                if own.isEmpty { rows.append(.item("None yet", nil, 0, nil, false)) }
            case nil:
                label(group, 0)
            }
        }
        let c = SchemaTrial.collection(of: project.id)
        rail2.set(heading: project.name, labels: (SchemaTrial.memberName(of: c), "Items"), rows: rows)
    }

    private func fillPage() {
        let lib = library.library
        let search = header.search.lowercased()
        func keep(_ name: String, _ hex: String?) -> Bool { search.isEmpty || name.lowercased().contains(search) || (hex?.lowercased().contains(search) ?? false) }
        func tiles(_ hexes: [String], in palette: UUID?) -> [TileGrid.Item] {
            hexes.compactMap { hex in
                let name = lib.name(of: hex, in: palette)
                return keep(name, hex) ? TileGrid.Item(title: name, caption: hex, colours: [Design.hex(hex)], hex: hex, id: nil) : nil
            }
        }
        func cards(_ list: [Swatch]) -> [TileGrid.Item] {
            list.compactMap { s in
                keep(s.name, nil) ? TileGrid.Item(title: s.name, caption: "\(s.entries.count) " + (s.entries.count == 1 ? "colour" : "colours"), colours: s.entries.prefix(8).map { Design.hex($0.hex) }, hex: nil, id: s.id) : nil
            }
        }
        func cardsOf(_ projects: [Project]) -> ([TileGrid.Item], Int) {
            let list = projects.flatMap { palettes(lib.palettes(in: $0.id)) }
            return (cards(list), list.reduce(0) { $0 + $1.entries.count })
        }
        var items: [TileGrid.Item] = [], title = "", meta = ("", "")
        page.showSettings(false)
        switch place {
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
            page.showSettings(true)
        }
        page.set(title: title, meta: meta, items: items)
        page.grid.chosenHex = chosenHex
    }

    private func fillHistory() {
        let lib = library.library
        let recent = lib.colours.sorted { $0.pickedAt > $1.pickedAt }.prefix(60)
        history.set(rows: recent.map { HistoryRail.Row(hex: $0.hex, name: lib.name(of: $0.hex, in: nil), what: "Picked", time: when($0.pickedAt)) })
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
final class StudioHeader: NSView {
    var grid: (x: CGFloat, column: CGFloat) = (24, 96) { didSet { needsLayout = true; needsDisplay = true } }
    var live: Int? = 0 { didSet { needsDisplay = true } }
    private var settingsRect = NSRect.zero
    var onTab: ((Int) -> Void)?
    var onSettings: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onAcross: ((Int) -> Void)?
    var search: String { field.stringValue }
    private let tabs = ["Library", "Palettes", "Lab", "Projects"]
    private var tabRects: [NSRect] = []
    private let field = NSTextField(string: "")
    private let slider = MiniSlider()
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
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        addSubview(field)
        slider.onChange = { [weak self] v in self?.onAcross?(4 + Int((v * 4).rounded())) }
        addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let g = Design.App.gutter
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        field.frame = NSRect(x: col(7) - 2, y: Self.baseline - 15, width: span(3) + 4, height: 20)
        slider.frame = NSRect(x: col(11), y: Self.baseline - 12, width: grid.column, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = Design.App.gutter, b = Self.baseline
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        // The wordmark: bold lowercase, until there is a logo.
        NSAttributedString(string: Brand.wordmark, attributes: [.font: Design.font(18, .bold), .foregroundColor: Design.ink, .kern: -0.4]).draw(x: col(1), baseline: b)
        // The tabs from column 3, 24 apart; the live one Medium in ink, the rest quiet. Lab and Projects wait for their redesign.
        var x = col(3)
        tabRects = []
        for (i, t) in tabs.enumerated() {
            let a = Design.attributed(t, i == live ? .bodyStrong : .body, colour: i == live ? Design.ink : i < 2 ? Design.quiet : Design.soft)
            a.draw(x: x, baseline: b)
            let w = a.size().width
            tabRects.append(NSRect(x: x - 8, y: 0, width: w + 16, height: bounds.height))
            if i == live { fill(NSRect(x: x, y: b + 7, width: w, height: 1), Design.ink) }
            x += w + 24
        }
        // Search on a hairline across columns 7 to 9.
        hairline(x: col(7), y: b + 7, width: span(3), field.currentEditor() != nil ? Design.ink : Design.rule)
        // Settings as a quiet word before the slider.
        let right = col(12) + grid.column
        let settings = Design.attributed("Settings", live == nil ? .bodyStrong : .body, colour: live == nil ? Design.ink : Design.quiet)
        let sx = col(11) - 24 - settings.size().width
        settings.draw(x: sx, baseline: b)
        settingsRect = NSRect(x: sx - 8, y: 0, width: settings.size().width + 16, height: bounds.height)
        // The avatar: a 24 square at the right edge carrying the user's initial.
        let box = NSRect(x: right - 24, y: b - 17, width: 24, height: 24)
        fill(box, Design.mist)
        let initial = Design.attributed(String(NSFullUserName().prefix(1)).uppercased(), .bodyStrong)
        initial.draw(x: box.midX - initial.size().width / 2, baseline: b - 1)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = tabRects.firstIndex(where: { $0.contains(p) }), i < 2 { onTab?(i); return }
        if settingsRect.contains(p) { onSettings?(); return }
        super.mouseDown(with: event)
    }
    @objc private func searched() { onSearch?(field.stringValue) }
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
        body.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(scroll.frame.height, body.height))
        // Rows that fit do not scroll at all; only a longer list moves under the header.
        scroll.verticalScrollElasticity = body.height > scroll.frame.height ? .allowed : .none
        body.needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        AreaHeader.draw(heading: heading, left: labels.0, right: labels.1, in: bounds, inset: inset)
    }

    class RailBody: NSView {
        var inset: CGFloat = 24
        override var isFlipped: Bool { true }
        var height: CGFloat { 0 }
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
    static let height: CGFloat = rule + 1
    static func draw(heading: String, left: String, right: String, in bounds: NSRect, inset: CGFloat) {
        let r = bounds.width - inset
        Design.attributed(heading, .heading).draw(x: inset, baseline: headingBaseline, width: r - inset - 24)
        Design.arrow(16).draw(in: NSRect(x: r - 16, y: headingBaseline - 13, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        Design.attributed(left, .label, colour: Design.quiet).draw(x: inset, baseline: labelBaseline)
        Design.attributed(right, .label, colour: Design.quiet).draw(right: r, baseline: labelBaseline)
        hairline(x: inset, y: rule, width: r - inset, Design.rule)
    }
}

/// The library rail: groups of rows, the name left and a tabular count right; a row one step in sits
/// inside the row above it, as a member sits in its folder.
final class LibraryRail: StudioRail {
    enum Row { case group(String), row(String, Int, StudioFrame.Place, Int) }
    var onPick: ((StudioFrame.Place) -> Void)?
    private var list: Body { body as! Body }
    init() { super.init(body: Body()); heading = "Library"; labels = ("Name", "Count"); list.onPick = { [weak self] p in self?.onPick?(p) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row], chosen: StudioFrame.Place) { list.rows = rows; list.chosen = chosen; needsLayout = true }

    final class Body: RailBody {
        var rows: [Row] = []
        var chosen: StudioFrame.Place = .catalogue
        var onPick: ((StudioFrame.Place) -> Void)?
        static let row: CGFloat = 20, gap: CGFloat = 6, groupAbove: CGFloat = 24, groupBelow: CGFloat = 10, step: CGFloat = 16
        private var hits: [(NSRect, StudioFrame.Place)] = []

        override var height: CGFloat {
            rows.reduce(0) { h, r in
                if case .group = r { return h + Self.groupAbove + 11 + Self.groupBelow }
                return h + Self.row + Self.gap
            } + 24
        }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            hits = []
            let right = bounds.width - inset
            for r in rows {
                switch r {
                case .group(let title):
                    y += Self.groupAbove
                    Design.attributed(title, .label, colour: Design.quiet).draw(x: inset, baseline: y + 9)
                    y += 11 + Self.groupBelow
                case .row(let name, let count, let place, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let on = place == chosen
                    if on { fill(box, Design.mist) }
                    let b = y + 14, x = inset + CGFloat(indent) * Self.step
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let countW = countText.size().width
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body)
                    nameText.draw(x: x, baseline: b, width: right - x - countW - 12 - (on ? 10 : 0))
                    if on { fill(NSRect(x: x + min(nameText.size().width, right - x - countW - 22) + 6, y: b - 6, width: 4, height: 4), Design.ink) }
                    countText.draw(right: right, baseline: b)
                    hits.append((box, place))
                    y += Self.row + Self.gap
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
    }
}

/// The context rail: a table. A palette row carries a strip of every colour in it before its name and
/// its count at the right; a group row is a Label, one step in for each level down; an item row is a
/// name with a detail at the right, going somewhere when it has a place.
final class PaletteTable: StudioRail {
    enum Row {
        case group(String, Int)
        case palette(UUID, String, Int, [NSColor], Bool, Int)
        case item(String, String?, Int, StudioFrame.Place?, Bool)
    }
    var onPick: ((StudioFrame.Place) -> Void)?
    private var table: Body { body as! Body }
    init() { super.init(body: Body()); labels = ("Palette", "Colours"); table.onPick = { [weak self] p in self?.onPick?(p) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(heading: String, labels: (String, String), rows: [Row]) {
        self.heading = heading; self.labels = labels; table.rows = rows; needsLayout = true
        // The chosen row is brought into view, which the eye expects when it was chosen elsewhere.
        var y: CGFloat = 0
        for r in rows {
            let h = Body.height(of: r)
            switch r {
            case .palette(_, _, _, _, true, _), .item(_, _, _, _, true):
                layoutSubtreeIfNeeded()
                body.scrollToVisible(NSRect(x: 0, y: max(0, y - h), width: 1, height: h * 3))
                return
            default: y += h
            }
        }
    }

    final class Body: RailBody {
        var rows: [Row] = []
        var onPick: ((StudioFrame.Place) -> Void)?
        static let row: CGFloat = 36, group: CGFloat = 34, step: CGFloat = 16, strip: CGFloat = 44
        private var hits: [(NSRect, StudioFrame.Place)] = []
        static func height(of r: Row) -> CGFloat { if case .group = r { return group }; return row }
        override var height: CGFloat { rows.reduce(0) { $0 + Self.height(of: $1) } + 24 }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - inset
            hits = []
            for r in rows {
                switch r {
                case .group(let name, let indent):
                    Design.attributed(name, .label, colour: Design.quiet).draw(x: inset + CGFloat(indent) * Self.step, baseline: y + 25)
                    y += Self.group
                case .palette(let id, let name, let count, let colours, let chosen, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    if chosen { fill(box, Design.mist) }
                    let b = y + 22, x = inset + CGFloat(indent) * Self.step
                    // The whole palette as a strip, each colour an equal band; an empty one is Mist.
                    let strip = NSRect(x: x, y: b - 9, width: Self.strip, height: 10)
                    if colours.isEmpty { fill(strip, Design.mist) }
                    else {
                        let bw = strip.width / CGFloat(colours.count)
                        for (k, c) in colours.enumerated() { fill(NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: k == colours.count - 1 ? strip.width - CGFloat(k) * bw : bw + 0.5, height: strip.height), c) }
                    }
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    Design.attributed(name, chosen ? .bodyStrong : .body).draw(x: x + Self.strip + 10, baseline: b, width: right - x - Self.strip - 10 - countText.size().width - 12)
                    countText.draw(right: right, baseline: b)
                    hairline(x: inset, y: y + Self.row - 1, width: right - inset, Design.mist)
                    hits.append((box, .palette(id)))
                    y += Self.row
                case .item(let name, let detail, let indent, let place, let chosen):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    if chosen { fill(box, Design.mist) }
                    let b = y + 22, x = inset + CGFloat(indent) * Self.step
                    let detailText = Design.attributed(detail ?? "", .caption, colour: Design.quiet)
                    let dim = place == nil && detail == nil && name == "None yet"
                    Design.attributed(name, chosen ? .bodyStrong : .body, colour: dim ? Design.soft : Design.ink).draw(x: x, baseline: b, width: right - x - detailText.size().width - 12)
                    if detail != nil { detailText.draw(right: right, baseline: b) }
                    hairline(x: inset, y: y + Self.row - 1, width: right - inset, Design.mist)
                    if let p = place { hits.append((box, p)) }
                    y += Self.row
                }
            }
            if rows.isEmpty { Design.attributed("Nothing here yet", .caption, colour: Design.soft).draw(x: inset, baseline: y + 22) }
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
    }
}

/// The history rail: a 22 colour square, the name over what happened, the time at the right.
final class HistoryRail: StudioRail {
    struct Row { let hex: String; let name: String; let what: String; let time: String }
    var onPick: ((String) -> Void)?
    private var list: Body { body as! Body }
    init() { super.init(body: Body()); heading = "History"; labels = ("Colour", "When"); list.onPick = { [weak self] h in self?.onPick?(h) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row]) { list.rows = rows; needsLayout = true }

    final class Body: RailBody {
        var rows: [Row] = []
        var onPick: ((String) -> Void)?
        static let row: CGFloat = 44
        private var hits: [(NSRect, String)] = []
        override var height: CGFloat { CGFloat(rows.count) * Self.row + 24 }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - inset
            hits = []
            for r in rows {
                let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                fill(NSRect(x: inset, y: y + 11, width: 22, height: 22), Design.hex(r.hex))
                let time = Design.attributed(r.time, .caption, colour: Design.quiet)
                Design.attributed(r.name, .body).draw(x: inset + 34, baseline: y + 19, width: right - inset - 34 - time.size().width - 12)
                Design.attributed(r.what, .caption, colour: Design.quiet).draw(x: inset + 34, baseline: y + 34)
                time.draw(right: right, baseline: y + 19)
                hits.append((box, r.hex))
                y += Self.row
            }
            if rows.isEmpty { Design.attributed("Nothing picked yet", .caption, colour: Design.soft).draw(x: inset, baseline: y + 19) }
        }
        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
    }
}

// MARK: - The page

/// The page: 34 clear, then a Split header on its own six columns, a hairline, 22 clear, and the grid of tiles.
final class StudioPage: NSView {
    var inset: CGFloat = 8 { didSet { needsLayout = true } }
    let grid = TileGrid()
    let settings = CatalogueSettings()
    private let scroll = NSScrollView()
    private var title = ""
    private var meta: (String, String) = ("", "")
    /// The area header, then 16 clear before the tiles.
    static var headerHeight: CGFloat { AreaHeader.height + 16 }

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
        settings.isHidden = true
        addSubview(settings)
        grid.onResize = { [weak self] in self?.needsLayout = true }
    }

    /// The Catalogues settings take the page in place of the tiles.
    func showSettings(_ on: Bool) {
        settings.isHidden = !on
        scroll.isHidden = on
        if on { settings.reload() }
        needsLayout = true
    }
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
        let top = Self.headerHeight
        scroll.frame = NSRect(x: inset, y: top, width: bounds.width - 2 * inset, height: bounds.height - top)
        settings.frame = scroll.frame
        grid.width = scroll.frame.width
        grid.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, grid.height))
        scroll.verticalScrollElasticity = grid.height > scroll.frame.height ? .allowed : .none
        grid.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The same header as the rails: the name as the Heading, its two facts as the Labels, the Rule under.
        AreaHeader.draw(heading: title, left: meta.0, right: meta.1, in: bounds, inset: inset)
    }
}

/// The tiles: `across` to a row, 16 apart, each a Card with its colour block 116 high over a name and
/// a caption. A colour tile carries one colour and its hex; a palette card a strip of its colours
/// and its count, and opens the palette.
final class TileGrid: NSView {
    struct Item { let title: String; let caption: String; let colours: [NSColor]; let hex: String?; let id: UUID? }
    var items: [Item] = [] { didSet { onResize?() } }
    var across = 6 { didSet { onResize?() } }
    var width: CGFloat = 600
    var chosenHex: String? { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onResize: (() -> Void)?
    static let block: CGFloat = 116, words: CGFloat = 52, gap: CGFloat = 16
    override var isFlipped: Bool { true }

    private var tile: CGFloat { ((width - CGFloat(across - 1) * Self.gap) / CGFloat(across)).rounded(.down) }
    var height: CGFloat {
        let rows = (items.count + across - 1) / across
        return CGFloat(rows) * (Self.block + Self.words + Self.gap) + 24
    }
    private func rect(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i % across) * (tile + Self.gap), y: CGFloat(i / across) * (Self.block + Self.words + Self.gap), width: tile, height: Self.block + Self.words)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, it) in items.enumerated() {
            let r = rect(i)
            guard r.intersects(dirtyRect) else { continue }
            fill(r, Design.card)
            Design.rule.setStroke()
            let edge = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            let block = NSRect(x: r.minX, y: r.minY, width: r.width, height: Self.block)
            if it.colours.isEmpty { fill(block, Design.mist) }
            else {
                // A palette's colours share the block as equal bands, a single colour takes it whole.
                let bw = block.width / CGFloat(it.colours.count)
                for (k, c) in it.colours.enumerated() { fill(NSRect(x: block.minX + CGFloat(k) * bw, y: block.minY, width: k == it.colours.count - 1 ? block.width - CGFloat(k) * bw : bw + 0.5, height: block.height), c) }
            }
            Design.attributed(it.title, .bodyStrong).draw(x: r.minX + 10, baseline: block.maxY + 21, width: r.width - 20)
            Design.attributed(it.caption, .caption, colour: Design.quiet).draw(x: r.minX + 10, baseline: block.maxY + 39, width: r.width - 20)
            if let h = it.hex, h == chosenHex {
                // The chosen tile: the one orange, a 2 ring inside the card's edge.
                Design.orange.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1)); p.lineWidth = 2; p.stroke()
            }
        }
        if items.isEmpty { Design.attributed("Nothing here yet", .lead, colour: Design.soft).draw(x: 0, baseline: 24) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = items.indices.first(where: { rect($0).contains(p) }) else { return }
        if let h = items[i].hex { onPick?(h) }
        else if let id = items[i].id, event.clickCount == 2 { onOpen?(id) }
        else if let id = items[i].id { onOpen?(id) }
    }
}

// MARK: - Settings: Catalogues

/// The Catalogues settings on the page. The actions along the top, then one row per catalogue: a
/// small square before its name, ink when that catalogue is the open one, or its own colour once it
/// has one; the pointer over a row lights the square, a click on the square opens the catalogue, and a
/// click on the name opens the row like an accordion: its folder on the full width, then Assign Colour,
/// Duplicate and Remove as icon-and-word actions at the right. Assign Colour drops a hue strip across the
/// page to pick from; Remove drops the chevron track that must be slid across before anything goes.
final class CatalogueSettings: NSView {
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    private var names: [String] = []
    private var expanded: String?
    private var hover: String?
    private var picking = false
    private var removing = false
    private var rowHits: [(NSRect, String)] = [], squareHits: [(NSRect, String)] = [], actionHits: [(NSRect, Int)] = []
    private var spectrum = NSRect.zero
    private let openButton = SwissButton("Open Catalogue\u{2026}", .primary)
    private let newButton = SwissButton("New Catalogue", .secondary)
    private let finderButton = SwissButton("Show In Finder", .secondary)
    private let track = ChevronTrack()
    private let cancel = SwissButton("Keep It", .quiet)
    static let row: CGFloat = 36, square: CGFloat = 12, step: CGFloat = 24, panel: CGFloat = 36 + 36, strip: CGFloat = 40
    private static let coloursKey = "catalogue.colours"

    init() {
        super.init(frame: .zero)
        openButton.target = self; openButton.action = #selector(openCatalogue)
        newButton.target = self; newButton.action = #selector(newCatalogue)
        finderButton.target = self; finderButton.action = #selector(showInFinder)
        cancel.target = self; cancel.action = #selector(keepIt)
        track.commit = "Remove"
        track.onComplete = { [weak self] in self?.removeExpanded() }
        track.isHidden = true
        cancel.isHidden = true
        for v in [openButton, newButton, finderButton, track, cancel] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        names = library?.availableCatalogues() ?? []
        if let e = expanded, !names.contains(e) { expanded = nil; picking = false; removing = false }
        needsLayout = true
        needsDisplay = true
    }

    // MARK: A catalogue's own colour, kept with the settings by its name.

    private static var colours: [String: String] {
        get { preferences.dictionary(forKey: coloursKey) as? [String: String] ?? [:] }
        set { preferences.set(newValue, forKey: coloursKey) }
    }
    private func colour(of name: String) -> NSColor? { Self.colours[name].map { Design.hex($0) } }

    // MARK: Where things are

    private var rowsTop: CGFloat { 32 + 32 }
    private func panelHeight(for name: String) -> CGFloat {
        guard name == expanded else { return 0 }
        return Self.panel + (picking ? Self.strip + 16 : 0) + (removing ? ChevronTrack.height + 16 : 0)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for b in [openButton, newButton, finderButton] {
            let w = b.intrinsicContentSize.width
            b.frame = NSRect(x: x, y: 0, width: w, height: 32)
            x += w + 12
        }
        // The track sits inside the open row's panel, under its actions.
        track.isHidden = !removing || expanded == nil
        cancel.isHidden = track.isHidden
        if let e = expanded, removing {
            var y = rowsTop + 1
            for n in names { if n == e { break }; y += Self.row + panelHeight(for: n) }
            let top = y + Self.row + Self.panel + (picking ? Self.strip + 16 : 0)
            let cw = cancel.intrinsicContentSize.width
            track.frame = NSRect(x: Self.step, y: top, width: bounds.width - Self.step - cw - 16, height: ChevronTrack.height)
            cancel.frame = NSRect(x: bounds.width - cw, y: top + (ChevronTrack.height - 32) / 2, width: cw, height: 32)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        var y = rowsTop
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        y += 1
        rowHits = []; squareHits = []; actionHits = []
        let current = library?.catalogue
        for n in names {
            let row = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
            let b = y + 23
            // The square: the catalogue's colour, or ink for the open one, or Card; Mist under the pointer.
            let sq = NSRect(x: 0, y: b - 10, width: Self.square, height: Self.square)
            let own = colour(of: n)
            fill(sq, own ?? (n == current ? Design.ink : hover == n ? Design.mist : Design.card))
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            Design.attributed(n, n == current ? .bodyStrong : .body).draw(x: Self.step, baseline: b, width: bounds.width - Self.step)
            hairline(x: 0, y: y + Self.row - 1, width: bounds.width, Design.mist)
            rowHits.append((row, n)); squareHits.append((NSRect(x: -6, y: y, width: Self.step, height: Self.row), n))
            y += Self.row
            if n == expanded {
                // The panel: the folder on the full width, then the actions at the right.
                let dir = Catalogues.standard.directory(for: n)
                Design.attributed((dir.path as NSString).abbreviatingWithTildeInPath, .caption, colour: Design.quiet).draw(x: Self.step, baseline: y + 23, width: bounds.width - Self.step)
                let ab = y + 36 + 23
                var ax = bounds.width
                // Laid from the right edge leftwards: Remove last, Assign Colour first.
                for (title, glyph) in [("Remove", 2), ("Duplicate", 1), ("Assign Colour", 0)] {
                    let live = (glyph == 0 && picking) || (glyph == 2 && removing)
                    let t = Design.attributed(title, live ? .bodyStrong : .body, colour: live ? Design.ink : Design.quiet)
                    ax -= t.size().width
                    t.draw(x: ax, baseline: ab)
                    ax -= 16
                    icon(glyph, at: NSPoint(x: ax, y: ab - 10), colour: live ? Design.ink : Design.quiet, own: own)
                    actionHits.append((NSRect(x: ax - 4, y: y + 36, width: t.size().width + 28, height: 36), glyph))
                    ax -= 24
                }
                y += Self.panel
                if picking {
                    // The hue strip, the whole way across: click a colour and it is the catalogue's.
                    spectrum = NSRect(x: 0, y: y, width: bounds.width, height: Self.strip)
                    for px in stride(from: 0, to: bounds.width, by: 1) {
                        NSColor(hue: px / bounds.width, saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
                        NSRect(x: px, y: y, width: 1.5, height: Self.strip).fill()
                    }
                    y += Self.strip + 16
                } else { spectrum = .zero }
                if removing { y += ChevronTrack.height + 16 }
                hairline(x: 0, y: y - 1, width: bounds.width, Design.mist)
            }
        }
        y += 24
        Design.attributed("A catalogue is a separate library with its own colours, palettes and projects. Open Catalogue puts one on the list where it is, from its .colcatalogue file, or makes one from a library.json; nothing is copied or changed. Remove moves a catalogue's folder to the Bin.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: y, width: min(bounds.width, 560), height: 60))
    }

    /// The three small marks: a square for a colour, two squares for a copy, a cross for the end.
    private func icon(_ which: Int, at p: NSPoint, colour: NSColor, own: NSColor?) {
        colour.setStroke()
        switch which {
        case 0:
            let r = NSRect(x: p.x + 0.5, y: p.y + 0.5, width: 11, height: 11)
            if let own = own { own.setFill(); r.fill() }
            let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
        case 1:
            for (dx, dy) in [(3, 0), (0, 3)] {
                let r = NSRect(x: p.x + CGFloat(dx) + 0.5, y: p.y + CGFloat(dy) + 0.5, width: 8, height: 8)
                Design.card.setFill(); r.fill()
                let path = NSBezierPath(rect: r); path.lineWidth = 1; path.stroke()
            }
        default:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: p.x + 1, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 11, y: p.y + 11))
            path.move(to: NSPoint(x: p.x + 11, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 1, y: p.y + 11))
            path.lineWidth = 1.2; path.stroke()
        }
    }

    // MARK: The pointer

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = rowHits.first { $0.0.contains(p) }?.1
        if over != hover { hover = over; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spectrum.contains(p), let e = expanded {
            let c = NSColor(hue: max(0, min(1, p.x / spectrum.width)), saturation: 0.85, brightness: 0.95, alpha: 1)
            var all = Self.colours
            all[e] = hexOf(c) ?? "#000000"
            Self.colours = all
            picking = false
            needsLayout = true; needsDisplay = true
            return
        }
        if let a = actionHits.first(where: { $0.0.contains(p) }) {
            switch a.1 {
            case 0: picking.toggle(); removing = false
            case 1: duplicateExpanded(); return
            default: removing.toggle(); picking = false; if removing { track.start() } else { track.stop() }
            }
            needsLayout = true; needsDisplay = true
            return
        }
        if let s = squareHits.first(where: { $0.0.contains(p) }), let lib = library {
            if s.1 != lib.catalogue { lib.open(catalogue: s.1); onChange?() }
            return
        }
        if let r = rowHits.first(where: { $0.0.contains(p) }) {
            expanded = expanded == r.1 ? nil : r.1
            picking = false; removing = false; track.stop()
            needsLayout = true; needsDisplay = true
        }
    }

    // MARK: The actions

    @objc private func keepIt() { removing = false; track.stop(); needsLayout = true; needsDisplay = true }

    private func duplicateExpanded() {
        guard let e = expanded, let lib = library else { return }
        do {
            let copy = try Catalogues.standard.store(for: e).load()
            let name = try Catalogues.standard.create(e + " (Copy)", holding: copy)
            if let c = Self.colours[e] { var all = Self.colours; all[name] = c; Self.colours = all }
        } catch { lib.show(error) }
        reload(); onChange?()
    }

    /// Moves the catalogue's folder to the Bin and takes it off the list; the open one hands over to another first.
    private func removeExpanded() {
        guard let e = expanded, let lib = library else { return }
        removing = false; track.stop()
        let dir = Catalogues.standard.directory(for: e)
        if lib.catalogue == e, let other = names.first(where: { $0 != e }) { lib.open(catalogue: other) }
        Catalogues.standard.unregister(e)
        do { try FileManager.default.trashItem(at: dir, resultingItemURL: nil) } catch { lib.show(error) }
        var all = Self.colours; all[e] = nil; Self.colours = all
        expanded = nil
        reload(); onChange?()
    }

    @objc private func openCatalogue() {
        guard let lib = library, let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: ColourFiles.catalogue), .json].compactMap { $0 }
        panel.prompt = "Open"
        panel.message = "Choose a catalogue's .colcatalogue file to open it where it is, or a library.json to make a catalogue from it."
        panel.beginSheetModal(for: w) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let name = url.pathExtension.lowercased() == ColourFiles.catalogue ? try Catalogues.standard.adopt(url) : try Catalogues.standard.importFile(url)
                lib.open(catalogue: name)
            } catch { lib.show(error) }
            self?.onChange?()
        }
    }

    @objc private func newCatalogue() {
        guard let lib = library else { return }
        let taken = Catalogues.standard.names()
        var n = 1
        while taken.contains("Catalogue \(n)") { n += 1 }
        do { lib.open(catalogue: try Catalogues.standard.create("Catalogue \(n)")) } catch { lib.show(error) }
        onChange?()
    }

    @objc private func showInFinder() {
        guard let lib = library else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lib.store.url])
    }
}

// MARK: - The footer, 48 high

/// Left: a 10 square of the current colour, its name, its hex. Centre: three text actions. Right: the release line.
final class StudioFooter: NSView {
    var grid: (x: CGFloat, column: CGFloat, centre: CGFloat) = (24, 96, 480) { didSet { needsDisplay = true } }
    private(set) var hex = Brand.masterHex
    private(set) var name = Brand.masterName
    var onAct: ((Int) -> Void)?
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
        // The actions as text from the page's left edge, the live one Medium.
        var x = grid.centre
        hits = []
        for (i, a) in actions.enumerated() {
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
