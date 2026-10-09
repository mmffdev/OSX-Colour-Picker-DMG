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
// Sections are added as each is agreed with Rick. Agreed so far: the catalogue's name. The others
// stand as titled templates so the travel and the lighthouse can be judged.

final class StudioSplash: NSView {
    typealias A = Design.App
    /// Called when the splash has done its work and the app may show.
    var onDone: (() -> Void)?
    private let library: LibraryController
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
        sections = [SplashName(library: library),
                    SplashPlaceholder(index: 1, step: "Who It Is For", first: "Who is the", second: "work for?", words: "Clients, customers, contracts, or work of your own: the main bucket in your collection."),
                    SplashPlaceholder(index: 2, step: "Streams", first: "More than one", second: "stream of work?", words: "Web, print, design, video: each client's kinds of work, or one kind only."),
                    SplashPlaceholder(index: 3, step: "What You Make", first: "What do", second: "you make?", words: "Products, projects, ranges: the thing that holds your palettes."),
                    SplashPlaceholder(index: 4, step: "What Sits Inside", first: "What sits", second: "inside each one?", words: "Information, palettes, typography and tags, all on to start."),
                    SplashPlaceholder(index: 5, step: "First Names", first: "Name your", second: "first ones", words: "The first client, its streams, the first thing made: real folders, named as you type them."),
                    SplashPlaceholder(index: 6, step: "Your Tree", first: "Your tree,", second: "ready to set", words: "Everything you answered, as rail1 will show it. Change any name, add or take away, then Set.")]
        for s in sections { surface.addSubview(s) }
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

    private func settleButtons() {
        back.isEnabled = at > 0
        next.title = at == sections.count - 1 ? "Set" : "Continue"
        next.invalidateIntrinsicContentSize()
        needsLayout = true
    }
    @objc private func backPressed() { go(to: at - 1) }
    @objc private func nextPressed() {
        if at == sections.count - 1 {
            guard sections[at].canContinue else { NSSound.beep(); return }
            sections[at].commit()
            onDone?()
            return
        }
        go(to: at + 1)
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
    /// What may be typed into first when the section locks.
    var firstField: NSView? { nil }
    /// Whether the section's answer is given, so Continue may move on.
    var canContinue: Bool { true }
    /// Takes the section's answer, as Continue moves on from it.
    func commit() {}
    override var isFlipped: Bool { true }

    /// The baseline of row `k` of the beat, in the section's own coordinates.
    func row(_ k: Int) -> CGFloat { CGFloat(k) * A.unit + A.textBaseline }
    /// The top of row `k`, where its unit line is.
    func line(_ k: Int) -> CGFloat { CGFloat(k) * A.unit }
    func col(_ c: Int) -> CGFloat { A.column(c, in: bounds.width) }
    func span(_ a: Int, _ b: Int) -> CGFloat { A.span(a, b, in: bounds.width) }

    /// The section's label on row 1 and its two-tone question on rows 3 and 5, from column 7.
    func drawQuestion(index: Int, step: String, first: String, second: String) {
        Design.attributed(String(format: "%02d", index) + "  \u{00B7}  " + step, .label, colour: Design.quiet).draw(x: col(7), baseline: row(1))
        Design.attributed(first, .title).draw(x: col(7), baseline: row(3), width: span(7, 12))
        Design.attributed(second, .title, colour: Design.soft).draw(x: col(7), baseline: row(5), width: span(7, 12))
    }

    /// Words in the Lead from column 7, a box of three lines from row 7.
    func drawWords(_ s: String) {
        let font = Design.Text.lead.font(), p = NSMutableParagraphStyle()
        p.minimumLineHeight = A.unit; p.maximumLineHeight = A.unit
        let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: Design.quiet, .kern: Design.Text.lead.size * Design.Text.lead.tracking, .paragraphStyle: p])
        // A fixed line sets its glyphs at its foot: the box's top is where that puts the first baseline on row 7.
        let top = row(7) - (A.unit + font.descender)
        text.draw(with: NSRect(x: col(7), y: top, width: span(7, 12), height: A.unit * 3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Section 0: what the catalogue is called. Its name is its folder's name and its file's, so a rename moves both.
final class SplashName: SplashSection, NSTextFieldDelegate {
    private let library: LibraryController
    private let field = NSTextField(string: "")
    /// Where the field's text sits on its baseline: the offset from the field's top to the line the glyphs stand on.
    private static let fieldBaseline: CGFloat = 13

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        field.stringValue = library.catalogue
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Design.font(17, .regular)
        field.textColor = Design.ink
        field.delegate = self
        field.placeholderAttributedString = NSAttributedString(string: "A name for everything you make", attributes: [.font: Design.font(17, .regular), .foregroundColor: Design.soft])
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var firstField: NSView? { field }
    private var typed: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    override var canContinue: Bool { !typed.isEmpty }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: col(7) - 2, y: row(12) - Self.fieldBaseline - 4, width: span(7, 12) + 4, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(index: 0, step: "Your Catalogue", first: "What shall we", second: "call it?")
        drawWords("Everything you make lives in here: your collections, your clients and every palette. You can change the name whenever you like.")
        Design.attributed("Catalogue Name", .caption, colour: Design.quiet).draw(x: col(7), baseline: row(11))
        // The field's hairline on the unit line under its row, in ink while the name is being typed.
        (field.currentEditor() != nil ? Design.ink : Design.rule).setFill()
        NSRect(x: col(7), y: line(13), width: span(7, 12), height: 1).fill()
        Design.attributed("Its folder on disk takes the same name.", .caption, colour: Design.quiet).draw(x: col(7), baseline: row(14))
    }

    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { (superview?.superview?.superview as? StudioSplash)?.go(to: 1); return true }
        return false
    }

    /// The name taken: the catalogue renamed if it changed, folder and file alike.
    override func commit() {
        guard canContinue else { return }
        if typed != library.catalogue { library.rename(catalogue: library.catalogue, to: typed) }
        field.stringValue = library.catalogue
    }
}

/// A section not designed yet: its label, question and words, so the travel and the lighthouse can be judged.
final class SplashPlaceholder: SplashSection {
    private let index: Int, step: String, first: String, second: String, words: String
    init(index: Int, step: String, first: String, second: String, words: String) {
        (self.index, self.step, self.first, self.second, self.words) = (index, step, first, second, words)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(index: index, step: step, first: first, second: second)
        drawWords(words)
    }
}
