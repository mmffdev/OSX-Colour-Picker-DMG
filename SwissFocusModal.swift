import AppKit
import CoreImage

/// Square Swiss modal surface shared by forms and safety prompts.
enum SwissModalStyle {
    static func apply(to card: NSView) {
        card.wantsLayer = true
        card.layer?.backgroundColor = Design.card.cgColor
        card.layer?.borderWidth = 1; card.layer?.borderColor = Design.rule.cgColor
        let shadow = NSShadow(); shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24); card.shadow = shadow
    }
}

/// A focus-taking modal primitive: automatic frozen backdrop blur, shadow, Escape and focus restoration.
final class SwissFocusModal: NSView, Overlay {
    private final class Card: NSView { override var isFlipped: Bool { true } }
    let card: NSView = Card()
    private let background = NSImageView()
    private weak var previous: NSResponder?
    private var actions: [() -> Void] = []
    private var nextY: CGFloat = 28
    private var cardHeight: CGFloat = 280
    private var monitor: Any?
    var overlayWindows: [NSWindow] { window.map { [$0] } ?? [] }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(title: String, message: String) {
        super.init(frame: .zero)
        card.frame = NSRect(x: 0, y: 0, width: 504, height: 560)
        background.imageScaling = .scaleAxesIndependently; addSubview(background)
        SwissModalStyle.apply(to: card); addSubview(card)
        addText(title, style: .header, height: 28)
        addText(message, style: .body, height: 56)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private func addText(_ text: String, style: Design.Text, height: CGFloat) {
        let label = Design.text(text, style)
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: 28, y: nextY, width: 448, height: height)
        label.autoresizingMask = [.width]; card.addSubview(label); nextY += height
    }
    func field(_ label: String, value: String) -> NSTextField {
        addText(label, style: .caption, height: 28)
        let field = NSTextField(string: value)
        field.font = Design.Text.body.font(); field.textColor = Design.ink
        field.backgroundColor = Design.card; field.isBordered = false; field.focusRingType = .none
        field.setAccessibilityLabel(label)
        field.frame = NSRect(x: 28, y: nextY, width: 448, height: 28); field.autoresizingMask = [.width]
        card.addSubview(field)
        let line = Design.hairline(Design.rule); line.frame = NSRect(x: 28, y: nextY + 27, width: 448, height: 1)
        line.autoresizingMask = [.width]; card.addSubview(line)
        nextY += 56; return field
    }
    func button(_ title: String, primary: Bool = false, run: @escaping () -> Void) {
        let button = SwissButton(title, primary ? .primary : .secondary, target: self, action: #selector(tapped(_:)))
        button.tag = actions.count; actions.append(run)
        button.frame = NSRect(x: 28, y: nextY, width: 448, height: 32)
        button.autoresizingMask = [.width]; card.addSubview(button); nextY += 44
    }
    @objc private func tapped(_ sender: NSButton) { actions[sender.tag]() }
    func present(over view: NSView) {
        guard let root = view.window?.contentView else { return }
        previous = root.window?.firstResponder
        frame = root.bounds; autoresizingMask = [.width, .height]
        if let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: rep)
            if let cg = rep.cgImage {
                let input = CIImage(cgImage: cg)
                let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 12]).cropped(to: input.extent)
                if let image = CIContext().createCGImage(output, from: input.extent) { background.image = NSImage(cgImage: image, size: root.bounds.size) }
            }
        }
        cardHeight = nextY + 16
        root.addSubview(self, positioned: .above, relativeTo: nil)
        needsLayout = true; layoutSubtreeIfNeeded(); Overlays.opened(self)
        window?.makeFirstResponder(card.subviews.first { $0 is NSTextField && ($0 as! NSTextField).isEditable } ?? self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53 { self.dismissOverlay(); return nil }
            // Keep app command shortcuts from navigating behind a form.
            if event.modifierFlags.contains(.command), !["c", "v", "x", "a", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") { return nil }
            return event
        }
    }
    override func layout() {
        super.layout(); background.frame = bounds
        let width = min(504, bounds.width - 56)
        card.frame = NSRect(x: (bounds.width - width) / 2, y: max(28, (bounds.height - cardHeight) / 2), width: width, height: cardHeight)
    }
    func dismissOverlay() {
        let win = window; Overlays.closed(self)
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        removeFromSuperview(); win?.makeFirstResponder(previous)
        actions.removeAll()
    }
    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
