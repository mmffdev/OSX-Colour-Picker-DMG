import AppKit

// ---------- Settings ▸ Schema, on the Studio window ----------
//
// The old Schema panel's mechanics, drawn the Studio way. The head: which collection, which stack
// (Default, or one member's own), New Collection and New Member under each, Use Default while a
// member has a stack of its own. The left column is the map: the collection at level 0, the level
// that groups its members when there is one, then the stack, the member at the next level and its
// groups beneath, each row with what it holds; a click selects a row, and the selected row carries
// what can be done with it: Add Inside, Add After, Remove, a level beneath, the collection or the
// level away. A group is dragged among the rows that share its parent. Under the map, the next group
// at the selected level. The right column is the selected row: its level, a word of help, the names
// on offer with the chosen one marked, a box for a name of your own, and a description. A group that
// holds things cannot simply go: the window's own panel asks what becomes of them.

final class SchemaSettings: NSView, NSTextFieldDelegate, Overlay {
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?

    // MARK: State, as the old panel kept it

    private enum Target { case collection, tier, member(UUID), node(SchemaNode, Int) }
    private var collectionID = SchemaTrial.firstCollection
    /// The project whose own stack is showing; nil is the collection's default.
    private var stack: UUID?
    private var root = SchemaTrial.saved
    private var selected: UUID?
    private static let tierRow = UUID(uuidString: "C0110000-0000-4000-8000-0000000000F1") ?? UUID()
    private var renaming = false
    private var all: [SchemaCollection] = SchemaTrial.collections

    private var lib: Library { library?.library ?? Library() }
    private var collection: SchemaCollection { all.first { $0.id == collectionID } ?? all[0] }
    private var member: String { SchemaTrial.memberName(of: collection) }
    private var offset: Int { collection.folderName == nil ? 0 : 1 }
    private var members: [Project] {
        let places = SchemaTrial.places
        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == collectionID }
    }
    private var current: (node: SchemaNode, level: Int)? { SchemaTrial.rows(of: root).first { $0.node.id == selected } }
    private var target: Target? {
        if selected == collectionID { return .collection }
        if selected == Self.tierRow { return collection.folderName == nil ? nil : .tier }
        guard let (node, level) = current else { return nil }
        if level == 1, let project = stack { return .member(project) }
        return .node(node, level)
    }
    private var holders: [UUID] { stack.map { [$0] } ?? members.map { $0.id }.filter { !SchemaTrial.hasOwn($0) } }

    // MARK: The views

    private let useDefault = SwissButton("Use Default", .quiet)
    private let addNext = SwissButton("Add", .secondary)
    private let removeMember = SwissButton("Remove", .quiet)
    private let customName = NSTextField(string: "")
    private let about = NSTextField(string: "")
    /// The head's lists, dropped under Collection or Stack; through the one overlay handler.
    private var dropped: SwissDropdown.MenuPanel?
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }

    /// One row of the map, as the drawing lays it out.
    private struct MapRow { let id: UUID; let text: String; let level: Int; let holds: String?; let strong: Bool; let node: SchemaNode?; let does: [(String, Int, () -> Void)] }
    private var mapRows: [MapRow] = []
    private var rowRects: [NSRect] = []
    private var doHits: [(NSRect, () -> Void)] = []
    private var nameHits: [(NSRect, String?)] = []
    private var headHits: [(NSRect, Int)] = []
    /// A group being dragged among its siblings, and the slot the pointer is over.
    private var dragging: UUID?
    private var dragSlot: Int?
    private var dragStart: NSPoint?

    /// Master Inner: the unit and the line text sits on in it; the page's six columns within its width.
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private static let step: CGFloat = 16, helpUnits: CGFloat = 3

    init() {
        super.init(frame: .zero)
        useDefault.target = self; useDefault.action = #selector(resetTapped)
        addNext.target = self; addNext.action = #selector(addNextTapped)
        removeMember.target = self; removeMember.action = #selector(removeMemberTapped)
        for f in [customName, about] {
            f.isBordered = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = Design.Text.body.font()
            f.textColor = Design.ink
            f.delegate = self
            f.isHidden = true
        }
        customName.placeholderAttributedString = Design.attributed("Type a name", .body, colour: Design.soft)
        about.placeholderAttributedString = Design.attributed("What this holds", .body, colour: Design.soft)
        customName.target = self; customName.action = #selector(nameEntered)
        for v in [useDefault, addNext, removeMember, customName, about] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        load()
        if selected == nil || target == nil { selected = collectionID }
        refresh()
    }
    private func refresh() { needsLayout = true; needsDisplay = true; onResize?() }

    private func load() {
        all = SchemaTrial.collections
        if !all.contains(where: { $0.id == collectionID }) { collectionID = all[0].id; stack = nil }
        if let id = stack, !members.contains(where: { $0.id == id }) { stack = nil }
        root = stack.map { SchemaTrial.schema(for: $0) } ?? collection.stack
    }
    private func keep() {
        if let id = stack { SchemaTrial.setSchema(root, for: id) } else { let tree = root; SchemaTrial.changeCollection(collectionID) { $0.stack = tree } }
        all = SchemaTrial.collections
    }
    private func show() { load(); if target == nil { selected = collectionID }; refresh(); onChange?() }

    // MARK: The head: Collection and Stack, each a list dropped under its hairline

    private var collectionNames: [String] { all.map { $0.name.isEmpty ? "Unnamed" : $0.name } + ["New Collection\u{2026}"] }
    private var stackNames: [String] { ["Default"] + members.map { $0.name + (SchemaTrial.hasOwn($0.id) ? "  \u{25A0}" : "") } + ["New \(member)\u{2026}"] }
    private var stackNow: String { stack.flatMap { id in members.firstIndex { $0.id == id } }.map { stackNames[$0 + 1] } ?? "Default" }

    private func dropList(_ which: Int, under r: NSRect) {
        guard let win = window else { return }
        closeMenu()
        let items = which == 0 ? collectionNames : stackNames
        let panel = SwissDropdown.MenuPanel(items: items, chosen: which == 0 ? collection.name : stackNow, width: r.width) { [weak self] i in
            guard let self = self else { return }
            self.closeMenu()
            if which == 0 { self.collectionChosen(i) } else { self.stackChosen(i) }
        }
        let origin = win.convertToScreen(convert(NSRect(x: r.minX, y: r.maxY, width: 1, height: 1), to: nil)).origin
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

    private func collectionChosen(_ i: Int) {
        if i == all.count {
            SwissConfirm.name(over: window, title: "New Collection", note: "A heading in rail1 of its own, starting with the stack of \(collection.name.isEmpty ? "this collection" : collection.name).",
                              placeholder: "Clients, Our Own Work, Archive", confirm: "Create Collection", check: { ProjectField.problem(name: $0, values: [:], naming: "collection") }) { [weak self] name in
                guard let self = self else { return }
                let made = SchemaCollection(name: name, stack: self.collection.stack)
                SchemaTrial.collections = self.all + [made]
                self.collectionID = made.id; self.stack = nil
                self.selected = self.collectionID
                self.show()
            }
            return
        }
        guard all.indices.contains(i) else { return }
        collectionID = all[i].id; stack = nil
        load(); selected = collectionID; show()
    }

    private func stackChosen(_ i: Int) {
        let inside = members
        if i == inside.count + 1 {
            SwissConfirm.name(over: window, title: "New \(member)", note: "A \(member.lowercased()) in \(collection.name), a project with files of its own, with a stack of its own to shape here.",
                              placeholder: "Client, product or piece of work", confirm: "Create \(member)", check: { ProjectField.problem(name: $0, values: [:]) }) { [weak self] name in
                guard let self = self, let lib = self.library else { return }
                var made: UUID?
                lib.apply("New Project") { l in
                    let id = l.createProject(named: name)
                    let organisation = ProjectField.tidy(Prefs.organisation)
                    if !organisation.isEmpty { l.setProjectDetails(id, organisation) }
                    made = id
                }
                guard let id = made, self.lib.project(id) != nil else { return }
                SchemaTrial.place(id, in: self.collectionID, folder: nil)
                SchemaTrial.setSchema(self.collection.stack, for: id)
                self.stack = id
                self.load(); self.selected = self.root.id; self.show()
            }
            return
        }
        stack = i == 0 ? nil : (inside.indices.contains(i - 1) ? inside[i - 1].id : nil)
        load(); selected = root.id; show()
    }

    @objc private func resetTapped() {
        guard let id = stack else { return }
        SchemaTrial.setSchema(nil, for: id)
        load(); selected = root.id; show()
    }

    // MARK: The map's rows

    private func palettes(_ role: SchemaRole, in project: UUID) -> [UUID] { lib.palettes(in: project).filter { $0.isTypography == (role == .typography) }.map { $0.id } }
    private func tags(in project: UUID) -> [String] { lib.allTags.filter { lib.project(ofTag: $0) == project } }
    private func count(_ node: SchemaNode, level: Int) -> Int {
        guard level == 2, let role = SchemaTrial.role(of: node) else { return 0 }
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

    private func buildMap() -> [MapRow] {
        let here = collection, inside = members
        var out: [MapRow] = []
        var does: [(String, Int, () -> Void)] = []
        if here.folderName == nil { does.append(("Add Level Beneath", 5, { [weak self] in self?.addTier() })) }
        if here.id != all[0].id { does.append(("Remove Collection", 2, { [weak self] in self?.removeCollection() })) }
        out.append(MapRow(id: collectionID, text: here.name.isEmpty ? "Unnamed" : here.name, level: 0,
                          holds: inside.isEmpty ? nil : "\(inside.count) " + (inside.count == 1 ? member : SchemaTrial.plural(member)).lowercased(), strong: true, node: nil, does: does))
        if let tier = here.folderName {
            out.append(MapRow(id: Self.tierRow, text: tier, level: 1, holds: here.folders.isEmpty ? nil : "\(here.folders.count) made", strong: false, node: nil,
                              does: [("Remove Level", 2, { [weak self] in self?.removeTier() })]))
        }
        let projectName = stack.flatMap { lib.project($0)?.name }
        for (node, level) in SchemaTrial.rows(of: root) {
            let n = count(node, level: level)
            var does: [(String, Int, () -> Void)] = [("Add Inside", 5, { [weak self] in self?.add(child: true, at: node.id) })]
            if level > 1 {
                does.append(("Add After", 4, { [weak self] in self?.add(child: false, at: node.id) }))
                does.append(("Remove", 2, { [weak self] in self?.remove(node, level: level) }))
            }
            out.append(MapRow(id: node.id, text: level == 1 ? projectName ?? node.name : node.name, level: level + offset,
                              holds: n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil, strong: level == 1, node: node, does: does))
        }
        return out
    }

    // MARK: Geometry: one walk, on the page's six columns and the unit, gives the drawing, the hits and the fields their places

    private struct Geometry {
        var cw: CGFloat = 0, g: CGFloat = 0
        var collection = NSRect.zero, stackBox = NSRect.zero, useDefault = NSRect.zero
        var left = NSRect.zero, right = NSRect.zero
        var mapTop: CGFloat = 0, mapRows: [NSRect] = []
        var addNext: CGFloat = 0
        var nameLabel: CGFloat = 0, names: [NSRect] = [], customLabel: CGFloat = 0, customName = NSRect.zero, aboutLabel: CGFloat = 0, about = NSRect.zero
        var height: CGFloat = 0
        var leftHelp = "", rightHelp = "", levelTitle = "", offered: [String] = [], name = "", said: String?, custom = false, fixed = false
    }

    private func geometry(width w: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u, gut = Design.App.gutter
        g.g = gut; g.cw = ((w - 5 * gut) / 6).rounded(.down)
        let cw = g.cw
        func col(_ i: Int) -> CGFloat { CGFloat(i - 1) * (cw + gut) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * cw + CGFloat(n - 1) * gut }
        // The head: rows 0 and 1. Collection on columns 1 and 2, Stack on 4 and 5, Use Default on 6.
        g.collection = NSRect(x: col(1), y: 0, width: span(2), height: 2 * u)
        g.stackBox = NSRect(x: col(4), y: 0, width: span(2), height: 2 * u)
        g.useDefault = NSRect(x: col(6), y: 0, width: cw, height: 2 * u)
        // The two columns of the page under the head: the map on columns 1 to 4, the row on 5 and 6; headers on row 3, words on rows 4 to 6, content from row 7.
        let lw = span(4), rx = col(5), rw = span(2)
        let here = collection, inside = members, heading = here.name.isEmpty ? "this collection" : here.name
        let own = stack.map { SchemaTrial.hasOwn($0) } ?? false
        let following = inside.filter { !SchemaTrial.hasOwn($0.id) }.count
        var words: String
        if let project = stack.flatMap({ lib.project($0) }) {
            words = "\(heading), on \(project.name)'s own stack. " + (own ? "It follows nothing: what is built below is its alone. Use Default puts it back with the others." : "It follows Default. Change anything below and it takes a stack of its own.")
        } else {
            words = "\(heading)'s Default stack: what every member follows unless it has a stack of its own. \(following) of \(inside.count) follow it. Choose a member under Stack to shape it on its own, or another collection under Collection."
        }
        g.leftHelp = words
        var y = 7 * u
        g.mapTop = y
        mapRows = buildMap()
        for _ in mapRows { g.mapRows.append(NSRect(x: 0, y: y, width: lw, height: u)); y += u }
        g.addNext = y + u
        g.left = NSRect(x: 0, y: 3 * u, width: lw, height: g.addNext + 2 * u - 3 * u)

        var ry = 7 * u
        if let what = target {
            let memberWord = member.lowercased(), many = SchemaTrial.plural(member).lowercased()
            switch what {
            case .collection:
                g.levelTitle = SchemaTrial.title(forLevel: 0); g.name = here.name; g.offered = SchemaTrial.collectionNames; g.said = here.about
                g.rightHelp = "Its name heads rail1; the description says what it is for. " + (here.folderName == nil ? "Its \(many) sit straight under it; Add Level Beneath groups them." : "Its \(many) are grouped under the level on the next row.")
            case .tier:
                g.levelTitle = SchemaTrial.title(forLevel: 1); g.name = here.folderName ?? ""; g.offered = SchemaTrial.folderNames
                g.rightHelp = "The level that groups the \(many) of \(heading). Name what one of them is; each is made in rail1 with its \(many) inside."
            case .member(let project):
                g.levelTitle = SchemaTrial.title(forLevel: 1 + offset); g.name = lib.project(project)?.name ?? ""; g.fixed = true; g.said = root.about
                g.rightHelp = "One \(memberWord) in \(heading). Type over its name and press Return to rename it. The groups below are its own."
            case .node(let node, let level):
                g.levelTitle = SchemaTrial.title(forLevel: level + offset); g.name = node.name; g.offered = SchemaTrial.names(forLevel: level); g.said = node.about
                g.rightHelp = level == 1 ? "What a \(memberWord) of \(heading) is called. Every \(memberWord) is a project of the app's, with files of its own."
                    : level == 2 ? "A group in every \(memberWord) of \(heading). Information, Palettes, Typography and Tags hold what they always have; any other group is a label for now."
                    : "A group \(level - 1) levels inside every \(memberWord) of \(heading). Groups this deep are labels for now."
            }
            g.custom = g.fixed || renaming || !g.offered.contains(g.name)
            g.nameLabel = ry; ry += u
            let count = g.fixed ? 0 : g.offered.count + 1
            for _ in 0..<count { g.names.append(NSRect(x: rx, y: ry, width: rw, height: u)); ry += u }
            if g.custom {
                ry += u
                g.customLabel = ry; ry += u
                g.customName = NSRect(x: rx, y: ry, width: rw, height: u); ry += u
            }
            if g.said != nil {
                ry += u
                g.aboutLabel = ry; ry += u
                g.about = NSRect(x: rx, y: ry, width: rw, height: u); ry += u
            }
        }
        g.right = NSRect(x: rx, y: 3 * u, width: rw, height: ry - 3 * u)
        g.height = max(g.left.maxY, g.right.maxY) + u + 4 * u
        return g
    }

    func height(forWidth width: CGFloat) -> CGFloat { geometry(width: max(width, 1)).height }

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width), u = Self.u, line = Self.line
        // Buttons hang their words on the row's line: a 32 button's text sits 22 below its top.
        useDefault.frame = NSRect(x: g.useDefault.minX, y: u + line - 22, width: useDefault.intrinsicContentSize.width, height: 32)
        useDefault.isHidden = !(stack.map { SchemaTrial.hasOwn($0) } ?? false)
        var next: String?
        if case .node(_, let level)? = target { next = level == 1 ? "Add \(SchemaTrial.title(forLevel: 2 + offset))" : "Add Next Level \(level + offset) Group" }
        if case .member? = target { next = "Add \(SchemaTrial.title(forLevel: 2 + offset))" }
        addNext.isHidden = next == nil
        if let n = next, addNext.title != n { addNext.title = n; addNext.invalidateIntrinsicContentSize() }
        addNext.frame = NSRect(x: g.left.maxX - addNext.intrinsicContentSize.width, y: g.addNext + line - 22, width: addNext.intrinsicContentSize.width, height: 32)
        if let project = stack, let name = lib.project(project)?.name {
            removeMember.isHidden = false
            let t = "Remove \(name)\u{2026}"
            if removeMember.title != t { removeMember.title = t; removeMember.invalidateIntrinsicContentSize() }
            removeMember.frame = NSRect(x: 0, y: g.addNext + line - 22, width: removeMember.intrinsicContentSize.width, height: 32)
        } else { removeMember.isHidden = true }
        // The fields: their text on the row's line, which for a 13 field is 15 below its top.
        customName.isHidden = !g.custom
        customName.frame = NSRect(x: g.customName.minX, y: g.customName.minY + line - 15, width: g.customName.width, height: 20)
        if customName.currentEditor() == nil { customName.stringValue = g.custom ? g.name : "" }
        about.isHidden = g.said == nil
        about.frame = NSRect(x: g.about.minX, y: g.about.minY + line - 15, width: g.about.width, height: 20)
        if about.currentEditor() == nil { about.stringValue = g.said ?? "" }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width), u = Self.u, line = Self.line
        rowRects = g.mapRows; doHits = []; nameHits = []; headHits = []
        // The head: a first-order caption on the first line, the value at 17 on the second, a chevron, a hairline under both.
        for (i, (cap, value, box)) in [("Collection", collection.name.isEmpty ? "Unnamed" : collection.name, g.collection), ("Stack", stackNow, g.stackBox)].enumerated() {
            Design.attributed(cap, .body).draw(x: box.minX, baseline: line)
            let v = Design.attributed(value, .headline, size: 17)
            v.draw(x: box.minX, baseline: u + line, width: box.width - 24)
            Design.attributed(dropped != nil && headHits.count == i ? "\u{25B4}" : "\u{25BE}", .caption, colour: Design.quiet).draw(x: box.minX + min(v.size().width, box.width - 24) + 8, baseline: u + line)
            hairline(x: box.minX, y: 2 * u - 1, width: box.width, Design.rule)
            headHits.append((NSRect(x: box.minX, y: u, width: box.width, height: u), i))
        }
        // The two headers on one line, row 3; the words in a box of three units under each; nothing below them moves.
        Design.attributed("Structure", .body).draw(x: 0, baseline: 3 * u + line)
        Design.attributed(g.leftHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: 0, y: 4 * u, width: g.left.width, height: Self.helpUnits * u))
        hairline(x: 0, y: g.mapTop - 1, width: g.left.width, Design.rule)
        for (i, r) in mapRows.enumerated() {
            let box = g.mapRows[i], b = box.minY + line
            let on = r.id == selected
            if on { fill(box, Design.mist) }
            let x = CGFloat(r.level) * Self.step
            Design.attributed("\(r.level)", .caption, colour: Design.soft).draw(x: x, baseline: b)
            let name = Design.attributed(r.text, on || r.strong ? .bodyStrong : .body, colour: on || r.strong ? Design.ink : Design.quiet)
            var right = box.maxX
            if on {
                for (title, glyph, run) in r.does.reversed() {
                    let t = Design.attributed(title, .caption, colour: Design.quiet)
                    right -= t.size().width
                    t.draw(x: right, baseline: b)
                    icon(glyph, at: NSPoint(x: right - 14, y: b - 9))
                    doHits.append((NSRect(x: right - 20, y: box.minY, width: t.size().width + 24, height: box.height), run))
                    right -= 32
                }
            } else if let holds = r.holds {
                let t = Design.attributed(holds, .caption, colour: Design.quiet)
                t.draw(right: right, baseline: b)
                right -= t.size().width + 12
            }
            name.draw(x: x + 20, baseline: b, width: right - x - 20)
            hairline(x: 0, y: box.maxY - 1, width: box.width, Design.mist)
        }
        if let slot = dragSlot, let d = dragging, let i = mapRows.firstIndex(where: { $0.id == d }) {
            let y = slotY(slot, among: siblings(of: d), draggedLevel: mapRows[i].level)
            fill(NSRect(x: CGFloat(mapRows[i].level) * Self.step, y: y - 1, width: g.left.width - CGFloat(mapRows[i].level) * Self.step, height: 2), Design.ink)
        }
        guard target != nil else { return }
        let rx = g.right.minX
        Design.attributed(g.levelTitle, .body).draw(x: rx, baseline: 3 * u + line)
        Design.attributed(g.rightHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: 4 * u, width: g.right.width, height: Self.helpUnits * u))
        Design.attributed("Name", .label, colour: Design.quiet).draw(x: rx, baseline: g.nameLabel + line)
        if !g.fixed {
            let list = ["Custom Name\u{2026}"] + g.offered
            for (i, n) in list.enumerated() {
                let box = g.names[i], b = box.minY + line
                let chosen = i == 0 ? g.custom : (!g.custom && n == g.name)
                let sq = NSRect(x: box.minX, y: b - 10, width: 12, height: 12)
                fill(sq, chosen ? Design.ink : Design.card)
                Design.ink.setStroke()
                let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                Design.attributed(n, .body, colour: chosen ? Design.ink : Design.quiet).draw(x: box.minX + 24, baseline: b, width: box.width - 24)
                nameHits.append((box, i == 0 ? nil : n))
            }
        }
        if g.custom {
            Design.attributed(g.fixed ? "Name" : "Custom Name", .label, colour: Design.quiet).draw(x: rx, baseline: g.customLabel + line)
            hairline(x: rx, y: g.customName.maxY - 1, width: g.right.width, customName.currentEditor() != nil ? Design.ink : Design.rule)
        }
        if g.said != nil {
            Design.attributed("Description", .label, colour: Design.quiet).draw(x: rx, baseline: g.aboutLabel + line)
            hairline(x: rx, y: g.about.maxY - 1, width: g.right.width, about.currentEditor() != nil ? Design.ink : Design.rule)
        }
        Design.attributed("A collection is a heading in rail1. Its members are the app's projects, grouped under a level between when you add one, and each follows the collection's Default stack: the groups inside a member, four filled by the app, any other a label of your own. Choose a member under Stack to give it a stack of its own.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: g.height - 4 * u, width: min(bounds.width, 560), height: 3 * u))
    }

    private func icon(_ which: Int, at p: NSPoint) {
        Design.quiet.setStroke()
        let s: CGFloat = 9, path = NSBezierPath()
        path.lineWidth = 1.2
        switch which {
        case 2:
            path.move(to: NSPoint(x: p.x + 1, y: p.y + 1)); path.line(to: NSPoint(x: p.x + s, y: p.y + s))
            path.move(to: NSPoint(x: p.x + s, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 1, y: p.y + s))
        case 4:
            path.move(to: NSPoint(x: p.x, y: p.y + 5)); path.line(to: NSPoint(x: p.x + s, y: p.y + 5))
            path.move(to: NSPoint(x: p.x + 5, y: p.y)); path.line(to: NSPoint(x: p.x + 5, y: p.y + s))
        default:
            path.move(to: NSPoint(x: p.x + 1, y: p.y)); path.line(to: NSPoint(x: p.x + 1, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6))
            path.move(to: NSPoint(x: p.x + s - 3, y: p.y + 3)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s - 3, y: p.y + 9))
        }
        path.stroke()
    }

    // MARK: The pointer: select, act, choose a name, drop a list, drag a group among its siblings

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if let h = headHits.first(where: { $0.0.contains(p) }) { dropList(h.1, under: h.0); return }
        if let d = doHits.first(where: { $0.0.contains(p) }) { d.1(); return }
        if let n = nameHits.first(where: { $0.0.contains(p) }) { choose(name: n.1); return }
        if let i = rowRects.firstIndex(where: { $0.contains(p) }) {
            let r = mapRows[i]
            selected = r.id
            renaming = false
            if let node = r.node, let level = SchemaTrial.rows(of: root).first(where: { $0.node.id == node.id })?.level, level > 1 { dragging = node.id; dragStart = p } else { dragging = nil }
            refresh()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging, let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard abs(p.y - start.y) > 4 || dragSlot != nil else { return }
        let sibs = siblings(of: d)
        var slot = sibs.count
        for (k, s) in sibs.enumerated() {
            if let i = mapRows.firstIndex(where: { $0.id == s }), p.y < rowRects[i].midY { slot = k; break }
        }
        if slot != dragSlot { dragSlot = slot; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        if let d = dragging, let slot = dragSlot {
            root = SchemaTrial.moving(d, to: slot, in: root)
            selected = d
            keep()
            show()
        }
        dragging = nil; dragSlot = nil; dragStart = nil
        needsDisplay = true
    }
    private func siblings(of id: UUID) -> [UUID] {
        for (node, _) in SchemaTrial.rows(of: root) where node.children.contains(where: { $0.id == id }) { return node.children.map { $0.id } }
        return []
    }
    private func slotY(_ slot: Int, among sibs: [UUID], draggedLevel: Int) -> CGFloat {
        if slot < sibs.count, let i = mapRows.firstIndex(where: { $0.id == sibs[slot] }) { return rowRects[i].minY }
        if let last = sibs.last, let i = mapRows.firstIndex(where: { $0.id == last }) {
            var end = i
            while end + 1 < mapRows.count && mapRows[end + 1].level > mapRows[i].level { end += 1 }
            return rowRects[end].maxY
        }
        return 0
    }

    // MARK: Adding, removing, moving

    private func add(child: Bool, at id: UUID) {
        let result = child ? SchemaTrial.addingChild(to: id, in: root) : SchemaTrial.addingSibling(after: id, in: root)
        root = result.tree
        if let made = result.added { selected = made }
        keep(); show()
    }
    @objc private func addNextTapped() {
        guard let (node, level) = current else { return }
        add(child: level == 1, at: node.id)
    }
    @objc private func removeMemberTapped() {
        guard let project = stack, let lib = library else { return }
        lib.dump(project: project, over: window) { [weak self] in
            guard let self = self else { return }
            self.stack = nil; self.load(); self.selected = self.collectionID; self.show()
        }
    }

    /// The bin on a group: gone at once when it holds nothing; asked about on the window's panel when it holds something.
    private func remove(_ node: SchemaNode, level: Int) {
        let n = count(node, level: level)
        guard n == 0 else { selected = node.id; refresh(); askAboutContents(of: node, level: level, holding: n); return }
        root = SchemaTrial.removing(node.id, from: root)
        keep(); show()
    }

    private func askAboutContents(of node: SchemaNode, level: Int, holding n: Int) {
        let role = SchemaTrial.role(of: node), things = "\(n) \(noun(role, n))"
        let keepWord = "Keep the \(noun(role, n)) and rename the group"
        guard let project = stack else {
            let note = "Its \(things) are spread over the \(holders.count) that follow Default, and would be left with nowhere to show. On Default the group can be renamed and they stay where they are. To delete them, choose each member under Stack and remove the group there."
            SwissConfirm.ask(over: window, title: "\(node.name) Holds \(things.prefix(1).uppercased() + things.dropFirst())", note: note, commit: "Go On", options: [keepWord]) { [weak self] _ in self?.keepAndRename() }
            return
        }
        let name = lib.project(project)?.name ?? ""
        var note = "A group that holds things cannot simply go: they would still be in \(name), with nowhere to show. Keep them and give the group another name, or delete the \(things) and remove the group. "
        note += role == .tags ? "A deleted tag comes off everything that carries it." : "A deleted palette leaves its colours in the catalogue, and the deletion is a step in History."
        if lib.project(project)?.isLocked == true { note += " \(name) is locked, so nothing in it can be deleted until it is unlocked." }
        SwissConfirm.ask(over: window, title: "\(node.name) Holds \(things.prefix(1).uppercased() + things.dropFirst())", note: note + " This cannot be undone.", commit: "Go On",
                         options: [keepWord, "Delete the \(noun(role, n)) and remove the group"]) { [weak self] choice in
            if choice == 0 { self?.keepAndRename() } else { self?.deleteAndRemove(node) }
        }
    }
    private func keepAndRename() {
        guard let id = selected else { return }
        root = SchemaTrial.changing(id, in: root) { $0.role = SchemaTrial.role(of: $0) }
        keep()
        renaming = true
        show()
        window?.makeFirstResponder(customName)
        customName.currentEditor()?.selectAll(nil)
    }
    private func deleteAndRemove(_ node: SchemaNode) {
        guard let project = stack, let role = SchemaTrial.role(of: node), let lib = library else { return }
        lib.erase(role: role, of: project)
        guard count(node, level: 2) == 0 else { show(); return }
        root = SchemaTrial.removing(node.id, from: root)
        keep(); show()
    }

    private func addTier() {
        SchemaTrial.changeCollection(collectionID) { $0.folderName = SchemaTrial.folderNames[0] }
        all = SchemaTrial.collections
        selected = Self.tierRow
        show()
    }
    private func removeTier() {
        SchemaTrial.changeCollection(collectionID) { $0.folderName = nil; $0.folders = [] }
        all = SchemaTrial.collections
        selected = collectionID
        show()
    }
    private func removeCollection() {
        guard collectionID != all[0].id, let lib = library else { return }
        lib.dump(collection: collectionID, over: window) { [weak self] in
            guard let self = self else { return }
            self.collectionID = SchemaTrial.firstCollection; self.stack = nil
            self.load(); self.selected = self.collectionID; self.show()
        }
    }

    // MARK: Names

    private func setName(_ name: String, done: Bool) {
        guard let what = target else { return }
        switch what {
        case .collection: SchemaTrial.changeCollection(collectionID) { $0.name = name }; all = SchemaTrial.collections
        case .tier: SchemaTrial.changeCollection(collectionID) { $0.folderName = name }; all = SchemaTrial.collections
        case .member(let project):
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard done, !typed.isEmpty, typed != lib.project(project)?.name else { return }
            library?.apply("Rename Project") { _ = $0.renameProject(project, to: typed) }
        case .node(let node, _):
            root = SchemaTrial.changing(node.id, in: root) { $0.role = SchemaTrial.role(of: $0); $0.name = name }
            keep()
        }
    }
    private func choose(name: String?) {
        guard let what = target else { return }
        if name == nil {
            let now: String, offered: [String]
            switch what {
            case .collection: now = collection.name; offered = SchemaTrial.collectionNames
            case .tier: now = collection.folderName ?? ""; offered = SchemaTrial.folderNames
            case .member: return
            case .node(let node, let level): now = node.name; offered = SchemaTrial.names(forLevel: level)
            }
            if !offered.contains(now) { window?.makeFirstResponder(customName); return }
            renaming = true
            show()
            window?.makeFirstResponder(customName)
            return
        }
        window?.makeFirstResponder(self)
        renaming = false
        setName(name ?? "", done: true)
        show()
    }
    @objc private func nameEntered() { window?.makeFirstResponder(self) }
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === customName {
            if case .member? = target { return }
            setName(field.stringValue, done: false)
            load(); onChange?()
        } else if field === about, let what = target {
            let text = field.stringValue
            switch what {
            case .collection: SchemaTrial.changeCollection(collectionID) { $0.about = text }; all = SchemaTrial.collections
            case .tier: break
            case .member: root.about = text; keep()
            case .node(let node, _): root = SchemaTrial.changing(node.id, in: root) { $0.about = text }; keep()
            }
        }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === customName else { needsDisplay = true; return }
        setName(field.stringValue, done: true)
        renaming = false
        load(); refresh(); onChange?()
    }
}
