import AppKit

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
        if let name = named, let s = library.library.swatches.first(where: { $0.name == name }) { c.frame.go(.palette(s.id)) }
        else { c.frame.go(args.contains("--palettes") ? .palettes : .catalogue) }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        c.window?.makeFirstResponder(c.frame)   // not the search field: nothing blinks until it is wanted
    }
}

// MARK: - Drawing on the baseline

/// Text is placed by its baseline, never its box, so a row of different sizes sits level (the
/// guide's first law). All the window's views are flipped: y grows downwards, as the grid reads.
private extension NSAttributedString {
    var baselineFont: NSFont { attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? Design.Text.body.font() }
    func draw(x: CGFloat, baseline: CGFloat) { draw(at: NSPoint(x: x, y: baseline - baselineFont.ascender)) }
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

    /// What the page shows and the rails point at.
    enum Place: Equatable { case catalogue, project(UUID), palette(UUID), palettes }
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
        header.onSearch = { [weak self] _ in self?.fillPage() }
        header.onAcross = { [weak self] n in self?.page.grid.across = n }
        rail1.onPick = { [weak self] p in self?.go(p) }
        rail2.onPick = { [weak self] id in self?.go(.palette(id)) }
        page.grid.onPick = { [weak self] hex in self?.choose(hex) }
        page.grid.onOpen = { [weak self] id in self?.go(.palette(id)) }
        history.onPick = { [weak self] hex in self?.choose(hex) }
        footer.onAct = { [weak self] i in self?.act(i) }
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: nil)
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

    /// Rebuilds every region from the library. Cheap enough to do whole on any change.
    func reload() {
        let lib = library.library
        // A palette that is gone goes back to the catalogue.
        if case .palette(let id) = place, lib.swatch(id) == nil { place = .catalogue }
        if case .project(let id) = place, lib.project(id) == nil { place = .catalogue }
        fillLibraryRail()
        fillPaletteTable()
        fillPage()
        fillHistory()
        fillFooter()
        header.live = isTiles ? 0 : 1
    }

    private var isTiles: Bool { if case .palettes = place { return false }; if case .project = place { return false }; return true }
    private func palettes(_ list: [Swatch]) -> [Swatch] { list.filter { !$0.isTypography } }

    private func fillLibraryRail() {
        let lib = library.library
        var rows: [LibraryRail.Row] = [.group("Catalogue"), .row("All Colours", lib.colours.count, .catalogue)]
        let favourites = palettes(lib.orderedFavourites)
        if !favourites.isEmpty {
            rows.append(.group("Favourites"))
            rows += favourites.map { .row($0.name, $0.entries.count, .palette($0.id)) }
        }
        let projects = lib.orderedProjects
        if !projects.isEmpty {
            rows.append(.group("Projects"))
            rows += projects.map { .row($0.name, palettes(lib.palettes(in: $0.id)).count, .project($0.id)) }
        }
        let loose = palettes(lib.palettes(in: nil))
        rows.append(.group("Palettes"))
        rows += loose.map { .row($0.name, $0.entries.count, .palette($0.id)) }
        rows.append(.row("All Palettes", palettes(lib.swatches).count, .palettes))
        rail1.set(rows: rows, chosen: place)
    }

    private func fillPaletteTable() {
        let lib = library.library
        let heading: String, list: [Swatch]
        switch place {
        case .catalogue, .palettes: heading = "Palettes"; list = palettes(lib.listedPalettes)
        case .project(let id): heading = lib.project(id)?.name ?? "Project"; list = palettes(lib.palettes(in: id))
        case .palette(let id):
            let p = lib.swatch(id)?.projectID
            heading = p.flatMap { lib.project($0)?.name } ?? "Palettes"
            list = palettes(lib.palettes(in: p))
        }
        let chosen: UUID? = { if case .palette(let id) = place { return id }; return nil }()
        rail2.set(heading: heading, rows: list.map { s in
            PaletteTable.Row(id: s.id, name: s.name, count: s.entries.count, colours: s.entries.prefix(3).map { Design.hex($0.hex) }, chosen: s.id == chosen)
        })
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
        let items: [TileGrid.Item], title: String, meta: (String, String)
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
        case .palettes:
            let list = palettes(lib.listedPalettes)
            items = cards(list)
            title = "All Palettes"; meta = ("\(items.count) palettes", "\(lib.orderedProjects.count) projects")
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
    var live = 0 { didSet { needsDisplay = true } }
    var onTab: ((Int) -> Void)?
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
        // The avatar: a 24 square at the right edge carrying the user's initial.
        let right = col(12) + grid.column
        let box = NSRect(x: right - 24, y: b - 17, width: 24, height: 24)
        fill(box, Design.mist)
        let initial = Design.attributed(String(NSFullUserName().prefix(1)).uppercased(), .bodyStrong)
        initial.draw(x: box.midX - initial.size().width / 2, baseline: b - 1)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = tabRects.firstIndex(where: { $0.contains(p) }), i < 2 { onTab?(i); return }
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
    var heading = "" { didSet { body.heading = heading; body.needsDisplay = true } }

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
    override func layout() {
        super.layout()
        scroll.frame = bounds
        body.inset = inset
        body.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, body.height))
        body.needsDisplay = true
    }

    class RailBody: NSView {
        var inset: CGFloat = 24
        var heading = ""
        override var isFlipped: Bool { true }
        var height: CGFloat { 0 }
        /// The area header every region shares: the Heading with the arrow on its baseline, a row of two
        /// Labels under it, and the Rule beneath, at the same height in every area so the rule reads as
        /// one line across the window broken only by each area's side padding. Returns the y under the rule.
        @discardableResult
        func drawHeader(_ left: String, _ right: String) -> CGFloat {
            AreaHeader.draw(heading: heading, left: left, right: right, in: bounds, inset: inset)
            return AreaHeader.height
        }
    }
}

/// The header of an area, drawn the same in rail1, rail2, the page and the history rail.
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

/// The library rail: groups of rows, the name left and a tabular count right.
final class LibraryRail: StudioRail {
    enum Row { case group(String), row(String, Int, StudioFrame.Place) }
    var onPick: ((StudioFrame.Place) -> Void)?
    private var list: Body { body as! Body }
    init() { super.init(body: Body()); heading = "Library"; list.onPick = { [weak self] p in self?.onPick?(p) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row], chosen: StudioFrame.Place) { list.rows = rows; list.chosen = chosen; needsLayout = true }

    final class Body: RailBody {
        var rows: [Row] = []
        var chosen: StudioFrame.Place = .catalogue
        var onPick: ((StudioFrame.Place) -> Void)?
        static let row: CGFloat = 20, gap: CGFloat = 6, groupAbove: CGFloat = 24, groupBelow: CGFloat = 10
        private var hits: [(NSRect, StudioFrame.Place)] = []

        override var height: CGFloat {
            rows.reduce(AreaHeader.height) { h, r in
                if case .group = r { return h + Self.groupAbove + 11 + Self.groupBelow }
                return h + Self.row + Self.gap
            } + 24
        }

        override func draw(_ dirtyRect: NSRect) {
            var y = drawHeader("Name", "Count")
            hits = []
            let right = bounds.width - inset
            for r in rows {
                switch r {
                case .group(let title):
                    y += Self.groupAbove
                    Design.attributed(title, .label, colour: Design.quiet).draw(x: inset, baseline: y + 9)
                    y += 11 + Self.groupBelow
                case .row(let name, let count, let place):
                    let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                    let on = place == chosen
                    if on { fill(box, Design.mist) }
                    let b = y + 14
                    let countText = Design.attributed(String(count), .caption, colour: Design.quiet)
                    let countW = countText.size().width
                    let nameText = Design.attributed(name, on ? .bodyStrong : .body)
                    nameText.draw(x: inset, baseline: b, width: right - inset - countW - 12 - (on ? 10 : 0))
                    if on { fill(NSRect(x: inset + min(nameText.size().width, right - inset - countW - 22) + 6, y: b - 6, width: 4, height: 4), Design.ink) }
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

/// The context rail: a table of palettes, Quiet column titles on a Rule, rows on Mist hairlines,
/// a strip of three swatches before each name, counts right.
final class PaletteTable: StudioRail {
    struct Row { let id: UUID; let name: String; let count: Int; let colours: [NSColor]; let chosen: Bool }
    var onPick: ((UUID) -> Void)?
    private var table: Body { body as! Body }
    init() { super.init(body: Body()); table.onPick = { [weak self] id in self?.onPick?(id) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(heading: String, rows: [Row]) {
        self.heading = heading; table.rows = rows; needsLayout = true
        // The chosen palette is brought into view, which the eye expects when it was chosen elsewhere.
        if let i = rows.firstIndex(where: { $0.chosen }) {
            layoutSubtreeIfNeeded()
            let y = AreaHeader.height + CGFloat(i) * Body.row
            body.scrollToVisible(NSRect(x: 0, y: y - Body.row, width: 1, height: Body.row * 3))
        }
    }

    final class Body: RailBody {
        var rows: [Row] = []
        var onPick: ((UUID) -> Void)?
        static let row: CGFloat = 36
        private var hits: [(NSRect, UUID)] = []
        override var height: CGFloat { AreaHeader.height + CGFloat(rows.count) * Self.row + 24 }

        override func draw(_ dirtyRect: NSRect) {
            var y = drawHeader("Palette", "Colours")
            let right = bounds.width - inset
            hits = []
            for r in rows {
                let box = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
                if r.chosen { fill(box, Design.mist) }
                let b = y + 22
                // Three 10 squares, 2 apart; a palette short of three leaves the rest Mist.
                for i in 0..<3 { fill(NSRect(x: inset + CGFloat(i) * 12, y: b - 9, width: 10, height: 10), i < r.colours.count ? r.colours[i] : Design.mist) }
                let count = Design.attributed(String(r.count), .caption, colour: Design.quiet)
                Design.attributed(r.name, r.chosen ? .bodyStrong : .body).draw(x: inset + 44, baseline: b, width: right - inset - 44 - count.size().width - 12)
                count.draw(right: right, baseline: b)
                hairline(x: inset, y: y + Self.row - 1, width: right - inset, Design.mist)
                hits.append((box, r.id))
                y += Self.row
            }
            if rows.isEmpty { Design.attributed("No palettes yet", .caption, colour: Design.soft).draw(x: inset, baseline: y + 22) }
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
    init() { super.init(body: Body()); heading = "History"; list.onPick = { [weak self] h in self?.onPick?(h) } }
    required init?(coder: NSCoder) { fatalError() }
    func set(rows: [Row]) { list.rows = rows; needsLayout = true }

    final class Body: RailBody {
        var rows: [Row] = []
        var onPick: ((String) -> Void)?
        static let row: CGFloat = 44
        private var hits: [(NSRect, String)] = []
        override var height: CGFloat { AreaHeader.height + CGFloat(rows.count) * Self.row + 24 }

        override func draw(_ dirtyRect: NSRect) {
            var y = drawHeader("Colour", "When")
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
        grid.onResize = { [weak self] in self?.needsLayout = true }
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
        grid.width = scroll.frame.width
        grid.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, grid.height))
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
