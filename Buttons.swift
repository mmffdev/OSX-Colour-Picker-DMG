import AppKit

// ---------- The app's own buttons ----------
//
// This is a colour tool: the controls must not out-shout the colours. So the main buttons and the
// toggles are drawn here, in greys taken from the background, instead of in the system's accent.
// Three looks: at rest, under the pointer (hover), and pressed or switched on (active). Hover and
// active can be set in Settings, under Theme; unset, they are the greys below.

extension Theme {
    /// The background as plain red, green and blue, whichever step is showing.
    private static var base: NSColor {
        if let l = level, let c = colorFromHex(levels[l]) { return c }
        return colorFromHex(isDark ? "#1E1E1E" : "#ECECEC") ?? .gray
    }
    /// A grey part of the way from the background towards the text colour.
    static func grey(_ fraction: CGFloat) -> NSColor { base.blended(withFraction: fraction, of: isDark ? .white : .black) ?? base }
    /// Text that reads on the background and on the greys made from it.
    static var text: NSColor { isDark ? .white : .black }

    static var defaultSidebarSelection: NSColor { grey(0.18) }
    static var defaultButtonHover: NSColor { grey(0.18) }
    static var defaultButtonActive: NSColor { grey(0.30) }

    static var sidebarSelectionBackground: NSColor { Prefs.sidebarSelectionBackground.flatMap(colorFromHex) ?? defaultSidebarSelection }
    static var sidebarSelectionText: NSColor { Prefs.sidebarSelectionText.flatMap(colorFromHex) ?? text }
    static var buttonRest: NSColor { grey(0.09) }
    static var buttonHoverBackground: NSColor { Prefs.buttonHoverBackground.flatMap(colorFromHex) ?? defaultButtonHover }
    static var buttonHoverText: NSColor { Prefs.buttonHoverText.flatMap(colorFromHex) ?? text }
    static var buttonActiveBackground: NSColor { Prefs.buttonActiveBackground.flatMap(colorFromHex) ?? defaultButtonActive }
    static var buttonActiveText: NSColor { Prefs.buttonActiveText.flatMap(colorFromHex) ?? text }
}

enum ButtonStyle {
    static let height: CGFloat = 24
    static let smallHeight: CGFloat = 20
    static let radius: CGFloat = 6
    static let pad: CGFloat = 10
    static let gap: CGFloat = 5
}

/// A template image filled with one colour.
private func tinted(_ image: NSImage, _ colour: NSColor) -> NSImage {
    let out = NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        colour.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    return out
}

private func watchTheme(_ view: NSView) {
    for name in [Notification.Name.prefsDidChange, .themeDidChange] {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak view] _ in view?.needsDisplay = true }
    }
}

/// A push button in the theme's greys: an optional symbol, then its title.
final class ThemedButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(title: String, image: NSImage?, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        font = NSFont.systemFont(ofSize: TextSize.body)
        setButtonType(.momentaryChange)
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var label: NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font ?? NSFont.systemFont(ofSize: TextSize.body)])
    }

    override var intrinsicContentSize: NSSize {
        let text = title.isEmpty ? 0 : ceil(label.size().width)
        let icon = image?.size.width ?? 0
        let between = (text > 0 && icon > 0) ? ButtonStyle.gap : 0
        return NSSize(width: max(34, ButtonStyle.pad * 2 + icon + between + text), height: ButtonStyle.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let active = isHighlighted || state == .on
        let fill = !isEnabled ? Theme.buttonRest : active ? Theme.buttonActiveBackground : hovering ? Theme.buttonHoverBackground : Theme.buttonRest
        var ink = active ? Theme.buttonActiveText : hovering ? Theme.buttonHoverText : Theme.text
        if !isEnabled { ink = Theme.text.withAlphaComponent(0.35) }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: ButtonStyle.radius, yRadius: ButtonStyle.radius).fill()

        let text = NSMutableAttributedString(attributedString: label)
        text.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: text.length))
        let textSize = title.isEmpty ? .zero : text.size()
        let iconSize = image?.size ?? .zero
        let between: CGFloat = (textSize.width > 0 && iconSize.width > 0) ? ButtonStyle.gap : 0
        var x = bounds.midX - (iconSize.width + between + textSize.width) / 2
        if let image = image {
            tinted(image, ink).draw(in: NSRect(x: x, y: bounds.midY - iconSize.height / 2, width: iconSize.width, height: iconSize.height))
            x += iconSize.width + between
        }
        if textSize.width > 0 { text.draw(at: NSPoint(x: x, y: bounds.midY - textSize.height / 2)) }
    }
}

/// A row of choices, one of them on: the theme's own segmented control.
final class ToggleBar: NSControl {
    private let labels: [String]
    var selectedSegment = 0 { didSet { needsDisplay = true } }
    private var hovered: Int?
    private var tracking: NSTrackingArea?

    init(labels: [String], target: AnyObject? = nil, action: Selector? = nil) {
        self.labels = labels
        super.init(frame: .zero)
        self.target = target
        self.action = action
        font = NSFont.systemFont(ofSize: TextSize.body)
        setAccessibilityRole(.radioGroup)
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func text(_ i: Int, _ colour: NSColor) -> NSAttributedString {
        NSAttributedString(string: labels[i], attributes: [.font: font ?? NSFont.systemFont(ofSize: TextSize.body), .foregroundColor: colour])
    }
    private var widths: [CGFloat] { labels.indices.map { ceil(text($0, .black).size().width) + ButtonStyle.pad * 2 } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: widths.reduce(0, +), height: controlSize == .small ? ButtonStyle.smallHeight : ButtonStyle.height)
    }
    override func sizeToFit() { setFrameSize(intrinsicContentSize) }
    override var controlSize: NSControl.ControlSize { didSet { invalidateIntrinsicContentSize() } }
    override var font: NSFont? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    /// Each choice's rectangle: its own width, scaled if the bar has been given a different one.
    private var rects: [NSRect] {
        let w = widths, total = w.reduce(0, +)
        let scale = total > 0 ? bounds.width / total : 1
        var x: CGFloat = 0
        return w.map { width in
            defer { x += width * scale }
            return NSRect(x: x, y: 0, width: width * scale, height: bounds.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.buttonRest.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: ButtonStyle.radius, yRadius: ButtonStyle.radius).fill()
        for (i, rect) in rects.enumerated() {
            let on = i == selectedSegment, over = i == hovered && isEnabled
            if on || over {
                (on ? Theme.buttonActiveBackground : Theme.buttonHoverBackground).setFill()
                NSBezierPath(roundedRect: rect, xRadius: ButtonStyle.radius, yRadius: ButtonStyle.radius).fill()
            }
            var ink = on ? Theme.buttonActiveText : over ? Theme.buttonHoverText : Theme.text.withAlphaComponent(0.75)
            if !isEnabled { ink = Theme.text.withAlphaComponent(0.35) }
            let t = text(i, ink), size = t.size()
            t.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        }
    }

    private func segment(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return rects.firstIndex { $0.contains(p) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseMoved(with event: NSEvent) { let s = segment(at: event); if s != hovered { hovered = s; needsDisplay = true } }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let s = segment(at: event), s != selectedSegment else { return }
        selectedSegment = s
        sendAction(action, to: target)
    }
}
