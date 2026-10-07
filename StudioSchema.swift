import AppKit

// ---------- Settings ▸ Schema, on the Studio window ----------
//
// One tree of everything, on Master Inner. The left column is the map: every collection at level
// 0, the level that groups its members when there is one, then its stack, the member at the next
// level and its groups beneath, each row with what it holds. A click selects a row, and the
// selected row carries what can be done with it: Add Sibling on every level (another collection,
// another folder, another member, another group), Add Inside, Remove, Add Level Beneath. A group is
// dragged among the rows that share its parent. The right column is the selected row: its level, a
// word of help in a box that never grows, the names on offer with the chosen one marked, a box for a
// name of your own, and a description. A group that holds things cannot simply go: the window's
// own panel asks.

final class SchemaSettings: NSView, NSTextFieldDelegate {
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    /// The page's edge to its first column: the view starts at the rail's divider so a row's ground can reach it, and the words start here.
    var leading: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    // MARK: State

    /// What a row on the map is: a collection, the level grouping its members, or a group in its stack with its level in the stack, the member being 1.
    private enum Target: Hashable {
        case collection(UUID), tier(UUID), node(UUID, UUID, Int)
        var collection: UUID { switch self { case .collection(let c), .tier(let c), .node(let c, _, _): return c } }
    }
    private var all: [SchemaCollection] = SchemaTrial.collections
    private var selected: Target?
    private var renaming = false
    private var lib: Library { library?.library ?? Library() }

    private func collection(_ id: UUID) -> SchemaCollection? { all.first { $0.id == id } }
    private func member(_ c: SchemaCollection) -> String { SchemaTrial.memberName(of: c) }
    private func offset(_ c: SchemaCollection) -> Int { c.folderName == nil ? 0 : 1 }
    private func members(of c: SchemaCollection) -> [Project] {
        let places = SchemaTrial.places
        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == c.id }
    }

    // MARK: The views

    private let customName = NSTextField(string: "")
    private let about = NSTextField(string: "")

    /// One row of the map, as the drawing lays it out.
    private struct MapRow { let target: Target; let text: String; let level: Int; let holds: String?; let strong: Bool; let does: [(String, Int, () -> Void)] }
    private var mapRows: [MapRow] = []
    private var rowRects: [NSRect] = []
    private var gripRects: [NSRect] = []
    private var doHits: [(NSRect, () -> Void)] = []
    private var nameHits: [(NSRect, String?)] = []
    /// The rollover: the row under the pointer, and how far each row's orange pane has flown out, 0 to 1, driven by the clock.
    /// A selected row's pane stays out; a click on a row already under the pointer changes nothing, so it cannot flick.
    private var hoverRow: Target?
    private var reveal: [Target: CGFloat] = [:]
    private var clock: Timer?
    private var lastTick = Date()
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
        for v in [customName, about] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: The rollover's clock

    /// Where a row's pane should be: out for the row under the pointer and the selected one, home for the rest.
    private func goal(_ t: Target) -> CGFloat { t == hoverRow || t == selected ? 1 : 0 }
    /// Starts the clock if any pane is away from where it should be; it stops itself when every pane has arrived.
    private func settle() {
        let moving = mapRows.contains { (reveal[$0.target] ?? 0) != goal($0.target) }
        guard moving, clock == nil else { return }
        lastTick = Date()
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 90, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            // Fast: the whole flight in a tenth of a second, so the wave follows the pointer without lag.
            let now = Date(), step = CGFloat(now.timeIntervalSince(self.lastTick) / 0.1)
            self.lastTick = now
            var done = true
            for r in self.mapRows {
                let g = self.goal(r.target), v = self.reveal[r.target] ?? 0
                if v == g { continue }
                let next = v < g ? min(g, v + step) : max(g, v - step)
                self.reveal[r.target] = next
                if next != g { done = false }
            }
            self.reveal = self.reveal.filter { $0.value > 0 }
            self.needsDisplay = true
            if done { t.invalidate(); self.clock = nil }
        }
        RunLoop.main.add(clock!, forMode: .common)
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = rowRects.firstIndex { $0.contains(p) }.map { mapRows[$0].target }
        if over != hoverRow { hoverRow = over; settle() }
    }
    override func mouseExited(with event: NSEvent) { if hoverRow != nil { hoverRow = nil; settle() } }
    override var isFlipped: Bool { true }

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
        case .node(_, let n, _): return SchemaTrial.rows(of: c.stack).contains { $0.node.id == n }
        }
    }
    private func refresh() { needsLayout = true; needsDisplay = true; onResize?() }
    private func show() { all = SchemaTrial.collections; if selected == nil || !stillThere(selected!) { selected = .collection(all[0].id) }; refresh(); onChange?() }
    private func keep(_ c: UUID, _ tree: SchemaNode) { SchemaTrial.changeCollection(c) { $0.stack = tree }; all = SchemaTrial.collections }

    // MARK: What a group holds

    private func palettes(_ role: SchemaRole, in project: UUID) -> [UUID] { lib.palettes(in: project).filter { $0.isTypography == (role == .typography) }.map { $0.id } }
    private func tags(in project: UUID) -> [String] { lib.allTags.filter { lib.project(ofTag: $0) == project } }
    private func count(_ node: SchemaNode, level: Int, in c: SchemaCollection) -> Int {
        guard level == 2, let role = SchemaTrial.role(of: node) else { return 0 }
        let holders = members(of: c).map { $0.id }.filter { !SchemaTrial.hasOwn($0) }
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

    // MARK: The map: every collection, its grouping level, its stack

    private func buildMap() -> [MapRow] {
        var out: [MapRow] = []
        for c in all {
            let inside = members(of: c), cid = c.id
            var does: [(String, Int, () -> Void)] = [("Add Sibling", 4, { [weak self] in self?.newCollection(after: cid) })]
            if c.folderName == nil { does.append(("Add Level Beneath", 5, { [weak self] in self?.addTier(cid) })) }
            if c.id != all[0].id { does.append(("Remove", 2, { [weak self] in self?.removeCollection(cid) })) }
            out.append(MapRow(target: .collection(cid), text: c.name.isEmpty ? "Unnamed" : c.name, level: 0,
                              holds: inside.isEmpty ? nil : "\(inside.count) " + (inside.count == 1 ? member(c) : SchemaTrial.plural(member(c))).lowercased(), strong: true, does: does))
            if let tier = c.folderName {
                out.append(MapRow(target: .tier(cid), text: tier, level: 1, holds: c.folders.isEmpty ? nil : "\(c.folders.count) made", strong: false,
                                  does: [("Add Sibling", 4, { [weak self] in self?.addFolder(cid) }), ("Remove", 2, { [weak self] in self?.removeTier(cid) })]))
            }
            for (node, level) in SchemaTrial.rows(of: c.stack) {
                let n = count(node, level: level, in: c), nid = node.id
                var does: [(String, Int, () -> Void)] = []
                if level == 1 { does.append(("Add Sibling", 4, { [weak self] in self?.newMember(in: cid) })) }
                else { does.append(("Add Sibling", 4, { [weak self] in self?.add(child: false, at: nid, in: cid) })) }
                does.append(("Add Inside", 5, { [weak self] in self?.add(child: true, at: nid, in: cid) }))
                if level > 1 { does.append(("Remove", 2, { [weak self] in self?.remove(node, level: level, in: cid) })) }
                out.append(MapRow(target: .node(cid, nid, level), text: node.name, level: level + offset(c),
                                  holds: n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil, strong: level == 1, does: does))
            }
        }
        return out
    }

    // MARK: Geometry: one walk, on the page's six columns and the unit

    private struct Geometry {
        var left = NSRect.zero, right = NSRect.zero
        var mapTop: CGFloat = 0, mapRows: [NSRect] = []
        var nameLabel: CGFloat = 0, names: [NSRect] = [], customLabel: CGFloat = 0, customName = NSRect.zero, aboutLabel: CGFloat = 0, about = NSRect.zero
        var height: CGFloat = 0
        var leftHelp = "", rightHelp = "", levelTitle = "", offered: [String] = [], name = "", said: String?, custom = false
    }

    /// `w` is the width from the first column to the last; the view is `leading` wider on the left.
    private func geometry(width w: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u, gut = Design.App.gutter, l = leading
        // Both columns: a header on row 0, words on rows 1 to 3, content from row 4. The map takes 60 of the width, the selected row 40 (Rick, 2026-10-08).
        let lw = ((w - gut) * 0.6).rounded(), rx = l + lw + gut, rw = w - lw - gut
        g.leftHelp = "Every collection is a heading in rail1, with its members under it, grouped under a level between when it has one. Each member follows its collection's stack: the groups inside it. Add Sibling on any row makes another at that level; a group drags among its siblings."
        var y = 4 * u
        g.mapTop = y
        mapRows = buildMap()
        for _ in mapRows { g.mapRows.append(NSRect(x: l, y: y, width: lw, height: u)); y += u }
        g.left = NSRect(x: l, y: 0, width: lw, height: y + u)

        var ry = 4 * u
        if let what = selected, let c = collection(what.collection) {
            let heading = c.name.isEmpty ? "this collection" : c.name
            let memberWord = member(c).lowercased(), many = SchemaTrial.plural(member(c)).lowercased()
            switch what {
            case .collection:
                g.levelTitle = SchemaTrial.title(forLevel: 0); g.name = c.name; g.offered = SchemaTrial.collectionNames; g.said = c.about
                g.rightHelp = "Its name heads rail1; the description says what it is for. " + (c.folderName == nil ? "Its \(many) sit straight under it; Add Level Beneath groups them." : "Its \(many) are grouped under the level on the next row.")
            case .tier:
                g.levelTitle = SchemaTrial.title(forLevel: 1); g.name = c.folderName ?? ""; g.offered = SchemaTrial.folderNames
                g.rightHelp = "The level that groups the \(many) of \(heading). Name what one of them is; Add Sibling makes another, and each is filled in rail1."
            case .node(_, let nid, let level):
                let node = SchemaTrial.rows(of: c.stack).first { $0.node.id == nid }?.node ?? c.stack
                g.levelTitle = SchemaTrial.title(forLevel: level + offset(c)); g.name = node.name; g.offered = SchemaTrial.names(forLevel: level); g.said = node.about
                g.rightHelp = level == 1 ? "What a \(memberWord) of \(heading) is called. Every \(memberWord) is a project of the app's, with files of its own; Add Sibling makes one."
                    : level == 2 ? "A group in every \(memberWord) of \(heading). Information, Palettes, Typography and Tags hold what they always have; any other group is a label for now."
                    : "A group \(level - 1) levels inside every \(memberWord) of \(heading). Groups this deep are labels for now."
            }
            g.custom = renaming || !g.offered.contains(g.name)
            g.nameLabel = ry; ry += u
            for _ in 0..<(g.offered.count + 1) { g.names.append(NSRect(x: rx, y: ry, width: rw, height: u)); ry += u }
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
        g.right = NSRect(x: rx, y: 0, width: rw, height: ry)
        g.height = max(g.left.maxY, g.right.maxY) + u
        return g
    }

    func height(forWidth width: CGFloat) -> CGFloat { geometry(width: max(width - leading, 1)).height }

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width - leading), line = Self.line
        // A 13 field's text sits 15 below its top: on the line.
        customName.isHidden = !g.custom
        customName.frame = NSRect(x: g.customName.minX, y: g.customName.minY + line - 15, width: g.customName.width, height: 20)
        if customName.currentEditor() == nil { customName.stringValue = g.custom ? g.name : "" }
        about.isHidden = g.said == nil
        about.frame = NSRect(x: g.about.minX, y: g.about.minY + line - 15, width: g.about.width, height: 20)
        if about.currentEditor() == nil { about.stringValue = g.said ?? "" }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width - leading), u = Self.u, line = Self.line, l = leading
        rowRects = g.mapRows; doHits = []; nameHits = []; gripRects = []
        // The two first-order headers on the first line, their words in a box of three units under each.
        Design.attributed("Structure", .body).draw(x: l, baseline: line)
        Design.attributed(g.leftHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: l, y: u, width: g.left.width, height: Self.helpUnits * u))
        hairline(x: l, y: g.mapTop - 1, width: g.left.width, Design.rule)
        for (i, r) in mapRows.enumerated() {
            let box = g.mapRows[i], b = box.minY + line
            let on = r.target == selected
            // The selected row's ground breaks the grid: from the rail's divider to the middle of the gutter between the panels.
            if on { fill(NSRect(x: 0, y: box.minY, width: box.maxX + Design.App.gutter / 2, height: box.height), Design.mist) }
            let x = l + CGFloat(r.level) * Self.step
            let name = Design.attributed(r.text, on || r.strong ? .bodyStrong : .body, colour: on || r.strong ? Design.ink : Design.quiet)
            // The pane: from the divider under the level, the grip and the name, to the name's end plus a step; eased out, and back.
            if let v = reveal[r.target], v > 0 {
                let full = x + 36 + name.size().width + Self.step
                let eased = 1 - pow(1 - v, 3)
                fill(NSRect(x: 0, y: box.minY, width: (full * eased).rounded(), height: box.height), Design.App.gridColour)
            }
            Design.attributed("\(r.level)", .caption, colour: Design.soft).draw(x: x, baseline: b)
            // The grip between the level and the name: two columns of three dots; a drag from it puts the row in another order among its own.
            let grip = NSRect(x: x + 16, y: box.minY, width: Self.grip, height: box.height)
            if canDrag(r.target) {
                for dx in [0, 4] as [CGFloat] { for dy in [-4, 0, 4] as [CGFloat] { fill(NSRect(x: grip.minX + 2 + dx, y: b - 5 + dy, width: 1.5, height: 1.5), on ? Design.quiet : Design.soft) } }
                gripRects.append(grip)
            } else { gripRects.append(.zero) }
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
            name.draw(x: x + 36, baseline: b, width: right - x - 36)
            hairline(x: l, y: box.maxY - 1, width: box.width, Design.mist)
        }
        if let slot = dragSlot, let d = dragging, let i = mapRows.firstIndex(where: { $0.target == d }) {
            let y = slotY(slot, for: d)
            fill(NSRect(x: l + CGFloat(mapRows[i].level) * Self.step, y: y - 1, width: g.left.width - CGFloat(mapRows[i].level) * Self.step, height: 2), Design.ink)
        }
        guard selected != nil else { return }
        let rx = g.right.minX
        Design.attributed(g.levelTitle, .body).draw(x: rx, baseline: line)
        Design.attributed(g.rightHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: u, width: g.right.width, height: Self.helpUnits * u))
        Design.attributed("Name", .label, colour: Design.quiet).draw(x: rx, baseline: g.nameLabel + line)
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
        if g.custom {
            Design.attributed("Custom Name", .label, colour: Design.quiet).draw(x: rx, baseline: g.customLabel + line)
            hairline(x: rx, y: g.customName.maxY - 1, width: g.right.width, customName.currentEditor() != nil ? Design.ink : Design.rule)
        }
        if g.said != nil {
            Design.attributed("Description", .label, colour: Design.quiet).draw(x: rx, baseline: g.aboutLabel + line)
            hairline(x: rx, y: g.about.maxY - 1, width: g.right.width, about.currentEditor() != nil ? Design.ink : Design.rule)
        }
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

    // MARK: The pointer: select, act, choose a name, drag a group among its siblings

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if let d = doHits.first(where: { $0.0.contains(p) }) { d.1(); return }
        if let n = nameHits.first(where: { $0.0.contains(p) }) { choose(name: n.1); return }
        if let i = rowRects.firstIndex(where: { $0.contains(p) }) {
            let r = mapRows[i]
            selected = r.target
            renaming = false
            dragging = gripRects[i].contains(p) && canDrag(r.target) ? r.target : nil
            dragStart = p
            refresh()
            settle()
        }
    }
    /// What can be put in another order: a collection among the collections, a group among its siblings. The grouping level and the member stand alone.
    private func canDrag(_ t: Target) -> Bool {
        switch t {
        case .collection: return all.count > 1
        case .tier: return false
        case .node(_, _, let level): return level > 1
        }
    }
    /// The rows a dragged row may land among, in order, itself included.
    private func peers(of t: Target) -> [Target] {
        switch t {
        case .collection: return all.map { .collection($0.id) }
        case .tier: return []
        case .node(let cid, let nid, let level): return collection(cid).map { siblings(of: nid, in: $0).map { .node(cid, $0, level) } } ?? []
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging, let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard abs(p.y - start.y) > 4 || dragSlot != nil else { return }
        let sibs = peers(of: d)
        var slot = sibs.count
        for (k, s) in sibs.enumerated() {
            if let i = mapRows.firstIndex(where: { $0.target == s }), p.y < rowRects[i].midY { slot = k; break }
        }
        if slot != dragSlot { dragSlot = slot; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
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
            case .tier: break
            }
            show()
        }
        dragging = nil; dragSlot = nil; dragStart = nil
        needsDisplay = true
    }
    private func siblings(of id: UUID, in c: SchemaCollection) -> [UUID] {
        for (node, _) in SchemaTrial.rows(of: c.stack) where node.children.contains(where: { $0.id == id }) { return node.children.map { $0.id } }
        return []
    }
    private func rowIndex(ofNode id: UUID, in cid: UUID) -> Int? {
        mapRows.firstIndex { if case .node(let c, let n, _) = $0.target { return c == cid && n == id }; return false }
    }
    /// Where the slot line goes: on the peer at that place, or under the last peer and everything inside it.
    private func slotY(_ slot: Int, for t: Target) -> CGFloat {
        let sibs = peers(of: t)
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

    /// The bin on a group: gone at once when it holds nothing, and the row above it takes the selection; asked about on the panel when it holds something.
    private func remove(_ node: SchemaNode, level: Int, in cid: UUID) {
        guard let c = collection(cid) else { return }
        let n = count(node, level: level, in: c)
        guard n == 0 else { selected = .node(cid, node.id, level); refresh(); askAboutContents(of: node, level: level, in: c, holding: n); return }
        let up = parent(of: node.id, in: c)
        let tree = SchemaTrial.removing(node.id, from: c.stack)
        keep(cid, tree)
        if let p = up, let l = SchemaTrial.rows(of: tree).first(where: { $0.node.id == p })?.level { selected = .node(cid, p, l) }
        show()
    }

    private func askAboutContents(of node: SchemaNode, level: Int, in c: SchemaCollection, holding n: Int) {
        let role = SchemaTrial.role(of: node), things = "\(n) \(noun(role, n))"
        let note = "Its \(things) are spread over the \(c.name) \(SchemaTrial.plural(member(c)).lowercased()) that follow this stack, and would be left with nowhere to show. The group can be renamed and they stay where they are; to delete them, do it member by member."
        SwissConfirm.ask(over: window, title: "\(node.name) Holds \(things.prefix(1).uppercased() + things.dropFirst())", note: note, commit: "Go On",
                         options: ["Keep the \(noun(role, n)) and rename the group"]) { [weak self] _ in self?.keepAndRename() }
    }
    private func keepAndRename() {
        guard case .node(let cid, let nid, _)? = selected, let c = collection(cid) else { return }
        keep(cid, SchemaTrial.changing(nid, in: c.stack) { $0.role = SchemaTrial.role(of: $0) })
        renaming = true
        show()
        window?.makeFirstResponder(customName)
        customName.currentEditor()?.selectAll(nil)
    }

    private func addTier(_ cid: UUID) {
        SchemaTrial.changeCollection(cid) { $0.folderName = SchemaTrial.folderNames[0] }
        selected = .tier(cid)
        show()
    }
    private func addFolder(_ cid: UUID) {
        SchemaTrial.changeCollection(cid) { col in col.folders.append(SchemaFolder(name: "\(col.folderName ?? "Folder") \(col.folders.count + 1)")) }
        selected = .tier(cid)
        show()
    }
    private func removeTier(_ cid: UUID) {
        SchemaTrial.changeCollection(cid) { $0.folderName = nil; $0.folders = [] }
        selected = .collection(cid)
        show()
    }
    private func removeCollection(_ cid: UUID) {
        guard cid != all[0].id, let lib = library else { return }
        lib.dump(collection: cid, over: window) { [weak self] in
            self?.selected = .collection(SchemaTrial.firstCollection)
            self?.show()
        }
    }

    /// Another collection, after this one, starting with its stack; named on the window's own panel.
    private func newCollection(after cid: UUID) {
        guard let c = collection(cid) else { return }
        SwissConfirm.name(over: window, title: "New Collection", note: "A heading in rail1 of its own, after \(c.name.isEmpty ? "this collection" : c.name) and starting with its stack.",
                          placeholder: "Clients, Our Own Work, Archive", confirm: "Create Collection", check: { ProjectField.problem(name: $0, values: [:], naming: "collection") }) { [weak self] name in
            guard let self = self else { return }
            var list = SchemaTrial.collections
            let made = SchemaCollection(name: name, stack: c.stack)
            list.insert(made, at: (list.firstIndex { $0.id == cid } ?? list.count - 1) + 1)
            SchemaTrial.collections = list
            self.selected = .collection(made.id)
            self.show()
        }
    }

    /// Another member of the collection: a project with files of its own, named on the panel, placed in the collection.
    private func newMember(in cid: UUID) {
        guard let c = collection(cid), let lib = library else { return }
        let word = member(c)
        SwissConfirm.name(over: window, title: "New \(word)", note: "A \(word.lowercased()) in \(c.name): a project with files of its own, following the collection's stack.",
                          placeholder: "Client, product or piece of work", confirm: "Create \(word)", check: { ProjectField.problem(name: $0, values: [:]) }) { [weak self] name in
            var made: UUID?
            lib.apply("New Project") { l in
                let id = l.createProject(named: name)
                let organisation = ProjectField.tidy(Prefs.organisation)
                if !organisation.isEmpty { l.setProjectDetails(id, organisation) }
                made = id
            }
            guard let id = made, lib.library.project(id) != nil else { return }
            SchemaTrial.place(id, in: cid, folder: nil)
            self?.show()
        }
    }

    // MARK: Names

    private func setName(_ name: String) {
        guard let what = selected, let c = collection(what.collection) else { return }
        switch what {
        case .collection(let cid): SchemaTrial.changeCollection(cid) { $0.name = name }
        case .tier(let cid): SchemaTrial.changeCollection(cid) { $0.folderName = name }
        case .node(let cid, let nid, _): keep(cid, SchemaTrial.changing(nid, in: c.stack) { $0.role = SchemaTrial.role(of: $0); $0.name = name })
        }
        all = SchemaTrial.collections
    }
    private func choose(name: String?) {
        guard let what = selected, let c = collection(what.collection) else { return }
        if name == nil {
            let now: String, offered: [String]
            switch what {
            case .collection: now = c.name; offered = SchemaTrial.collectionNames
            case .tier: now = c.folderName ?? ""; offered = SchemaTrial.folderNames
            case .node(_, let nid, let level): now = SchemaTrial.rows(of: c.stack).first { $0.node.id == nid }?.node.name ?? ""; offered = SchemaTrial.names(forLevel: level)
            }
            if !offered.contains(now) { window?.makeFirstResponder(customName); return }
            renaming = true
            refresh()
            window?.makeFirstResponder(customName)
            return
        }
        window?.makeFirstResponder(self)
        renaming = false
        setName(name ?? "")
        show()
    }
    @objc private func nameEntered() { window?.makeFirstResponder(self) }
    /// Typing keeps the name letter by letter without rebuilding the window, which would end the editing; the rails follow when it ends.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let what = selected, let c = collection(what.collection) else { return }
        if field === customName {
            setName(field.stringValue)
            needsDisplay = true
        } else if field === about {
            let text = field.stringValue
            switch what {
            case .collection(let cid): SchemaTrial.changeCollection(cid) { $0.about = text }
            case .tier: break
            case .node(let cid, let nid, _): keep(cid, SchemaTrial.changing(nid, in: c.stack) { $0.about = text })
            }
            all = SchemaTrial.collections
        }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === customName { setName(field.stringValue); renaming = false }
        show()
    }
}
