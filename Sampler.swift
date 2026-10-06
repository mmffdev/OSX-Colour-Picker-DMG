import AppKit
import ScreenCaptureKit

// ---------- Sampling an area of the screen ----------
//
// Sample is Pick's neighbour in the toolbar, and always a drag: the screen dims, a rectangle is
// drawn over whatever is wanted, and the colours under it become a palette. The pixels are read
// in the display's own colour space, as a pick is, and the same extractor the Image Tool uses
// finds the colours that actually appear, not blends of them. Esc, or a drag too small to mean
// anything, gives nothing.

final class ScreenSampler {
    /// Called with the image of the area dragged over, or nil when nothing was chosen.
    private let done: (CGImage?) -> Void
    private var overlays: [SampleOverlayWindow] = []
    private static var current: ScreenSampler?

    static func begin(done: @escaping (CGImage?) -> Void) {
        current?.finish(nil)
        let s = ScreenSampler(done: done)
        current = s
        s.start()
    }

    private init(done: @escaping (CGImage?) -> Void) { self.done = done }

    private func start() {
        for screen in NSScreen.screens {
            let w = SampleOverlayWindow(screen: screen)
            w.onChosen = { [weak self] rect in self?.capture(rect, on: screen) }
            w.onCancel = { [weak self] in self?.finish(nil) }
            overlays.append(w)
            w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        overlays.first?.makeKey()
    }

    private func finish(_ image: CGImage?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        Self.current = nil
        done(image)
    }

    /// Reads the pixels under `rect` (in screen points) once the overlays are out of the way.
    private func capture(_ rect: NSRect, on screen: NSScreen) {
        overlays.forEach { $0.orderOut(nil) }
        guard rect.width >= 4, rect.height >= 4,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { finish(nil); return }
        Task { @MainActor in
            let image = await Self.image(of: rect, on: number, screen: screen)
            self.finish(image)
        }
    }

    /// The display's pixels in `rect`, through ScreenCaptureKit, in the display's colour space.
    /// Screen points are measured from the bottom left; the display's are from the top left.
    private static func image(of rect: NSRect, on display: CGDirectDisplayID, screen: NSScreen) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let target = content.displays.first(where: { $0.displayID == display }) else { return nil }
        let scale = screen.backingScaleFactor
        let local = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Int(local.width * scale)
        config.height = Int(local.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.displayP3
        let filter = SCContentFilter(display: target, excludingWindows: [])
        do { return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch {
            // Seen only in a trial run (MMFFDEV_COLOUR3_HOME set): the user gets the flash about Screen Recording instead.
            if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_HOME"] != nil { FileHandle.standardError.write(Data("sample: capture failed: \(error)\n".utf8)) }
            return nil
        }
    }
}

/// One screen's worth of dimmed glass to drag a rectangle on.
final class SampleOverlayWindow: NSWindow {
    var onChosen: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = SampleOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onChosen = { [weak self] local in
            guard let self = self else { return }
            self.onChosen?(NSRect(x: local.minX + self.frame.minX, y: local.minY + self.frame.minY, width: local.width, height: local.height))
        }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}

final class SampleOverlayView: NSView {
    var onChosen: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?
    private var tracking: NSTrackingArea?

    private var selection: NSRect? {
        guard let a = start, let b = current else { return nil }
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let chosen = selection
        start = nil
        current = nil
        needsDisplay = true
        if let r = chosen, r.width >= 4, r.height >= 4 { onChosen?(r) } else { onCancel?() }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        guard let r = selection else {
            let hint = "Drag over the colours you want \u{00B7} Esc to stop"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: TextSize.body, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85)]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 80), withAttributes: attrs)
            return
        }
        // The chosen area shows through clear; a gold edge marks it.
        NSColor.clear.setFill()
        r.fill(using: .copy)
        let edge = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
        edge.lineWidth = 1
        (colorFromHex("#FFC726") ?? .systemYellow).setStroke()
        edge.stroke()
        let label = "\(Int(r.width)) \u{00D7} \(Int(r.height))"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular), .foregroundColor: NSColor.white]
        let size = label.size(withAttributes: attrs)
        let tag = NSRect(x: r.minX, y: r.maxY + 4, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: tag.minX + 5, y: tag.minY + 2), withAttributes: attrs)
    }
}
