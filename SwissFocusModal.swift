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
    private let form = Card()
    private var formScroll: FittedScrollView?
    private let background = NSImageView()
    private weak var previous: NSResponder?
    private var actions: [() -> Void] = []
    private var nextY: CGFloat = 28
    private var cardHeight: CGFloat = 280
    private var monitor: Any?
    private var hidToolbar = false
    private var customContent: NSView?
    var fillsWorkspace = false
    var onDismiss: (() -> Void)?
    private var preferredSize = NSSize(width: 504, height: 560)
    var overlayWindows: [NSWindow] { window.map { [$0] } ?? [] }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(title: String, message: String) {
        super.init(frame: .zero)
        card.frame = NSRect(x: 0, y: 0, width: 504, height: 560)
        background.imageScaling = .scaleAxesIndependently; addSubview(background)
        SwissModalStyle.apply(to: card); addSubview(card)
        form.frame = card.bounds; card.addSubview(form)
        addText(title, style: .header, height: 28)
        addText(message, style: .body, height: 56)
    }
    /// Large analytical views use the same focus, backdrop and dismissal as forms.
    init(content: NSView, size: NSSize) {
        super.init(frame: .zero)
        preferredSize = size; customContent = content
        background.imageScaling = .scaleAxesIndependently; addSubview(background)
        SwissModalStyle.apply(to: card); addSubview(card); card.addSubview(content)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    private func addText(_ text: String, style: Design.Text, height: CGFloat) {
        let label = Design.text(text, style)
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: 28, y: nextY, width: 448, height: height)
        label.autoresizingMask = [.width]; form.addSubview(label); nextY += height
    }
    func field(_ label: String, value: String) -> NSTextField {
        addText(label, style: .caption, height: 28)
        let field = NSTextField(string: value)
        field.font = Design.Text.body.font(); field.textColor = Design.ink
        field.backgroundColor = Design.card; field.isBordered = false; field.focusRingType = .none
        field.setAccessibilityLabel(label)
        field.frame = NSRect(x: 28, y: nextY, width: 448, height: 28); field.autoresizingMask = [.width]
        form.addSubview(field)
        let line = Design.hairline(Design.rule); line.frame = NSRect(x: 28, y: nextY + 27, width: 448, height: 1)
        line.autoresizingMask = [.width]; form.addSubview(line)
        nextY += 56; return field
    }
    func button(_ title: String, primary: Bool = false, run: @escaping () -> Void) {
        let button = SwissButton(title, primary ? .primary : .secondary, target: self, action: #selector(tapped(_:)))
        button.tag = actions.count; actions.append(run)
        button.frame = NSRect(x: 28, y: nextY, width: 448, height: 32)
        button.autoresizingMask = [.width]; form.addSubview(button); nextY += 44
    }
    func content(_ view: NSView, height: CGFloat) {
        view.frame = NSRect(x: 28, y: nextY, width: 448, height: height)
        view.autoresizingMask = [.width]; form.addSubview(view); nextY += height + 16
    }
    @objc private func tapped(_ sender: NSButton) { actions[sender.tag]() }
    func present(over view: NSView) {
        guard let root = view.window?.contentView else { return }
        if let toolbar = view.window?.toolbar, toolbar.isVisible { toolbar.isVisible = false; hidToolbar = true }
        root.layoutSubtreeIfNeeded()
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
        window?.makeFirstResponder(focusableViews.first ?? self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, Overlays.isTop(self) else { return event }
            if event.keyCode == 53 { self.dismissOverlay(); return nil }
            if event.keyCode == 48 { self.advanceFocus(backwards: event.modifierFlags.contains(.shift)); return nil }
            // Keep app command shortcuts from navigating behind a form.
            if event.modifierFlags.contains(.command), !["c", "v", "x", "a", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") { return nil }
            return event
        }
    }
    override func layout() {
        super.layout(); background.frame = bounds
        if fillsWorkspace, let content = customContent {
            card.frame = NSRect(x: 0, y: Design.App.header, width: bounds.width, height: max(0, bounds.height - Design.App.header - Design.App.footer))
            content.frame = card.bounds.insetBy(dx: Design.App.margin, dy: Design.App.margin)
            return
        }
        let width = min(preferredSize.width, bounds.width - 56)
        if let content = customContent {
            let height = min(preferredSize.height, bounds.height - 56)
            card.frame = NSRect(x: (bounds.width-width)/2, y: (bounds.height-height)/2, width: width, height: height)
            content.frame = card.bounds.insetBy(dx: 28, dy: 28)
            return
        }
        let height = min(cardHeight, max(100, bounds.height - 56))
        card.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
        if height < cardHeight {
            if formScroll == nil {
                let scroll = FittedScrollView(); scroll.drawsBackground = false
                scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
                form.removeFromSuperview(); card.addSubview(scroll); scroll.documentView = form; formScroll = scroll
            }
            formScroll?.frame = card.bounds
            form.frame = NSRect(x: 0, y: 0, width: formScroll?.contentSize.width ?? width, height: cardHeight)
        } else {
            if let scroll = formScroll { form.removeFromSuperview(); scroll.removeFromSuperview(); formScroll = nil; card.addSubview(form) }
            form.frame = card.bounds
        }
    }
    private var focusableViews: [NSView] {
        func collect(_ view: NSView) -> [NSView] {
            guard !view.isHidden else { return [] }
            if let control = view as? NSControl, !control.isEnabled { return [] }
            if view is SwissDropdown || view is NSButton || (view as? NSTextField)?.isEditable == true { return [view] }
            return view.subviews.flatMap(collect)
        }
        return collect(card)
    }
    private func advanceFocus(backwards: Bool) {
        let controls = focusableViews
        guard !controls.isEmpty else { return }
        let responder = (window?.firstResponder as? NSTextView)?.delegate as? NSView ?? window?.firstResponder as? NSView
        let current = controls.firstIndex { $0 === responder }
        let next = current.map { ($0 + (backwards ? controls.count - 1 : 1)) % controls.count } ?? (backwards ? controls.count - 1 : 0)
        window?.makeFirstResponder(controls[next]); controls[next].scrollToVisible(controls[next].bounds)
    }
    func handleOverlayEscape() -> Bool { dismissOverlay(); return true }
    func dismissOverlay() {
        let callback = onDismiss; onDismiss = nil; callback?()
        let win = window; Overlays.closed(self)
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        removeFromSuperview()
        if hidToolbar { win?.toolbar?.isVisible = true; hidToolbar = false }
        win?.makeFirstResponder(previous)
        actions.removeAll()
    }
    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
