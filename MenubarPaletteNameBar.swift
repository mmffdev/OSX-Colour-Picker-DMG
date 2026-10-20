import AppKit

/// A nonactivating naming bar: it takes text focus without reopening a minimized workspace.
final class MenubarPaletteNameBar: NSObject, NSTextFieldDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    private final class Bar: NSView { override var isFlipped: Bool { true } }
    private let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let field = NSTextField(string: "")
    private let picker = ClickCursorButton(title: "", target: nil, action: nil)
    private let rectangle = ClickCursorButton(title: "", target: nil, action: nil)
    private weak var library: LibraryController?
    private let palette: UUID
    private var monitors: [Any] = []
    var onClose: (() -> Void)?
    init(library: LibraryController, palette: UUID) {
        self.library = library; self.palette = palette
        super.init()
        let bar = Bar(frame: NSRect(x: 0, y: 0, width: 420, height: 60))
        SwissModalStyle.apply(to: bar); panel.contentView = bar
        panel.level = .statusBar; panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        field.stringValue = library.library.swatch(palette)?.name ?? "New Palette"
        field.placeholderAttributedString = Design.attributed("Palette Name", .body, colour: Design.quiet)
        field.font = Design.Text.body.font(); field.textColor = Design.ink
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.delegate = self; field.setAccessibilityLabel("New Palette Name")
        field.frame = NSRect(x: 84, y: 17, width: 320, height: 28); bar.addSubview(field)
        let rule = Design.hairline(Design.rule); rule.frame = NSRect(x: 84, y: 43, width: 320, height: 1); bar.addSubview(rule)
        for (button, glyph, label, x, selector) in [
            (picker, "eyedropper", "Save Name And Pick Colours", CGFloat(12), #selector(pick)),
            (rectangle, "rectangle.dashed", "Save Name And Sample A Rectangle", CGFloat(46), #selector(sample))
        ] {
            button.isBordered = false; button.image = symbol(glyph, label, size: 17)
            button.contentTintColor = Design.ink; button.imagePosition = .imageOnly
            button.toolTip = label; button.setAccessibilityLabel(label)
            button.target = self; button.action = selector
            button.frame = NSRect(x: x, y: 15, width: 28, height: 30); bar.addSubview(button)
        }
    }
    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }
    func show(below button: NSButton) {
        guard let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let x = min(max(screen.minX + 8, anchor.maxX - 420), screen.maxX - 428)
        panel.setFrameOrigin(NSPoint(x: x, y: max(screen.minY + 8, anchor.minY - 64)))
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(field); field.selectText(nil)
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel { self.finish(save: true) }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.finish(save: true) }) { monitors.append(monitor) }
    }
    private func finish(save: Bool) {
        if save {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name != library?.library.swatch(palette)?.name { library?.rename(palette, to: name) }
        }
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
        panel.orderOut(nil); onClose?()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finish(save: true); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finish(save: false); return true }
        return false
    }
    @objc private func pick() {
        let library = self.library
        finish(save: true)
        DispatchQueue.main.async { library?.startMenubarPicking(sound: Prefs.appleMenubarSound) }
    }
    @objc private func sample() {
        let library = self.library, palette = self.palette
        finish(save: true)
        DispatchQueue.main.async { library?.sampleAreaFromMenubar(sound: Prefs.appleMenubarSound, target: palette) }
    }
}
