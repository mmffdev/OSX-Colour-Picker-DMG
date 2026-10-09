import AppKit

// ---------- Settings ▸ Schema, on the Studio window ----------
//
// Two columns on Master Inner. The left is the map, Schema: every collection at level 0, the level that groups
// its members when there is one, the Master Template with the groups every member follows, then the members
// themselves with those groups beneath each, exactly as rail1 lists them, tied by right-angled lines. Every row
// carries Add Child, Add Sibling and a bin. A group drags among its siblings. The right is the selected row,
// Type: its name, its description where it has one, then the types on offer for its level, each with its icon
// and a template, the ones its siblings already have locked. The map and the types each scroll under their
// header; the headers and the words stay.

final class SchemaSettings: NSView, NSTextFieldDelegate, NSTextViewDelegate, PageSection, Overlay {
    /// The template menu open over a type row, if any.
    private var dropped: SwissDropdown.MenuPanel?
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }
    /// Opens a menu under a rect of one of the views here, in that view's coordinates.
    private func openMenu(under rect: NSRect, in view: NSView, items: [String], chosen: String, pick: @escaping (Int) -> Void) {
        guard let win = window else { return }
        closeMenu()
        let panel = SwissDropdown.MenuPanel(items: items, chosen: chosen, width: max(200, rect.width)) { [weak self] i in self?.closeMenu(); pick(i) }
        let s = win.convertToScreen(view.convert(rect, to: nil))
        panel.place(below: NSPoint(x: s.maxX - max(200, rect.width), y: s.minY - 4))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }
    /// The types a group may be, at any level beneath the member: the app's own four, Projects, and every other word on offer.
    private static var groupTypes: [String] { Array(Set(SchemaTrial.nestedNames + SchemaRole.allCases.map { $0.title } + ["Projects"])).sorted() }
    private static func isRole(_ t: String) -> Bool { SchemaRole.allCases.contains { $0.title == t } }
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    /// The page's edge to its first column: the view starts at the rail's divider so a row's ground can reach it, and the words start here.
    var leading: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    // MARK: State

    /// What a row on the map is: a collection; the level grouping its members; one folder on that level; a group in the
    /// pattern with its level, the Master Template being 1; one member; or one group inside one member, shown, not edited here.
    private enum Target: Hashable {
        case collection(UUID), tier(UUID), folder(UUID, UUID), node(UUID, UUID, Int), member(UUID, UUID), instance(UUID, UUID, UUID, Int)
        var collection: UUID { switch self { case .collection(let c), .tier(let c), .folder(let c, _), .node(let c, _, _), .member(let c, _), .instance(let c, _, _, _): return c } }
    }
    /// A row of the map or a type on the right, for the rollover: the pane follows the pointer and locks on the chosen one.
    private enum Key: Hashable { case row(Target), type(String) }

    private var all: [SchemaCollection] = SchemaTrial.collections
    private var selected: Target?
    /// What is being typed into Name, drawn on the map as it goes and written only when the typing ends, since every write rebuilds the window.
    private var draft: String?
    private var lib: Library { library?.library ?? Library() }

    private func collection(_ id: UUID) -> SchemaCollection? { all.first { $0.id == id } }
    private func member(_ c: SchemaCollection) -> String { SchemaTrial.memberName(of: c) }
    private func offset(_ c: SchemaCollection) -> Int { c.folderName == nil ? 0 : 1 }
    private func members(of c: SchemaCollection) -> [Project] {
        let places = SchemaTrial.places
        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == c.id }
    }
    /// The members in one folder of the collection, or, with nil, those in no folder.
    private func members(of c: SchemaCollection, folder: UUID?) -> [Project] {
        let places = SchemaTrial.places
        return members(of: c).filter { SchemaTrial.folder(of: $0.id, among: all, places: places) == folder }
    }
    private func folderWord(_ c: SchemaCollection) -> String { c.folderName ?? "Folder" }
    private func node(_ nid: UUID, in c: SchemaCollection) -> SchemaNode? { SchemaTrial.rows(of: c.stack).first { $0.node.id == nid }?.node }
    /// The tree a member shows: its own once it has shaped one, the collection's Master Template until then.
    private func tree(of pid: UUID) -> SchemaNode { SchemaTrial.schema(for: pid) }
    private func node(_ nid: UUID, of pid: UUID) -> SchemaNode? { SchemaTrial.rows(of: tree(of: pid)).first { $0.node.id == nid }?.node }
    /// A change to a member's tree: the template is copied into a tree of the member's own first, if it still followed the template.
    private func shape(_ pid: UUID, _ change: (SchemaNode) -> SchemaNode) { SchemaTrial.setSchema(change(tree(of: pid)), for: pid); all = SchemaTrial.collections }
    private func parent(of id: UUID, in root: SchemaNode) -> UUID? {
        for (node, _) in SchemaTrial.rows(of: root) where node.children.contains(where: { $0.id == id }) { return node.id }
        return nil
    }

    // MARK: The views

    private let nameField = NSTextField(string: "")
    /// The description: a box of five lines, each line on the beat, in its own scroll.
    private let about = NSTextView()
    private let aboutScroll = NSScrollView()
    private let mapScroll = NSScrollView(), typeScroll = NSScrollView()
    private let map = Canvas(), types = Canvas()

    /// What a row's action is: a child beneath, a sibling after, or the bin.
    private enum Act { case child, sibling, bin }
    /// One row of the map, as the drawing lays it out.
    private struct MapRow { let target: Target; let text: String; let level: Int; let holds: String?; let strong: Bool; let does: [(Act, () -> Void)] }
    /// One type on offer at the right: locked when a sibling already has it, chosen when this row has it.
    private struct TypeRow { let name: String; let locked: Bool; let chosen: Bool; let symbol: String }
    private var mapRows: [MapRow] = []
    private var typeRows: [TypeRow] = []
    /// The last row of the templates: saves the row's own shape as a template of the catalogue.
    private static let saveTemplateRow = "Save As Template\u{2026}"
    private var rowRects: [NSRect] = []
    private var gripRects: [NSRect] = []
    private var doHits: [(NSRect, () -> Void)] = []
    private var typeHits: [(NSRect, String)] = []
    /// The template at the right of each type row, and the one on the Custom Name row.
    private var templateHits: [(NSRect, String)] = []
    /// The rollover: what is under the pointer, and how far each pane has flown out, 0 to 1, driven by its clock.
    private let rollover = Rollover<Key>()
    /// A group being dragged among its siblings, and the slot the pointer is over.
    private var dragging: Target?
    private var dragSlot: Int?
    private var dragStart: NSPoint?

    /// Master Inner: the unit and the line text sits on in it; the page's six columns within its width.
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private static let step: CGFloat = 16, helpUnits: CGFloat = 3, grip: CGFloat = 14

    init() {
        super.init(frame: .zero)
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = Design.Text.body.font()
        nameField.textColor = Design.ink
        nameField.delegate = self
        nameField.isHidden = true
        nameField.placeholderAttributedString = Design.attributed("Name", .body, colour: Design.soft)
        nameField.target = self; nameField.action = #selector(nameEntered)
        addSubview(nameField)
        about.drawsBackground = false
        about.focusRingType = .none
        about.font = Design.Text.body.font()
        about.textColor = Design.ink
        about.insertionPointColor = Design.ink
        about.isRichText = false
        about.textContainerInset = .zero
        about.textContainer?.lineFragmentPadding = 0
        about.isVerticallyResizable = true
        about.isHorizontallyResizable = false
        about.autoresizingMask = [.width]
        about.delegate = self
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = Design.App.unit; para.maximumLineHeight = Design.App.unit
        about.defaultParagraphStyle = para
        about.typingAttributes = [.font: Design.Text.body.font(), .foregroundColor: Design.ink, .paragraphStyle: para]
        aboutScroll.drawsBackground = false
        aboutScroll.hasVerticalScroller = true
        aboutScroll.autohidesScrollers = true
        aboutScroll.scrollerStyle = .overlay
        aboutScroll.documentView = about
        aboutScroll.isHidden = true
        addSubview(aboutScroll)
        for (scroll, canvas) in [(mapScroll, map), (typeScroll, types)] {
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            scroll.documentView = canvas
            addSubview(scroll)
        }
        rollover.keys = { [weak self] in self?.keys ?? [] }
        rollover.locked = { [weak self] k in self?.locked(k) ?? false }
        rollover.redraw = { [weak self] in self?.map.needsDisplay = true; self?.types.needsDisplay = true }
        map.onDraw = { [weak self] in self?.drawMap() }
        map.onDown = { [weak self] p in self?.mapDown(at: p) }
        map.onDrag = { [weak self] p in self?.mapDragged(to: p) }
        map.onUp = { [weak self] in self?.mapUp() }
        map.onMove = { [weak self] p in
            guard let self = self else { return }
            var over: Key?
            if let pt = p, let i = self.rowRects.firstIndex(where: { $0.contains(pt) }) { over = .row(self.mapRows[i].target) }
            self.moved(over)
        }
        types.onDraw = { [weak self] in self?.drawTypes() }
        types.onDown = { [weak self] p in self?.typesDown(at: p) }
        types.onMove = { [weak self] p in
            guard let self = self else { return }
            var over: Key?
            if let pt = p, let h = self.typeHits.first(where: { $0.0.contains(pt) }) { over = .type(h.1) }
            self.moved(over)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: The rollover

    /// A pane stays out on the chosen row and the chosen type; the rollover's clock does the rest.
    private func locked(_ k: Key) -> Bool {
        switch k {
        case .row(let t): return t == selected
        case .type(let n): return typeRows.contains { $0.name == n && $0.chosen }
        }
    }
    private var keys: [Key] { mapRows.map { .row($0.target) } + typeRows.map { .type($0.name) } }
    private func settle() { rollover.settle() }
    private func moved(_ over: Key?) { rollover.moved(over) }

    func reload() {
        all = SchemaTrial.collections
        if selected == nil || !stillThere(selected!) { selected = .collection(all[0].id) }
        refresh()
    }
    private func stillThere(_ t: Target) -> Bool {
        guard let c = collection(t.collection) else { return false }
        switch t {
        case .collection: return true
        case .tier: return c.folderName != nil
        case .folder(_, let f): return c.folders.contains { $0.id == f }
        case .node(_, let n, _): return node(n, in: c) != nil
        case .member(_, let p): return lib.project(p) != nil
        case .instance(_, let p, let n, _): return lib.project(p) != nil && node(n, of: p) != nil
        }
    }
    private func refresh() { needsLayout = true; needsDisplay = true; map.needsDisplay = true; types.needsDisplay = true; onResize?() }
    private func show() { all = SchemaTrial.collections; if selected == nil || !stillThere(selected!) { selected = .collection(all[0].id) }; refresh(); settle(); onChange?() }
    private func keep(_ c: UUID, _ tree: SchemaNode) { SchemaTrial.changeCollection(c) { $0.stack = tree }; all = SchemaTrial.collections }

    // MARK: What a group holds

    private func palettes(_ role: SchemaRole, in project: UUID) -> [UUID] { lib.palettes(in: project).filter { $0.isTypography == (role == .typography) }.map { $0.id } }
    private func tags(in project: UUID) -> [String] { lib.allTags.filter { lib.project(ofTag: $0) == project } }
    private func count(_ node: SchemaNode, in c: SchemaCollection, of member: UUID? = nil) -> Int {
        guard let role = SchemaTrial.role(of: node) else { return 0 }
        let holders = member.map { [$0] } ?? members(of: c).map { $0.id }.filter { !SchemaTrial.hasOwn($0) }
        switch role {
        case .information: return 0
        case .palettes, .typography: return holders.reduce(0) { $0 + palettes(role, in: $1).count }
        case .tags: return holders.reduce(0) { $0 + tags(in: $1).count }
        }
    }
    private func noun(_ role: SchemaRole?, _ n: Int) -> String {
        switch role {
        case .typography?: return n == 1 ? "typography palette" : "typography palettes"
        case .tags?: return n == 1 ? "tag" : "tags"
        default: return n == 1 ? "palette" : "palettes"
        }
    }

    // MARK: The map: every collection, its grouping level, its template, its members

    private func buildMap() -> [MapRow] {
        var out: [MapRow] = []
        for c in all {
            let inside = members(of: c), cid = c.id, hasTier = c.folderName != nil
            var does: [(Act, () -> Void)] = [(.child, { [weak self] in if hasTier { self?.addFolder(cid) } else { self?.addTier(cid) } }), (.sibling, { [weak self] in self?.newCollection(after: cid) })]
            if c.id != all[0].id { does.append((.bin, { [weak self] in self?.removeCollection(cid) })) }
            out.append(MapRow(target: .collection(cid), text: c.name.isEmpty ? "Unnamed" : c.name, level: 0,
                              holds: inside.isEmpty ? nil : "\(inside.count) " + (inside.count == 1 ? member(c) : SchemaTrial.plural(member(c))).lowercased(), strong: true, does: does))
            if let tier = c.folderName {
                out.append(MapRow(target: .tier(cid), text: tier, level: 1, holds: c.folders.isEmpty ? nil : "\(c.folders.count) made", strong: false,
                                  does: [(.child, { [weak self] in self?.addFolder(cid) }), (.bin, { [weak self] in self?.removeTier(cid) })]))
            }
            // The Master Template, the pattern every member follows, with its groups.
            for (node, level) in SchemaTrial.rows(of: c.stack) {
                let n = count(node, in: c), nid = node.id
                var does: [(Act, () -> Void)] = [(.child, { [weak self] in self?.add(child: true, at: nid, in: cid) })]
                if level > 1 {
                    does.append((.sibling, { [weak self] in self?.add(child: false, at: nid, in: cid) }))
                    does.append((.bin, { [weak self] in self?.remove(node, level: level, in: cid) }))
                } else {
                    does.append((.sibling, { [weak self] in self?.newMember(in: cid, folder: nil) }))
                }
                out.append(MapRow(target: .node(cid, nid, level), text: level == 1 ? "Master Template" : node.name, level: level + offset(c),
                                  holds: level == 1 ? nil : n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil, strong: level == 1, does: does))
            }
            // Then the members, as rail1 lists them: each folder on the grouping level with the members in it, then those in none.
            func memberRow(_ p: Project, folder: UUID?) {
                let pid = p.id, own = lib.palettes(in: pid).count, root = tree(of: pid).id
                out.append(MapRow(target: .member(cid, pid), text: p.name, level: 1 + offset(c), holds: own > 0 ? plural(own, "palette") : nil, strong: false,
                                  does: [(.child, { [weak self] in self?.addOwn(child: true, at: root, of: pid, in: cid) }), (.sibling, { [weak self] in self?.newMember(in: cid, folder: folder) }),
                                         (.bin, { [weak self] in self?.removeMember(cid, pid) })]))
                // The member's own tree beneath it, as rail1 lists it: the template's shape until the member shapes its own.
                for (node, level) in SchemaTrial.rows(of: tree(of: pid)) where level >= 2 {
                    let nid = node.id, n = count(node, in: c, of: pid)
                    out.append(MapRow(target: .instance(cid, pid, nid, level), text: node.name, level: level + offset(c),
                                      holds: n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil, strong: false,
                                      does: [(.child, { [weak self] in self?.addOwn(child: true, at: nid, of: pid, in: cid) }), (.sibling, { [weak self] in self?.addOwn(child: false, at: nid, of: pid, in: cid) }),
                                             (.bin, { [weak self] in self?.removeOwn(node, level: level, of: pid, in: cid) })]))
                }
            }
            if hasTier {
                for f in c.folders {
                    let fid = f.id, held = members(of: c, folder: fid)
                    out.append(MapRow(target: .folder(cid, fid), text: f.name, level: 1,
                                      holds: held.isEmpty ? nil : "\(held.count) " + (held.count == 1 ? member(c) : SchemaTrial.plural(member(c))).lowercased(), strong: false,
                                      does: [(.child, { [weak self] in self?.newMember(in: cid, folder: fid) }), (.sibling, { [weak self] in self?.addFolder(cid) }),
                                             (.bin, { [weak self] in self?.removeFolder(cid, fid) })]))
                    for p in held { memberRow(p, folder: fid) }
                }
                for p in members(of: c, folder: nil) { memberRow(p, folder: nil) }
            } else {
                for p in inside { memberRow(p, folder: nil) }
            }
        }
        return out
    }

    // MARK: The selected row: its words, name, description and the types on offer

    private struct Form {
        var title = "", help = "", name = "", said: String?, offered: [String] = [], chosen: String?, locked: Set<String> = [], canName = false, symbol = "square.dashed"
        /// The right column lists the catalogue's templates instead of types: on the Master Template and on a member.
        var templates = false
        /// The template the row was made from, ticked in the list.
        var fromTemplate: UUID?
        /// Whether the name is one of the types on offer; when it is not, the Custom Name row holds it with the type it follows.
        var custom: Bool { !offered.isEmpty && !offered.contains(name) }
    }
    private func symbol(forType t: String) -> String {
        switch SchemaRole.allCases.first(where: { $0.title == t }) {
        case .palettes?: return "swatchpalette"
        case .information?: return "info.circle"
        case .typography?: return "textformat"
        case .tags?: return "tag"
        case nil: return "square.dashed"
        }
    }
    private func form() -> Form {
        var f = Form()
        guard let what = selected, let c = collection(what.collection) else { return f }
        let heading = c.name.isEmpty ? "this collection" : c.name
        let memberWord = member(c).lowercased(), many = SchemaTrial.plural(member(c)).lowercased()
        switch what {
        case .collection:
            f.title = SchemaTrial.title(forLevel: 0); f.name = c.name; f.offered = SchemaTrial.collectionNames.sorted(); f.chosen = c.name; f.said = c.about; f.canName = true
            f.help = "Its name heads rail1; the description says what it is for. " + (c.folderName == nil ? "Its \(many) sit straight under it; Add Child makes a level that groups them." : "Its \(many) are grouped under the level on the next row.")
        case .tier:
            f.title = SchemaTrial.title(forLevel: 1); f.name = c.folderName ?? ""; f.offered = SchemaTrial.folderNames.sorted(); f.chosen = c.folderName; f.canName = true; f.symbol = "building.2"
            f.help = "The level that groups the \(many) of \(heading). Name what one of them is; Add Child makes one, and each is filled in rail1."
        case .folder(_, let fid):
            f.title = folderWord(c); f.name = c.folders.first { $0.id == fid }?.name ?? ""; f.canName = true; f.symbol = "building.2"
            f.help = "One \(folderWord(c).lowercased()) in \(heading), holding the \(many) listed beneath it. Add Child makes a \(memberWord) in it."
        case .node(_, let nid, let level):
            let n = node(nid, in: c) ?? c.stack
            f.title = level == 1 ? "Master Template" : SchemaTrial.title(forLevel: level + offset(c)); f.name = n.name; f.said = n.about; f.canName = true
            if level == 1 {
                f.symbol = "folder"
                f.templates = true; f.fromTemplate = c.templateID
                f.help = "What a \(memberWord) of \(heading) is called, and the pattern every one follows: the groups beneath it. Choose a template to make it this pattern, or save this pattern as a template; Add Child makes a group in every \(memberWord)."
            } else {
                f.offered = Self.groupTypes; f.chosen = SchemaTrial.type(of: n); f.symbol = symbol(forType: SchemaTrial.type(of: n))
                // The types its siblings already hold are locked: one of each to a level. A second can always be made under a name of its own.
                if let p = parent(of: nid, in: c), let pn = node(p, in: c) { f.locked = Set(pn.children.filter { $0.id != nid }.map { SchemaTrial.type(of: $0) }) }
                f.help = "A group in every \(memberWord) of \(heading). Choose its type, then name it as you like. Information, Palettes, Typography and Tags hold what they always have; any other type is a label for now."
            }
        case .member(_, let pid):
            f.title = member(c); f.name = lib.project(pid)?.name ?? ""; f.canName = true; f.symbol = "folder"; f.said = lib.project(pid)?.details?[ProjectField.notes.rawValue] ?? ""
            f.templates = true
            f.help = "One \(memberWord) in \(heading): a folder of its own in the catalogue, following the Master Template until it is shaped. Choose a template to give it that shape as its own, or save its shape as a template."
        case .instance(_, let pid, let nid, let level):
            let root = tree(of: pid), n = node(nid, of: pid) ?? root
            f.title = SchemaTrial.title(forLevel: level + offset(c)); f.name = n.name; f.said = n.about; f.canName = true
            f.offered = Self.groupTypes; f.chosen = SchemaTrial.type(of: n); f.symbol = symbol(forType: SchemaTrial.type(of: n))
            if let p = parent(of: nid, in: root), let pn = SchemaTrial.rows(of: root).first(where: { $0.node.id == p })?.node { f.locked = Set(pn.children.filter { $0.id != nid }.map { SchemaTrial.type(of: $0) }) }
            f.help = (SchemaTrial.hasOwn(pid) ? "A group of \(lib.project(pid)?.name ?? memberWord)'s own: its tree began as the Master Template and is now its own to shape." : "A group in \(lib.project(pid)?.name ?? memberWord), following the Master Template; the first change here gives the \(memberWord) a tree of its own.")
                + " Choose its type, then name it as you like."
        }
        return f
    }

    // MARK: Geometry: the two columns on the page's six columns and the unit

    private struct Geometry {
        var lw: CGFloat = 0, rx: CGFloat = 0, rw: CGFloat = 0
        var mapTop: CGFloat = 0, formTop: CGFloat = 0, nameLabel: CGFloat = 0, nameRow = NSRect.zero, aboutLabel: CGFloat = 0, aboutRow: NSRect?, typesTop: CGFloat = 0
        var form = Form()
    }
    private func geometry(width w: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u, gut = Design.App.areaGutter, l = leading   // the split is an area gutter
        // Both columns: a header on row 0, words on rows 1 to 3, a second header on row 4 with its rule, content from row 5. The map takes 60 of the width, the selected row 40.
        g.lw = ((w - gut) * 0.6).rounded(); g.rx = l + g.lw + gut; g.rw = w - g.lw - gut
        g.mapTop = 5 * u
        g.form = form()
        g.formTop = 5 * u
        // Under the Type rule: Name over its field, Description over its box of five lines, then the types; every piece a whole number of units, so the types' rows keep the map's beat.
        var y = g.formTop
        if g.form.canName { g.nameLabel = y; g.nameRow = NSRect(x: g.rx, y: y + u, width: g.rw, height: u); y += 2 * u }
        if g.form.said != nil { g.aboutLabel = y; g.aboutRow = NSRect(x: g.rx, y: y + u, width: g.rw, height: 5 * u); y += 6 * u }
        g.typesTop = y
        return g
    }
    private var leftHelp: String {
        "Every collection is a heading in rail1, with its members under it, grouped under a level between when it has one. Each member follows its collection's Master Template: the groups inside it. Add Child and Add Sibling on any row make another; a group drags among its siblings."
    }

    /// The section fills the page; the map and the types scroll within it.
    func height(forWidth width: CGFloat) -> CGFloat { 0 }

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width - leading), u = Self.u, line = Self.line
        mapRows = buildMap()
        typeRows = g.form.templates
            ? SchemaTrial.templates.map { TypeRow(name: $0.name, locked: false, chosen: $0.id == g.form.fromTemplate, symbol: "square.stack.3d.up") } + [TypeRow(name: Self.saveTemplateRow, locked: false, chosen: false, symbol: "plus")]
            : g.form.offered.map { TypeRow(name: $0, locked: g.form.locked.contains($0) && $0 != g.form.chosen, chosen: $0 == g.form.chosen, symbol: symbol(forType: $0)) }
        // The map's scroll starts at the page's edge, so a row's ground can reach the rail's divider, and ends in the middle of the gutter.
        mapScroll.frame = NSRect(x: 0, y: g.mapTop, width: leading + g.lw + Design.App.areaGutter / 2, height: max(0, bounds.height - g.mapTop))
        let mapHeight = CGFloat(mapRows.count) * u + u
        map.frame = NSRect(x: 0, y: 0, width: mapScroll.frame.width, height: max(mapScroll.frame.height, mapHeight))
        mapScroll.verticalScrollElasticity = mapHeight > mapScroll.frame.height ? .allowed : .none
        rowRects = mapRows.indices.map { NSRect(x: leading, y: CGFloat($0) * u, width: g.lw, height: u) }
        let lead = Design.App.areaGutter / 2
        typeScroll.frame = NSRect(x: g.rx - lead, y: g.typesTop, width: g.rw + lead, height: max(0, bounds.height - g.typesTop))
        let typesHeight = CGFloat(typeRows.count) * u + u
        types.frame = NSRect(x: 0, y: 0, width: g.rw + lead, height: max(typeScroll.frame.height, typesHeight))
        typeScroll.verticalScrollElasticity = typesHeight > typeScroll.frame.height ? .allowed : .none
        typeScroll.isHidden = typeRows.isEmpty
        // A 13 field's text sits 15 below its top: on the line.
        nameField.isHidden = selected == nil || !g.form.canName
        nameField.frame = NSRect(x: g.nameRow.minX - 2, y: g.nameRow.minY + line - 12, width: g.nameRow.width + 2, height: 20)
        if nameField.currentEditor() == nil { nameField.stringValue = g.form.name }
        aboutScroll.isHidden = g.aboutRow == nil
        if let r = g.aboutRow {
            // The box's first line sits on the row's line: the text's baseline in a 28 line is 20 below the line's top.
            aboutScroll.frame = NSRect(x: r.minX, y: r.minY + line - 20, width: r.width, height: r.height)
            about.frame = NSRect(x: 0, y: 0, width: r.width, height: r.height)
            about.textContainer?.containerSize = NSSize(width: r.width, height: .greatestFiniteMagnitude)
        }
        if window?.firstResponder !== about { about.string = g.form.said ?? "" }
    }

    // MARK: Drawing: the headers and words here, the map and the types on their own canvases

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width - leading), u = Self.u, line = Self.line, l = leading
        // The two first-order headers on the first line, their words in a box of three units under each, then the second pair of headers on one line with their rules.
        Design.attributed("Structure", .header).draw(x: l, baseline: line)
        Design.attributed(leftHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: l, y: u, width: g.lw, height: Self.helpUnits * u))
        Design.attributed("Schema", .header).draw(x: l, baseline: 4 * u + line)
        hairline(x: l, y: g.mapTop - 1, width: g.lw, Design.rule)
        guard selected != nil else { return }
        let rx = g.rx
        Design.attributed(g.form.title, .header).draw(x: rx, baseline: line)
        Design.attributed(g.form.help, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: u, width: g.rw, height: Self.helpUnits * u))
        Design.attributed(g.form.templates ? "Templates" : "Type", .header).draw(x: rx, baseline: 4 * u + line)
        hairline(x: rx, y: g.formTop - 1, width: g.rw, Design.rule)
        if g.form.canName {
            Design.attributed("Name", .label, colour: Design.quiet).draw(x: rx, baseline: g.nameLabel + line)
            hairline(x: rx, y: g.nameRow.maxY - 1, width: g.rw, nameField.currentEditor() != nil ? Design.ink : Design.rule)
        }
        if let r = g.aboutRow {
            Design.attributed("Description", .label, colour: Design.quiet).draw(x: rx, baseline: g.aboutLabel + line)
            if about.string.isEmpty && window?.firstResponder !== about { Design.attributed("What this holds", .body, colour: Design.soft).draw(x: rx, baseline: r.minY + line) }
            hairline(x: rx, y: r.maxY - 1, width: g.rw, window?.firstResponder === about ? Design.ink : Design.rule)
        }
    }
    /// The icon and the template at the right of a row on the Type side: the icon picker to come, and the template's word with its
    /// menu, which the app's own four types do without. Returns the rect a click opens the menu from.
    @discardableResult
    private func trailing(in box: NSRect, baseline b: CGFloat, symbol: String, word: String? = "Template") -> NSRect {
        var hit = NSRect.zero
        if let word = word {
            let t = Design.attributed(word, .caption, colour: Design.quiet)
            t.draw(right: box.maxX - 14, baseline: b)
            Design.quiet.setStroke()
            let p = NSBezierPath(); p.lineWidth = 1
            p.move(to: NSPoint(x: box.maxX - 9, y: b - 6)); p.line(to: NSPoint(x: box.maxX - 5, y: b - 2)); p.line(to: NSPoint(x: box.maxX - 1, y: b - 6))
            p.stroke()
            hit = NSRect(x: box.maxX - 14 - t.size().width - 8, y: box.minY, width: t.size().width + 22, height: box.height)
        }
        RowMark.draw(symbol, x: box.maxX - 120, baseline: b, colour: Design.soft)
        return hit
    }

    private func drawMap() {
        let line = Self.line, l = leading
        doHits = []; gripRects = []
        guard rowRects.count == mapRows.count else { return }
        // The grounds first, each a point taller at the top so it sits over the rule above it; then the tree's lines; then the rows.
        for (i, r) in mapRows.enumerated() {
            let box = rowRects[i]
            let on = r.target == selected
            if on { fill(NSRect(x: 0, y: box.minY - 1, width: box.maxX + Design.App.areaGutter / 2, height: box.height + 1), Design.mist) }
            let x = l + CGFloat(r.level) * Self.step
            let name = Design.attributed(on ? (draft ?? r.text) : r.text, on || r.strong ? .bodyStrong : .body, colour: on || r.strong ? Design.ink : Design.quiet)
            rollover.pane(.row(r.target), box: box, reach: x + 36 + name.size().width + Self.step)
        }
        TreeLines.draw(mapRows.enumerated().map { k, m in
            TreeLines.Row(top: rowRects[k].minY, height: rowRects[k].height, level: m.level, anchor: l + CGFloat(m.level) * Self.step + 3.5, markLeft: l + CGFloat(m.level) * Self.step, baseline: line)
        }, colour: Design.rule)
        for (i, r) in mapRows.enumerated() {
            let box = rowRects[i], b = box.minY + line
            let on = r.target == selected
            let x = l + CGFloat(r.level) * Self.step
            let name = Design.attributed(on ? (draft ?? r.text) : r.text, on || r.strong ? .bodyStrong : .body, colour: on || r.strong ? Design.ink : Design.quiet)
            Design.attributed("\(r.level)", .caption, colour: Design.soft).draw(x: x, baseline: b)
            // The grip between the level and the name: two columns of three dots; a drag from it puts the row in another order among its own.
            let grip = NSRect(x: x + 16, y: box.minY, width: Self.grip, height: box.height)
            if canDrag(r.target) {
                for dx in [0, 4] as [CGFloat] { for dy in [-4, 0, 4] as [CGFloat] { fill(NSRect(x: grip.minX + 2 + dx, y: b - 5 + dy, width: 1.5, height: 1.5), on ? Design.quiet : Design.soft) } }
                gripRects.append(grip)
            } else { gripRects.append(.zero) }
            var right = box.maxX
            if on {
                // Add Child, Add Sibling and the bin, from the right: the bin an icon alone.
                for (act, run) in r.does.reversed() {
                    let title = act == .child ? "Add Child" : act == .sibling ? "Add Sibling" : ""
                    let t = Design.attributed(title, .caption, colour: Design.quiet)
                    let w = title.isEmpty ? 0 : t.size().width
                    right -= w
                    if !title.isEmpty { t.draw(x: right, baseline: b) }
                    icon(act, at: NSPoint(x: right - 14, y: b - 9))
                    doHits.append((NSRect(x: right - 20, y: box.minY, width: w + 24, height: box.height), run))
                    right -= title.isEmpty ? 24 : 32
                }
            } else if let holds = r.holds {
                let t = Design.attributed(holds, .caption, colour: Design.quiet)
                t.draw(right: right, baseline: b)
                right -= t.size().width + 12
            }
            name.draw(x: x + 36, baseline: b, width: right - x - 36)
            hairline(x: l, y: box.maxY - 1, width: box.width, Design.mist)
        }
        if let slot = dragSlot, let d = dragging, let i = mapRows.firstIndex(where: { $0.target == d }) {
            let y = slotY(slot, for: d)
            fill(NSRect(x: l + CGFloat(mapRows[i].level) * Self.step, y: y - 1, width: rowRects[i].width - CGFloat(mapRows[i].level) * Self.step, height: 2), Design.ink)
        }
    }

    private func drawTypes() {
        let u = Self.u, line = Self.line, w = types.bounds.width, lead = Design.App.areaGutter / 2, air: CGFloat = 16
        typeHits = []; templateHits = []
        for (i, t) in typeRows.enumerated() {
            let box = NSRect(x: 0, y: CGFloat(i) * u, width: w, height: u), b = box.minY + line
            if t.chosen { fill(NSRect(x: 0, y: box.minY - 1, width: w, height: u + 1), Design.mist) }
            let name = Design.attributed(t.name, t.chosen ? .bodyStrong : .body, colour: t.locked ? Design.soft : t.chosen ? Design.ink : Design.quiet)
            // The pane: from the middle of the gutter, over the square and the name, to the name's end plus a step.
            rollover.pane(.type(t.name), box: box, reach: lead + 24 + name.size().width + Self.step)
            // The square: filled for the chosen type and for one a sibling holds, which cannot be chosen again.
            let sq = NSRect(x: lead, y: b - 10, width: 12, height: 12)
            fill(sq, t.chosen || t.locked ? Design.ink : Design.card)
            Design.ink.setStroke()
            let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
            name.draw(x: lead + 24, baseline: b, width: w - lead - 24 - 150)
            let inTemplates = form().templates
            let menuRect = trailing(in: NSRect(x: lead, y: box.minY, width: w - lead - air, height: u), baseline: b, symbol: t.symbol,
                                    word: inTemplates ? (t.name == Self.saveTemplateRow ? nil : "Delete") : Self.isRole(t.name) ? nil : "Template")
            hairline(x: lead, y: box.maxY - 1, width: w - lead - air, Design.mist)
            if !t.locked {
                if !menuRect.isEmpty { templateHits.append((menuRect, t.name)) }
                typeHits.append((box, t.name))
            }
        }
    }

    private func icon(_ act: Act, at p: NSPoint) {
        Design.quiet.setStroke()
        let s: CGFloat = 9, path = NSBezierPath()
        path.lineWidth = 1.2
        switch act {
        case .bin:
            // A bin: the lid with its handle, then the body.
            path.move(to: NSPoint(x: p.x, y: p.y + 2)); path.line(to: NSPoint(x: p.x + s + 1, y: p.y + 2))
            path.move(to: NSPoint(x: p.x + 3, y: p.y + 2)); path.line(to: NSPoint(x: p.x + 3, y: p.y)); path.line(to: NSPoint(x: p.x + s - 2, y: p.y)); path.line(to: NSPoint(x: p.x + s - 2, y: p.y + 2))
            path.move(to: NSPoint(x: p.x + 1.5, y: p.y + 2)); path.line(to: NSPoint(x: p.x + 2.5, y: p.y + s + 1)); path.line(to: NSPoint(x: p.x + s - 1.5, y: p.y + s + 1)); path.line(to: NSPoint(x: p.x + s - 0.5, y: p.y + 2))
        case .sibling:
            path.move(to: NSPoint(x: p.x, y: p.y + 5)); path.line(to: NSPoint(x: p.x + s, y: p.y + 5))
            path.move(to: NSPoint(x: p.x + 5, y: p.y)); path.line(to: NSPoint(x: p.x + 5, y: p.y + s))
        case .child:
            path.move(to: NSPoint(x: p.x + 1, y: p.y)); path.line(to: NSPoint(x: p.x + 1, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6))
            path.move(to: NSPoint(x: p.x + s - 3, y: p.y + 3)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s - 3, y: p.y + 9))
        }
        path.stroke()
    }

    // MARK: The pointer: select, act, choose a type, drag a group among its siblings

    private func mapDown(at p: NSPoint) {
        window?.makeFirstResponder(self)
        if let d = doHits.first(where: { $0.0.contains(p) }) { d.1(); return }
        if let i = rowRects.firstIndex(where: { $0.contains(p) }) {
            let r = mapRows[i]
            selected = r.target
            dragging = gripRects[i].contains(p) && canDrag(r.target) ? r.target : nil
            dragStart = p
            refresh()
            settle()
        }
    }
    private func typesDown(at p: NSPoint) {
        if form().templates {
            if let h = templateHits.first(where: { $0.0.contains(p) }), let t = SchemaTrial.templates.first(where: { $0.name == h.1 }) { deleteTemplate(t); return }
            if let h = typeHits.first(where: { $0.0.contains(p) }) { h.1 == Self.saveTemplateRow ? saveAsTemplate() : useTemplate(named: h.1) }
            return
        }
        if let h = templateHits.first(where: { $0.0.contains(p) }) { openTemplates(for: h.1, under: h.0, in: types); return }
        if let h = typeHits.first(where: { $0.0.contains(p) }) { choose(type: h.1) }
    }

    // MARK: Templates: the catalogue's own shapes, used, saved and deleted here

    /// The shape the selected row stands for: the collection's Master Template, or the member's own tree.
    private var shapeInHand: SchemaNode? {
        guard let what = selected, let c = collection(what.collection) else { return nil }
        switch what {
        case .node(_, _, 1): return c.stack
        case .member(_, let pid): return tree(of: pid)
        default: return nil
        }
    }
    private func useTemplate(named name: String) {
        guard let what = selected, let t = SchemaTrial.templates.first(where: { $0.name == name }) else { return }
        switch what {
        case .node(let cid, _, 1): SchemaTrial.apply(template: t.id, toCollection: cid)
        case .member(_, let pid): SchemaTrial.apply(template: t.id, toMember: pid)
        default: return
        }
        library?.flash("\(name) is now the shape")
        show()
    }
    private func saveAsTemplate() {
        guard let shape = shapeInHand else { return }
        SwissConfirm.name(over: window, title: "Save As Template", note: "The shape as it stands, the groups beneath the member, kept as a template of this catalogue for any collection or member to take.",
                          placeholder: "Template name", value: "", confirm: "Save", check: { name in SchemaTrial.templates.contains { $0.name.lowercased() == name.lowercased() } ? "There is a template called that already." : nil }) { [weak self] name in
            SchemaTrial.saveTemplate(shape, named: name)
            self?.show()
        }
    }
    private func deleteTemplate(_ t: SchemaTemplate) {
        SwissConfirm.ask(over: window, title: "Delete Template", note: "You are about to delete the template \(t.name). Every collection and member keeps the shape it took from it; only the template goes.", commit: "Delete") { [weak self] in
            SchemaTrial.removeTemplate(t.id)
            self?.show()
        }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    /// A type's menu: the type itself, Customise, which takes the type and opens the name, and the templates saved for it, none yet.
    private func openTemplates(for type: String, under rect: NSRect, in view: NSView) {
        let M = SwissDropdown.MenuPanel.self
        let items = [type, M.divider, "Customise", M.divider, M.heading("Templates"), M.heading("None saved yet")]
        openMenu(under: rect, in: view, items: items, chosen: type) { [weak self] i in
            guard let self = self else { return }
            if i == 0 { self.choose(type: type) }
            if i == 2 { self.choose(type: type); self.customise() }
        }
    }
    /// The name becomes the row's own: the field takes the typing with the type's word selected, ready to be replaced.
    private func customise() {
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    /// What can be put in another order: a collection among the collections, a folder among the folders, a group among its siblings, a member among the members.
    private func canDrag(_ t: Target) -> Bool {
        switch t {
        case .collection: return all.count > 1
        case .tier: return false
        case .instance(_, let pid, let nid, _): return parent(of: nid, in: tree(of: pid)).flatMap { p in SchemaTrial.rows(of: tree(of: pid)).first { $0.node.id == p }?.node.children.count } ?? 0 > 1
        case .folder(let cid, _): return (collection(cid)?.folders.count ?? 0) > 1
        case .node(_, _, let level): return level > 1
        case .member(let cid, _): return (collection(cid).map { members(of: $0).count } ?? 0) > 1
        }
    }
    /// The rows a dragged row may land among, in order, itself included.
    private func peers(of t: Target) -> [Target] {
        switch t {
        case .collection: return all.map { .collection($0.id) }
        case .tier: return []
        case .instance(let cid, let pid, let nid, let level):
            guard let p = parent(of: nid, in: tree(of: pid)), let pn = SchemaTrial.rows(of: tree(of: pid)).first(where: { $0.node.id == p })?.node else { return [] }
            return pn.children.map { .instance(cid, pid, $0.id, level) }
        case .folder(let cid, _): return collection(cid).map { $0.folders.map { .folder(cid, $0.id) } } ?? []
        case .node(let cid, let nid, let level): return collection(cid).map { siblings(of: nid, in: $0).map { .node(cid, $0, level) } } ?? []
        case .member(let cid, _): return collection(cid).map { members(of: $0).map { .member(cid, $0.id) } } ?? []
        }
    }
    private func mapDragged(to p: NSPoint) {
        guard let d = dragging, let start = dragStart else { return }
        guard abs(p.y - start.y) > 4 || dragSlot != nil else { return }
        let sibs = peers(of: d)
        var slot = sibs.count
        for (k, s) in sibs.enumerated() {
            if let i = mapRows.firstIndex(where: { $0.target == s }), p.y < rowRects[i].midY { slot = k; break }
        }
        if slot != dragSlot { dragSlot = slot; map.needsDisplay = true }
    }
    private func mapUp() {
        if let d = dragging, let slot = dragSlot {
            switch d {
            case .node(let cid, let nid, _):
                if let c = collection(cid) { keep(cid, SchemaTrial.moving(nid, to: slot, in: c.stack)) }
            case .collection(let cid):
                var list = SchemaTrial.collections
                if let from = list.firstIndex(where: { $0.id == cid }) {
                    let moved = list.remove(at: from)
                    var to = min(max(slot, 0), list.count + 1)
                    if from < to { to -= 1 }
                    list.insert(moved, at: min(to, list.count))
                    SchemaTrial.collections = list
                }
            case .member(let cid, let pid):
                // The members of this collection in their new order, among every project's order.
                if let c = collection(cid), let lib = library {
                    var mine = members(of: c).map { $0.id }
                    if let from = mine.firstIndex(of: pid) {
                        mine.remove(at: from)
                        var to = min(max(slot, 0), mine.count + 1)
                        if from < to { to -= 1 }
                        mine.insert(pid, at: min(to, mine.count))
                        var order = self.lib.orderedProjects.map { $0.id }, k = 0
                        for i in order.indices where mine.contains(order[i]) { order[i] = mine[k]; k += 1 }
                        lib.placeProjects(order)
                    }
                }
            case .folder(let cid, let fid):
                SchemaTrial.changeCollection(cid) { col in
                    guard let from = col.folders.firstIndex(where: { $0.id == fid }) else { return }
                    let moved = col.folders.remove(at: from)
                    var to = min(max(slot, 0), col.folders.count + 1)
                    if from < to { to -= 1 }
                    col.folders.insert(moved, at: min(to, col.folders.count))
                }
            case .instance(_, let pid, let nid, _):
                shape(pid) { SchemaTrial.moving(nid, to: slot, in: $0) }
            case .tier: break
            }
            show()
        }
        dragging = nil; dragSlot = nil; dragStart = nil
        map.needsDisplay = true
    }
    private func siblings(of id: UUID, in c: SchemaCollection) -> [UUID] {
        for (node, _) in SchemaTrial.rows(of: c.stack) where node.children.contains(where: { $0.id == id }) { return node.children.map { $0.id } }
        return []
    }
    /// Where the drag's line sits: above the slot's row, or under the last sibling's subtree.
    private func slotY(_ slot: Int, for d: Target) -> CGFloat {
        let sibs = peers(of: d)
        if slot < sibs.count, let i = mapRows.firstIndex(where: { $0.target == sibs[slot] }) { return rowRects[i].minY }
        if let last = sibs.last, let i = mapRows.firstIndex(where: { $0.target == last }) {
            var end = i
            while end + 1 < mapRows.count && mapRows[end + 1].level > mapRows[i].level { end += 1 }
            return rowRects[end].maxY
        }
        return 0
    }
    private func parent(of id: UUID, in c: SchemaCollection) -> UUID? {
        for (node, _) in SchemaTrial.rows(of: c.stack) where node.children.contains(where: { $0.id == id }) { return node.id }
        return nil
    }

    // MARK: Adding, removing, moving

    private func add(child: Bool, at id: UUID, in cid: UUID) {
        guard let c = collection(cid) else { return }
        let result = child ? SchemaTrial.addingChild(to: id, in: c.stack) : SchemaTrial.addingSibling(after: id, in: c.stack)
        keep(cid, result.tree)
        if let made = result.added, let level = SchemaTrial.rows(of: result.tree).first(where: { $0.node.id == made })?.level { selected = .node(cid, made, level) }
        show()
    }

    private func addOwn(child: Bool, at id: UUID, of pid: UUID, in cid: UUID) {
        var made: UUID?
        shape(pid) { root in
            let r = child ? SchemaTrial.addingChild(to: id, in: root) : SchemaTrial.addingSibling(after: id, in: root)
            made = r.added
            return r.tree
        }
        if let m = made, let level = SchemaTrial.rows(of: tree(of: pid)).first(where: { $0.node.id == m })?.level { selected = .instance(cid, pid, m, level) }
        show()
    }
    /// The bin on a group of a member's own: gone at once when it holds nothing in that member; asked about when it holds something.
    private func removeOwn(_ node: SchemaNode, level: Int, of pid: UUID, in cid: UUID) {
        guard let c = collection(cid) else { return }
        let n = count(node, in: c, of: pid)
        guard n == 0 else { selected = .instance(cid, pid, node.id, level); refresh(); askAboutContents(of: node, in: c, holding: n); return }
        let up = parent(of: node.id, in: tree(of: pid))
        shape(pid) { SchemaTrial.removing(node.id, from: $0) }
        if let p = up, let l = SchemaTrial.rows(of: tree(of: pid)).first(where: { $0.node.id == p })?.level { selected = p == tree(of: pid).id ? .member(cid, pid) : .instance(cid, pid, p, l) }
        show()
    }

    /// The bin on a group: gone at once when it holds nothing, and the row above it takes the selection; asked about on the panel when it holds something.
    private func remove(_ node: SchemaNode, level: Int, in cid: UUID) {
        guard let c = collection(cid) else { return }
        let n = count(node, in: c)
        guard n == 0 else { selected = .node(cid, node.id, level); refresh(); askAboutContents(of: node, in: c, holding: n); return }
        let up = parent(of: node.id, in: c)
        let tree = SchemaTrial.removing(node.id, from: c.stack)
        keep(cid, tree)
        if let p = up, let l = SchemaTrial.rows(of: tree).first(where: { $0.node.id == p })?.level { selected = .node(cid, p, l) }
        show()
    }

    private func askAboutContents(of node: SchemaNode, in c: SchemaCollection, holding n: Int) {
        let role = SchemaTrial.role(of: node), things = "\(n) \(noun(role, n))"
        let note = "You are about to remove \(node.name), which holds \(things), spread over the \(c.name) \(SchemaTrial.plural(member(c)).lowercased()) that follow this template. They would be left with nowhere to show. The group can be renamed and they stay where they are; to delete them, do it member by member."
        SwissConfirm.ask(over: window, title: "Remove Group", note: note, commit: "Go On",
                         options: ["Keep the \(noun(role, n)) and rename the group"]) { [weak self] _ in self?.focusName() }
    }
    /// The name field takes the typing, its words selected.
    private func focusName() {
        show()
        window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    private func addTier(_ cid: UUID) {
        SchemaTrial.changeCollection(cid) { $0.folderName = SchemaTrial.folderNames[0] }
        selected = .tier(cid)
        show()
    }
    private func addFolder(_ cid: UUID) {
        var made: UUID?
        SchemaTrial.changeCollection(cid) { col in
            let f = SchemaFolder(name: "\(col.folderName ?? "Folder") \(col.folders.count + 1)")
            made = f.id
            col.folders.append(f)
        }
        if let f = made { selected = .folder(cid, f) }
        focusName()
    }
    private func removeFolder(_ cid: UUID, _ fid: UUID) {
        guard let lib = library else { return }
        lib.dump(folder: fid, in: cid, over: window) { [weak self] in
            self?.selected = .tier(cid)
            self?.show()
        }
    }
    private func removeTier(_ cid: UUID) {
        SchemaTrial.changeCollection(cid) { $0.folderName = nil; $0.folders = [] }
        selected = .collection(cid)
        show()
    }
    private func removeMember(_ cid: UUID, _ pid: UUID) {
        guard let lib = library else { return }
        lib.dump(project: pid, over: window) { [weak self] in
            self?.selected = .collection(cid)
            self?.show()
        }
    }
    private func removeCollection(_ cid: UUID) {
        guard cid != all[0].id, let lib = library else { return }
        lib.dump(collection: cid, over: window) { [weak self] in
            self?.selected = .collection(SchemaTrial.firstCollection)
            self?.show()
        }
    }

    /// Another collection, after this one, starting with its template; it appears at once, its name ready to type over.
    private func newCollection(after cid: UUID) {
        guard let c = collection(cid) else { return }
        var list = SchemaTrial.collections
        let taken = Set(list.map { $0.name })
        let name = SchemaTrial.collectionNames.first { !taken.contains($0) } ?? "Collection \(list.count + 1)"
        let made = SchemaCollection(name: name, stack: c.stack)
        list.insert(made, at: (list.firstIndex { $0.id == cid } ?? list.count - 1) + 1)
        SchemaTrial.collections = list
        selected = .collection(made.id)
        focusName()
    }

    /// Another member of the collection: a project with files of its own, placed in the collection and the folder, named at once on the right.
    private func newMember(in cid: UUID, folder: UUID?) {
        guard let c = collection(cid), let lib = library else { return }
        let word = member(c), n = members(of: c).count + 1
        var made: UUID?
        lib.apply("New \(word)") { l in
            let id = l.createProject(named: "\(word) \(n)")
            let organisation = ProjectField.tidy(Prefs.organisation)
            if !organisation.isEmpty { l.setProjectDetails(id, organisation) }
            made = id
        }
        guard let id = made, lib.library.project(id) != nil else { return }
        SchemaTrial.place(id, in: cid, folder: folder)
        selected = .member(cid, id)
        focusName()
    }

    // MARK: Types and names

    /// A type chosen on the right: the row takes it, its name starts as the type unless it already had one of its own, and the name is ready to change.
    private func choose(type: String) {
        guard let what = selected, let c = collection(what.collection) else { return }
        switch what {
        case .collection(let cid): SchemaTrial.changeCollection(cid) { $0.name = type }
        case .tier(let cid): SchemaTrial.changeCollection(cid) { $0.folderName = type }
        case .node(let cid, let nid, _):
            keep(cid, SchemaTrial.changing(nid, in: c.stack) { n in
                let wasTyped = n.name == SchemaTrial.type(of: n) || n.name.isEmpty
                n.kind = type
                n.role = SchemaRole.allCases.first { $0.title == type }
                if wasTyped { n.name = type }
            })
        case .instance(_, let pid, let nid, _):
            shape(pid) { root in
                SchemaTrial.changing(nid, in: root) { n in
                    let wasTyped = n.name == SchemaTrial.type(of: n) || n.name.isEmpty
                    n.kind = type
                    n.role = SchemaRole.allCases.first { $0.title == type }
                    if wasTyped { n.name = type }
                }
            }
        case .folder, .member: return
        }
        focusName()
    }
    private func setName(_ raw: String) {
        guard let what = selected, let c = collection(what.collection) else { return }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch what {
        case .collection(let cid): SchemaTrial.changeCollection(cid) { $0.name = name }
        case .tier(let cid): SchemaTrial.changeCollection(cid) { $0.folderName = name }
        case .folder(let cid, let fid): SchemaTrial.changeCollection(cid) { col in if let i = col.folders.firstIndex(where: { $0.id == fid }) { col.folders[i].name = name } }
        case .node(let cid, let nid, _): keep(cid, SchemaTrial.changing(nid, in: c.stack) { $0.name = name })
        case .member(_, let pid):
            guard name != lib.project(pid)?.name else { return }
            library?.apply("Rename Project") { _ = $0.renameProject(pid, to: name) }
        case .instance(_, let pid, let nid, _): shape(pid) { SchemaTrial.changing(nid, in: $0) { $0.name = name } }
        }
        all = SchemaTrial.collections
    }
    @objc private func nameEntered() { window?.makeFirstResponder(self) }
    /// Typing only keeps a draft, drawn on the map as it goes; nothing is written until the typing ends, since a write rebuilds the window.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === nameField { draft = field.stringValue; map.needsDisplay = true }
    }
    func textDidEndEditing(_ notification: Notification) { describe(about.string); show() }
    func textDidBeginEditing(_ notification: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let what = selected, collection(what.collection) != nil else { return }
        if field === nameField {
            draft = nil
            setName(field.stringValue)
        }
        show()
    }
    private func describe(_ text: String) {
        guard let what = selected, let c = collection(what.collection) else { return }
        do {
            switch what {
            case .collection(let cid): SchemaTrial.changeCollection(cid) { $0.about = text }
            case .node(let cid, let nid, _): keep(cid, SchemaTrial.changing(nid, in: c.stack) { $0.about = text })
            case .instance(_, let pid, let nid, _): shape(pid) { SchemaTrial.changing(nid, in: $0) { $0.about = text } }
            case .member(_, let pid):
                var details = lib.project(pid)?.details ?? [:]
                details[ProjectField.notes.rawValue] = text
                library?.apply("Describe Project") { $0.setProjectDetails(pid, details) }
            case .tier, .folder: break
            }
            all = SchemaTrial.collections
        }
    }
}

/// A drawing surface inside a scroll view that hands everything to its owner: what to draw, and where the pointer went.
final class Canvas: NSView {
    var onDraw: (() -> Void)?
    var onDown: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onUp: (() -> Void)?
    /// The pointer's place while it moves over the canvas, or nil when it leaves.
    var onMove: ((NSPoint?) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { onDraw?() }
    override func mouseDown(with event: NSEvent) { onDown?(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { onDrag?(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { onUp?() }
    override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { onMove?(nil) }
}
