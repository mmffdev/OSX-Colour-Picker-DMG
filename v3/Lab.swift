import AppKit

// ---------- cLab: the colour wheel, its harmony rules and the result strip ----------
//
// The maths lives in ColourScience.swift. Everything here is drawn as shapes, so it stays sharp at
// any window size; only the wheel's colour fill is a picture, and that is stretched under a
// vector edge.

private func labSymbol() -> String {
    NSImage(systemSymbolName: "flask.fill", accessibilityDescription: nil) != nil ? "flask.fill" : "testtube.2"
}
let labSymbolName = labSymbol()

extension LibraryController {
    /// Saves colours as a new palette without leaving the page or redirecting picks.
    func keep(_ hexes: [String], named name: String, in project: UUID?) {
        var made: String?
        apply { lib in
            let target = lib.activeSwatchID
            let id = lib.createSwatch(named: name, hexes: hexes, custom: true)
            lib.activeSwatchID = target
            if let p = project { lib.move(id, to: p, index: Int.max) }
            made = lib.swatch(id)?.name
        }
        let place = project.flatMap { library.project($0)?.name }.map { " in \($0)" } ?? ""
        flash("Saved \(plural(hexes.count, "colour")) as \(made ?? name)\(place)\(project == nil ? "" : "; it is under Palettes too")")
    }
}

// ---------- The wheel ----------

final class WheelView: NSView {
    var state = LabState(base: LabNode(h: 0, s: 0, v: 0.5)) { didSet { needsDisplay = true } }
    /// The colour the lightness slider is working on; ringed when colours move on their own.
    var selected = 0 { didSet { needsDisplay = true } }

    var onGrab: ((Int) -> Void)?
    var onDrag: ((Int, _ h: Double, _ s: Double) -> Void)?
    var onRelease: (() -> Void)?

    private var dragging: Int?
    /// The fill never changes, so every wheel shares one picture of it.
    private static let fill = WheelView.disc()
    private let nodeRadius: CGFloat = 12

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? { "Colour wheel" }

    private var centre: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }
    private var radius: CGFloat { max(10, min(bounds.width, bounds.height) / 2 - nodeRadius - 3) }

    private func place(_ n: LabNode) -> NSPoint {
        let p = n.point
        return NSPoint(x: centre.x + CGFloat(p.x) * radius, y: centre.y + CGFloat(p.y) * radius)
    }

    /// The artists' wheel: pure hues round the rim, paling to white at the centre. Each spot is the
    /// colour a node placed there has at full brightness.
    static func disc(pixels n: Int = 512) -> CGImage? {
        var data = [UInt8](repeating: 255, count: n * n * 4)
        let mid = Double(n - 1) / 2
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Double(x) - mid) / mid, dy = (mid - Double(y)) / mid
                let r = min((dx * dx + dy * dy).squareRoot(), 1)
                var h = atan2(dy, dx) * 180 / .pi
                if h < 0 { h += 360 }
                let c = LabNode(h: h, s: r, v: 1).rgb
                let at = (y * n + x) * 4
                data[at] = UInt8(c.r * 255 + 0.5); data[at + 1] = UInt8(c.g * 255 + 0.5); data[at + 2] = UInt8(c.b * 255 + 0.5)
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rim = NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)

        ctx.saveGState()
        ctx.addEllipse(in: rim)
        ctx.clip()
        ctx.interpolationQuality = .high
        if let image = WheelView.fill { ctx.draw(image, in: rim) }
        ctx.restoreGState()
        NSColor.separatorColor.setStroke()
        NSBezierPath(ovalIn: rim.insetBy(dx: -0.5, dy: -0.5)).stroke()

        // Spokes show that the colours are tied together; with no rule there is nothing to show.
        if state.rule != .custom {
            let spokes = NSBezierPath()
            for n in state.nodes { spokes.move(to: centre); spokes.line(to: place(n)) }
            // Dark under white, so the spokes show over both the pale middle and the strong rim.
            spokes.lineWidth = 2.5
            NSColor.black.withAlphaComponent(0.25).setStroke()
            spokes.stroke()
            spokes.lineWidth = 1.5
            NSColor.white.setStroke()
            spokes.stroke()
        }

        // The base is drawn last so it is never hidden under a colour that shares its place.
        let order = state.nodes.indices.filter { $0 != state.base } + [state.base]
        for i in order where state.nodes.indices.contains(i) {
            let n = state.nodes[i], p = place(n), isBase = i == state.base
            let r = nodeRadius + (isBase ? 1.5 : 0)
            let circle = NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            (colorFromHex(n.hex) ?? .gray).setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSGraphicsContext.restoreGraphicsState()
            let ring = NSBezierPath(ovalIn: circle)
            ring.lineWidth = 2.5
            (state.rule == .custom && i == selected ? NSColor.controlAccentColor : NSColor.white).setStroke()
            if state.rule != .custom || i != selected {
                // A hairline outside the white ring keeps a node visible over the pale middle of the wheel.
                NSColor.black.withAlphaComponent(0.25).setStroke()
                let outer = NSBezierPath(ovalIn: circle.insetBy(dx: -1.5, dy: -1.5))
                outer.lineWidth = 0.5
                outer.stroke()
                NSColor.white.setStroke()
            }
            ring.stroke()
            if isBase {
                let ink = colorFromHex(readableText(on: n.hex)) ?? .white
                ink.setStroke(); ink.setFill()
                let inner = NSBezierPath(ovalIn: circle.insetBy(dx: r * 0.42, dy: r * 0.42))
                inner.lineWidth = 1.5
                inner.stroke()
                NSBezierPath(ovalIn: circle.insetBy(dx: r * 0.8, dy: r * 0.8)).fill()
            }
            if n.locked {
                let ink = colorFromHex(readableText(on: n.hex)) ?? .white
                let lock = symbol("lock.fill", "Locked", size: 8, weight: .bold)
                let tinted = NSImage(size: lock.size, flipped: false) { rect in
                    lock.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                if !isBase { tinted.draw(in: NSRect(x: p.x - lock.size.width / 2, y: p.y - lock.size.height / 2, width: lock.size.width, height: lock.size.height)) }
            }
        }
    }

    private func node(at p: NSPoint) -> Int? {
        // The base wins when colours overlap, as it does when a rule stacks them on one spot.
        let order = [state.base] + state.nodes.indices.filter { $0 != state.base }.reversed()
        return order.first { i in
            guard state.nodes.indices.contains(i) else { return false }
            let q = place(state.nodes[i])
            return hypot(q.x - p.x, q.y - p.y) <= nodeRadius + 5
        }
    }

    private func move(to p: NSPoint) {
        guard let i = dragging else { return }
        let polar = LabNode.polar(x: Double((p.x - centre.x) / radius), y: Double((p.y - centre.y) / radius))
        onDrag?(i, polar.h, polar.s)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = node(at: p) else { return }
        dragging = i
        onGrab?(i)
    }

    override func mouseDragged(with event: NSEvent) { move(to: convert(event.locationInWindow, from: nil)) }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        dragging = nil
        onRelease?()
    }
}

// ---------- Rule buttons ----------

/// A small diagram of the rule, drawn from the rule's own arrangement.
final class RuleButton: NSButton {
    let rule: LabRule
    var chosen = false { didSet { needsDisplay = true } }

    init(rule: LabRule, target: AnyObject, action: Selector) {
        self.rule = rule
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        toolTip = rule.title
        setAccessibilityLabel(rule.title)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Where the dots go, on a circle of radius 1 with the base at the top.
    private var dots: [(x: Double, y: Double)] {
        guard let made = rule.arrangement(around: LabNode(h: 90, s: 1, v: 1)) else {
            return [(-0.45, 0.35), (0.5, 0.15), (-0.05, -0.55)]
        }
        let oneHue = Set(made.nodes.map { Int($0.h.rounded()) }).count == 1
        var out: [(Double, Double)] = []
        for n in made.nodes {
            // Rules that turn the hue show one dot per hue; rules that stay on a hue show their steps along it.
            let p = oneHue ? n.point : LabNode(h: n.h, s: 1, v: 1).point
            // Dots that would touch at this size are left out; the shape still reads.
            if !out.contains(where: { hypot($0.0 - p.x, $0.1 - p.y) < 0.45 }) { out.append((p.x, p.y)) }
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if chosen {
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            box.fill()
            NSColor.controlAccentColor.setStroke()
            box.lineWidth = 1.5
            box.stroke()
        } else if isHighlighted {
            NSColor.quaternaryLabelColor.setFill()
            box.fill()
        }
        let c = NSPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) / 2 - 6
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 1.5
        NSColor.tertiaryLabelColor.setStroke()
        ring.stroke()

        let ink = chosen ? NSColor.controlAccentColor : NSColor.labelColor
        ink.setStroke(); ink.setFill()
        let points = dots.map { NSPoint(x: c.x + CGFloat($0.x) * r, y: c.y + CGFloat($0.y) * r) }
        if rule != .custom {
            let spokes = NSBezierPath()
            for p in points { spokes.move(to: c); spokes.line(to: p) }
            spokes.lineWidth = 1
            spokes.stroke()
        }
        for p in points { NSBezierPath(ovalIn: NSRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill() }
    }
}

// ---------- The result strip ----------

/// One colour in the strip: click copies it; its controls appear under the pointer.
final class StripColumn: NSView {
    var onCopy: (() -> Void)?
    var onBase: (() -> Void)?
    var onLock: (() -> Void)?
    var onDelete: (() -> Void)?

    private var hex = "#000000"
    private var isBase = false, locked = false, removable = true
    private let label = NSTextField(labelWithString: "")
    private var base: NSButton!, lock: NSButton!, bin: NSButton!
    private var hovering = false { didSet { showControls() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        base = symbolButton("scope", tooltip: "Set As Base", target: self, action: #selector(baseTapped))
        lock = symbolButton("lock.open", tooltip: "Lock", target: self, action: #selector(lockTapped))
        bin = symbolButton("trash", tooltip: "Delete", target: self, action: #selector(binTapped))
        label.lineBreakMode = .byClipping
        for v in [label, base, lock, bin] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(hex: String, isBase: Bool, locked: Bool, removable: Bool) {
        self.hex = hex; self.isBase = isBase; self.locked = locked; self.removable = removable
        let ink = colorFromHex(readableText(on: hex)) ?? .white
        label.textColor = ink
        for b in [base, lock, bin] { b?.contentTintColor = ink.withAlphaComponent(0.85) }
        base.image = symbol(isBase ? "smallcircle.filled.circle" : "scope", "Base", size: 13)
        base.toolTip = isBase ? "The Base Colour" : "Set As Base"
        lock.image = symbol(locked ? "lock.fill" : "lock.open", "Lock", size: 12)
        lock.toolTip = locked ? "Unlock" : "Lock: Keep This Colour When The Others Change"
        lock.setAccessibilityLabel(locked ? "Unlock" : "Lock")
        bin.image = symbol("trash", "Delete", size: 12)
        toolTip = "Click To Copy \(Prefs.copyText(hex))"
        setAccessibilityLabel("\(colourName(hex)), \(hex)")
        showControls()
        needsLayout = true
        needsDisplay = true
    }

    // The base mark and a closed lock always show; the rest wait for the pointer.
    private func showControls() {
        base.isHidden = !(hovering || isBase)
        lock.isHidden = !(hovering || locked)
        bin.isHidden = !(hovering && removable)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { onCopy?(); return true }

    override func draw(_ dirtyRect: NSRect) {
        (colorFromHex(hex) ?? .gray).setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()
        // At the smallest window a column is barely wider than six characters, so the text gives way first.
        let narrow = bounds.width < 62, tight = bounds.width < 46
        label.font = NSFont.monospacedSystemFont(ofSize: tight ? 8 : narrow ? 9.5 : 11, weight: .medium)
        label.stringValue = narrow ? String(hex.dropFirst()) : hex
        label.sizeToFit()
        let inset: CGFloat = tight ? 1 : narrow ? 4 : 10
        label.frame.origin = NSPoint(x: inset, y: inset)
        var y = bounds.height - inset - 20
        for b in [base, lock, bin] as [NSButton] {
            b.frame = NSRect(x: narrow ? (bounds.width - 20) / 2 : bounds.width - inset - 20, y: y, width: 20, height: 20)
            y -= 24
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onCopy?() }
    }

    @objc private func baseTapped() { onBase?() }
    @objc private func lockTapped() { onLock?() }
    @objc private func binTapped() { onDelete?() }
}

final class StripView: NSView {
    var onCopy: ((Int) -> Void)?
    var onBase: ((Int) -> Void)?
    var onLock: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    private var columns: [StripColumn] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ state: LabState) {
        while columns.count > state.nodes.count { columns.removeLast().removeFromSuperview() }
        while columns.count < state.nodes.count {
            let c = StripColumn(frame: .zero)
            columns.append(c)
            addSubview(c)
        }
        for (i, c) in columns.enumerated() {
            let n = state.nodes[i]
            c.configure(hex: n.hex, isBase: i == state.base, locked: n.locked, removable: state.nodes.count > 1)
            c.onCopy = { [weak self] in self?.onCopy?(i) }
            c.onBase = { [weak self] in self?.onBase?(i) }
            c.onLock = { [weak self] in self?.onLock?(i) }
            c.onDelete = { [weak self] in self?.onDelete?(i) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !columns.isEmpty else { return }
        let each = bounds.width / CGFloat(columns.count)
        for (i, c) in columns.enumerated() {
            // Whole-point edges, so neighbours meet exactly.
            let left = (CGFloat(i) * each).rounded(), right = i == columns.count - 1 ? bounds.width : (CGFloat(i + 1) * each).rounded()
            c.frame = NSRect(x: left, y: 0, width: right - left, height: bounds.height)
        }
    }
}

// ---------- Saving a tool's colours ----------

/// A push button with a small symbol, as the tools' pages use.
func toolButton(_ title: String, _ icon: String, _ tip: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton(title: title.isEmpty ? "" : " " + title, target: target, action: action)
    b.image = symbol(icon, tip, size: 12)
    b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    b.bezelStyle = .rounded
    b.toolTip = tip
    b.setAccessibilityLabel(tip)
    return b
}

/// The foot of a tool's page: a name, then Add To Palette and Add To Project. Neither leaves the page.
final class SaveBar: NSView, NSTextFieldDelegate {
    /// What a save keeps, and what it is called when no name has been typed.
    var colours: () -> [String] = { [] }
    var defaultName: () -> String = { "" }
    var onNameChanged: (() -> Void)?

    private let library: LibraryController
    private let name = NSTextField()
    private var toPalette: NSButton!, toProject: NSButton!
    override var isFlipped: Bool { true }

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        name.placeholderString = "Palette Name"
        name.delegate = self
        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.setAccessibilityLabel("Palette name")
        toPalette = toolButton("Add To Palette", "plus.rectangle.on.rectangle", "Save These Colours To A Palette", target: self, action: #selector(paletteTapped(_:)))
        toProject = toolButton("Add To Project", "folder.badge.plus", "Save These Colours As A New Palette In A Project", target: self, action: #selector(projectTapped(_:)))
        for v in [name, toPalette, toProject] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }

    var chosenName: String {
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultName() : typed
    }

    func refresh() { name.placeholderString = defaultName() }

    override func layout() {
        super.layout()
        var x = bounds.width
        for button in [toProject, toPalette] as [NSButton] {
            button.sizeToFit()
            x -= button.frame.width
            button.frame.origin = NSPoint(x: x, y: (bounds.height - button.frame.height) / 2)
            x -= 6
        }
        name.frame = NSRect(x: 0, y: (bounds.height - 22) / 2, width: max(80, min(260, x - 8)), height: 22)
    }

    @objc private func paletteTapped(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Palette", action: #selector(keepNew(_:)), keyEquivalent: "").target = self
        let palettes = library.paletteOrder
        if !palettes.isEmpty { menu.addItem(.separator()) }
        for s in palettes {
            let item = menu.addItem(withTitle: s.name, action: #selector(keepIn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.id
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func projectTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let projects = library.library.orderedProjects
        if projects.isEmpty {
            menu.addItem(withTitle: "No Projects Yet", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
            menu.addItem(withTitle: "New Project\u{2026}", action: #selector(LibraryController.newProject), keyEquivalent: "").target = library
        }
        for p in projects {
            let item = menu.addItem(withTitle: p.name, action: #selector(keepNew(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.id
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func keepNew(_ sender: NSMenuItem) {
        library.keep(colours(), named: chosenName, in: sender.representedObject as? UUID)
    }

    @objc private func keepIn(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { library.add(colours(), to: id) }
    }

    func controlTextDidChange(_ obj: Notification) { onNameChanged?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        window?.makeFirstResponder(superview)
        return true
    }
}

// ---------- The page ----------

/// Lays its subviews out by hand, top down, so the parts can trade places as the window changes shape.
final class ToolPageView: NSView {
    var onLayout: ((NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        onLayout?(bounds)
    }
    override func viewDidMoveToWindow() { needsLayout = true }
}

final class LabViewController: NSViewController {
    private let library: LibraryController
    private(set) var state: LabState
    private var history = LabHistory()
    /// The state when a drag or a slide began, so the whole gesture is one step to undo.
    private var gestureStart: LabState?
    private var selected = 0

    private let heading = NSTextField(labelWithString: "cLab")
    private var undo: NSButton!, redo: NSButton!, add: NSButton!, random: NSButton!, check: NSButton!
    private let wheel = WheelView()
    private var rules: [RuleButton] = []
    private let dim = NSImageView(), bright = NSImageView()
    private let slider = NSSlider(value: 1, minValue: 0.08, maxValue: 1, target: nil, action: nil)
    private let why = NSTextField(wrappingLabelWithString: "")
    private let strip = StripView()
    private let saveBar: SaveBar

    private static let key = "labState"

    init(library: LibraryController) {
        self.library = library
        saveBar = SaveBar(library: library)
        let saved = preferences.data(forKey: LabViewController.key).flatMap { try? JSONDecoder().decode(LabState.self, from: $0) }
        state = saved.flatMap { $0.nodes.isEmpty || !$0.nodes.indices.contains($0.base) ? nil : $0 }
            ?? LabState(rule: .analogous, base: LabNode(hex: "#2456F5") ?? LabNode(h: 260, s: 0.8, v: 1))
        super.init(nibName: nil, bundle: nil)
        selected = state.base
        publish()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let page = ToolPageView(frame: NSRect(x: 0, y: 0, width: 700, height: 520))
        page.onLayout = { [weak self] in self?.arrange(in: $0) }
        view = page

        heading.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        undo = toolButton("", "arrow.uturn.backward", "Undo", target: self, action: #selector(undoTapped))
        redo = toolButton("", "arrow.uturn.forward", "Redo", target: self, action: #selector(redoTapped))
        add = toolButton("", "plus", "Add A Colour", target: self, action: #selector(addTapped))
        random = toolButton("Random", "shuffle", "Roll New Colours; Locked Ones Stay", target: self, action: #selector(randomTapped))
        check = toolButton("Contrast", "circle.lefthalf.filled", "Check These Colours In Contrast", target: self, action: #selector(contrastTapped))

        rules = LabRule.allCases.map { RuleButton(rule: $0, target: self, action: #selector(ruleTapped(_:))) }

        dim.image = symbol("sun.min", "Darker", size: 12)
        bright.image = symbol("sun.max.fill", "Lighter", size: 12)
        dim.contentTintColor = .secondaryLabelColor
        bright.contentTintColor = .secondaryLabelColor
        slider.target = self
        slider.action = #selector(slid)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.toolTip = "Brightness"
        slider.setAccessibilityLabel("Brightness")

        why.font = NSFont.systemFont(ofSize: 11.5)
        why.textColor = .secondaryLabelColor
        why.maximumNumberOfLines = 2
        why.lineBreakMode = .byTruncatingTail

        saveBar.colours = { [weak self] in self?.uniqueHexes ?? [] }
        saveBar.defaultName = { [weak self] in self?.defaultName ?? "" }
        saveBar.onNameChanged = { [weak self] in self?.publish() }

        wheel.onGrab = { [weak self] i in
            guard let self = self else { return }
            self.gestureStart = self.state
            if self.state.rule == .custom { self.selected = i; self.refresh() }
        }
        wheel.onDrag = { [weak self] i, h, s in
            guard let self = self else { return }
            self.state.move(i, h: h, s: s)
            self.refresh()
        }
        wheel.onRelease = { [weak self] in self?.endGesture() }
        strip.onCopy = { [weak self] i in
            guard let self = self, self.state.nodes.indices.contains(i) else { return }
            self.library.copy(self.state.nodes[i].hex)
        }
        strip.onBase = { [weak self] i in self?.change { $0.makeBase(i) } }
        strip.onLock = { [weak self] i in self?.change { $0.toggleLock(i) } }
        strip.onDelete = { [weak self] i in self?.change { $0.remove(i) } }

        for v in [heading, undo, redo, add, random, check, wheel, dim, slider, bright, why, strip, saveBar] + rules as [NSView] {
            page.addSubview(v)
        }
        refresh()
    }

    // MARK: Layout

    /// The wheel beside the strip; in a window that is narrow but tall, the strip drops below it.
    private func arrange(in b: NSRect) {
        let pad: CGFloat = 20, bar: CGFloat = 28, gap: CGFloat = 14
        let w = b.width - pad * 2
        let head = view.safeAreaInsets.top + 14 // the page runs under the toolbar; its contents must not

        heading.sizeToFit()
        heading.frame.origin = NSPoint(x: pad, y: head + (bar - heading.frame.height) / 2)
        var x = b.width - pad
        for button in [check, random, add, redo, undo] as [NSButton] {
            button.sizeToFit()
            x -= button.frame.width
            button.frame.origin = NSPoint(x: x, y: head + (bar - button.frame.height) / 2)
            x -= button === add || button === check ? 14 : 4
        }

        let foot = b.height - pad - bar
        saveBar.frame = NSRect(x: pad, y: foot, width: w, height: bar)

        // The caption runs the full width under the working area, so it never squeezes the wheel.
        let whyHeight: CGFloat = 30
        why.frame = NSRect(x: pad, y: foot - gap - whyHeight, width: w, height: whyHeight)

        let top = head + bar + gap, bottom = why.frame.minY - 10
        let ruleSide: CGFloat = 30, ruleRow = CGFloat(rules.count) * ruleSide + CGFloat(rules.count - 1)
        let controls = 10 + ruleSide + 8 + 20
        let stacked = b.width < 600 && b.height >= 600

        let column: CGFloat, side: CGFloat, left: CGFloat
        if stacked {
            column = w
            side = max(120, min(w, 360, (bottom - top) * 0.5 - controls))
            left = pad
        } else {
            column = max(ruleRow + 2, min(480, w * 0.45, bottom - top - controls))
            side = max(110, min(column, bottom - top - controls))
            left = pad
        }
        wheel.frame = NSRect(x: left + (column - side) / 2, y: top, width: side, height: side)
        var y = top + side + 10
        var rx = left + (column - ruleRow) / 2
        for r in rules {
            r.frame = NSRect(x: rx, y: y, width: ruleSide, height: ruleSide)
            rx += ruleSide + 1
        }
        y += ruleSide + 8
        let track = min(column, max(ruleRow, 300))
        let sx = left + (column - track) / 2
        dim.frame = NSRect(x: sx, y: y + 2, width: 16, height: 16)
        bright.frame = NSRect(x: sx + track - 16, y: y + 2, width: 16, height: 16)
        slider.frame = NSRect(x: sx + 22, y: y, width: track - 44, height: 20)
        y += 20

        strip.frame = stacked
            ? NSRect(x: pad, y: y + gap, width: w, height: max(60, bottom - y - gap))
            : NSRect(x: left + column + 18, y: top, width: max(60, w - column - 18), height: bottom - top)
    }

    // MARK: Showing and changing

    private func refresh() {
        publish()
        guard isViewLoaded else { return }
        if !state.nodes.indices.contains(selected) || state.rule != .custom { selected = state.base }
        let target = state.nodes[selected]
        wheel.state = state
        wheel.selected = selected
        strip.show(state)
        for r in rules { r.chosen = r.rule == state.rule }
        if abs(slider.doubleValue - target.v) > 0.001 { slider.doubleValue = target.v }
        slider.toolTip = state.rule == .custom ? "Brightness Of The Ringed Colour" : "Brightness Of The Base Colour"

        let text = NSMutableAttributedString(string: state.rule.title + "  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(string: state.rule.why, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.secondaryLabelColor]))
        why.attributedStringValue = text
        why.toolTip = state.rule.why

        saveBar.refresh()
        undo.isEnabled = history.canUndo
        redo.isEnabled = history.canRedo
        add.isEnabled = state.nodes.count < LabState.most
    }

    /// Keeps the library's copy of the strip current, for export, sharing and the other tools.
    private func publish() {
        library.labPalette = ExportPalette(name: saveBar.chosenName.isEmpty ? defaultName : saveBar.chosenName,
                                           colours: uniqueHexes.map { ExportColour(name: colourName($0), hex: $0) })
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { preferences.set(data, forKey: LabViewController.key) }
    }

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

    /// Starts the wheel from a colour, keeping the rule in use.
    func open(with hex: String) {
        guard let node = LabNode(hex: hex) else { return }
        _ = view
        change { $0 = LabState(rule: $0.rule == .custom ? .analogous : $0.rule, base: node) }
    }

    /// Colours two places in the strip can share, once each, for saving.
    private var uniqueHexes: [String] {
        var seen = Set<String>()
        return state.hexes.filter { seen.insert($0).inserted }
    }
    private var defaultName: String { "\(colourName(state.nodes[state.base].hex)) \u{2014} \(state.rule.title)" }

    // MARK: Actions

    @objc private func ruleTapped(_ sender: RuleButton) { change { $0.setRule(sender.rule) } }
    @objc private func randomTapped() { change { $0.randomise { Double.random(in: 0..<1) } } }
    @objc private func addTapped() { change { $0.add() } }
    @objc private func contrastTapped() { library.onShow?(.contrast, false) }

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

    @objc private func slid() {
        if gestureStart == nil { gestureStart = state }
        state.setBrightness(slider.doubleValue, of: selected)
        refresh()
        if NSApp.currentEvent?.type == .leftMouseUp { endGesture() }
    }
}
