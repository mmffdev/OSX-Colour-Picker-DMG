import AppKit

// ---------- Contrast, on the Studio window ----------
//
// A text colour on a background, drawn on the page's own columns and the 28 beat. Two Splits. The
// first: the pair, its score and what it passes, the target and the fixes on the left; the pair in
// the user's own words and fonts, the fonts, and the ways to keep it on the right. The second: the
// chosen palette's colours on the left; every pair of them scored on the right, across the block.
// The palette is chosen in rail2, which lists them as it does everywhere, a press choosing rather
// than opening. Every first-order header has its words in a box of three units; every second-order
// header sits on a rule; what is under them starts on one line across the page whatever the words
// say. The maths is the old page's (ColourScience.swift, ColourFormats.swift), and so is the state,
// kept under the same key, so the old window and this page hold one pair.

final class ContrastPage: NSView, PageSection, Overlay, NSTextFieldDelegate {
    var onResize: (() -> Void)?
    private let library: LibraryController
    private(set) var state: ContrastState
    private var history = History<ContrastState>()
    /// Whether the Lab's wheel is listed as a palette: only when the page was reached from the Lab.
    private(set) var offersWheel = false
    /// Which of the two colours the next colour picked goes to: true is the text colour.
    private var arming = true
    private var sampler: NSColorSampler?
    /// Every library colour as it is drawn, from its master; a colour not in the library is drawn from its hex.
    private var shade: [String: NSColor] = [:]
    private static let key = "contrastState"
    /// The grid stops being readable beyond this many colours a side.
    private static let gridMost = 8
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }

    // MARK: The rows, counted in units from the section's top

    private enum R {
        static let header = 0, help = 1, sub = 4
        static let fieldLabel = 5, field = 6, choice = 8, grade = 9, score = 10
        static let sub2 = 12, columns = 13, table = 14, addType = 16
        static let sub3 = 18, label3 = 19, value3 = 20, buttons = 22
        /// The second Split: the colours and every pair.
        static let lower = 24
        static var lowerSub: Int { lower + 4 }
        static var lowerRows: Int { lower + 5 }
    }

    // MARK: The views: the fields that take typing, and the buttons

    private let inkField = NSTextField(string: ""), paperField = NSTextField(string: ""), nameField = NSTextField(string: "")
    private let heading = NSTextField(string: ""), body = NSTextField(wrappingLabelWithString: "")
    private let fixInk = SwissButton("Fix Text Colour", .secondary), fixPaper = SwissButton("Fix Background", .secondary)
    private let toTypography = SwissButton("Add To Typography", .secondary)
    private let toPalette = SwissButton("Add To Palette", .secondary), toProject = SwissButton("Add To Project", .secondary)
    private let undoButton = SwissButton("Undo", .quiet), redoButton = SwissButton("Redo", .quiet)
    /// What a press on the drawn parts does, rebuilt with every drawing.
    private var hits: [(NSRect, () -> Void)] = []
    /// The rects the menus open under, kept from the drawing.
    private var targetRect = NSRect.zero, headingFontRect = NSRect.zero, bodyFontRect = NSRect.zero
    /// The menu open over the page, if any.
    private var dropped: SwissDropdown.MenuPanel?
    private var openRect: NSRect?

    init(library: LibraryController) {
        self.library = library
        state = preferences.data(forKey: ContrastPage.key).flatMap { try? JSONDecoder().decode(ContrastState.self, from: $0) } ?? ContrastState()
        super.init(frame: .zero)
        for (f, label) in [(inkField, "Text colour hex"), (paperField, "Background hex"), (nameField, "Palette name")] {
            f.isBordered = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = Design.font(17, .regular)
            f.textColor = Design.ink
            f.delegate = self
            f.cell?.usesSingleLineMode = true
            f.cell?.isScrollable = true
            f.setAccessibilityLabel(label)
            addSubview(f)
        }
        for (f, label) in [(heading, "Sample heading"), (body, "Sample text")] {
            f.isEditable = true
            f.isSelectable = true
            f.isBordered = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.delegate = self
            f.setAccessibilityLabel(label)
            addSubview(f)
        }
        heading.cell?.usesSingleLineMode = true
        heading.lineBreakMode = .byTruncatingTail
        body.lineBreakMode = .byWordWrapping
        body.cell?.truncatesLastVisibleLine = true
        for (b, action) in [(fixInk, #selector(fixInkTapped)), (fixPaper, #selector(fixPaperTapped)), (toTypography, #selector(typographyTapped)),
                            (toPalette, #selector(paletteTapped)), (toProject, #selector(projectTapped)), (undoButton, #selector(undoTapped)), (redoButton, #selector(redoTapped))] {
            b.target = self
            b.action = action
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: The state

    private func save() {
        if let data = try? JSONEncoder().encode(state) { preferences.set(data, forKey: ContrastPage.key) }
    }
    /// One change, one step to undo.
    private func change(_ body: (inout ContrastState) -> Void) {
        let before = state
        body(&state)
        history.record(before, now: state)
        save()
        refresh()
    }
    private var pairHexes: [String] { state.pair.ink == state.pair.paper ? [state.pair.ink] : [state.pair.ink, state.pair.paper] }
    private var defaultName: String { "\(colourName(state.pair.ink)) On \(colourName(state.pair.paper))" }
    private var chosenName: String {
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultName : typed
    }
    /// The pair as an exportable palette, kept on the controller so it can be shared like one.
    private func publish() {
        library.contrastPalette = ExportPalette(name: chosenName, colours: pairHexes.map { ExportColour(name: colourName($0), hex: $0) })
    }
    private func colour(_ hex: String) -> NSColor { shade[hex] ?? colorFromHex(hex) ?? Design.hex(hex) }
    /// A palette's colour as the sRGB hex the pair holds: a plain hex as it is, a colour key as the hex it shows as.
    private static func sRGB(_ key: String) -> String? { sRGBHex(key) }
    private func same(_ key: String, _ hex: String) -> Bool { Self.sRGB(key) == hex }

    /// Called on arriving at the page. From the Lab, its wheel is offered as a palette and chosen; from anywhere else it is not.
    func arrive(fromLab: Bool) {
        offersWheel = fromLab && library.labPalette != nil
        if fromLab, state.palette != nil { state.palette = nil; save() }
        refresh()
    }

    func reload() {
        let lib = library.library
        if let id = state.palette, lib.swatch(id) == nil { state.palette = nil }
        if let id = state.typography, lib.swatch(id)?.isTypography != true { state.typography = nil; state.editing = nil }
        refresh()
    }

    private func refresh() {
        shade = library.library.displayTable()
        publish()
        if inkField.currentEditor() == nil { inkField.stringValue = state.pair.ink }
        if paperField.currentEditor() == nil { paperField.stringValue = state.pair.paper }
        nameField.placeholderAttributedString = NSAttributedString(string: defaultName, attributes: [.font: Design.font(17, .regular), .foregroundColor: Design.soft])
        let ink = colour(state.pair.ink)
        heading.textColor = ink
        body.textColor = ink
        heading.font = typeFont(family: state.headingFont, size: 28, bold: true)
        body.font = typeFont(family: state.bodyFont, size: 13, bold: false)
        if heading.currentEditor() == nil { heading.stringValue = state.heading }
        if body.currentEditor() == nil { body.stringValue = state.body }
        let met = state.usesAPCA ? lc >= state.lcGoal : state.pair.ratio >= state.goal
        fixInk.isEnabled = !met
        fixPaper.isEnabled = !met
        undoButton.isEnabled = history.canUndo
        redoButton.isEnabled = history.canRedo
        needsLayout = true
        needsDisplay = true
        onResize?()
        tellRail()
    }

    private var lc: Double { abs(apcaContrast(text: state.pair.ink, background: state.pair.paper)) }

    // MARK: The palette, chosen in rail2

    /// Whether the Lab's wheel is listed: only after arriving from the Lab, while it has colours.
    var wheelOffered: Bool { offersWheel && library.labPalette != nil }
    /// Told when the palette chosen changes, so the rail can mark the row.
    var onPaletteChange: (() -> Void)?
    private var listed = ""
    private func tellRail() {
        let now = "\(state.palette?.uuidString ?? "wheel")/\(wheelOffered)"
        guard now != listed else { return }
        listed = now
        onPaletteChange?()
    }
    /// A row of rail2 pressed: a palette's row chooses it, the Lab's row the wheel. False for a place the page has no use for, which then opens.
    func pick(_ place: StudioFrame.Place) -> Bool {
        switch place {
        case .palette(let id):
            guard library.library.swatch(id) != nil else { return false }
            change { $0.palette = id }
        case .lab:
            guard wheelOffered else { return false }
            change { $0.palette = nil }
        default: return false
        }
        return true
    }

    // MARK: The palettes to pick from

    /// The palette the two colours are picked from, as its colours.
    private var targetHexes: [String] {
        if let id = state.palette, library.library.swatch(id) != nil { return library.hexes(in: id) }
        return offersWheel ? library.labPalette?.colours.map { $0.hex } ?? [] : []
    }
    private var targetName: String {
        if let id = state.palette, let s = library.library.swatch(id) { return s.name }
        return offersWheel ? "Colour Lab Wheel" : "No Palette Chosen"
    }

    // MARK: Geometry: the page's columns, the two blocks and their halves

    private struct Geometry {
        var cols: [CGFloat] = []
        var lx: CGFloat = 0, lw: CGFloat = 0, rx: CGFloat = 0, rw: CGFloat = 0
        /// The halves of each block, as (x, width): a and b on the left, c and d on the right.
        var a: (x: CGFloat, w: CGFloat) = (0, 0), b: (x: CGFloat, w: CGFloat) = (0, 0)
        var c: (x: CGFloat, w: CGFloat) = (0, 0), d: (x: CGFloat, w: CGFloat) = (0, 0)
        var card = NSRect.zero
        var tiles: [(hex: String, rect: NSRect)] = []
        var spectrumRows = 1
        var gridRow: Int?
        /// A cell of the grid: the block's width shared between the colours, whole units high, up to three and never taller than wide.
        var cell = NSSize.zero
        var gridHexes: [String] = []
        var height: CGFloat = 0
    }

    /// The page starts on a column's edge; its columns are the window's, every edge on the grid the overlay draws.
    private func geometry(width: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u, gut = Design.App.gutter
        let cw = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        let n = max(2, Int(((width + gut) / (cw + gut)).rounded()))
        g.cols = (0..<n).map { (CGFloat($0) * (cw + gut)).rounded() }
        func span(_ count: Int) -> CGFloat { (CGFloat(count) * cw + CGFloat(count - 1) * gut).rounded() }
        let k = n / 2, rk = n - k, h = max(1, k / 2), rh = max(1, rk / 2)
        g.lx = 0; g.lw = span(k); g.rx = g.cols[k]; g.rw = span(rk)
        g.a = (g.cols[0], span(h)); g.b = (g.cols[k - h], span(h))
        g.c = (g.cols[k], span(rh)); g.d = (g.cols[n - rh], span(rh))
        // The sample: from the rule under its header, as the grid and the Lab's blocks meet theirs, to the score's line, so its
        // bottom edge and the numeral's baseline are one line across the Split.
        g.card = NSRect(x: g.rx, y: CGFloat(R.fieldLabel) * u, width: g.rw, height: CGFloat(R.score) * u + Self.line - CGFloat(R.fieldLabel) * u)

        // The second Split: the chosen palette's colours on the left; every pair of them scored on the right, across the block.
        let hexes = targetHexes, extras = ["#FFFFFF", "#000000"].filter { !hexes.contains($0) }
        let perRow = max(1, Int((g.lw + 4) / 28))
        var slots: [String?] = hexes.map { $0 }
        if !hexes.isEmpty && !extras.isEmpty { slots.append(nil) }
        slots += extras.map { $0 }
        for (i, s) in slots.enumerated() {
            guard let hex = s else { continue }
            g.tiles.append((hex, NSRect(x: g.lx + CGFloat(i % perRow) * 28, y: CGFloat(R.lowerRows + i / perRow) * u + 4, width: 24, height: 24)))
        }
        g.spectrumRows = max(1, (slots.count + perRow - 1) / perRow)
        let shown = Array(hexes.prefix(Self.gridMost))
        var end = CGFloat(R.lowerRows + g.spectrumRows) * u
        if shown.count > 1 {
            g.gridHexes = shown
            g.gridRow = R.lowerRows
            let n = CGFloat(shown.count), w = (g.rw / n).rounded(.down)
            g.cell = NSSize(width: w, height: min(3 * u, max(u, (w / u).rounded(.down) * u)))
            end = max(end, CGFloat(g.gridRow!) * u + n * g.cell.height)
        }
        g.height = max(end, CGFloat(R.lowerRows + 2) * u) + 2 * u
        return g
    }

    func height(forWidth width: CGFloat) -> CGFloat { geometry(width: width).height }

    // MARK: Layout: the fields and buttons, each on its row's line

    /// Puts a view so the baseline of its words sits on a row's line.
    private func place(_ v: NSView, x: CGFloat, row: Int, width: CGFloat, height: CGFloat? = nil) {
        let h = height ?? v.fittingSize.height
        // Measured from a capture: a borderless field at 17 Helvetica Neue puts its baseline 13 below its top, three less than it reports.
        let base = v === inkField || v === paperField || v === nameField ? Self.fieldBaseline : v.firstBaselineOffsetFromTop
        v.frame = NSRect(x: x, y: CGFloat(row) * Self.u + Self.line - base, width: width, height: h)
    }
    private static let fieldBaseline: CGFloat = 13

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width), u = Self.u
        // The hex: after the square and a step, short of the swap mark at the right of the first half.
        place(inkField, x: g.a.x + 28 - 2, row: R.field, width: g.a.w - 28 - 28)
        place(paperField, x: g.b.x + 28 - 2, row: R.field, width: g.b.w - 28)
        place(nameField, x: g.rx - 2, row: R.value3, width: g.rw + 2)
        for (button, x, w, row) in [(fixInk, g.a.x, g.a.w, R.buttons), (fixPaper, g.b.x, g.b.w, R.buttons), (toPalette, g.c.x, g.c.w, R.buttons),
                                    (toProject, g.d.x, g.d.w, R.buttons), (toTypography, g.c.x, g.c.w, R.addType)] {
            button.fixedWidth = w
            place(button, x: x, row: row, width: w, height: SwissButton.height)
        }
        let redoW = redoButton.intrinsicContentSize.width, undoW = undoButton.intrinsicContentSize.width
        place(redoButton, x: g.rx + g.rw - redoW, row: R.header, width: redoW, height: SwissButton.height)
        place(undoButton, x: g.rx + g.rw - redoW - 16 - undoW, row: R.header, width: undoW, height: SwissButton.height)
        // The sample's words: the heading on the card's second line, the sentence on the two after, over the button.
        let pad: CGFloat = 16, card = g.card
        place(heading, x: card.minX + pad - 2, row: R.field, width: card.width - 2 * pad + 4, height: 36)
        let top = CGFloat(R.field + 1) * u + Self.line - body.firstBaselineOffsetFromTop
        body.frame = NSRect(x: card.minX + pad - 2, y: top, width: card.width - 2 * pad + 4, height: card.maxY - pad - 24 - 8 - top)
    }

    // MARK: Drawing

    private func label(_ s: String, x: CGFloat, row: Int) { Design.attributed(s, .label, colour: Design.quiet).draw(x: x, baseline: CGFloat(row) * Self.u + Self.line) }
    private func words(_ s: String, x: CGFloat, width: CGFloat) {
        Design.attributed(s, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: x, y: CGFloat(R.help) * Self.u, width: width, height: 3 * Self.u))
    }
    /// A second-order header: its word on the row's line, the rule under the row.
    private func subheader(_ s: String, x: CGFloat, width: CGFloat, row: Int) {
        Design.attributed(s, .header).draw(x: x, baseline: CGFloat(row) * Self.u + Self.line, width: width)
        hairline(x: x, y: CGFloat(row + 1) * Self.u - 1, width: width, Design.rule)
    }
    private func value(_ s: String, colour: NSColor = Design.ink) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: Design.font(17, .regular), .foregroundColor: colour])
    }
    /// The chevron at the right of a dropdown, on the line; turned up while its menu is open.
    private func chevron(right: CGFloat, baseline b: CGFloat, open: Bool) {
        Design.quiet.setStroke()
        let p = NSBezierPath(); p.lineWidth = 1
        let y0 = open ? b - 2 : b - 6, y1 = open ? b - 6 : b - 2
        p.move(to: NSPoint(x: right - 9, y: y0)); p.line(to: NSPoint(x: right - 5, y: y1)); p.line(to: NSPoint(x: right - 1, y: y0))
        p.stroke()
    }
    /// A dropdown as the guide draws one: the label above, the value at 17 on the line under it, the chevron right, a hairline beneath.
    @discardableResult
    private func dropdown(_ title: String, value v: String, x: CGFloat, width: CGFloat, row: Int, act: @escaping () -> Void) -> NSRect {
        let u = Self.u, b = CGFloat(row + 1) * u + Self.line
        label(title, x: x, row: row)
        let r = NSRect(x: x, y: CGFloat(row) * u, width: width, height: 2 * u)
        let open = openRect == r
        value(v).draw(x: x, baseline: b, width: width - 24)
        chevron(right: x + width, baseline: b, open: open)
        hairline(x: x, y: CGFloat(row + 2) * u - 1, width: width, open ? Design.ink : Design.rule)
        hits.append((r, act))
        return r
    }
    /// The Choice: capitals in a one-point ink outline, the chosen cell filled ink, its words on the line.
    private func choice(_ items: [String], chosen: Int, x: CGFloat, baseline b: CGFloat, pick: @escaping (Int) -> Void) {
        var cx = x
        let top = b - 16, h: CGFloat = 22
        for (i, s) in items.enumerated() {
            let on = i == chosen
            let t = Design.attributed(s, .label, colour: on ? Design.card : Design.ink)
            let w = (t.size().width + 24).rounded()
            let cell = NSRect(x: cx, y: top, width: w, height: h)
            if on { fill(cell, Design.ink) }
            t.draw(x: cx + 12, baseline: b)
            hits.append((cell, { pick(i) }))
            cx += w
        }
        Design.ink.setStroke()
        let edge = NSBezierPath(rect: NSRect(x: x, y: top, width: cx - x, height: h).insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
        var dx = x
        for s in items.dropLast() { dx += (Design.attributed(s, .label).size().width + 24).rounded(); fill(NSRect(x: dx - 0.5, y: top, width: 1, height: h), Design.ink) }
    }
    /// The Check: twelve square, one-point ink, filled ink with a paper tick when it passes; its word after it.
    private func verdict(_ ok: Bool?, x: CGFloat, baseline b: CGFloat) {
        guard let ok = ok else { Design.attributed("N/A", .body, colour: Design.soft).draw(x: x + 20, baseline: b); return }
        let sq = NSRect(x: x, y: b - 10, width: 12, height: 12)
        fill(sq, ok ? Design.ink : Design.card)
        Design.ink.setStroke()
        let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
        if ok {
            Design.card.setStroke()
            let t = NSBezierPath(); t.lineWidth = 1.4
            t.move(to: NSPoint(x: sq.minX + 2.5, y: sq.midY)); t.line(to: NSPoint(x: sq.minX + 5, y: sq.maxY - 3)); t.line(to: NSPoint(x: sq.maxX - 2.5, y: sq.minY + 3))
            t.stroke()
        }
        Design.attributed(ok ? "Pass" : "Fail", .body).draw(x: x + 20, baseline: b)
    }
    /// The swap mark: two strokes, one each way, with their heads.
    private func swapMark(right: CGFloat, baseline b: CGFloat) -> NSRect {
        let r = NSRect(x: right - 14, y: b - 12, width: 14, height: 12)
        Design.ink.setStroke()
        let p = NSBezierPath(); p.lineWidth = 1.1
        p.move(to: NSPoint(x: r.minX, y: r.minY + 3)); p.line(to: NSPoint(x: r.maxX, y: r.minY + 3)); p.line(to: NSPoint(x: r.maxX - 3, y: r.minY))
        p.move(to: NSPoint(x: r.maxX, y: r.maxY - 3)); p.line(to: NSPoint(x: r.minX, y: r.maxY - 3)); p.line(to: NSPoint(x: r.minX + 3, y: r.maxY))
        p.stroke()
        return r.insetBy(dx: -6, dy: -8)
    }
    /// A colour's square: one-point Rule round it when it would vanish on the card.
    private func square(_ hex: String, _ r: NSRect) {
        fill(r, colour(hex))
        if contrastRatio(hex, "#F8F7F5") < 1.3 {
            Design.rule.setStroke()
            let e = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
        }
    }

    private var methodNote: String {
        state.usesAPCA
            ? "APCA scores readability as Lc, from 0 to about 106, and knows dark on light from light on dark. It is drafted for WCAG 3 and not yet a standard: audits still ask for WCAG 2."
            : "The WCAG 2 ratio compares how light two colours are, from 1 to 21. Audits, contracts and accessibility law ask for it: body text needs 4.5; large text, icons and controls need 3."
    }
    private var targets: [(title: String, value: Double)] {
        state.usesAPCA ? APCAUse.allCases.map { ($0.target, $0.minimum) } : ContrastTarget.allCases.map { ($0.title, $0.rawValue) }
    }
    private var targetTitle: String {
        let want = state.usesAPCA ? state.lcGoal : state.goal
        return targets.first { $0.value == want }?.title ?? targets[0].title
    }
    private func fontWord(_ family: String?) -> String {
        guard let f = family else { return "System Font" }
        return fontInstalled(f) ? f : "\(f)  \u{00B7}  Missing"
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width), u = Self.u, line = Self.line
        func at(_ row: Int) -> CGFloat { CGFloat(row) * u + line }
        hits = []
        let pair = state.pair, apca = state.usesAPCA, ratio = pair.ratio, lc = self.lc

        // The first Split's headers: first order on the first line with their words in three units, second order on a rule.
        Design.attributed("Text And Background", .header).draw(x: g.lx, baseline: at(R.header))
        words(methodNote, x: g.lx, width: g.lw)
        Design.attributed("Preview", .header).draw(x: g.rx, baseline: at(R.header))
        words("The pair in your own words and fonts. Click the heading or the sentence to type over it; Add To Typography keeps the pairing with its words and fonts.", x: g.rx, width: g.rw)
        subheader("Pair", x: g.lx, width: g.lw, row: R.sub)
        subheader("Sample", x: g.rx, width: g.rw, row: R.sub)

        // The two colours: label over a square and its hex on a hairline. The one the next colour goes to has its line in ink.
        for (title, hex, half, ink) in [("Text Colour", pair.ink, g.a, true), ("Background", pair.paper, g.b, false)] {
            label(title, x: half.x, row: R.fieldLabel)
            let sq = NSRect(x: half.x, y: at(R.field) - 20, width: 20, height: 20)
            square(hex, sq)
            let field = ink ? inkField : paperField, typing = field.currentEditor() != nil, armed = arming == ink
            let lineW = ink ? half.w - 28 : half.w
            fill(NSRect(x: half.x, y: CGFloat(R.field + 1) * u - (typing ? 2 : 1), width: lineW, height: typing ? 2 : 1), armed || typing ? Design.ink : Design.rule)
            hits.append((NSRect(x: half.x, y: CGFloat(R.fieldLabel) * u, width: 24, height: 2 * u), { [weak self] in self?.arm(ink) }))
            hits.append((NSRect(x: half.x + 24, y: CGFloat(R.fieldLabel) * u, width: half.w - 24, height: u), { [weak self] in self?.arm(ink) }))
        }
        let swap = swapMark(right: g.a.x + g.a.w, baseline: at(R.field))
        hits.append((swap, { [weak self] in self?.change { $0.pair = $0.pair.swapped } }))

        // The score: the method's Choice, the grade and whether the target is met on the left; the numeral flush right on the score's line.
        choice(["WCAG 2", "APCA"], chosen: apca ? 1 : 0, x: g.lx, baseline: at(R.choice)) { [weak self] i in
            guard let self = self, (i == 1) != self.state.usesAPCA else { return }
            self.change { $0.apca = i == 1 }
        }
        let grade: String, score: String, met: Bool
        if apca {
            let best = APCAUse.best(for: lc)
            grade = best == .body ? "Body Text" : best == .large ? "Large Text" : best == .headline ? "Headlines" : "Fail"
            score = "Lc \(Int(lc.rounded(.down)))"
            met = lc >= state.lcGoal
        } else {
            grade = ["AAA": "AAA", "AA": "AA", "AA large": "AA Large", "fail": "Fail"][contrastGrade(ratio)] ?? ""
            score = ContrastPair.text(ratio)
            met = ratio >= state.goal
        }
        let numeral = Design.attributed(score, .numeral)
        numeral.draw(right: g.lx + g.lw, baseline: at(R.score))
        let room = g.lw - numeral.size().width - 16
        Design.attributed(grade, .heading).draw(x: g.lx, baseline: at(R.grade), width: room)
        Design.attributed(met ? "Target Met" : "Below Target", .caption, colour: Design.quiet).draw(x: g.lx, baseline: at(R.score), width: room)

        // The sample: the pair as it would be used, square, its words in the user's own fonts, a button and a check under them.
        let card = g.card, ink = colour(pair.ink), paper = colour(pair.paper)
        fill(card, paper)
        Design.rule.setStroke()
        let edge = NSBezierPath(rect: card.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
        let buttonWords = NSAttributedString(string: "Button", attributes: [.font: typeFont(family: state.bodyFont, size: 13, bold: true), .foregroundColor: paper])
        let box = NSRect(x: card.minX + 16, y: card.maxY - 16 - 24, width: (buttonWords.size().width + 28).rounded(), height: 24)
        fill(box, ink)
        buttonWords.draw(at: NSPoint(x: box.minX + 14, y: box.midY - buttonWords.size().height / 2))
        let check = NSRect(x: box.maxX + 16, y: box.minY + 3, width: 18, height: 18)
        ink.setStroke()
        let ring = NSBezierPath(rect: check.insetBy(dx: 1, dy: 1)); ring.lineWidth = 2; ring.stroke()
        let tick = NSBezierPath(); tick.lineWidth = 2
        tick.move(to: NSPoint(x: check.minX + 4.5, y: check.midY)); tick.line(to: NSPoint(x: check.minX + 7.5, y: check.maxY - 5)); tick.line(to: NSPoint(x: check.maxX - 4, y: check.minY + 5))
        tick.stroke()

        // What the pair passes: the uses down the side, the two levels flush right.
        subheader("What It Passes", x: g.lx, width: g.lw, row: R.sub2)
        let v2 = g.lx + g.lw - 64, v1 = v2 - 88
        let headers = apca ? ("Least", "Ideal") : ("AA", "AAA")
        label("Use", x: g.lx, row: R.columns)
        label(headers.0, x: v1, row: R.columns)
        label(headers.1, x: v2, row: R.columns)
        let rows: [(String, Bool?, Bool?)] = apca ? APCAUse.allCases.map { ($0.title, lc >= $0.minimum, lc >= $0.preferred) }
                                                 : ContrastUse.allCases.map { use in (use.title, ratio >= use.aa, use.aaa.map { ratio >= $0 }) }
        for (i, r) in rows.enumerated() {
            let b = at(R.table + i)
            Design.attributed(r.0, .body).draw(x: g.lx, baseline: b, width: v1 - g.lx - 16)
            verdict(r.1, x: v1, baseline: b)
            verdict(r.2, x: v2, baseline: b)
            hairline(x: g.lx, y: CGFloat(R.table + i + 1) * u - 1, width: g.lw, Design.mist)
        }

        // The fonts of the sample, and the pairing kept as typography.
        subheader("Fonts", x: g.rx, width: g.rw, row: R.sub2)
        headingFontRect = dropdown("Heading Font", value: fontWord(state.headingFont), x: g.c.x, width: g.c.w, row: R.columns) { [weak self] in self?.openFonts(heading: true) }
        bodyFontRect = dropdown("Text Font", value: fontWord(state.bodyFont), x: g.d.x, width: g.d.w, row: R.columns) { [weak self] in self?.openFonts(heading: false) }
        if let e = edited {
            let x = g.c.x + g.c.w + Design.App.gutter
            Design.attributed("Editing \(e.style.name) In \(e.palette.name)", .caption, colour: Design.quiet).draw(x: x, baseline: at(R.addType), width: g.rx + g.rw - x)
        }

        // The fix: the target, then the two ways to reach it.
        subheader("Fix", x: g.lx, width: g.lw, row: R.sub3)
        targetRect = dropdown("Target", value: targetTitle, x: g.lx, width: g.lw, row: R.label3) { [weak self] in self?.openTargets() }

        // Keeping the pair as a palette of two colours.
        subheader("Keep As A Palette", x: g.rx, width: g.rw, row: R.sub3)
        label("Palette Name", x: g.rx, row: R.label3)
        let naming = nameField.currentEditor() != nil
        fill(NSRect(x: g.rx, y: CGFloat(R.value3 + 1) * u - (naming ? 2 : 1), width: g.rw, height: naming ? 2 : 1), naming ? Design.ink : Design.rule)

        drawLower(g)
    }

    /// The second Split: the chosen palette's colours on the left, every pair of them scored on the right.
    private func drawLower(_ g: Geometry) {
        let u = Self.u, line = Self.line
        func at(_ row: Int) -> CGFloat { CGFloat(row) * u + line }
        let top = R.lower, lright = g.lx + g.lw, right = g.rx + g.rw
        Design.attributed("Colours", .header).draw(x: g.lx, baseline: at(top))
        Design.attributed("The palette chosen in the rail. Click a colour to set the text colour; the next sets the background. White and black are always offered.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: g.lx, y: CGFloat(top + 1) * u, width: g.lw, height: 3 * u))
        Design.attributed("Every Pair", .header).draw(x: g.rx, baseline: at(top))
        Design.attributed("The palette's first eight colours against each other: rows are the text colour, columns the background, each cell its score. Click a cell to make it the pair.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: g.rx, y: CGFloat(top + 1) * u, width: g.rw, height: 3 * u))

        // The colours: the chosen palette's name on the rule, what the next click sets and the eyedropper flush right.
        let next = Design.attributed(arming ? "Next Sets The Text Colour" : "Next Sets The Background", .caption, colour: Design.quiet)
        Design.attributed(targetName, .header).draw(x: g.lx, baseline: at(R.lowerSub), width: g.lw - next.size().width - 48)
        hairline(x: g.lx, y: CGFloat(R.lowerSub + 1) * u - 1, width: g.lw, Design.rule)
        RowMark.draw("eyedropper", x: lright - 14, baseline: at(R.lowerSub), colour: Design.ink)
        next.draw(right: lright - 14 - 12, baseline: at(R.lowerSub))
        hits.append((NSRect(x: lright - 24, y: CGFloat(R.lowerSub) * u, width: 24, height: u), { [weak self] in self?.pickFromScreen() }))
        for t in g.tiles {
            square(t.hex, t.rect)
            // T and B mark the two colours in use.
            if let mark = same(t.hex, state.pair.ink) ? "T" : same(t.hex, state.pair.paper) ? "B" : nil {
                let m = Design.attributed(mark, .label, colour: Design.hex(readableText(on: t.hex)))
                m.draw(x: t.rect.midX - m.size().width / 2 + 0.5, baseline: t.rect.minY + 16)
            }
            let hex = t.hex
            hits.append((t.rect, { [weak self] in self?.take(hex) }))
        }

        // Every pair of the palette's first colours: rows are the text colour, columns the background, the cells across the block.
        let all = targetHexes.count
        subheader(all > g.gridHexes.count ? "The First \(g.gridHexes.count) Colours" : "Rows Text, Columns Background", x: g.rx, width: g.rw, row: R.lowerSub)
        guard let gr = g.gridRow else {
            Design.attributed(all == 0 ? "Choose a palette in the rail" : "One colour makes no pair", .body, colour: Design.soft).draw(x: g.rx, baseline: at(R.lowerRows))
            return
        }
        let s = g.cell, y0 = CGFloat(gr) * u, apca = state.usesAPCA, last = g.gridHexes.count - 1
        for (r, inkHex) in g.gridHexes.enumerated() {
            for (c, paperHex) in g.gridHexes.enumerated() {
                let x = g.rx + CGFloat(c) * s.width
                // The last column runs to the block's edge, taking the width the rounding left.
                let cell = NSRect(x: x, y: y0 + CGFloat(r) * s.height, width: c == last ? right - x : s.width, height: s.height)
                fill(cell, colour(paperHex))
                guard r != c else { continue }   // a colour on itself is nothing to read
                let readable = Design.hex(readableText(on: paperHex))
                let ratio = contrastRatio(inkHex, paperHex), lcv = abs(apcaContrast(text: inkHex, background: paperHex))
                let text = apca ? String(Int(lcv.rounded(.down))) : String(format: "%.1f", (ratio * 10 + 1e-9).rounded(.down) / 10)
                let weak = apca ? lcv < APCAUse.headline.minimum : ratio < 3
                // The score and the square of the text colour being judged, a quarter of the cell's size and centred in it, as one group.
                let size = max(11, (min(cell.width, cell.height) * 0.25).rounded())
                let t = Design.attributed(text, .caption, size: size, colour: readable.withAlphaComponent(weak ? 0.5 : 1))
                let tw = t.size().width.rounded(), gap = (size * 0.5).rounded()
                // The square is the numeral's cap height, so the two sit on one line.
                let capHeight = (size * 0.72).rounded(), withSquare = cell.width >= capHeight + gap + tw + 2 * gap
                let groupW = withSquare ? capHeight + gap + tw : tw
                let x0 = (cell.midX - groupW / 2).rounded(), b = (cell.midY + capHeight / 2).rounded()
                if withSquare {
                    fill(NSRect(x: x0, y: b - capHeight, width: capHeight, height: capHeight), colour(inkHex))
                    t.draw(x: x0 + capHeight + gap, baseline: b, width: cell.width - (x0 + capHeight + gap - cell.minX))
                } else { t.draw(x: x0, baseline: b, width: cell.width - (x0 - cell.minX)) }
                if same(inkHex, state.pair.ink) && same(paperHex, state.pair.paper) {
                    readable.setStroke()
                    let mark = NSBezierPath(rect: cell.insetBy(dx: 1.5, dy: 1.5)); mark.lineWidth = 2; mark.stroke()
                }
                guard let ink = Self.sRGB(inkHex), let paper = Self.sRGB(paperHex) else { continue }
                let pairing = ContrastPair(ink: ink, paper: paper)
                hits.append((cell, { [weak self] in self?.change { $0.pair = pairing } }))
            }
        }
    }

    // MARK: The pointer

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        if let h = hits.last(where: { $0.0.contains(p) }) { h.1() }
    }

    private func arm(_ ink: Bool) { arming = ink; needsDisplay = true }

    /// A colour picked from the palette or the screen goes to whichever colour is waiting, and the other waits next.
    private func take(_ hex: String) {
        guard let clean = Self.sRGB(hex) else { return }
        let toInk = arming
        arming.toggle()
        change { if toInk { $0.pair.ink = clean } else { $0.pair.paper = clean } }
    }

    private func pickFromScreen() {
        let s = NSColorSampler()
        sampler = s
        s.show { [weak self] c in
            self?.sampler = nil
            if let hex = c.flatMap(hexOf) { self?.take(hex) }
        }
    }

    private func fix(ink: Bool) {
        let (mine, other) = ink ? (state.pair.ink, state.pair.paper) : (state.pair.paper, state.pair.ink)
        // APCA cares which colour is the text, so the test is put the right way round for the one being moved.
        let apca = state.usesAPCA, lcGoal = state.lcGoal, ratioGoal = state.goal
        let shade = nearestShade(of: mine) { candidate in
            guard apca else { return contrastRatio(candidate, other) >= ratioGoal }
            return abs(ink ? apcaContrast(text: candidate, background: other) : apcaContrast(text: other, background: candidate)) >= lcGoal
        }
        guard let found = shade else {
            let want = apca ? "Lc \(Int(lcGoal))" : ContrastPair.text(ratioGoal)
            library.flash("No Shade Of \(mine) Reaches \(want) Against \(other). Try Fixing The \(ink ? "Background" : "Text Colour") Instead")
            return
        }
        change { if ink { $0.pair.ink = found } else { $0.pair.paper = found } }
    }
    @objc private func fixInkTapped() { fix(ink: true) }
    @objc private func fixPaperTapped() { fix(ink: false) }

    @objc private func undoTapped() {
        guard let back = history.undo(from: state) else { return }
        state = back; save(); refresh()
    }
    @objc private func redoTapped() {
        guard let on = history.redo(from: state) else { return }
        state = on; save(); refresh()
    }

    // MARK: Menus, on the window's own panel

    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        openRect = nil
        needsDisplay = true
        Overlays.closed(self)
    }

    /// One thing a menu offers: a row to choose, a heading over a run of rows, or a hairline between runs.
    private enum Entry { case item(String, () -> Void), heading(String), divider }
    private struct Group { let heading: String; let items: [(String, () -> Void)] }

    /// Opens a menu under a rect of this view, or over it when there is no room below. Groups that would run
    /// taller than the screen are offered one by one: the first menu names them, and a name opens its group.
    private func openMenu(under rect: NSRect, width: CGFloat, chosen: String = "", lead: [Entry] = [], groups: [Group], tail: [Entry] = []) {
        guard let win = window else { return }
        closeMenu()
        func rows(_ es: [Entry]) -> CGFloat { es.reduce(12) { r, e in if case .divider = e { return r + 12 }; return r + 30 } }
        var entries = lead
        for (i, g) in groups.enumerated() {
            if i > 0 || !lead.isEmpty { entries.append(.divider) }
            if !g.heading.isEmpty { entries.append(.heading(g.heading)) }
            entries += g.items.map { .item($0.0, $0.1) }
        }
        if !tail.isEmpty { entries.append(.divider); entries += tail }
        let s = win.convertToScreen(convert(rect, to: nil))
        let visible = win.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let room = max(s.minY - visible.minY, visible.maxY - s.maxY) - 16
        if rows(entries) > room && groups.count > 1 {
            // Too tall: each group is one row, which opens a menu of its own in the same place.
            var short = lead
            if !lead.isEmpty { short.append(.divider) }
            short += groups.map { g in .item(g.heading + "\u{2026}", { [weak self] in self?.openMenu(under: rect, width: width, chosen: chosen, groups: [g]) }) }
            if !tail.isEmpty { short.append(.divider); short += tail }
            entries = short
        }
        var titles: [String] = [], acts: [() -> Void] = []
        let M = SwissDropdown.MenuPanel.self
        for e in entries {
            switch e {
            case .item(let t, let a): titles.append(t); acts.append(a)
            case .heading(let t): titles.append(M.heading(t)); acts.append {}
            case .divider: titles.append(M.divider); acts.append {}
            }
        }
        let w = max(220, width)
        let panel = SwissDropdown.MenuPanel(items: titles, chosen: chosen, width: w) { [weak self] i in
            self?.closeMenu()
            if acts.indices.contains(i) { acts[i]() }
        }
        let h = panel.frame.height
        let below = s.minY - 4 - h >= visible.minY
        panel.place(below: NSPoint(x: min(s.minX, visible.maxX - w), y: below ? s.minY - 4 : min(visible.maxY, s.maxY + 4 + h)))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        openRect = rect
        needsDisplay = true
        Overlays.opened(self)
    }

    private func openTargets() {
        let all = targets, apca = state.usesAPCA
        openMenu(under: targetRect, width: targetRect.width, chosen: targetTitle,
                 groups: [Group(heading: "", items: all.map { t in (t.title, { [weak self] in self?.change { if apca { $0.apcaGoal = t.value } else { $0.goal = t.value } } }) })])
    }

    /// The fonts on offer: the system font, those the library's typography already uses, a few on every Mac, and any other by name.
    private func openFonts(heading: Bool) {
        let rect = heading ? headingFontRect : bodyFontRect
        func set(_ family: String?) { change { if heading { $0.headingFont = family } else { $0.bodyFont = family } } }
        let used = Array(Set(library.typographyOrder.flatMap { ($0.styles ?? []).flatMap { $0.fonts } })).sorted()
        let common = ["Helvetica Neue", "Avenir Next", "Futura", "Gill Sans", "Optima", "Georgia", "Baskerville", "Didot", "Palatino", "Charter"]
            .filter { fontInstalled($0) && !used.contains($0) }
        var groups: [Group] = []
        if !used.isEmpty { groups.append(Group(heading: "In Your Typography", items: used.map { f in (f, { set(f) }) })) }
        groups.append(Group(heading: "On Every Mac", items: common.map { f in (f, { set(f) }) }))
        let current = heading ? state.headingFont : state.bodyFont
        openMenu(under: rect, width: rect.width, chosen: current ?? "System Font", lead: [.item("System Font", { set(nil) })], groups: groups,
                 tail: [.item("Another Font\u{2026}", { [weak self] in self?.askFont(heading: heading) })])
    }
    private func askFont(heading: Bool) {
        let families = NSFontManager.shared.availableFontFamilies
        func match(_ s: String) -> String? { families.first { $0.caseInsensitiveCompare(s.trimmingCharacters(in: .whitespaces)) == .orderedSame } }
        SwissConfirm.name(over: window, title: "Another Font", note: "Type the family's name as Font Book lists it. The pairing keeps the font by name.",
                          placeholder: "Font family", confirm: "Use Font", check: { match($0) == nil ? "No font family of that name is on this Mac." : nil }) { [weak self] typed in
            guard let f = match(typed) else { return }
            self?.change { if heading { $0.headingFont = f } else { $0.bodyFont = f } }
        }
    }

    // MARK: Keeping: typography, a palette, a project

    /// Opens a typography palette's pairing for editing, or (nil) gets ready to add a new one to it.
    func edit(_ style: UUID?, in palette: UUID) {
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
    private func style(id: UUID?, name: String) -> TypeStyle {
        TypeStyle(id: id ?? UUID(), name: name, ink: state.pair.ink, paper: state.pair.paper, heading: state.heading, body: state.body,
                  headingFont: state.headingFont, bodyFont: state.bodyFont)
    }
    /// The pairing being edited, if it is still there.
    private var edited: (palette: Swatch, style: TypeStyle)? {
        guard let p = state.typography.flatMap({ library.library.swatch($0) }), let s = p.styles?.first(where: { $0.id == state.editing }) else { return nil }
        return (p, s)
    }
    private func addStyle(to palette: UUID?) {
        let kept = library.keep(style(id: nil, name: ""), in: palette)
        // Further pairings go to the same palette; this one is done, so the next press adds another.
        state.typography = kept
        state.editing = nil
        save()
        refresh()
    }

    /// Add To Typography: Update when a pairing is being edited, the palette last added to, every member's typography palettes, then a new one in a chosen member.
    @objc private func typographyTapped() {
        let lib = library.library
        var lead: [Entry] = []
        if let e = edited { lead.append(.item("Update \u{201C}\(e.style.name)\u{201D} In \(e.palette.name)", { [weak self] in
            guard let self = self, let e = self.edited else { return }
            self.library.keep(self.style(id: e.style.id, name: e.style.name), in: e.palette.id)
        })) }
        if let current = state.typography.flatMap({ lib.swatch($0) }) {
            if !lead.isEmpty { lead.append(.divider) }
            lead.append(.item("Add To \(current.name)", { [weak self] in self?.addStyle(to: current.id) }))
        }
        var groups: [Group] = []
        for p in lib.orderedProjects {
            let type = lib.palettes(in: p.id).filter { $0.isTypography }
            if !type.isEmpty { groups.append(Group(heading: p.name, items: type.map { s in ("Add To \(s.name)", { [weak self] in self?.addStyle(to: s.id) }) })) }
        }
        let loose = lib.palettes(in: nil).filter { $0.isTypography }
        if !loose.isEmpty { groups.append(Group(heading: "In No Member", items: loose.map { s in ("Add To \(s.name)", { [weak self] in self?.addStyle(to: s.id) }) })) }
        openMenu(under: buttonRect(toTypography), width: toTypography.frame.width, lead: lead, groups: groups,
                 tail: [.item("New Typography Palette\u{2026}", { [weak self] in self?.newTypography() })])
    }
    /// A new typography palette, in the member chosen next or in none, with this pairing as its first.
    private func newTypography() {
        let members = library.library.orderedProjects
        let items: [(String, () -> Void)] = members.map { p in ("In \(p.name)", { [weak self] in self?.addToNewTypography(in: p.id) }) }
        openMenu(under: buttonRect(toTypography), width: toTypography.frame.width, groups: [Group(heading: "New Typography Palette", items: items)],
                 tail: [.item("In No Member", { [weak self] in self?.addStyle(to: nil) })])
    }
    private func addToNewTypography(in member: UUID) {
        var made: UUID?
        library.apply("New Typography Palette") { made = $0.createTypography(in: member) }
        guard let id = made, library.library.swatch(id) != nil else { return }
        addStyle(to: id)
    }

    /// Add To Palette: every palette of colours, member by member, then a new loose one.
    @objc private func paletteTapped() {
        let lib = library.library, colours = pairHexes
        var groups: [Group] = []
        for p in lib.orderedProjects {
            let list = lib.palettes(in: p.id).filter { !$0.isTypography }
            if !list.isEmpty { groups.append(Group(heading: p.name, items: list.map { s in (s.name, { [weak self] in self?.library.add(colours, to: s.id) }) })) }
        }
        let loose = lib.palettes(in: nil).filter { !$0.isTypography }
        if !loose.isEmpty { groups.append(Group(heading: "In No Member", items: loose.map { s in (s.name, { [weak self] in self?.library.add(colours, to: s.id) }) })) }
        let name = chosenName
        openMenu(under: buttonRect(toPalette), width: toPalette.frame.width, groups: groups,
                 tail: [.item("New Palette", { [weak self] in self?.library.keep(colours, named: name, in: nil) })])
    }
    /// Add To Project: the pair as a new palette in a member, collection by collection, or in a new member.
    @objc private func projectTapped() {
        let lib = library.library, colours = pairHexes, name = chosenName
        var groups: [Group] = []
        for c in SchemaTrial.collections {
            let inside = lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id).id == c.id }
            if !inside.isEmpty { groups.append(Group(heading: c.name, items: inside.map { p in (p.name, { [weak self] in self?.library.keep(colours, named: name, in: p.id) }) })) }
        }
        openMenu(under: buttonRect(toProject), width: toProject.frame.width, groups: groups,
                 tail: [.item("New Project\u{2026}", { [weak self] in self?.library.startProject(keeping: colours, named: name) })])
    }
    private func buttonRect(_ b: NSView) -> NSRect { b.frame }

    // MARK: Typing

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === inkField { arming = true }
        if field === paperField { arming = false }
        // The caret in the sample is the text colour, which the window's own could vanish on.
        let caret = field === heading || field === body ? colour(state.pair.ink) : Design.ink
        (field.currentEditor() as? NSTextView)?.insertionPointColor = caret
        needsDisplay = true
    }
    func controlTextDidChange(_ obj: Notification) { if (obj.object as? NSTextField) === nameField { publish() } }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        defer { needsDisplay = true }
        if field === heading || field === body {
            // Emptied words go back to what they were: a blank sample shows nothing.
            if heading.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { heading.stringValue = state.heading }
            if body.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body.stringValue = state.body }
            let (h, b) = (heading.stringValue, body.stringValue)
            if h != state.heading || b != state.body { change { $0.heading = h; $0.body = b } }
            return
        }
        guard field === inkField || field === paperField else { publish(); return }
        let ink = field === inkField, was = ink ? state.pair.ink : state.pair.paper
        guard let clean = normaliseHex(field.stringValue) else { field.stringValue = was; return }   // not a colour: what was there comes back
        field.stringValue = clean
        if clean != was { change { if ink { $0.pair.ink = clean } else { $0.pair.paper = clean } } }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            control.abortEditing()
            if control === inkField { inkField.stringValue = state.pair.ink }
            if control === paperField { paperField.stringValue = state.pair.paper }
            if control === heading { heading.stringValue = state.heading }
            if control === body { body.stringValue = state.body }
            window?.makeFirstResponder(self)
            needsDisplay = true
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
}
