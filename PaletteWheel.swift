import AppKit
import CoreImage

/// Circular indexing is independent of drawing, so every palette remains reachable in either direction.
enum PaletteWheelModel {
    static func index(_ position: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let value = Int(position.rounded()) % count
        return value < 0 ? value + count : value
    }
    static func visible(_ position: CGFloat, count: Int, slots: Int = 9) -> [Int] {
        guard count > 0 else { return [] }
        let centre = Int(position.rounded())
        let lower = -(min(count, slots) / 2)
        return (lower..<(lower + min(count, slots))).map { centre + $0 }
    }
}

/// A reusable edge-mounted fan. The host supplies a snapshot when opened and the action for an item.
/// `edge` names the edge of the receiving area: .left fans right, .bottom fans up, etc.
final class PaletteWheel: NSView {
    enum Edge { case left, right, top, bottom
        var angle: CGFloat { switch self { case .left: return 0; case .right: return .pi; case .top: return .pi / 2; case .bottom: return -.pi / 2 } }
    }
    struct ColourDetail { let name: String; let hex: String }
    struct Item { let id: UUID; let name: String; let colours: [NSColor]; var details: [ColourDetail] = [] }
    var items: (() -> [Item])?
    var onOpen: ((UUID) -> Void)?
    var onPresent: (() -> Void)?
    var onDismiss: (() -> Void)?
    var currentID: (() -> UUID?)?
    weak var backdropView: NSView?
    private var blurredBackdrop: NSImage?
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])
    var edge: Edge = .left { didSet { needsLayout = true; needsDisplay = true } }
    var availableRect = NSRect.zero { didSet { needsDisplay = true } }
    var anchor = NSPoint.zero { didSet { needsLayout = true; needsDisplay = true } }
    private let notch = WheelNotch(frame: .zero)
    private let openButton = NSButton(title: "", target: nil, action: nil)
    private var snapshot: [Item] = []
    private var position: CGFloat = 0, destination: CGFloat = 0
    private var reveal: CGFloat = 0, revealFrom: CGFloat = 0, revealTo: CGFloat = 0
    private var revealStart = Date.timeIntervalSinceReferenceDate
    private var lastInput = Date.timeIntervalSinceReferenceDate
    private var lastTick = Date.timeIntervalSinceReferenceDate
    private var clock: Timer?
    private weak var previousResponder: NSResponder?
    private var tracking: NSTrackingArea?
    private var hovered: Int?
    private var showingDetails = false
    private var detailOrdinal: Int?
    private var detailRect = NSRect.zero, detailBridge = NSRect.zero
    private var monitorFullscreen = false, beforeMonitorExpanded = false
    private var fieldHit = NSRect.zero, monitorHit = NSRect.zero
    private var previewExpanded = false
    private var expansion: CGFloat = 0
    private var expandHit = NSRect.zero, previousHit = NSRect.zero, nextHit = NSRect.zero
    private var spectrumHits: [(index: Int, rect: NSRect)] = []
    private var markerPosition: CGFloat = 0, markerFrom: CGFloat = 0
    private var markerStart: TimeInterval = 0
    private var previewIndex = 0 {
        didSet {
            guard oldValue != previewIndex else { return }
            markerFrom = markerPosition; markerStart = Date.timeIntervalSinceReferenceDate
            if reduced { markerPosition = CGFloat(previewIndex) }
            run()
        }
    }
    private var previewRect = NSRect.zero
    private var colourHits: [(index: Int, rect: NSRect)] = []
    private var detailOffset: CGFloat = 0
    private var detailMaximum: CGFloat = 0
    private var hits: [(ordinal: Int, angle: CGFloat, rect: NSRect)] = []
    private var lastAnnounced: UUID?
    private var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var isOpen = false
    private let spacing: CGFloat = .pi / 8
    private let inner: CGFloat = 58, spokeHeight: CGFloat = 30
    private var spokeWidth: CGFloat { min(238, max(160, crossRoom - inner - 12)) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isOpen }

    override init(frame: NSRect) {
        super.init(frame: frame)
        notch.target = self; notch.action = #selector(toggle)
        notch.toolTip = "Tab to open palettes · Scroll to turn, I for colour details, Return to open, Escape to close"
        notch.setAccessibilityLabel("Browse all palettes")
        notch.isHidden = true
        openButton.target = self; openButton.action = #selector(showSelectedDetails)
        openButton.isBordered = false
        openButton.font = .systemFont(ofSize: TextSize.caption, weight: .semibold)
        openButton.isHidden = true
        addSubview(openButton)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Palette wheel")
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Keep the notch on its edge, and fit the visible fan below the app's protected headers.
    private var usable: NSRect { availableRect.isEmpty ? bounds : availableRect }
    private var centre: NSPoint {
        let area = usable
        switch edge {
        case .left, .right:
            return NSPoint(x: anchor.x, y: min(max(anchor.y, area.minY + min(140, area.height / 2)), area.maxY - min(140, area.height / 2)))
        case .top, .bottom:
            return NSPoint(x: min(max(anchor.x, area.minX + min(140, area.width / 2)), area.maxX - min(140, area.width / 2)), y: anchor.y)
        }
    }
    private var crossRoom: CGFloat {
        let c = centre, area = usable
        return max(40, (edge == .left || edge == .right) ? min(c.y - area.minY, area.maxY - c.y) : min(c.x - area.minX, area.maxX - c.x))
    }
    private var spokeSlots: Int { 9 }
    private func world(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        let a = edge.angle, c = centre
        return NSPoint(x: c.x + x * cos(a) - y * sin(a), y: c.y + x * sin(a) + y * cos(a))
    }
    override func layout() {
        super.layout()
        let c = centre
        let vertical = edge == .left || edge == .right
        notch.frame = NSRect(x: c.x - (vertical ? 13 : 34), y: c.y - (vertical ? 34 : 13), width: vertical ? 26 : 68, height: vertical ? 68 : 26)
        if edge == .left { notch.frame.origin.x = max(0, notch.frame.origin.x) }
        notch.edge = edge; notch.expanded = isOpen; notch.isHidden = true
        let p = world(23, 0)
        openButton.frame = NSRect(x: p.x - 24, y: p.y - 11, width: 42, height: 22)
        openButton.contentTintColor = Design.ink
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        if let tracking { addTrackingArea(tracking) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isOpen || reveal > 0.01 { return super.hitTest(point) }
        return nil
    }
    @objc private func toggle() { present() }
    func present() {
        guard !isOpen else { return }
        snapshot = items?() ?? [] // Snapshot once, never fetch or reorder while the wheel is turning.
        let selected = currentID?().flatMap { id in snapshot.firstIndex { $0.id == id } } ?? 0
        position = CGFloat(selected); destination = position; hovered = nil; lastAnnounced = nil; showingDetails = false; detailOffset = 0
        onPresent?()
        captureBackdrop()
        previousResponder = window?.firstResponder
        isOpen = true
        window?.makeFirstResponder(self)
        animate(to: 1)
        openButton.isHidden = snapshot.isEmpty
        needsLayout = true
        announceSelection()
    }
    func dismiss() {
        guard isOpen else { return }
        if monitorFullscreen { monitorFullscreen = false; window?.toggleFullScreen(nil) }
        isOpen = false; hovered = nil; showingDetails = false; openButton.isHidden = true
        animate(to: 0); needsLayout = true
        onDismiss?()
        if window?.firstResponder === self || window?.firstResponder === openButton { window?.makeFirstResponder(previousResponder) }
    }
    private func animate(to value: CGFloat) {
        revealFrom = reveal; revealTo = value; revealStart = Date.timeIntervalSinceReferenceDate
        if reduced { reveal = value; needsDisplay = true } else { run() }
    }
    private func run() {
        guard clock == nil else { return }
        lastTick = Date.timeIntervalSinceReferenceDate
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }; self.tick()
        }
        clock = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        let now = Date.timeIntervalSinceReferenceDate, dt = min(0.05, now - lastTick); lastTick = now
        let duration = revealTo > revealFrom ? 0.46 : 0.20
        let t = min(1, (now - revealStart) / duration)
        reveal = revealFrom + (revealTo - revealFrom) * CGFloat(1 - pow(1 - t, 3))
        if now - lastInput > 0.12 { destination = destination.rounded() }
        position += (destination - position) * CGFloat(1 - exp(-dt * 19))
        if abs(position - destination) < 0.001 { position = destination }
        func approach(_ value: CGFloat, _ target: CGFloat) -> CGFloat {
            let next = value + (target - value) * CGFloat(1 - exp(-dt * 18))
            return abs(next - target) < 0.001 ? target : next
        }
        expansion = reduced ? (previewExpanded ? 1 : 0) : approach(expansion, previewExpanded ? 1 : 0)
        let markerT = CGFloat(min(1, (now - markerStart) / 0.24))
        let markerEase = markerT * markerT * (3 - 2 * markerT)
        markerPosition = reduced ? CGFloat(previewIndex) : markerFrom + (CGFloat(previewIndex) - markerFrom) * markerEase
        announceSelection()
        needsDisplay = true
        if markerT >= 1 && t >= 1 && expansion == (previewExpanded ? 1 : 0) && position == destination { clock?.invalidate(); clock = nil }
    }
    override func scrollWheel(with event: NSEvent) {
        if previewExpanded { return }
        guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
        let pointer = convert(event.locationInWindow, from: nil)
        if isOpen, showingDetails, detailRect.contains(pointer) {
            detailOffset = min(detailMaximum, max(0, detailOffset - event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 16)))
            needsDisplay = true; return
        }
        showingDetails = false; hovered = nil; needsDisplay = true
        guard isOpen, snapshot.count > 1 else { if !isOpen { super.scrollWheel(with: event) }; return }
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        destination -= delta / (event.hasPreciseScrollingDeltas ? 42 : 1)
        lastInput = Date.timeIntervalSinceReferenceDate
        if reduced { position = destination.rounded(); announceSelection(); needsDisplay = true } else { run() }
    }
    private func backFromPreview() {
        if previewExpanded || monitorFullscreen {
            if monitorFullscreen { monitorFullscreen = false; window?.toggleFullScreen(nil) }
            previewExpanded = false; run()
        } else { dismiss() }
    }
    override func cancelOperation(_ sender: Any?) { backFromPreview() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: backFromPreview()
        case 36, 76: openSelection()
        case 123, 126: showingDetails ? changeColour(-1) : step(-1)
        case 124, 125: showingDetails ? changeColour(1) : step(1)
        case 34:
            showSelectedDetails()
        case 48: window?.makeFirstResponder(openButton)
        default: super.keyDown(with: event)
        }
    }
    private func changeColour(_ delta: Int) {
        guard let ordinal = detailOrdinal, let i = PaletteWheelModel.index(CGFloat(ordinal), count: snapshot.count), !snapshot[i].details.isEmpty else { return }
        let count = snapshot[i].details.count
        previewIndex = (previewIndex + delta + count) % count
        let top = CGFloat(previewIndex) * 64
        if top < detailOffset { detailOffset = top }
        else if top + 54 > detailOffset + detailRect.height - 24 { detailOffset = min(detailMaximum, top + 54 - (detailRect.height - 24)) }
        needsDisplay = true
    }
    private func step(_ direction: CGFloat) {
        showingDetails = false; hovered = nil; needsDisplay = true
        guard snapshot.count > 1 else { return }
        destination = destination.rounded() + direction; lastInput = Date.timeIntervalSinceReferenceDate
        if reduced { position = destination; announceSelection(); needsDisplay = true } else { run() }
    }
    @objc private func showSelectedDetails() {
        detailOrdinal = Int(position.rounded()); showingDetails = true; detailOffset = 0; previewIndex = 0; previewExpanded = false; expansion = 0; needsDisplay = true
    }
    @objc private func openSelection() {
        guard let i = PaletteWheelModel.index(position, count: snapshot.count) else { return }
        let id = snapshot[i].id
        dismiss(); onOpen?(id)
    }
    private func announceSelection() {
        guard let i = PaletteWheelModel.index(position, count: snapshot.count) else { return }
        let item = snapshot[i]
        openButton.toolTip = "Show colour details for \(item.name)"
        openButton.setAccessibilityHelp(item.details.map { "\($0.name), \($0.hex)" }.joined(separator: "; "))
        openButton.setAccessibilityLabel("Show colour details for \(item.name), \(item.colours.count) colours, \(i + 1) of \(snapshot.count)")
        if lastAnnounced != item.id {
            lastAnnounced = item.id
            setAccessibilityValue("\(item.name), \(i + 1) of \(snapshot.count)")
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
    private func hit(_ point: NSPoint) -> Int? {
        let dx = point.x - centre.x, dy = point.y - centre.y
        guard hypot(dx, dy) > 48, dx * cos(edge.angle) + dy * sin(edge.angle) >= 0 else { return nil }
        return hits.reversed().first { h in
            let a = h.angle
            return h.rect.contains(NSPoint(x: dx * cos(a) + dy * sin(a), y: -dx * sin(a) + dy * cos(a)))
        }?.ordinal
    }
    override func mouseMoved(with event: NSEvent) {
        guard isOpen else { return }
        let pointer = convert(event.locationInWindow, from: nil)
        if showingDetails, !previewExpanded, let row = colourHits.first(where: { $0.rect.contains(pointer) }) { previewIndex = row.index }
        hovered = hit(pointer)
        toolTip = showingDetails ? nil : hovered.flatMap { PaletteWheelModel.index(CGFloat($0), count: snapshot.count) }.map { snapshot[$0].name }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isOpen else { return }
        let pointer = convert(event.locationInWindow, from: nil)
        if showingDetails {
            if let segment = spectrumHits.first(where: { $0.rect.contains(pointer) }) { changeColour(segment.index - previewIndex); return }
            if monitorHit.contains(pointer) {
                if monitorFullscreen {
                    monitorFullscreen = false; previewExpanded = beforeMonitorExpanded
                    window?.toggleFullScreen(nil)
                } else {
                    beforeMonitorExpanded = previewExpanded; previewExpanded = true
                    if window?.styleMask.contains(.fullScreen) == false { monitorFullscreen = true; window?.toggleFullScreen(nil) }
                }
                run(); return
            }
            if expandHit.contains(pointer) || fieldHit.contains(pointer) {
                if monitorFullscreen { monitorFullscreen = false; window?.toggleFullScreen(nil) }
                previewExpanded.toggle(); run(); return
            }
            if previousHit.contains(pointer) { changeColour(-1); return }
            if nextHit.contains(pointer) { changeColour(1); return }
            if previewExpanded { return }
            if let row = colourHits.first(where: { $0.rect.contains(pointer) }) {
                previewIndex = row.index; needsDisplay = true; return
            }
            if detailRect.contains(pointer) || previewRect.contains(pointer) { return }
        }
        if let ordinal = hit(convert(event.locationInWindow, from: nil)) {
            guard let i = PaletteWheelModel.index(CGFloat(ordinal), count: snapshot.count) else { return }
            let pointer = convert(event.locationInWindow, from: nil)
            if let h = hits.first(where: { $0.ordinal == ordinal }) {
                let dx = pointer.x - centre.x, dy = pointer.y - centre.y
                let localX = dx * cos(h.angle) + dy * sin(h.angle)
                if localX >= h.rect.maxX - 30 {
                    detailOrdinal = ordinal; showingDetails = true; detailOffset = 0; previewIndex = 0; previewExpanded = false; expansion = 0; needsDisplay = true; return
                }
            }
            let id = snapshot[i].id
            dismiss(); onOpen?(id)
        } else {
            let p = convert(event.locationInWindow, from: nil)
            if hypot(p.x - centre.x, p.y - centre.y) <= 48 { return }
            dismiss()
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // macOS temporarily detaches this view while moving into a fullscreen Space.
        // Preserve the wheel and preview state across that transition.
    }
    private func text(_ value: String, rect: NSRect, size: CGFloat, colour: NSColor, weight: NSFont.Weight = .regular, centred: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = centred ? .center : .left
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour, .paragraphStyle: paragraph])
    }
    private func captureBackdrop() {
        blurredBackdrop = nil
        guard let view = backdropView, !view.bounds.isEmpty,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let cg = bitmap.cgImage else { return }
        let source = CIImage(cgImage: cg)
        let scale = CGFloat(cg.width) / view.bounds.width
        let blurred = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 24 * scale]).cropped(to: source.extent)
        guard let result = Self.blurContext.createCGImage(blurred, from: source.extent) else { return }
        blurredBackdrop = NSImage(cgImage: result, size: view.bounds.size)
    }
    private func drawBackdrop() {
        guard let image = blurredBackdrop, let view = backdropView else { return }
        let rect = view.convert(view.bounds, to: self)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect.intersection(usable)).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: reveal, respectFlipped: true, hints: nil)
        Design.card.withAlphaComponent(0.18 * reveal).setFill(); NSBezierPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    private func drawColourDetails() {
        guard isOpen, showingDetails, let ordinal = detailOrdinal,
              let index = PaletteWheelModel.index(CGFloat(ordinal), count: snapshot.count) else { return }
        let item = snapshot[index]
        guard !item.details.isEmpty else { return }
        let angle = (CGFloat(ordinal) - position) * spacing
        let origin = world((inner + spokeWidth) * cos(angle), (inner + spokeWidth) * sin(angle)), area = usable.insetBy(dx: 12, dy: 12)
        let rowHeight: CGFloat = 54, gap: CGFloat = 10, header: CGFloat = 24
        let width: CGFloat = min(280, area.width), fullHeight = CGFloat(item.details.count) * (rowHeight + gap) - gap
        let height = min(fullHeight + header, area.height)
        let outward = world(inner + spokeWidth, 0)
        var x = outward.x + 52, y = area.midY - height / 2
        if edge == .right { x = outward.x - 52 - width }
        if edge == .top || edge == .bottom {
            x = origin.x + 52
        }
        x = min(max(x, area.minX), area.maxX - width)
        y = min(max(y, area.minY), area.maxY - height)
        detailRect = NSRect(x: x, y: y, width: width, height: height)
        let leftward = detailRect.midX < origin.x
        let endX = leftward ? detailRect.maxX : detailRect.minX
        detailBridge = NSRect(x: min(origin.x, endX) - 4, y: min(origin.y - 18, y), width: abs(endX - origin.x) + 8, height: max(origin.y + 18, y + height) - min(origin.y - 18, y))
        let viewport = NSRect(x: x, y: y + header, width: width, height: height - header)
        detailMaximum = max(0, fullHeight - viewport.height)
        detailOffset = min(detailOffset, detailMaximum)
        text("\(item.details.count) Colours" + (detailMaximum > 0 ? " · Scroll" : ""), rect: NSRect(x: x, y: y + 2, width: width, height: 18), size: TextSize.caption, colour: Design.quiet)
        colourHits = []
        for (i, detail) in item.details.enumerated() {
            let row = NSRect(x: x, y: viewport.minY + CGFloat(i) * (rowHeight + gap) - detailOffset, width: width, height: rowHeight)
            guard row.intersects(viewport) else { continue }
            colourHits.append((i, row.intersection(viewport)))
            let endpoint = NSPoint(x: endX, y: min(max(row.midY, viewport.minY), viewport.maxY))
            let curve = NSBezierPath(); curve.move(to: origin)
            let bend = (endX - origin.x) * 0.52
            curve.curve(to: endpoint, controlPoint1: NSPoint(x: origin.x + bend, y: origin.y), controlPoint2: NSPoint(x: endX - bend, y: endpoint.y))
            Design.rule.setStroke(); curve.lineWidth = 1; curve.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: viewport.insetBy(dx: -64, dy: -64)).addClip()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
            Design.card.setFill(); NSBezierPath(rect: row.intersection(viewport)).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: viewport).addClip()
            Design.card.setFill(); NSBezierPath(rect: row).fill(); Design.rule.setStroke(); NSBezierPath(rect: row.insetBy(dx: 0.5, dy: 0.5)).stroke()
            if item.colours.indices.contains(i) {
                item.colours[i].setFill(); NSBezierPath(rect: NSRect(x: row.minX + 12, y: row.minY + 12, width: 32, height: 30)).fill()
            }
            text(detail.name, rect: NSRect(x: row.minX + 56, y: row.minY + 9, width: width - 68, height: 18), size: TextSize.body, colour: Design.ink, weight: .medium)
            text(detail.hex, rect: NSRect(x: row.minX + 56, y: row.minY + 30, width: width - 68, height: 16), size: TextSize.caption, colour: Design.quiet)
            NSGraphicsContext.restoreGraphicsState()
        }
        // The colour field shares the list's top and bottom, with a fixed connector gate.
        let previewX = detailRect.maxX + 44
        let previewWidth = area.maxX - previewX - 12
        previewRect = .zero
        guard previewWidth >= 100 else { return }
        previewRect = NSRect(x: previewX, y: viewport.minY, width: previewWidth, height: viewport.height)
        let normal = previewRect
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * expansion }
        previewRect = NSRect(x: mix(normal.minX, bounds.minX), y: mix(normal.minY, bounds.minY), width: mix(normal.width, bounds.width), height: mix(normal.height, bounds.height))
        let active = min(previewIndex, item.details.count - 1)
        let sourceY = min(max(viewport.minY + CGFloat(active) * (rowHeight + gap) - detailOffset + rowHeight / 2, viewport.minY), viewport.maxY)
        let start = NSPoint(x: detailRect.maxX, y: sourceY)
        let end = NSPoint(x: previewRect.minX, y: previewRect.midY)
        let connector = NSBezierPath(); connector.move(to: start)
        connector.curve(to: end, controlPoint1: NSPoint(x: start.x + 22, y: start.y), controlPoint2: NSPoint(x: end.x - 22, y: end.y))
        Design.rule.setStroke(); connector.lineWidth = 1; connector.stroke()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
        Design.card.setFill(); NSBezierPath(rect: previewRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        let field = NSRect(x: previewRect.minX + 12, y: previewRect.minY + 12, width: previewRect.width - 24, height: max(24, previewRect.height - 66))
        fieldHit = field
        if item.colours.indices.contains(active) { item.colours[active].setFill(); NSBezierPath(rect: field).fill() }
        text(item.details[active].name, rect: NSRect(x: field.minX, y: field.maxY + 10, width: field.width, height: 18), size: TextSize.body, colour: Design.ink, weight: .medium)
        expandHit = NSRect(x: previewRect.maxX - 42, y: field.maxY + 8, width: 30, height: 38)
        monitorHit = NSRect(x: expandHit.minX - 36, y: expandHit.minY, width: 30, height: 38)
        previousHit = NSRect(x: previewRect.midX - 38, y: field.maxY + 8, width: 32, height: 38)
        nextHit = NSRect(x: previewRect.midX + 6, y: field.maxY + 8, width: 32, height: 38)
        let monitor = NSRect(x: monitorHit.minX + 6, y: monitorHit.minY + 9, width: 18, height: 13)
        Design.ink.setStroke(); let screen = NSBezierPath(rect: monitor); screen.lineWidth = 1.5; screen.stroke()
        let stand = NSBezierPath(); stand.move(to: NSPoint(x: monitor.midX, y: monitor.maxY)); stand.line(to: NSPoint(x: monitor.midX, y: monitor.maxY + 4)); stand.move(to: NSPoint(x: monitor.midX - 5, y: monitor.maxY + 4)); stand.line(to: NSPoint(x: monitor.midX + 5, y: monitor.maxY + 4)); stand.lineWidth = 1.5; stand.stroke()
        text(previewExpanded ? "↙" : "↗", rect: expandHit.insetBy(dx: 4, dy: 5), size: TextSize.title, colour: Design.ink, centred: true)
        text("‹", rect: previousHit.insetBy(dx: 4, dy: 5), size: TextSize.title, colour: Design.ink, centred: true)
        text("›", rect: nextHit.insetBy(dx: 4, dy: 5), size: TextSize.title, colour: Design.ink, centred: true)
        let meta = NSRect(x: field.minX, y: field.maxY + 31, width: max(60, previousHit.minX - field.minX - 12), height: 18)
        do {
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: meta).addClip()
            let spectrum = NSRect(x: meta.minX, y: meta.minY + 2, width: min(92, meta.width * 0.45), height: 12)
            spectrumHits = []
            for (i, colour) in item.colours.enumerated() {
                let segment = spectrum.width / CGFloat(item.colours.count)
                let r = NSRect(x: spectrum.minX + CGFloat(i) * segment, y: spectrum.minY, width: segment, height: spectrum.height)
                colour.setFill(); r.fill()
                spectrumHits.append((i, r.insetBy(dx: 0, dy: -3)))
            }
            if !item.colours.isEmpty {
                let segment = spectrum.width / CGFloat(item.colours.count)
                let markerRect = NSRect(x: spectrum.minX + markerPosition * segment + 0.5, y: spectrum.minY - 1, width: segment - 1, height: spectrum.height + 2)
                Design.ink.setStroke(); let marker = NSBezierPath(rect: markerRect); marker.lineWidth = 2; marker.stroke()
            }
            text(item.name, rect: NSRect(x: spectrum.maxX + 8, y: meta.minY, width: meta.maxX - spectrum.maxX - 8, height: 18), size: TextSize.caption, colour: Design.ink)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard reveal > 0.001 else { return }
        drawBackdrop()
        let c = centre
        hits = []
        // Mask the wheel at the receiving edge, as though it sits behind the rail.
        NSGraphicsContext.saveGraphicsState()
        let halfPlane = NSBezierPath(rect: NSRect(x: 0, y: -10000, width: 10000, height: 20000))
        var clipTransform = AffineTransform(rotationByRadians: edge.angle)
        clipTransform.append(AffineTransform(translationByX: c.x, byY: c.y))
        halfPlane.transform(using: clipTransform); halfPlane.addClip()
        let ordinals = PaletteWheelModel.visible(position, count: snapshot.count, slots: spokeSlots)
        // Draw the selected spoke last so its rim always remains legible.
        for ordinal in ordinals.sorted(by: { abs(CGFloat($0) - position) > abs(CGFloat($1) - position) }) {
            guard let i = PaletteWheelModel.index(CGFloat(ordinal), count: snapshot.count) else { continue }
            let difference = CGFloat(ordinal) - position, angle = difference * spacing
            let p = max(0, min(1, reveal * 1.35 - abs(difference) * 0.06))
            let a = edge.angle + angle * p
            let selected = ordinal == Int(position.rounded()), item = snapshot[i]
            let x = inner - (1 - p) * 20, rect = NSRect(x: 0, y: -spokeHeight / 2, width: x + spokeWidth, height: spokeHeight)
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by: c.x, yBy: c.y); t.rotate(byRadians: a); t.concat()
            NSGraphicsContext.current?.cgContext.setAlpha(p)
            let capsule = NSBezierPath()
            capsule.move(to: .zero)
            capsule.line(to: NSPoint(x: 48, y: rect.minY))
            capsule.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            capsule.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            capsule.line(to: NSPoint(x: 48, y: rect.maxY))
            capsule.close()
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.set()
            (selected ? Design.ink : (hovered == ordinal ? Design.paper : Design.card)).setFill(); capsule.fill()
            NSGraphicsContext.restoreGraphicsState()
            if !selected { Design.rule.setStroke(); capsule.lineWidth = 0.7; capsule.stroke() }
            let spectrumWidth = min(92, max(44, spokeWidth - 146))
            let spectrum = NSRect(x: x + 11, y: -6, width: spectrumWidth, height: 12)
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: spectrum).addClip()
            if item.colours.isEmpty { Design.rule.setFill(); NSBezierPath(rect: spectrum).fill() }
            for (j, colour) in item.colours.enumerated() {
                let width = spectrum.width / CGFloat(item.colours.count)
                colour.setFill(); NSBezierPath(rect: NSRect(x: spectrum.minX + CGFloat(j) * width, y: spectrum.minY, width: width + 0.3, height: spectrum.height)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            let label = NSRect(x: x + spectrumWidth + 22, y: -9, width: spokeWidth - spectrumWidth - 54, height: 18)
            let info = NSRect(x: rect.maxX - 23, y: -8, width: 16, height: 16)
            (selected ? Design.paper : Design.quiet).setStroke()
            let infoRing = NSBezierPath(ovalIn: info); infoRing.lineWidth = 1; infoRing.stroke()
            NSGraphicsContext.saveGraphicsState()
            let upright = NSAffineTransform(); upright.translateX(by: info.midX, yBy: info.midY); upright.rotate(byRadians: -a); upright.concat()
            text("i", rect: NSRect(x: -6, y: -8, width: 12, height: 16), size: TextSize.caption, colour: selected ? Design.paper : Design.ink, centred: true)
            NSGraphicsContext.restoreGraphicsState()
            if cos(a) < 0 {
                let flip = NSAffineTransform(); flip.translateX(by: label.midX, yBy: label.midY); flip.rotate(byDegrees: 180); flip.translateX(by: -label.midX, yBy: -label.midY); flip.concat()
            }
            text(item.name, rect: label, size: TextSize.body, colour: selected ? Design.paper : Design.ink, weight: selected ? .medium : .regular)
            NSGraphicsContext.restoreGraphicsState()
            if p > 0.8 { hits.append((ordinal, a, rect)) }
        }
        NSGraphicsContext.restoreGraphicsState()
        // The plain half-circle sits over the common origin of every spoke.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(reveal)
        let transform = NSAffineTransform(); transform.translateX(by: c.x, yBy: c.y); transform.rotate(byRadians: edge.angle); transform.concat()
        let hub = NSBezierPath(); hub.move(to: NSPoint(x: 0, y: -48)); hub.appendArc(withCenter: .zero, radius: 48, startAngle: -90, endAngle: 90, clockwise: false); hub.close()
        NSGraphicsContext.saveGraphicsState()
        let hubShadow = NSShadow(); hubShadow.shadowColor = NSColor.black.withAlphaComponent(0.18); hubShadow.shadowBlurRadius = 14; hubShadow.shadowOffset = NSSize(width: 0, height: -4); hubShadow.set()
        Design.card.setFill(); hub.fill()
        NSGraphicsContext.restoreGraphicsState()
        Design.rule.setStroke(); hub.lineWidth = 1; hub.stroke()
        let inset = NSBezierPath(); inset.move(to: NSPoint(x: 0, y: -30)); inset.appendArc(withCenter: .zero, radius: 30, startAngle: -90, endAngle: 90, clockwise: false); inset.close()
        Design.card.setFill(); inset.fill()
        NSGraphicsContext.saveGraphicsState()
        hub.addClip()
        let stripes = NSAffineTransform(); stripes.rotate(byRadians: .pi / 4 - edge.angle); stripes.concat()
        Design.rule.withAlphaComponent(0.55).setFill()
        for x in stride(from: -120, through: 120, by: 20) {
            NSBezierPath(rect: NSRect(x: CGFloat(x), y: -120, width: 10, height: 240)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        Design.card.setFill(); inset.fill()
        Design.rule.setStroke(); inset.lineWidth = 1; inset.stroke()
        NSGraphicsContext.restoreGraphicsState()
        // Redraw the launching panel's continuous divider above the wheel.
        let divider = NSBezierPath()
        if edge == .left || edge == .right {
            divider.move(to: NSPoint(x: c.x, y: usable.minY)); divider.line(to: NSPoint(x: c.x, y: usable.maxY))
        } else {
            divider.move(to: NSPoint(x: usable.minX, y: c.y)); divider.line(to: NSPoint(x: usable.maxX, y: c.y))
        }
        Design.rule.setStroke(); divider.lineWidth = 1; divider.stroke()
        drawColourDetails()
        if snapshot.isEmpty {
            let p = world(130, 0)
            text("No palettes yet", rect: NSRect(x: p.x - 70, y: p.y - 10, width: 140, height: 22), size: TextSize.body, colour: Design.quiet, centred: true)
        }
    }
}

private final class WheelNotch: NSButton {
    var edge: PaletteWheel.Edge = .left { didSet { needsDisplay = true } }
    var expanded = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); isBordered = false; title = ""; setButtonType(.momentaryChange) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (isHighlighted || expanded ? Design.ink : Design.card).setFill(); path.fill()
        Design.rule.setStroke(); path.lineWidth = 1; path.stroke()
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: bounds.midX, yBy: bounds.midY); t.rotate(byRadians: edge.angle); t.concat()
        for i in -2...2 {
            let a = CGFloat(i) * .pi / 6
            let spoke = NSBezierPath(); spoke.move(to: NSPoint(x: -3 + cos(a) * 3, y: sin(a) * 3)); spoke.line(to: NSPoint(x: -3 + cos(a) * 9, y: sin(a) * 9)); spoke.lineWidth = 1.4
            (expanded ? Design.paper : Design.ink).setStroke(); spoke.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if window?.firstResponder === self { NSFocusRingPlacement.only.set(); path.fill() }
    }
}

func runPaletteWheelTests(check: (Bool, String) -> Void) {
    print("palette wheel")
    check(PaletteWheelModel.index(-1, count: 27) == 26, "wheel scrolls backwards from the first palette to the last")
    check(PaletteWheelModel.index(27, count: 27) == 0, "wheel scrolls forwards from the last palette to the first")
    check(PaletteWheelModel.index(10, count: 0) == nil, "an empty wheel has no selectable palette")
    for count in [1, 2, 8, 9, 27, 10000] {
        let shown = PaletteWheelModel.visible(-2.4, count: count).compactMap { PaletteWheelModel.index(CGFloat($0), count: count) }
        check(shown.count == min(count, 9) && Set(shown).count == shown.count, "wheel shows unique bounded spokes for \(count) palettes")
    }
}
