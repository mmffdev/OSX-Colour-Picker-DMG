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
        if let fixed = fixedBackground, let c = colorFromHex(fixed) { return c }
        return colorFromHex(isDark ? "#1E1E1E" : "#FFFFFF") ?? .gray
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

/// The one set of numbers every button and toggle on a page is drawn from. A button is as tall as
/// the action bar's row, whatever holds it; nothing on a page sets a button height of its own.
enum ButtonStyle {
    static var height: CGFloat { PageStyle.barHeight }
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

func watchTheme(_ view: NSView) {
    for name in [Notification.Name.prefsDidChange, .themeDidChange] {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak view] _ in view?.needsDisplay = true }
    }
}

/// A push button in the theme's greys: an optional symbol, then its title.
final class ThemedButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?
    /// A fill of its own instead of the theme's greys, for the one button a page leads with (a
    /// setup's Continue). Its text is black or white, whichever reads better on it.
    var prominent: NSColor? { didSet { needsDisplay = true } }

    init(title: String, image: NSImage?, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        font = NSFont.systemFont(ofSize: TextSize.body)
        setButtonType(.momentaryChange)
        // The height is pinned, not left to AppKit, which otherwise sizes some buttons from the cell
        // and others from the numbers here. Just short of required, so a button laid out by frame still works.
        let tall = heightAnchor.constraint(equalToConstant: ButtonStyle.height)
        tall.priority = NSLayoutConstraint.Priority(999)
        tall.isActive = true
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.required, for: axis)
            setContentCompressionResistancePriority(.required, for: axis)
        }
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var image: NSImage? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override func sizeToFit() { setFrameSize(intrinsicContentSize) }
    /// None: AppKit pads a button's frame beyond its layout size by amounts that vary with its image
    /// and title, which is what made two buttons of one kind come out at two heights.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var fittingSize: NSSize { intrinsicContentSize }

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
    /// A press counts even when the app is not the active one. AppKit otherwise spends the first click on
    /// activating the app and the button does nothing, which is what a gate shown before the app opens meets.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let active = isHighlighted || state == .on
        var fill = !isEnabled ? Theme.buttonRest : active ? Theme.buttonActiveBackground : hovering ? Theme.buttonHoverBackground : Theme.buttonRest
        var ink = active ? Theme.buttonActiveText : hovering ? Theme.buttonHoverText : Theme.text
        if !isEnabled { ink = Theme.text.withAlphaComponent(0.35) }
        if let lead = prominent?.usingColorSpace(.sRGB), isEnabled {
            fill = isHighlighted ? lead.blended(withFraction: 0.2, of: .black) ?? lead : hovering ? lead.blended(withFraction: 0.12, of: .white) ?? lead : lead
            ink = ThemedButton.readable(on: lead)
        }
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

extension ThemedButton {
    /// Black or white, whichever has more contrast on `colour` (WCAG relative luminance).
    static func readable(on colour: NSColor) -> NSColor {
        let c = colour.usingColorSpace(.sRGB) ?? colour
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        return 1.05 / (l + 0.05) >= (l + 0.05) / 0.05 ? .white : .black
    }
}

/// The bar every page lays its controls out on: one row, as tall as a button, with a group at the
/// left and a group at the right and the spare width between them. A label for a group is made
/// with `ActionBar.label`. Pages put their buttons and toggles in one of these; nothing lays a
/// row of controls out by hand.
final class ActionBar: NSView {
    private let row = NSStackView()

    init(leading: [NSView], trailing: [NSView] = []) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        row.setViews(leading + [spacer] + trailing, in: .leading)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PageStyle.barSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // A toggle is as tall as the buttons beside it.
        for toggle in (leading + trailing).compactMap({ $0 as? ToggleBar }) {
            toggle.heightAnchor.constraint(equalToConstant: ButtonStyle.height).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// A wider gap after one of the bar's views, to set one group apart from the next.
    func setGap(_ gap: CGFloat, after view: NSView) { row.setCustomSpacing(gap, after: view) }

    /// The quiet word in front of a group: "Group By", "Show".
    static func label(_ text: String) -> NSTextField {
        let l = caption(text)
        l.textColor = .secondaryLabelColor
        return l
    }
}

/// A section's heading on a page: "Palette", "Swatches".
func sectionHeading(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = NSFont.systemFont(ofSize: 15, weight: .bold)
    l.textColor = .labelColor
    return l
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

// ---------- Colorgain's own buttons (the design guide, c_c_design_controls.md) ----------

/// A button drawn to the design: ink fill for the one primary action on a screen, an ink outline for
/// a secondary one, underlined text for a quiet one. Helvetica Neue Medium 13, 32 high, radius 4.
/// The primary carries the arrow on its right behind a hairline.
final class SwissButton: NSButton {
    /// A press counts even when the app is not the active one; see ThemedButton.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    enum Kind { case primary, secondary, quiet }
    private(set) var kind: Kind
    /// A button that turns into another, as Keep It becomes Remove once the slide is home.
    func setKind(_ k: Kind) { kind = k; invalidateIntrinsicContentSize(); needsDisplay = true }
    enum Trailing { case none, arrow, tick, cross }
    /// What sits in the cell at the right end, behind a hairline: the arrow for "go on", a tick or a cross for a state.
    var trailing = Trailing.none { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var arrow: Bool { get { trailing == .arrow } set { trailing = newValue ? .arrow : .none } }
    /// A set width, so two buttons on different rows line up; nil takes the title's width.
    var fixedWidth: CGFloat? { didSet { invalidateIntrinsicContentSize() } }
    /// The diagonal arrow in front of the title: "go there", for a quiet button that leaves the page.
    var leadingArrow = false { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    private static let arrowSize: CGFloat = 14, arrowGap: CGFloat = 6
    private var hovering = false
    private var tracking: NSTrackingArea?
    static let height: CGFloat = 32

    init(_ title: String, _ kind: Kind, target: AnyObject? = nil, action: Selector? = nil) {
        self.kind = kind
        super.init(frame: .zero)
        // Every boxed button carries the arrow cell unless given a state instead; a quiet one is text alone.
        if kind != .quiet { trailing = .arrow }
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        font = Design.Text.action.font()
        setButtonType(.momentaryChange)
        if kind == .primary { arrow = true }
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.required, for: axis)
            setContentCompressionResistancePriority(.required, for: axis)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var fittingSize: NSSize { intrinsicContentSize }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    private var label: NSAttributedString { Design.attributed(title, .action, colour: ink) }
    private var ink: NSColor {
        if !isEnabled { return Design.ink.withAlphaComponent(0.35) }
        return kind == .primary ? Design.card : Design.ink
    }
    /// The baseline sits where the text's does, so a row of these aligns with text beside it.
    override var firstBaselineOffsetFromTop: CGFloat { (Self.height - label.size().height) / 2 + Design.Text.action.font().ascender + 1 }
    override var lastBaselineOffsetFromBottom: CGFloat { Self.height - firstBaselineOffsetFromTop }

    override var intrinsicContentSize: NSSize {
        let text = ceil(label.size().width)
        switch kind {
        case .quiet: return NSSize(width: text + (leadingArrow ? Self.arrowSize + Self.arrowGap : 0), height: Self.height)
        case .secondary, .primary:
            return NSSize(width: fixedWidth ?? (text + 28 + (trailing != .none ? 22 + 10 : 0)), height: Self.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let box = NSBezierPath(rect: r)
        switch kind {
        case .primary:
            let fill = !isEnabled ? Design.ink.withAlphaComponent(0.35) : isHighlighted ? NSColor.black : hovering ? Design.hex("#2C2C2C") : Design.ink
            fill.setFill(); box.fill()
        case .secondary:
            if hovering && isEnabled { Design.mist.setFill(); box.fill() }
            Design.ink.withAlphaComponent(isEnabled ? 1 : 0.35).setStroke(); box.lineWidth = 1
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        case .quiet: break
        }
        let text = label
        let size = text.size()
        let y = (r.height - size.height) / 2
        let lead: CGFloat = kind == .quiet && leadingArrow ? Self.arrowSize + Self.arrowGap : 0
        let x: CGFloat = (kind == .quiet ? 0 : 14) + lead
        text.draw(at: NSPoint(x: x, y: y))
        if kind == .quiet {
            if leadingArrow {
                Design.arrow(Self.arrowSize, colour: ink).draw(in: NSRect(x: 0, y: (r.height - Self.arrowSize) / 2, width: Self.arrowSize, height: Self.arrowSize),
                                                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            ink.setStroke()
            let u = NSBezierPath(); u.move(to: NSPoint(x: lead, y: y + size.height + 1.5)); u.line(to: NSPoint(x: lead + size.width, y: y + size.height + 1.5)); u.lineWidth = 1; u.stroke()
        }
        if kind != .quiet && trailing != .none {
            let cell = NSRect(x: r.maxX - 22, y: 0, width: 22, height: r.height)
            (kind == .primary ? Design.paper.withAlphaComponent(0.18) : Design.ink.withAlphaComponent(0.18)).setStroke()
            let l = NSBezierPath(); l.move(to: NSPoint(x: cell.minX, y: 8)); l.line(to: NSPoint(x: cell.minX, y: r.height - 8)); l.lineWidth = 1; l.stroke()
            let glyph = trailing == .arrow ? "\u{2192}" : trailing == .tick ? "\u{2713}" : "\u{2715}"
            let a = Design.attributed(glyph, .action, colour: ink)
            let s = a.size()
            a.draw(at: NSPoint(x: cell.midX - s.width / 2, y: (r.height - s.height) / 2))
        }
        if window?.firstResponder === self, NSApp.isFullKeyboardAccessEnabled {
            Design.orange.setStroke()
            let f = NSBezierPath(rect: r.insetBy(dx: -2, dy: -2)); f.lineWidth = 2; f.stroke()
        }
    }
}
