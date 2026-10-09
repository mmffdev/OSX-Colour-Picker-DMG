import AppKit

// ---------- Colour Lab, on the Studio window ----------
//
// The old window's cLab redrawn in the house: a page section drawn by frame on the page's own columns and the 28 beat.
// A Split. The left is the colour being worked on, the base or, with no rule, the ringed one: its block drawn from its
// master through Display P3, then its values, every one worked out from the master (XYZ under D50), the print build
// naming its press and intent, then the proof: a panel titled by the colour difference, the master and what the press
// prints side by side and the working on the right. The right is the harmony: the rule's words in a fixed box, the wheel,
// the nine rules as the guide's Choice, the brightness slider and the actions, then, on the proof's row, the colours the
// wheel holds as square tiles on the side's columns, each copying its value, with Base, Lock and Delete under the pointer.
// Under both sides, the palette's name and the house buttons that keep them. The maths, the rules and the history are ColourScience.swift's; nothing is reinvented.

final class LabPage: NSView, PageSection, Overlay, NSTextFieldDelegate {
    var onResize: (() -> Void)?
    private let library: LibraryController

    // MARK: State, as the old Lab keeps it: one key in the preferences, so both windows share the wheel.

    private(set) var state: LabState
    private var history = LabHistory()
    /// The state when a drag began, so the whole gesture is one step to undo.
    private var gestureStart: LabState?
    /// The ringed colour, with no rule; the base under a rule.
    private var selected = 0
    /// The library colour the wheel was opened on, kept whole: while the base is still that colour, its values are its own master's, not its eight-bit hex.
    private var origin: String?
    private static let key = "labState", formatKey = "labFormat", methodKey = "labDifference", illuminantKey = "labIlluminant"

    /// The model the tiles' values are written in and copied as.
    private var format: ColourFormat {
        get { (preferences.string(forKey: Self.formatKey)).flatMap(ColourFormat.init(rawValue:)) ?? .lab }
        set { preferences.set(newValue.rawValue, forKey: Self.formatKey) }
    }

    // MARK: The views: the house buttons and the name field; everything else is drawn.

    private let undo = SwissButton("Undo", .quiet), redo = SwissButton("Redo", .quiet)
    private let random = SwissButton("Random", .quiet), addOne = SwissButton("Add Colour", .quiet)
    private let contrast = SwissButton("Contrast", .quiet)
    private let toPalette = SwissButton("Add To Palette", .primary)
    private let toProject = SwissButton("Add To Project", .secondary)
    private let nameField = NSTextField(string: "")

    /// The way the proof compares the master with the print: the house's method, CIEDE2000 until it says otherwise.
    private var method: DifferenceMethod {
        get { (preferences.string(forKey: Self.methodKey)).flatMap(DifferenceMethod.init(rawValue:)) ?? .ciede2000 }
        set { preferences.set(newValue.rawValue, forKey: Self.methodKey) }
    }

    /// The white the colour's values are quoted under: D50, the master's own, until the house says otherwise.
    private var illuminant: Illuminant {
        get { Illuminant.named(preferences.string(forKey: Self.illuminantKey)) ?? .d50 }
        set { preferences.set(newValue.key, forKey: Self.illuminantKey) }
    }

    /// What a press is on, worked out as the page draws.
    private enum Hit: Equatable { case node(Int), rule(LabRule), slider, block(Int), name(Int), base(Int), lock(Int), bin(Int), format, method, illuminant }
    private var hits: [(NSRect, Hit)] = []
    private var hover: Hit?
    private var hoverTile: Int?
    private var dragging: Hit?
    /// Tooltips are kept here: the view does not hold the strings it hands out.
    private var tips: [NSString] = []

    /// The open menu: the palettes, the projects or the models.
    private var dropped: SwissDropdown.MenuPanel?
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }

    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    /// The words over each side: three units, the words rewritten to fit, never the box grown.
    private static let helpUnits: CGFloat = 3
    /// The wheel is eight units square; the working colour's band two, over its nine values; a tile's block two, as the band is, its words two.
    private static let wheelUnits: CGFloat = 8, bandUnits: CGFloat = 2, blockUnits: CGFloat = 2, wordUnits: CGFloat = 2
    /// The proof's heading row, then its block: the two colours seven units tall beside the working, two units a value and three for the numeral.
    private static let proofRow: CGFloat = 17, proofUnits: CGFloat = 7
    /// The note under the proof: what the method is and what the two colours are, in a box of three units, the words written to fit.
    private static let proofNoteUnits: CGFloat = 3
    /// The brightness a colour may go down to, as the old slider did: below it a colour is black whatever its hue.
    private static let darkest = 0.08

    init(library: LibraryController) {
        self.library = library
        let saved = preferences.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(LabState.self, from: $0) }
        state = saved.flatMap { $0.nodes.isEmpty || !$0.nodes.indices.contains($0.base) ? nil : $0 }
            ?? LabState(rule: .analogous, base: LabNode(hex: Brand.masterHex) ?? LabNode(h: 260, s: 0.8, v: 1))
        super.init(frame: .zero)
        selected = state.base
        for (b, act) in [(undo, #selector(undoTapped)), (redo, #selector(redoTapped)), (random, #selector(randomTapped)), (addOne, #selector(addTapped)),
                         (contrast, #selector(contrastTapped)), (toPalette, #selector(paletteTapped)), (toProject, #selector(projectTapped))] {
            b.target = self; b.action = act
            addSubview(b)
        }
        contrast.leadingArrow = true
        undo.toolTip = "Undo The Last Change"
        redo.toolTip = "Redo"
        random.toolTip = "Roll New Colours; Locked Ones Stay"
        addOne.toolTip = "Add A Colour; The Rule Is Left Behind"
        contrast.toolTip = "Check These Colours In Contrast"
        toPalette.toolTip = "Add These Colours To A Palette, Or Make A New One"
        toProject.toolTip = "Keep These Colours As A New Palette In A Project"
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = Design.Text.body.font()
        nameField.textColor = Design.ink
        nameField.delegate = self
        nameField.cell?.usesSingleLineMode = true
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setAccessibilityLabel("Palette name")
        addSubview(nameField)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
        setAccessibilityLabel("Colour Lab")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func reload() { refresh() }

    // MARK: The colour being worked on, from its master

    private var working: Int { state.rule == .custom && state.nodes.indices.contains(selected) ? selected : state.base }

    /// The working colour's key, its definition and its name: the library colour the wheel was opened on while the base is still it, else the wheel's own sRGB colour.
    private func definition(of i: Int) -> (key: String, def: ColourDefinition, name: String) {
        let hex = state.nodes[i].hex
        if i == state.base, let o = origin, displayHex(o) == hex, let d = ColourKeys.definition(of: o) ?? ColourDefinition.of(hex: o) {
            return (o, d, library.library.name(of: o, in: nil))
        }
        let d = ColourDefinition.of(hex: hex) ?? ColourDefinition(source: ColourSource(space: RGBSpace.srgb.rawValue, values: [0, 0, 0]), master: XYZ(x: 0, y: 0, z: 0), kind: .surface)
        return (hex, d, colourName(hex))
    }
    /// What each colour is painted as: its master through Display P3.
    private var shades: [NSColor] = []
    /// The working colour's values, worked out once a change, not once a frame.
    private struct Value { let label: String; let value: String; let note: String }
    private var values: [Value] = []
    private var workingName = ""
    /// The proof: the master against what the press prints, both painted through Display P3, and the difference between them.
    private struct Proof {
        var master = NSColor.black, masterLab = LabD50(l: 0, a: 0, b: 0)
        var print: NSColor?, printLab: LabD50?, difference: Double?
        var inRange = false
    }
    private var proof = Proof()

    private func work() {
        shades = state.nodes.indices.map { definition(of: $0).def.master.display }
        let w = definition(of: working), d = w.def, m = d.master
        workingName = w.name
        // The values under the house's illuminant: the master carried to its white, so the XYZ, the L*a*b* and the proof all read under it.
        let ill = illuminant, under = m.adapted(to: ill), lab = under.lab(under: ill)
        let ok = oklchOf({ let v = RGBSpace.srgb.values(of: m); return (v[0], v[1], v[2]) }())
        let p3 = Rendering.of(d, in: ProfileChannel(space: RGBSpace.displayP3.rawValue))
        let video = Rendering.of(d, in: ProfileChannel(space: RGBSpace.rec2020.rawValue))
        let press = PrintCondition.current, print = Rendering.of(d, in: press)
        /// A value's figures without the depth and range its space writes after them, which the label says instead.
        func bare(_ s: String?) -> String { (s ?? "\u{2014}").components(separatedBy: "  (").first ?? "\u{2014}" }
        let ink = print.detail.components(separatedBy: "Total Ink ").last.map { "Ink " + $0 } ?? ""
        // The difference by the house's method, the master as the reference; the Print row's note and the proof's title are one number.
        let printLab = print.shown.map { $0.adapted(to: ill).lab(under: ill) }
        let difference = printLab.map { method.difference(lab, $0) }
        proof = Proof(master: m.display, masterLab: lab, print: print.shown?.display, printLab: printLab, difference: difference,
                      inRange: difference.map { $0 <= Rendering.visible } ?? false)
        values = [
            // The source's note names the white its numbers came in under, the "in" to the Values Under row's "out", then what the colour is.
            Value(label: "Source", value: d.sourceText, note: d.source.whiteName + "  \u{00B7}  " + (d.kind == .light ? "Light" : "Surface")),
            Value(label: ill == .d50 ? "Master XYZ" : "XYZ", value: String(format: "%.4f, %.4f, %.4f", under.x, under.y, under.z), note: ill.label),
            Value(label: "L*a*b*", value: String(format: "%.2f, %.2f, %.2f", lab.l, lab.a, lab.b), note: ill.label),
            Value(label: "OKLCH", value: String(format: "%.3f, %.3f, %.1f\u{00B0}", ok.l, ok.c, ok.h), note: ""),
            Value(label: "Display P3", value: bare(p3.value), note: p3.inRange ? "In Range" : "Out Of Range"),
            Value(label: "Rec. 2020", value: bare(video.value), note: "10-Bit"),
            Value(label: "Print", value: print.value ?? "\u{2014}", note: difference.map { String(format: "\u{0394}E %.1f", $0) } ?? ""),
            Value(label: "Press", value: press.press ?? PressProfiles.generic, note: print.value == nil ? "" : ink),
            Value(label: "Intent", value: (press.intent ?? .relative).name, note: press.blackPoint == true ? "BPC" : ""),
        ]
    }

    // MARK: Showing and changing, as the old Lab does

    private func refresh() {
        if !state.nodes.indices.contains(selected) || state.rule != .custom { selected = state.base }
        work()
        undo.isEnabled = history.canUndo
        redo.isEnabled = history.canRedo
        addOne.isEnabled = state.nodes.count < LabState.most
        nameField.placeholderAttributedString = Design.attributed(defaultName, .body, colour: Design.soft)
        publish()
        needsLayout = true
        needsDisplay = true
        onResize?()
    }

    /// Keeps the library's copy of the colours current, for export, sharing and the other tools.
    private func publish() {
        library.labPalette = ExportPalette(name: chosenName, colours: keys.map { ExportColour(name: library.library.name(of: $0, in: nil), hex: $0) })
    }
    private func save() { if let data = try? JSONEncoder().encode(state) { preferences.set(data, forKey: Self.key) } }

    /// One change, one step to undo.
    private func change(_ body: (inout LabState) -> Void) {
        let before = state
        body(&state)
        history.record(before, now: state)
        save()
        refresh()
    }
    private func endGesture() {
        if let start = gestureStart { history.record(start, now: state) }
        gestureStart = nil
        save()
        refresh()
    }

    /// Starts the wheel from a colour, keeping the rule in use. A colour with a key of its own is kept whole as the base's values.
    func open(with key: String) {
        guard let node = LabNode(hex: displayHex(key)) else { return }
        origin = key
        change { $0 = LabState(rule: $0.rule == .custom ? .analogous : $0.rule, base: node) }
    }

    /// Each colour once, for saving: the library colour the wheel was opened on in place of its sRGB copy while the base is still it.
    private var keys: [String] {
        var seen = Set<String>(), out: [String] = []
        for i in state.nodes.indices {
            let k = definition(of: i).key
            if seen.insert(k).inserted { out.append(k) }
        }
        return out
    }
    private var defaultName: String { "\(definition(of: state.base).name) \u{2014} \(state.rule.title)" }
    private var chosenName: String {
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultName : typed
    }

    // MARK: Geometry: the page's own columns and the beat

    private struct Geometry {
        var w: CGFloat = 0, column: CGFloat = 0, gutter: CGFloat = 0, n = 6, half = 3
        /// The left side, columns 1 to half; the right from the next column to the edge.
        var lw: CGFloat = 0, rx: CGFloat = 0, rw: CGFloat = 0
        func x(_ k: Int) -> CGFloat { CGFloat(k) * (column + gutter) }
        var wheel = NSRect.zero, choice = NSRect.zero
        /// The proof's block, under its heading row; the tiles' header a unit of air below it.
        var proof = NSRect.zero, coloursTop: CGFloat = 0
        var tilesTop: CGFloat = 0, tileRows = 1, saveTop: CGFloat = 0
        /// The tiles on the right side's columns, as many to a row as the side has.
        func tile(_ i: Int) -> NSRect {
            let u = Design.App.unit
            return NSRect(x: x(half + i % half), y: tilesTop + CGFloat(i / half) * (LabPage.blockUnits + LabPage.wordUnits + 1) * u, width: column, height: (LabPage.blockUnits + LabPage.wordUnits) * u)
        }
    }
    private func geometry(width w: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u
        g.w = w
        g.gutter = Design.App.gutter
        g.column = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        // The page is a whole number of the window's columns, six with both rails and the history, more as they go.
        g.n = max(2, Int(((w + g.gutter) / (g.column + g.gutter)).rounded()))
        let half = g.n / 2
        g.half = half
        g.lw = CGFloat(half) * g.column + CGFloat(half - 1) * g.gutter
        g.rx = g.x(half)
        g.rw = w - g.rx
        g.wheel = NSRect(x: g.rx, y: 5 * u, width: Self.wheelUnits * u, height: Self.wheelUnits * u)
        g.choice = NSRect(x: g.rx, y: 13 * u + 2, width: g.rw, height: u - 4)
        g.proof = NSRect(x: 0, y: (Self.proofRow + 1) * u, width: g.lw, height: Self.proofUnits * u)
        // The colours share the proof's row, on the right side under the harmony.
        g.coloursTop = Self.proofRow * u
        g.tilesTop = g.coloursTop + u
        g.tileRows = max(1, (state.nodes.count + half - 1) / half)
        // The save row under whichever side runs longer: the proof, a unit of air, its note and a unit more; or the tiles, whose
        // every row ends in a unit of air, since the buttons stand taller than the beat.
        let proofBottom = g.proof.maxY + (Self.proofNoteUnits + 2) * u
        g.saveTop = max(proofBottom, g.tilesTop + CGFloat(g.tileRows) * (Self.blockUnits + Self.wordUnits + 1) * u)
        return g
    }
    /// Down to the foot of the save row's buttons, which end a point short of the unit: at the window's first size the page holds it all without a scroll.
    func height(forWidth width: CGFloat) -> CGFloat { geometry(width: width).saveTop + Self.u - 1 }

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width), u = Self.u, line = Self.line
        // A boxed or quiet button's words sit 22 below its top: its frame is set so they sit on the row's line.
        func place(_ b: SwissButton, x: CGFloat, row: CGFloat) { b.frame = NSRect(x: x, y: row * u + line - 22, width: b.intrinsicContentSize.width, height: SwissButton.height) }
        func placeRight(_ b: SwissButton, right: CGFloat, top: CGFloat) { b.frame = NSRect(x: right - b.intrinsicContentSize.width, y: top + line - 22, width: b.intrinsicContentSize.width, height: SwissButton.height) }
        // The actions under the slider, from the side's left edge, a step apart.
        var x = g.rx
        for b in [random, addOne, undo, redo] { place(b, x: x, row: 15); x += b.intrinsicContentSize.width + 24 }
        // Contrast leaves the page: the arrow at the top right of the side.
        placeRight(contrast, right: g.w, top: 0)
        placeRight(toPalette, right: g.w, top: g.saveTop)
        placeRight(toProject, right: toPalette.frame.minX - Design.App.gutter, top: g.saveTop)
        // The name on its hairline, from the left side's second column; a 13 field's words sit twelve below its top.
        let fx = g.x(1)
        nameField.frame = NSRect(x: fx - 2, y: g.saveTop + line - 12, width: g.lw - fx + 2, height: 20)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width), u = Self.u, line = Self.line
        hits = []
        removeAllToolTips(); tips = []
        func tip(_ r: NSRect, _ s: String) { let t = s as NSString; tips.append(t); addToolTip(r, owner: t, userData: nil) }

        // The two first-order headers on the first line, their words in a fixed box of three units under each.
        Design.attributed("Colour", .body).draw(x: 0, baseline: line)
        Design.attributed("Harmony", .body).draw(x: g.rx, baseline: line)
        // The left's words take two of the three units; the third is the illuminant row, the white every value under it is quoted against.
        let leftHelp = state.rule == .custom
            ? "No rule ties the colours, so this is the ringed one. Every value below is worked out from its master, XYZ under D50."
            : "The base the harmony is built on. Every value below is worked out from its master, XYZ under D50."
        Design.attributed(leftHelp, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: 0, y: u, width: g.lw, height: (Self.helpUnits - 1) * u))
        Design.attributed("Values Under", .caption, colour: Design.quiet).draw(x: 0, baseline: (Self.helpUnits) * u + line)
        let illuminantMenu = drawMenu(illuminant.label, right: g.lw, top: Self.helpUnits * u)
        hits.append((illuminantMenu, .illuminant))
        tip(illuminantMenu, "The Illuminant And Observer The Values Are Quoted Under; The Master Stays D50")
        let why = NSMutableAttributedString(attributedString: Design.attributed(state.rule.title + ".  ", .caption, colour: Design.ink, lineHeight: true))
        why.append(Design.attributed(state.rule.why + (state.rule == .custom ? " Drag any colour on the wheel." : " Drag any colour on the wheel and the rest follow; a locked one stays."), .caption, colour: Design.quiet, lineHeight: true))
        why.draw(in: NSRect(x: g.rx, y: u, width: g.rw, height: Self.helpUnits * u))

        // The second-order headers on one line with their rules: the colour's name and what it is; the wheel and how many it holds.
        let which = Design.attributed(state.rule == .custom ? "Ringed" : "Base", .caption, colour: Design.quiet)
        which.draw(right: g.lw, baseline: 4 * u + line)
        Design.attributed(workingName, .body).draw(x: 0, baseline: 4 * u + line, width: g.lw - which.size().width - 16)
        hairline(x: 0, y: 5 * u - 1, width: g.lw, Design.rule)
        Design.attributed("Wheel", .body).draw(x: g.rx, baseline: 4 * u + line)
        Design.attributed(plural(state.nodes.count, "colour"), .caption, colour: Design.quiet).draw(right: g.w, baseline: 4 * u + line)
        hairline(x: g.rx, y: 5 * u - 1, width: g.rw, Design.rule)

        drawColour(g)
        drawProof(g, tip: tip)
        drawWheel(g)
        drawRules(g)
        drawSlider(g)
        drawTiles(g, tip: tip)

        // The palette's name, as the settings write a value: its label left, the words on a hairline from the second column.
        Design.attributed("Palette Name", .label, colour: Design.quiet).draw(x: 0, baseline: g.saveTop + line)
        let editing = nameField.currentEditor() != nil
        hairline(x: g.x(1), y: g.saveTop + u - 1, width: g.lw - g.x(1), editing ? Design.ink : Design.rule)
    }

    /// The house's menu control as the page draws it: the chosen words as a caption with a chevron, flush right on a row. Returns the rect a press on it lands in.
    @discardableResult
    private func drawMenu(_ chosen: String, right: CGFloat, top: CGFloat) -> NSRect {
        let b = top + Self.line, t = Design.attributed(chosen, .caption, colour: Design.quiet)
        t.draw(right: right - 14, baseline: b)
        Design.quiet.setStroke()
        let chevron = NSBezierPath(); chevron.lineWidth = 1
        chevron.move(to: NSPoint(x: right - 9, y: b - 6)); chevron.line(to: NSPoint(x: right - 5, y: b - 2)); chevron.line(to: NSPoint(x: right - 1, y: b - 6))
        chevron.stroke()
        return NSRect(x: right - 14 - t.size().width - 8, y: top, width: t.size().width + 22, height: Self.u)
    }

    /// The colour's block, a band across the side, drawn from its master; then its values on the beat, each on a Mist hairline.
    private func drawColour(_ g: Geometry) {
        let u = Self.u, line = Self.line
        if shades.indices.contains(working) { fill(NSRect(x: 0, y: 5 * u, width: g.lw, height: Self.bandUnits * u), shades[working]) }
        let vx = g.x(1)
        for (k, v) in values.enumerated() {
            let top = (5 + Self.bandUnits + CGFloat(k)) * u, b = top + line
            Design.attributed(v.label, .caption, colour: Design.quiet).draw(x: 0, baseline: b, width: vx - 8)
            let note = Design.attributed(v.note, .caption, colour: v.note == "Out Of Range" ? Design.ink : Design.quiet)
            note.draw(right: g.lw, baseline: b)
            Design.attributed(v.value, .body).draw(x: vx, baseline: b, width: g.lw - vx - (v.note.isEmpty ? 0 : note.size().width + 12))
            hairline(x: 0, y: top + u - 1, width: g.lw, Design.mist)
        }
    }

    // MARK: The proof: the colour difference as the title, the two colours side by side, the working beside them

    /// The first of the writings that fits the width, so a value is rewritten to fit its column, never cut or let run.
    private func fitted(_ writings: [String], _ style: Design.Text, colour: NSColor = Design.ink, width: CGFloat) -> NSAttributedString {
        let all = writings.map { Design.attributed($0, style, colour: colour) }
        return all.first { $0.size().width <= width } ?? all.last ?? NSAttributedString()
    }
    /// L*a*b* to two places, one, or none, as the column allows.
    private func labText(_ lab: LabD50?, width: CGFloat) -> NSAttributedString {
        guard let lab = lab else { return Design.attributed("\u{2014}", .body) }
        return fitted([2, 1, 0].map { String(format: "%.\($0)f, %.\($0)f, %.\($0)f", lab.l, lab.a, lab.b) }, .body, width: width)
    }

    private func drawProof(_ g: Geometry, tip: (NSRect, String) -> Void) {
        let u = Self.u, line = Self.line, p = proof, box = g.proof
        // The heading row: the difference is the title, its verdict beside it as the Display P3 row writes it, the method's menu at the right.
        let b = Self.proofRow * u + line
        let title = Design.attributed(p.difference.map { String(format: "\u{0394}E %.1f", $0) } ?? "\u{0394}E \u{2014}", .body)
        let verdict = p.print == nil ? "Not Worked Out" : p.inRange ? "In Range" : "Out Of Range"
        title.draw(x: 0, baseline: b)
        let menu = drawMenu(method.label, right: g.lw, top: Self.proofRow * u)
        hits.append((menu, .method))
        tip(menu, "The Method The House Compares Colours By")
        Design.attributed(verdict, .caption, colour: p.inRange || p.print == nil ? Design.quiet : Design.ink)
            .draw(x: title.size().width + 12, baseline: b, width: menu.minX - title.size().width - 24)
        hairline(x: 0, y: box.minY - 1, width: g.lw, Design.rule)

        // The two colours, edge to edge so the eye compares them with no paper between: the master, then what the press prints.
        let half = g.n / 2
        let huesWidth = half > 1 ? g.x(half - 1) - g.gutter : ((g.lw - g.gutter) / 2).rounded()
        let left = NSRect(x: 0, y: box.minY, width: (huesWidth / 2).rounded(), height: box.height)
        let right = NSRect(x: left.maxX, y: box.minY, width: huesWidth - left.width, height: box.height)
        fill(left, p.master)
        fill(right, p.print ?? Design.mist)
        // Each named inside, at its top left, in whichever of ink and paper reads on it.
        func name(_ s: String, in r: NSRect, on lab: LabD50?) {
            Design.attributed(s, .caption, colour: (lab?.l ?? 100) > 60 ? Design.ink : Design.paper).draw(x: r.minX + 8, baseline: r.minY + line, width: r.width - 16)
        }
        name("Master", in: left, on: p.masterLab)
        name(p.print == nil ? "Not Worked Out" : "Print", in: right, on: p.printLab)
        let press = values.first { $0.label == "Press" }?.value ?? "", intent = values.first { $0.label == "Intent" }?.value ?? ""
        tip(left, "The Master Colour, As The Screen Shows It")
        tip(right, p.print == nil ? "The Press Profile Is Not On This Mac" : "What \(press) Prints, \(intent), As The Screen Shows It")

        // The working, in the last column: each L*a*b* under its label, then the difference as the numeral on the block's bottom line.
        let cx = huesWidth + g.gutter, cw = g.lw - cx
        Design.attributed("Master L*a*b*", .caption, colour: Design.quiet).draw(x: cx, baseline: box.minY + line, width: cw)
        labText(p.masterLab, width: cw).draw(x: cx, baseline: box.minY + u + line)
        Design.attributed("Print L*a*b*", .caption, colour: Design.quiet).draw(x: cx, baseline: box.minY + 2 * u + line, width: cw)
        labText(p.printLab, width: cw).draw(x: cx, baseline: box.minY + 3 * u + line)
        Design.attributed(method.short, .caption, colour: Design.quiet).draw(x: cx, baseline: box.minY + 4 * u + line, width: cw)
        let numeral = p.difference.map { d in fitted([String(format: "%.1f", d), String(format: "%.0f", d)], .numeral, width: cw) }
            ?? Design.attributed("\u{2014}", .numeral)
        (numeral.size().width <= cw ? numeral : Design.attributed(numeral.string, .headline)).draw(right: g.lw, baseline: box.maxY)

        // The note, a unit of air under the colours: the method and how to read it, then what the two colours are: previews through Display P3, never the sheet.
        Design.attributed(method.note + " Both are previews through Display P3, not the printed sheet.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: box.maxY + u, width: g.lw, height: Self.proofNoteUnits * u))
    }

    // MARK: The wheel: the artists' disc, the spokes, and the colours as squares

    private static let disc: NSImage? = WheelView.disc().map { NSImage(cgImage: $0, size: NSSize(width: 512, height: 512)) }
    private static let node: CGFloat = 14, baseNode: CGFloat = 18
    private func radius(_ g: Geometry) -> CGFloat { g.wheel.width / 2 - Self.baseNode / 2 - 2 }
    private func centre(_ g: Geometry) -> NSPoint { NSPoint(x: g.wheel.midX, y: g.wheel.midY) }
    /// Where a colour sits: the wheel's y runs up, the page's down.
    private func place(_ n: LabNode, _ g: Geometry) -> NSPoint {
        let p = n.point, c = centre(g), r = radius(g)
        return NSPoint(x: c.x + CGFloat(p.x) * r, y: c.y - CGFloat(p.y) * r)
    }

    private func drawWheel(_ g: Geometry) {
        let c = centre(g), r = radius(g)
        let rim = NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rim).addClip()
        Self.disc?.draw(in: rim, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        Design.rule.setStroke()
        let edge = NSBezierPath(ovalIn: rim.insetBy(dx: -0.5, dy: -0.5)); edge.lineWidth = 1; edge.stroke()
        // The spokes tie the colours to the centre while a rule holds them; with none there is nothing to tie.
        if state.rule != .custom {
            Design.ink.setStroke()
            let spokes = NSBezierPath(); spokes.lineWidth = 1
            for n in state.nodes { spokes.move(to: c); spokes.line(to: place(n, g)) }
            spokes.stroke()
        }
        // The base last, so a colour sharing its place never hides it.
        let order = state.nodes.indices.filter { $0 != state.base } + [state.base]
        for i in order where state.nodes.indices.contains(i) {
            let n = state.nodes[i], p = place(n, g), isBase = i == state.base
            let s = isBase ? Self.baseNode : Self.node
            let sq = NSRect(x: (p.x - s / 2).rounded(), y: (p.y - s / 2).rounded(), width: s, height: s)
            // A card edge inside the ink, so the colour reads apart from the ink and the ink from the wheel.
            fill(sq.insetBy(dx: -2, dy: -2), Design.ink)
            fill(sq.insetBy(dx: -1, dy: -1), Design.card)
            fill(sq, shades.indices.contains(i) ? shades[i] : Design.hex(n.hex))
            let mark = Design.hex(readableText(on: n.hex))
            if isBase { fill(NSRect(x: sq.midX - 2, y: sq.midY - 2, width: 4, height: 4), mark) }
            if n.locked && !isBase { lockGlyph(in: NSRect(x: sq.midX - 4, y: sq.midY - 4, width: 8, height: 8), colour: mark, filled: true) }
            if state.rule == .custom && i == selected {
                Design.ink.setStroke()
                let ring = NSBezierPath(rect: sq.insetBy(dx: -4.5, dy: -4.5)); ring.lineWidth = 1; ring.stroke()
            }
            hits.append((sq.insetBy(dx: -6, dy: -6), .node(i)))
        }
    }

    /// The nine rules as the guide's Choice: cells in a one-point ink outline, the chosen one filled ink, each drawn as its own arrangement.
    private func drawRules(_ g: Geometry) {
        let rules = LabRule.allCases, box = g.choice
        for (k, rule) in rules.enumerated() {
            let x0 = (box.minX + box.width * CGFloat(k) / CGFloat(rules.count)).rounded(), x1 = (box.minX + box.width * CGFloat(k + 1) / CGFloat(rules.count)).rounded()
            let cell = NSRect(x: x0, y: box.minY, width: x1 - x0, height: box.height)
            let on = rule == state.rule
            if on { fill(cell, Design.ink) } else if hover == .rule(rule) { fill(cell, Design.mist) }
            diagram(rule, in: cell, colour: on ? Design.card : Design.ink)
            hits.append((cell, .rule(rule)))
            addToolTip(cell, owner: rule.title as NSString, userData: nil)
        }
        Design.ink.setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); outline.lineWidth = 1; outline.stroke()
        for k in 1..<rules.count {
            let x = (box.minX + box.width * CGFloat(k) / CGFloat(rules.count)).rounded()
            fill(NSRect(x: x, y: box.minY, width: 1, height: box.height), Design.ink)
        }
    }

    /// A rule's shape: a ring, and a dot for each hue it holds, spokes to them when the rule ties them. Drawn from the rule's own arrangement.
    private func diagram(_ rule: LabRule, in cell: NSRect, colour: NSColor) {
        let c = NSPoint(x: cell.midX, y: cell.midY), r = min(cell.width, cell.height) / 2 - 3
        colour.setStroke(); colour.setFill()
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ring.lineWidth = 0.75; ring.stroke()
        var dots: [(Double, Double)] = []
        if let made = rule.arrangement(around: LabNode(h: 90, s: 1, v: 1)) {
            let oneHue = Set(made.nodes.map { Int($0.h.rounded()) }).count == 1
            for n in made.nodes {
                let p = oneHue ? n.point : LabNode(h: n.h, s: 1, v: 1).point
                if !dots.contains(where: { hypot($0.0 - p.x, $0.1 - p.y) < 0.45 }) { dots.append((p.x, p.y)) }
            }
        } else { dots = [(-0.45, 0.35), (0.5, 0.15), (-0.05, -0.55)] }
        let points = dots.map { NSPoint(x: c.x + CGFloat($0.0) * r, y: c.y - CGFloat($0.1) * r) }
        if rule != .custom {
            let spokes = NSBezierPath(); spokes.lineWidth = 1
            for p in points { spokes.move(to: c); spokes.line(to: p) }
            spokes.stroke()
        }
        for p in points { NSRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3).fill() }
    }

    /// The guide's slider: a one-point ink track, a 14 hollow knob on the line, a glyph at each end saying which way is more, the value as a caption on the right.
    private func drawSlider(_ g: Geometry) {
        let u = Self.u, b = 14 * u + Self.line
        let label = Design.attributed("Brightness", .caption, colour: Design.quiet)
        label.draw(x: g.rx, baseline: b)
        let valueBox: CGFloat = 40
        let x0 = g.rx + label.size().width + 12 + 9 + 8, x1 = g.rx + g.rw - valueBox - 9 - 8
        // Darker: a filled square; lighter: a hollow one; both sitting on the line.
        fill(NSRect(x: x0 - 17, y: b - 9, width: 9, height: 9), Design.ink)
        Design.ink.setStroke()
        let light = NSBezierPath(rect: NSRect(x: x1 + 8.5, y: b - 8.5, width: 8, height: 8)); light.lineWidth = 1; light.stroke()
        fill(NSRect(x: x0, y: b - 7, width: x1 - x0, height: 1), Design.ink)
        let v = state.nodes.indices.contains(working) ? state.nodes[working].v : 1
        let t = CGFloat(min(max((v - Self.darkest) / (1 - Self.darkest), 0), 1))
        let knob = NSRect(x: (x0 + t * (x1 - x0) - 7).rounded(), y: b - 14, width: 14, height: 14)
        fill(knob, Design.card)
        let k = NSBezierPath(rect: knob.insetBy(dx: 0.5, dy: 0.5)); k.lineWidth = 1; k.stroke()
        Design.attributed("\(Int((v * 100).rounded()))%", .caption, colour: Design.quiet).draw(right: g.rx + g.rw, baseline: b)
        hits.append((NSRect(x: x0 - 7, y: 14 * u, width: x1 - x0 + 14, height: u), .slider))
        trackSpan = (x0, x1)
    }
    private var trackSpan: (CGFloat, CGFloat) = (0, 1)

    // MARK: The colours: square tiles on the columns

    private func drawTiles(_ g: Geometry, tip: (NSRect, String) -> Void) {
        let u = Self.u, line = Self.line
        // The second-order header across the right side, on the proof's row, the model the values are written in at its right.
        Design.attributed("Colours", .body).draw(x: g.rx, baseline: g.coloursTop + line)
        hits.append((drawMenu(format.label, right: g.w, top: g.coloursTop), .format))
        hairline(x: g.rx, y: g.tilesTop - 1, width: g.rw, Design.rule)

        for (i, n) in state.nodes.enumerated() {
            let r = g.tile(i), key = definition(of: i).key
            let block = NSRect(x: r.minX, y: r.minY, width: r.width, height: Self.blockUnits * u)
            fill(block, shades.indices.contains(i) ? shades[i] : Design.hex(n.hex))
            hits.append((block, .block(i)))
            tip(block, "Click To Copy \(format.label)  \(format.text(key, lowercase: Prefs.lowercaseHex))")
            // The words: the name, Medium with the chosen dot when it is the base; the value in the chosen model.
            let isBase = i == state.base
            let nb = block.maxY + line, vb = block.maxY + u + line
            let name = Design.attributed(definition(of: i).name, isBase ? .bodyStrong : .body)
            let nameWidth = r.width - (isBase ? 10 : 0)
            name.draw(x: r.minX, baseline: nb, width: nameWidth)
            if isBase { fill(NSRect(x: r.minX + min(name.size().width, nameWidth) + 6, y: nb - 6, width: 4, height: 4), Design.ink) }
            hits.append((NSRect(x: r.minX, y: block.maxY, width: r.width, height: u), .name(i)))
            tip(NSRect(x: r.minX, y: block.maxY, width: r.width, height: u), state.rule == .custom ? "Ring This Colour And Make It The Base" : "Build The Harmony On This Colour")
            Design.attributed(format.text(key, lowercase: Prefs.lowercaseHex), .caption, colour: Design.quiet).draw(x: r.minX, baseline: vb, width: r.width)
            // Base, Lock and Delete: the guide's icons along the block's top, at its right, under the pointer; a closed lock always shows.
            let s: CGFloat = 24
            let icons: [(Hit, Bool, String)] = [(.base(i), hoverTile == i, isBase ? "The Base Colour" : "Set As Base"),
                                                (.lock(i), hoverTile == i || n.locked, n.locked ? "Unlock" : "Lock: Keep This Colour When The Others Change"),
                                                (.bin(i), hoverTile == i && state.nodes.count > 1, "Delete")]
            for (k, icon) in icons.enumerated() where icon.1 {
                let cell = NSRect(x: block.maxX - CGFloat(icons.count - k) * s, y: block.minY, width: s, height: s)
                fill(cell, hover == icon.0 ? Design.mist : Design.card)
                Design.rule.setStroke()
                let e = NSBezierPath(rect: cell.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                let glyph = cell.insetBy(dx: 7, dy: 7)
                switch icon.0 {
                case .base:
                    Design.ink.setStroke()
                    let sq = NSBezierPath(rect: glyph.insetBy(dx: 0.5, dy: 0.5)); sq.lineWidth = 1; sq.stroke()
                    fill(NSRect(x: glyph.midX - 2, y: glyph.midY - 2, width: 4, height: 4), Design.ink)
                    if isBase { fill(glyph, Design.ink); fill(NSRect(x: glyph.midX - 2, y: glyph.midY - 2, width: 4, height: 4), Design.card) }
                case .lock: lockGlyph(in: glyph, colour: Design.ink, filled: n.locked)
                default: binGlyph(in: glyph)
                }
                hits.insert((cell, icon.0), at: 0)
                tip(cell, icon.2)
            }
        }
    }

    /// A padlock: the shackle over the body, the body filled when it is shut.
    private func lockGlyph(in r: NSRect, colour: NSColor, filled: Bool) {
        colour.setStroke(); colour.setFill()
        let body = NSRect(x: r.minX, y: r.minY + r.height * 0.45, width: r.width, height: r.height * 0.55)
        let shackle = NSBezierPath(); shackle.lineWidth = 1.2
        let sx0 = r.minX + r.width * 0.22, sx1 = filled ? r.maxX - r.width * 0.22 : r.maxX + r.width * 0.15
        shackle.move(to: NSPoint(x: sx0, y: body.minY)); shackle.line(to: NSPoint(x: sx0, y: r.minY + 0.6))
        shackle.line(to: NSPoint(x: sx1 - (filled ? 0 : r.width * 0.37), y: r.minY + 0.6))
        if filled { shackle.line(to: NSPoint(x: sx1, y: body.minY)) } else { shackle.line(to: NSPoint(x: sx1 - r.width * 0.37, y: r.minY + r.height * 0.3)) }
        shackle.stroke()
        if filled { body.fill() } else { let b = NSBezierPath(rect: body.insetBy(dx: 0.5, dy: 0.5)); b.lineWidth = 1; b.stroke() }
    }
    /// The bin, as the schema draws it: the lid with its handle, then the body.
    private func binGlyph(in r: NSRect) {
        Design.ink.setStroke()
        let p = NSPoint(x: r.minX, y: r.minY), s = r.width - 1, path = NSBezierPath()
        path.lineWidth = 1.2
        path.move(to: NSPoint(x: p.x, y: p.y + 2)); path.line(to: NSPoint(x: p.x + s + 1, y: p.y + 2))
        path.move(to: NSPoint(x: p.x + 3, y: p.y + 2)); path.line(to: NSPoint(x: p.x + 3, y: p.y)); path.line(to: NSPoint(x: p.x + s - 2, y: p.y)); path.line(to: NSPoint(x: p.x + s - 2, y: p.y + 2))
        path.move(to: NSPoint(x: p.x + 1.5, y: p.y + 2)); path.line(to: NSPoint(x: p.x + 2.5, y: p.y + s + 1)); path.line(to: NSPoint(x: p.x + s - 1.5, y: p.y + s + 1)); path.line(to: NSPoint(x: p.x + s - 0.5, y: p.y + 2))
        path.stroke()
    }

    // MARK: The pointer

    private func hit(at p: NSPoint) -> Hit? { hits.first { $0.0.contains(p) }?.1 }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        guard let h = hit(at: p) else { return }
        switch h {
        case .node(let i):
            dragging = h
            gestureStart = state
            if state.rule == .custom { selected = i; refresh() }
        case .slider:
            dragging = h
            gestureStart = state
            slide(to: p.x)
        case .rule(let r): change { $0.setRule(r) }
        case .block(let i): library.copy(definition(of: i).key, as: format)
        case .name(let i), .base(let i):
            if state.rule == .custom { selected = i }
            change { $0.makeBase(i) }
        case .lock(let i): change { $0.toggleLock(i) }
        case .bin(let i): change { $0.remove(i) }
        case .format: openFormats(under: hits.first { $0.1 == .format }?.0 ?? .zero)
        case .method: openMethods(under: hits.first { $0.1 == .method }?.0 ?? .zero)
        case .illuminant: openIlluminants(under: hits.first { $0.1 == .illuminant }?.0 ?? .zero)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch dragging {
        case .node(let i)?:
            let g = geometry(width: bounds.width), c = centre(g), r = radius(g)
            let polar = LabNode.polar(x: Double((p.x - c.x) / r), y: Double((c.y - p.y) / r))
            state.move(i, h: polar.h, s: polar.s)
            refresh()
        case .slider?: slide(to: p.x)
        default: break
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        endGesture()
    }
    private func slide(to x: CGFloat) {
        let t = Double(min(max((x - trackSpan.0) / max(1, trackSpan.1 - trackSpan.0), 0), 1))
        state.setBrightness(Self.darkest + t * (1 - Self.darkest), of: working)
        refresh()
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), g = geometry(width: bounds.width)
        let h = hit(at: p)
        let tile = state.nodes.indices.first { g.tile($0).contains(p) }
        if h != hover || tile != hoverTile { hover = h; hoverTile = tile; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if hover != nil || hoverTile != nil { hover = nil; hoverTile = nil; needsDisplay = true } }

    // MARK: Actions

    @objc private func randomTapped() { change { $0.randomise { Double.random(in: 0..<1) } } }
    @objc private func addTapped() { change { $0.add() } }
    @objc private func undoTapped() {
        guard let back = history.undo(from: state) else { return }
        state = back; save(); refresh()
    }
    @objc private func redoTapped() {
        guard let on = history.redo(from: state) else { return }
        state = on; save(); refresh()
    }
    /// Contrast on the Studio window, the page beside this one.
    @objc private func contrastTapped() { StudioWindowController.shared?.frame.go(.contrast) }

    // MARK: Keeping the colours: the house menus, opening upward from the button so the last row, the new one, is nearest the pointer

    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }
    private func openMenu(items: [String], chosen: String, width: CGFloat, from rect: NSRect, upward: Bool, pick: @escaping (Int) -> Void) {
        guard let win = window else { return }
        closeMenu()
        let panel = SwissDropdown.MenuPanel(items: items, chosen: chosen, width: width) { [weak self] i in self?.closeMenu(); pick(i) }
        let s = win.convertToScreen(convert(rect, to: nil))
        if upward { panel.setFrameOrigin(NSPoint(x: s.maxX - width, y: s.maxY + 4)) } else { panel.place(below: NSPoint(x: s.maxX - width, y: s.minY - 4)) }
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }
    /// How many rows a menu opening upward from a rect can show before it reaches the top of the screen.
    private func room(above rect: NSRect) -> Int {
        guard let win = window, let screen = win.screen else { return 12 }
        let s = win.convertToScreen(convert(rect, to: nil))
        return max(4, Int((screen.visibleFrame.maxY - s.maxY - 40) / 30))
    }

    @objc private func paletteTapped() {
        let M = SwissDropdown.MenuPanel.self
        // The palettes most lately made or placed first, as many as the screen has room for, then New Palette nearest the pointer.
        let fits = min(20, room(above: toPalette.frame) - 3)
        let all = library.paletteOrder
        let list = all.count <= fits ? all : Array(all.sorted { ($0.placedAt ?? $0.createdAt) > ($1.placedAt ?? $1.createdAt) }.prefix(fits))
        var items = [M.heading(all.count <= fits ? "Palettes" : "Latest Palettes")] + list.map { $0.name }
        items += [M.divider, "New Palette"]
        let colours = keys, name = chosenName
        openMenu(items: items, chosen: "", width: max(240, toPalette.frame.width), from: toPalette.frame, upward: true) { [weak self] i in
            guard let self = self else { return }
            if i == items.count - 1 { self.library.keep(colours, named: name, in: nil); return }
            let k = i - 1
            if list.indices.contains(k) { self.library.add(colours, to: list[k].id) }
        }
    }
    @objc private func projectTapped() {
        let M = SwissDropdown.MenuPanel.self
        let fits = min(20, room(above: toProject.frame) - 3)
        let projects = Array(library.library.orderedProjects.prefix(fits))
        var items = [M.heading("Projects")] + (projects.isEmpty ? [M.heading("None yet")] : projects.map { $0.name })
        items += [M.divider, "New Project\u{2026}"]
        let colours = keys, name = chosenName
        openMenu(items: items, chosen: "", width: max(240, toProject.frame.width), from: toProject.frame, upward: true) { [weak self] i in
            guard let self = self else { return }
            if i == items.count - 1 { self.library.startProject(keeping: colours, named: name); return }
            let k = i - 1
            if projects.indices.contains(k) { self.library.keep(colours, named: name, in: projects[k].id) }
        }
    }
    private func openFormats(under rect: NSRect) {
        let models = StudioPage.models
        openMenu(items: models.map { $0.label }, chosen: format.label, width: 160, from: rect, upward: false) { [weak self] i in
            self?.format = models[i]
            self?.needsDisplay = true
        }
    }

    private func openIlluminants(under rect: NSRect) {
        let all = Illuminant.allCases
        openMenu(items: all.map { $0.label }, chosen: illuminant.label, width: 160, from: rect, upward: false) { [weak self] i in
            self?.illuminant = all[i]
            self?.refresh()
        }
    }
    private func openMethods(under rect: NSRect) {
        let methods = DifferenceMethod.allCases
        openMenu(items: methods.map { $0.label }, chosen: method.label, width: 160, from: rect, upward: false) { [weak self] i in
            self?.method = methods[i]
            self?.refresh()
        }
    }

    // MARK: The name

    func controlTextDidChange(_ obj: Notification) { publish() }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { publish(); needsDisplay = true }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        window?.makeFirstResponder(self)
        return true
    }
}
