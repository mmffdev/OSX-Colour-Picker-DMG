import AppKit

// ---------- The tree on the splash's left: the structure as the answers build it ----------
//
// From the first section on, the left of the splash shows the catalogue as rail1 will show it, from
// the catalogue itself down to the groups inside each member, every branch drawn in full, and every
// answer changes it at once: the teaching aid is the tree, not a page at the end. A word being typed
// on the right shows on the tree before it is taken, and what a later section asks for stands as a
// placeholder until that section is reached. The tree scrolls, and a caret before each node that
// holds others opens and closes it. It is a toy until Set: click a name to change it, add another of
// anything from the words the splash offered or a word of your own, take any away. Each level
// carries a caption saying what it is.
//
// The tree's lines join: a row's elbow comes down from its parent's caret and runs into its own,
// and where a level goes on below (Web, then Print) the vertical runs through the rows between.
//
// The working nodes are marked (Rick, 2026-10-09): each section says which nodes its blocks are about,
// each with a colour from the palette, and a band of that colour slides in from the right behind the
// node's row, a ribbon with a point at its end; the same colour stands in a square before the block's
// cells on the right, so the block and its node read as one. On reaching the next section the bands
// slide out again and the new section's slide in.

final class SplashTreeView: NSView {
    typealias A = Design.App
    private let draft: SplashDraft
    private let catalogueName: () -> String
    /// Called after any change made on the tree, so the splash can settle its buttons.
    var onChange: (() -> Void)?

    /// A level another of can be added at; a group belongs to a stream inside its member, or directly to a member without streams.
    enum Level: Equatable { case party(String), category(UUID), stream(UUID, String), group(String) }
    /// A node a section can be working on, to mark it with a band.
    enum Target: Hashable { case catalogue, collection(String), party(UUID), category(UUID, String), leaf(String) }
    /// The colours the bands and the squares take, in turn: eight printer's inks that sit on warm paper and apart from each other,
    /// vermilion, steel blue, viridian, mustard, plum, teal, olive, periwinkle; none of them a colour the app uses for anything else.
    static let palette: [NSColor] = [Design.hex("#E04E2F"), Design.hex("#3A6EA5"), Design.hex("#2F9E6E"), Design.hex("#D9A126"), Design.hex("#8C4A9E"), Design.hex("#1F9AA6"), Design.hex("#A5A32E"), Design.hex("#6B7FD7")]
    static func colour(_ i: Int) -> NSColor { palette[((i % palette.count) + palette.count) % palette.count] }
    /// The nodes marked, with the palette index of each; set by the splash for the section in view, and the bands follow.
    var marks: [Target: Int] = [:] { didSet { if marks != oldValue { settleBands() } } }
    private struct Band { var colour: Int; var start: TimeInterval; var leaving: Bool }
    private var bands: [Target: Band] = [:]
    private var bandTimer: Timer?
    /// The band comes in from the left: its point travels to its place, and once it has settled the tail follows and the notch shows.
    private static let slide: TimeInterval = 0.48, tailWait: TimeInterval = 0.56, tail: TimeInterval = 0.3
    private enum Kind { case catalogue, collection(String), party(Int), category(UUID, Int), stream(UUID, String, Int), member(UUID, String), placeholder, pending, group(String, String), add(Level) }
    private struct Line {
        let kind: Kind; let name: String; let depth: Int; let caption: String; let removable: Bool
        /// A node that holds others has a key the caret opens and closes it by.
        var key: String? = nil
        /// Drawn soft: a placeholder, a word being typed, a member not yet named.
        var soft = false
        /// What the row stands for, to a section marking the node it works on.
        var targets: [Target] = []
    }
    private var hits: [(NSRect, () -> Void)] = []
    private var collapsed: Set<String> = []
    private var options: SplashMenu?
    /// The furthest section reached: what a later section asks for is a placeholder until then (Rick, 2026-10-09).
    var reached = 0
    /// The section that asks what sits inside each member; before it the groups are one "Asset Collection".
    var groupsStep = 5
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
        var out: [Line] = [Line(kind: .catalogue, name: catalogueName(), depth: 0, caption: "Catalogue", removable: false, key: "cat", targets: [.catalogue])]
        func open(_ key: String) -> Bool { !collapsed.contains(key) }
        func pending(_ w: SplashDraft.Pending) -> String? { d.pending.flatMap { $0.level == w && !$0.text.isEmpty ? $0.text : nil } }
        func add(_ level: Level, _ name: String, at depth: Int) { out.append(Line(kind: .add(level), name: name, depth: depth, caption: "", removable: false)) }
        /// The groups under a member, the leaf's own: each leaf may differ (Rick, 2026-10-09).
        func groups(at depth: Int, leaf: String) {
            guard reached >= groupsStep else { out.append(Line(kind: .placeholder, name: "Assets", depth: depth, caption: "Assets", removable: false, soft: true)); return }
            let mine = d.groups(of: leaf)
            for g in mine { out.append(Line(kind: .group(leaf, g), name: d.groupNames[g] ?? g, depth: depth, caption: "Asset", removable: mine.count > 1)) }
            if let p = pending(.group(leaf)) { out.append(Line(kind: .pending, name: p, depth: depth, caption: "Asset", removable: false, soft: true)) }
            add(.group(leaf), "Another asset", at: depth)
        }
        func streams(_ p: SplashDraft.Party, _ category: String, under key: String, at depth: Int) {
            let active = d.activeStreams(of: p.id, category)
            guard !active.isEmpty || pending(.stream(p.id, category)) != nil else {
                groups(at: depth, leaf: SplashDraft.leafKey(p.id, category, nil)); return
            }
            for (j, s) in active.enumerated() {
                let k = key + "/s\(j)", leaf = SplashDraft.leafKey(p.id, category, s)
                out.append(Line(kind: .stream(p.id, category, j), name: s, depth: depth, caption: "Stream", removable: true, key: k, targets: [.leaf(leaf)]))
                if open(k) { groups(at: depth + 1, leaf: leaf) }
            }
            if let w = pending(.stream(p.id, category)) { out.append(Line(kind: .pending, name: w, depth: depth, caption: "Stream", removable: false, soft: true)) }
            if !active.isEmpty { add(.stream(p.id, category), "Another stream", at: depth) }
        }
        func member(_ p: SplashDraft.Party, _ category: String, under key: String, at depth: Int) {
            let word = SplashDraft.memberWord(category), named = d.member(of: p.id, category)
            let k = key + "/m"
            let targets: [Target] = d.activeStreams(of: p.id, category).isEmpty ? [.leaf(SplashDraft.leafKey(p.id, category, nil))] : []
            out.append(Line(kind: .member(p.id, category), name: named ?? pending(.member(p.id, category)) ?? "First \(word.lowercased())", depth: depth, caption: word, removable: named != nil, key: k, soft: named == nil, targets: targets))
            if open(k) { streams(p, category, under: k, at: depth + 1) }
        }
        func categories(_ p: SplashDraft.Party, under key: String, at depth: Int) {
            let mine = d.categories(of: p.id)
            if mine.isEmpty {
                let k = key + "/c"
                out.append(Line(kind: .placeholder, name: pending(.category(p.id)) ?? "First category", depth: depth, caption: "Category", removable: false, key: k, soft: true))
                if open(k) { groups(at: depth + 1, leaf: SplashDraft.leafKey(p.id, "", nil)) }
                return
            }
            for (i, c) in mine.enumerated() {
                let k = key + "/c\(i)"
                out.append(Line(kind: .category(p.id, i), name: c, depth: depth, caption: "Category", removable: true, key: k, targets: [.category(p.id, c)]))
                if open(k) { member(p, c, under: k, at: depth + 1) }
            }
            if let w = pending(.category(p.id)) { out.append(Line(kind: .pending, name: w, depth: depth, caption: "Category", removable: false, soft: true)) }
            add(.category(p.id), "Another category", at: depth)
        }
        guard open("cat") else { return out }
        for type in d.types {
            let ck = "c:" + type
            let own = type == SplashDraft.ownWork ? d.parties.first(where: { $0.isOwnWork }) : nil
            out.append(Line(kind: .collection(type), name: d.collectionTitle(type), depth: 1, caption: "Collection", removable: false, key: ck, targets: [.collection(type)] + (own.map { [.party($0.id)] } ?? [])))
            guard open(ck) else { continue }
            if type == SplashDraft.ownWork {
                if let own = own { categories(own, under: ck, at: 2) }
                continue
            }
            for (i, p) in d.parties.enumerated() where p.type == type {
                let pk = ck + "/p\(i)"
                out.append(Line(kind: .party(i), name: p.name, depth: 2, caption: SplashDraft.singular(type), removable: true, key: pk, targets: [.party(p.id)]))
                if open(pk) { categories(p, under: pk, at: 3) }
            }
            if let w = pending(.party(type)) { out.append(Line(kind: .pending, name: w, depth: 2, caption: SplashDraft.singular(type), removable: false, soft: true)) }
            else if d.parties(of: type).isEmpty { out.append(Line(kind: .placeholder, name: "First \(SplashDraft.singular(type).lowercased())", depth: 2, caption: SplashDraft.singular(type), removable: false, soft: true)) }
            add(.party(type), "Another \(SplashDraft.singular(type).lowercased())", at: 2)
        }
        if d.types.isEmpty { out.append(Line(kind: .placeholder, name: "Your first collection", depth: 1, caption: "Collection", removable: false, soft: true)) }
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
        let now = CACurrentMediaTime()
        for (k, l) in all.enumerated() {
            let b = row(k), top = line(k), x = left + CGFloat(l.depth) * step
            // The band behind a marked row, sliding in from the right or away again.
            var banded = false
            for t in l.targets { if let band = bands[t] { drawBand(band, top: top, at: now); banded = banded || !band.leaving } }
            let captionColour = banded ? Design.ink.withAlphaComponent(0.6) : Design.soft
            // The verticals passing through from levels above, and this row's own elbow, every one meeting the next.
            for a in 1..<max(1, l.depth) where continues(after: k, at: a) {
                fill(NSRect(x: left + CGFloat(a - 1) * step + 6, y: top, width: 1, height: A.unit), Design.rule)
            }
            if l.depth > 0 {
                let vx = left + CGFloat(l.depth - 1) * step + 6
                fill(NSRect(x: vx, y: top, width: 1, height: continues(after: k, at: l.depth) ? A.unit : A.unit / 2 + 1), Design.rule)
                // The elbow runs into the caret, or, where the row has none, on to the name.
                fill(NSRect(x: vx, y: top + A.unit / 2, width: (l.key == nil ? x + caret - 4 : x - 2) - vx, height: 1), Design.rule)
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
            let nx = x + caret, nameWidth = width - CGFloat(l.depth) * step - caret - 118
            let rowRect = NSRect(x: nx, y: top, width: nameWidth, height: A.unit)
            switch l.kind {
            case .add(let level):
                Design.attributed("+  " + l.name, .body, colour: Design.quiet).draw(x: nx, baseline: b)
                hits.append((rowRect, { [weak self] in self?.add(level, below: rowRect) }))
            case .placeholder, .pending:
                Design.attributed(l.name, .body, colour: Design.soft).draw(x: nx, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 96, baseline: b - 1)
            default:
                let style: Design.Text = l.depth < 2 ? .bodyStrong : .body
                Design.attributed(l.name, style, colour: l.soft ? Design.soft : Design.ink).draw(x: nx, baseline: b, width: nameWidth)
                Design.attributed(l.caption, .label, colour: captionColour).draw(x: left + width - 96, baseline: b - 1)
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

    // MARK: The bands

    /// Marks changed: a node newly marked gets a band coming in, one no longer marked has its band leave.
    private func settleBands() {
        let now = CACurrentMediaTime()
        for (t, c) in marks {
            if var b = bands[t] { if b.leaving || b.colour != c { b.leaving = false; b.colour = c; b.start = now; bands[t] = b } }
            else { bands[t] = Band(colour: c, start: now, leaving: false) }
        }
        for (t, var b) in bands where marks[t] == nil && !b.leaving { b.leaving = true; b.start = now; bands[t] = b }
        if bandTimer == nil {
            bandTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tickBands() }
        }
        needsDisplay = true
    }
    private func tickBands() {
        let now = CACurrentMediaTime()
        var busy = false
        for (t, b) in bands {
            let done = now - b.start >= (b.leaving ? Self.slide : Self.tailWait + Self.tail)
            if done, b.leaving { bands[t] = nil } else if !done { busy = true }
        }
        if !busy { bandTimer?.invalidate(); bandTimer = nil }
        needsDisplay = true
    }
    /// The ribbon: the row's height, with a point at its head and a notch at its tail, its head reaching to the gap before the
    /// sections. It grows in from off the left edge: the head travels to its place, the body behind it off the edge still, and
    /// once the head has settled the tail comes in after it and the notch shows. Leaving, it slides back out the way it came.
    private func drawBand(_ band: Band, top: CGFloat, at now: TimeInterval) {
        func ease(_ u: Double) -> CGFloat { CGFloat(1 - pow(1 - max(0, min(1, u)), 3)) }
        let tip: CGFloat = 14, notch: CGFloat = 10, mid = top + A.unit / 2
        let end = bounds.width - tip - 2, off = -(end + tip)
        let age = now - band.start
        var head: CGFloat, tailX: CGFloat
        if band.leaving {
            head = end - (end - off) * ease(age / Self.slide)
            tailX = min(0, head - (end + tip))
        } else {
            head = off + (end - off) * ease(age / Self.slide)
            tailX = -(notch + 24) + (notch + 24) * ease((age - Self.tailWait) / Self.tail)
            tailX = min(tailX, head - tip - 1)
        }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tailX, y: top))
        path.line(to: NSPoint(x: head, y: top))
        path.line(to: NSPoint(x: head + tip, y: mid))
        path.line(to: NSPoint(x: head, y: top + A.unit))
        path.line(to: NSPoint(x: tailX, y: top + A.unit))
        path.line(to: NSPoint(x: tailX + notch, y: mid))
        path.close()
        Self.colour(band.colour).setFill(); path.fill()
    }

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
        let d = draft
        let was: String
        if case .member(let id, let c) = l.kind, d.member(of: id, c) == nil { was = "" } else { was = l.name }
        InlineName.edit(was, style: style, in: self, x: x, baseline: baseline, width: width, at: NSPoint(x: x, y: baseline)) { [weak self] typed in
            guard let self = self, let t = typed?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { self?.needsDisplay = true; return }
            switch l.kind {
            case .catalogue: d.catalogueName = t
            case .collection(let type): d.collectionNames[type] = t
            case .party(let i): if d.parties.indices.contains(i) { d.parties[i].name = t }
            case .category(let id, let i):
                if var list = d.categoriesOf[id], list.indices.contains(i) {
                    // The category's streams and member go with its name.
                    let old = list[i]; list[i] = t; d.categoriesOf[id] = list
                    d.streamsOf[SplashDraft.key(id, t)] = d.streamsOf.removeValue(forKey: SplashDraft.key(id, old))
                    d.members[SplashDraft.key(id, t)] = d.members.removeValue(forKey: SplashDraft.key(id, old))
                }
            case .stream(let id, let c, let j): if var list = d.streamsOf[SplashDraft.key(id, c)], list.indices.contains(j) { list[j] = t; d.streamsOf[SplashDraft.key(id, c)] = list }
            case .member(let id, let c): d.members[SplashDraft.key(id, c)] = t
            case .group(_, let g): d.groupNames[g] = t
            default: break
            }
            self.changed()
        }
    }
    /// Another of a level: a client is typed straight in; a category, a stream or a group is picked from the words the splash
    /// offered, less those already there, or typed as a word of your own.
    private func add(_ level: Level, below r: NSRect) {
        let d = draft
        switch level {
        case .party(let type):
            d.parties.append(SplashDraft.Party(type: type, name: uniqueName(SplashDraft.singular(type) + " 2", among: d.names(of: type))))
            changed(); edit(.party(d.parties.count - 1))
        case .category, .stream, .group:
            let offered: [String], taken: [String]
            switch level {
            case .category(let id): offered = SplashDraft.categoryOptions; taken = d.categories(of: id)
            case .stream(let id, let c): offered = SplashDraft.streamOptions; taken = d.streams(of: id, c)
            case .group(let leaf): offered = SplashDraft.groupOptions; taken = d.groups(of: leaf)
            default: offered = []; taken = []
            }
            let m = SplashMenu(items: offered.filter { !taken.contains($0) }, own: "A word of your own") { [weak self] choice in
                guard let self = self else { return }
                self.options?.removeFromSuperview(); self.options = nil
                switch level {
                case .category(let id):
                    let word = choice ?? uniqueName("Category 2", among: taken)
                    d.categoriesOf[id, default: []].append(word); self.changed(); if choice == nil { self.edit(.category(id, d.categories(of: id).count - 1)) }
                case .stream(let id, let c):
                    let word = choice ?? uniqueName("Stream 2", among: taken)
                    d.streamsOf[SplashDraft.key(id, c), default: []].append(word); d.setOneKind(false, id, c); self.changed(); if choice == nil { self.edit(.stream(id, c, d.streams(of: id, c).count - 1)) }
                case .group(let leaf):
                    let word = choice ?? uniqueName("Asset 2", among: taken)
                    d.groupsOf[leaf] = d.groups(of: leaf) + [word]; self.changed(); if choice == nil { self.edit(.group(leaf, word)) }
                default: break
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
            case (.party(let i), .party(let j)): return i == j
            case (.category(let a, let i), .category(let b, let j)): return a == b && i == j
            case (.stream(let a, let c, let i), .stream(let b, let e, let j)): return a == b && c == e && i == j
            case (.group(let a, let g), .group(let b, let h)): return a == b && g == h
            default: return false
            }
        }
    }
    private func remove(_ kind: Kind) {
        let d = draft
        switch kind {
        case .party(let i): if d.parties.indices.contains(i) { let p = d.parties.remove(at: i); if d.parties(of: p.type).isEmpty { d.types.removeAll { $0 == p.type } } }
        case .category(let id, let i): if var list = d.categoriesOf[id], list.indices.contains(i) { list.remove(at: i); d.categoriesOf[id] = list }
        case .stream(let id, let c, let j): if var list = d.streamsOf[SplashDraft.key(id, c)], list.indices.contains(j) { list.remove(at: j); d.streamsOf[SplashDraft.key(id, c)] = list }
        case .member(let id, let c): d.members[SplashDraft.key(id, c)] = nil
        case .group(let leaf, let g): let mine = d.groups(of: leaf); if mine.count > 1 { d.groupsOf[leaf] = mine.filter { $0 != g } }
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
