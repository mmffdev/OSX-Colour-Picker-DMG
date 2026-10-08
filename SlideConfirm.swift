import AppKit

/// The house confirm for anything that cannot be undone, after Platform's: a panel dead centre over
/// its window, saying what is about to happen, with a chevron track beneath. The handle is dragged
/// right across the whole track; let go short of the end and it springs back. At the end it becomes
/// the button that commits, named for the act. Esc, or Cancel, is the way out.
enum SlideConfirm {
    static let gold = NSColor(red: 0xFC / 255, green: 0xC8 / 255, blue: 0x0A / 255, alpha: 1)   // #FCC80A
    static let ink = NSColor(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1B / 255, alpha: 1)    // #1B1B1B
    static let slate = NSColor(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255, alpha: 1)  // #2C2C2C

    /// A way out that keeps things: shown as a plain button above the track, and closes the panel when pressed.
    struct Option {
        let title: String
        let run: () -> Void
    }

    /// Asks on the window's own confirm panel, the one primitive for anything that cannot be undone: the safer choices as rows
    /// before the slide, the slide itself the act. The chosen row runs instead of the act; the last row is the act.
    static func ask(over window: NSWindow?, title: String, note: String, options: [Option] = [], commit: String = "Remove", then: @escaping () -> Void) {
        if options.isEmpty { SwissConfirm.ask(over: window, title: title, note: note, commit: commit, then: then); return }
        SwissConfirm.ask(over: window, title: title, note: note, commit: commit, options: options.map { $0.title } + [commit]) { choice in
            if options.indices.contains(choice) { options[choice].run() } else { then() }
        }
    }
}

private final class SlidePanel: NSPanel {
    private var done: (() -> Void)?
    private let track = ChevronTrack()
    private let options: [SlideConfirm.Option]

    init(title: String, note: String, options: [SlideConfirm.Option], commit: String) {
        self.options = options
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
        let cue = caption("SLIDE TO CONFIRM")
        cue.alignment = .center
        cue.font = NSFont.systemFont(ofSize: TextSize.caption, weight: .semibold)
        let back = ThemedButton(title: "Cancel", image: symbol("xmark", "Cancel", size: 11), target: self, action: #selector(goBack))
        back.keyEquivalent = "\u{1B}"
        // The safer choices, each a button of its own, then a line saying the track is the other way.
        let choices = NSStackView(views: options.enumerated().map { at, one in
            let b = ThemedButton(title: one.title, image: nil, target: self, action: #selector(optionTapped(_:)))
            b.tag = at
            return b
        })
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 8
        let or = caption(options.isEmpty ? "" : "OR, TO \(commit.uppercased()) FOR GOOD")
        or.font = NSFont.systemFont(ofSize: TextSize.caption, weight: .semibold)
        for v in [heading, words, choices, or, track, cue, back] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(v) }
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
            choices.topAnchor.constraint(equalTo: words.bottomAnchor, constant: options.isEmpty ? 0 : 18),
            choices.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            or.topAnchor.constraint(equalTo: choices.bottomAnchor, constant: options.isEmpty ? 0 : 18),
            or.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            track.topAnchor.constraint(equalTo: or.bottomAnchor, constant: options.isEmpty ? 22 : 8),
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
        track.commit = commit
        track.onComplete = { [weak self] in self?.finish(confirmed: true) }
        track.onArmed = { armed in cue.isHidden = armed }
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
    @objc private func optionTapped(_ sender: NSButton) {
        guard options.indices.contains(sender.tag) else { return }
        let run = options[sender.tag].run
        finish(confirmed: false)
        run()
    }
    override func cancelOperation(_ sender: Any?) { goBack() }
    override var canBecomeKey: Bool { true }
}

/// The track: a field of gold chevrons marching right over ink, one tile per loop, and a handle that
/// is dragged across it. The last half-percent counts; anything less lets go and slides home. At the
/// end the handle widens into the button that commits.
final class ChevronTrack: NSView {
    static let height: CGFloat = 40
    private static let handle: CGFloat = 34, tile: CGFloat = 30, band: CGFloat = 15, slant: CGFloat = 12, edge: CGFloat = 3
    var commit = "Remove"
    var onComplete: (() -> Void)?
    var onArmed: ((Bool) -> Void)?
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
            self.march = (self.march + Self.tile / 180).truncatingRemainder(dividingBy: Self.tile)   // one tile every 3 s
            self.needsDisplay = true
        }
        RunLoop.current.add(timer!, forMode: .modalPanel)
    }
    func stop() { timer?.invalidate(); timer = nil }

    private var span: CGFloat { max(0, bounds.width - Self.handle) }
    private var label: NSAttributedString {
        NSAttributedString(string: commit, attributes: [.font: NSFont.systemFont(ofSize: TextSize.body, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
    }
    /// Where the handle is: a block on the way across, the commit button once armed.
    private var grip: NSRect {
        armed ? NSRect(x: bounds.width - (label.size().width + 28), y: 0, width: label.size().width + 28, height: bounds.height)
              : NSRect(x: offset, y: 0, width: Self.handle, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        SlideConfirm.ink.setFill()
        bounds.fill()
        NSBezierPath(rect: bounds).addClip()
        SlideConfirm.gold.setFill()
        var x = -Self.tile + (armed ? 0 : march)
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
        NSRect(x: 0, y: 0, width: grip.maxX, height: h).fill()
        // The handle: a slate block carrying the way to go, or the word that commits once there.
        let g = grip
        SlideConfirm.slate.setFill()
        g.fill()
        if armed {
            let size = label.size()
            label.draw(at: NSPoint(x: g.midX - size.width / 2, y: g.midY - size.height / 2))
        } else {
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let glyph = NSBezierPath()
            glyph.lineWidth = 2
            glyph.lineCapStyle = .round
            glyph.lineJoinStyle = .round
            let c = NSPoint(x: g.midX, y: g.midY)
            glyph.move(to: NSPoint(x: c.x - 3, y: c.y + 6)); glyph.line(to: NSPoint(x: c.x + 4, y: c.y)); glyph.line(to: NSPoint(x: c.x - 3, y: c.y - 6))
            glyph.stroke()
        }
        SlideConfirm.slate.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: Self.edge / 2, dy: Self.edge / 2))
        border.lineWidth = Self.edge
        border.stroke()
    }

    override func resetCursorRects() { addCursorRect(grip, cursor: armed ? .pointingHand : .openHand) }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let start = convert(event.locationInWindow, from: nil)
        guard grip.contains(start) else { return }
        if armed {
            // The button: pressed and let go on it commits.
            guard let up = window.nextEvent(matching: [.leftMouseUp]), grip.contains(convert(up.locationInWindow, from: nil)) else { return }
            onComplete?()
            return
        }
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
            // Across: the handle is now the button, and nothing happens until it is pressed.
            armed = true
            offset = span
            onArmed?(true)
            needsDisplay = true
        } else {
            offset = 0   // short of the end: home again
        }
        window.invalidateCursorRects(for: self)
    }
}
