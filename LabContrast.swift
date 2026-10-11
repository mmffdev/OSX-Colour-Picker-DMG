import AppKit

// ---------- cTools: Contrast ----------
//
// A text colour on a background: the WCAG ratio, what it passes, a one-press fix to the nearest
// shade that does pass, and a preview in the user's own words and fonts. The two colours are taken
// from a palette chosen out of the library. The maths lives in ColourScience.swift.

/// Everything the Contrast page is holding. Saved between launches; each change is one step to undo.
struct ContrastState: Codable, Equatable {
    var pair = ContrastPair(ink: "#1B1B1F", paper: "#FFFFFF")
    /// The palette the two colours are being picked from. nil is cLab's wheel.
    var palette: UUID?
    var heading = "Large Text"
    var body = "Small text has to work hardest. This is how a sentence in the text colour reads on the background."
    /// Font families for the two pieces of text; nil is the system font.
    var headingFont: String?
    var bodyFont: String?
    var goal = ContrastTarget.aa.rawValue
    /// The Typography palette pairings are being added to, and the pairing being edited, when there is one.
    var typography: UUID?
    var editing: UUID?
    /// Scored by APCA rather than the WCAG 2 ratio, and the Lc a fix should then reach. Absent in older saves.
    var apca: Bool?
    var apcaGoal: Double?

    var usesAPCA: Bool { apca ?? false }
    var lcGoal: Double { apcaGoal ?? APCAUse.body.minimum }
}

private func passColour(_ ok: Bool) -> NSColor { ok ? .systemGreen : .systemRed }

/// A square of one of the two colours. Pressing it makes it the one the next colour picked goes to.
private final class ChipButton: NSButton {
    var hex = "#000000" { didSet { needsDisplay = true } }
    var armed = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 2.5, dy: 2.5), xRadius: 5, yRadius: 5)
        (colorFromHex(hex) ?? .gray).setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.stroke()
        if armed {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6.5, yRadius: 6.5)
            ring.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }
}

/// What the pair is good enough for: three uses down the side, two levels across.
private final class ContrastTable: NSView {
    /// The two levels, and for each use whether each is met (nil = the level does not apply).
    var headers = ("AA", "AAA") { didSet { needsDisplay = true } }
    var rows: [(title: String, first: Bool?, second: Bool?)] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }
        let head: CGFloat = 16, row = (bounds.height - head) / CGFloat(rows.count)
        let firstX = bounds.width - 104, secondX = bounds.width - 50
        func put(_ text: String, _ x: CGFloat, _ y: CGFloat, _ colour: NSColor, weight: NSFont.Weight = .regular, size: CGFloat = 11.5) {
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour])
        }
        put(headers.0, firstX, 0, .secondaryLabelColor, weight: .semibold, size: 11)
        put(headers.1, secondX, 0, .secondaryLabelColor, weight: .semibold, size: 11)
        for (i, r) in rows.enumerated() {
            let y = head + CGFloat(i) * row
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
            let text = y + (row - 15) / 2
            put(r.title, 0, text, .labelColor)
            func verdict(_ ok: Bool?, _ x: CGFloat) {
                guard let ok = ok else { put("N/A", x, text, .tertiaryLabelColor); return }
                put(ok ? "Pass" : "Fail", x, text, passColour(ok), weight: .medium)
            }
            verdict(r.first, firstX)
            verdict(r.second, secondX)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? {
        func word(_ ok: Bool?) -> String { ok == nil ? "not applicable" : ok! ? "pass" : "fail" }
        return rows.map { "\($0.title): \(headers.0) \(word($0.first)), \(headers.1) \(word($0.second))" }.joined(separator: ". ")
    }
}

/// The colours of the chosen palette, then white and black. A press sends the colour to whichever
/// of Text Colour and Background is waiting for one.
private final class TargetSpectrum: NSView {
    var hexes: [String] = [] { didSet { needsDisplay = true } }
    var pair = ContrastPair(ink: "#000000", paper: "#FFFFFF") { didSet { needsDisplay = true } }
    var onPick: ((String) -> Void)?
    override var isFlipped: Bool { true }

    /// Each colour's box, with a gap before white and black.
    private var boxes: [(hex: String, rect: NSRect)] {
        let extras = ["#FFFFFF", "#000000"].filter { !hexes.contains($0) }
        let gap: CGFloat = extras.isEmpty || hexes.isEmpty ? 0 : 8
        let count = CGFloat(hexes.count + extras.count)
        guard count > 0 else { return [] }
        let each = min(34, (bounds.width - gap) / count)
        var out: [(String, NSRect)] = [], x: CGFloat = 0
        for (i, hex) in (hexes + extras).enumerated() {
            if i == hexes.count { x += gap }
            out.append((hex, NSRect(x: x.rounded(), y: 0, width: (x + each).rounded() - x.rounded(), height: bounds.height)))
            x += each
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, b) in boxes.enumerated() {
            // The palette's colours run together as one strip; white and black stand apart.
            let own = i < hexes.count
            let first = i == 0 || i == hexes.count, last = i == hexes.count - 1 || i == boxes.count - 1
            let path = NSBezierPath()
            path.appendRoundedRect(b.rect, xRadius: own && !first && !last ? 0 : 5, yRadius: own && !first && !last ? 0 : 5)
            (colorFromHex(b.hex) ?? .gray).setFill()
            path.fill()
            if b.hex == "#FFFFFF" || b.hex == "#000000" {
                NSColor.separatorColor.setStroke()
                NSBezierPath(roundedRect: b.rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5).stroke()
            }
            // T and B mark the two colours in use.
            let mark = b.hex == pair.ink ? "T" : b.hex == pair.paper ? "B" : nil
            if let mark = mark, b.rect.width >= 12 {
                let text = NSAttributedString(string: mark, attributes: [
                    .font: NSFont.systemFont(ofSize: TextSize.caption, weight: .bold), .foregroundColor: colorFromHex(readableText(on: b.hex)) ?? .white])
                text.draw(at: NSPoint(x: b.rect.midX - text.size().width / 2, y: b.rect.midY - text.size().height / 2))
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = boxes.first(where: { $0.rect.contains(p) }) { onPick?(hit.hex) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Colours of the chosen palette" }
}

/// Every palette in the library as a strip of its colours, in the sidebar's groups: Favourites,
/// each project, then Palettes. A press on a palette chooses it; a press on a group's heading
/// opens or closes the group.
private final class PaletteShelf: NSView {
    enum Row {
        /// `key` names the group for remembering whether it is closed.
        case heading(String, key: String)
        /// nil is cLab's wheel.
        case palette(id: UUID?, name: String, hexes: [String])
    }
    var rows: [Row] = [] { didSet { needsDisplay = true } }
    /// The chosen palette; `.some(nil)` is cLab's wheel.
    var chosen: UUID?? { didSet { needsDisplay = true } }
    var onChoose: ((UUID?) -> Void)?
    /// A group opened or closed, so the list is a different height.
    var onResize: (() -> Void)?
    override var isFlipped: Bool { true }

    private func closedKey(_ key: String) -> String { "contrastShelfClosed.\(key)" }
    private func isClosed(_ key: String) -> Bool { AppPreferences.shared.bool(forKey: closedKey(key)) }

    private static let headingHeight: CGFloat = 24, rowHeight: CGFloat = 30
    /// Clear space under each group, held at the top of the next heading's row.
    private static let groupGap: CGFloat = 28
    /// Names and strips sit in from the edges, so the mark on the chosen row has room round them.
    private static let inset: CGFloat = 8

    var height: CGFloat { frames.last?.rect.maxY ?? 0 }

    private var frames: [(row: Row, rect: NSRect)] {
        var y: CGFloat = 0, hidden = false, out: [(Row, NSRect)] = []
        for (i, row) in rows.enumerated() {
            var h = PaletteShelf.rowHeight
            if case .heading(_, let key) = row {
                h = PaletteShelf.headingHeight + (i == 0 ? 0 : PaletteShelf.groupGap)
                hidden = isClosed(key)
            } else if hidden {
                continue   // inside a closed group
            }
            out.append((row, NSRect(x: 0, y: y, width: bounds.width, height: h)))
            y += h
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = PaletteShelf.inset, nameWidth = min(150, bounds.width * 0.42)
        for (row, rect) in frames where rect.intersects(dirtyRect) {
            switch row {
            case .heading(let title, let key):
                // The title sits at the foot of its row; any gap from the group above is over it.
                let top = rect.maxY - PaletteShelf.headingHeight
                // An arrow at the left, as in the sidebar: right when closed, down when open.
                let arrow = NSBezierPath(), mid = NSPoint(x: inset + 4, y: top + 13)
                if isClosed(key) {
                    arrow.move(to: NSPoint(x: mid.x - 2, y: mid.y - 4)); arrow.line(to: NSPoint(x: mid.x + 2, y: mid.y)); arrow.line(to: NSPoint(x: mid.x - 2, y: mid.y + 4))
                } else {
                    arrow.move(to: NSPoint(x: mid.x - 4, y: mid.y - 2)); arrow.line(to: NSPoint(x: mid.x, y: mid.y + 2)); arrow.line(to: NSPoint(x: mid.x + 4, y: mid.y - 2))
                }
                arrow.lineWidth = 1.5
                arrow.lineCapStyle = .round
                arrow.lineJoinStyle = .round
                // Headings and arrows as the sidebar has them: bold, in the full text colour.
                NSColor.labelColor.setStroke()
                arrow.stroke()
                (title as NSString).draw(at: NSPoint(x: inset + 14, y: top + 6), withAttributes: [
                    .font: SidebarOutlineView.headingFont, .foregroundColor: NSColor.labelColor])
            case .palette(let id, let name, let hexes):
                if let chosen = chosen, chosen == id {
                    NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
                }
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                (name as NSString).draw(in: NSRect(x: inset, y: rect.minY + 6, width: nameWidth - 8 - inset, height: 18), withAttributes: [
                    .font: NSFont.systemFont(ofSize: TextSize.body), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
                let strip = NSRect(x: nameWidth, y: rect.minY + 6, width: bounds.width - nameWidth - inset, height: rect.height - 12)
                guard !hexes.isEmpty else {
                    NSColor.tertiaryLabelColor.setStroke()
                    NSBezierPath(roundedRect: strip.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
                    continue
                }
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: strip, xRadius: 4, yRadius: 4).addClip()
                let each = strip.width / CGFloat(hexes.count)
                for (i, hex) in hexes.enumerated() {
                    let left = (strip.minX + CGFloat(i) * each).rounded()
                    let right = i == hexes.count - 1 ? strip.maxX : (strip.minX + CGFloat(i + 1) * each).rounded()
                    (colorFromHex(hex) ?? .clear).setFill()
                    NSRect(x: left, y: strip.minY, width: right - left, height: strip.height).fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = frames.first(where: { $0.rect.contains(p) }) else { return }
        switch hit.row {
        case .palette(let id, _, _): onChoose?(id)
        case .heading(_, let key):
            // The whole heading is the switch, arrow and name alike.
            guard p.y >= hit.rect.maxY - PaletteShelf.headingHeight else { return }
            AppPreferences.shared.set(!isClosed(key), forKey: closedKey(key))
            needsDisplay = true
            onResize?()
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Palettes in the library" }
}

/// The pair in use, in the user's own words and fonts: a heading, a passage, a button and an outline.
private final class ContrastPreview: NSView, NSTextFieldDelegate {
    /// Either piece of text was edited and the edit finished.
    var onText: ((_ heading: String, _ body: String) -> Void)?

    private var state = ContrastState()
    private let heading = NSTextField()
    private let body = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (field, tip, label) in [(heading, "Click To Type Your Own Heading", "Sample heading"), (body, "Click To Type Your Own Text", "Sample text")] {
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.delegate = self
            field.toolTip = tip
            field.setAccessibilityLabel(label)
            addSubview(field)
        }
        heading.cell?.usesSingleLineMode = true
        heading.lineBreakMode = .byTruncatingTail
        body.lineBreakMode = .byWordWrapping
        body.cell?.truncatesLastVisibleLine = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ new: ContrastState) {
        state = new
        let ink = colorFromHex(new.pair.ink) ?? .black
        heading.textColor = ink
        body.textColor = ink
        if heading.currentEditor() == nil { heading.stringValue = new.heading }
        if body.currentEditor() == nil { body.stringValue = new.body }
        needsLayout = true
        needsDisplay = true
    }

    private var pad: CGFloat { min(22, bounds.height * 0.14) }
    private var buttonBox: NSRect {
        let width = ("Button" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width + 28
        return NSRect(x: pad, y: bounds.height - pad - 26, width: width, height: 26)
    }
    /// The button and outline are dropped when there is no room for them under the heading.
    private var showsButton: Bool { bounds.height >= 120 }

    override func layout() {
        super.layout()
        let big = min(34, max(15, bounds.height * 0.2))
        heading.font = typeFont(family: state.headingFont, size: big, bold: true)
        body.font = typeFont(family: state.bodyFont, size: 13, bold: false)
        let width = bounds.width - pad * 2
        let headingHeight = ceil(heading.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 200)).height ?? big * 1.3)
        heading.frame = NSRect(x: pad, y: pad, width: width, height: headingHeight)
        let top = heading.frame.maxY + 4, floor = (showsButton ? buttonBox.minY : bounds.height - pad) - 8
        body.isHidden = floor - top < 16
        body.frame = NSRect(x: pad, y: top, width: width, height: max(0, floor - top))
    }

    override func draw(_ dirtyRect: NSRect) {
        let ink = colorFromHex(state.pair.ink) ?? .black, paper = colorFromHex(state.pair.paper) ?? .white
        paper.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12).stroke()
        guard showsButton else { return }

        let box = buttonBox
        ink.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        let label = NSAttributedString(string: "Button", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: paper])
        label.draw(at: NSPoint(x: box.minX + 14, y: box.minY + (26 - label.size().height) / 2))
        // An outline and a mark: the "graphics and controls" case.
        let ring = NSRect(x: box.maxX + 12, y: box.minY + 1, width: 24, height: 24)
        ink.setStroke()
        let circle = NSBezierPath(ovalIn: ring)
        circle.lineWidth = 2
        circle.stroke()
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: ring.minX + 6.5, y: ring.midY + 0.5))
        tick.line(to: NSPoint(x: ring.minX + 10.5, y: ring.midY + 4.5))
        tick.line(to: NSPoint(x: ring.minX + 17.5, y: ring.midY - 4))
        tick.lineWidth = 2
        tick.lineCapStyle = .round
        tick.lineJoinStyle = .round
        tick.stroke()
    }

    // The caret would otherwise be the window's text colour, which can vanish on the background.
    func controlTextDidBeginEditing(_ obj: Notification) {
        ((obj.object as? NSTextField)?.currentEditor() as? NSTextView)?.insertionPointColor = colorFromHex(state.pair.ink) ?? .black
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Emptied text goes back to what it was: a blank preview shows nothing.
        if heading.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { heading.stringValue = state.heading }
        if body.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body.stringValue = state.body }
        onText?(heading.stringValue, body.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            control.abortEditing()
            heading.stringValue = state.heading
            body.stringValue = state.body
            window?.makeFirstResponder(superview)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(superview)
            return true
        }
        return false
    }
}

/// Every pairing of the chosen palette's colours. Rows are the text colour, columns the background.
private final class ContrastGrid: NSView {
    var hexes: [String] = [] { didSet { needsDisplay = true } }
    var pair = ContrastPair(ink: "#000000", paper: "#FFFFFF") { didSet { needsDisplay = true } }
    var onPick: ((ContrastPair) -> Void)?
    /// Scored by APCA (Lc) rather than the WCAG 2 ratio.
    var apca = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    private func cell(_ row: Int, _ column: Int) -> NSRect {
        let n = CGFloat(max(hexes.count, 1))
        let w = bounds.width / n, h = bounds.height / n
        // Whole-point edges, so neighbours meet exactly.
        let left = (CGFloat(column) * w).rounded(), top = (CGFloat(row) * h).rounded()
        return NSRect(x: left, y: top, width: ((CGFloat(column) + 1) * w).rounded() - left, height: ((CGFloat(row) + 1) * h).rounded() - top)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !hexes.isEmpty else { return }
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        let size: CGFloat = min(bounds.height, bounds.width * 0.6) / CGFloat(hexes.count) < 20 ? 9.5 : 11
        for (r, ink) in hexes.enumerated() {
            for (c, paper) in hexes.enumerated() {
                let box = cell(r, c)
                (colorFromHex(paper) ?? .gray).setFill()
                box.fill()
                guard r != c else { continue }   // a colour on itself is nothing to read
                // The number is always readable; the dot beside it is the text colour being judged.
                let readable = colorFromHex(readableText(on: paper)) ?? .white
                let ratio = contrastRatio(ink, paper), lc = abs(apcaContrast(text: ink, background: paper))
                // Bold where body text passes, faint where nothing does.
                let label = apca ? String(Int(lc.rounded(.down))) : String(format: "%.1f", (ratio * 10 + 1e-9).rounded(.down) / 10)
                let strong = apca ? lc >= APCAUse.body.minimum : ratio >= 4.5, weak = apca ? lc < APCAUse.headline.minimum : ratio < 3
                let text = NSAttributedString(string: label, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: strong ? .semibold : .regular),
                    .foregroundColor: readable.withAlphaComponent(weak ? 0.5 : 1)])
                let dot: CGFloat = 7, width = dot + 4 + text.size().width
                if width <= box.width - 2 {
                    let x = box.midX - width / 2
                    (colorFromHex(ink) ?? .gray).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: box.midY - dot / 2, width: dot, height: dot)).fill()
                    text.draw(at: NSPoint(x: x + dot + 4, y: box.midY - text.size().height / 2))
                }
                if ink == pair.ink && paper == pair.paper {
                    readable.setStroke()
                    let mark = NSBezierPath(rect: box.insetBy(dx: 1.5, dy: 1.5))
                    mark.lineWidth = 2
                    mark.stroke()
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), n = hexes.count
        guard n > 0, bounds.contains(p) else { return }
        let row = min(Int(p.y / bounds.height * CGFloat(n)), n - 1), column = min(Int(p.x / bounds.width * CGFloat(n)), n - 1)
        if row != column { onPick?(ContrastPair(ink: hexes[row], paper: hexes[column])) }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Contrast of every pair in the palette" }
}

/// The left-hand column. It scrolls as one piece, so nothing is lost in a short window.
private final class ControlColumn: NSView {
    override var isFlipped: Bool { true }
}

final class ContrastViewController: NSViewController, NSTextFieldDelegate {
    private let library: LibraryController
    private(set) var state: ContrastState
    private var history = History<ContrastState>()
    /// Whether cLab's wheel is listed as a palette: only when the page was reached from cLab.
    private var offersWheel = false
    /// Which of the two colours the next colour picked goes to.
    private var arming = true   // true = text colour

    private var header: PageHeader!
    private var undo: NSButton!, redo: NSButton!, toType: NSButton!
    private let why = NSTextField(wrappingLabelWithString: "")
    private let saveBar: SaveBar

    private let scroll = LetGoScrollView()
    private let column = ControlColumn()
    private let inkLabel = caption("Text Colour", size: 11), paperLabel = caption("Background", size: 11)
    private let inkChip = ChipButton(), paperChip = ChipButton()
    private let inkField = NSTextField(), paperField = NSTextField()
    private var swap: NSButton!
    private let badge = NSTextField(labelWithString: "")
    private let method = ToggleBar(labels: ["WCAG 2", "APCA"])
    private let table = ContrastTable()
    private let goal = NSPopUpButton()
    private var fixInk: NSButton!, fixPaper: NSButton!
    private let from = NSPopUpButton()
    private let hint = caption("", size: 11)
    private let spectrum = TargetSpectrum()
    private var dropper: NSButton!
    private let shelf = PaletteShelf()
    /// The palettes scroll on their own, under the controls, so the controls stay in view.
    private let shelfScroll = LetGoScrollView()

    private let headingFont = NSPopUpButton(), bodyFont = NSPopUpButton()
    private let preview = ContrastPreview()
    private let gridTitle = caption("", size: 11)
    private let grid = ContrastGrid()
    private var sampler: NSColorSampler?

    private static let key = "contrastState"
    /// The grid stops being readable beyond this many colours a side.
    private static let gridMost = 8

    init(library: LibraryController) {
        self.library = library
        saveBar = SaveBar(library: library)
        state = AppPreferences.shared.data(forKey: ContrastViewController.key).flatMap { try? JSONDecoder().decode(ContrastState.self, from: $0) } ?? ContrastState()
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let page = ToolPageView(frame: NSRect(x: 0, y: 0, width: 700, height: 520))
        page.onLayout = { [weak self] in self?.arrange(in: $0) }
        view = page

        undo = toolButton("", "arrow.uturn.backward", "Undo", target: self, action: #selector(undoTapped))
        redo = toolButton("", "arrow.uturn.forward", "Redo", target: self, action: #selector(redoTapped))
        toType = toolButton("Add To Typography", "textformat", "Keep This Pairing, With Its Words And Fonts, In A Typography Palette", target: self, action: #selector(typographyTapped(_:)))
        // The note sits in the column under the fix buttons and wraps to whatever it needs.
        why.font = NSFont.systemFont(ofSize: TextSize.body)
        why.maximumNumberOfLines = 0
        why.lineBreakMode = .byWordWrapping
        method.controlSize = .small
        method.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        method.target = self
        method.action = #selector(methodChosen)
        method.toolTip = "How The Pair Is Scored: The WCAG 2 Ratio (The Standard), Or APCA (Drafted For WCAG 3)"
        method.setAccessibilityLabel("Scoring method")

        saveBar.colours = { [weak self] in self?.pairHexes ?? [] }
        saveBar.defaultName = { [weak self] in self?.defaultName ?? "" }
        saveBar.onNameChanged = { [weak self] in self?.publish() }

        for (chip, tip) in [(inkChip, "Take The Next Colour Picked As The Text Colour"), (paperChip, "Take The Next Colour Picked As The Background")] {
            chip.title = ""
            chip.isBordered = false
            chip.target = self
            chip.action = #selector(chipTapped(_:))
            chip.toolTip = tip
            chip.setAccessibilityLabel(tip)
        }
        for (field, label) in [(inkField, "Text colour hex"), (paperField, "Background hex")] {
            field.font = NSFont.monospacedSystemFont(ofSize: TextSize.body, weight: .regular)
            field.delegate = self
            field.cell?.usesSingleLineMode = true
            field.setAccessibilityLabel(label)
        }
        swap = symbolButton("arrow.left.arrow.right", tooltip: "Swap Text And Background", target: self, action: #selector(swapTapped))

        func small(_ popup: NSPopUpButton, _ tip: String, _ action: Selector) {
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            popup.target = self
            popup.action = action
            popup.toolTip = tip
            popup.setAccessibilityLabel(tip)
        }
        small(goal, "The Ratio A Fix Should Reach", #selector(goalChosen))
        func smallButton(_ title: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            b.toolTip = tip
            return b
        }
        fixInk = smallButton("Fix Text Colour", "Move The Text Colour To The Nearest Shade That Reaches The Target", #selector(fixInkTapped))
        fixPaper = smallButton("Fix Background", "Move The Background To The Nearest Shade That Reaches The Target", #selector(fixPaperTapped))

        small(from, "The Palette To Pick The Two Colours From", #selector(paletteChosen(_:)))
        from.autoenablesItems = false
        spectrum.onPick = { [weak self] in self?.take($0) }
        dropper = symbolButton("eyedropper", tooltip: "Pick From Screen", target: self, action: #selector(pickTapped))
        shelf.onChoose = { [weak self] id in self?.change { $0.palette = id } }
        shelf.onResize = { [weak self] in self?.view.needsLayout = true }

        let families = NSFontManager.shared.availableFontFamilies
        for (popup, tip, action) in [(headingFont, "Font For The Heading", #selector(headingFontChosen)), (bodyFont, "Font For The Text", #selector(bodyFontChosen))] {
            popup.addItem(withTitle: "System Font")
            popup.menu?.addItem(.separator())
            popup.addItems(withTitles: families)
            small(popup, tip, action)
        }
        preview.onText = { [weak self] heading, body in self?.change { $0.heading = heading; $0.body = body } }
        grid.onPick = { [weak self] pair in self?.change { $0.pair = pair } }

        for v in [inkLabel, paperLabel, inkChip, paperChip, inkField, paperField, swap, badge, method, table, goal, fixInk, fixPaper,
                  why, from, hint, spectrum, dropper, shelfScroll] as [NSView] { column.addSubview(v) }
        shelfScroll.documentView = shelf
        shelfScroll.hasVerticalScroller = true
        shelfScroll.drawsBackground = false
        shelfScroll.automaticallyAdjustsContentInsets = false
        shelfScroll.scrollerStyle = .overlay
        scroll.documentView = column
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.scrollerStyle = .overlay
        header = PageHeader(actions: [undo, redo, toType])
        header.title.stringValue = "Contrast"
        for v in [header, scroll, headingFont, bodyFont, preview, gridTitle, grid, saveBar] as [NSView] { page.addSubview(v) }
        refresh()
    }

    // MARK: Layout

    private func arrange(in b: NSRect) {
        let pad = PageStyle.side, bar: CGFloat = 28, gap: CGFloat = 14
        let w = b.width - pad * 2
        header.frame = NSRect(x: 0, y: view.safeAreaInsets.top, width: b.width, height: PageStyle.height)
        let foot = b.height - pad - bar
        saveBar.frame = NSRect(x: pad, y: foot, width: w, height: bar)
        let top = header.frame.maxY, bottom = foot - gap, height = bottom - top

        // The preview and grid take four fifths of what an even split would give them; the controls and palettes get the rest.
        let even = max(236, min(340, w * 0.42))
        // In a very large window neither side balloons: the parts keep a size that reads well and the rest is left clear.
        let left = min(620, w - 18 - (w - even - 18) * 0.8)
        scroll.frame = NSRect(x: pad, y: top, width: left, height: height)
        column.frame = NSRect(x: 0, y: 0, width: left, height: max(height, arrangeColumn(width: left, visible: height)))

        let rx = pad + left + 18, rw = max(60, min(1000, b.width - pad - rx))
        let half = (rw - 6) / 2
        headingFont.frame = NSRect(x: rx, y: top, width: half, height: 22)
        bodyFont.frame = NSRect(x: rx + half + 6, y: top, width: half, height: 22)
        let showsGrid = !grid.hexes.isEmpty
        let room = height - 28
        let previewHeight = min(420, showsGrid ? max(70, (room - 24) * 0.5) : room)
        preview.frame = NSRect(x: rx, y: top + 28, width: rw, height: previewHeight)
        gridTitle.isHidden = !showsGrid
        grid.isHidden = !showsGrid
        gridTitle.frame = NSRect(x: rx, y: preview.frame.maxY + 8, width: rw, height: 14)
        // A grid row is tall enough to read and click at 48 points; more is just colour.
        let gridHeight = min(CGFloat(max(grid.hexes.count, 1)) * 48, bottom - preview.frame.maxY - 26)
        grid.frame = NSRect(x: rx, y: preview.frame.maxY + 26, width: rw, height: max(30, gridHeight))
    }

    /// Places the left column's parts and returns the height they need. The palettes take the room
    /// left under the controls and scroll within it. Only when the window is too short for that do
    /// they run on at full length, and the whole column scrolls instead.
    private func arrangeColumn(width: CGFloat, visible: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        let group = (width - 28) / 2
        inkLabel.frame = NSRect(x: 0, y: y, width: group, height: 14)
        paperLabel.frame = NSRect(x: group + 28, y: y, width: group, height: 14)
        y += 18
        inkChip.frame = NSRect(x: 0, y: y - 1, width: 30, height: 26)
        inkField.frame = NSRect(x: 34, y: y + 1, width: group - 34, height: 22)
        swap.frame = NSRect(x: group + 4, y: y + 2, width: 20, height: 20)
        paperChip.frame = NSRect(x: group + 28, y: y - 1, width: 30, height: 26)
        paperField.frame = NSRect(x: group + 62, y: y + 1, width: group - 34, height: 22)
        y += 24 + 10

        method.sizeToFit()
        method.frame.origin = NSPoint(x: width - method.frame.width, y: y + 5)
        badge.frame = NSRect(x: 0, y: y, width: width - method.frame.width - 8, height: 30)
        y += 30 + 8
        // What the number means, right under the score and the WCAG 2 / APCA switch.
        why.preferredMaxLayoutWidth = width
        let noteHeight = why.intrinsicContentSize.height
        why.frame = NSRect(x: 0, y: y, width: width, height: noteHeight)
        y += noteHeight + 14
        table.frame = NSRect(x: 0, y: y, width: width, height: 88)
        y += 88 + 10
        goal.frame = NSRect(x: 0, y: y, width: width, height: 22)
        y += 26
        fixInk.frame = NSRect(x: 0, y: y, width: (width - 6) / 2, height: 22)
        fixPaper.frame = NSRect(x: (width + 6) / 2, y: y, width: (width - 6) / 2, height: 22)
        y += 22 + 28

        from.frame = NSRect(x: 0, y: y, width: width, height: 22)
        y += 26
        hint.frame = NSRect(x: 0, y: y, width: width, height: 14)
        y += 18
        spectrum.frame = NSRect(x: 0, y: y, width: width - 28, height: 28)
        dropper.frame = NSRect(x: width - 22, y: y + 4, width: 20, height: 20)
        y += 28 + 30
        let room = visible - y
        let fits = room >= 96
        shelfScroll.frame = NSRect(x: 0, y: y, width: width, height: fits ? room : shelf.height)
        shelfScroll.hasVerticalScroller = fits
        // The strips stop short of the edge, so the scroller has a lane of its own.
        shelf.frame = NSRect(x: 0, y: 0, width: width - (fits ? 16 : 0), height: max(shelf.height, fits ? room : 0))
        return fits ? visible : y + shelf.height + 4
    }

    // MARK: Showing

    /// The palette the two colours are picked from, as its colours.
    private var targetHexes: [String] {
        if let id = state.palette, library.library.swatch(id) != nil { return library.hexes(in: id) }
        return offersWheel ? library.labPalette?.colours.map { $0.hex } ?? [] : []
    }

    /// Called on arriving at the page. Coming from cLab, its wheel is offered as a palette and
    /// chosen; coming from anywhere else it is not shown, and nothing is chosen until the user picks.
    func arrive(fromLab: Bool) {
        offersWheel = fromLab
        if fromLab, state.palette != nil { state.palette = nil; save() }
        if isViewLoaded { refresh() }
    }
    private var pairHexes: [String] { state.pair.ink == state.pair.paper ? [state.pair.ink] : [state.pair.ink, state.pair.paper] }
    private var defaultName: String { "\(colourName(state.pair.ink)) On \(colourName(state.pair.paper))" }

    private func publish() {
        library.contrastPalette = ExportPalette(name: saveBar.chosenName, colours: pairHexes.map { ExportColour(name: colourName($0), hex: $0) })
    }

    /// Call when the library has changed: palettes may have come, gone or been renamed.
    func reload() {
        guard isViewLoaded else { return }
        if let id = state.palette, library.library.swatch(id) == nil { state.palette = nil }
        if let id = state.typography, library.library.swatch(id)?.isTypography != true { state.typography = nil; state.editing = nil }
        refresh()
    }

    private func refresh() {
        publish()
        guard isViewLoaded else { return }
        let pair = state.pair, ratio = pair.ratio, lib = library.library
        inkChip.hex = pair.ink
        paperChip.hex = pair.paper
        inkChip.armed = arming
        paperChip.armed = !arming
        if inkField.currentEditor() == nil { inkField.stringValue = pair.ink }
        if paperField.currentEditor() == nil { paperField.stringValue = pair.paper }

        // The score, what it is good for, and what a fix can aim at, by whichever method is chosen.
        let apca = state.usesAPCA, lc = abs(apcaContrast(text: pair.ink, background: pair.paper))
        let score: String, grade: String, colour: NSColor, met: Bool
        if apca {
            let best = APCAUse.best(for: lc)
            score = "Lc \(Int(lc.rounded(.down)))"   // cut, not rounded, as with the ratio
            grade = best?.title ?? "Fail"
            colour = best == .body ? .systemGreen : best == nil ? .systemRed : .systemOrange
            met = lc >= state.lcGoal
            table.headers = ("Least", "Ideal")
            table.rows = APCAUse.allCases.map { ($0.title, lc >= $0.minimum, lc >= $0.preferred) }
        } else {
            score = ContrastPair.text(ratio)
            grade = ["AAA": "AAA", "AA": "AA", "AA large": "AA Large", "fail": "Fail"][contrastGrade(ratio)] ?? ""
            colour = ratio >= 4.5 ? .systemGreen : ratio >= 3 ? .systemOrange : .systemRed
            met = ratio >= state.goal
            table.headers = ("AA", "AAA")
            table.rows = ContrastUse.allCases.map { use in (use.title, ratio >= use.aa, use.aaa.map { ratio >= $0 }) }
        }
        let text = NSMutableAttributedString(string: score, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(string: "   " + grade, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: colour]))
        badge.attributedStringValue = text
        badge.setAccessibilityLabel(apca ? "APCA lightness contrast \(Int(lc.rounded(.down))), \(grade)" : "Contrast ratio \(ContrastPair.text(ratio)), \(grade)")
        method.selectedSegment = apca ? 1 : 0

        goal.removeAllItems()
        let targets: [(title: String, value: Double)] = apca ? APCAUse.allCases.map { ($0.target, $0.minimum) } : ContrastTarget.allCases.map { ($0.title, $0.rawValue) }
        for t in targets {
            goal.addItem(withTitle: t.title)
            goal.lastItem?.representedObject = t.value
        }
        goal.selectItem(at: targets.firstIndex { $0.value == (apca ? state.lcGoal : state.goal) } ?? 0)
        // Nothing to fix once the target is met.
        fixInk.isEnabled = !met
        fixPaper.isEnabled = !met

        // The note under the score says what the number means and, for APCA, where it stands.
        let lead = apca ? "APCA  " : "WCAG 2  "
        let rest = apca
            ? "Lc scores how readable the text is, from 0 to about 106, and knows light-on-dark from dark-on-light. APCA is drafted for WCAG 3 and is not yet a standard: audits, contracts and accessibility law still ask for the WCAG 2 ratio."
            : "The ratio compares how light two colours are, from 1 (the same) to 21 (black on white). It is the standard that audits, contracts and accessibility law ask for. Body text needs 4.5; large text, icons and controls need 3."
        let note = NSMutableAttributedString(string: lead, attributes: [.font: NSFont.systemFont(ofSize: TextSize.body, weight: .semibold), .foregroundColor: NSColor.labelColor])
        note.append(NSAttributedString(string: rest, attributes: [.font: NSFont.systemFont(ofSize: TextSize.body), .foregroundColor: NSColor.secondaryLabelColor]))
        why.attributedStringValue = note
        view.needsLayout = true
        grid.apca = apca

        // The palette menu and the shelf below it list the same things, in the sidebar's groups:
        // cLab's wheel, Favourites, each project's palettes, then every palette.
        var rows: [PaletteShelf.Row] = []
        from.removeAllItems()
        // Items are made by hand: a pop-up button asked to add a title it already has replaces the first one.
        func offer(_ id: UUID?, _ name: String, indent: Int) {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = id
            item.indentationLevel = indent
            item.tag = 1
            from.menu?.addItem(item)
            rows.append(.palette(id: id, name: name, hexes: id.map { library.hexes(in: $0) } ?? library.labPalette?.colours.map { $0.hex } ?? []))
        }
        func group(_ title: String, key: String, _ palettes: [Swatch]) {
            let colours = palettes.filter { !$0.isTypography }   // colours are picked from palettes of colours
            guard !colours.isEmpty else { return }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if from.numberOfItems > 0 { from.menu?.addItem(.separator()) }
            from.menu?.addItem(item)
            rows.append(.heading(title, key: key))
            for s in colours { offer(s.id, s.name, indent: 1) }
        }
        if offersWheel, library.labPalette != nil {
            offer(nil, "Colour Lab Wheel", indent: 0)
        } else {
            // Shown in the menu while no palette is chosen.
            let none = NSMenuItem(title: "Choose A Palette", action: nil, keyEquivalent: "")
            none.isEnabled = false
            from.menu?.addItem(none)
        }
        group("Favourites", key: "favourites", library.favourites)
        for p in lib.orderedProjects { group(p.name, key: "project.\(p.id.uuidString)", lib.palettes(in: p.id)) }
        group("Palettes", key: "palettes", lib.listedPalettes)
        let chosen = from.itemArray.first { $0.tag == 1 && ($0.representedObject as? UUID) == state.palette }
        from.select(chosen ?? from.item(at: 0))
        shelf.rows = rows
        shelf.chosen = chosen == nil ? nil : .some(state.palette)

        let target = targetHexes
        spectrum.hexes = target
        spectrum.pair = pair
        hint.stringValue = "Click A Colour To Set The \(arming ? "Text Colour" : "Background")"

        // A font this Mac does not have keeps its name in the menu, marked, so it is never silently dropped.
        func choose(_ popup: NSPopUpButton, _ family: String?) {
            if let stale = popup.menu?.item(withTag: 99) { popup.menu?.removeItem(stale) }
            guard let family = family else { popup.selectItem(at: 0); return }
            if popup.itemTitles.contains(family) { popup.selectItem(withTitle: family); return }
            let item = NSMenuItem(title: "\(family)  \u{2014}  Missing", action: nil, keyEquivalent: "")
            item.tag = 99
            item.representedObject = family
            popup.menu?.insertItem(item, at: 1)
            popup.select(item)
        }
        choose(headingFont, state.headingFont)
        choose(bodyFont, state.bodyFont)
        preview.show(state)

        let shown = Array(target.prefix(ContrastViewController.gridMost))
        grid.hexes = shown.count > 1 ? shown : []
        grid.pair = pair
        gridTitle.stringValue = target.count > shown.count ? "Compare The First \(shown.count) Colours" : "Compare Entire Palette"
        gridTitle.toolTip = "Rows Are The Text Colour, Columns Are The Background. Click A Cell To Check That Pair"
        grid.toolTip = gridTitle.toolTip

        saveBar.refresh()
        undo.isEnabled = history.canUndo
        redo.isEnabled = history.canRedo
        view.needsLayout = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { AppPreferences.shared.set(data, forKey: ContrastViewController.key) }
    }

    /// One change, one step to undo.
    private func change(_ body: (inout ContrastState) -> Void) {
        let before = state
        body(&state)
        history.record(before, now: state)
        save()
        refresh()
    }

    // MARK: Actions

    /// A colour picked from the spectrum or the screen goes to whichever colour is waiting, and the other waits next.
    private func take(_ hex: String) {
        guard let clean = sRGBHex(hex) else { return }   // a colour kept under a key is taken as the sRGB it shows as
        let toInk = arming
        arming.toggle()
        change { if toInk { $0.pair.ink = clean } else { $0.pair.paper = clean } }
    }

    @objc private func chipTapped(_ sender: NSButton) {
        arming = sender === inkChip
        refresh()
    }

    @objc private func swapTapped() { change { $0.pair = $0.pair.swapped } }
    @objc private func goalChosen() {
        guard let value = goal.selectedItem?.representedObject as? Double else { return }
        change { if $0.usesAPCA { $0.apcaGoal = value } else { $0.goal = value } }
    }
    @objc private func methodChosen() { change { $0.apca = method.selectedSegment == 1 } }
    @objc private func paletteChosen(_ sender: NSPopUpButton) {
        let id = sender.selectedItem?.representedObject as? UUID
        change { $0.palette = id }
    }
    private func family(_ popup: NSPopUpButton) -> String? {
        guard popup.indexOfSelectedItem > 0, let item = popup.selectedItem else { return nil }
        return item.tag == 99 ? item.representedObject as? String : item.title
    }
    @objc private func headingFontChosen() { change { $0.headingFont = family(headingFont) } }
    @objc private func bodyFontChosen() { change { $0.bodyFont = family(bodyFont) } }

    // MARK: Typography palettes

    /// Opens a Typography palette's pairing for editing, or (nil) gets ready to add a new one to it.
    func edit(_ style: UUID?, in palette: UUID) {
        _ = view
        let found = library.library.swatch(palette)?.styles?.first { $0.id == style }
        change {
            $0.typography = palette
            $0.editing = found?.id
            guard let s = found else { return }
            $0.pair = ContrastPair(ink: s.ink, paper: s.paper)
            $0.heading = s.heading
            $0.body = s.body
            $0.headingFont = s.headingFont
            $0.bodyFont = s.bodyFont
        }
        if found == nil { library.flash("Choose Two Colours, Then Press Add To Typography") }
    }

    /// The pairing on screen, as it would be kept. `id` nil makes a new one.
    private func style(id: UUID?, name: String) -> TypeStyle {
        TypeStyle(id: id ?? UUID(), name: name, ink: state.pair.ink, paper: state.pair.paper, heading: state.heading, body: state.body,
                  headingFont: state.headingFont, bodyFont: state.bodyFont)
    }

    /// The pairing being edited, if it is still there.
    private var edited: (palette: Swatch, style: TypeStyle)? {
        guard let p = state.typography.flatMap({ library.library.swatch($0) }), let s = p.styles?.first(where: { $0.id == state.editing }) else { return nil }
        return (p, s)
    }

    @objc private func typographyTapped(_ sender: NSButton) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ object: Any? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
        }
        if let e = edited {
            add("Update \u{201C}\(e.style.name)\u{201D} In \(e.palette.name)", #selector(updateStyle))
            menu.addItem(.separator())
        }
        let sets = library.typographyOrder
        // The palette last added to comes first.
        if let current = sets.first(where: { $0.id == state.typography }) { add("Add To \(current.name)", #selector(addStyle(_:)), current.id) }
        for s in sets where s.id != state.typography { add("Add To \(s.name)", #selector(addStyle(_:)), s.id) }
        if !sets.isEmpty { menu.addItem(.separator()) }
        add("Add To A New Typography Palette", #selector(addStyle(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func updateStyle() {
        guard let e = edited else { return }
        library.keep(style(id: e.style.id, name: e.style.name), in: e.palette.id)
    }

    @objc private func addStyle(_ sender: NSMenuItem) {
        let palette = library.keep(style(id: nil, name: ""), in: sender.representedObject as? UUID)
        // Further pairings go to the same palette; this one is done, so the next press adds another.
        state.typography = palette
        state.editing = nil
        save()
        refresh()
    }

    private func fix(ink: Bool) {
        let (mine, other) = ink ? (state.pair.ink, state.pair.paper) : (state.pair.paper, state.pair.ink)
        // APCA cares which colour is the text, so the test is put the right way round for the one being moved.
        let apca = state.usesAPCA, lcGoal = state.lcGoal, ratioGoal = state.goal
        let shade = nearestShade(of: mine) { candidate in
            guard apca else { return contrastRatio(candidate, other) >= ratioGoal }
            return abs(ink ? apcaContrast(text: candidate, background: other) : apcaContrast(text: other, background: candidate)) >= lcGoal
        }
        guard let shade = shade else {
            let want = apca ? "Lc \(Int(lcGoal))" : ContrastPair.text(ratioGoal)
            library.flash("No Shade Of \(mine) Reaches \(want) Against \(other). Try Fixing The \(ink ? "Background" : "Text Colour") Instead")
            return
        }
        change { if ink { $0.pair.ink = shade } else { $0.pair.paper = shade } }
    }
    @objc private func fixInkTapped() { fix(ink: true) }
    @objc private func fixPaperTapped() { fix(ink: false) }

    @objc private func pickTapped() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] colour in
            self?.sampler = nil
            if let hex = colour.flatMap(hexOf) { self?.take(hex) }
        }
    }

    @objc private func undoTapped() {
        guard let back = history.undo(from: state) else { return }
        state = back
        save()
        refresh()
    }

    @objc private func redoTapped() {
        guard let on = history.redo(from: state) else { return }
        state = on
        save()
        refresh()
    }

    // MARK: Typing a hex

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let ink = field === inkField, was = ink ? state.pair.ink : state.pair.paper
        guard let clean = normaliseHex(field.stringValue) else {
            field.stringValue = was   // not a colour: put back what was there
            return
        }
        field.stringValue = clean
        if clean != was { change { if ink { $0.pair.ink = clean } else { $0.pair.paper = clean } } }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            control.abortEditing()
            (control as? NSTextField)?.stringValue = control === inkField ? state.pair.ink : state.pair.paper
            view.window?.makeFirstResponder(view)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(view)
            return true
        }
        return false
    }
}
