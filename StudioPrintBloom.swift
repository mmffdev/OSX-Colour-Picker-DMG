import AppKit

/// A radial ΔE plot. Equal-angle petals preserve palette order; radius uses one shared numeric scale.
final class PrintBloomView: NSView {
    struct Item { let id: String; let name: String; let master: NSColor; let printed: NSColor?; let delta: Double?; let ink: Double? }
    var items: [Item] = [] { didSet { needsDisplay = true } }
    var tolerance: Double = 2 { didSet { needsDisplay = true } }
    var selected: String? { didSet { needsDisplay = true } }
    var onSelect: ((String) -> Void)?
    var onExpand: (() -> Void)?
    var expanded = false
    private var paths: [(NSBezierPath, String)] = []
    private var hovered: String?
    private var tracking: NSTrackingArea?
    private var expandRect = NSRect.zero
    private var diameter: CGFloat { max(20, min(bounds.width - 64, bounds.height - 156)) }
    var captionGuide: CGFloat { SettingsSheet.baseline(ceil((38 + diameter + 40 - Design.App.textBaseline) / Design.App.unit)) }
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
        Design.attributed("Colour Bloom", .bodyStrong).draw(x: 0, baseline: 17)
        expandRect = NSRect(x: bounds.width - 28, y: 0, width: 28, height: 28)
        Design.arrow(14, colour: Design.ink, back: expanded).draw(in: expandRect.insetBy(dx: 7, dy: 7), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let diameter = self.diameter
        let centre = NSPoint(x: bounds.midX, y: 38 + diameter / 2), radius = diameter / 2 - 10, inner = radius * 0.20
        let ceiling = max(tolerance * 1.6, (items.compactMap(\.delta).max() ?? tolerance) * 1.12, 0.1)
        func reach(_ value: Double) -> CGFloat { inner + (radius - inner) * CGFloat(max(0, value) / ceiling) }
        let toleranceRadius = reach(tolerance)
        func point(_ r: CGFloat, _ a: CGFloat) -> NSPoint { NSPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a)) }
        func petal(_ start: CGFloat, _ end: CGFloat, _ r: CGFloat) -> NSBezierPath {
            let path = NSBezierPath(); path.move(to: point(inner, start))
            path.line(to: point(r, start))
            let segments = max(3, Int((end - start) * 24))
            for n in 1...segments { path.line(to: point(r, start + (end - start) * CGFloat(n) / CGFloat(segments))) }
            path.line(to: point(inner, end))
            for n in 1...segments { path.line(to: point(inner, end - (end - start) * CGFloat(n) / CGFloat(segments))) }
            path.close(); path.lineJoinStyle = .round; return path
        }
        for (index, item) in items.enumerated() {
            let step = CGFloat.pi * 2 / CGFloat(max(1, items.count)), gap = min(step * 0.11, 0.035)
            let start = -CGFloat.pi / 2 + CGFloat(index) * step + gap, end = start + step - gap * 2
            let envelope = petal(start, end, radius)
            item.master.withAlphaComponent(0.08).setFill(); envelope.fill()
            Design.rule.withAlphaComponent(0.55).setStroke(); envelope.lineWidth = 0.5; envelope.stroke()
            let r = item.delta.map(reach) ?? inner + (radius - inner) * 0.2
            let shape = petal(start, end, max(inner + 5, r))
            item.master.setFill(); shape.fill()
            let status: NSColor = item.delta.map { $0 <= tolerance ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1) : NSColor(calibratedRed: 0.77, green: 0.22, blue: 0.23, alpha: 1) } ?? Design.quiet

            if let printed = item.printed {
                printed.setFill(); petal(start + gap, end - gap, min(max(inner + 5, r), inner + 10)).fill()
            }
            paths.append((envelope, item.id))
            if items.count <= 12, let delta = item.delta {
                let position = point(radius + 24, (start + end) / 2)
                let label = Design.attributed(String(format: "%.1f", delta), .caption, colour: Design.ink)
                label.draw(x: position.x - label.size().width / 2, baseline: position.y + 4)
            }
        }
        let ring = NSBezierPath(ovalIn: NSRect(x: centre.x - toleranceRadius, y: centre.y - toleranceRadius, width: toleranceRadius * 2, height: toleranceRadius * 2))
        Design.ink.withAlphaComponent(0.6).setStroke(); ring.lineWidth = 1; ring.setLineDash([3, 4], count: 2, phase: 0); ring.stroke()
        fill(NSRect(x: centre.x - 18, y: centre.y - 13, width: 36, height: 26), Design.card)
        let value = Design.attributed("ΔE", .bodyStrong); value.draw(x: centre.x - value.size().width / 2, baseline: centre.y + 5)
        let rim = NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        let rimColour: NSColor
        if items.isEmpty || items.contains(where: { $0.delta == nil }) { rimColour = Design.quiet }
        else if items.contains(where: { ($0.delta ?? 0) > tolerance }) { rimColour = NSColor(calibratedRed: 0.77, green: 0.22, blue: 0.23, alpha: 1) }
        else { rimColour = NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1) }
        rimColour.setStroke(); rim.lineWidth = 6 / max(1, window?.backingScaleFactor ?? 1); rim.stroke()
        let y = captionGuide
        let inspect = items.first { $0.id == (hovered ?? selected) }
        Design.attributed(inspect?.name ?? "\(items.count) Palette Colours", .bodyStrong).draw(x: 0, baseline: y, width: bounds.width)
        let detail = inspect.map { item in
            item.delta.map { String(format: "ΔE00 %.2f · %@", $0, $0 <= tolerance ? "Holds" : "Outside") } ?? "No Profile Prediction"
        } ?? String(format: "Dashed Ring: ΔE00 %.1f Tolerance", tolerance)
        Design.attributed(detail, .caption, colour: Design.quiet).draw(x: 0, baseline: y + Design.App.unit, width: bounds.width)
        Design.attributed("Petal Reach: ΔE · Rim: Palette Pass / Fail", .caption, colour: Design.quiet).draw(x: 0, baseline: y + 2 * Design.App.unit, width: bounds.width)
        if items.isEmpty { Design.attributed("Choose A Palette", .body).draw(x: centre.x - 50, baseline: centre.y + 40) }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let next = paths.first { $0.0.contains(p) }?.1
        if hovered != next { hovered = next; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if expandRect.contains(p) { onExpand?(); return }
        if let id = paths.first(where: { $0.0.contains(p) })?.1 { selected = id; onSelect?(id) }
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
    private let comparison = WholePalettePredictionGraph()
    private let scroll = FittedScrollView()
    var selected: String? { didSet { chart.selected = selected; comparison.selected = selected } }
    var tolerance: Double = 2 { didSet { chart.tolerance = tolerance; comparison.tolerance = tolerance } }
    var controls: [SwissDropdown] = [] { didSet { oldValue.forEach { $0.removeFromSuperview() }; controls.forEach { addSubview($0) }; needsLayout = true } }
    var summary = "" { didSet { needsDisplay = true } }
    var items: [PrintBloomView.Item] = [] { didSet { chart.items = items; comparison.items = items; needsLayout = true; needsDisplay = true } }
    override var isFlipped: Bool { true }
    private var gridWidth: CGFloat { bounds.width + Design.App.margin * 2 }
    private func column(_ n: Int) -> CGFloat { Design.App.column(n, in: gridWidth) - Design.App.margin }
    override init(frame: NSRect) {
        super.init(frame: frame); chart.expanded = true; addSubview(chart)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = comparison; addSubview(scroll)
        comparison.onSelect = { [weak self] id in self?.chart.onSelect?(id) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let chartWidth = Design.App.span(1, 5, in: gridWidth), middle = column(10), middleWidth = bounds.width - column(10)
        chart.frame = NSRect(x: 0, y: 0, width: chartWidth, height: bounds.height)
        for (index, control) in controls.enumerated() {
            for c in control.constraints where c.firstAttribute == .width { c.constant = middleWidth }
            control.frame = NSRect(x: middle, y: SettingsSheet.baseline(CGFloat(2 + index * 3)) - 11, width: middleWidth, height: 56)
        }
        scroll.frame = NSRect(x: column(6), y: 2 * Design.App.unit, width: Design.App.span(9, 12, in: gridWidth), height: max(0, bounds.height - 2 * Design.App.unit))
        comparison.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, CGFloat(items.count) * 2 * Design.App.unit))
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
        let middle = column(10), middleWidth = bounds.width - middle, right = column(6), width = scroll.contentSize.width
        Design.attributed("Palette Prediction", .bodyStrong).draw(x: middle, baseline: SettingsSheet.baseline(0), width: middleWidth)
        Design.attributed("Whole Palette", .bodyStrong).draw(x: right, baseline: SettingsSheet.baseline(0), width: width)
        SettingsSheet.paragraph(summary, x: middle, firstBaseline: chart.captionGuide, width: middleWidth, height: Design.App.unit * 4, colour: Design.quiet)
        Design.attributed("Master", .caption, colour: Design.quiet).draw(x: right + 24, baseline: SettingsSheet.baseline(1))
        Design.attributed("Printed Prediction", .caption, colour: Design.quiet).draw(x: right + 24 + (width - 40 - 12) / 2 + 12, baseline: SettingsSheet.baseline(1), width: (width - 40 - 12) / 2)
    }
}

private final class WholePalettePredictionGraph: NSView {
    private let rollover = Rollover<String>()
    private var tracking: NSTrackingArea?
    var items: [PrintBloomView.Item] = [] { didSet { rollover.settle(); needsDisplay = true } }
    var selected: String? { didSet { rollover.settle(); needsDisplay = true } }
    var tolerance: Double = 2 { didSet { needsDisplay = true } }
    var onSelect: ((String) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); rollover.barberPole = true
        rollover.keys = { [weak self] in self?.items.map(\.id) ?? [] }
        rollover.locked = { [weak self] id in self?.selected == id }
        rollover.redraw = { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) {
        let index = Int(convert(event.locationInWindow, from: nil).y / (2 * Design.App.unit))
        rollover.moved(items.indices.contains(index) ? items[index].id : nil)
    }
    override func mouseExited(with event: NSEvent) { rollover.moved(nil) }
    override func draw(_ dirtyRect: NSRect) {
        let unit = Design.App.unit, half = (bounds.width - 40 - 12) / 2
        for (index, item) in items.enumerated() {
            let top = CGFloat(index) * 2 * unit
            rollover.pane(item.id, box: NSRect(x: 0, y: top, width: bounds.width, height: 2 * unit), reach: bounds.width, stripWidth: 24)
            let delta = item.delta.map { String(format: "ΔE %.1f", $0) } ?? "No Profile"
            let values = Design.attributed(delta + (item.ink.map { String(format: " · %.0f%% Ink", $0) } ?? ""), .caption, colour: Design.quiet)
            Design.attributed(item.name, .bodyStrong).draw(x: 24, baseline: top + Design.App.textBaseline, width: max(0, bounds.width - 40 - values.size().width - 8))
            values.draw(right: bounds.width - 16, baseline: top + Design.App.textBaseline)
            let master = NSRect(x: 24, y: top + unit, width: half, height: unit - 12), printed = master.offsetBy(dx: half + 12, dy: 0)
            fill(master, item.master); fill(printed, item.printed ?? Design.mist)
            let status: NSColor = item.delta.map { $0 <= tolerance ? NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.34, alpha: 1) : NSColor(calibratedRed: 0.77, green: 0.22, blue: 0.23, alpha: 1) } ?? Design.quiet
            status.setStroke(); let edge = NSBezierPath(rect: printed.insetBy(dx: 1, dy: 1)); edge.lineWidth = 2; edge.stroke()
            hairline(x: 0, y: top + 2 * unit - 1, width: bounds.width, Design.rule)
        }
    }
    override func mouseDown(with event: NSEvent) {
        let index = Int(convert(event.locationInWindow, from: nil).y / (2 * Design.App.unit))
        if items.indices.contains(index) { onSelect?(items[index].id) }
    }
}
