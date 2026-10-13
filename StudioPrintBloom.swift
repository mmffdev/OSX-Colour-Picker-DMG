import AppKit

/// A radial ΔE plot with shared numeric scale and stable, selectable petal ordering.
final class PrintBloomView: NSView {
    struct Item { let id: String; let name: String; let master: NSColor; let printed: NSColor?; let delta: Double?; let ink: Double? }
    enum Order: String, CaseIterable {
        case palette = "Palette Order", failFirst = "Fail First", passFirst = "Pass First"
        case highest = "Highest ΔE First", lowest = "Lowest ΔE First", name = "Name"
        func arrange(_ items: [Item], tolerance: Double) -> [Item] {
            guard self != .palette else { return items }
            return items.enumerated().sorted { a, b in
                if self == .name {
                    let result = a.element.name.localizedStandardCompare(b.element.name)
                    return result == .orderedSame ? a.offset < b.offset : result == .orderedAscending
                }
                guard let x = a.element.delta else { return b.element.delta == nil && a.offset < b.offset }
                guard let y = b.element.delta else { return true }
                if self == .failFirst || self == .passFirst {
                    let xp = x <= tolerance, yp = y <= tolerance
                    return xp == yp ? a.offset < b.offset : (self == .passFirst ? xp : !xp)
                }
                return x == y ? a.offset < b.offset : (self == .highest ? x > y : x < y)
            }.map { $0.element }
        }
    }
    var order: Order = .palette { didSet {
        orderMenu.displayValue(order.rawValue)
        if oldValue != order { motionDirty = true; needsDisplay = true }
    } }
    var onOrder: ((Order) -> Void)?
    private let orderMenu = SwissDropdown("Arrange Petals", value: Order.palette.rawValue, options: Order.allCases.map(\.rawValue), allowsOwn: false, width: 200)
    override init(frame: NSRect) {
        super.init(frame: frame); addSubview(orderMenu)
        orderMenu.onChange = { [weak self] value in
            guard let order = Order(rawValue: value) else { return }
            self?.order = order; self?.onOrder?(order)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let width = max(100, min(240, bounds.width))
        for c in orderMenu.constraints where c.firstAttribute == .width { c.constant = width }
        orderMenu.frame = NSRect(x: 0, y: 34, width: width, height: 50)
    }
    var items: [Item] = [] { didSet {
        if oldValue.map(\.id) != items.map(\.id) { entrancePending = true }
        motionDirty = true; needsDisplay = true
    } }
    var tolerance: Double = 2 { didSet { motionDirty = true; needsDisplay = true } }
    var selected: String? { didSet { needsDisplay = true } }
    var onSelect: ((String) -> Void)?
    var onExpand: (() -> Void)?
    var expanded = false
    /// One pose per colour identity, shared by its fill, border, label and hit region.
    struct PetalMotion {
        var from: Double, to: Double, scaleFrom: Double, started: Double, duration: Double
        func pose(at time: Double) -> (angle: Double, scale: Double) {
            let t = duration > 0 ? min(1, max(0, (time - started) / duration)) : 1
            let ease = t * t * (3 - 2 * t)
            return (from + (to - from) * ease, scaleFrom + (1 - scaleFrom) * ease)
        }
        static func nearest(_ target: Double, from source: Double) -> Double {
            source + atan2(sin(target - source), cos(target - source))
        }
    }
    private var motions: [String: PetalMotion] = [:]
    private var entrancePending = true
    private var motionDirty = true
    private var motionClock: Timer?
    deinit { motionClock?.invalidate() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { motionClock?.invalidate(); motionClock = nil }
        else { needsDisplay = true }
    }
    private func prepareMotion(at now: Double) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !motionDirty && !entrancePending && !reduced { return }
        let arranged = order.arrange(items, tolerance: tolerance)
        let step = Double.pi * 2 / Double(max(1, items.count))
        let gap = min(step * 0.11, 0.035)
        let opening = entrancePending
        var next: [String: PetalMotion] = [:]
        for (index, item) in arranged.enumerated() {
            let target = -Double.pi / 2 + Double(index) * step + gap
            let previous = motions[item.id]?.pose(at: now)
            let source = opening ? -Double.pi / 2 - step / 2 + gap : (previous?.angle ?? target)
            let destination = opening ? target : PetalMotion.nearest(target, from: source)
            if !opening, !reduced, let existing = motions[item.id], abs(PetalMotion.nearest(target, from: existing.to) - existing.to) < 0.00001 {
                next[item.id] = existing
            } else {
                next[item.id] = PetalMotion(from: source, to: destination, scaleFrom: opening ? 0 : (previous?.scale ?? 1), started: now, duration: reduced ? 0 : (opening ? 0.62 : 0.38))
            }
        }
        motions = next; entrancePending = false; motionDirty = false
        if motionClock == nil && !reduced && !items.isEmpty {
            let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
                guard let self, self.window != nil else { timer.invalidate(); return }
                self.needsDisplay = true
                let now = ProcessInfo.processInfo.systemUptime
                if self.motions.values.allSatisfy({ now >= $0.started + $0.duration }) {
                    timer.invalidate(); self.motionClock = nil
                    self.window?.invalidateCursorRects(for: self)
                }
            }
            motionClock = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    private var paths: [(NSBezierPath, String)] = []
    private var hovered: String?
    private var tracking: NSTrackingArea?
    private var expandRect = NSRect.zero
    private var diameter: CGFloat { max(20, min(bounds.width - 64, bounds.height - 220)) }
    var captionGuide: CGFloat { SettingsSheet.baseline(ceil((102 + diameter + 40 - Design.App.textBaseline) / Design.App.unit)) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func draw(_ dirtyRect: NSRect) {
        paths = []
        let now = ProcessInfo.processInfo.systemUptime
        // Wait until the plot itself scrolls into view before spending its entrance animation.
        let plot = NSRect(x: 0, y: 102, width: bounds.width, height: diameter)
        if !items.isEmpty && visibleRect.intersects(plot) { prepareMotion(at: now) }
        Design.attributed("Colour Bloom", .bodyStrong).draw(x: 0, baseline: 17)
        expandRect = expanded ? .zero : NSRect(x: bounds.width - 28, y: 0, width: 28, height: 28)
        if !expanded { Design.arrow(14, colour: Design.ink, back: expanded).draw(in: expandRect.insetBy(dx: 7, dy: 7), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        let diameter = self.diameter
        let centre = NSPoint(x: bounds.midX, y: 102 + diameter / 2), radius = diameter / 2 - 10, inner = radius * 0.20
        let ceiling = max(tolerance * 1.6, (items.compactMap(\.delta).max() ?? tolerance) * 1.12, 0.1)
        func reach(_ value: Double) -> CGFloat { inner + (radius - inner) * CGFloat(max(0, value) / ceiling) }
        let toleranceRadius = reach(tolerance)
        var petalScale: CGFloat = 1
        func point(_ r: CGFloat, _ a: CGFloat) -> NSPoint { NSPoint(x: centre.x + r * petalScale * cos(a), y: centre.y + r * petalScale * sin(a)) }
        func petal(_ start: CGFloat, _ end: CGFloat, _ r: CGFloat, from hole: CGFloat? = nil) -> NSBezierPath {
            let holeRadius = hole ?? inner
            let path = NSBezierPath(); path.move(to: point(holeRadius, start))
            path.line(to: point(r, start))
            let segments = max(3, Int((end - start) * 24))
            for n in 1...segments { path.line(to: point(r, start + (end - start) * CGFloat(n) / CGFloat(segments))) }
            path.line(to: point(holeRadius, end))
            for n in 1...segments { path.line(to: point(holeRadius, end - (end - start) * CGFloat(n) / CGFloat(segments))) }
            path.close(); path.lineJoinStyle = .round; return path
        }
        for (index, item) in order.arrange(items, tolerance: tolerance).enumerated() {
            let step = CGFloat.pi * 2 / CGFloat(max(1, items.count)), gap = min(step * 0.11, 0.035)
            let pose = motions[item.id]?.pose(at: now)
            petalScale = CGFloat(pose?.scale ?? (entrancePending ? 0 : 1))
            let start = CGFloat(pose?.angle ?? Double(-CGFloat.pi / 2 + CGFloat(index) * step + gap)), end = start + step - gap * 2
            guard petalScale > 0.001 else { continue }
            let envelope = petal(start, end, radius)
            item.master.withAlphaComponent(0.08).setFill(); petal(start, end, toleranceRadius).fill()
            (item.printed ?? Design.mist).withAlphaComponent(0.08).setFill(); petal(start, end, radius, from: toleranceRadius).fill()
            Design.rule.withAlphaComponent(0.55).setStroke(); envelope.lineWidth = 0.5; envelope.stroke()
            let r = item.delta.map(reach) ?? inner + (radius - inner) * 0.2
            let outer = max(inner + 5, r)
            item.master.setFill(); petal(start, end, min(outer, toleranceRadius)).fill()
            if outer > toleranceRadius {
                (item.printed ?? Design.mist).setFill()
                petal(start, end, outer, from: toleranceRadius).fill()
            }
            let status: NSColor = item.delta.map { $0 <= tolerance ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1) : NSColor(calibratedRed: 0.77, green: 0.22, blue: 0.23, alpha: 1) } ?? Design.quiet

            // The outer arc of each petal reports its own result, in physical pixels.
            let rim = NSBezierPath()
            let arcRadius = radius - 7.5 / max(1, window?.backingScaleFactor ?? 1)
            rim.move(to: point(arcRadius, start))
            let segments = max(3, Int((end - start) * 48))
            for n in 1...segments { rim.line(to: point(arcRadius, start + (end - start) * CGFloat(n) / CGFloat(segments))) }
            status.setStroke(); rim.lineWidth = 15 * petalScale / max(1, window?.backingScaleFactor ?? 1); rim.stroke()
            paths.append((envelope, item.id))
            if items.count <= 12, petalScale > 0.75, let delta = item.delta {
                let position = point(radius + 24, (start + end) / 2)
                let label = Design.attributed(String(format: "%.1f", delta), .caption, colour: Design.ink)
                label.draw(x: position.x - label.size().width / 2, baseline: position.y + 4)
            }
        }
        let ring = NSBezierPath(ovalIn: NSRect(x: centre.x - toleranceRadius, y: centre.y - toleranceRadius, width: toleranceRadius * 2, height: toleranceRadius * 2))
        Design.ink.withAlphaComponent(0.6).setStroke(); ring.lineWidth = 1; ring.setLineDash([3, 4], count: 2, phase: 0); ring.stroke()
        fill(NSRect(x: centre.x - 18, y: centre.y - 13, width: 36, height: 26), Design.card)
        let value = Design.attributed("ΔE", .bodyStrong); value.draw(x: centre.x - value.size().width / 2, baseline: centre.y + 5)
        let y = captionGuide
        let inspect = items.first { $0.id == (hovered ?? selected) }
        Design.attributed(inspect?.name ?? "\(items.count) Palette Colours", .bodyStrong).draw(x: 0, baseline: y, width: bounds.width)
        let detail = inspect.map { item in
            item.delta.map { String(format: "ΔE00 %.2f · %@", $0, $0 <= tolerance ? "Holds" : "Outside") } ?? "No Profile Prediction"
        } ?? String(format: "Dashed Ring: ΔE00 %.1f Tolerance", tolerance)
        Design.attributed(detail, .caption, colour: Design.quiet).draw(x: 0, baseline: y + Design.App.unit, width: bounds.width)
        Design.attributed("Inside: RGB · Outside: Print Prediction · Rim: Pass / Fail", .caption, colour: Design.quiet).draw(x: 0, baseline: y + 2 * Design.App.unit, width: bounds.width)
        if items.isEmpty { Design.attributed("Choose A Palette", .body).draw(x: centre.x - 50, baseline: centre.y + 40) }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let next = paths.reversed().first { $0.0.contains(p) }?.1
        if hovered != next { hovered = next; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if expandRect.contains(p) { onExpand?(); return }
        if let id = paths.reversed().first(where: { $0.0.contains(p) })?.1 { selected = id; onSelect?(id) }
    }
    override func resetCursorRects() {
        addCursorRect(expandRect, cursor: .pointingHand)
        for (path, _) in paths { addCursorRect(path.bounds, cursor: .pointingHand) }
    }
}

final class PrintSortHeader: NSButton {
    var direction: Bool? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let label = Design.attributed(title, .caption, colour: direction == nil ? Design.quiet : Design.ink)
        let room = max(0, bounds.width - 18)
        if label.size().width <= room { label.draw(x: 0, baseline: 17, width: room) }
        else {
            let parts = title.contains(" · ") ? title.components(separatedBy: " · ") : title.components(separatedBy: " ")
            Design.attributed(parts.first ?? title, .caption, colour: direction == nil ? Design.quiet : Design.ink).draw(x: 0, baseline: 10, width: room)
            Design.attributed(parts.dropFirst().joined(separator: " "), .caption, colour: direction == nil ? Design.quiet : Design.ink).draw(x: 0, baseline: 25, width: room)
        }
        Design.attributed(direction.map { $0 ? "↑" : "↓" } ?? "↕", .caption, colour: Design.quiet).draw(x: bounds.width - 14, baseline: 17)
    }
}

final class PrintBloomDetail: NSView {
    let chart = PrintBloomView()
    private let close = NSButton()
    var onClose: (() -> Void)?
    var order: PrintBloomView.Order = .palette { didSet { chart.order = order } }
    @objc private func closePressed() { onClose?() }
    private let feedback = PrintBloomFeedback()
    private let scroll = FittedScrollView()
    private final class SettingsContent: NSView { override var isFlipped: Bool { true } }
    private let settingsScroll = FittedScrollView()
    private let settingsContent = SettingsContent()
    private let profileSelector = PrintProfileSelector()
    private let summaryLabel = Design.text("", .caption, colour: Design.quiet)
    var selected: String? { didSet { chart.selected = selected; updateFeedback() } }
    var tolerance: Double = 2 { didSet { chart.tolerance = tolerance; updateFeedback() } }
    var controls: [SwissDropdown] = [] { didSet { oldValue.forEach { $0.removeFromSuperview() }; controls.forEach { settingsContent.addSubview($0) }; needsLayout = true } }
    var summary = "" { didSet { summaryLabel.stringValue = summary; needsLayout = true } }
    var items: [PrintBloomView.Item] = [] { didSet { chart.items = items; updateFeedback(); needsLayout = true; needsDisplay = true } }
    var printingCondition = "" { didSet { updateFeedback() } }
    private func updateFeedback() {
        feedback.update(item: items.first { $0.id == selected }, tolerance: tolerance, condition: printingCondition)
        needsLayout = true
    }
    override var isFlipped: Bool { true }
    private var gridWidth: CGFloat { bounds.width + Design.App.margin * 2 }
    private func column(_ n: Int) -> CGFloat { Design.App.column(n, in: gridWidth) - Design.App.margin }
    override init(frame: NSRect) {
        super.init(frame: frame); chart.expanded = true; addSubview(chart)
        close.isBordered = false; close.image = Design.arrow(14, colour: Design.ink, back: true)
        close.imagePosition = .imageOnly; close.target = self; close.action = #selector(closePressed)
        close.toolTip = "Close Expanded Bloom"; close.setAccessibilityLabel("Close Expanded Bloom")
        addSubview(close)
        settingsScroll.drawsBackground = false; settingsScroll.hasVerticalScroller = true; settingsScroll.autohidesScrollers = true
        settingsScroll.documentView = settingsContent; addSubview(settingsScroll)
        settingsContent.addSubview(profileSelector); settingsContent.addSubview(summaryLabel)
        summaryLabel.maximumNumberOfLines = 0; summaryLabel.lineBreakMode = .byWordWrapping
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = feedback; addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        close.frame = NSRect(x: bounds.width - 28, y: 0, width: 28, height: 28)
        let chartWidth = Design.App.span(4, 8, in: gridWidth), middle = column(1), middleWidth = Design.App.span(1, 3, in: gridWidth)
        chart.frame = NSRect(x: column(4), y: 0, width: chartWidth, height: bounds.height)
        settingsScroll.frame = NSRect(x: middle, y: 2 * Design.App.unit, width: middleWidth, height: max(0, bounds.height - 2 * Design.App.unit))
        let settingsWidth = settingsScroll.contentSize.width
        let summaryY = CGFloat(controls.count + 1) * 3 * Design.App.unit
        settingsContent.frame = NSRect(x: 0, y: 0, width: settingsWidth, height: max(settingsScroll.contentSize.height, summaryY + 112))
        profileSelector.frame = NSRect(x: 0, y: 0, width: settingsWidth, height: 56)
        summaryLabel.frame = NSRect(x: 0, y: summaryY, width: settingsWidth, height: 112)
        for (index, control) in controls.enumerated() {
            for c in control.constraints where c.firstAttribute == .width { c.constant = settingsWidth }
            control.frame = NSRect(x: 0, y: CGFloat(index + 1) * 3 * Design.App.unit, width: settingsWidth, height: 56)
        }
        scroll.frame = NSRect(x: column(9), y: 2 * Design.App.unit, width: max(0, bounds.width - column(9)), height: max(0, bounds.height - 2 * Design.App.unit))
        feedback.fit(width: scroll.contentSize.width, minimumHeight: scroll.contentSize.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        if Design.App.masterGrid {
            for n in 1...12 { fill(NSRect(x: column(n), y: 0, width: 0.5, height: bounds.height), Design.App.gridColour.withAlphaComponent(0.35)) }
            var row: CGFloat = 0
            while row < bounds.height {
                hairline(x: 0, y: row, width: bounds.width, Design.App.gridColour.withAlphaComponent(0.18))
                hairline(x: 0, y: row + Design.App.textBaseline, width: bounds.width, Design.App.gridColour.withAlphaComponent(0.35)); row += Design.App.unit
            }
        }
        let middle = column(1), middleWidth = Design.App.span(1, 3, in: gridWidth), right = column(9), width = scroll.contentSize.width
        Design.attributed("Palette Prediction", .bodyStrong).draw(x: middle, baseline: SettingsSheet.baseline(0), width: max(0, middleWidth - 36))
        Design.attributed("Outcome", .bodyStrong).draw(x: right, baseline: SettingsSheet.baseline(0), width: max(0, width - 36))
    }
}

/// Guidance uses prediction data only; it never claims a measured proof or gamut diagnosis.
private final class PrintBloomFeedback: NSView {
    private var labels: [(NSTextField, Bool)] = []
    override var isFlipped: Bool { true }

    func update(item: PrintBloomView.Item?, tolerance: Double, condition: String) {
        labels.forEach { $0.0.removeFromSuperview() }; labels.removeAll()
        func add(_ text: String, heading: Bool = false) {
            let label = Design.text(text, heading ? .bodyStrong : .body, colour: heading ? Design.ink : Design.quiet)
            label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
            addSubview(label); labels.append((label, heading))
        }
        guard let item else {
            add("Select A Colour", heading: true)
            add("Choose a petal in the bloom to see its predicted print result and recommended next steps.")
            return
        }
        add(item.name, heading: true)
        let delta = item.delta.flatMap { $0.isFinite ? $0 : nil }
        if let delta {
            add(delta <= tolerance ? "Predicted Within Tolerance" : "Predicted Outside Tolerance", heading: true)
            add(String(format: "ΔE00 %.1f · Tolerance %.1f", delta, tolerance))
            add(delta <= tolerance
                ? "This printing condition predicts a match within your chosen tolerance. Confirm with a physical proof when colour accuracy is critical."
                : "The predicted print differs from your master by more than your chosen tolerance. This alone does not prove the colour is impossible to print.")
        } else {
            add("Prediction Unavailable", heading: true)
            add("A usable print prediction is needed before this colour can be assessed. Check the selected printing condition.")
        }
        add("Profile Prediction · No Measured Proof")
        add("Check The Printing Condition", heading: true)
        add(condition == "Generic CMYK"
            ? "Generic CMYK is an approximation. Use Printing Condition on the left to choose the profile supplied by your printer for the intended press, inks and paper."
            : "Confirm that \(condition.isEmpty ? "the selected profile" : condition) matches your printer’s press, inks and paper. Use Printing Condition on the left to change it.")
        if delta.map({ $0 > tolerance }) ?? false {
            add("Compare Real Printing Options", heading: true)
            add("Try another profile only if your printer can produce that printing condition. Ask about different paper, a wider-gamut process or a spot ink if a closer match is essential.")
            add("Keep The Master Colour", heading: true)
            add("Agree a print-specific alternative with your printer and keep the original master. Increasing tolerance changes the acceptance rule, not the printed colour.")
        }
        add("Confirm With A Physical Proof", heading: true)
        add("Ask your printer for a proof using the intended output conditions. Compare it under agreed lighting and measure the colour against the master with a spectrophotometer. Record the measured ΔE00, printing condition and approval.")
    }

    func fit(width: CGFloat, minimumHeight: CGFloat) {
        var y: CGFloat = 0
        for (index, entry) in labels.enumerated() {
            let (label, heading) = entry
            if index > 0 { y += heading ? 24 : 8 }
            let height = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width), height: 10000)).height ?? 28)
            label.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height
        }
        frame = NSRect(x: 0, y: 0, width: width, height: max(minimumHeight, y + 24))
    }
}
