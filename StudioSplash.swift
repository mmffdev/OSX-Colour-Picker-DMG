import AppKit

// ---------- The splash: the work set up, one section at a time ----------
//
// The first time the app opens on a catalogue with no structure (TH-299), the splash covers the
// whole window. Nothing of the app shows but the wordmark, drawn by Logo exactly where the header
// draws it, column 1 on the header's baseline, so when the splash ends the mark has not moved.
//
// The lighthouse stands on the left, columns 1 to 6, and grows a level as each section locks. The
// sections travel on one tall surface on the right, columns 7 to 12: Continue moves the surface up
// one section, pushing the one in view up and out of the band's top edge as the next slides up under
// it and locks. Each section is exactly the band's height and draws on the window's columns and on
// the beat counted from the band's top, so a locked section leaves every baseline on the grid. Only
// the surface moves; nothing inside a section is animated on its own. One gesture, one section: a
// swipe, a wheel turn, Return or the down arrow moves exactly one, and a section whose answer is
// missing does not move on.
//
// Back and Continue are the splash's own, locked at the bottom right for every section, their foot
// as far from the window's foot as the wordmark's top is from its top.
//
// The seven sections: the catalogue's name; who the work is for; the streams of work; what is made;
// what sits inside each one; the first names; and the tree, a toy to rename, add to and take from
// until Set, which builds the collection, its levels and the first member as one change. The splash
// is never a lock: it opens again from the Schema page whenever wanted.

final class StudioSplash: NSView {
    typealias A = Design.App
    /// Called when the splash has done its work and the app may show.
    var onDone: (() -> Void)?
    private let library: LibraryController
    private let draft = SplashDraft()
    private let lighthouse = LighthouseView()
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
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        band.wantsLayer = true
        band.layer?.masksToBounds = true
        surface.wantsLayer = true
        addSubview(band)
        band.addSubview(surface)
        addSubview(lighthouse)
        let d = draft
        sections = [
            SplashName(index: 0, library: library),
            SplashChoice(index: 1, step: "Who It Is For", first: "Who is the", second: "work for?",
                         words: "The main bucket in your collection: a level for each client, customer or brand. Work of your own has no such level.",
                         options: SplashDraft.whoOptions, many: false, ownWord: true,
                         read: { d.who.map { [$0] } ?? [] }, write: { d.who = $0.first }),
            SplashChoice(index: 2, step: "Streams", first: "More than one", second: "stream of work?",
                         words: "Web, print, design, video: the kinds of work each one gets, as a level of its own. One kind of work needs no level.",
                         options: SplashDraft.streamOptions, many: true, ownWord: true, none: SplashDraft.oneKind,
                         read: { d.streamsAnswered && d.streams.isEmpty ? [SplashDraft.oneKind] : d.streams },
                         write: { d.streams = $0.filter { $0 != SplashDraft.oneKind }; d.streamsAnswered = true }),
            SplashChoice(index: 3, step: "What You Make", first: "What do", second: "you make?",
                         words: "The thing that holds your palettes, typography, information and tags.",
                         options: SplashDraft.makeOptions, many: false, ownWord: true,
                         read: { d.make.map { [$0] } ?? [] }, write: { d.make = $0.first }),
            SplashChoice(index: 4, step: "What Sits Inside", first: "What sits", second: "inside each one?",
                         words: "The groups of every one you make. All four to start; take any away here or on the tree.",
                         options: SchemaRole.allCases.map { $0.title }, many: true, ownWord: false,
                         read: { d.groups.map { $0.title } }, write: { chosen in d.groups = SchemaRole.allCases.filter { chosen.contains($0.title) } }),
            SplashNames(index: 5, draft: d),
            SplashTree(index: 6, draft: d)
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
        // The lighthouse on columns 1 to 6, from the band's top to the window's foot, its finial three units under the band's top.
        let right = A.column(6, in: w) + A.columnWidth(in: w) + A.gutter / 2
        lighthouse.frame = NSRect(x: 0, y: top, width: right, height: bounds.height - top)
        lighthouse.headroom = 3 * A.unit
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
            library.flash("Would set up \(draft.collectionTitle), \(schema.collections[0].levels.isEmpty ? "no level between" : schema.collections[0].levels.joined(separator: " then ")), \(plural(made.members.count, draft.memberWord.lowercased()))")
            go(to: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.travel + 0.1) { [weak self] in self?.lighthouse.set(level: 0, to: 1) }
            return
        }
        var schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
        var lib = library.library
        let made = draft.build(into: &schema, library: &lib)
        SchemaTrial.replace(schema)
        let built = lib
        library.apply("Set Up Structure") { $0 = built }
        library.flash("Set up \(draft.collectionTitle) with \(plural(made.members.count, SplashDraft.singular(draft.memberWord).lowercased()))")
        onDone?()
    }

    /// Moves the surface so section `i` locks in the band: up for a later section, down for an earlier one; the lighthouse follows.
    func go(to i: Int) {
        guard sections.indices.contains(i), i != at, !moving else { return }
        if i > at {
            guard sections[at].canContinue else { NSSound.beep(); return }
            sections[at].commit()
        }
        let was = at
        at = i
        sections[i].arrive()
        settleButtons()
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

    /// The Choice: capitals in one ink outline, the chosen cells filled ink, wrapping to the next row when the words run past the width. Returns the rows used.
    @discardableResult
    func strip(_ items: [String], on: (String) -> Bool, x: CGFloat, width: CGFloat, baseline b: CGFloat, pick: @escaping (String) -> Void) -> Int {
        let h: CGFloat = 22, capHeight = Design.Text.label.size * 0.714
        var rows: [[String]] = [[]], widths: [String: CGFloat] = [:], rowWidth: CGFloat = 0
        for s in items {
            let w = (Design.attributed(s, .label).size().width + 24).rounded()
            widths[s] = w
            if rowWidth + w > width, !rows[rows.count - 1].isEmpty { rows.append([]); rowWidth = 0 }
            rows[rows.count - 1].append(s); rowWidth += w
        }
        for (r, rowItems) in rows.enumerated() {
            let top = b - 16 + CGFloat(r) * A.unit, words = (top + h / 2 + capHeight / 2).rounded()
            var cx = x
            for s in rowItems {
                let w = widths[s] ?? 0, cell = NSRect(x: cx, y: top, width: w, height: h), chosen = on(s)
                if chosen { fill(cell, Design.ink) }
                Design.attributed(s, .label, colour: chosen ? Design.card : Design.ink).draw(x: cx + 12, baseline: words)
                hits.append((cell, { pick(s) }))
                cx += w
            }
            Design.ink.setStroke()
            let edge = NSBezierPath(rect: NSRect(x: x, y: top, width: cx - x, height: h).insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            var dx = x
            for s in rowItems.dropLast() { dx += widths[s] ?? 0; fill(NSRect(x: dx - 0.5, y: top, width: 1, height: h), Design.ink) }
        }
        return rows.count
    }

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

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = hits.first(where: { $0.0.contains(p) }) { window?.makeFirstResponder(splash); h.1(); return }
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) { hits = [] }
}

/// Section 0: what the catalogue is called. Its name is its folder's name and its file's, so a rename moves both.
final class SplashName: SplashSection, NSTextFieldDelegate {
    private let library: LibraryController
    private let field = SplashSection.field("A name for everything you make")

    init(index: Int, library: LibraryController) {
        self.library = library
        super.init(index: index)
        field.stringValue = library.catalogue
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
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { splash?.settleButtons() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { splash?.go(to: index + 1); return true }
        return false
    }
    /// The name taken: the catalogue renamed if it changed, folder and file alike.
    override func commit() {
        guard canContinue else { return }
        if typed != library.catalogue { library.rename(catalogue: library.catalogue, to: typed) }
        field.stringValue = library.catalogue
    }
}

/// A question answered by a Choice: one cell, or several; with a word of the user's own as well, when offered.
final class SplashChoice: SplashSection, NSTextFieldDelegate {
    private let step: String, first: String, second: String, words: String, options: [String], many: Bool, none: String?
    private let read: () -> [String], write: ([String]) -> Void
    private let own: NSTextField?

    init(index: Int, step: String, first: String, second: String, words: String, options: [String], many: Bool, ownWord: Bool, none: String? = nil,
         read: @escaping () -> [String], write: @escaping ([String]) -> Void) {
        (self.step, self.first, self.second, self.words, self.options, self.many, self.none, self.read, self.write) = (step, first, second, words, options, many, none, read, write)
        own = ownWord ? SplashSection.field("Or a word of your own") : nil
        super.init(index: index)
        if let f = own { f.delegate = self; addSubview(f) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { !read().isEmpty }
    private var ownWord: String { own?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    /// The user's own word, as the cells show it: capitalised, so it reads as the others do.
    private var ownCell: String? { ownWord.isEmpty ? nil : ownWord.prefix(1).uppercased() + ownWord.dropFirst() }
    private var stripRows = 1

    override func layout() {
        super.layout()
        if let f = own { place(f, row: 12 + stripRows) }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: step, first: first, second: second)
        drawWords(words)
        let chosen = read()
        let cells = options + (none.map { [$0] } ?? []) + (ownCell.map { options.contains($0) ? [] : [$0] } ?? [])
        let rows = strip(cells, on: { chosen.contains($0) }, x: left, width: width, baseline: row(11)) { [weak self] s in self?.pick(s) }
        if rows != stripRows { stripRows = rows; needsLayout = true }
        if let f = own {
            Design.attributed("Or A Word Of Your Own", .caption, colour: Design.quiet).draw(x: left, baseline: row(11 + stripRows))
            hairline(row: 12 + stripRows, live: f.currentEditor() != nil)
        }
    }
    private func pick(_ s: String) {
        var chosen = read()
        if s == none {
            chosen = [s]
        } else if many {
            chosen.removeAll { $0 == none }
            if let i = chosen.firstIndex(of: s) { chosen.remove(at: i) } else { chosen.append(s) }
        } else {
            chosen = chosen == [s] ? [] : [s]
        }
        write(chosen)
        needsDisplay = true
        splash?.settleButtons()
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) {
        // The word typed is a cell too, chosen as it is typed.
        var chosen = read().filter { options.contains($0) || $0 == none }
        if let w = ownCell { if many { chosen.removeAll { $0 == none }; chosen.append(w) } else { chosen = [w] } }
        write(chosen)
        needsDisplay = true
        splash?.settleButtons()
    }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { splash?.go(to: index + 1); return true }
        return false
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
    override func arrive() { client.isHidden = !needsClient; needsLayout = true; needsDisplay = true }

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
    override func commit() {
        draft.clients = needsClient ? [typed(client)] : []
        draft.members = [typed(member)]
    }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { splash?.settleButtons() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if control === client { window?.makeFirstResponder(member) } else { splash?.go(to: index + 1) }
        return true
    }
}

/// Section 6: the tree as rail1 will show it, a toy until Set: every name typed over where it is drawn, another of anything
/// added, any taken away. Each level carries a caption saying what it is, so the screen teaches the schema.
final class SplashTree: SplashSection {
    private let draft: SplashDraft
    private enum Kind { case collection, client(Int), stream(Int), member(Int), group(SchemaRole), addClient, addStream, addMember }
    private struct Line { let kind: Kind; let name: String; let depth: Int; let caption: String; let removable: Bool }

    init(index: Int, draft: SplashDraft) { self.draft = draft; super.init(index: index) }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { !draft.members.isEmpty && draft.make != nil && draft.who != nil }

    private func lines() -> [Line] {
        let d = draft
        var out: [Line] = [Line(kind: .collection, name: d.collectionTitle, depth: 0, caption: "Collection", removable: false)]
        func members(at depth: Int) {
            for (i, m) in d.members.enumerated() {
                out.append(Line(kind: .member(i), name: m, depth: depth, caption: d.memberWord, removable: d.members.count > 1))
                if i == 0 { for g in d.groups { out.append(Line(kind: .group(g), name: d.groupNames[g] ?? g.title, depth: depth + 1, caption: "Group", removable: d.groups.count > 1)) } }
            }
            out.append(Line(kind: .addMember, name: "Another \(d.memberWord.lowercased())", depth: depth, caption: "", removable: false))
        }
        func streams(at depth: Int) {
            for (j, s) in d.streams.enumerated() {
                out.append(Line(kind: .stream(j), name: s, depth: depth, caption: "Stream", removable: d.streams.count > 1))
                if j == 0 { members(at: depth + 1) }
            }
            out.append(Line(kind: .addStream, name: "Another stream", depth: depth, caption: "", removable: false))
        }
        if d.isOwnWork {
            if d.streams.isEmpty { members(at: 1) } else { streams(at: 1) }
        } else {
            for (i, c) in d.clients.enumerated() {
                out.append(Line(kind: .client(i), name: c, depth: 1, caption: d.clientWord, removable: d.clients.count > 1))
                if i == 0 { if d.streams.isEmpty { members(at: 2) } else { streams(at: 2) } }
            }
            out.append(Line(kind: .addClient, name: "Another \(d.clientWord.lowercased())", depth: 1, caption: "", removable: false))
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuestion(step: "Your Tree", first: "Your tree,", second: "ready to set")
        drawWords("As rail1 will show it. Click a name to change it, add another of anything, take any away; then Set. It is one step the history undoes.")
        let step: CGFloat = 20
        for (k, l) in lines().enumerated() {
            let b = row(11 + k), x = left + CGFloat(l.depth) * step
            let r = NSRect(x: left, y: line(11 + k), width: width, height: A.unit)
            switch l.kind {
            case .addClient, .addStream, .addMember:
                Design.attributed("+  " + l.name, .body, colour: Design.quiet).draw(x: x, baseline: b)
                hits.append((r, { [weak self] in self?.add(l.kind) }))
            default:
                // The tree's lines: a vertical from the parent and a short tick into the name.
                if l.depth > 0 {
                    fill(NSRect(x: x - step + 6, y: line(11 + k), width: 1, height: A.unit / 2), Design.rule)
                    fill(NSRect(x: x - step + 6, y: line(11 + k) + A.unit / 2, width: step - 10, height: 1), Design.rule)
                }
                let style: Design.Text = l.depth == 0 ? .bodyStrong : .body
                Design.attributed(l.name, style).draw(x: x, baseline: b, width: width - CGFloat(l.depth) * step - 140)
                Design.attributed(l.caption, .label, colour: Design.soft).draw(x: left + width - 120, baseline: b - 1)
                let nameRect = NSRect(x: x, y: line(11 + k), width: width - CGFloat(l.depth) * step - 140, height: A.unit)
                hits.append((nameRect, { [weak self] in self?.rename(l, x: x, baseline: b, width: nameRect.width, style: style) }))
                if l.removable {
                    let mark = NSRect(x: left + width - 24, y: line(11 + k), width: 24, height: A.unit)
                    Design.attributed("\u{00D7}", .body, colour: Design.quiet).draw(x: mark.minX + 8, baseline: b)
                    hits.append((mark, { [weak self] in self?.remove(l.kind) }))
                }
            }
        }
    }
    private func rename(_ l: Line, x: CGFloat, baseline: CGFloat, width: CGFloat, style: Design.Text) {
        let p = NSPoint(x: x, y: baseline)
        InlineName.edit(l.name, style: style, in: self, x: x, baseline: baseline, width: width, at: p) { [weak self] typed in
            guard let self = self, let t = typed?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { self?.needsDisplay = true; return }
            let d = self.draft
            switch l.kind {
            case .collection: d.collectionName = t
            case .client(let i): if d.clients.indices.contains(i) { d.clients[i] = t }
            case .stream(let j): if d.streams.indices.contains(j) { d.streams[j] = t }
            case .member(let i): if d.members.indices.contains(i) { d.members[i] = t }
            case .group(let g): d.groupNames[g] = t
            default: break
            }
            self.needsDisplay = true
            self.splash?.settleButtons()
        }
    }
    private func add(_ kind: Kind) {
        let d = draft
        switch kind {
        case .addClient: d.clients.append(uniqueName(d.clientWord + " 2", among: d.clients))
        case .addStream: d.streams.append(uniqueName("Stream 2", among: d.streams))
        case .addMember: d.members.append(uniqueName(d.memberWord + " 2", among: d.members))
        default: break
        }
        needsDisplay = true
        splash?.settleButtons()
    }
    private func remove(_ kind: Kind) {
        let d = draft
        switch kind {
        case .client(let i): if d.clients.count > 1, d.clients.indices.contains(i) { d.clients.remove(at: i) }
        case .stream(let j): if d.streams.count > 1, d.streams.indices.contains(j) { d.streams.remove(at: j) }
        case .member(let i): if d.members.count > 1, d.members.indices.contains(i) { d.members.remove(at: i) }
        case .group(let g): if d.groups.count > 1 { d.groups.removeAll { $0 == g } }
        default: break
        }
        needsDisplay = true
        splash?.settleButtons()
    }
}
