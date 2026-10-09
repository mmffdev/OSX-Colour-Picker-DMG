import AppKit

// ---------- The splash: the work set up, one section at a time ----------
//
// The first time the app opens on a catalogue with no structure (TH-299), the splash covers the
// whole window. Nothing of the app shows but the wordmark, drawn by Logo exactly where the header
// draws it, column 1 on the header's baseline, so when the splash ends the mark has not moved.
//
// Half and half (Rick, 2026-10-09): the tree (SplashTree.swift), the structure as the answers build it,
// growing with every choice, is in a scroll of its own on columns 1 to 6; the sections travel on one
// tall surface on the right, columns 7 to 12. The lighthouse (Lighthouse.swift) is kept but not shown
// (showLighthouse) until its picture is right. Continue moves the surface up one section, pushing the one in view up
// and out of the band's top edge as the next slides up under it and locks. Each section is exactly
// the band's height and draws on the window's columns and on the beat counted from the band's top,
// so a locked section leaves every baseline on the grid. Only the surface moves; nothing inside a
// section is animated on its own. One gesture, one section: a swipe, a wheel turn, Return or the
// down arrow moves exactly one, and a section whose answer is missing does not move on.
//
// Back and Continue are the splash's own, locked at the bottom right for every section, their foot
// as far from the window's foot as the wordmark's top is from its top.
//
// The six sections: the catalogue's name; who the work is for, each one named as it is picked; how
// each one's work is categorised; the first name in each category; each category's streams of work;
// and what sits inside each one. Every question after the first is asked once for each answer to the
// one before, a block a time, so the page grows with the answers rather than the answers fitting the
// page. A question with choices is a row of cells to click, with Custom apart from them for words of
// your own; what is chosen lists beneath in its order, each with a handle to drag it by. Set builds the
// collections, their levels and the first member as one change. The splash is never a lock: it
// opens again from the Schema page.

final class StudioSplash: NSView {
    typealias A = Design.App
    /// Called when the splash has done its work and the app may show.
    var onDone: (() -> Void)?
    private let library: LibraryController
    private let draft: SplashDraft
    private let lighthouse = LighthouseView()
    private static let showLighthouse = false
    private let tree: SplashTreeView
    private let scroll = NSScrollView()
    private let band = SplashBand()
    private let surface = SplashBand()
    private let back = SwissButton("Back", .secondary), next = SwissButton("Continue", .primary)
    private var sections: [SplashSection] = []
    private(set) var at = 0
    private var moving = false
    private var lastWheel = Date.distantPast
    /// The band starts one point under the header's height, where the app's beat starts.
    static var bandTop: CGFloat { A.header + 1 }
    /// The wordmark's top is this far from the window's top; the buttons' foot is as far from its foot.
    static var edge: CGFloat { (StudioHeader.baseline - Logo.font.capHeight).rounded() }
    static let travel: TimeInterval = 0.46
    /// The design loop: the splash opens on every launch and Set starts it again, writing nothing. --splash-loop, or the splashLoop default.
    static var looping: Bool { CommandLine.arguments.contains("--splash-loop") || preferences.bool(forKey: "splashLoop") }

    init(library: LibraryController) {
        self.library = library
        let d = SplashDraft()
        draft = d
        let name: () -> String = { [weak library] in d.catalogueName ?? library?.catalogue ?? "" }
        tree = SplashTreeView(draft: d, catalogueName: name)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        band.wantsLayer = true
        band.layer?.masksToBounds = true
        surface.wantsLayer = true
        addSubview(band)
        band.addSubview(surface)
        if Self.showLighthouse { addSubview(lighthouse) }
        scroll.documentView = tree
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        addSubview(scroll)
        tree.onChange = { [weak self] in self?.settleButtons() }
        sections = [
            SplashName(index: 0, library: library, draft: d),
            SplashWho(index: 1, draft: d),
            SplashBlocks(index: 2, step: "Categories", first: "How do you", second: "categorise work?",
                         words: "Products, projects, ranges, jobs, campaigns: the categories each one's work falls into, a level under them holding the things you make. Pick for each one you named.",
                         options: SplashDraft.categoryOptions, word: "category",
                         blocks: { d.parties.map { p in SplashBlocks.Block(key: p.id.uuidString, caption: "Categories For \(p.title)", pending: .category(p.id),
                                                                      read: { d.categories(of: p.id) }, write: { d.categoriesOf[p.id] = $0 }) } },
                         ready: { d.everyoneCategorised }),
            SplashNames(index: 3, draft: d),
            SplashBlocks(index: 4, step: "Streams", first: "More than one", second: "stream of work?",
                         words: "Web, print, video: each stream is a level of its own under the category it belongs to, and each category has streams of its own. Choose them in order, or say it is one kind of work and there is no level.",
                         options: SplashDraft.streamOptions, word: "stream",
                         blocks: { d.chains.map { c in SplashBlocks.Block(key: SplashDraft.key(c.party.id, c.category), caption: "Streams For \(c.party.title) \u{00B7} \(c.category)", pending: .stream(c.party.id, c.category),
                                                                    read: { d.streams(of: c.party.id, c.category) }, write: { d.streamsOf[SplashDraft.key(c.party.id, c.category)] = $0 },
                                                                    check: ("One kind of work here, no stream level", { d.isOneKind(c.party.id, c.category) }, { d.setOneKind($0, c.party.id, c.category) })) } },
                         ready: { d.streamsAnswered }),
            SplashBlocks(index: 5, step: "What Sits Inside", first: "What sits", second: "inside each one?",
                         words: "The groups inside the first one of each stream: the four the app fills itself, and any of the Schema page's own types. Each stream may differ. Drag them into the order rail1 shows.",
                         options: SplashDraft.groupOptions, word: "group",
                         blocks: { d.leaves.map { l in SplashBlocks.Block(key: l.key, caption: "Groups Inside \(l.title)", pending: .group(l.key),
                                                                    read: { d.groups(of: l.key) }, write: { d.groupsOf[l.key] = $0 }) } },
                         ready: { d.everyLeafGrouped })
        ]
        tree.groupsStep = 5
        for s in sections { s.splash = self; surface.addSubview(s) }
        back.target = self; back.action = #selector(backPressed)
        next.target = self; next.action = #selector(nextPressed)
        addSubview(back); addSubview(next)
        settleButtons()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Design.card.setFill()
        bounds.fill()
        // The mark, as everywhere: where the header draws it, so it is still there when the splash has gone.
        Logo.draw(x: A.column(1, in: bounds.width), baseline: StudioHeader.baseline)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, top = Self.bandTop
        // The buttons' foot a wordmark's margin above the window's foot; the band ends a gutter above them.
        let foot = bounds.height - Self.edge
        let nh = next.intrinsicContentSize.height, nw = next.intrinsicContentSize.width, bw = back.intrinsicContentSize.width
        next.frame = NSRect(x: A.column(12, in: w) + A.columnWidth(in: w) - nw, y: foot - nh, width: nw, height: nh)
        back.frame = NSRect(x: next.frame.minX - A.gutter - bw, y: foot - nh, width: bw, height: nh)
        let h = foot - nh - A.gutter - top
        band.frame = NSRect(x: 0, y: top, width: w, height: h)
        if !moving { surface.frame = NSRect(x: 0, y: -CGFloat(at) * h, width: w, height: h * CGFloat(sections.count)) }
        for (i, s) in sections.enumerated() { s.frame = NSRect(x: 0, y: CGFloat(i) * h, width: w, height: h) }
        // Half and half: the tree's scroll takes columns 1 to 6 from the band's top to the buttons' foot, the sections
        // columns 7 to 12. The lighthouse, when shown, stands under the tree.
        if Self.showLighthouse {
            let lhH = min(13 * A.unit, max(8 * A.unit, bounds.height - top - 15 * A.unit))
            lighthouse.frame = NSRect(x: 0, y: bounds.height - lhH, width: A.column(6, in: w) + A.columnWidth(in: w) + A.gutter / 2, height: lhH)
            lighthouse.headroom = A.unit
        }
        scroll.frame = NSRect(x: 0, y: top, width: A.column(6, in: w) + A.columnWidth(in: w) + A.gutter / 2, height: foot - top)
        tree.fit()
    }

    /// The first thing to type into, once the splash is on screen; and the sea rises.
    func begin() {
        window?.makeFirstResponder(sections.first?.firstField ?? self)
        settleButtons()
        if Self.showLighthouse {
            // --lighthouse-up raises the whole tower at once, for framing the picture while it is designed.
            let all = CommandLine.arguments.contains("--lighthouse-up")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in for k in 0..<(all ? 7 : 1) { self?.lighthouse.set(level: k, to: 1) } }
        }
    }

    func settleButtons() {
        back.isEnabled = at > 0
        next.title = at == sections.count - 1 ? "Set" : "Continue"
        next.isEnabled = sections[at].canContinue
        next.invalidateIntrinsicContentSize()
        needsLayout = true
    }
    /// An answer changed: the buttons settle and the tree on the left follows.
    func changed() {
        settleButtons()
        tree.fit()
    }
    @objc private func backPressed() { go(to: at - 1) }
    @objc private func nextPressed() {
        if at == sections.count - 1 { setUp(); return }
        go(to: at + 1)
    }

    /// Set: the collections, their levels, the first folders and the first member, built into the catalogue as one change; then the app.
    private func setUp() {
        guard sections[at].canContinue else { NSSound.beep(); return }
        sections[at].commit()
        if Self.looping {
            // The loop: what Set would build is said, nothing is written, and the splash starts again from the first section.
            var schema = SchemaTrial.SchemaFile(collections: [], places: [:]), lib = Library()
            let made = draft.build(into: &schema, library: &lib)
            let renamed = draft.catalogueName.map { "rename the catalogue \($0) and " } ?? ""
            let levels = schema.collections.first.map { $0.levels.isEmpty ? "no level between" : $0.levels.joined(separator: " then ") } ?? ""
            library.flash("Would \(renamed)set up \(schema.collections.map { $0.name }.joined(separator: ", ")), \(levels), \(plural(made.members.count, "first member"))")
            go(to: 0)
            return
        }
        // The rename first, so the structure is written into the folder under its new name.
        if let name = draft.catalogueName, name != library.catalogue { library.rename(catalogue: library.catalogue, to: name) }
        var schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
        var lib = library.library
        let made = draft.build(into: &schema, library: &lib)
        SchemaTrial.replace(schema)
        let built = lib
        library.apply("Set Up Structure") { $0 = built }
        library.flash("Set up \(plural(made.collections.count, "collection")) with \(plural(made.members.count, "first member"))")
        Prefs.assistantDone = true   // the work is set up: the splash was the first open's setup
        Prefs.setupDone = true
        onDone?()
    }

    /// Moves the surface so section `i` locks in the band: up for a later section, down for an earlier one; the lighthouse follows.
    func go(to i: Int) {
        guard sections.indices.contains(i), i != at, !moving else { return }
        if i > at {
            guard sections[at].canContinue else { NSSound.beep(); return }
            sections[at].commit()
        }
        tree.closeMenu()
        let was = at
        at = i
        tree.reached = max(tree.reached, i)
        sections[i].arrive()
        changed()
        // A level rises for every section passed on the way up, and sinks for every one left on the way down.
        if Self.showLighthouse {
            if i > was { for k in (was + 1)...i { lighthouse.set(level: k, to: 1) } } else { for k in stride(from: was, to: i, by: -1) { lighthouse.set(level: k, to: 0) } }
        }
        let h = band.bounds.height
        let target = NSPoint(x: 0, y: -CGFloat(i) * h)
        window?.makeFirstResponder(sections[i].firstField ?? self)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            surface.alphaValue = 0
            surface.setFrameOrigin(target)
            NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; surface.animator().alphaValue = 1 }
            return
        }
        moving = true
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = Self.travel
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            c.allowsImplicitAnimation = true
            surface.animator().setFrameOrigin(target)
        }, completionHandler: { [weak self] in
            self?.moving = false
            self?.needsLayout = true
        })
    }

    /// The band above the sections is where the window is dragged from, as the header's top strip is when the app shows.
    override func mouseDown(with event: NSEvent) {
        if convert(event.locationInWindow, from: nil).y < Self.bandTop { window?.performDrag(with: event) } else { super.mouseDown(with: event) }
    }

    // One gesture, one section.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125, 36, 76: nextPressed()   // down, Return, Enter
        case 126: backPressed()           // up
        default: super.keyDown(with: event)
        }
    }
    override func scrollWheel(with event: NSEvent) {
        // Momentum after a swipe is the same gesture still going: only the gesture itself, or a wheel's click, moves a section.
        guard event.momentumPhase.isEmpty, abs(event.scrollingDeltaY) > 3, Date().timeIntervalSince(lastWheel) > Self.travel + 0.15 else { return }
        lastWheel = Date()
        if event.scrollingDeltaY < 0 { nextPressed() } else { backPressed() }
    }
}

/// A flipped view, for the band the sections travel in and the surface that carries them.
final class SplashBand: NSView {
    override var isFlipped: Bool { true }
}

/// One section of the splash: as tall as the band, its words on columns 7 to 12, on the beat counted from the band's top.
class SplashSection: NSView {
    typealias A = Design.App
    let index: Int
    weak var splash: StudioSplash?
    /// What may be typed into first when the section locks.
    var firstField: NSView? { nil }
    /// Whether the section's answer is given, so Continue may move on.
    var canContinue: Bool { true }
    /// Takes the section's answer, as Continue moves on from it.
    func commit() {}
    /// The section has locked into view: what it shows may depend on the answers before it.
    func arrive() { needsDisplay = true }
    /// What a click does, by where it lands, rebuilt on every draw.
    var hits: [(NSRect, () -> Void)] = []
    /// Where the pointer is, so a cell under it can reverse.
    private var hover: NSPoint?
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }

    init(index: Int) { self.index = index; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    /// The baseline of row `k` of the beat, in the section's own coordinates.
    func row(_ k: Int) -> CGFloat { CGFloat(k) * A.unit + A.textBaseline }
    /// The top of row `k`, where its unit line is.
    func line(_ k: Int) -> CGFloat { CGFloat(k) * A.unit }
    func col(_ c: Int) -> CGFloat { A.column(c, in: bounds.width) }
    func span(_ a: Int, _ b: Int) -> CGFloat { A.span(a, b, in: bounds.width) }
    /// Half and half: the tree has columns 1 to 6, the section's words begin at column 7 and run to column 12's end (Rick, 2026-10-09).
    var left: CGFloat { col(7) }
    var width: CGFloat { span(7, 12) }

    /// The section's label on row 1 and its two-tone question on rows 3 and 5, from column 7.
    func drawQuestion(step: String, first: String, second: String) {
        Design.attributed(String(format: "%02d", index) + "  \u{00B7}  " + step, .label, colour: Design.quiet).draw(x: left, baseline: row(1))
        Design.attributed(first, .title).draw(x: left, baseline: row(3), width: width)
        Design.attributed(second, .title, colour: Design.soft).draw(x: left, baseline: row(5), width: width)
    }

    /// Words in the Lead from column 7, a box of three lines from row 7.
    func drawWords(_ s: String) {
        let font = Design.Text.lead.font(), p = NSMutableParagraphStyle()
        p.minimumLineHeight = A.unit; p.maximumLineHeight = A.unit
        let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: Design.quiet, .kern: Design.Text.lead.size * Design.Text.lead.tracking, .paragraphStyle: p])
        // A fixed line sets its glyphs at its foot: the box's top is where that puts the first baseline on row 7.
        let top = row(7) - (A.unit + font.descender)
        text.draw(with: NSRect(x: left, y: top, width: width, height: A.unit * 3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: The Choice

    struct Cell { let word: String; let rect: NSRect; let apart: Bool; let plus: Bool }
    /// Lays the Choice's cells out from `x` on the row at `baseline`, wrapping to the next row where the words run past `width`.
    /// Each of `apart` is set after a gap in a box of its own, with a plus before its word when asked. Returns the cells and the rows used.
    func cells(_ items: [String], apart: [(word: String, plus: Bool)], x: CGFloat, width: CGFloat, baseline b: CGFloat) -> (cells: [Cell], rows: Int) {
        let h: CGFloat = 22
        var out: [Cell] = [], r = 0, cx = x
        func wide(_ s: String, plus: Bool) -> CGFloat { (Design.attributed(s, .label).size().width + 24 + (plus ? 14 : 0)).rounded() }
        for s in items {
            let w = wide(s, plus: false)
            if cx + w > x + width, cx > x { r += 1; cx = x }
            out.append(Cell(word: s, rect: NSRect(x: cx, y: b - 16 + CGFloat(r) * A.unit, width: w, height: h), apart: false, plus: false))
            cx += w
        }
        for a in apart {
            let w = wide(a.word, plus: a.plus)
            cx += 12
            if cx + w > x + width, cx > x + 12 { r += 1; cx = x }
            out.append(Cell(word: a.word, rect: NSRect(x: cx, y: b - 16 + CGFloat(r) * A.unit, width: w, height: h), apart: true, plus: a.plus))
            cx += w
        }
        return (out, r + 1)
    }
    /// Draws the cells: capitals in one ink outline per run, the chosen filled ink, the one under the pointer reversed too.
    func drawStrip(_ cells: [Cell], on: (String) -> Bool, pick: @escaping (String) -> Void) {
        let capHeight = Design.Text.label.size * 0.714
        var i = 0
        while i < cells.count {
            // A run: cells joined edge to edge on one row share an outline and dividers; a cell apart has its own.
            var j = i
            while !cells[j].apart, j + 1 < cells.count, !cells[j + 1].apart, cells[j + 1].rect.minX == cells[j].rect.maxX, cells[j + 1].rect.minY == cells[j].rect.minY { j += 1 }
            let run = cells[i...j]
            for c in run {
                let lit = on(c.word) || hovered(c.rect)
                if lit { fill(c.rect, Design.ink) }
                let ink = lit ? Design.card : Design.ink, words = (c.rect.minY + c.rect.height / 2 + capHeight / 2).rounded()
                var tx = c.rect.minX + 12
                if c.plus {
                    fill(NSRect(x: tx, y: c.rect.midY - 0.5, width: 9, height: 1), ink)
                    fill(NSRect(x: tx + 4, y: c.rect.midY - 4.5, width: 1, height: 9), ink)
                    tx += 14
                }
                Design.attributed(c.word, .label, colour: ink).draw(x: tx, baseline: words)
                hits.append((c.rect, { pick(c.word) }))
            }
            let box = NSRect(x: run.first!.rect.minX, y: run.first!.rect.minY, width: run.last!.rect.maxX - run.first!.rect.minX, height: run.first!.rect.height)
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            for c in run.dropLast() { fill(NSRect(x: c.rect.maxX - 0.5, y: c.rect.minY, width: 1, height: c.rect.height), Design.ink) }
            i = j + 1
        }
    }
    /// The Check: a 14 square in ink, filled with a paper tick when on, its words beside it on the baseline.
    func drawCheck(_ title: String, on: Bool, x: CGFloat, baseline b: CGFloat, toggle: @escaping () -> Void) {
        let box = NSRect(x: x, y: b - 13, width: 14, height: 14)
        if on { fill(box, Design.ink); Design.attributed("\u{2713}", .label, colour: Design.card).draw(x: x + 3, baseline: b - 1) }
        Design.ink.setStroke()
        let edge = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
        let words = Design.attributed(title, .body)
        words.draw(x: x + 22, baseline: b)
        hits.append((NSRect(x: x, y: b - A.textBaseline, width: 22 + words.size().width, height: A.unit), toggle))
    }
    /// A row of the chosen: a handle to drag by, the name with a quiet word after it, and a cross to take it away. Returns the handle's rectangle.
    @discardableResult
    func drawListRow(_ name: String, note: String? = nil, muted: Bool = false, row k: Int, x: CGFloat, width: CGFloat, remove: @escaping () -> Void) -> NSRect {
        let b = row(k), top = line(k)
        let handle = NSRect(x: x, y: top, width: 22, height: A.unit)
        for dy in [-4, 0, 4] { fill(NSRect(x: x + 1, y: (top + A.unit / 2 + CGFloat(dy) - 0.5).rounded(), width: 10, height: 1), Design.soft) }
        let text = Design.attributed(name, .body, colour: muted ? Design.soft : Design.ink)
        text.draw(x: x + 22, baseline: b, width: width - 46)
        if let n = note { Design.attributed(n, .caption, colour: Design.soft).draw(x: x + 22 + text.size().width + 12, baseline: b) }
        let mark = NSRect(x: x + width - 24, y: top, width: 24, height: A.unit)
        Design.attributed("\u{00D7}", .body, colour: Design.quiet).draw(x: mark.minX + 8, baseline: b)
        hits.append((mark, remove))
        return handle
    }
    func hovered(_ r: NSRect) -> Bool { hover.map { r.contains($0) } ?? false }

    /// A field as the sections draw them: no border, the app's 17, its hairline drawn by the section on the unit line under its row.
    static func field(_ placeholder: String) -> NSTextField {
        let f = NSTextField(string: "")
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Design.font(17, .regular)
        f.textColor = Design.ink
        f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: Design.font(17, .regular), .foregroundColor: Design.soft])
        return f
    }
    /// Where a field's text sits on its baseline: the offset from the field's top to the line the glyphs stand on.
    static let fieldBaseline: CGFloat = 13
    /// Room at a field's right end for its tick and cross.
    static let marks: CGFloat = 56
    func place(_ f: NSTextField, row k: Int, marks: Bool = false, indent: CGFloat = 0) {
        f.frame = NSRect(x: left + indent - 2, y: row(k) - Self.fieldBaseline - 4, width: width - indent + 4 - (marks ? Self.marks : 0), height: 22)
    }
    func hairline(row k: Int, live: Bool, indent: CGFloat = 0) {
        (live ? Design.ink : Design.rule).setFill()
        NSRect(x: left + indent, y: line(k + 1), width: width - indent, height: 1).fill()
    }
    /// The tick and the cross at a field's right end: take the word now, or let it go.
    func drawMarks(row k: Int, accept: @escaping () -> Void, cancel: @escaping () -> Void) {
        let b = row(k), top = line(k)
        let tick = NSRect(x: left + width - 48, y: top, width: 24, height: A.unit), cross = NSRect(x: left + width - 24, y: top, width: 24, height: A.unit)
        Design.attributed("\u{2713}", .heading, colour: hovered(tick) ? Design.ink : Design.quiet).draw(x: tick.minX + 5, baseline: b)
        Design.attributed("\u{00D7}", .heading, colour: hovered(cross) ? Design.ink : Design.quiet).draw(x: cross.minX + 6, baseline: b)
        hits.append((tick, accept)); hits.append((cross, cancel))
    }
    /// A word as the cells show it: capitalised, so it reads as the others do.
    static func titled(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t.prefix(1).uppercased() + t.dropFirst()
    }

    // MARK: The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let was = hover.flatMap { q in hits.firstIndex { $0.0.contains(q) } }
        hover = p
        if was != hits.firstIndex(where: { $0.0.contains(p) }) { needsDisplay = true }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    override func resetCursorRects() { for h in hits { addCursorRect(h.0, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = hits.first(where: { $0.0.contains(p) }) { window?.makeFirstResponder(splash); h.1(); return }
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        hits = []
        window?.invalidateCursorRects(for: self)
    }
    /// Something changed: the section is laid out and drawn again, and the splash told.
    func refresh() {
        needsLayout = true; needsDisplay = true
        splash?.changed()
    }
    /// Moves the row pressed on a handle to where the pointer goes, among `count` rows from the row `start`.
    func drag(handles: [NSRect], at p: NSPoint, from start: Int, count: Int, move: (Int, Int) -> Void) -> Bool {
        guard let from = handles.firstIndex(where: { $0.contains(p) }), let win = window else { return false }
        var current = from
        let top = line(start)
        while let e = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let y = convert(e.locationInWindow, from: nil).y
            let to = max(0, min(count - 1, Int((y - top) / A.unit)))
            if to != current { move(current, to); current = to; refresh(); displayIfNeeded() }
        }
        return true
    }
}

/// Section 0: what the catalogue is called. Its name is its folder's name and its file's; the name typed waits in the draft, and
/// Set renames both with everything else it builds, so nothing on disk moves while the splash is open.
final class SplashName: SplashSection, NSTextFieldDelegate {
    private let library: LibraryController
    private let draft: SplashDraft
    private let field = SplashSection.field("A name for everything you make")

    init(index: Int, library: LibraryController, draft: SplashDraft) {
        self.library = library
        self.draft = draft
        super.init(index: index)
        field.stringValue = draft.catalogueName ?? library.catalogue
        field.delegate = self
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var firstField: NSView? { field }
    private var typed: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    override var canContinue: Bool { !typed.isEmpty }

    override func layout() { super.layout(); place(field, row: 12) }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "Your Catalogue", first: "What shall we", second: "call it?")
        drawWords("Everything you make lives in here: your collections, your clients and every palette. You can change the name whenever you like.")
        Design.attributed("Catalogue Name", .caption, colour: Design.quiet).draw(x: left, baseline: row(11))
        hairline(row: 12, live: field.currentEditor() != nil)
        Design.attributed("Its folder on disk takes the same name.", .caption, colour: Design.quiet).draw(x: left, baseline: row(14))
    }
    override func arrive() { super.arrive(); field.stringValue = draft.catalogueName ?? library.catalogue }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    /// The name typed goes to the draft as it is typed, so the tree's root says it; the catalogue itself is renamed by Set.
    func controlTextDidChange(_ obj: Notification) {
        draft.catalogueName = typed.isEmpty || typed == library.catalogue ? nil : typed
        splash?.changed()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { splash?.go(to: index + 1); return true }
        return false
    }
}

/// Section 1: who the work is for, and their names. Each type picked (Clients, Brands) heads its own part of the list, lit in the
/// cells while it is there, with a field under its names that asks for the first and then the next, so one type takes any number
/// of names without picking it again. Our Own Work, apart from the types, is a collection with no name to give. Custom, apart as
/// well, takes a type of your own, which heads the list the moment it is taken. The names drag within their collection and go with
/// their cross; a collection's cross takes it and every name in it.
final class SplashWho: SplashSection, NSTextFieldDelegate {
    private let draft: SplashDraft
    private let typeField = SplashSection.field("A type of your own: Agencies, Partners")
    private var nameFields: [String: NSTextField] = [:]
    private var customOpen = false
    private var handles: [(rect: NSRect, party: Int)] = []
    private static let indent: CGFloat = 22

    init(index: Int, draft: SplashDraft) {
        self.draft = draft
        super.init(index: index)
        typeField.delegate = self
        typeField.isHidden = true
        addSubview(typeField)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { !draft.parties.isEmpty }
    override var firstField: NSView? { customOpen ? typeField : draft.types.last.flatMap { nameFields[$0] } }
    private func typed(_ f: NSTextField) -> String { f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func nameField(for type: String) -> NSTextField {
        if let f = nameFields[type] { return f }
        let f = SplashSection.field("")
        f.delegate = self
        addSubview(f)
        nameFields[type] = f
        return f
    }

    /// The list, collection by collection: a heading, its names, and the field for the next name.
    private enum Row { case header(String), party(Int), field(String) }
    private func rows() -> [Row] {
        var out: [Row] = []
        for t in draft.types {
            out.append(.header(t))
            if t == SplashDraft.ownWork { continue }
            for (i, p) in draft.parties.enumerated() where p.type == t { out.append(.party(i)) }
            out.append(.field(t))
        }
        return out
    }
    private struct Metrics { let cells: [Cell]; let typeRow: Int?; let captionRow: Int?; let rows: [(Row, Int)] }
    private func metrics() -> Metrics {
        let (cells, stripRows) = self.cells(SplashDraft.whoOptions, apart: [(SplashDraft.ownWork, false), ("Custom", true)], x: left, width: width, baseline: row(11))
        var k = 11 + stripRows
        var typeRow: Int?
        if customOpen { typeRow = k + 1; k += 4 }
        let list = rows()
        var captionRow: Int?
        var placed: [(Row, Int)] = []
        if !list.isEmpty {
            k += 1
            captionRow = k; k += 1
            for r in list {
                placed.append((r, k))
                if case .field = r { k += 3 } else { k += 1 }
            }
        }
        return Metrics(cells: cells, typeRow: typeRow, captionRow: captionRow, rows: placed)
    }
    override func layout() {
        super.layout()
        let m = metrics()
        typeField.isHidden = m.typeRow == nil
        if let k = m.typeRow { place(typeField, row: k + 1, marks: true) }
        for f in nameFields.values { f.isHidden = true }
        for (r, k) in m.rows {
            guard case .field(let t) = r else { continue }
            let f = nameField(for: t)
            f.isHidden = false
            let one = SplashDraft.singular(t)
            f.placeholderAttributedString = NSAttributedString(string: draft.names(of: t).isEmpty ? "Name of the first \(one.lowercased())" : "Add the next \(one.lowercased())",
                                                               attributes: [.font: Design.font(17, .regular), .foregroundColor: Design.soft])
            place(f, row: k + 1, marks: true, indent: Self.indent)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "Who It Is For", first: "Who is the", second: "work for?")
        drawWords("Each type you pick is a collection, with a level inside for every one you name: clients, brands, agencies. Our own work is a collection with no such level. Pick again to add more.")
        let m = metrics()
        drawStrip(m.cells, on: { [weak self] w in self?.isOn(w) ?? false }) { [weak self] s in self?.pick(s) }
        if let k = m.typeRow {
            Design.attributed("Custom Type", .caption, colour: Design.quiet).draw(x: left, baseline: row(k))
            hairline(row: k + 1, live: typeField.currentEditor() != nil)
            drawMarks(row: k + 1, accept: { [weak self] in self?.takeType() }, cancel: { [weak self] in self?.customOpen = false; self?.typeField.stringValue = ""; self?.refresh() })
        }
        if let k = m.captionRow { Design.attributed("Your Collections, In Order, And Who Is In Each", .caption, colour: Design.quiet).draw(x: left, baseline: row(k)) }
        handles = []
        for (r, k) in m.rows {
            switch r {
            case .header(let t):
                Design.attributed(draft.collectionTitle(t), .bodyStrong).draw(x: left, baseline: row(k), width: width - 160)
                Design.attributed("Collection", .caption, colour: Design.soft).draw(x: left + width - 110, baseline: row(k))
                let mark = NSRect(x: left + width - 24, y: line(k), width: 24, height: A.unit)
                Design.attributed("\u{00D7}", .body, colour: Design.quiet).draw(x: mark.minX + 8, baseline: row(k))
                hits.append((mark, { [weak self] in self?.removeType(t) }))
            case .party(let i):
                let h = drawListRow(draft.parties[i].name, row: k, x: left + Self.indent, width: width - Self.indent) { [weak self] in self?.remove(i) }
                handles.append((h, i))
            case .field(let t):
                let one = SplashDraft.singular(t)
                Design.attributed(draft.names(of: t).isEmpty ? "First \(one)" : "Next \(one)", .caption, colour: Design.quiet).draw(x: left + Self.indent, baseline: row(k))
                hairline(row: k + 1, live: nameFields[t]?.currentEditor() != nil, indent: Self.indent)
                drawMarks(row: k + 1, accept: { [weak self] in self?.take(t) }, cancel: { [weak self] in self?.nameFields[t]?.stringValue = ""; self?.draft.pending = nil; self?.refresh() })
            }
        }
    }

    /// A cell stays lit while its type is on the list; Custom while its field is open.
    private func isOn(_ w: String) -> Bool { w == "Custom" ? customOpen : draft.types.contains(w) }
    private func pick(_ s: String) {
        if s == "Custom" {
            customOpen.toggle()
            if !customOpen { typeField.stringValue = "" }
            refresh()
            if customOpen { window?.makeFirstResponder(typeField) }
            return
        }
        if s == SplashDraft.ownWork {
            if draft.types.contains(s) { removeType(s) } else { draft.types.append(s); draft.parties.append(SplashDraft.Party(type: s, name: "")); refresh() }
            return
        }
        open(s)
    }
    /// A type picked: its collection heads the list at once with the field for its first name, and the tree shows the collection it will be.
    private func open(_ type: String) {
        if !draft.types.contains(type) { draft.types.append(type) }
        customOpen = false
        typeField.stringValue = ""
        refresh()
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(nameField(for: type))
    }
    private func takeType() {
        guard let w = SplashSection.titled(typed(typeField)) else { return }
        open(w)
    }
    /// The name typed for a type is taken, and its field waits for the next.
    private func take(_ type: String) {
        guard let f = nameFields[type], let n = SplashSection.titled(typed(f)) else { return }
        draft.parties.append(SplashDraft.Party(type: type, name: n))
        draft.pending = nil
        f.stringValue = ""
        refresh()
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(f)
    }
    private func remove(_ i: Int) {
        guard draft.parties.indices.contains(i) else { return }
        draft.parties.remove(at: i)
        refresh()
    }
    private func removeType(_ t: String) {
        draft.parties.removeAll { $0.type == t }
        draft.types.removeAll { $0 == t }
        nameFields[t]?.stringValue = ""
        draft.pending = nil
        refresh()
    }
    /// A name drags among the names of its own collection.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let h = handles.first(where: { $0.rect.contains(p) }) else { super.mouseDown(with: event); return }
        let type = draft.parties[h.party].type
        let group = draft.parties.indices.filter { draft.parties[$0].type == type }
        guard let start = metrics().rows.first(where: { if case .party(let i) = $0.0 { return i == group[0] } else { return false } })?.1 else { return }
        _ = drag(handles: [h.rect], at: p, from: start, count: group.count) { [weak self] a, b in
            guard let d = self?.draft else { return }
            var names = group.map { d.parties[$0] }
            let item = names.remove(at: a); names.insert(item, at: b)
            for (slot, i) in group.enumerated() { d.parties[i] = names[slot] }
        }
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSTextField, let t = nameFields.first(where: { $0.value === f })?.key { draft.pending = (.party(t), typed(f)); splash?.changed() }
        needsDisplay = true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if control === typeField { takeType() } else if let t = nameFields.first(where: { $0.value === control })?.key { take(t) }
        return true
    }
}

/// A question asked once for each answer to the one before: a block for each, with its caption, its row of cells, Custom apart
/// for words of your own, and beneath them what is chosen, in order, each row with a handle to drag it by and a cross to take it
/// away. The Custom field opens under its block's cells, shows its word on the tree as it is typed, and the tick or Return adds it
/// and keeps the field for the next. A `check` is the question's other answer, drawn last on a row of its own; it sets every
/// block's choices aside without losing them.
final class SplashBlocks: SplashSection, NSTextFieldDelegate {
    typealias Check = (title: String, read: () -> Bool, write: (Bool) -> Void)
    /// One block: a question asked for one answer to the one before. Its check, when it has one, sets its own list aside.
    struct Block { let key: String; let caption: String; let pending: SplashDraft.Pending; let read: () -> [String]; let write: ([String]) -> Void; var check: Check? = nil }
    private let step: String, first: String, second: String, words: String, options: [String], word: String
    private let blocks: () -> [Block], ready: () -> Bool
    private let custom = SplashSection.field("Type one and press Return")
    /// The key of the block whose Custom field is open.
    private var customFor: String?
    private var handles: [(rect: NSRect, key: String)] = []

    init(index: Int, step: String, first: String, second: String, words: String, options: [String], word: String,
         blocks: @escaping () -> [Block], ready: @escaping () -> Bool) {
        (self.step, self.first, self.second, self.words, self.options, self.word, self.blocks, self.ready) = (step, first, second, words, options, word, blocks, ready)
        super.init(index: index)
        custom.delegate = self
        custom.isHidden = true
        addSubview(custom)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { ready() }
    private var typed: String { custom.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var splashDraft: SplashDraft? { splash?.draftForSections }

    private struct Placed { let block: Block; let captionRow: Int; let cells: [Cell]; let customRow: Int?; let listStart: Int; let listCount: Int; let checkRow: Int? }
    private struct Metrics { let placed: [Placed] }
    private func metrics() -> Metrics {
        var k = 11, placed: [Placed] = []
        for b in blocks() {
            let captionRow = k
            let (cells, rows) = self.cells(options, apart: [("Custom", true)], x: left, width: width, baseline: row(k + 1))
            k += 1 + rows
            var customRow: Int?
            if customFor == b.key { customRow = k + 1; k += 4 }
            let count = b.read().count
            let listStart = k
            k += count
            // The block's check, on the row after its list, before the next block begins.
            var checkRow: Int?
            if b.check != nil { checkRow = k; k += 1 }
            placed.append(Placed(block: b, captionRow: captionRow, cells: cells, customRow: customRow, listStart: listStart, listCount: count, checkRow: checkRow))
            k += 1
        }
        return Metrics(placed: placed)
    }
    override func layout() {
        super.layout()
        custom.isHidden = true
        for p in metrics().placed { if let k = p.customRow { custom.isHidden = false; place(custom, row: k + 1, marks: true) } }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: step, first: first, second: second)
        drawWords(words)
        let m = metrics()
        handles = []
        for p in m.placed {
            let b = p.block, chosen = b.read(), aside = b.check?.read() ?? false
            Design.attributed(b.caption, .caption, colour: Design.quiet).draw(x: left, baseline: row(p.captionRow))
            drawStrip(p.cells, on: { $0 == "Custom" ? customFor == b.key : chosen.contains($0) }) { [weak self] s in self?.pick(s, in: b) }
            if let k = p.customRow {
                Design.attributed("Custom " + word.prefix(1).uppercased() + word.dropFirst(), .caption, colour: Design.quiet).draw(x: left, baseline: row(k))
                hairline(row: k + 1, live: custom.currentEditor() != nil)
                drawMarks(row: k + 1, accept: { [weak self] in self?.addTyped() }, cancel: { [weak self] in self?.closeCustom() })
            }
            for (i, name) in chosen.enumerated() {
                handles.append((drawListRow(name, muted: aside, row: p.listStart + i, x: left, width: width) { [weak self] in self?.remove(i, from: b) }, b.key))
            }
            if let c = b.check, let k = p.checkRow {
                drawCheck(c.title, on: aside, x: left, baseline: row(k)) { [weak self] in c.write(!c.read()); self?.refresh() }
            }
        }
    }

    private func pick(_ s: String, in b: Block) {
        if s == "Custom" {
            if customFor == b.key { closeCustom() } else { customFor = b.key; custom.stringValue = ""; refresh(); window?.makeFirstResponder(custom) }
            return
        }
        var chosen = b.read()
        if let i = chosen.firstIndex(of: s) { chosen.remove(at: i) } else { chosen.append(s) }
        b.write(chosen)
        if !chosen.isEmpty { b.check?.write(false) }   // a stream picked is a stream level: the block is no longer one kind
        refresh()
    }
    private func remove(_ i: Int, from b: Block) {
        var chosen = b.read()
        guard chosen.indices.contains(i) else { return }
        chosen.remove(at: i)
        b.write(chosen)
        refresh()
    }
    private func addTyped() {
        guard let b = blocks().first(where: { $0.key == customFor }), let w = SplashSection.titled(typed) else { return }
        var chosen = b.read()
        if !chosen.contains(w) { chosen.append(w) }
        b.write(chosen)
        b.check?.write(false)
        custom.stringValue = ""
        splashDraft?.pending = nil
        refresh()
        window?.makeFirstResponder(custom)
    }
    private func closeCustom() {
        customFor = nil
        custom.stringValue = ""
        splashDraft?.pending = nil
        refresh()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = handles.first(where: { $0.rect.contains(p) }), let placed = metrics().placed.first(where: { $0.block.key == h.key }) {
            _ = drag(handles: [h.rect], at: p, from: placed.listStart, count: placed.listCount) { a, c in
                var items = placed.block.read(); let item = items.remove(at: a); items.insert(item, at: c); placed.block.write(items)
            }
            return
        }
        super.mouseDown(with: event)
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    /// The word shows on the tree as it is typed.
    func controlTextDidChange(_ obj: Notification) {
        if let b = blocks().first(where: { $0.key == customFor }) { splashDraft?.pending = (b.pending, typed); splash?.changed() }
        needsDisplay = true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        addTyped()
        return true
    }
}

/// Section 3: the first one in each category, named: a field for each, and the tree shows the name as it is typed.
final class SplashNames: SplashSection, NSTextFieldDelegate {
    private let draft: SplashDraft
    private var fields: [String: NSTextField] = [:]
    init(index: Int, draft: SplashDraft) { self.draft = draft; super.init(index: index) }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { draft.anyoneNamed }
    override var firstField: NSView? { draft.chains.first.flatMap { fields[SplashDraft.key($0.party.id, $0.category)] } }
    private func typed(_ f: NSTextField) -> String { f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func field(for key: String, word: String) -> NSTextField {
        if let f = fields[key] { return f }
        let f = SplashSection.field("The first \(word.lowercased())")
        f.delegate = self
        addSubview(f)
        fields[key] = f
        return f
    }
    private var placed: [(key: String, caption: String, word: String, row: Int)] {
        var k = 11
        return draft.chains.map { c in
            defer { k += 3 }
            let word = SplashDraft.memberWord(c.category)
            return (SplashDraft.key(c.party.id, c.category), "First \(word) For \(c.party.title) \u{00B7} \(c.category)", word, k)
        }
    }
    override func arrive() {
        super.arrive()
        for p in placed { let f = field(for: p.key, word: p.word); if typed(f) != (draft.members[p.key] ?? "") { f.stringValue = draft.members[p.key] ?? "" } }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let live = placed
        for f in fields.values { f.isHidden = true }
        for p in live { let f = field(for: p.key, word: p.word); f.isHidden = false; place(f, row: p.row + 1) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "First Names", first: "Name your", second: "first ones")
        drawWords("The first one in each category: a real folder, named as you type it, holding its own palettes, typography, information and tags. Every later one is made from the app.")
        for p in placed {
            Design.attributed(p.caption, .caption, colour: Design.quiet).draw(x: left, baseline: row(p.row))
            hairline(row: p.row + 1, live: fields[p.key]?.currentEditor() != nil)
        }
    }
    /// The name goes to the draft as it is typed, so the tree shows it; cleared, the tree's placeholder returns.
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, let key = fields.first(where: { $0.value === f })?.key else { return }
        draft.members[key] = typed(f).isEmpty ? nil : typed(f)
        splash?.changed()
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let order = placed.map { $0.key }
        if let key = fields.first(where: { $0.value === control })?.key, let i = order.firstIndex(of: key), i + 1 < order.count, let next = fields[order[i + 1]] {
            window?.makeFirstResponder(next)
        } else {
            splash?.go(to: index + 1)
        }
        return true
    }
}

extension StudioSplash {
    /// The draft, for a section that needs to show a word on the tree before it is taken.
    var draftForSections: SplashDraft { draft }
}
