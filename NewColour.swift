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
    private var kind: Kind { Kind.offered.indices.contains(kinds.selectedSegment) ? Kind.offered[kinds.selectedSegment] : .p3 }

    /// `palette` names where the colour is going, for the message; `done` is handed the colour to add.
    init(palette: String?, press chosen: String, start: NewColourStart? = nil, done: @escaping (ColourDefinition) -> Void) {
        self.done = done
        super.init(frame: .zero)
        // Opens on the kind asked for, or the kind used last time.
        let first = start?.kind ?? preferences.integer(forKey: "newColourKind")
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

        let column = NSStackView(views: [heading, body, kinds, about, values, pressRow, preview, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.setCustomSpacing(8, after: heading)
        column.setCustomSpacing(8, after: kinds)
        column.setCustomSpacing(18, after: preview)
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
        for full in [heading, body, about, values, preview, bar] as [NSView] { full.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
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
            guard let colour = colour, let picked = ColourDefinition.picked(colour), let fill = NewColourSheet.fill(for: picked) else { return }
            playShutter()
            self.take(fill.kind, fill.values)
        }
    }

    /// What a picked colour is typed in as: its hex when sRGB holds it, as the main picker keeps
    /// it; otherwise its Display P3 values, 0 to 255, so a vivid colour is kept whole.
    static func fill(for picked: ColourDefinition) -> (kind: Kind, values: [String])? {
        if picked.source.space == RGBSpace.srgb.rawValue { return (.hex, [RGBSpace.srgb.text(picked.source.values)]) }
        guard picked.source.space == RGBSpace.displayP3.rawValue, picked.source.values.count == 3 else { return nil }
        return (.p3, picked.source.values.map { value in
            let text = String(format: "%.2f", value * 255)
            return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
        })
    }

    /// Shows `kind` with these values typed in.
    private func take(_ kind: Kind, _ values: [String]) {
        if let at = Kind.offered.firstIndex(of: kind), kinds.selectedSegment != at {
            kinds.selectedSegment = at
            shown = kind
            preferences.set(kind.rawValue, forKey: "newColourKind")
            show()
        }
        for (field, value) in zip(fields, values) { field.stringValue = value }
        valueChanged()
        window?.makeFirstResponder(fields[0])
    }

    private var shown = Kind.p3
    @objc private func kindChanged() {
        guard kind != shown else { return }
        shown = kind
        preferences.set(kind.rawValue, forKey: "newColourKind")
        show()
    }
    @objc private func valueChanged() { problem.stringValue = ""; update() }
    func controlTextDidChange(_ obj: Notification) { valueChanged() }

    @objc private func confirmTapped() {
        let result = typed
        guard let colour = result.colour else { problem.stringValue = result.problem; return }
        preferences.set(kind.rawValue, forKey: "newColourKind")
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
