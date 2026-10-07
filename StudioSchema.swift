import AppKit

// ---------- Settings ▸ Schema, on the Studio window ----------
//
// The schema as the Catalogues settings lay a page out: New Collection along the top, then one row
// per collection, a small square before its name and how many members it holds at the right. A
// click opens the row like an accordion, everything in it on the row's own left edge: the name and
// the notes, each a value on a hairline that a click turns into a field; what the members are grouped
// under, Not Grouped or one of the words on offer, the chosen one underlined; the folders when they
// are grouped, each a square and a name with Remove at its right and Add Client under them; the
// stack, every group on its own line with its level, the member at 1, its name, a word for the
// four the app fills itself, and Add Inside, Add After and Remove at the right; Reset To Standard
// and Remove Collection last. Everything is kept the moment it is changed, the way the schema always
// has been; rail1 follows at once.

final class SchemaSettings: NSView, NSTextFieldDelegate {
    weak var library: LibraryController?
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    private var collections: [SchemaCollection] = []
    private var expanded: UUID?
    private var openness: [UUID: CGFloat] = [:]
    private var clock: Timer?
    private var hover: UUID?
    private let newButton = SwissButton("New Collection", .primary)
    /// The one field, put over whichever value is being edited.
    private let editor = NSTextField(string: "")
    private var editing: Edit?
    /// What a click does, found as the panel is drawn.
    private var rowHits: [(NSRect, UUID)] = [], editHits: [(NSRect, Edit)] = [], actHits: [(NSRect, Act)] = []

    static let row: CGFloat = 36, square: CGFloat = 12, step: CGFloat = 24, line: CGFloat = 28, inset: CGFloat = 16
    private var rowsTop: CGFloat { 32 + 32 }

    /// A value that can be typed over, and where it sits.
    private enum Edit: Equatable {
        case name(UUID), about(UUID), folder(UUID, UUID), node(UUID, UUID)
    }
    /// A thing to do with a click.
    private enum Act: Equatable {
        case group(UUID, String?), addFolder(UUID), removeFolder(UUID, UUID)
        case addInside(UUID, UUID), addAfter(UUID, UUID), removeNode(UUID, UUID)
        case reset(UUID), removeCollection(UUID)
    }

    init() {
        super.init(frame: .zero)
        newButton.target = self; newButton.action = #selector(newCollection)
        editor.isBordered = false
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.font = Design.Text.body.font()
        editor.textColor = Design.ink
        editor.isHidden = true
        editor.delegate = self
        editor.target = self; editor.action = #selector(commitEdit)
        addSubview(newButton)
        addSubview(editor)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        collections = SchemaTrial.collections
        if let e = expanded, !collections.contains(where: { $0.id == e }) { expanded = nil; openness = [:] }
        refresh()
    }
    private func refresh() { needsLayout = true; needsDisplay = true; onResize?() }

    private func members(in c: SchemaCollection) -> Int {
        let all = collections, places = SchemaTrial.places
        return library?.library.projects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == c.id }.count ?? 0
    }

    // MARK: Where things are

    /// The panel's full height: the same walk as the drawing, without drawing.
    private func fullPanelHeight(for c: SchemaCollection) -> CGFloat { walk(c, at: 0, width: max(bounds.width, 1), draw: false) }
    private func panelHeight(for c: SchemaCollection) -> CGFloat { (fullPanelHeight(for: c) * (openness[c.id] ?? 0)).rounded() }

    func height(forWidth width: CGFloat) -> CGFloat {
        var y = rowsTop + 1
        for c in collections { y += Self.row + panelHeight(for: c) }
        return y + 24 + 80 + 16
    }

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
                let now = f >= 1 ? target : start + (target - start) * eased
                self.openness[n] = now
                if now != target { done = false }
            }
            if done { t.invalidate(); self.clock = nil; self.openness = self.openness.filter { $0.value > 0 } }
            self.refresh()
        }
        RunLoop.main.add(clock!, forMode: .common)
    }

    override func layout() {
        super.layout()
        newButton.frame = NSRect(x: 0, y: 0, width: newButton.intrinsicContentSize.width, height: 32)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        var y = rowsTop
        hairline(x: 0, y: y, width: bounds.width, Design.rule)
        y += 1
        rowHits = []; editHits = []; actHits = []
        for c in collections {
            let row = NSRect(x: 0, y: y, width: bounds.width, height: Self.row)
            let b = y + 23
            let sq = NSRect(x: 0, y: b - 10, width: Self.square, height: Self.square)
            fill(sq, hover == c.id ? Design.mist : Design.card)
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            let n = members(in: c)
            let count = Design.attributed("\(n) " + (n == 1 ? SchemaTrial.memberName(of: c) : SchemaTrial.plural(SchemaTrial.memberName(of: c))).lowercased(), .caption, colour: Design.quiet)
            count.draw(right: bounds.width, baseline: b)
            Design.attributed(c.name.isEmpty ? "Unnamed" : c.name, c.id == expanded ? .bodyStrong : .body).draw(x: Self.step, baseline: b, width: bounds.width - Self.step - count.size().width - 12)
            let open = openness[c.id] ?? 0
            if open == 0 { hairline(x: 0, y: y + Self.row - 1, width: bounds.width, Design.mist) }
            rowHits.append((row, c.id))
            y += Self.row
            if open > 0 {
                let shown = panelHeight(for: c)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: shown)).addClip()
                _ = walk(c, at: y, width: bounds.width, draw: true, live: c.id == expanded && open == 1)
                NSGraphicsContext.restoreGraphicsState()
                y += shown
                hairline(x: 0, y: y - 1, width: bounds.width, Design.mist)
            }
        }
        y += 24
        Design.attributed("A collection is a heading in rail1: Projects, Clients, Our Own Work. Its members are the app's projects, grouped under folders when you say so, and each follows the collection's stack: the groups inside a member, Information, Palettes, Typography and Tags filled by the app, any other a label of your own. The schema is kept with the app's settings on this Mac.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: y, width: min(bounds.width, 560), height: 80))
    }

    /// The open row's panel, top down. With `draw` off it only measures. Returns the panel's height.
    private func walk(_ c: SchemaCollection, at top: CGFloat, width w: CGFloat, draw: Bool, live: Bool = false) -> CGFloat {
        var y = top
        func section(_ title: String) {
            if draw { Design.attributed(title, .section, colour: Design.quiet).draw(x: 0, baseline: y + 20) }
            y += 28
        }
        /// A value on a hairline that a click turns into a field.
        func value(_ text: String, placeholder: String, _ edit: Edit, x: CGFloat = 0) {
            if draw {
                let t = text.isEmpty ? Design.attributed(placeholder, .body, colour: Design.soft) : Design.attributed(text, .body)
                if editing != edit { t.draw(x: x, baseline: y + 16, width: w - x) }
                hairline(x: x, y: y + 22, width: w - x, editing == edit ? Design.ink : Design.rule)
                if live { editHits.append((NSRect(x: x, y: y, width: w - x, height: 28), edit)) }
            }
            if editing == edit { editorFrame = NSRect(x: x, y: y + 2, width: w - x, height: 20) }
            y += 36
        }
        /// Words to act on, from the right edge leftwards: icon and word, quiet, the live one underlined.
        func actions(_ list: [(String, Int, Act, Bool)], baseline b: CGFloat, rowTop: CGFloat, height: CGFloat) {
            var ax = w
            for (title, glyph, act, on) in list {
                let t = Design.attributed(title, .caption, colour: on ? Design.ink : Design.quiet)
                ax -= t.size().width
                if draw {
                    t.draw(x: ax, baseline: b)
                    if on { hairline(x: ax, y: b + 3, width: t.size().width, Design.ink) }
                    icon(glyph, at: NSPoint(x: ax - 14, y: b - 9), colour: on ? Design.ink : Design.quiet)
                    if live { actHits.append((NSRect(x: ax - 20, y: rowTop, width: t.size().width + 24, height: height), act)) }
                }
                ax -= 34
            }
        }

        section("Name")
        value(c.name, placeholder: "Name the collection", .name(c.id))
        section("About")
        value(c.about, placeholder: "What goes in it", .about(c.id))

        // Grouping: Not Grouped, or one of the words on offer; the chosen one underlined in ink.
        section("Members Are Grouped Under")
        do {
            var x: CGFloat = 0
            let b = y + 16
            for word in [nil] + SchemaTrial.folderNames.map { Optional($0) } {
                let on = c.folderName == word
                let t = Design.attributed(word ?? "Not Grouped", .body, colour: on ? Design.ink : Design.quiet)
                if draw {
                    t.draw(x: x, baseline: b)
                    if on { hairline(x: x, y: b + 4, width: t.size().width, Design.ink) }
                    if live { actHits.append((NSRect(x: x - 6, y: y, width: t.size().width + 12, height: 28), .group(c.id, word))) }
                }
                x += t.size().width + 20
                if x > w - 80 { break }
            }
            y += 36
        }
        if let word = c.folderName {
            section(SchemaTrial.plural(word))
            for f in c.folders {
                let b = y + 19
                if draw {
                    let sq = NSRect(x: Self.inset, y: b - 10, width: Self.square, height: Self.square)
                    fill(sq, Design.card)
                    Design.ink.setStroke()
                    let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                }
                actions([("Remove", 2, .removeFolder(c.id, f.id), false)], baseline: b, rowTop: y, height: Self.line)
                let saved = y
                y = saved - 3
                value(f.name, placeholder: "Name the \(word.lowercased())", .folder(c.id, f.id), x: Self.inset + Self.step)
                y = saved + Self.line + 8
            }
            do {
                let b = y + 19
                let t = Design.attributed("Add \(word)", .caption, colour: Design.quiet)
                if draw {
                    icon(4, at: NSPoint(x: Self.inset, y: b - 9), colour: Design.quiet)
                    t.draw(x: Self.inset + 16, baseline: b)
                    if live { actHits.append((NSRect(x: Self.inset - 4, y: y, width: t.size().width + 28, height: Self.line), .addFolder(c.id))) }
                }
                y += Self.line + 8
            }
        }

        // The stack: every group on a line with its level, the member at 1; the four the app fills say so.
        section("Stack")
        for (node, level) in SchemaTrial.rows(of: c.stack) {
            let b = y + 19
            let x = Self.inset + CGFloat(level - 1) * Self.step
            if draw { Design.attributed("\(level)", .caption, colour: Design.soft).draw(x: x, baseline: b) }
            let role = level == 2 ? SchemaTrial.role(of: node) : nil
            var does: [(String, Int, Act, Bool)] = []
            if role == nil && level > 1 { does.append(("Remove", 2, .removeNode(c.id, node.id), false)) }
            if level > 1 { does.append(("Add After", 4, .addAfter(c.id, node.id), false)) }
            does.append(("Add Inside", 5, .addInside(c.id, node.id), false))
            actions(does, baseline: b, rowTop: y, height: Self.line)
            if draw, let r = role {
                let word = Design.attributed("Filled by the app: \(r.title.lowercased())", .caption, colour: Design.soft)
                word.draw(right: w - CGFloat(does.count) * 100 - 20, baseline: b)
            }
            let saved = y
            y = saved - 3
            value(node.name, placeholder: level == 1 ? "What a member is called" : "Name the group", .node(c.id, node.id), x: x + 20)
            y = saved + Self.line + 8
        }

        // The row's own actions at the right: Reset To Standard, and Remove Collection while another remains.
        y += 8
        var last: [(String, Int, Act, Bool)] = []
        if collections.count > 1 { last.append(("Remove Collection", 2, .removeCollection(c.id), false)) }
        last.append(("Reset To Standard", 3, .reset(c.id), false))
        actions(last, baseline: y + 23, rowTop: y, height: 36)
        y += 36 + 8
        return y - top
    }

    private var editorFrame = NSRect.zero

    /// The small marks beside a word: a cross, a reset arrow, a plus, a corner for "inside".
    private func icon(_ which: Int, at p: NSPoint, colour: NSColor) {
        colour.setStroke()
        let s: CGFloat = 9, path = NSBezierPath()
        path.lineWidth = 1.2
        switch which {
        case 2:
            path.move(to: NSPoint(x: p.x + 1, y: p.y + 1)); path.line(to: NSPoint(x: p.x + s, y: p.y + s))
            path.move(to: NSPoint(x: p.x + s, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 1, y: p.y + s))
        case 3:
            path.appendArc(withCenter: NSPoint(x: p.x + 5, y: p.y + 5), radius: 4, startAngle: 40, endAngle: 320)
            path.move(to: NSPoint(x: p.x + 8, y: p.y + 1)); path.line(to: NSPoint(x: p.x + 8.5, y: p.y + 4.5)); path.line(to: NSPoint(x: p.x + 5, y: p.y + 4))
        case 4:
            path.move(to: NSPoint(x: p.x, y: p.y + 5)); path.line(to: NSPoint(x: p.x + s, y: p.y + 5))
            path.move(to: NSPoint(x: p.x + 5, y: p.y)); path.line(to: NSPoint(x: p.x + 5, y: p.y + s))
        default:
            path.move(to: NSPoint(x: p.x + 1, y: p.y)); path.line(to: NSPoint(x: p.x + 1, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6))
            path.move(to: NSPoint(x: p.x + s - 3, y: p.y + 3)); path.line(to: NSPoint(x: p.x + s, y: p.y + 6)); path.line(to: NSPoint(x: p.x + s - 3, y: p.y + 9))
        }
        path.stroke()
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
        if editing != nil { commitEdit() }
        if let a = actHits.first(where: { $0.0.contains(p) }) { perform(a.1); return }
        if let e = editHits.first(where: { $0.0.contains(p) }) { begin(e.1); return }
        if let r = rowHits.first(where: { $0.0.contains(p) }) {
            expanded = expanded == r.1 ? nil : r.1
            animate()
            refresh()
        }
    }

    // MARK: Editing a value in place

    private func current(_ e: Edit) -> String {
        switch e {
        case .name(let c): return collections.first { $0.id == c }?.name ?? ""
        case .about(let c): return collections.first { $0.id == c }?.about ?? ""
        case .folder(let c, let f): return collections.first { $0.id == c }?.folders.first { $0.id == f }?.name ?? ""
        case .node(let c, let n): return collections.first { $0.id == c }.flatMap { SchemaTrial.rows(of: $0.stack).first { $0.node.id == n }?.node.name } ?? ""
        }
    }

    private func begin(_ e: Edit) {
        editing = e
        editor.stringValue = current(e)
        needsDisplay = true
        displayIfNeeded()   // the walk finds the field's place as it draws
        editor.frame = editorFrame
        editor.isHidden = false
        window?.makeFirstResponder(editor)
    }

    @objc private func commitEdit() {
        guard let e = editing else { return }
        let text = editor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        editor.isHidden = true
        if window?.firstResponder === editor.currentEditor() { window?.makeFirstResponder(self) }
        switch e {
        case .name(let c): SchemaTrial.changeCollection(c) { $0.name = text }
        case .about(let c): SchemaTrial.changeCollection(c) { $0.about = text }
        case .folder(let c, let f): SchemaTrial.changeCollection(c) { col in if let i = col.folders.firstIndex(where: { $0.id == f }) { col.folders[i].name = text } }
        case .node(let c, let n): SchemaTrial.changeCollection(c) { $0.stack = SchemaTrial.changing(n, in: $0.stack) { $0.name = text } }
        }
        reload(); onChange?()
    }
    func controlTextDidEndEditing(_ obj: Notification) { if editing != nil { commitEdit() } }

    // MARK: Acts

    private func perform(_ a: Act) {
        switch a {
        case .group(let c, let word):
            SchemaTrial.changeCollection(c) { col in
                col.folderName = word
                if word != nil && col.folders.isEmpty { col.folders = [SchemaFolder(name: "\(word!) 1")] }
            }
        case .addFolder(let c):
            SchemaTrial.changeCollection(c) { col in col.folders.append(SchemaFolder(name: "\(col.folderName ?? "Folder") \(col.folders.count + 1)")) }
        case .removeFolder(let c, let f):
            // Members in the folder stay in the collection, straight under its heading.
            SchemaTrial.changeCollection(c) { col in col.folders.removeAll { $0.id == f } }
            var places = SchemaTrial.places
            for (k, v) in places where v.folder == f { places[k] = SchemaPlace(collection: v.collection, folder: nil) }
            SchemaTrial.places = places
        case .addInside(let c, let n):
            SchemaTrial.changeCollection(c) { $0.stack = SchemaTrial.addingChild(to: n, in: $0.stack).tree }
        case .addAfter(let c, let n):
            SchemaTrial.changeCollection(c) { $0.stack = SchemaTrial.addingSibling(after: n, in: $0.stack).tree }
        case .removeNode(let c, let n):
            SchemaTrial.changeCollection(c) { $0.stack = SchemaTrial.removing(n, from: $0.stack) }
        case .reset(let c):
            SchemaTrial.changeCollection(c) { $0.stack = SchemaTrial.start }
        case .removeCollection(let c):
            guard let col = collections.first(where: { $0.id == c }), collections.count > 1 else { return }
            let n = members(in: col)
            let first = collections.first { $0.id != c }?.name ?? "the first collection"
            SwissConfirm.ask(over: window, title: "Remove \(col.name)",
                             note: (n == 0 ? "It holds no members. " : "Its \(plural(n, SchemaTrial.memberName(of: col).lowercased())) move to \(first), with everything in them. ") + "The heading goes from rail1. Slide across to go on.",
                             commit: "Remove") { [weak self] in
                SchemaTrial.collections = SchemaTrial.collections.filter { $0.id != c }
                self?.expanded = nil
                self?.reload(); self?.onChange?()
            }
            return
        }
        reload(); onChange?()
    }

    @objc private func newCollection() {
        var all = SchemaTrial.collections
        let used = Set(all.map { $0.name })
        let name = SchemaTrial.collectionNames.first { !used.contains($0) } ?? "Collection \(all.count + 1)"
        let made = SchemaCollection(name: name, stack: SchemaTrial.start)
        all.append(made)
        SchemaTrial.collections = all
        expanded = made.id
        reload(); animate(); onChange?()
    }
}
