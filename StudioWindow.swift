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
        w.isMovableByWindowBackground = false   // a press on the page is a press on the page, never a drag of the window
        w.backgroundColor = Design.paper
        w.minSize = Design.App.least
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
        else { c.frame.go(args.contains("--settings") ? .settings : args.contains("--schema") ? .schema : args.contains("--projects") ? .projects : args.contains("--palettes") ? .palettes : .catalogue) }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        library.window = c.window   // errors and prompts come up on this window
        // The backslash key turns Master Inner on and off, whenever no words are being typed.
        if gridKey == nil {
            gridKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c] e in
                guard e.characters == "\\", !(c?.window?.firstResponder is NSText) else { return e }
                c?.frame.toggleGrid()
                return nil
            }
        }
        // The controller's questions come up on the window's own panels, not the old window's.
        library.onPrompt = { [weak c] p in
            SwissConfirm.name(over: c?.window, title: p.title, note: p.message, placeholder: p.placeholder, confirm: p.confirm, check: p.check) { p.done($0) }
        }
        library.onAsk = { [weak c] title, message, choices in
            SwissConfirm.choose(over: c?.window, title: title, note: message, choices: choices.map { $0.title }) { i in if choices.indices.contains(i) { choices[i].run() } }
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
    enum Place: Equatable { case catalogue, collection(UUID), folder(UUID, UUID), project(UUID), palette(UUID), palettes, projects, settings, schema }
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

    init(library: LibraryController) {
        self.library = library
        super.init(frame: NSRect(origin: .zero, size: A.size))
        wantsLayer = true
        layer?.backgroundColor = Design.paper.cgColor
        for v in [header, rail1, rail2, page, history, footer, strip, overlay] { addSubview(v) }
        header.onTab = { [weak self] i in self?.go(i == 0 ? .catalogue : i == 3 ? .projects : .palettes) }
        header.onSettings = { [weak self] in self?.go(.settings) }
        header.onSearch = { [weak self] _ in self?.fillPage() }
        page.onAcross = { [weak self] n in self?.page.grid.across = n }
        rail1.onPick = { [weak self] p in self?.go(p) }
        // A palette dropped on a member moves into its Palettes, and rail2 turns to that member to show it there.
        rail1.onDrop = { [weak self] palette, member in
            guard let self = self else { return }
            self.library.apply("Move Palette") { $0.move(palette, to: member, index: 0) }
            self.go(.project(member))
        }
        rail2.onPick = { [weak self] p in self?.go(p) }
        page.grid.onPick = { [weak self] hex in self?.choose(hex) }
        page.grid.onOpen = { [weak self] id in
            guard let self = self else { return }
            self.go(self.library.library.project(id) != nil ? .project(id) : .palette(id))
        }
        page.settings.library = library
        page.settings.onChange = { [weak self] in self?.reload() }
        page.schema.library = library
        page.schema.onChange = { [weak self] in self?.reload() }
        page.onNew = { [weak self] in self?.newMember() }
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
        footer.grid = (A.column(1, in: w), A.columnWidth(in: w), A.column(5, in: w))
        // Every area's words sit exactly on its columns: the left edge on the first, the right edge at the end of the last.
        func edges(_ v: NSView, _ from: Int, _ to: Int) -> (CGFloat, CGFloat) {
            (A.column(from, in: w) - v.frame.minX, v.frame.maxX - (A.column(to, in: w) + A.columnWidth(in: w)))
        }
        (rail1.inset, rail1.insetRight) = edges(rail1, 1, 2)
        (rail2.inset, rail2.insetRight) = edges(rail2, 3, 4)
        (page.inset, page.insetRight) = edges(page, 5, 10)
        (history.inset, history.insetRight) = edges(history, 11, 12)
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
        header.live = { switch place { case .catalogue, .palette: return 0; case .settings, .schema: return nil; case .projects: return 3; default: return 1 } }()
    }

    private func palettes(_ list: [Swatch]) -> [Swatch] { list.filter { !$0.isTypography } }

    /// A member made where the page stands: in the collection or folder in view, else the first collection; named on the window's own panel.
    private func newMember() {
        let all = SchemaTrial.collections
        var c = all[0], folder: UUID? = nil
        switch place {
        case .collection(let id): c = all.first { $0.id == id } ?? c
        case .folder(let id, let f): c = all.first { $0.id == id } ?? c; folder = f
        default: break
        }
        library.startProject(moving: nil, called: SchemaTrial.memberName(of: c), in: c) { [weak self] id in
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
        var rows: [LibraryRail.Row] = [.group("Catalogue"), .row("All Colours", lib.colours.count, .catalogue, 0)]
        func two(_ s: Swatch) -> LibraryRail.Row { .palette(s.name, s.entries.count, .palette(s.id), s.entries.map { Design.hex($0.hex) }) }
        let favourites = palettes(lib.orderedFavourites)
        if !favourites.isEmpty {
            rows.append(.group("Favourites"))
            rows += favourites.map(two)
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
        rows += loose.map(two)
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
        case .settings, .schema:
            heading = "Settings"; labels = ("Section", "")
            rows = [.item("Catalogues", nil, 0, .settings, place == .settings), .item("Schema", nil, 0, .schema, place == .schema)]
        case .projects:
            heading = "Members"; labels = ("Collection", "Palettes")
            for c in SchemaTrial.collections {
                rows.append(.group(c.name, 0))
                if c.folderName != nil {
                    for f in c.folders { rows.append(.group(f.name, 1)); rows += memberRows(members(of: c, folder: .some(f.id))) }
                }
                rows += memberRows(members(of: c, folder: .some(nil)))
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
                func row(_ s: Swatch) -> PaletteTable.Row { .palette(s.id, s.name, s.entries.count, s.entries.map { Design.hex($0.hex) }, place == .palette(s.id), 0) }
                // This week's arrivals first, parted from the rest by a word on a hairline, when there are both.
                let week = Date().addingTimeInterval(-7 * 24 * 3600)
                let fresh = colours.filter { ($0.placedAt ?? $0.createdAt) >= week }, older = colours.filter { ($0.placedAt ?? $0.createdAt) < week }
                if !fresh.isEmpty && !older.isEmpty {
                    rows.append(.divider("Just Added")); rows += fresh.map(row)
                    rows.append(.divider("Earlier")); rows += older.map(row)
                } else { rows += colours.map(row) }
                if colours.isEmpty { rows.append(.item("None found", nil, 0, nil, false)) }
            case .typography?:
                rows.append(.group(group.name.isEmpty ? "Typography" : group.name, 0))
                let type = held.filter { $0.isTypography }
                rows += type.map { .item($0.name, "\($0.styles?.count ?? 0)", 0, nil, false) }
                if type.isEmpty { rows.append(.item("None found", nil, 0, nil, false)) }
            case .tags?:
                rows.append(.group(group.name.isEmpty ? "Tags" : group.name, 0))
                rows += own.map { .item($0, nil, 0, nil, false) }
                if own.isEmpty { rows.append(.item("None found", nil, 0, nil, false)) }
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
        page.show(.tiles)
        // A new member can be made wherever members are listed: the Members view, a collection, a folder.
        func newWord(_ c: SchemaCollection) -> String { "New " + SchemaTrial.memberName(of: c) }
        func memberCards(_ list: [Project]) -> [TileGrid.Item] {
            list.compactMap { p in
                let own = palettes(lib.palettes(in: p.id))
                var seen = Set<String>(), hexes: [String] = []
                for h in own.flatMap({ $0.entries.map { $0.hex } }) where !seen.contains(h) { seen.insert(h); hexes.append(h) }
                return keep(p.name, nil) ? TileGrid.Item(title: p.name, caption: plural(own.count, "palette"), colours: hexes.prefix(8).map { Design.hex($0) }, hex: nil, id: p.id) : nil
            }
        }
        switch place {
        case .projects:
            let all = SchemaTrial.collections
            items = memberCards(lib.orderedProjects)
            title = "Members"; meta = (plural(items.count, "member"), plural(all.count, "collection"))
            page.showNew(newWord(all[0]))
        case .schema:
            let all = SchemaTrial.collections
            title = "Schema"; meta = (plural(all.count, "collection"), plural(lib.projects.count, "member"))
            page.show(.schema)
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
            page.show(.catalogues)
        }
        switch place {
        case .collection(let id): if let c = SchemaTrial.collections.first(where: { $0.id == id }) { page.showNew(newWord(c)) }
        case .folder(let id, _): if let c = SchemaTrial.collections.first(where: { $0.id == id }) { page.showNew(newWord(c)) }
        default: break
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
final class StudioHeader: NSView, Overlay {
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    var grid: (x: CGFloat, column: CGFloat) = (24, 96) { didSet { needsLayout = true; needsDisplay = true } }
    var live: Int? = 0 { didSet { needsDisplay = true } }
    private var settingsRect = NSRect.zero
    var onTab: ((Int) -> Void)?
    /// The three window marks at the top of column 1, where macOS would put its buttons: close, minimise, and arrange, which drops its menu.
    private var markRects: [NSRect] = []
    private var markHover: Int?
    private var dropped: SwissDropdown.MenuPanel?
    var onSettings: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onAcross: ((Int) -> Void)?
    var search: String { field.stringValue }
    private let tabs = ["Library", "Palettes", "Lab", "Projects"]
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
        // The wordmark: bold lowercase, until there is a logo.
        NSAttributedString(string: Brand.wordmark, attributes: [.font: Design.font(18, .bold), .foregroundColor: Design.ink, .kern: -0.4]).draw(x: col(1), baseline: b)
        // The tabs from column 3, 24 apart; the live one Medium in ink, the rest quiet. Lab and Projects wait for their redesign.
        var x = col(3)
        tabRects = []
        for (i, t) in tabs.enumerated() {
            let a = Design.attributed(t, i == live ? .bodyStrong : .body, colour: i == live ? Design.ink : i == 2 ? Design.soft : Design.quiet)
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
        let sx = right - 24 - 2 * 36 - 24 - settings.size().width
        settings.draw(x: sx, baseline: b)
        settingsRect = NSRect(x: sx - 8, y: 0, width: settings.size().width + 16, height: bounds.height)
        // The three window marks at the right end, each a clean 24 glyph hung from the baseline, no box: the arrow that
        // arranges, the dash that minimises, the cross that closes. Quiet until the pointer is on one.
        markRects = []
        for i in 0..<3 {
            let r = NSRect(x: right - 24 - CGFloat(2 - i) * 36, y: b - 24, width: 24, height: 24)
            (markHover == i ? Design.ink : Design.quiet).setStroke()
            let p = NSBezierPath(); p.lineWidth = 1.3; p.lineCapStyle = .butt
            let g = r.insetBy(dx: 5, dy: 5)
            switch i {
            case 2: p.move(to: NSPoint(x: g.minX, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.maxY)); p.move(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.minX, y: g.maxY))
            case 1: p.move(to: NSPoint(x: g.minX, y: g.midY)); p.line(to: NSPoint(x: g.maxX, y: g.midY))
            default: p.move(to: NSPoint(x: g.minX, y: g.maxY)); p.line(to: NSPoint(x: g.maxX, y: g.minY)); p.move(to: NSPoint(x: g.minX + 4, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.maxY - 4))
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
        let origin = win.convertToScreen(convert(NSRect(x: markRects[0].maxX - 220, y: markRects[0].maxY, width: 1, height: 1), to: nil)).origin
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
            case 2: window?.performClose(nil)
            case 1: window?.miniaturize(nil)
            default: arrange()
            }
            return
        }
        if let i = tabRects.firstIndex(where: { $0.contains(p) }), i != 2 { onTab?(i); return }
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
    var insetRight: CGFloat = 24 { didSet { needsLayout = true } }
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
        AreaHeader.draw(heading: heading, left: labels.0, right: labels.1, in: bounds, inset: inset, insetRight: insetRight)
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
    static let height: CGFloat = rule + 1
    static func draw(heading: String, left: String, right: String, in bounds: NSRect, inset: CGFloat, insetRight: CGFloat? = nil) {
        let r = bounds.width - (insetRight ?? inset)
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
    /// A group label; a row with its count; a palette on two lines, its name over its colours with the count on the second line.
    enum Row { case group(String), row(String, Int, StudioFrame.Place, Int), palette(String, Int, StudioFrame.Place, [NSColor]) }
    var onPick: ((StudioFrame.Place) -> Void)?
    /// A palette dropped on a member: the palette, then the member it lands in.
    var onDrop: ((UUID, UUID) -> Void)?
    private var list: Body { body as! Body }
    init() {
        super.init(body: Body()); heading = "Library"; labels = ("Name", "Count")
        list.onPick = { [weak self] p in self?.onPick?(p) }
        list.onDrop = { [weak self] s, m in self?.onDrop?(s, m) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row], chosen: StudioFrame.Place) { list.rows = rows; list.chosen = chosen; needsLayout = true }

    final class Body: RailBody, NSDraggingSource {
        var rows: [Row] = []
        var chosen: StudioFrame.Place = .catalogue
        var onPick: ((StudioFrame.Place) -> Void)?
        var onDrop: ((UUID, UUID) -> Void)?
        static var row: CGFloat { unit }
        static var two: CGFloat { unit * 2 }
        static var groupAbove: CGFloat { unit }
        static let step: CGFloat = 16
        private var hits: [(NSRect, StudioFrame.Place)] = []
        /// The palette under the mouse at mouseDown, so a drag can take it; the member a drag is over.
        private var pressed: (UUID, String, [NSColor])?
        private var target: UUID?

        override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([PaletteDrag.type]) }
        required init?(coder: NSCoder) { fatalError() }

        /// The first group's header sits on the first-order line, the first row under the rule; every later group has a unit of air above it.
        override var height: CGFloat {
            var h: CGFloat = 0
            for (i, r) in rows.enumerated() {
                switch r {
                case .group: h += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row: h += Self.row
                case .palette: h += Self.two
                }
            }
            return h + Self.unit
        }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            hits = []
            let right = bounds.width - insetRight
            for (i, r) in rows.enumerated() {
                switch r {
                case .group(let title):
                    if i > 0 { y += Self.groupAbove }
                    // A first-order header: Title Case, the body weight, on the line every area shares.
                    Design.attributed(title, .body).draw(x: inset, baseline: y + Self.line)
                    y += Self.row
                case .row(let name, let count, let place, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let on = place == chosen
                    if on { fill(box, Design.mist) }
                    // Rows sit one small step in from their group's header, so the groups read as groups.
                    let b = y + Self.line, x = inset + 12 + CGFloat(indent) * Self.step
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let countW = countText.size().width
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body)
                    nameText.draw(x: x, baseline: b, width: right - x - countW - 12 - (on ? 10 : 0))
                    if on { fill(NSRect(x: x + min(nameText.size().width, right - x - countW - 22) + 6, y: b - 6, width: 4, height: 4), Design.ink) }
                    countText.draw(right: right, baseline: b)
                    // A member lit while a palette is dragged over it: a one-point ink edge.
                    if case .project(let id) = place, id == target {
                        Design.ink.setStroke()
                        let e = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                    }
                    hits.append((box, place))
                    y += Self.row
                case .palette(let name, let count, let place, let colours):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.two)
                    let on = place == chosen
                    if on { fill(box, Design.mist) }
                    let x = inset + 12
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body)
                    nameText.draw(x: x, baseline: y + Self.line, width: right - x - (on ? 10 : 0))
                    if on { fill(NSRect(x: x + min(nameText.size().width, right - x - 10) + 6, y: y + Self.line - 6, width: 4, height: 4), Design.ink) }
                    // The second line: the colours as one strip, its bottom on the second line, the same width on every row, the count at the right.
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let strip = NSRect(x: x, y: y + Self.unit + Self.line - 10, width: right - x - 36, height: 10)
                    if colours.isEmpty { fill(strip, Design.mist) }
                    else {
                        let bw = strip.width / CGFloat(colours.count)
                        for (k, c) in colours.enumerated() { fill(NSRect(x: strip.minX + CGFloat(k) * bw, y: strip.minY, width: k == colours.count - 1 ? strip.width - CGFloat(k) * bw : bw + 0.5, height: strip.height), c) }
                    }
                    countText.draw(right: right, baseline: y + Self.unit + Self.line)
                    hits.append((box, place))
                    y += Self.two
                }
            }
        }

        private func palette(at p: NSPoint) -> (UUID, String, [NSColor])? {
            var y: CGFloat = 0
            for (i, r) in rows.enumerated() {
                switch r {
                case .group: y += (i == 0 ? 0 : Self.groupAbove) + Self.row
                case .row: y += Self.row
                case .palette(let name, _, let place, let colours):
                    if case .palette(let id) = place, NSRect(x: 0, y: y, width: bounds.width, height: Self.two).contains(p) { return (id, name, colours) }
                    y += Self.two
                }
            }
            return nil
        }

        override func mouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            pressed = palette(at: p)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (id, name, colours) = pressed else { return }
            pressed = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        override func mouseUp(with event: NSEvent) { pressed = nil }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

        // MARK: A palette dropped on a member

        private func member(at p: NSPoint) -> UUID? {
            for (box, place) in hits where box.contains(p) { if case .project(let id) = place { return id } }
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
        case group(String, Int)
        case palette(UUID, String, Int, [NSColor], Bool, Int)
        case item(String, String?, Int, StudioFrame.Place?, Bool)
        /// A word on a hairline between runs of rows, as "Just Added" parts this week's palettes from the rest.
        case divider(String)
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

    final class Body: RailBody, NSDraggingSource {
        var rows: [Row] = []
        var onPick: ((StudioFrame.Place) -> Void)?
        static var row: CGFloat { unit }
        static var group: CGFloat { unit }
        static var divider: CGFloat { unit }
        static let step: CGFloat = 16, strip: CGFloat = 44
        private var hits: [(NSRect, StudioFrame.Place)] = []
        private var pressed: (UUID, String, [NSColor])?
        static func height(of r: Row) -> CGFloat {
            switch r { case .group: return group; case .divider: return divider; default: return row }
        }
        override var height: CGFloat { rows.reduce(0) { $0 + Self.height(of: $1) } + Self.unit }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - insetRight
            hits = []
            for r in rows {
                switch r {
                case .group(let name, let indent):
                    // A first-order header: Title Case, the body weight, on the shared line.
                    Design.attributed(name, .body).draw(x: inset + CGFloat(indent) * Self.step, baseline: y + Self.line)
                    y += Self.group
                case .palette(let id, let name, let count, let colours, let chosen, let indent):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    if chosen { fill(box, Design.mist) }
                    let b = y + Self.line, x = inset + CGFloat(indent) * Self.step
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
                    let b = y + Self.line, x = inset + CGFloat(indent) * Self.step
                    let detailText = Design.attributed(detail ?? "", .caption, colour: Design.quiet)
                    let dim = place == nil && detail == nil && name == "None found"
                    Design.attributed(name, chosen ? .bodyStrong : .body, colour: dim ? Design.soft : Design.ink).draw(x: x, baseline: b, width: right - x - detailText.size().width - 12)
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
            pressed = palette(at: p)
            if let h = hits.first(where: { $0.0.contains(p) }) { onPick?(h.1) }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (id, name, colours) = pressed else { return }
            pressed = nil
            PaletteDrag.begin(id, name: name, colours: colours, event: event, in: self)
        }
        override func mouseUp(with event: NSEvent) { pressed = nil }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
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
        static var row: CGFloat { unit * 2 }
        private var hits: [(NSRect, String)] = []
        override var height: CGFloat { CGFloat(rows.count) * Self.row + Self.unit }

        override func draw(_ dirtyRect: NSRect) {
            var y: CGFloat = 0
            let right = bounds.width - insetRight
            hits = []
            for r in rows {
                let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                // The swatch hangs between the two lines: its top on the first, its bottom on the second.
                fill(NSRect(x: inset, y: y + Self.line - 12, width: 24, height: Self.unit + 12), Design.hex(r.hex))
                let time = Design.attributed(r.time, .caption, colour: Design.quiet)
                Design.attributed(r.name, .body).draw(x: inset + 36, baseline: y + Self.line, width: right - inset - 36 - time.size().width - 12)
                Design.attributed(r.what, .caption, colour: Design.quiet).draw(x: inset + 36, baseline: y + Self.unit + Self.line)
                time.draw(right: right, baseline: y + Self.line)
                hits.append((box, r.hex))
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
final class StudioPage: NSView {
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
    /// How many tiles sit across: the slider in the page's header, right-aligned before the arrow and centred on it, shown with the tiles.
    private let slider = MiniSlider()
    var onAcross: ((Int) -> Void)?
    enum Section { case tiles, catalogues, schema }
    private var section = Section.tiles
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
        if s == .catalogues { settings.reload() }
        if s == .schema { schema.reload() }
        newButton.isHidden = true
        needsLayout = true
    }
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
        if !newButton.isHidden {
            // The button's words on the first row's line; the tiles two units down.
            newButton.frame = NSRect(x: inset, y: top + Design.App.textBaseline - 22, width: newButton.intrinsicContentSize.width, height: 32)
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
        grid.width = scroll.frame.width
        grid.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, grid.height))
        scroll.verticalScrollElasticity = grid.height > scroll.frame.height ? .allowed : .none
        grid.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // The same header as the rails: the name as the Heading, its two facts as the Labels, the Rule under.
        AreaHeader.draw(heading: title, left: meta.0, right: meta.1, in: bounds, inset: inset, insetRight: insetRight)
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
    /// On the beat: a block of five units, two units of words with the title and the caption on their lines, a unit between rows; across, the page's own gutter.
    static var block: CGFloat { Design.App.unit * 5 }
    static var words: CGFloat { Design.App.unit * 2 }
    static var rowGap: CGFloat { Design.App.unit }
    static let gap: CGFloat = 16
    override var isFlipped: Bool { true }

    private var tile: CGFloat { ((width - CGFloat(across - 1) * Self.gap) / CGFloat(across)).rounded(.down) }
    var height: CGFloat {
        let rows = (items.count + across - 1) / across
        return CGFloat(rows) * (Self.block + Self.words + Self.rowGap)
    }
    private func rect(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i % across) * (tile + Self.gap), y: CGFloat(i / across) * (Self.block + Self.words + Self.rowGap), width: tile, height: Self.block + Self.words)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, it) in items.enumerated() {
            let r = rect(i)
            guard r.intersects(dirtyRect) else { continue }
            // No box: the colour block, the words on the ground beneath it, and nothing drawn around them.
            let block = NSRect(x: r.minX, y: r.minY, width: r.width, height: Self.block)
            if it.colours.isEmpty { fill(block, Design.mist) }
            else {
                // A palette's colours share the block as equal bands, a single colour takes it whole.
                let bw = block.width / CGFloat(it.colours.count)
                for (k, c) in it.colours.enumerated() { fill(NSRect(x: block.minX + CGFloat(k) * bw, y: block.minY, width: k == it.colours.count - 1 ? block.width - CGFloat(k) * bw : bw + 0.5, height: block.height), c) }
            }
            Design.attributed(it.title, .bodyStrong).draw(x: r.minX + 10, baseline: block.maxY + Design.App.textBaseline, width: r.width - 20)
            Design.attributed(it.caption, .caption, colour: Design.quiet).draw(x: r.minX + 10, baseline: block.maxY + Design.App.unit + Design.App.textBaseline, width: r.width - 20)
            if let h = it.hex, h == chosenHex {
                // The chosen tile: the one orange, a 2 ring inside the card's edge.
                Design.orange.setStroke()
                let p = NSBezierPath(rect: r.insetBy(dx: 1, dy: 1)); p.lineWidth = 2; p.stroke()
            }
        }
        if items.isEmpty { Design.attributed("Nothing found", .lead, colour: Design.soft).draw(x: 0, baseline: Design.App.textBaseline) }
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
        for v in [openButton, newButton, finderButton, aboutScroll] { addSubview(v) }
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
        lines = Self.lines(of: lib)
    }

    /// The catalogue as rail1 lists it: Favourites; each collection with its folders and members, or a word that it is empty; the loose palettes.
    private static func lines(of lib: Library) -> [Line] {
        var out: [Line] = []
        func palette(_ s: Swatch, _ indent: Int) -> Line {
            Line(text: s.name, count: "\(s.entries.count)", item: .palette(s.id), indent: indent, heading: false, hexes: s.entries.map { $0.hex })
        }
        let favourites = lib.orderedFavourites
        if !favourites.isEmpty {
            out.append(Line(text: "Favourites", count: "", item: nil, indent: 0, heading: true))
            out += favourites.map { palette($0, 0) }
        }
        let all = SchemaTrial.collections, places = SchemaTrial.places
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
        for b in [openButton, newButton, finderButton] {
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
        Design.attributed("About", .body).draw(x: 0, baseline: y + Self.aboutLabel)
        if about.string.isEmpty {
            Design.attributed("Add catalogue notes\u{2026}", .body, colour: Design.soft).draw(at: NSPoint(x: 0, y: y + Self.aboutBox))
        }
        hairline(x: 0, y: y + Self.aboutBox + Self.notes, width: w, Design.rule)
        Design.attributed("All Colours", .body).draw(x: 0, baseline: y + Self.coloursLabel)
        Design.attributed(contents.map { plural($0.colours.count, "colour") } ?? "", .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.coloursValue)
        Design.attributed("Directory", .body).draw(x: 0, baseline: y + Self.directoryLabel)
        let dir = Catalogues.standard.directory(for: n)
        Design.attributed((dir.path as NSString).abbreviatingWithTildeInPath, .body, colour: Design.quiet).draw(x: 0, baseline: y + Self.directory, width: w)
        // Contents: the catalogue as rail1 lists it, a square before each thing that can be ticked, its colours, its name.
        Design.attributed("Contents", .body).draw(x: 0, baseline: y + Self.contentsLabel)
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
        if let id = made { SchemaTrial.place(id, in: collection, folder: nil) }
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
        let what = [picked.projects.isEmpty ? nil : plural(picked.projects.count, "member"), picked.palettes.isEmpty ? nil : plural(picked.palettes.count, "palette")].compactMap { $0 }.joined(separator: " and ")
        SwissConfirm.ask(over: window, title: items.count == 1 ? "Remove 1 Item" : "Remove \(items.count) Items",
                         note: "\(what.prefix(1).uppercased() + what.dropFirst()) go from \(e) for good, a member's palettes with it; the colours stay in the catalogue. Slide across to go on.",
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
        SwissConfirm.ask(over: window, title: "Remove \(e)",
                         note: held + "The catalogue's folder goes to the Bin with everything still in it, and it comes off the list. Choose where its contents go, then slide across.",
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
    override func draw(_ dirtyRect: NSRect) {
        typealias A = Design.App
        let w = bounds.width, h = bounds.height, c = A.gridColour
        let cw = A.columnWidth(in: w)
        for i in 1...A.columns {
            let x = A.column(i, in: w)
            fill(NSRect(x: x, y: 0, width: cw, height: h), c.withAlphaComponent(0.05))
            fill(NSRect(x: x, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
            fill(NSRect(x: x + cw - 1, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
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
