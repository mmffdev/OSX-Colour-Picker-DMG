import AppKit

// ---------- The tree on the splash's left: the structure as the answers build it ----------
//
// From the first section on, the left of the splash shows the catalogue as rail1 will show it, from
// the catalogue itself down to the groups inside each member, every branch drawn in full, and every
// answer changes it at once: the teaching aid is the tree, not a page at the end. A word being typed
// on the right shows on the tree before it is taken. The tree scrolls, and a caret before each node
// that holds others opens and closes it. It is a toy until Set: click a name to change it, add
// another of anything from the words the splash offered or a word of your own, take any away. Each
// level carries a caption saying what it is.
//
// The tree's lines join: a row's elbow comes down from its parent's caret and runs into its own,
// and where a level goes on below (Web, then Print) the vertical runs through the rows between.

final class SplashTreeView: NSView {
    typealias A = Design.App
    private let draft: SplashDraft
    private let catalogueName: () -> String
    /// Called after any change made on the tree, so the splash can settle its buttons.
    var onChange: (() -> Void)?

    enum Level: Equatable { case party(String), kind, stream, member, group }
    private enum Kind { case catalogue, collection(String), party(Int), kind(Int), stream(Int), member(Int), placeholder, pending, group(String), add(Level) }
    private struct Line {
        let kind: Kind; let name: String; let depth: Int; let caption: String; let removable: Bool
        /// A node that holds others has a key the caret opens and closes it by.
        var key: String? = nil
    }
    private var hits: [(NSRect, () -> Void)] = []
    private var collapsed: Set<String> = []
    private var options: SplashMenu?
    private static let step: CGFloat = 22, caret: CGFloat = 14

    init(draft: SplashDraft, catalogueName: @escaping () -> String) {
        self.draft = draft
        self.catalogueName = catalogueName
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// The tree's first row is the band's row 1, the baseline the sections' labels sit on.
    private func row(_ k: Int) -> CGFloat { CGFloat(k + 1) * A.unit + A.textBaseline }
    private func line(_ k: Int) -> CGFloat { CGFloat(k + 1) * A.unit }
    private var left: CGFloat { A.margin }
    private var width: CGFloat { bounds.width - A.margin - A.gutter / 2 }

    // MARK: The lines

    private func lines() -> [Line] {
        let d = draft
        var out: [Line] = [Line(kind: .catalogue, name: catalogueName(), depth: 0, caption: "Catalogue", removable: false, key: "cat")]
        func open(_ key: String) -> Bool { !collapsed.contains(key) }
        func pending(_ w: SplashDraft.Pending) -> String? { d.pending.flatMap { $0.level == w && !$0.text.isEmpty ? $0.text : nil } }
        func add(_ level: Level, _ name: String, at depth: Int) { out.append(Line(kind: .add(level), name: name, depth: depth, caption: "", removable: false)) }
        func groups(at depth: Int) {
            for g in d.groups { out.append(Line(kind: .group(g), name: d.groupNames[g] ?? g, depth: depth, caption: "Group", removable: d.groups.count > 1)) }
            if let p = pending(.group) { out.append(Line(kind: .pending, name: p, depth: depth, caption: "Group", removable: false)) }
            add(.group, "Another group", at: depth)
        }
        func members(under key: String, at depth: Int, first: Bool) {
            let word = d.memberWord
            if first, !d.members.isEmpty {
                for (i, m) in d.members.enumerated() {
                    let k = key + "/m\(i)"
                    out.append(Line(kind: .member(i), name: m, depth: depth, caption: word, removable: d.members.count > 1, key: k))
                    if open(k) { groups(at: depth + 1) }
                }
                add(.member, "Another \(word.lowercased())", at: depth)
            } else {
                let k = key + "/m"
                out.append(Line(kind: .placeholder, name: (first ? pending(.member) : nil) ?? "First \(word.lowercased())", depth: depth, caption: word, removable: false, key: k))
                if open(k) { groups(at: depth + 1) }
            }
        }
        func streams(under key: String, at depth: Int, first: Bool) {
            let active = d.activeStreams
            guard !active.isEmpty || (first && pending(.stream) != nil) else { members(under: key, at: depth, first: first); return }
            for (j, s) in active.enumerated() {
                let k = key + "/s\(j)"
                out.append(Line(kind: .stream(j), name: s, depth: depth, caption: "Stream", removable: true, key: k))
                if open(k) { members(under: k, at: depth + 1, first: first && j == 0) }
            }
            if first, let p = pending(.stream) { out.append(Line(kind: .pending, name: p, depth: depth, caption: "Stream", removable: false)) }
            if !active.isEmpty { add(.stream, "Another stream", at: depth) }
        }
        func kinds(under key: String, at depth: Int, first: Bool) {
            guard !d.kinds.isEmpty || (first && pending(.kind) != nil) else { streams(under: key, at: depth, first: first); return }
            for (i, name) in d.kinds.enumerated() {
                let k = key + "/k\(i)"
                out.append(Line(kind: .kind(i), name: name, depth: depth, caption: "Kind", removable: true, key: k))
                if open(k) { streams(under: k, at: depth + 1, first: first && i == 0) }
            }
            if first, let p = pending(.kind) { out.append(Line(kind: .pending, name: p, depth: depth, caption: "Kind", removable: false)) }
            if !d.kinds.isEmpty { add(.kind, "Another kind", at: depth) }
        }
        guard open("cat") else { return out }
        for (n, type) in d.types.enumerated() {
            let ck = "c:" + type
            out.append(Line(kind: .collection(type), name: d.collectionTitle(type), depth: 1, caption: "Collection", removable: false, key: ck))
            guard open(ck) else { continue }
            if type == SplashDraft.ownWork { kinds(under: ck, at: 2, first: n == 0); continue }
            var firstParty = true
            for (i, p) in d.parties.enumerated() where p.type == type {
                let pk = ck + "/p\(i)"
                out.append(Line(kind: .party(i), name: p.name, depth: 2, caption: SplashDraft.singular(type), removable: true, key: pk))
                if open(pk) { kinds(under: pk, at: 3, first: n == 0 && firstParty) }
                firstParty = false
            }
            if let p = pending(.party(type)) { out.append(Line(kind: .pending, name: p, depth: 2, caption: SplashDraft.singular(type), removable: false)) }
            add(.party(type), "Another \(SplashDraft.singular(type).lowercased())", at: 2)
        }
        // A type being named before any of it exists shows as its collection, the name beneath it.
        if let p = d.pending, case .party(let type) = p.level, !d.types.contains(type) {
            out.append(Line(kind: .pending, name: d.collectionTitle(type), depth: 1, caption: "Collection", removable: false))
            if !p.text.isEmpty { out.append(Line(kind: .pending, name: p.text, depth: 2, caption: SplashDraft.singular(type), removable: false)) }
        } else if d.types.isEmpty {
            out.append(Line(kind: .placeholder, name: "Your first collection", depth: 1, caption: "Collection", removable: false))
        }
        return out
    }

    /// The tree's own height, for the scroll view it sits in: a row a line, and one spare.
    func fit() {
        let wanted = CGFloat(lines().count + 2) * A.unit
        let seen = enclosingScrollView?.contentSize ?? bounds.size
        let size = NSSize(width: seen.width, height: max(wanted, seen.height))
        if size != bounds.size { setFrameSize(size) }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        let all = lines(), step = Self.step, caret = Self.caret
        /// Whether the ancestor of line `k` at `depth` has a sibling after it: the first later line no deeper than that depth is at it.
        func continues(after k: Int, at depth: Int) -> Bool {
            for j in (k + 1)..<all.count where all[j].depth <= depth { return all[j].depth == depth }
            return false
        }
        for (k, l) in all.enumerated() {
            let b = row(k), top = line(k), x = left + CGFloat(l.depth) * step
            // The verticals passing through from levels above, and this row's own elbow, every one meeting the next.
            for a in 1..<max(1, l.depth) where continues(after: k, at: a) {
                fill(NSRect(x: left + CGFloat(a - 1) * step + 6, y: top, width: 1, height: A.unit), Design.rule)
            }
            if l.depth > 0 {
                let vx = left + CGFloat(l.depth - 1) * step + 6
                fill(NSRect(x: vx, y: top, width: 1, height: continues(after: k, at: l.depth) ? A.unit : A.unit / 2 + 1), Design.rule)
                fill(NSRect(x: vx, y: top + A.unit / 2, width: x - 2 - vx, height: 1), Design.rule)
            }
            // The caret, for a node that holds others.
            if let key = l.key {
                let mid = top + A.unit / 2, shut = collapsed.contains(key)
                let t = NSBezierPath()
                if shut { t.move(to: NSPoint(x: x + 4, y: mid - 4)); t.line(to: NSPoint(x: x + 4, y: mid + 4)); t.line(to: NSPoint(x: x + 9, y: mid)) }
                else { t.move(to: NSPoint(x: x + 2, y: mid - 2)); t.line(to: NSPoint(x: x + 10, y: mid - 2)); t.line(to: NSPoint(x: x + 6, y: mid + 3)) }
                t.close(); Design.quiet.setFill(); t.fill()
                hits.append((NSRect(x: x - 4, y: top, width: caret + 4, height: A.unit), { [weak self] in self?.toggle(key) }))
            }
            let nx = x + caret, nameWidth = width - CGFloat(l.depth) * step - caret - 130
            let rowRect = NSRect(x: nx, y: top, width: nameWidth, height: A.unit)
            switch l.kind {
            case .add(let level):
                Design.attributed("+  " + l.name, .body, colour: Design.quiet).draw(x: nx, baseline: b)
                hits.append((rowRect, { [weak self] in self?.add(level, below: rowRect) }))
            case .placeholder, .pending:
                Design.attributed(l.name, .body, colour: Design.soft).draw(x: nx, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 110, baseline: b - 1)
            default:
                let style: Design.Text = l.depth < 2 ? .bodyStrong : .body
                Design.attributed(l.name, style).draw(x: nx, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 110, baseline: b - 1)
                hits.append((rowRect, { [weak self] in self?.rename(l, x: nx, baseline: b, width: nameWidth, style: style) }))
                if l.removable {
                    let mark = NSRect(x: left + width - 24, y: top, width: 24, height: A.unit)
                    Design.attributed("\u{00D7}", .body, colour: Design.quiet).draw(x: mark.minX + 8, baseline: b)
                    hits.append((mark, { [weak self] in self?.remove(l.kind) }))
                }
            }
        }
        window?.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() { for h in hits { addCursorRect(h.0, cursor: .pointingHand) } }

    // MARK: Changing it

    private func changed() {
        fit()
        onChange?()
    }
    private func toggle(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        fit()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let m = options { m.removeFromSuperview(); options = nil; if m.frame.contains(p) { return } }
        if let h = hits.first(where: { $0.0.contains(p) }) { window?.makeFirstResponder(nil); h.1(); return }
        super.mouseDown(with: event)
    }
    private func rename(_ l: Line, x: CGFloat, baseline: CGFloat, width: CGFloat, style: Design.Text) {
        InlineName.edit(l.name, style: style, in: self, x: x, baseline: baseline, width: width, at: NSPoint(x: x, y: baseline)) { [weak self] typed in
            guard let self = self, let t = typed?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { self?.needsDisplay = true; return }
            let d = self.draft
            switch l.kind {
            case .catalogue: d.catalogueName = t
            case .collection(let type): d.collectionNames[type] = t
            case .party(let i): if d.parties.indices.contains(i) { d.parties[i].name = t }
            case .kind(let i): if d.kinds.indices.contains(i) { d.kinds[i] = t }
            case .stream(let j): if d.streams.indices.contains(j) { d.streams[j] = t }
            case .member(let i): if d.members.indices.contains(i) { d.members[i] = t }
            case .group(let g): d.groupNames[g] = t
            default: break
            }
            self.changed()
        }
    }
    /// Another of a level: a client or a member is typed straight in; a kind, a stream or a group is picked from the words
    /// the splash offered, less those already there, or typed as a word of your own.
    private func add(_ level: Level, below r: NSRect) {
        let d = draft
        switch level {
        case .party(let type):
            d.parties.append(SplashDraft.Party(type: type, name: uniqueName(SplashDraft.singular(type) + " 2", among: d.names(of: type))))
            changed(); edit(.party(d.parties.count - 1))
        case .member:
            d.members.append(uniqueName(d.memberWord + " 2", among: d.members)); changed(); edit(.member(d.members.count - 1))
        case .kind, .stream, .group:
            let offered: [String], taken: [String]
            switch level {
            case .kind: offered = SplashDraft.makeOptions; taken = d.kinds
            case .stream: offered = SplashDraft.streamOptions; taken = d.streams
            default: offered = SplashDraft.groupOptions; taken = d.groups
            }
            let m = SplashMenu(items: offered.filter { !taken.contains($0) }, own: "A word of your own") { [weak self] choice in
                guard let self = self else { return }
                self.options?.removeFromSuperview(); self.options = nil
                let word = choice ?? uniqueName(level == .kind ? "Kind 2" : level == .stream ? "Stream 2" : "Group 2", among: taken)
                switch level {
                case .kind: d.kinds.append(word); self.changed(); if choice == nil { self.edit(.kind(d.kinds.count - 1)) }
                case .stream: d.streams.append(word); d.oneKind = false; self.changed(); if choice == nil { self.edit(.stream(d.streams.count - 1)) }
                default: d.groups.append(word); self.changed(); if choice == nil { self.edit(.group(word)) }
                }
            }
            m.frame = NSRect(x: r.minX, y: r.maxY, width: min(220, bounds.width - r.minX - A.gutter), height: m.wanted)
            addSubview(m)
            options = m
            fit()
            scrollToVisible(m.frame)
        }
    }
    /// Opens the name of a line just added for typing, once it has been drawn.
    private func edit(_ kind: Kind) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let all = self.lines()
            guard let k = all.firstIndex(where: { same($0.kind, kind) }) else { return }
            let l = all[k], x = self.left + CGFloat(l.depth) * Self.step + Self.caret
            self.scrollToVisible(NSRect(x: 0, y: self.line(k), width: 1, height: A.unit))
            self.rename(l, x: x, baseline: self.row(k), width: self.width - CGFloat(l.depth) * Self.step - Self.caret - 130, style: l.depth < 2 ? .bodyStrong : .body)
        }
        func same(_ a: Kind, _ b: Kind) -> Bool {
            switch (a, b) {
            case (.party(let i), .party(let j)), (.kind(let i), .kind(let j)), (.stream(let i), .stream(let j)), (.member(let i), .member(let j)): return i == j
            case (.group(let g), .group(let h)): return g == h
            default: return false
            }
        }
    }
    private func remove(_ kind: Kind) {
        let d = draft
        switch kind {
        case .party(let i): if d.parties.indices.contains(i) { d.parties.remove(at: i) }
        case .kind(let i): if d.kinds.indices.contains(i) { d.kinds.remove(at: i) }
        case .stream(let j): if d.streams.indices.contains(j) { d.streams.remove(at: j) }
        case .member(let i): if d.members.count > 1, d.members.indices.contains(i) { d.members.remove(at: i) }
        case .group(let g): if d.groups.count > 1 { d.groups.removeAll { $0 == g } }
        default: break
        }
        changed()
    }
    func closeMenu() { options?.removeFromSuperview(); options = nil }
}

/// The dropdown as the guide draws it: a Card with a Rule edge, rows on the beat, Mist under the pointer, and a last quiet
/// row for a word of your own. Picks with the row's word, or nil for the word of your own.
final class SplashMenu: NSView {
    typealias A = Design.App
    private let items: [String], own: String
    private let pick: (String?) -> Void
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    var wanted: CGFloat { CGFloat(items.count + 1) * A.unit + 2 }

    init(items: [String], own: String, pick: @escaping (String?) -> Void) {
        (self.items, self.own, self.pick) = (items, own, pick)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func rowRect(_ i: Int) -> NSRect { NSRect(x: 1, y: 1 + CGFloat(i) * A.unit, width: bounds.width - 2, height: A.unit) }
    override func draw(_ dirtyRect: NSRect) {
        Design.card.setFill(); bounds.fill()
        for i in 0...items.count {
            let r = rowRect(i)
            if i == hovered { Design.mist.setFill(); r.fill() }
            let last = i == items.count
            Design.attributed(last ? own + "\u{2026}" : items[i], .body, colour: last ? Design.quiet : Design.ink).draw(x: r.minX + 11, baseline: r.minY + A.textBaseline)
        }
        Design.rule.setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
    }
    private func index(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return (0...items.count).first { rowRect($0).contains(p) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseMoved(with event: NSEvent) { let i = index(at: event); if i != hovered { hovered = i; needsDisplay = true } }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {
        guard let i = index(at: event) else { return }
        pick(i == items.count ? nil : items[i])
    }
}
