import AppKit

// ---------- New Colour ----------
//
// A colour typed in as what it is: Display P3 values, a build of four inks for a press, Lab, or a
// hex. It is kept exactly as typed (see ColourIdentity.swift), with a master worked out from it,
// so a CMYK brand colour stays that build and a P3 colour stays as vivid as it was given.

final class NewColourSheet: NSView, NSTextFieldDelegate {
    enum Kind: Int, CaseIterable {
        case p3, cmyk, lab, hex, prophoto
        /// The order they are offered in; the raw values are kept in preferences, so new kinds go at the end.
        static let offered: [Kind] = [.p3, .prophoto, .cmyk, .lab, .hex]
        var title: String { ["Display P3", "CMYK", "Lab", "Hex", "ProPhoto"][rawValue] }
        var labels: [String] {
            switch self {
            case .p3, .prophoto: return ["Red", "Green", "Blue"]
            case .cmyk: return ["Cyan", "Magenta", "Yellow", "Black"]
            case .lab: return ["L*", "a*", "b*"]
            case .hex: return ["Hex"]
            }
        }
        var about: String {
            switch self {
            case .p3: return "Each value 0 to 255, in Display P3. A colour beyond sRGB is kept whole."
            case .prophoto: return "Each value 0 to 255, in ProPhoto RGB; decimals are kept. Wider than any screen."
            case .cmyk: return "Each ink 0 to 100, for the press chosen. The build is kept exactly as typed."
            case .lab: return "L* 0 to 100; a* and b* from \u{2212}128 to 127. Lab under D50, as print uses."
            case .hex: return "An sRGB colour, as #RRGGBB."
            }
        }
    }

    private let panel = NSView()
    private let done: (ColourDefinition) -> Void
    private lazy var kinds = ToggleBar(labels: Kind.offered.map { $0.title }, target: self, action: #selector(kindChanged))
    private let about = NSTextField(wrappingLabelWithString: "")
    private var fields: [NSTextField] = []
    private var captions: [NSTextField] = []
    private var columns: [NSStackView] = []
    private let press = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pressRow = NSStackView()
    private let chip = NSView()
    private let readout = NSTextField(wrappingLabelWithString: "")
    private let problem = caption("")
    private let working = NSTextField(wrappingLabelWithString: "")
    /// The colour last picked from the screen, while the values on show are still its conversion.
    private var picked: ColourDefinition?
    private var kind: Kind { Kind.offered.indices.contains(kinds.selectedSegment) ? Kind.offered[kinds.selectedSegment] : .p3 }

    /// `palette` names where the colour is going, for the message; `done` is handed the colour to add.
    init(palette: String?, press chosen: String, start: NewColourStart? = nil, done: @escaping (ColourDefinition) -> Void) {
        self.done = done
        super.init(frame: .zero)
        // Opens on the kind asked for, or the kind used last time.
        let first = start?.kind ?? AppPreferences.shared.integer(forKey: "newColourKind")
        kinds.selectedSegment = Kind(rawValue: first).flatMap { Kind.offered.firstIndex(of: $0) } ?? 0
        shown = kind
        let chosen = start?.press ?? chosen
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.shadow = { let s = NSShadow(); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -8); s.shadowColor = NSColor.black.withAlphaComponent(0.45); return s }()

        let heading = NSTextField(wrappingLabelWithString: "New Colour")
        heading.font = PageStyle.titleFont
        let body = NSTextField(wrappingLabelWithString: palette.map { "Type the colour as it was given to you. It goes into \u{201C}\($0)\u{201D}." }
                               ?? "Type the colour as it was given to you. It goes into All Swatches.")
        body.font = NSFont.systemFont(ofSize: TextSize.body)
        body.textColor = .secondaryLabelColor
        about.font = NSFont.systemFont(ofSize: TextSize.caption)
        about.textColor = .secondaryLabelColor

        for _ in 0..<4 {
            let field = NSTextField()
            field.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.body, weight: .regular)
            field.bezelStyle = .roundedBezel
            field.focusRingType = .none
            field.delegate = self
            let label = caption("")
            let column = NSStackView(views: [label, field])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 4
            field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            fields.append(field); captions.append(label); columns.append(column)
        }
        let values = NSStackView(views: columns)
        values.orientation = .horizontal
        values.distribution = .fillEqually
        values.spacing = PageStyle.barSpacing

        press.addItems(withTitles: PressProfiles.all.map { $0.name })
        if press.itemTitles.contains(chosen) { press.selectItem(withTitle: chosen) } else { press.selectItem(withTitle: PressProfiles.generic) }
        press.font = NSFont.systemFont(ofSize: TextSize.body)
        press.target = self
        press.action = #selector(valueChanged)
        let pressLabel = caption("Press")
        pressRow.setViews([pressLabel, press], in: .leading)
        pressRow.orientation = .vertical
        pressRow.alignment = .leading
        pressRow.spacing = 4

        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.cornerCurve = .continuous
        chip.layer?.borderWidth = 1
        readout.font = NSFont.systemFont(ofSize: TextSize.body)
        readout.textColor = .secondaryLabelColor
        let preview = NSStackView(views: [chip, readout])
        preview.orientation = .horizontal
        preview.alignment = .centerY
        preview.spacing = 12

        problem.textColor = .systemRed
        problem.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let bar = NSStackView(views: [toolButton("Pick", "eyedropper", "Pick A Colour From The Screen", target: self, action: #selector(pickTapped)),
                                      problem, spacer,
                                      toolButton("Cancel", "xmark", "Cancel (Escape)", target: self, action: #selector(cancelTapped)),
                                      toolButton("Add Colour", "plus", "Add Colour (Return)", target: self, action: #selector(confirmTapped))])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = PageStyle.barSpacing

        working.isHidden = true
        working.isSelectable = true
        let column = NSStackView(views: [heading, body, kinds, about, values, pressRow, preview, working, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.setCustomSpacing(8, after: heading)
        column.setCustomSpacing(8, after: kinds)
        column.setCustomSpacing(18, after: preview)
        column.setCustomSpacing(18, after: working)
        column.translatesAutoresizingMaskIntoConstraints = false
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        panel.addSubview(column)
        let pad = SwatchListStyle.sheetPad
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: 520),
            column.topAnchor.constraint(equalTo: panel.topAnchor, constant: pad),
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: pad),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -pad),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -pad),
            chip.widthAnchor.constraint(equalToConstant: 56),
            chip.heightAnchor.constraint(equalToConstant: 56),
            kinds.heightAnchor.constraint(equalToConstant: ButtonStyle.height),
        ])
        for full in [heading, body, about, values, preview, working, bar] as [NSView] { full.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        show()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(over page: NSView) {
        guard let root = page.window?.contentView else { return }
        root.addSubview(self, positioned: .above, relativeTo: nil)
        let across = panel.centerXAnchor.constraint(equalTo: page.centerXAnchor)
        across.priority = .defaultHigh
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: root.topAnchor),
            bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trailingAnchor.constraint(equalTo: root.trailingAnchor),
            across,
            panel.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 8),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
        ])
        // After the click that opened the sheet has finished, or the grid takes the focus back.
        DispatchQueue.main.async { [weak self] in if let self = self { self.window?.makeFirstResponder(self.fields[0]) } }
        // For a trial run: MMFFDEV_COLOUR3_PICK is a hex, or "vivid" for a colour beyond sRGB, taken as if picked from the screen.
        let env = ProcessInfo.processInfo.environment
        if env["MMFFDEV_COLOUR3_HOME"] != nil, let ask = env["MMFFDEV_COLOUR3_PICK"] {
            picked = ask == "vivid" ? ColourDefinition.displayP3([1, 0.1, 0.2]) : ColourDefinition.of(hex: ask)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.convertPick() }
        }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        panel.layer?.backgroundColor = Theme.grey(0.05).cgColor
        panel.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
        chip.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
    }

    /// Lays the fields out for the kind chosen.
    private func show() {
        let labels = kind.labels
        for (i, column) in columns.enumerated() {
            column.isHidden = i >= labels.count
            if i < labels.count { captions[i].stringValue = labels[i] }
            fields[i].stringValue = ""
            fields[i].placeholderString = kind == .hex ? "#4F8093" : "0"
        }
        about.stringValue = kind.about
        pressRow.isHidden = kind != .cmyk
        problem.stringValue = ""
        update()
        window?.makeFirstResponder(fields[0])
    }

    /// Reads what is typed: the colour, or what is wrong with it. Static so it can be tested without a window.
    static func read(_ kind: Kind, _ typed: [String], press: String) -> (colour: ColourDefinition?, problem: String) {
        let texts = typed.prefix(kind.labels.count).map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "\u{2212}", with: "-") }
        if kind == .hex {
            guard let hex = normaliseHex(texts.first ?? ""), let colour = ColourDefinition.of(hex: hex) else { return (nil, "A hex is six digits, such as #4F8093.") }
            return (colour, "")
        }
        // The greyed 0 in an empty field means what it says: once anything is typed, an empty field is 0.
        guard texts.contains(where: { !$0.isEmpty }) else { return (nil, "Type at least one value.") }
        let numbers = texts.compactMap { $0.isEmpty ? 0 : Double($0) }
        guard numbers.count == kind.labels.count else { return (nil, "Each value is a number.") }
        switch kind {
        case .p3:
            guard numbers.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return (nil, "Each value is 0 to 255.") }
            return (ColourDefinition.displayP3(numbers.map { $0 / 255 }), "")
        case .prophoto:
            guard numbers.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return (nil, "Each value is 0 to 255.") }
            return (ColourDefinition.prophoto(numbers.map { $0 / 255 }), "")
        case .cmyk:
            guard numbers.allSatisfy({ $0 >= 0 && $0 <= 100 }) else { return (nil, "Each ink is 0 to 100.") }
            guard let colour = ColourDefinition.cmyk(numbers.map { $0 / 100 }, press: press) else { return (nil, "The press profile \u{201C}\(press)\u{201D} is not on this Mac.") }
            return (colour, "")
        case .lab:
            guard numbers[0] >= 0, numbers[0] <= 100, numbers[1] >= -128, numbers[1] <= 127, numbers[2] >= -128, numbers[2] <= 127 else { return (nil, "L* is 0 to 100; a* and b* are \u{2212}128 to 127.") }
            return (ColourDefinition.lab(numbers[0], numbers[1], numbers[2]), "")
        case .hex: return (nil, "")
        }
    }

    private var typed: (colour: ColourDefinition?, problem: String) {
        NewColourSheet.read(kind, fields.map { $0.stringValue }, press: press.titleOfSelectedItem ?? PressProfiles.generic)
    }

    /// The preview follows the typing: the colour as this screen shows it, and whether sRGB can hold it.
    private func update() {
        guard let colour = typed.colour else {
            chip.layer?.backgroundColor = NSColor.clear.cgColor
            readout.stringValue = "The colour shows here as you type."
            return
        }
        let v = RGBSpace.displayP3.values(of: colour.master).map { CGFloat(min(max($0, 0), 1)) }
        chip.layer?.backgroundColor = NSColor(displayP3Red: v[0], green: v[1], blue: v[2], alpha: 1).cgColor
        let shown = RGBSpace.srgb.text(RGBSpace.srgb.values(of: colour.master))
        var lines = [colour.fitsSRGB ? "sRGB shows it as \(shown)." : "Beyond sRGB: the nearest sRGB can show is \(shown). Kept whole."]
        if kind == .cmyk { lines.append("Total Ink \(Int((colour.source.values.reduce(0, +) * 100).rounded()))%") }
        readout.stringValue = lines.joined(separator: "\n")
    }

    // MARK: Picking from the screen

    private var sampler: NSColorSampler?

    /// The screen picker, as the main one: the loupe, then the colour under it. What it picks
    /// fills the sheet, to be looked at or changed before it is added. Escape in the loupe picks nothing.
    @objc private func pickTapped() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] colour in
            guard let self = self else { return }
            self.sampler = nil
            guard let colour = colour, let picked = ColourDefinition.picked(colour) else { return }
            playShutter()
            self.picked = picked
            self.convertPick()
        }
    }

    /// A pick turned into values for one kind of colour, with the arithmetic that got there.
    struct Conversion {
        /// The kind the values are for: the one asked for, or Display P3 when a hex cannot hold the colour.
        let kind: Kind
        let values: [String]
        /// Each step as what it gives and how: "XYZ D50  0.4310  0.2312  0.0190", "Display P3 matrix…".
        let working: [(step: String, how: String)]
    }

    /// Converts a picked colour into `kind`, showing the working. A pick is sRGB or Display P3;
    /// every conversion goes through the master, XYZ under D50. A hex that cannot hold the colour
    /// becomes Display P3 instead, so nothing is flattened. CMYK goes through the press's profile.
    static func convert(_ picked: ColourDefinition, to kind: Kind, press: String) -> Conversion? {
        guard let from = RGBSpace(rawValue: picked.source.space), picked.source.values.count == 3 else { return nil }
        func n(_ v: [Double], _ places: Int = 4) -> String { v.map { String(format: "%.\(places)f", $0) }.joined(separator: "  ") }
        func typed(_ v: Double, _ places: Int = 2) -> String {
            var text = String(format: "%.\(places)f", v)
            if text.contains(".") { while text.hasSuffix("0") { text.removeLast() }; if text.hasSuffix(".") { text.removeLast() } }
            return text == "-0" ? "0" : text
        }
        let m = picked.master
        var steps: [(step: String, how: String)] = [
            ("Picked     \(from.name)  \(n(picked.source.values))" + (from == .srgb ? "  (\(RGBSpace.srgb.text(picked.source.values)))" : ""),
             "What the screen showed, each value 0 to 1."),
        ]
        func toMaster() {
            steps.append(("Linear     \(n(picked.source.values.map(from.linear)))", "The screen curve undone: ((v + 0.055) \u{00F7} 1.055)^2.4, or v \u{00F7} 12.92 near black."))
            steps.append(("XYZ D50    \(n([m.x, m.y, m.z]))", "The \(from.name) matrix, then the white moved from D65 to D50 (Bradford). This is the master."))
        }
        func rgb(_ space: RGBSpace, _ kind: Kind, curve: String) -> Conversion {
            if from == space {
                steps.append(("\(space.name)   \(n(picked.source.values.map { $0 * 255 }, 2))", "Already \(space.name): each value \u{00D7} 255, nothing converted."))
                return Conversion(kind: kind, values: picked.source.values.map { typed($0 * 255) }, working: steps)
            }
            toMaster()
            let linear = space.linearValues(of: m), encoded = linear.map(space.encoded)
            steps.append(("Linear     \(n(linear))", "The inverse \(space.name) matrix, from XYZ under its own white."))
            steps.append(("Encoded    \(n(encoded))", "The \(space.name) curve put on: \(curve)."))
            steps.append(("\(space.name)   \(n(encoded.map { $0 * 255 }, 2))", "Each value \u{00D7} 255."))
            return Conversion(kind: kind, values: encoded.map { typed($0 * 255) }, working: steps)
        }
        switch kind {
        case .hex:
            if from == .srgb {
                steps.append(("Hex        \(RGBSpace.srgb.text(picked.source.values))", "Already sRGB: each value \u{00D7} 255 in hexadecimal, nothing converted."))
                return Conversion(kind: .hex, values: [RGBSpace.srgb.text(picked.source.values)], working: steps)
            }
            // A pick is only kept as Display P3 when sRGB cannot hold it, so a hex would flatten it.
            var kept = rgb(.displayP3, .p3, curve: "")
            let nearest = RGBSpace.srgb.text(RGBSpace.srgb.values(of: m))
            kept = Conversion(kind: .p3, values: kept.values, working: kept.working + [("No hex     nearest is \(nearest)", "sRGB cannot hold this colour, so it is kept as Display P3 instead.")])
            return kept
        case .p3: return rgb(.displayP3, .p3, curve: "1.055 \u{00D7} v^(1 \u{00F7} 2.4) \u{2212} 0.055, or 12.92 \u{00D7} v near black")
        case .prophoto: return rgb(.prophoto, .prophoto, curve: "v^(1 \u{00F7} 1.8), or 16 \u{00D7} v near black")
        case .lab:
            toMaster()
            let lab = m.lab
            steps.append(("L*         \(typed(lab.l))", "116 \u{00D7} f(Y \u{00F7} Yn) \u{2212} 16, where f is the cube root and n is the D50 white."))
            steps.append(("a*         \(typed(lab.a))", "500 \u{00D7} (f(X \u{00F7} Xn) \u{2212} f(Y \u{00F7} Yn))."))
            steps.append(("b*         \(typed(lab.b))", "200 \u{00D7} (f(Y \u{00F7} Yn) \u{2212} f(Z \u{00F7} Zn))."))
            return Conversion(kind: .lab, values: [typed(lab.l), typed(lab.a), typed(lab.b)], working: steps)
        case .cmyk:
            toMaster()
            guard let build = PrintBuild.of(m, press: press, intent: .relative) else { return nil }
            let inks = build.inks.map { ($0 * 100).rounded() }
            let off = deltaE2000(m.lab, build.printed.lab)
            steps.append(("CMYK       \(inks.map { typed($0, 0) }.joined(separator: "  "))",
                          "Through the profile \u{201C}\(press)\u{201D}, relative colorimetric. A profile is a table measured from the press, not a formula."))
            steps.append(("Prints     \(String(format: "%.1f", off)) \u{0394}E2000 from the pick",
                          off > Rendering.visible ? "Beyond this press: this is the nearest build it can print, and it will not match the screen."
                                                             : "Within this press: the build prints as the colour that was picked."))
            return Conversion(kind: .cmyk, values: inks.map { typed($0, 0) }, working: steps)
        }
    }

    /// Turns the pick into the kind on show, types the values in and shows the working.
    private func convertPick() {
        guard let picked = picked,
              let made = NewColourSheet.convert(picked, to: kind, press: press.titleOfSelectedItem ?? PressProfiles.generic) else {
            if self.picked != nil { problem.stringValue = "The press profile is not on this Mac, so the pick cannot be turned into inks." }
            return
        }
        if let at = Kind.offered.firstIndex(of: made.kind), kinds.selectedSegment != at { kinds.selectedSegment = at }
        if shown != made.kind {
            shown = made.kind
            AppPreferences.shared.set(made.kind.rawValue, forKey: "newColourKind")
        }
        show()
        for (field, value) in zip(fields, made.values) { field.stringValue = value }
        problem.stringValue = ""
        update()
        let text = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .medium), plain = NSFont.systemFont(ofSize: TextSize.caption)
        for (at, line) in made.working.enumerated() {
            text.append(NSAttributedString(string: (at == 0 ? "" : "\n") + line.step + "\n", attributes: [.font: mono, .foregroundColor: NSColor.labelColor]))
            text.append(NSAttributedString(string: line.how, attributes: [.font: plain, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        working.attributedStringValue = text
        working.isHidden = false
        window?.makeFirstResponder(fields[0])
    }

    /// The values were changed by hand: they are no longer the pick's conversion.
    private func forgetPick() {
        picked = nil
        working.isHidden = true
        working.stringValue = ""
    }

    private var shown = Kind.p3
    @objc private func kindChanged() {
        guard kind != shown else { return }
        shown = kind
        AppPreferences.shared.set(kind.rawValue, forKey: "newColourKind")
        // A pick follows the kind: the same colour, converted again.
        if picked != nil { convertPick() } else { show() }
    }
    /// The press was changed: a pick on show as inks is converted again for the new press.
    @objc private func valueChanged() {
        if picked != nil, kind == .cmyk { convertPick(); return }
        problem.stringValue = ""
        update()
    }
    func controlTextDidChange(_ obj: Notification) {
        forgetPick()
        problem.stringValue = ""
        update()
    }

    @objc private func confirmTapped() {
        let result = typed
        guard let colour = result.colour else { problem.stringValue = result.problem; return }
        AppPreferences.shared.set(kind.rawValue, forKey: "newColourKind")
        removeFromSuperview()
        done(colour)
    }
    @objc private func cancelTapped() { removeFromSuperview() }
    override func cancelOperation(_ sender: Any?) { cancelTapped() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { confirmTapped(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelTapped(); return true }
        // Tab goes round the values on show, and nowhere else.
        if selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)) {
            let count = kind.labels.count, here = fields.firstIndex { $0 === control } ?? 0
            let next = (here + (selector == #selector(NSResponder.insertTab(_:)) ? 1 : count - 1)) % count
            window?.makeFirstResponder(fields[next])
            return true
        }
        return false
    }
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { cancelTapped() }
    }
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

// ---------- The blank swatch that adds one ----------

/// A blank swatch the size of its neighbours, with a ringed plus in the middle. Pressing it opens
/// New Colour. Drawn in the theme's button greys, so it never competes with the colours beside it.
final class AddSwatchTile: NSView {
    var onPress: (() -> Void)?
    private let radius: CGFloat
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)
        toolTip = "New Colour: Type It As Display P3, CMYK, Lab Or Hex (\u{21E7}\u{2318}K)"
        setAccessibilityRole(.button)
        setAccessibilityLabel("New Colour")
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let was = pressed
        pressed = false
        if was && inside { onPress?() }
    }
    // A blank swatch has no swatch menu; the click stops here rather than reaching the grid.
    override func rightMouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let fill = pressed ? Theme.buttonActiveBackground : hovering ? Theme.buttonHoverBackground : Theme.buttonRest
        let ink = (pressed ? Theme.buttonActiveText : hovering ? Theme.buttonHoverText : Theme.text).withAlphaComponent(hovering || pressed ? 0.9 : 0.5)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(0.14).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        // The ring and its plus: a fixed size, so the mark is the same on a card and on a row.
        let size: CGFloat = 44, arm: CGFloat = 9
        let ring = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        ink.setStroke()
        let circle = NSBezierPath(ovalIn: ring)
        circle.lineWidth = 1.5
        circle.stroke()
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: bounds.midX - arm, y: bounds.midY)); plus.line(to: NSPoint(x: bounds.midX + arm, y: bounds.midY))
        plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - arm)); plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + arm))
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        plus.stroke()
    }
}

/// The blank swatch as the last card of a palette's grid.
final class AddCard: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("addCard")
    let tile = AddSwatchTile(radius: 12)
    override func loadView() { view = tile }
    // Never shown as selected: it is a button, not a swatch.
    override var isSelected: Bool { get { false } set {} }
}
