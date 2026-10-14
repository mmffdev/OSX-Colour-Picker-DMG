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
    var showsCaption = true
    var showsExpandControl = true
    var expanded = false
    var compact = false { didSet { orderMenu.isHidden=compact;needsLayout=true;needsDisplay=true } }
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
        let gap = 0.0
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
    private var plotTop: CGFloat { compact ? 64 : 186 }
    private var diameter: CGFloat { max(20, min(bounds.width - (compact ? 128 : 216), bounds.height - (compact ? 176 : 404))) }
    var captionGuide: CGFloat { if compact { return plotTop + diameter + 64 }; return SettingsSheet.baseline(ceil((plotTop + diameter + 88 - Design.App.textBaseline) / Design.App.unit)) }
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
        let plot = NSRect(x: 0, y: plotTop, width: bounds.width, height: diameter)
        if !items.isEmpty && visibleRect.intersects(plot) { prepareMotion(at: now) }
        if !compact { Design.attributed("Delta Bloom", .bodyStrong).draw(x: 0, baseline: 17) }
        expandRect = expanded || !showsExpandControl ? .zero : NSRect(x: bounds.width - 28, y: 0, width: 28, height: 28)
        if !expanded && showsExpandControl { Design.arrow(14, colour: Design.ink, back: expanded).draw(in: expandRect.insetBy(dx: 7, dy: 7), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        let diameter = self.diameter
        let centre = NSPoint(x: bounds.midX, y: plotTop + diameter / 2), radius = diameter / 2 - 10, inner = max(22, radius * 0.20)
        let ceiling = max(tolerance * 1.6, (items.compactMap(\.delta).max() ?? tolerance) * 1.12, 0.1)
        func reach(_ value: Double) -> CGFloat { inner + (radius - inner) * CGFloat(max(0, value) / ceiling) }
        let toleranceRadius = reach(tolerance)
        var petalScale: CGFloat = 1
        func point(_ r: CGFloat, _ a: CGFloat) -> NSPoint { NSPoint(x: centre.x + r * petalScale * cos(a), y: centre.y + r * petalScale * sin(a)) }
        func petal(_ start: CGFloat, _ end: CGFloat, _ r: CGFloat, from hole: CGFloat? = nil, rounded: Bool = false) -> NSBezierPath {
            let holeRadius = hole ?? inner
            let path = NSBezierPath(); path.move(to: point(holeRadius, start))
            let corner = rounded ? min(radius * 0.065, (r - holeRadius) * 0.5, r * (end - start) * 0.15) : 0
            let angle = corner / max(1, r)
            path.line(to: point(r - corner, start))
            path.curve(to: point(r, start + angle), controlPoint1: point(r, start), controlPoint2: point(r, start))
            let segments = max(3, Int((end - start) * 24))
            for n in 1...segments { path.line(to: point(r, start + angle + (end - start - 2 * angle) * CGFloat(n) / CGFloat(segments))) }
            path.curve(to: point(r - corner, end), controlPoint1: point(r, end), controlPoint2: point(r, end))
            path.line(to: point(holeRadius, end))
            for n in 1...segments { path.line(to: point(holeRadius, end - (end - start) * CGFloat(n) / CGFloat(segments))) }
            path.close(); path.lineJoinStyle = .round; return path
        }
        for (index, item) in order.arrange(items, tolerance: tolerance).enumerated() {
            let step = CGFloat.pi * 2 / CGFloat(max(1, items.count)), gap: CGFloat = 0
            let pose = motions[item.id]?.pose(at: now)
            petalScale = CGFloat(pose?.scale ?? (entrancePending ? 0 : 1))
            let start = CGFloat(pose?.angle ?? Double(-CGFloat.pi / 2 + CGFloat(index) * step + gap)), end = start + step - gap * 2
            guard petalScale > 0.001 else { continue }
            let envelope = petal(start, end, radius, rounded: true)
            NSGraphicsContext.saveGraphicsState(); envelope.addClip()
            item.master.withAlphaComponent(0.08).setFill(); petal(start, end, toleranceRadius).fill()
            (item.printed ?? Design.mist).withAlphaComponent(0.08).setFill(); petal(start, end, radius, from: toleranceRadius).fill()
            Design.rule.withAlphaComponent(0.55).setStroke(); envelope.lineWidth = 0.5; envelope.stroke()
            let r = item.delta.map(reach) ?? inner + (radius - inner) * 0.2
            let outer = min(radius * 0.90, max(inner + 5, r))
            // Prediction underlays the whole filled petal, including the rounded master corners.
            // Keep the faint outer envelope and status-rim clearance separate from this fill.
            (item.printed ?? Design.mist).setFill()
            petal(start, end, outer, rounded: true).fill()
            item.master.setFill(); petal(start, end, min(outer, toleranceRadius), rounded: true).fill()
            if outer > toleranceRadius {
                (item.printed ?? Design.mist).setFill()
                petal(start, end, outer, from: toleranceRadius, rounded: true).fill()
            }
            let status: NSColor = item.delta.map { $0 <= tolerance ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1) : NSColor(calibratedRed: 0.77, green: 0.22, blue: 0.23, alpha: 1) } ?? Design.quiet

            NSGraphicsContext.restoreGraphicsState()
            // A gently rounded outer rim preserves the result colour and physical thickness.
            let rimWidth = radius * 0.035
            let rimRadius=radius-rimWidth/2
            let capAngle=min((end-start)/2,asin(min(1,rimWidth/(2*rimRadius))))
            let rim=NSBezierPath(), rimStart=start+capAngle, rimEnd=end-capAngle
            rim.move(to:point(rimRadius,rimStart))
            let rimSteps=max(2,Int((rimEnd-rimStart)*64))
            for n in 1...rimSteps {rim.line(to:point(rimRadius,rimStart+(rimEnd-rimStart)*CGFloat(n)/CGFloat(rimSteps)))}
            status.setStroke();rim.lineWidth=rimWidth*petalScale;rim.lineCapStyle = .round;rim.stroke()
            if selected == item.id {
                // The number sits 24 points outside the petal; selection sits another 24 out.
                let selection = NSBezierPath()
                selection.move(to: point(radius + (compact ? 30 : 48), start))
                let segments = max(3, Int((end - start) * 48))
                for n in 1...segments { selection.line(to: point(radius + (compact ? 30 : 48), start + (end - start) * CGFloat(n) / CGFloat(segments))) }
                Design.ink.setStroke(); selection.lineWidth = 2; selection.lineCapStyle = .round; selection.stroke()
            }
            paths.append((envelope, item.id))
            if items.count <= 12, petalScale > 0.75, let delta = item.delta {
                let position = point(radius + (compact ? 16 : 24), (start + end) / 2)
                let label = Design.attributed(String(format: "%.1f", delta), .caption, colour: Design.ink)
                label.draw(x: position.x - label.size().width / 2, baseline: position.y + 4)
            }
            if petalScale > 0.75 {
                let glyphRadius = radius + (compact ? 54 : 84)
                let position = point(glyphRadius, (start + end) / 2)
                // Keep dense palettes legible without letting adjacent result marks overlap.
                let size = min(compact ? 20.0 : 34.0, max(8, glyphRadius * step * 0.65))
                let rect = NSRect(x: position.x - size / 2, y: position.y - size / 2, width: size, height: size)
                if let delta = item.delta, delta.isFinite {
                    (delta <= tolerance ? ResultGlyph.pass : ResultGlyph.warning).draw(in: rect)
                } else {
                    let unknown = Design.attributed("?", .caption, colour: Design.quiet)
                    unknown.draw(x: rect.midX - unknown.size().width / 2, baseline: rect.midY + 4)
                }
            }
        }
        let ring = NSBezierPath(ovalIn: NSRect(x: centre.x - toleranceRadius, y: centre.y - toleranceRadius, width: toleranceRadius * 2, height: toleranceRadius * 2))
        Design.ink.withAlphaComponent(0.6).setStroke(); ring.lineWidth = 1; ring.setLineDash([3, 4], count: 2, phase: 0); ring.stroke()
        Design.card.setFill(); NSBezierPath(ovalIn:NSRect(x:centre.x-inner,y:centre.y-inner,width:inner*2,height:inner*2)).fill()
        let value = Design.attributed("ΔE", .bodyStrong); value.draw(x: centre.x - value.size().width / 2, baseline: centre.y + 5)
        if showsCaption {
        let y = captionGuide
        let inspect = items.first { $0.id == (selected ?? hovered) }
        Design.attributed(inspect?.name ?? "\(items.count) Palette Colours", .bodyStrong).draw(x: 0, baseline: y, width: bounds.width)
        let detail = inspect.map { item in
            item.delta.map { String(format: "ΔE00 %.2f · %@", $0, $0 <= tolerance ? "Holds" : "Outside") } ?? "No Profile Prediction"
        } ?? String(format: "Dashed Ring: ΔE00 %.1f Tolerance", tolerance)
        Design.attributed(detail, .caption, colour: Design.quiet).draw(x: 0, baseline: y + (compact ? 20 : Design.App.unit), width: bounds.width)
        if !compact { Design.attributed("Inside: RGB · Outside: Print Prediction · Rim: Pass / Fail", .caption, colour: Design.quiet).draw(x: 0, baseline: y + 2 * Design.App.unit, width: bounds.width) }
        }
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
    var order: PrintBloomView.Order = .palette { didSet { chart.order = order; if oldValue != order { updateFeedback() } } }
    @objc private func closePressed() { onClose?() }
    private let feedback = PrintBloomReport()
    private var pendingAnchor: String?
    private let scroll = FittedScrollView()
    private final class SettingsContent: NSView { override var isFlipped: Bool { true } }
    private let settingsScroll = FittedScrollView()
    private let settingsContent = SettingsContent()
    private let profileSelector = PrintProfileSelector()
    private let summaryLabel = Design.text("", .caption, colour: Design.quiet)
    var selected: String? { didSet { chart.selected = selected; pendingAnchor = selected; needsLayout = true } }
    var tolerance: Double = 2 { didSet { chart.tolerance = tolerance; updateFeedback() } }
    var controls: [SwissDropdown] = [] { didSet { oldValue.forEach { $0.removeFromSuperview() }; controls.forEach { settingsContent.addSubview($0) }; needsLayout = true } }
    var summary = "" { didSet { summaryLabel.stringValue = summary; needsLayout = true } }
    var items: [PrintBloomView.Item] = [] { didSet { chart.items = items; updateFeedback(); needsLayout = true; needsDisplay = true } }
    var printingCondition = "" { didSet { updateFeedback() } }
    private func updateFeedback() {
        feedback.update(items: order.arrange(items, tolerance: tolerance), tolerance: tolerance, condition: printingCondition)
        pendingAnchor = selected
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
        if let id = pendingAnchor, let y = feedback.anchors[id] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            pendingAnchor = nil
        }
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
        Design.attributed("Palette Report", .bodyStrong).draw(x: right, baseline: SettingsSheet.baseline(0), width: max(0, width - 36))
    }
}

/// Guidance uses prediction data only; it never claims a measured proof or gamut diagnosis.
final class PrintBloomFeedback: NSView {
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
            ? "Generic CMYK is an approximation. Use Printing Condition in the Delta Bloom panel to choose the profile supplied by your printer for the intended press, inks and paper."
            : "Confirm that \(condition.isEmpty ? "the selected profile" : condition) matches your printer’s press, inks and paper. Use Printing Condition in the Delta Bloom panel to change it.")
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

/// One continuous report, ordered like the bloom, with colour-identity anchors.
private final class PrintBloomReport: NSView {
    private var sections: [(String, PrintBloomFeedback)] = []
    private(set) var anchors: [String: CGFloat] = [:]
    override var isFlipped: Bool { true }
    func update(items: [PrintBloomView.Item], tolerance: Double, condition: String) {
        sections.forEach { $0.1.removeFromSuperview() }; sections.removeAll()
        if items.isEmpty {
            let section = PrintBloomFeedback()
            section.update(item: nil, tolerance: tolerance, condition: condition)
            sections.append(("", section)); addSubview(section)
        } else {
            for item in items {
                let section = PrintBloomFeedback()
                section.update(item: item, tolerance: tolerance, condition: condition)
                sections.append((item.id, section)); addSubview(section)
            }
        }
    }
    func fit(width: CGFloat, minimumHeight: CGFloat) {
        anchors.removeAll()
        var y: CGFloat = 0
        for (index, section) in sections.enumerated() {
            anchors[section.0] = y
            section.1.fit(width: width, minimumHeight: index == sections.count - 1 ? minimumHeight : 0)
            section.1.setFrameOrigin(NSPoint(x: 0, y: y))
            y += section.1.frame.height + 32
        }
        frame = NSRect(x: 0, y: 0, width: width, height: max(minimumHeight, y))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        for section in sections.dropFirst() {
            hairline(x: 0, y: section.1.frame.minY - 16, width: bounds.width, Design.rule)
        }
    }
}
