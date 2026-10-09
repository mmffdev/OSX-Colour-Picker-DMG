import AppKit

// ---------- The tree on the splash's left: the structure as the answers build it ----------
//
// From the first section on, the left of the splash shows the catalogue as rail1 will show it, from
// the catalogue itself down to the groups inside the first member, and every answer changes it at
// once: the teaching aid is the tree, not a page at the end. It is a toy until Set: click a name to
// change it, add another of anything from the words the splash offered or a word of your own, take
// any away. Each level carries a caption saying what it is.
//
// The tree's lines join: a row's elbow comes down from its parent's indent and runs into its name,
// and where a level goes on below (Web, then Print) the vertical runs through the rows between.

final class SplashTreeView: NSView {
    typealias A = Design.App
    private let draft: SplashDraft
    private let catalogueName: () -> String
    /// Called after any change made on the tree, so the splash can settle its buttons.
    var onChange: (() -> Void)?

    enum Level { case client, stream, kind, member, group }
    private enum Kind { case catalogue, collection, client(Int), stream(Int), kind(Int), member(Int), placeholder(Level), group(String), add(Level) }
    private struct Line { let kind: Kind; let name: String; let depth: Int; let caption: String; let removable: Bool }
    private var hits: [(NSRect, () -> Void)] = []
    private var tracking: NSTrackingArea?
    private var options: SplashMenu?
    private static let step: CGFloat = 20

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
        var out: [Line] = [
            Line(kind: .catalogue, name: catalogueName(), depth: 0, caption: "Catalogue", removable: false),
            Line(kind: .collection, name: d.collectionTitle, depth: 1, caption: "Collection", removable: false)]
        func groups(at depth: Int) {
            for g in d.groups { out.append(Line(kind: .group(g), name: d.groupNames[g] ?? g, depth: depth, caption: "Group", removable: d.groups.count > 1)) }
            out.append(Line(kind: .add(.group), name: "Another group", depth: depth, caption: "", removable: false))
        }
        func members(at depth: Int) {
            if d.members.isEmpty {
                out.append(Line(kind: .placeholder(.member), name: "First \(d.memberWord.lowercased())", depth: depth, caption: d.memberWord, removable: false))
                groups(at: depth + 1)
                return
            }
            for (i, m) in d.members.enumerated() {
                out.append(Line(kind: .member(i), name: m, depth: depth, caption: d.memberWord, removable: d.members.count > 1))
                if i == 0 { groups(at: depth + 1) }
            }
            out.append(Line(kind: .add(.member), name: "Another \(d.memberWord.lowercased())", depth: depth, caption: "", removable: false))
        }
        func kinds(at depth: Int) {
            guard d.kinds.count > 1 else { members(at: depth); return }
            for (k, name) in d.kinds.enumerated() {
                out.append(Line(kind: .kind(k), name: name, depth: depth, caption: "Kind", removable: true))
                if k == 0 { members(at: depth + 1) }
            }
            out.append(Line(kind: .add(.kind), name: "Another kind", depth: depth, caption: "", removable: false))
        }
        func streams(at depth: Int) {
            guard !d.streams.isEmpty else { kinds(at: depth); return }
            for (j, s) in d.streams.enumerated() {
                out.append(Line(kind: .stream(j), name: s, depth: depth, caption: "Stream", removable: true))
                if j == 0 { kinds(at: depth + 1) }
            }
            out.append(Line(kind: .add(.stream), name: "Another stream", depth: depth, caption: "", removable: false))
        }
        if d.isOwnWork || d.who == nil {
            streams(at: 2)
        } else if d.clients.isEmpty {
            out.append(Line(kind: .placeholder(.client), name: "First \(d.clientWord.lowercased())", depth: 2, caption: d.clientWord, removable: false))
            streams(at: 3)
        } else {
            for (i, c) in d.clients.enumerated() {
                out.append(Line(kind: .client(i), name: c, depth: 2, caption: d.clientWord, removable: d.clients.count > 1))
                if i == 0 { streams(at: 3) }
            }
            out.append(Line(kind: .add(.client), name: "Another \(d.clientWord.lowercased())", depth: 2, caption: "", removable: false))
        }
        return out
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        let all = lines(), step = Self.step
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
                fill(NSRect(x: vx, y: top + A.unit / 2, width: step - 10, height: 1), Design.rule)
            }
            let nameWidth = width - CGFloat(l.depth) * step - 130
            let rowRect = NSRect(x: x, y: top, width: nameWidth, height: A.unit)
            switch l.kind {
            case .add(let level):
                Design.attributed("+  " + l.name, .body, colour: Design.quiet).draw(x: x, baseline: b)
                hits.append((rowRect, { [weak self] in self?.add(level, below: rowRect) }))
            case .placeholder:
                Design.attributed(l.name, .body, colour: Design.soft).draw(x: x, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 110, baseline: b - 1)
            default:
                let style: Design.Text = l.depth < 2 ? .bodyStrong : .body
                Design.attributed(l.name, style).draw(x: x, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 110, baseline: b - 1)
                hits.append((rowRect, { [weak self] in self?.rename(l, x: x, baseline: b, width: nameWidth, style: style) }))
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
        needsDisplay = true
        onChange?()
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
            case .collection: d.collectionName = t
            case .client(let i): if d.clients.indices.contains(i) { d.clients[i] = t }
            case .stream(let j): if d.streams.indices.contains(j) { d.streams[j] = t }
            case .kind(let k): if d.kinds.indices.contains(k) { d.kinds[k] = t }
            case .member(let i): if d.members.indices.contains(i) { d.members[i] = t }
            case .group(let g): d.groupNames[g] = t
            default: break
            }
            self.changed()
        }
    }
    /// Another of a level: a client or a member is typed straight in; a stream, a kind or a group is picked from the words
    /// the splash offered, less those already there, or typed as a word of your own.
    private func add(_ level: Level, below r: NSRect) {
        let d = draft
        switch level {
        case .client: d.clients.append(uniqueName(d.clientWord + " 2", among: d.clients)); changed(); edit(.client(d.clients.count - 1))
        case .member: d.members.append(uniqueName(d.memberWord + " 2", among: d.members)); changed(); edit(.member(d.members.count - 1))
        case .stream, .kind, .group:
            let offered: [String], taken: [String]
            switch level {
            case .stream: offered = SplashDraft.streamOptions; taken = d.streams
            case .kind: offered = SplashDraft.makeOptions; taken = d.kinds
            default: offered = SplashDraft.groupOptions; taken = d.groups
            }
            let items = offered.filter { !taken.contains($0) }
            let m = SplashMenu(items: items, own: "A word of your own") { [weak self] choice in
                guard let self = self else { return }
                self.options?.removeFromSuperview(); self.options = nil
                let word = choice ?? uniqueName(level == .stream ? "Stream 2" : level == .kind ? "Kind 2" : "Group 2", among: taken)
                switch level {
                case .stream: d.streams.append(word); d.oneKind = false; self.changed(); if choice == nil { self.edit(.stream(d.streams.count - 1)) }
                case .kind: d.kinds.append(word); self.changed(); if choice == nil { self.edit(.kind(d.kinds.count - 1)) }
                default: d.groups.append(word); self.changed(); if choice == nil { self.edit(.group(word)) }
                }
            }
            m.frame = NSRect(x: r.minX, y: r.maxY, width: min(220, bounds.width - r.minX - A.gutter), height: m.wanted)
            addSubview(m)
            options = m
        }
    }
    /// Opens the name of a line just added for typing, once it has been drawn.
    private func edit(_ kind: Kind) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let all = self.lines()
            guard let k = all.firstIndex(where: { same($0.kind, kind) }) else { return }
            let l = all[k], x = self.left + CGFloat(l.depth) * Self.step
            self.rename(l, x: x, baseline: self.row(k), width: self.width - CGFloat(l.depth) * Self.step - 130, style: l.depth < 2 ? .bodyStrong : .body)
        }
        func same(_ a: Kind, _ b: Kind) -> Bool {
            switch (a, b) {
            case (.client(let i), .client(let j)), (.stream(let i), .stream(let j)), (.kind(let i), .kind(let j)), (.member(let i), .member(let j)): return i == j
            case (.group(let g), .group(let h)): return g == h
            default: return false
            }
        }
    }
    private func remove(_ kind: Kind) {
        let d = draft
        switch kind {
        case .client(let i): if d.clients.count > 1, d.clients.indices.contains(i) { d.clients.remove(at: i) }
        case .stream(let j): if d.streams.indices.contains(j) { d.streams.remove(at: j); if d.streams.isEmpty { d.oneKind = true } }
        case .kind(let k): if d.kinds.count > 1, d.kinds.indices.contains(k) { d.kinds.remove(at: k) }
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
