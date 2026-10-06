import AppKit

/// The house confirm for anything that cannot be undone, after Platform's: a panel dead centre over
/// its window, saying what is about to happen, with a chevron track beneath. Only the handle dragged
/// right across the whole track says yes; let go short of the end and it springs back. Esc, or Go
/// Back, is the way out. No button commits.
enum SlideConfirm {
    static let gold = NSColor(red: 0xFC / 255, green: 0xC8 / 255, blue: 0x0A / 255, alpha: 1)   // #FCC80A
    static let ink = NSColor(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1B / 255, alpha: 1)    // #1B1B1B

    /// Asks over `window` (or wherever the app is, without one) and runs `then` only when the slide completes.
    static func ask(over window: NSWindow?, title: String, note: String, confirm: String = "Slide To Confirm", then: @escaping () -> Void) {
        let panel = SlidePanel(title: title, note: note, hint: confirm)
        panel.present(over: window, then: then)
    }
}

private final class SlidePanel: NSPanel {
    private var done: (() -> Void)?
    private let track = ChevronTrack()

    init(title: String, note: String, hint: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 10), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        let words = NSTextField(wrappingLabelWithString: note)
        words.font = NSFont.systemFont(ofSize: TextSize.body)
        words.textColor = .secondaryLabelColor
        let cue = caption(hint.uppercased())
        cue.alignment = .center
        cue.font = NSFont.systemFont(ofSize: TextSize.caption, weight: .semibold)
        let back = ThemedButton(title: "Go Back", image: symbol("arrow.left", "Go Back", size: 11), target: self, action: #selector(goBack))
        back.keyEquivalent = "\u{1B}"
        for v in [heading, words, track, cue, back] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(v) }
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView = card
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 400),
            heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            words.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            words.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            words.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            track.topAnchor.constraint(equalTo: words.bottomAnchor, constant: 22),
            track.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            track.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            track.heightAnchor.constraint(equalToConstant: ChevronTrack.height),
            cue.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 10),
            cue.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            back.topAnchor.constraint(equalTo: cue.bottomAnchor, constant: 12),
            back.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            back.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
        ])
        words.preferredMaxLayoutWidth = 352
        heading.preferredMaxLayoutWidth = 352
        card.layer?.backgroundColor = Theme.background.cgColor
        card.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        track.onComplete = { [weak self] in self?.finish(confirmed: true) }
        track.onArmed = { cue.isHidden = true }
    }

    func present(over window: NSWindow?, then: @escaping () -> Void) {
        done = then
        contentView?.layoutSubtreeIfNeeded()
        let size = contentView?.fittingSize ?? NSSize(width: 400, height: 200)
        setContentSize(size)
        // Dead centre of the window it belongs to, or of the screen.
        let within = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        setFrameOrigin(NSPoint(x: within.midX - size.width / 2, y: within.midY - size.height / 2))
        window?.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        track.start()
        NSApp.runModal(for: self)
    }

    private func finish(confirmed: Bool) {
        track.stop()
        NSApp.stopModal()
        parent?.removeChildWindow(self)
        orderOut(nil)
        if confirmed { done?() }
        done = nil
    }

    @objc private func goBack() { finish(confirmed: false) }
    override func cancelOperation(_ sender: Any?) { goBack() }
    override var canBecomeKey: Bool { true }
}

/// The track: a field of gold chevrons marching right over ink, one tile per loop, and a handle that
/// is dragged across it. The last half-percent counts; anything less lets go and slides home.
final class ChevronTrack: NSView {
    static let height: CGFloat = 40
    private static let handle: CGFloat = 34, tile: CGFloat = 30, band: CGFloat = 15, slant: CGFloat = 12
    var onComplete: (() -> Void)?
    var onArmed: (() -> Void)?
    private var offset: CGFloat = 0 { didSet { needsDisplay = true } }
    private var march: CGFloat = 0
    private var armed = false
    private var timer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self = self, !self.armed else { return }
            self.march = (self.march + Self.tile / 90).truncatingRemainder(dividingBy: Self.tile)   // one tile every 1.5 s
            self.needsDisplay = true
        }
        RunLoop.current.add(timer!, forMode: .modalPanel)
    }
    func stop() { timer?.invalidate(); timer = nil }

    private var span: CGFloat { max(0, bounds.width - Self.handle) }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        SlideConfirm.ink.setFill()
        bounds.fill()
        if !armed {
            NSBezierPath(rect: bounds).addClip()
            SlideConfirm.gold.setFill()
            var x = -Self.tile + march
            while x < bounds.width {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x, y: 0))
                p.line(to: NSPoint(x: x + Self.band, y: 0))
                p.line(to: NSPoint(x: x + Self.band + Self.slant, y: h / 2))
                p.line(to: NSPoint(x: x + Self.band, y: h))
                p.line(to: NSPoint(x: x, y: h))
                p.line(to: NSPoint(x: x + Self.slant, y: h / 2))
                p.close()
                p.fill()
                x += Self.tile
            }
            // The ground covered so far, darkened behind the handle.
            SlideConfirm.ink.withAlphaComponent(0.72).setFill()
            NSRect(x: 0, y: 0, width: offset + Self.handle, height: h).fill()
        } else {
            let label = NSAttributedString(string: "ARMED", attributes: [.font: NSFont.systemFont(ofSize: TextSize.caption, weight: .semibold), .foregroundColor: SlideConfirm.gold, .kern: 0.5])
            let size = label.size()
            label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (h - size.height) / 2))
        }
        // The handle: a pale block carrying the way to go, a tick once there.
        let grip = NSRect(x: offset, y: 0, width: Self.handle, height: h)
        NSColor(white: 0.95, alpha: 1).setFill()
        grip.fill()
        SlideConfirm.ink.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = 2
        glyph.lineCapStyle = .round
        glyph.lineJoinStyle = .round
        let c = NSPoint(x: grip.midX, y: grip.midY)
        if armed {
            glyph.move(to: NSPoint(x: c.x - 6, y: c.y)); glyph.line(to: NSPoint(x: c.x - 2, y: c.y - 4)); glyph.line(to: NSPoint(x: c.x + 6, y: c.y + 5))
        } else {
            glyph.move(to: NSPoint(x: c.x - 3, y: c.y + 6)); glyph.line(to: NSPoint(x: c.x + 4, y: c.y)); glyph.line(to: NSPoint(x: c.x - 3, y: c.y - 6))
        }
        glyph.stroke()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func resetCursorRects() { addCursorRect(NSRect(x: offset, y: 0, width: Self.handle, height: bounds.height), cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard !armed, let window = window else { return }
        let start = convert(event.locationInWindow, from: nil)
        guard NSRect(x: offset, y: 0, width: Self.handle, height: bounds.height).contains(start) else { return }
        let grab = start.x - offset
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        while true {
            guard let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let x = convert(e.locationInWindow, from: nil).x - grab
            offset = min(max(0, x), span)
            if e.type == .leftMouseUp { break }
        }
        if span > 0, offset / span >= 0.995 {
            armed = true
            offset = span
            onArmed?()
            window.invalidateCursorRects(for: self)
            needsDisplay = true
            // A beat to see it land before it goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.onComplete?() }
        } else {
            offset = 0   // short of the end: home again
        }
        window.invalidateCursorRects(for: self)
    }
}
