import AppKit

// ---------- The splash: the work set up, one section at a time ----------
//
// The first time the app opens on a catalogue with no structure (TH-299), the splash covers the
// whole window. Nothing of the app shows but the wordmark, drawn by Logo exactly where the header
// draws it, column 1 on the header's baseline, so when the splash ends the mark has not moved.
// Below the wordmark's band the sections travel on one tall surface: Continue moves the surface up
// one section, pushing the one in view up and out of the band's top edge as the next slides up under
// it and locks. Each section is exactly the band's height and draws on the window's twelve columns
// and on the beat counted from the band's top, so a locked section leaves every baseline on the
// grid. Only the surface moves; nothing inside a section is animated on its own. One gesture, one
// section: a swipe, a wheel turn, Return or the down arrow moves exactly one, and a section whose
// answer is missing does not move on.
//
// Sections are added as each is agreed with Rick. Agreed so far: the catalogue's name. The second,
// who the work is for, stands as a placeholder so the move between them can be judged.

final class StudioSplash: NSView {
    typealias A = Design.App
    /// Called when the splash has done its work and the app may show.
    var onDone: (() -> Void)?
    private let library: LibraryController
    private let band = SplashBand()
    private let surface = SplashBand()
    private var sections: [SplashSection] = []
    private(set) var at = 0
    private var moving = false
    private var lastWheel = Date.distantPast
    /// The band starts one point under the header's height, where the app's beat starts.
    static var bandTop: CGFloat { A.header + 1 }
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
        let name = SplashName(library: library)
        let who = SplashPlaceholder(index: 1, step: "Who It Is For", first: "Who is the", second: "work for?",
                                    words: "Clients, customers, contracts, or work of your own. This section is designed next.")
        sections = [name, who]
        for (i, s) in sections.enumerated() {
            s.onContinue = { [weak self] in self?.go(to: i + 1) }
            s.onBack = { [weak self] in self?.go(to: i - 1) }
            surface.addSubview(s)
        }
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
        let top = Self.bandTop, h = bounds.height - top
        band.frame = NSRect(x: 0, y: top, width: bounds.width, height: h)
        if !moving { surface.frame = NSRect(x: 0, y: -CGFloat(at) * h, width: bounds.width, height: h * CGFloat(sections.count)) }
        for (i, s) in sections.enumerated() { s.frame = NSRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h) }
    }

    /// The first thing to type into, once the splash is on screen.
    func begin() { window?.makeFirstResponder(sections.first?.firstField ?? self) }

    /// Moves the surface so section `i` locks in the band: up for a later section, down for an earlier one.
    func go(to i: Int) {
        guard sections.indices.contains(i), i != at, !moving else { return }
        if i > at, !sections[at].canContinue { NSSound.beep(); return }
        at = i
        let h = band.bounds.height
        let target = NSPoint(x: 0, y: -CGFloat(i) * h)
        window?.makeFirstResponder(sections[i].firstField ?? self)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Reduce Motion: no travel; the new section is simply there, after the shortest fade.
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
        case 125, 36, 76: sections[at].onContinue?()   // down, Return, Enter
        case 126: sections[at].onBack?()              // up
        default: super.keyDown(with: event)
        }
    }
    override func scrollWheel(with event: NSEvent) {
        // Momentum after a swipe is the same gesture still going: only the gesture itself, or a wheel's click, moves a section.
        guard event.momentumPhase.isEmpty, abs(event.scrollingDeltaY) > 3, Date().timeIntervalSince(lastWheel) > Self.travel + 0.15 else { return }
        lastWheel = Date()
        if event.scrollingDeltaY < 0 { sections[at].onContinue?() } else { sections[at].onBack?() }
    }
}

/// A flipped view, for the band the sections travel in and the surface that carries them.
final class SplashBand: NSView {
    override var isFlipped: Bool { true }
}

/// One section of the splash: as tall as the band, drawn on the window's columns and on the beat counted from the band's top.
class SplashSection: NSView {
    typealias A = Design.App
    var onContinue: (() -> Void)?
    var onBack: (() -> Void)?
    /// What may be typed into first when the section locks.
    var firstField: NSView? { nil }
    /// Whether the section's answer is given, so Continue may move on.
    var canContinue: Bool { true }
    override var isFlipped: Bool { true }

    /// The baseline of row `k` of the beat, in the section's own coordinates.
    func row(_ k: Int) -> CGFloat { CGFloat(k) * A.unit + A.textBaseline }
    /// The top of row `k`, where its unit line is.
    func line(_ k: Int) -> CGFloat { CGFloat(k) * A.unit }
    func col(_ c: Int) -> CGFloat { A.column(c, in: bounds.width) }
    func span(_ a: Int, _ b: Int) -> CGFloat { A.span(a, b, in: bounds.width) }

    /// The section's label and its two-tone question at columns 1 to 5: the label on row 3, the question's lines on rows 5 and 7.
    func drawQuestion(index: Int, step: String, first: String, second: String) {
        Design.attributed(String(format: "%02d", index) + "  \u{00B7}  " + step, .label, colour: Design.quiet).draw(x: col(1), baseline: row(3))
        Design.attributed(first, .title).draw(x: col(1), baseline: row(5), width: span(1, 5))
        Design.attributed(second, .title, colour: Design.soft).draw(x: col(1), baseline: row(7), width: span(1, 5))
    }

    /// Words in the Lead at columns 7 to 12, a box of three lines from row 5, the first on the question's first line.
    func drawWords(_ s: String) {
        let font = Design.Text.lead.font(), p = NSMutableParagraphStyle()
        p.minimumLineHeight = A.unit; p.maximumLineHeight = A.unit
        let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: Design.quiet, .kern: Design.Text.lead.size * Design.Text.lead.tracking, .paragraphStyle: p])
        // A fixed line sets its glyphs at its foot: the box's top is where that puts the first baseline on row 5.
        let top = row(5) - (A.unit + font.descender)
        text.draw(with: NSRect(x: col(7), y: top, width: span(7, 12), height: A.unit * 3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Back and Continue at the right margin, their bottoms on row 14's baseline.
    func placeActions(back: SwissButton?, next: SwissButton) {
        let right = col(12) + A.columnWidth(in: bounds.width)
        let nw = next.intrinsicContentSize.width
        next.frame = NSRect(x: right - nw, y: row(14) - next.intrinsicContentSize.height, width: nw, height: next.intrinsicContentSize.height)
        if let b = back {
            let bw = b.intrinsicContentSize.width
            b.frame = NSRect(x: next.frame.minX - A.gutter - bw, y: row(14) - b.intrinsicContentSize.height, width: bw, height: b.intrinsicContentSize.height)
        }
    }
}

/// Section 0: what the catalogue is called. Its name is its folder's name and its file's, so a rename moves both.
final class SplashName: SplashSection, NSTextFieldDelegate {
    private let library: LibraryController
    private let field = NSTextField(string: "")
    private let next = SwissButton("Continue", .primary)
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
        next.target = self
        next.action = #selector(continued)
        addSubview(next)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var firstField: NSView? { field }
    private var typed: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    override var canContinue: Bool { !typed.isEmpty }

    override func layout() {
        super.layout()
        field.frame = NSRect(x: col(7) - 2, y: row(10) - Self.fieldBaseline - 4, width: span(7, 12) + 4, height: 22)
        placeActions(back: nil, next: next)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(index: 0, step: "Your Catalogue", first: "What shall we", second: "call it?")
        drawWords("Everything you make lives in here: your collections, your clients and every palette. You can change the name whenever you like.")
        Design.attributed("Catalogue Name", .caption, colour: Design.quiet).draw(x: col(7), baseline: row(9))
        // The field's hairline on the unit line under its row, in ink while the name is being typed.
        (field.currentEditor() != nil ? Design.ink : Design.rule).setFill()
        NSRect(x: col(7), y: line(11), width: span(7, 12), height: 1).fill()
        Design.attributed("Its folder on disk takes the same name.", .caption, colour: Design.quiet).draw(x: col(7), baseline: row(12))
    }

    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { next.isEnabled = canContinue }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { continued(); return true }
        return false
    }

    /// The name taken: the catalogue renamed if it changed, folder and file alike, then on to the next section.
    @objc private func continued() {
        guard canContinue else { NSSound.beep(); return }
        if typed != library.catalogue { library.rename(catalogue: library.catalogue, to: typed) }
        field.stringValue = library.catalogue
        onContinue?()
    }
}

/// A section not designed yet: its label and question, words saying so, Back, and a Continue that waits.
final class SplashPlaceholder: SplashSection {
    private let index: Int, step: String, first: String, second: String, words: String
    private let back = SwissButton("Back", .secondary)
    private let next = SwissButton("Continue", .primary)

    init(index: Int, step: String, first: String, second: String, words: String) {
        (self.index, self.step, self.first, self.second, self.words) = (index, step, first, second, words)
        super.init(frame: .zero)
        back.target = self; back.action = #selector(backed)
        next.isEnabled = false
        addSubview(back); addSubview(next)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { false }
    override func layout() { super.layout(); placeActions(back: back, next: next) }
    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(index: index, step: step, first: first, second: second)
        drawWords(words)
    }
    @objc private func backed() { onBack?() }
}
