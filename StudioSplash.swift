import AppKit

// ---------- The splash: the work set up, one section at a time ----------
//
// The first time the app opens on a catalogue with no structure (TH-299), the splash covers the
// whole window. Nothing of the app shows but the wordmark, drawn by Logo exactly where the header
// draws it, column 1 on the header's baseline, so when the splash ends the mark has not moved.
//
// The left is the tree (SplashTree.swift), the structure as the answers build it, growing with
// every choice, over the lighthouse at the bottom left, which rises a level as each section locks.
// The sections travel on one tall surface on the right, columns 7 to 12: Continue moves the surface
// up one section, pushing the one in view up and out of the band's top edge as the next slides up
// under it and locks. Each section is exactly the band's height and draws on the window's columns
// and on the beat counted from the band's top, so a locked section leaves every baseline on the
// grid. Only the surface moves; nothing inside a section is animated on its own. One gesture, one
// section: a swipe, a wheel turn, Return or the down arrow moves exactly one, and a section whose
// answer is missing does not move on.
//
// Back and Continue are the splash's own, locked at the bottom right for every section, their foot
// as far from the window's foot as the wordmark's top is from its top.
//
// The seven sections: the catalogue's name; who the work is for; the streams of work; what is made;
// what sits inside each one; the first names; and the tree, ready to set. A question with choices is
// a row of cells to click, with Custom apart from them for words of your own; what is chosen lists
// beneath in its order, each with a handle to drag it by. Set builds the collection, its levels and
// the first member as one change. The splash is never a lock: it opens again from the Schema page.

final class StudioSplash: NSView {
    typealias A = Design.App
    /// Called when the splash has done its work and the app may show.
    var onDone: (() -> Void)?
    private let library: LibraryController
    private let draft: SplashDraft
    private let lighthouse = LighthouseView()
    private let tree: SplashTreeView
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
        addSubview(lighthouse)
        addSubview(tree)
        tree.onChange = { [weak self] in self?.settleButtons() }
        sections = [
            SplashName(index: 0, library: library, draft: d),
            SplashPick(index: 1, step: "Who It Is For", first: "Who is the", second: "work for?",
                       words: "The main bucket in your collection: a level for each client, customer or brand. Work of your own has no such level.",
                       options: SplashDraft.whoOptions, many: false, word: "word",
                       read: { d.who.map { [$0] } ?? [] }, write: { d.who = $0.first }),
            SplashPick(index: 2, step: "Streams", first: "More than one", second: "stream of work?",
                       words: "Web, print, video: each stream is a level of its own under every client. Choose yours in order, or say it is one kind of work and there is no level. The tree on the left follows.",
                       options: SplashDraft.streamOptions, many: true, word: "stream",
                       read: { d.streams }, write: { d.streams = $0; if !$0.isEmpty { d.oneKind = false } },
                       check: ("One kind of work, no stream level", { d.oneKind }, { d.oneKind = $0; if $0 { d.streams = [] } })),
            SplashPick(index: 3, step: "What You Make", first: "What do", second: "you make?",
                       words: "The thing that holds your palettes, typography, information, tags, assets and other collections. Choose more than one and each kind is a level of its own.",
                       options: SplashDraft.makeOptions, many: true, word: "kind",
                       read: { d.kinds }, write: { d.kinds = $0 }),
            SplashPick(index: 4, step: "What Sits Inside", first: "What sits", second: "inside each one?",
                       words: "The groups of every one you make: the four the app fills itself, and any of the Schema page's own types. Drag them into the order rail1 shows.",
                       options: SplashDraft.groupOptions, many: true, word: "group",
                       read: { d.groups }, write: { d.groups = $0 }),
            SplashNames(index: 5, draft: d),
            SplashReady(index: 6, draft: d, catalogueName: name)
        ]
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
        // The lighthouse stands at the bottom left on columns 1 to 4, thirteen units tall where the window allows and eight at least;
        // the tree takes the band's height above it, on columns 1 to 6.
        let lhH = min(13 * A.unit, max(8 * A.unit, bounds.height - top - 15 * A.unit))
        lighthouse.frame = NSRect(x: 0, y: bounds.height - lhH, width: A.column(4, in: w) + A.columnWidth(in: w) + A.gutter / 2, height: lhH)
        lighthouse.headroom = A.unit
        tree.frame = NSRect(x: 0, y: top, width: A.column(6, in: w) + A.columnWidth(in: w) + A.gutter / 2, height: bounds.height - lhH - A.gutter - top)
    }

    /// The first thing to type into, once the splash is on screen; and the sea rises.
    func begin() {
        window?.makeFirstResponder(sections.first?.firstField ?? self)
        settleButtons()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.lighthouse.set(level: 0, to: 1) }
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
        tree.needsDisplay = true
    }
    @objc private func backPressed() { go(to: at - 1) }
    @objc private func nextPressed() {
        if at == sections.count - 1 { setUp(); return }
        go(to: at + 1)
    }

    /// Set: the collection, its levels, the first folders and the first member, built into the catalogue as one change; then the app.
    private func setUp() {
        guard sections[at].canContinue else { NSSound.beep(); return }
        sections[at].commit()
        if Self.looping {
            // The loop: what Set would build is said, nothing is written, and the splash starts again from the first section.
            var schema = SchemaTrial.SchemaFile(collections: [], places: [:]), lib = Library()
            let made = draft.build(into: &schema, library: &lib)
            let renamed = draft.catalogueName.map { "rename the catalogue \($0) and " } ?? ""
            library.flash("Would \(renamed)set up \(draft.collectionTitle), \(schema.collections[0].levels.isEmpty ? "no level between" : schema.collections[0].levels.joined(separator: " then ")), \(plural(made.members.count, draft.memberWord.lowercased()))")
            go(to: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.travel + 0.1) { [weak self] in self?.lighthouse.set(level: 0, to: 1) }
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
        library.flash("Set up \(draft.collectionTitle) with \(plural(made.members.count, draft.memberWord.lowercased()))")
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
        sections[i].arrive()
        changed()
        // A level rises for every section passed on the way up, and sinks for every one left on the way down.
        if i > was { for k in (was + 1)...i { lighthouse.set(level: k, to: 1) } } else { for k in stride(from: was, to: i, by: -1) { lighthouse.set(level: k, to: 0) } }
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
    /// The section's words begin at column 7 and run to column 12's end.
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

    struct Cell { let word: String; let rect: NSRect; let apart: Bool }
    /// Lays the Choice's cells out from `x` on the row at `baseline`, wrapping to the next row where the words run past `width`.
    /// `apart` is set after a gap in a box of its own, with a plus before its word. Returns the cells and the rows used.
    func cells(_ items: [String], apart: String?, x: CGFloat, width: CGFloat, baseline b: CGFloat) -> (cells: [Cell], rows: Int) {
        let h: CGFloat = 22
        var out: [Cell] = [], r = 0, cx = x
        func wide(_ s: String, plus: Bool) -> CGFloat { (Design.attributed(s, .label).size().width + 24 + (plus ? 14 : 0)).rounded() }
        for s in items {
            let w = wide(s, plus: false)
            if cx + w > x + width, cx > x { r += 1; cx = x }
            out.append(Cell(word: s, rect: NSRect(x: cx, y: b - 16 + CGFloat(r) * A.unit, width: w, height: h), apart: false))
            cx += w
        }
        if let a = apart {
            let w = wide(a, plus: true)
            cx += 12
            if cx + w > x + width, cx > x + 12 { r += 1; cx = x }
            out.append(Cell(word: a, rect: NSRect(x: cx, y: b - 16 + CGFloat(r) * A.unit, width: w, height: h), apart: true))
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
                if c.apart {
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
    /// A row of the chosen: a handle to drag by, the name, and a cross to take it away. Returns the handle's rectangle.
    @discardableResult
    func drawListRow(_ name: String, row k: Int, x: CGFloat, width: CGFloat, remove: @escaping () -> Void) -> NSRect {
        let b = row(k), top = line(k)
        let handle = NSRect(x: x, y: top, width: 22, height: A.unit)
        for dy in [-4, 0, 4] { fill(NSRect(x: x + 1, y: (top + A.unit / 2 + CGFloat(dy) - 0.5).rounded(), width: 10, height: 1), Design.soft) }
        Design.attributed(name, .body).draw(x: x + 22, baseline: b, width: width - 46)
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
    func place(_ f: NSTextField, row k: Int) { f.frame = NSRect(x: left - 2, y: row(k) - Self.fieldBaseline - 4, width: width + 4, height: 22) }
    func hairline(row k: Int, live: Bool) {
        (live ? Design.ink : Design.rule).setFill()
        NSRect(x: left, y: line(k + 1), width: width, height: 1).fill()
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

/// A question answered from a row of cells, one of them or several, with Custom apart for words of your own. With `many`, what is
/// chosen lists beneath in its order, each row with a handle to drag it by and a cross to take it away; the Custom field sits under
/// the list and Return adds the word typed, so the list grows and the field moves down. A `check` is the question's other answer,
/// drawn under the cells; on, it clears the choices.
final class SplashPick: SplashSection, NSTextFieldDelegate {
    typealias Check = (title: String, read: () -> Bool, write: (Bool) -> Void)
    private let step: String, first: String, second: String, words: String, options: [String], many: Bool, word: String
    private let read: () -> [String], write: ([String]) -> Void
    private let check: Check?
    private let custom: NSTextField
    private var customOpen = false
    private var handles: [NSRect] = []

    init(index: Int, step: String, first: String, second: String, words: String, options: [String], many: Bool, word: String,
         read: @escaping () -> [String], write: @escaping ([String]) -> Void, check: Check? = nil) {
        (self.step, self.first, self.second, self.words, self.options, self.many, self.word, self.read, self.write, self.check) = (step, first, second, words, options, many, word, read, write, check)
        custom = SplashSection.field(many ? "Type one and press Return" : "A word of your own")
        super.init(index: index)
        custom.delegate = self
        custom.isHidden = true
        addSubview(custom)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { !read().isEmpty || (check?.read() ?? false) }
    private var typed: String { custom.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The word typed as the cells show it: capitalised, so it reads as the others do.
    private var typedWord: String? { typed.isEmpty ? nil : typed.prefix(1).uppercased() + typed.dropFirst() }

    /// Where everything sits: the cells from row 11, the check under them, the list under that, and the Custom field last.
    private struct Metrics { let cells: [Cell]; let checkRow: Int?; let listStart: Int; let listCount: Int; let customRow: Int? }
    private func metrics() -> Metrics {
        let (cells, rows) = self.cells(options, apart: "Custom", x: left, width: width, baseline: row(11))
        var k = 11 + rows
        var checkRow: Int?
        if check != nil { checkRow = k; k += 1 }
        let listCount = many ? read().count : 0
        let listStart = k
        k += listCount
        return Metrics(cells: cells, checkRow: checkRow, listStart: listStart, listCount: listCount, customRow: customOpen ? k : nil)
    }

    override func layout() {
        super.layout()
        let m = metrics()
        custom.isHidden = m.customRow == nil
        if let k = m.customRow { place(custom, row: k + 1) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: step, first: first, second: second)
        drawWords(words)
        let m = metrics(), chosen = read()
        drawStrip(m.cells, on: { $0 == "Custom" ? customOpen : chosen.contains($0) }) { [weak self] s in self?.pick(s) }
        if let c = check, let k = m.checkRow {
            drawCheck(c.title, on: c.read(), x: left, baseline: row(k)) { [weak self] in self?.toggleCheck() }
        }
        handles = []
        for (i, name) in (many ? chosen : []).enumerated() {
            handles.append(drawListRow(name, row: m.listStart + i, x: left, width: width) { [weak self] in self?.remove(i) })
        }
        if let k = m.customRow {
            Design.attributed("Custom " + word.prefix(1).uppercased() + word.dropFirst(), .caption, colour: Design.quiet).draw(x: left, baseline: row(k))
            hairline(row: k + 1, live: custom.currentEditor() != nil)
        }
    }

    private func pick(_ s: String) {
        if s == "Custom" {
            customOpen.toggle()
            needsLayout = true; needsDisplay = true
            if customOpen { window?.makeFirstResponder(custom) } else { custom.stringValue = "" }
            return
        }
        var chosen = read()
        if many {
            if let i = chosen.firstIndex(of: s) { chosen.remove(at: i) } else { chosen.append(s) }
            if !chosen.isEmpty { check?.write(false) }
        } else {
            chosen = chosen == [s] ? [] : [s]
            customOpen = false; custom.stringValue = ""
        }
        write(chosen)
        needsLayout = true; needsDisplay = true
        splash?.changed()
    }
    private func toggleCheck() {
        guard let c = check else { return }
        c.write(!c.read())
        needsLayout = true; needsDisplay = true
        splash?.changed()
    }
    private func remove(_ i: Int) {
        var chosen = read()
        guard chosen.indices.contains(i) else { return }
        chosen.remove(at: i)
        write(chosen)
        needsLayout = true; needsDisplay = true
        splash?.changed()
    }
    /// Adds the word typed to the list, or makes it the one choice, and clears the field for the next.
    private func addTyped() {
        guard let w = typedWord else { return }
        var chosen = read()
        if many { if !chosen.contains(w) { chosen.append(w) }; check?.write(false) } else { chosen = [w] }
        write(chosen)
        custom.stringValue = ""
        needsLayout = true; needsDisplay = true
        splash?.changed()
    }

    // The handle: a press on it drags the row to a new place in the list as the pointer crosses the rows.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = handles.firstIndex(where: { $0.contains(p) }) { drag(from: h) ; return }
        super.mouseDown(with: event)
    }
    private func drag(from start: Int) {
        guard let win = window else { return }
        var current = start
        let m = metrics(), top = line(m.listStart)
        while let e = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let y = convert(e.locationInWindow, from: nil).y
            let to = max(0, min(m.listCount - 1, Int((y - top) / A.unit)))
            if to != current {
                var items = read()
                let item = items.remove(at: current)
                items.insert(item, at: to)
                write(items)
                current = to
                splash?.changed()
                needsDisplay = true
                displayIfNeeded()
            }
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) {
        // A single choice is the word as it is typed; a list takes the word on Return.
        if !many { write(typedWord.map { [$0] } ?? []); splash?.changed() }
        needsDisplay = true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if many { addTyped() } else { splash?.go(to: index + 1) }
        return true
    }
}

/// Section 5: the first names, the first client and the first thing made, as fields; real folders on disk, named as typed.
final class SplashNames: SplashSection, NSTextFieldDelegate {
    private let draft: SplashDraft
    private let client = SplashSection.field("Acme"), member = SplashSection.field("Spring Launch")

    init(index: Int, draft: SplashDraft) {
        self.draft = draft
        super.init(index: index)
        for f in [client, member] { f.delegate = self; addSubview(f) }
    }
    required init?(coder: NSCoder) { fatalError() }
    private var needsClient: Bool { !draft.isOwnWork }
    private func typed(_ f: NSTextField) -> String { f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    override var firstField: NSView? { needsClient ? client : member }
    override var canContinue: Bool { !typed(member).isEmpty && (!needsClient || !typed(client).isEmpty) }
    override func arrive() {
        client.isHidden = !needsClient
        // Names given on the tree come back into the fields.
        if let c = draft.clients.first, typed(client) != c { client.stringValue = c }
        if let m = draft.members.first, typed(member) != m { member.stringValue = m }
        needsLayout = true; needsDisplay = true
    }

    override func layout() {
        super.layout()
        place(client, row: 12)
        place(member, row: needsClient ? 15 : 12)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "First Names", first: "Name your", second: "first ones")
        drawWords(needsClient ? "Your first \(draft.clientWord.lowercased()) and the first \(draft.memberWord.lowercased()) for it. They become real folders, named as you type them."
                              : "Your first \(draft.memberWord.lowercased()). It becomes a real folder, named as you type it.")
        var k = 11
        if needsClient {
            Design.attributed("First \(draft.clientWord)", .caption, colour: Design.quiet).draw(x: left, baseline: row(k))
            hairline(row: k + 1, live: client.currentEditor() != nil)
            k += 3
        }
        Design.attributed("First \(draft.memberWord)", .caption, colour: Design.quiet).draw(x: left, baseline: row(k))
        hairline(row: k + 1, live: member.currentEditor() != nil)
    }
    /// The names go to the draft as they are typed, so the tree shows them; a name cleared leaves the tree's placeholder.
    private func take() {
        let c = typed(client), m = typed(member)
        if needsClient { if c.isEmpty { if !draft.clients.isEmpty { draft.clients.removeFirst() } } else if draft.clients.isEmpty { draft.clients = [c] } else { draft.clients[0] = c } }
        else { draft.clients = [] }
        if m.isEmpty { if !draft.members.isEmpty { draft.members.removeFirst() } } else if draft.members.isEmpty { draft.members = [m] } else { draft.members[0] = m }
        splash?.changed()
    }
    override func commit() { take() }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { take() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if control === client { window?.makeFirstResponder(member) } else { splash?.go(to: index + 1) }
        return true
    }
}

/// Section 6: ready to set. The tree on the left is the whole answer; here it is said in words, caption and value, row by row.
final class SplashReady: SplashSection {
    private let draft: SplashDraft
    private let catalogueName: () -> String
    init(index: Int, draft: SplashDraft, catalogueName: @escaping () -> String) { self.draft = draft; self.catalogueName = catalogueName; super.init(index: index) }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { !draft.members.isEmpty && !draft.kinds.isEmpty && draft.who != nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "Ready", first: "Your tree,", second: "ready to set")
        drawWords("The tree on the left is what Set builds. Click a name there to change it, add another of anything, take any away; then Set. It is one step the history undoes.")
        let d = draft
        let levels = d.levelNames.isEmpty ? "None: the \(d.memberWord.lowercased())s sit straight in the collection" : d.levelNames.joined(separator: ", then ")
        let first = ((d.isOwnWork ? [] : d.clients.prefix(1).map { $0 }) + d.streams.prefix(1) + (d.kinds.count > 1 ? d.kinds.prefix(1).map { $0 } : []) + d.members.prefix(1)).joined(separator: "  \u{00B7}  ")
        let rows: [(String, String)] = [
            ("Catalogue", catalogueName()),
            ("Collection", d.collectionTitle),
            ("Levels", levels),
            ("First", first),
            ("Groups", d.groups.map { d.groupNames[$0] ?? $0 }.joined(separator: ", "))]
        for (i, r) in rows.enumerated() where !r.1.isEmpty {
            Design.attributed(r.0, .caption, colour: Design.quiet).draw(x: left, baseline: row(11 + i))
            Design.attributed(r.1, .body).draw(x: left + 120, baseline: row(11 + i), width: width - 120)
        }
    }
}
