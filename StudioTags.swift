import AppKit

// ---------- Settings ▸ Tags, on the Studio window, and the panel the halo tags with ----------
//
// The one place for every tag, drawn as the Schema page is: two columns at 60 and 40 on Master Inner, first-order
// headers on the first line, their words in a box of three units, second-order headers on a rule. The left is the list:
// the two filters, Scope and Palette, then every tag as a row on the beat with its colour, its name (renamed where it is
// drawn), its scope and how many colours and palettes wear it; the list scrolls under its column titles, and the pane flies
// out under the pointer and stays on the chosen row. The right is the chosen tag: its name, its colour from a row of
// squares, its scope, the palettes and colours wearing it as small square chips, then New Tag and Delete.
//
// A tag is global, or belongs to a member, or to a group on a collection's level 1 (a client, say). A tag made on a
// collection's level 0 or on a palette outside any member is global.

/// Where a tag may be worn.
enum TagScope: Hashable {
    case global, member(UUID), group(UUID)
}

extension Library {
    /// The tag's scope as it stands: its member while that member is there, else its group while that is in the schema, else global.
    func scope(ofTag name: String) -> TagScope {
        if let p = project(ofTag: name) { return .member(p) }
        if let g = group(ofTag: name) { return .group(g) }
        return .global
    }
}

/// The scopes as words and as the house menu offers them.
enum TagScopes {
    /// A level-1 group by its id, with the collection it is in.
    static func folder(_ id: UUID) -> (collection: SchemaCollection, folder: SchemaFolder)? {
        for c in SchemaTrial.collections { if let f = c.folders.first(where: { $0.id == id }) { return (c, f) } }
        return nil
    }
    /// "Global", the member's name, or the group as its level calls it: "Client: Acme".
    static func name(_ s: TagScope, in lib: Library) -> String {
        switch s {
        case .global: return "Global"
        case .member(let p): return lib.project(p)?.name ?? "Global"
        case .group(let g): return folder(g).map { "\($0.collection.folderName ?? "Group"): \($0.folder.name)" } ?? "Global"
        }
    }
    /// The members of a collection in rail1's order.
    private static func members(of c: SchemaCollection, in lib: Library) -> [Project] {
        let all = SchemaTrial.collections, places = SchemaTrial.places
        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == c.id }
    }
    /// The house menu of scopes: Global, then each collection as a heading over its level-1 groups and its members, a member
    /// set in under its group. `within`, when given, keeps only the scopes something in those members may wear: Global, the
    /// members themselves and the groups they sit in. `lead` rows come first, such as All for a filter. Each row's scope is
    /// beside it; a divider or a heading has none.
    static func menu(_ lib: Library, within: Set<UUID>? = nil, lead: [(String, TagScope?)] = []) -> (items: [String], scopes: [TagScope?], all: [Bool]) {
        let M = SwissDropdown.MenuPanel.self
        var items: [String] = [], scopes: [TagScope?] = [], alls: [Bool] = []
        func add(_ s: String, _ scope: TagScope?, all: Bool = false) { items.append(s); scopes.append(scope); alls.append(all) }
        for (t, s) in lead { add(t, s, all: s == nil) }
        add("Global", .global)
        let all = SchemaTrial.collections, places = SchemaTrial.places
        func allowed(_ s: TagScope) -> Bool {
            guard let within = within else { return true }
            switch s {
            case .global: return true
            case .member(let p): return within.contains(p)
            case .group(let g): return within.contains { SchemaTrial.folder(of: $0, among: all, places: places) == g }
            }
        }
        for c in all {
            var rows: [(String, TagScope)] = []
            let inside = members(of: c, in: lib)
            if let word = c.folderName {
                for f in c.folders {
                    if allowed(.group(f.id)) { rows.append(("\(word): \(f.name)", .group(f.id))) }
                    for p in inside where SchemaTrial.folder(of: p.id, among: all, places: places) == f.id && allowed(.member(p.id)) {
                        rows.append(("\u{2003}" + p.name, .member(p.id)))
                    }
                }
                for p in inside where SchemaTrial.folder(of: p.id, among: all, places: places) == nil && allowed(.member(p.id)) { rows.append((p.name, .member(p.id))) }
            } else {
                for p in inside where allowed(.member(p.id)) { rows.append((p.name, .member(p.id))) }
            }
            guard !rows.isEmpty else { continue }
            add(M.divider, nil); add(M.heading(c.name), nil)
            for (t, s) in rows { add(t, s) }
        }
        return (items, scopes, alls)
    }
}

extension LibraryController {
    /// Tags typed on the halo's panel for a palette: the words are its tags now; any that are new take `scope`, the rest keep theirs.
    func setTags(ofPalette id: UUID, _ tags: [String], newScope: TagScope) {
        apply("Tag Palette") { lib in
            Self.make(tags, scope: newScope, in: &lib)
            lib.setTags(ofPalette: id, tags)
        }
        let kept = Set((library.swatch(id)?.tagList ?? []).map { $0.lowercased() })
        sayTagsRefused(tags.filter { !kept.contains($0.lowercased()) })
    }
    /// The same for colours: every one of them takes the words.
    func setTags(ofSwatches hexes: [String], _ tags: [String], newScope: TagScope) {
        apply("Tag Swatches") { lib in
            Self.make(tags, scope: newScope, in: &lib)
            for h in hexes { lib.setTags(ofColour: h, tags) }
        }
        sayTagsRefused(tags.filter { tag in hexes.contains { h in !(library.colours.first { $0.hex == h }?.tags ?? []).contains { $0.lowercased() == tag.lowercased() } } })
    }
    /// The tag's scope changed, its colour kept.
    func setScope(_ s: TagScope, ofTag name: String) {
        let colour = library.info(forTag: name)?.colour
        switch s {
        case .global: setTag(name, colour: colour, project: nil, group: .some(nil))
        case .member(let p): setTag(name, colour: colour, project: p, group: .some(nil))
        case .group(let g): setTag(name, colour: colour, project: nil, group: .some(g))
        }
    }
    /// The tag's colour changed, its scope kept; nil is the standard, no colour of its own.
    func setColour(_ hex: String?, ofTag name: String) {
        setTag(name, colour: hex, project: library.project(ofTag: name))
    }
    /// A tag made where nothing wears it yet, in a scope.
    func makeTag(_ name: String, scope: TagScope) {
        apply("New Tag") { lib in Self.make([name], scope: scope, in: &lib) }
    }
    private static func make(_ tags: [String], scope: TagScope, in lib: inout Library) {
        for tag in tags where !lib.allTags.contains(where: { $0.lowercased() == tag.lowercased() }) {
            switch scope {
            case .global: lib.setTag(tag, colour: nil, project: nil, group: .some(nil))
            case .member(let p): lib.setTag(tag, colour: nil, project: p, group: .some(nil))
            case .group(let g): lib.setTag(tag, colour: nil, project: nil, group: .some(g))
            }
        }
    }
    /// Says which tags were not put on, and why: each belongs somewhere this is not.
    private func sayTagsRefused(_ tags: [String]) {
        guard let first = tags.first else { return }
        let home = TagScopes.name(library.scope(ofTag: first), in: library)
        flash(tags.count == 1 ? "\u{201C}\(first)\u{201D} belongs to \(home), so it was not added here" : "\(tags.count) tags were not added: they belong to other members or groups")
    }
}

/// The panel the halo's Tags opens: the tags as words separated by commas, and the scope a new one takes, from a house dropdown.
enum TagPanel {
    static func palette(_ id: UUID, library: LibraryController, over window: NSWindow?) {
        let lib = library.library
        guard let s = lib.swatch(id) else { Diagnostics.log("tags", "no palette for \(id)"); return }
        Diagnostics.log("tags", "panel for \(s.name)")
        // The scopes this palette can wear: Global, its member and the group its member is in. It starts on its own member.
        let within = Set([s.projectID].compactMap { $0 })
        let start: TagScope = s.projectID.map { .member($0) } ?? .global
        ask(title: "Tags", note: "The tags on \(s.name), separated by commas. A tag that is new takes the scope below; Settings, Tags holds every tag.",
            value: s.tagList.joined(separator: ", "), within: within, start: start, library: library, over: window) { tags, scope in
            library.setTags(ofPalette: id, tags, newScope: scope)
        }
    }
    static func colours(_ hexes: [String], library: LibraryController, over window: NSWindow?) {
        let lib = library.library
        guard let first = hexes.first else { return }
        let now = lib.colours.first { $0.hex == first }?.tags ?? []
        let within = lib.projects(holdingAll: hexes)
        let start: TagScope = within.count == 1 ? .member(within.first!) : .global
        ask(title: "Tags", note: "The tags on \(hexes.count == 1 ? colourName(first) : plural(hexes.count, "colour")), separated by commas. A tag that is new takes the scope below; Settings, Tags holds every tag.",
            value: now.joined(separator: ", "), within: within, start: start, library: library, over: window) { tags, scope in
            library.setTags(ofSwatches: hexes, tags, newScope: scope)
        }
    }
    private static func ask(title: String, note: String, value: String, within: Set<UUID>, start: TagScope, library: LibraryController, over window: NSWindow?, then: @escaping ([String], TagScope) -> Void) {
        let menu = TagScopes.menu(library.library, within: within)
        SwissConfirm.name(over: window, title: title, note: note, placeholder: "Brand, Spring 2027, Approved", value: value,
                          pickLabel: "Scope", items: menu.items, chosen: menu.scopes.firstIndex(of: start) ?? 0, confirm: "Save Tags", allowsEmpty: true,
                          check: { _ in nil }) { typed, i in
            then(split(typed), menu.scopes.indices.contains(i) ? menu.scopes[i] ?? .global : .global)
        }
    }
    static func split(_ typed: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in typed.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !t.isEmpty && !seen.contains(t.lowercased()) { seen.insert(t.lowercased()); out.append(t) }
        return out
    }
}

final class TagsSettings: NSView, NSTextFieldDelegate, PageSection, Overlay {
    /// Rail1's Edit Tags under a member: the page opens filtered to it. Taken by the next reload.
    static var pendingScope: TagScope?

    private let library: LibraryController
    var onResize: (() -> Void)?
    /// The page's edge to its first column: the view starts at the rail's divider so a row's ground can reach it, and the words start here.
    var leading: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private static let helpUnits: CGFloat = 3, step: CGFloat = 16

    /// The colours a tag can be given, chosen to sit apart from the step colours, which mean the wizard's steps and nothing else.
    static let colours = ["#D9452B", "#EE7B30", "#F2C230", "#4E9A4A", "#2E8C8C", "#4A9BD9", "#2F5FD6", "#7650C8", "#D6508A", "#8A6A4A", "#8C8A85"]

    // MARK: State

    private var lib: Library { library.library }
    private var chosen: String?
    /// The filters: a scope, nil for all; a palette, nil for all.
    private var scopeFilter: TagScope?
    private var paletteFilter: UUID?
    private var rows: [String] = []
    /// Every colour as it is drawn, from its master.
    private var shade: [String: NSColor] = [:]

    // MARK: Views

    private let listScroll = NSScrollView()
    private let list = Canvas()
    private let nameField = NSTextField(string: "")
    private let newButton = SwissButton("New Tag", .secondary)
    private let deleteButton = SwissButton("Delete", .secondary)
    private var draft: String?
    private var renaming: String?

    // Hits, each frame: the list's rows and names; the filters, the colour squares and the scope on this view.
    private var rowRects: [NSRect] = []
    private var nameRects: [NSRect] = []
    private var filterHits: [(NSRect, Int)] = []
    private var colourHits: [(NSRect, String?)] = []
    private var scopeHit = NSRect.zero

    // The rollover: what is under the pointer, how far each pane has flown out, driven by the clock.
    private var hover: String?
    private var reveal: [String: CGFloat] = [:]
    private var clock: Timer?
    private var lastTick = Date()

    // The menu open over a filter or the scope.
    private var dropped: SwissDropdown.MenuPanel?
    private var droppedFrom = -1
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = Design.Text.body.font()
        nameField.textColor = Design.ink
        nameField.delegate = self
        nameField.cell?.sendsActionOnEndEditing = false
        nameField.placeholderAttributedString = Design.attributed("Name", .body, colour: Design.soft)
        nameField.target = self; nameField.action = #selector(nameEntered)
        addSubview(nameField)
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.scrollerStyle = .overlay
        listScroll.documentView = list
        addSubview(listScroll)
        list.onDraw = { [weak self] in self?.drawList() }
        list.onDown = { [weak self] p in self?.listDown(at: p) }
        list.onMove = { [weak self] p in
            guard let self = self else { return }
            var over: String?
            if let pt = p, let i = self.rowRects.firstIndex(where: { $0.contains(pt) }), self.rows.indices.contains(i) { over = self.rows[i] }
            if over != self.hover { self.hover = over; self.settle() }
        }
        newButton.target = self; newButton.action = #selector(newTag)
        deleteButton.target = self; deleteButton.action = #selector(deleteTag)
        addSubview(newButton); addSubview(deleteButton)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: Loading

    func reload() {
        if let s = Self.pendingScope { scopeFilter = s; paletteFilter = nil; Self.pendingScope = nil; chosen = nil }
        // A filter on something gone goes back to All.
        if case .member(let p)? = scopeFilter, lib.project(p) == nil { scopeFilter = nil }
        if case .group(let g)? = scopeFilter, TagScopes.folder(g) == nil { scopeFilter = nil }
        if let p = paletteFilter, lib.swatch(p) == nil { paletteFilter = nil }
        shade = lib.displayTable()
        rows = filtered()
        if let c = chosen, !lib.allTags.contains(c) { chosen = nil }
        if chosen == nil || !rows.contains(chosen!) { chosen = rows.first ?? chosen }
        needsLayout = true; needsDisplay = true; list.needsDisplay = true
        onResize?()
        settle()
    }
    private func filtered() -> [String] {
        var tags = lib.allTags
        if let s = scopeFilter { tags = tags.filter { lib.scope(ofTag: $0) == s } }
        if let p = paletteFilter, let s = lib.swatch(p) {
            let on = Set(s.tagList.map { $0.lowercased() })
            let hexes = Set(s.entries.map { $0.hex })
            let worn = Set(lib.colours.filter { hexes.contains($0.hex) }.flatMap { $0.tags ?? [] }.map { $0.lowercased() })
            tags = tags.filter { on.contains($0.lowercased()) || worn.contains($0.lowercased()) }
        }
        return tags
    }

    // MARK: Geometry

    private struct Geometry { var lw: CGFloat = 0, rx: CGFloat = 0, rw: CGFloat = 0 }
    private func geometry() -> Geometry {
        let w = bounds.width - leading, gut = Design.App.areaGutter   // the split is an area gutter
        var g = Geometry()
        g.lw = ((w - gut) * 0.6).rounded(); g.rx = leading + g.lw + gut; g.rw = w - g.lw - gut
        return g
    }
    /// The list's columns, from the left column's edge: the name after the square, the scope, then the two counts flush right.
    private func columns(_ lw: CGFloat) -> (name: CGFloat, scope: CGFloat, colours: CGFloat, palettes: CGFloat) {
        (24, (lw * 0.44).rounded(), (lw * 0.82).rounded(), lw)
    }
    /// Rows under the rule: the filters on 5 and 6, the column titles on 8, the list from 9; on the right the fields from 5, the buttons on 16.
    private static let listTop: CGFloat = 9

    /// The right column needs seventeen units; at least that, so a short window scrolls the page rather than cutting the buttons.
    func height(forWidth width: CGFloat) -> CGFloat { 17 * Self.u }

    override func layout() {
        super.layout()
        let g = geometry(), u = Self.u, line = Self.line
        let top = Self.listTop * u
        listScroll.frame = NSRect(x: 0, y: top, width: leading + g.lw + Design.App.areaGutter / 2, height: max(0, bounds.height - top))
        let listHeight = CGFloat(max(rows.count, 1)) * u + u
        list.frame = NSRect(x: 0, y: 0, width: listScroll.frame.width, height: max(listScroll.frame.height, listHeight))
        listScroll.verticalScrollElasticity = listHeight > listScroll.frame.height ? .allowed : .none
        rowRects = rows.indices.map { NSRect(x: leading, y: CGFloat($0) * u, width: g.lw, height: u) }
        // The name field on row 6: a 13 field's text sits on the line when its frame starts 12 above it.
        nameField.isHidden = chosen == nil
        nameField.frame = NSRect(x: g.rx - 2, y: 6 * u + line - 12, width: g.rw + 2, height: 20)
        if nameField.currentEditor() == nil { nameField.stringValue = chosen ?? "" }
        // The buttons on row 16, their words on its line.
        let by = 16 * u + line - 22
        newButton.frame = NSRect(x: g.rx, y: by, width: newButton.intrinsicContentSize.width, height: SwissButton.height)
        deleteButton.frame = NSRect(x: newButton.frame.maxX + 16, y: by, width: deleteButton.intrinsicContentSize.width, height: SwissButton.height)
        deleteButton.isEnabled = chosen != nil
    }

    // MARK: Drawing: the headers, the filters and the chosen tag here; the list on its own canvas

    private var leftHelp: String {
        "Every tag in the catalogue: its colour, where it may be worn and what wears it. A global tag goes on anything; a member's or a group's only inside it. Double-click a name to rename it everywhere it is worn."
    }
    private func rightHelp(_ name: String?) -> String {
        guard let name = name else { return "Choose a tag in the list, or make one with New Tag." }
        switch lib.scope(ofTag: name) {
        case .global: return "\(name) is global: any palette or colour in the catalogue can wear it. Give it a member or a group to keep it there."
        case .member(let p): return "\(name) belongs to \(lib.project(p)?.name ?? "a member"): only the palettes and colours inside it can wear it, and it is offered nowhere else."
        case .group(let g):
            let f = TagScopes.folder(g)
            return "\(name) belongs to \(f?.folder.name ?? "a group"): every palette and colour in its \(SchemaTrial.plural(f.map { SchemaTrial.memberName(of: $0.collection) } ?? "member").lowercased()) can wear it."
        }
    }

    /// A dropdown drawn on the beat as the Name field is: its label on one row, its value and chevron on the next over a hairline.
    private func dropdown(_ label: String, value: String, x: CGFloat, row: CGFloat, width: CGFloat, open: Bool) -> NSRect {
        let u = Self.u, line = Self.line
        Design.attributed(label, .label, colour: Design.quiet).draw(x: x, baseline: row * u + line)
        let b = (row + 1) * u + line
        Design.attributed(value, .body).draw(x: x, baseline: b, width: width - 24)
        Design.quiet.setStroke()
        let c = NSBezierPath(); c.lineWidth = 1
        let r = x + width
        c.move(to: NSPoint(x: r - 9, y: open ? b - 2 : b - 6)); c.line(to: NSPoint(x: r - 5, y: open ? b - 6 : b - 2)); c.line(to: NSPoint(x: r - 1, y: open ? b - 2 : b - 6))
        c.stroke()
        hairline(x: x, y: (row + 2) * u - 1, width: width, open ? Design.ink : Design.rule)
        return NSRect(x: x, y: (row + 1) * u, width: width, height: u)
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(), u = Self.u, line = Self.line, l = leading, gut = Design.App.gutter
        filterHits = []; colourHits = []; scopeHit = .zero
        // Left: the first-order header and its words, then the list's header on its rule.
        Design.attributed("Tag Library", .header).draw(x: l, baseline: line)
        Design.attributed(leftHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: l, y: u, width: g.lw, height: Self.helpUnits * u))
        Design.attributed("Every Tag", .header).draw(x: l, baseline: 4 * u + line)
        Design.attributed(rows.count == lib.allTags.count ? plural(rows.count, "tag") : "\(rows.count) of \(lib.allTags.count)", .caption, colour: Design.quiet).draw(right: l + g.lw, baseline: 4 * u + line)
        hairline(x: l, y: 5 * u - 1, width: g.lw, Design.rule)
        // The filters, side by side on rows 5 and 6, a gutter between.
        let fw = ((g.lw - gut) / 2).rounded()
        filterHits.append((dropdown("Scope", value: scopeFilter.map { TagScopes.name($0, in: lib) } ?? "All", x: l, row: 5, width: fw, open: droppedFrom == 0), 0))
        filterHits.append((dropdown("Palette", value: paletteFilter.flatMap { lib.swatch($0)?.name } ?? "All", x: l + fw + gut, row: 5, width: g.lw - fw - gut, open: droppedFrom == 1), 1))
        // The list's column titles on row 8, quiet, on a rule.
        let col = columns(g.lw), tb = 8 * u + line
        Design.attributed("Name", .caption, colour: Design.quiet).draw(x: l + col.name, baseline: tb)
        Design.attributed("Scope", .caption, colour: Design.quiet).draw(x: l + col.scope, baseline: tb)
        Design.attributed("Colours", .caption, colour: Design.quiet).draw(right: l + col.colours, baseline: tb)
        Design.attributed("Palettes", .caption, colour: Design.quiet).draw(right: l + col.palettes, baseline: tb)
        hairline(x: l, y: Self.listTop * u - 1, width: g.lw, Design.rule)

        // Right: the chosen tag.
        let rx = g.rx, rw = g.rw
        Design.attributed("Tag", .header).draw(x: rx, baseline: line)
        Design.attributed(rightHelp(chosen), .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: u, width: rw, height: Self.helpUnits * u))
        Design.attributed("Details", .header).draw(x: rx, baseline: 4 * u + line)
        hairline(x: rx, y: 5 * u - 1, width: rw, Design.rule)
        guard let name = chosen else { return }
        let info = lib.info(forTag: name)
        // Name, on rows 5 and 6.
        Design.attributed("Name", .label, colour: Design.quiet).draw(x: rx, baseline: 5 * u + line)
        hairline(x: rx, y: 7 * u - 1, width: rw, nameField.currentEditor() != nil ? Design.ink : Design.rule)
        // Colour, on rows 7 and 8: the squares to choose from, the first none; the chosen one framed in ink.
        Design.attributed("Colour", .label, colour: Design.quiet).draw(x: rx, baseline: 7 * u + line)
        var choices: [String?] = [nil] + Self.colours.map { Optional($0) }
        if let own = info?.colour, !Self.colours.contains(own) { choices.append(own) }
        let gap: CGFloat = 6, n = CGFloat(choices.count)
        let side = max(10, min(16, ((rw - gap * (n - 1)) / n).rounded(.down)))
        let cb = 8 * u + line
        for (i, hex) in choices.enumerated() {
            let r = NSRect(x: rx + CGFloat(i) * (side + gap), y: cb + 2 - side, width: side, height: side)
            if let h = hex { fill(r, Design.hex(h)) } else {
                fill(r, Design.card)
                Design.quiet.setStroke()
                let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                let d = NSBezierPath(); d.lineWidth = 1; d.move(to: NSPoint(x: r.minX + 2, y: r.maxY - 2)); d.line(to: NSPoint(x: r.maxX - 2, y: r.minY + 2)); d.stroke()
            }
            if hex?.uppercased() == info?.colour?.uppercased() {
                Design.ink.setStroke()
                let e = NSBezierPath(rect: r.insetBy(dx: -2.5, dy: -2.5)); e.lineWidth = 1; e.stroke()
            }
            colourHits.append((r.insetBy(dx: -gap / 2, dy: -6), hex))
        }
        // Scope, on rows 9 and 10.
        scopeHit = dropdown("Scope", value: TagScopes.name(lib.scope(ofTag: name), in: lib), x: rx, row: 9, width: rw, open: droppedFrom == 2)
        // What wears it: the palettes on rows 11 and 12, the colours on 13 and 14, each as small square chips.
        let uses = lib.uses(ofTag: name)
        let hexes = Set(lib.hexes(tagged: name))
        let colours = lib.colours.map { $0.hex }.filter { hexes.contains($0) }
        chips("Palettes", count: uses.palettes.count, row: 11, x: rx, width: rw, items: uses.palettes.map { p in Array(p.entries.prefix(4).map { colour($0.hex) }) })
        chips("Colours", count: colours.count, row: 13, x: rx, width: rw, items: colours.map { [colour($0)] })
    }
    private func colour(_ hex: String) -> NSColor { shade[hex] ?? colorFromHex(hex) ?? Design.mist }

    /// A label with its count flush right, then a row of 14 squares: one colour each, or a palette's first four in quarters.
    /// What does not fit is said as a count in the last place, so the row never grows.
    private func chips(_ label: String, count: Int, row: CGFloat, x: CGFloat, width: CGFloat, items: [[NSColor]]) {
        let u = Self.u, line = Self.line
        Design.attributed(label, .label, colour: Design.quiet).draw(x: x, baseline: row * u + line)
        Design.attributed("\(count)", .caption, colour: Design.quiet).draw(right: x + width, baseline: row * u + line)
        let b = (row + 1) * u + line, side: CGFloat = 14, gap: CGFloat = 4
        guard !items.isEmpty else { Design.attributed("None", .body, colour: Design.soft).draw(x: x, baseline: b); return }
        let fits = max(1, Int((width + gap) / (side + gap)))
        let shown = items.count > fits ? fits - 1 : items.count
        for (i, cs) in items.prefix(shown).enumerated() {
            let r = NSRect(x: x + CGFloat(i) * (side + gap), y: b + 2 - side, width: side, height: side)
            if cs.isEmpty { fill(r, Design.mist) }
            else if cs.count == 1 { fill(r, cs[0]) }
            else {
                // Quarters, left to right then down; three colours leave the last quarter to the first.
                let h = side / 2
                for k in 0..<4 { fill(NSRect(x: r.minX + CGFloat(k % 2) * h, y: r.minY + CGFloat(k / 2) * h, width: h, height: h), cs[k < cs.count ? k : 0]) }
            }
        }
        if shown < items.count {
            Design.attributed("+\(items.count - shown)", .caption, colour: Design.quiet).draw(x: x + CGFloat(shown) * (side + gap), baseline: b)
        }
    }

    private func drawList() {
        let g = geometry(), u = Self.u, line = Self.line, l = leading, col = columns(g.lw)
        nameRects = []
        guard rowRects.count == rows.count else { return }
        if rows.isEmpty {
            Design.attributed(lib.allTags.isEmpty ? "No tags yet. New Tag makes one; the halo tags a palette or a colour." : "No tag matches the filters.", .body, colour: Design.soft).draw(x: l, baseline: line, width: g.lw)
            return
        }
        for (i, name) in rows.enumerated() {
            let box = rowRects[i], b = box.minY + line, on = name == chosen
            let text = Design.attributed(on ? (draft ?? name) : name, on ? .bodyStrong : .body)
            if on { fill(NSRect(x: 0, y: box.minY - 1, width: box.maxX + Design.App.areaGutter / 2, height: u + 1), Design.mist) }
            if let v = reveal[name], v > 0 {
                let full = l + col.name + min(text.size().width, col.scope - col.name - 12) + Self.step, eased = 1 - pow(1 - v, 3)
                fill(NSRect(x: 0, y: box.minY - 1, width: (full * eased).rounded(), height: u + 1), Design.App.gridColour)
            }
            // The tag's colour as a square; none of its own, an empty square.
            let sq = NSRect(x: l, y: b - 10, width: 12, height: 12)
            if let hex = lib.info(forTag: name)?.colour { fill(sq, Design.hex(hex)) } else {
                fill(sq, Design.card)
                Design.quiet.setStroke()
                let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            }
            let nameRect = NSRect(x: l + col.name, y: box.minY, width: col.scope - col.name - 12, height: u)
            nameRects.append(nameRect)
            if renaming != name { text.draw(x: nameRect.minX, baseline: b, width: nameRect.width) }
            Design.attributed(TagScopes.name(lib.scope(ofTag: name), in: lib), .caption, colour: Design.quiet).draw(x: l + col.scope, baseline: b, width: col.colours - col.scope - 56)
            let hexes = lib.hexes(tagged: name).count, palettes = lib.uses(ofTag: name).palettes.count
            Design.attributed("\(hexes)", .caption, colour: hexes == 0 ? Design.soft : Design.quiet).draw(right: l + col.colours, baseline: b)
            Design.attributed("\(palettes)", .caption, colour: palettes == 0 ? Design.soft : Design.quiet).draw(right: l + col.palettes, baseline: b)
            hairline(x: l, y: box.maxY - 1, width: box.width, Design.mist)
        }
    }

    // MARK: The rollover's clock, as the Schema page's

    private func goal(_ k: String) -> CGFloat { k == hover || k == chosen ? 1 : 0 }
    private func settle() {
        let moving = rows.contains { (reveal[$0] ?? 0) != goal($0) } || reveal.keys.contains { !rows.contains($0) }
        guard moving, clock == nil else { return }
        lastTick = Date()
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 90, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let now = Date(), step = CGFloat(now.timeIntervalSince(self.lastTick) / 0.1)
            self.lastTick = now
            var done = true
            for k in Set(self.rows).union(self.reveal.keys) {
                let g = self.rows.contains(k) ? self.goal(k) : 0, v = self.reveal[k] ?? 0
                if v == g { continue }
                let next = v < g ? min(g, v + step) : max(g, v - step)
                self.reveal[k] = next
                if next != g { done = false }
            }
            self.reveal = self.reveal.filter { $0.value > 0 }
            self.list.needsDisplay = true
            if done { t.invalidate(); self.clock = nil }
        }
        RunLoop.main.add(clock!, forMode: .common)
    }

    // MARK: The pointer

    private func listDown(at p: NSPoint) {
        guard let i = rowRects.firstIndex(where: { $0.contains(p) }), rows.indices.contains(i) else { return }
        let name = rows[i]
        if NSApp.currentEvent?.clickCount == 2, nameRects.indices.contains(i), nameRects[i].contains(p) { rename(name, in: nameRects[i], at: p); return }
        window?.makeFirstResponder(self)
        choose(name)
    }
    private func choose(_ name: String) {
        chosen = name; draft = nil
        needsLayout = true; needsDisplay = true; list.needsDisplay = true
        settle()
    }
    /// The name typed over where it is drawn, written when the typing ends.
    private func rename(_ name: String, in rect: NSRect, at p: NSPoint) {
        choose(name)
        renaming = name; list.needsDisplay = true
        InlineName.edit(name, style: .bodyStrong, in: list, x: rect.minX, baseline: rect.minY + Self.line, width: rect.width, at: p) { [weak self] typed in
            guard let self = self else { return }
            self.renaming = nil
            self.write(name: typed, for: name)
            self.list.needsDisplay = true
        }
    }
    private func write(name typed: String?, for old: String) {
        guard let new = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !new.isEmpty, new != old else { return }
        chosen = new
        library.renameTag(old, to: new)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if let h = filterHits.first(where: { $0.0.contains(p) }) { openFilter(h.1, under: h.0); return }
        guard let name = chosen else { return }
        if scopeHit.contains(p) { openScope(for: name); return }
        if let h = colourHits.first(where: { $0.0.contains(p) }) { library.setColour(h.1, ofTag: name) }
    }

    // MARK: The menus

    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil; droppedFrom = -1
        Overlays.closed(self)
        needsDisplay = true
    }
    private func openMenu(_ which: Int, under rect: NSRect, items: [String], chosen: String, pick: @escaping (Int) -> Void) {
        guard let win = window else { return }
        let again = droppedFrom == which
        closeMenu()
        if again { return }
        let panel = SwissDropdown.MenuPanel(items: items, chosen: chosen, width: max(200, rect.width)) { [weak self] i in self?.closeMenu(); pick(i) }
        let s = win.convertToScreen(convert(rect, to: nil))
        panel.place(below: NSPoint(x: s.minX, y: s.minY - 4))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel; droppedFrom = which
        Overlays.opened(self)
        needsDisplay = true
    }
    private func openFilter(_ which: Int, under rect: NSRect) {
        if which == 0 {
            let menu = TagScopes.menu(lib, lead: [("All", nil), (SwissDropdown.MenuPanel.divider, nil)])
            let now = scopeFilter.map { TagScopes.name($0, in: lib) } ?? "All"
            openMenu(0, under: rect, items: menu.items, chosen: now) { [weak self] i in
                guard let self = self else { return }
                self.scopeFilter = i == 0 ? nil : menu.scopes[i] ?? self.scopeFilter
                self.reload()
            }
        } else {
            // All, then the palettes outside any member, then each member's under its name.
            let M = SwissDropdown.MenuPanel.self
            var items = ["All"], ids: [UUID?] = [nil]
            let loose = lib.palettes(in: nil)
            if !loose.isEmpty { items += [M.divider, M.heading("Palettes")]; ids += [nil, nil]; for s in loose { items.append(s.name); ids.append(s.id) } }
            for p in lib.orderedProjects {
                let own = lib.palettes(in: p.id)
                guard !own.isEmpty else { continue }
                items += [M.divider, M.heading(p.name)]; ids += [nil, nil]
                for s in own { items.append(s.name); ids.append(s.id) }
            }
            let now = paletteFilter.flatMap { lib.swatch($0)?.name } ?? "All"
            openMenu(1, under: rect, items: items, chosen: now) { [weak self] i in
                guard let self = self else { return }
                self.paletteFilter = ids[i]
                self.reload()
            }
        }
    }
    private func openScope(for name: String) {
        let menu = TagScopes.menu(lib)
        openMenu(2, under: scopeHit, items: menu.items, chosen: TagScopes.name(lib.scope(ofTag: name), in: lib)) { [weak self] i in
            guard let self = self, let s = menu.scopes[i] else { return }
            self.library.setScope(s, ofTag: name)
        }
    }

    // MARK: Name, New Tag, Delete

    @objc private func nameEntered() { window?.makeFirstResponder(self) }
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === nameField else { return }
        draft = nameField.stringValue; list.needsDisplay = true
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === nameField, let old = chosen else { return }
        draft = nil
        write(name: nameField.stringValue, for: old)
        needsDisplay = true; list.needsDisplay = true
    }

    /// A tag made on the window's own panel: its name and its scope, the scope starting as the filter's when it has one.
    @objc private func newTag() {
        let menu = TagScopes.menu(lib)
        let start = scopeFilter ?? .global
        let taken = Set(lib.allTags.map { $0.lowercased() })
        SwissConfirm.name(over: window, title: "New Tag", note: "A tag to put on palettes and colours. Global goes on anything; a member or a group keeps it inside that one.",
                          placeholder: "Tag name", pickLabel: "Scope", items: menu.items, chosen: menu.scopes.firstIndex(of: start) ?? 0, confirm: "Make Tag",
                          check: { taken.contains($0.lowercased()) ? "There is a tag called \($0) already." : nil }) { [weak self] name, i in
            guard let self = self, !name.isEmpty else { return }
            self.chosen = name
            self.library.makeTag(name, scope: menu.scopes.indices.contains(i) ? menu.scopes[i] ?? .global : .global)
        }
    }
    @objc private func deleteTag() {
        guard let name = chosen else { return }
        let uses = lib.uses(ofTag: name)
        let worn = [uses.palettes.isEmpty ? nil : plural(uses.palettes.count, "palette"), uses.swatches.isEmpty ? nil : plural(uses.swatches.count, "colour")].compactMap { $0 }
        let note = worn.isEmpty ? "\(name) is not worn by anything. It goes from the list, and from every menu that offers it."
            : "\(name) is taken off the \(worn.joined(separator: " and ")) that wear it. The palettes and colours themselves are not touched."
        SwissConfirm.ask(over: window, title: "Delete Tag", note: note, commit: "Delete") { [weak self] in
            self?.chosen = nil
            self?.library.deleteTag(name)
        }
    }
}
