import AppKit

// ---------- rail2: the context rail ----------
//
// The window's four areas, by the names agreed on 2026-10-04:
//
//   rail1    the primary library rail, on the left; its title is "Catalogue"
//   rail2    the context rail, right of rail1; what it holds depends on the page showing
//   page     the main viewport
//   History  the history rail, on the right
//
// Each begins with the same title panel (TitlePanel, in PageHeader.swift). rail2 uses rail1's
// padding and text styles. Its sections are buckets, open to begin with: a heading with a
// disclosure arrow, then rows. A row is a choice from a menu, a switch, or a link. A page builds
// its own rail from these and hands it to the window, which shows it while that page is showing.

enum RailStyle {
    /// A row's height, and the gap above each bucket after the first: rail1's own.
    static let row: CGFloat = 28
    static var bucketGap: CGFloat { SidebarOutlineView.sectionGap }
    /// Where things start from the rail's left edge: the disclosure arrow, a heading's text, a row's icon, a row's text.
    static let arrow: CGFloat = 12
    static let heading: CGFloat = 28
    static let icon: CGFloat = 36
    static let text: CGFloat = 60
    static let trailing: CGFloat = 12
    static var bodyFont: NSFont { NSFont.systemFont(ofSize: NSFont.systemFontSize) }
}

/// One row of a bucket: an icon, a title, and on the right whatever the kind of row needs.
final class RailRow: NSView {
    enum Kind {
        /// A choice from a menu; the pop-up shows what is chosen.
        case choice(NSPopUpButton)
        /// On or off; a tick shows when on.
        case toggle(() -> Void)
        /// Something that happens when pressed.
        case link(() -> Void)
    }

    private let kind: Kind
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let tick = NSImageView()
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    /// For a toggle: whether it is on.
    var isOn = false { didSet { show() } }
    var isEnabled = true { didSet { show() } }

    /// `dot`, when given, replaces the symbol with a disc of that colour, as rail1 shows a tag.
    init(_ text: String, symbol name: String, dot: NSColor? = nil, tip: String = "", kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = tip.isEmpty ? nil : tip
        title.stringValue = text
        title.font = RailStyle.bodyFont
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let dot = dot {
            icon.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                dot.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
                return true
            }
        } else {
            icon.image = symbol(name, text, size: 13)
        }
        icon.contentTintColor = .secondaryLabelColor
        tick.image = symbol("checkmark", "On", size: 11, weight: .semibold)
        tick.contentTintColor = .labelColor
        var views: [NSView] = [icon, title]
        if case .choice(let menu) = kind {
            // The menu itself, plain, on the row's right: it shows what is chosen and opens on a press.
            menu.isBordered = false
            menu.font = RailStyle.bodyFont
            menu.controlSize = .regular
            (menu.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
            menu.alignment = .right
            menu.contentTintColor = .secondaryLabelColor
            menu.setContentHuggingPriority(.defaultLow, for: .horizontal)
            menu.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            menu.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            views.append(menu)
        } else {
            views.append(tick)
        }
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let last = views[2]
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: RailStyle.row),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: RailStyle.icon),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: RailStyle.text),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            last.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -RailStyle.trailing),
            last.centerYAnchor.constraint(equalTo: centerYAnchor),
            last.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
        ])
        if case .choice = kind {} else { tick.widthAnchor.constraint(equalToConstant: 14).isActive = true }
        show()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func show() {
        if case .toggle = kind { tick.isHidden = !isOn } else { tick.isHidden = true }
        // A switch that is off, and anything that cannot be used, sits back.
        var strength: CGFloat = 1
        if case .toggle = kind, !isOn { strength = 0.6 }
        if !isEnabled { strength = 0.35 }
        title.textColor = NSColor.labelColor.withAlphaComponent(strength)
        icon.alphaValue = isEnabled ? 1 : 0.4
        if case .choice(let menu) = kind { menu.isEnabled = isEnabled }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering, isEnabled else { return }
        Theme.buttonHoverBackground.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        switch kind {
        case .choice(let menu): menu.performClick(nil)   // a press anywhere on the row opens the menu
        case .toggle(let action): action()
        case .link(let action): action()
        }
    }
    override func mouseDown(with event: NSEvent) {}
}

/// A bucket: a heading that opens and closes it, then its rows. Open to begin with.
final class RailBucket: NSView {
    private let arrow = NSImageView()
    private let heading = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    private let head = NSView()
    private(set) var isOpen = true

    init(_ title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heading.stringValue = title
        heading.font = SidebarOutlineView.headingFont
        heading.textColor = .labelColor
        arrow.contentTintColor = .secondaryLabelColor
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        for v in [head, rows] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        for v in [arrow, heading] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; head.addSubview(v) }
        head.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: topAnchor),
            head.leadingAnchor.constraint(equalTo: leadingAnchor),
            head.trailingAnchor.constraint(equalTo: trailingAnchor),
            head.heightAnchor.constraint(equalToConstant: RailStyle.row),
            arrow.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: RailStyle.arrow),
            arrow.centerYAnchor.constraint(equalTo: head.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 12),
            heading.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: RailStyle.heading),
            heading.centerYAnchor.constraint(equalTo: head.centerYAnchor),
            rows.topAnchor.constraint(equalTo: head.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        show()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Replaces the bucket's rows.
    func set(_ list: [NSView]) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in list {
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }

    private func show() {
        arrow.image = symbol(isOpen ? "chevron.down" : "chevron.right", isOpen ? "Open" : "Closed", size: 9, weight: .semibold)
        rows.isHidden = !isOpen
    }
    @objc private func toggle() { isOpen.toggle(); show() }
}

/// A rail a page hands to the window: the title panel, then its buckets.
final class ContextRail: NSView {
    let title = TitlePanel("")
    private let stack = NSStackView()
    private let scroll = LetGoScrollView()
    private let page = FlippedRailPage()

    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = RailStyle.bucketGap
        scroll.documentView = page
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        page.addSubview(stack)
        for v in [title, scroll, page, stack] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(title)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 10),   // rail1's first heading sits this far under its title panel
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -20),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ buckets: [RailBucket]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for bucket in buckets {
            stack.addArrangedSubview(bucket)
            bucket.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

private final class FlippedRailPage: NSView {
    override var isFlipped: Bool { true }
}

/// rail2's place in the window: it shows whichever rail the page showing has, and nothing when the page has none.
final class ContextRailController: NSViewController {
    private var showing: NSView?

    override func loadView() { view = SidebarBackdrop() }

    func show(_ rail: NSView?) {
        _ = view
        guard rail !== showing else { return }
        showing?.removeFromSuperview()
        showing = rail
        guard let rail = rail else { return }
        rail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rail)
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: view.topAnchor),
            rail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
