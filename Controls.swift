import AppKit

// ---------- Colorgain's own controls, beyond the buttons (the design guide, c_c_design_controls.md) ----------

/// A dropdown as the design draws one: a caption label above, the value at 17 Regular on a hairline,
/// a chevron at the right. The menu is a Card with a Rule edge under the field, rows with a Mist
/// hover and a tick on the chosen one, and "Your own word…" turns the value into a field to type in.
final class SwissDropdown: NSView {
    private let cap: NSTextField
    private let value = NSTextField(string: "")
    private let chevron = Design.text("\u{25BE}", .caption, colour: Design.quiet)
    private let line = Design.hairline(Design.rule)
    private let options: [String]
    private let allowsOwn: Bool
    private var list: MenuPanel?
    var onChange: ((String) -> Void)?
    var text: String { value.stringValue }

    init(_ caption: String, value v: String, options: [String], allowsOwn: Bool = true, width: CGFloat) {
        cap = Design.text(caption, .caption, colour: Design.quiet)
        self.options = options
        self.allowsOwn = allowsOwn
        super.init(frame: .zero)
        value.stringValue = v
        value.isBordered = false
        value.drawsBackground = false
        value.focusRingType = .none
        value.font = Design.font(17, .regular)
        value.textColor = Design.ink
        value.isEditable = false
        value.isSelectable = false
        value.target = self
        value.action = #selector(typed)
        let row = NSStackView(views: [value, chevron])
        row.orientation = .horizontal
        row.alignment = .lastBaseline
        row.spacing = 8
        let col = NSStackView(views: [cap, row, line])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: topAnchor), col.bottomAnchor.constraint(equalTo: bottomAnchor),
            col.leadingAnchor.constraint(equalTo: leadingAnchor), col.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: width),
            row.widthAnchor.constraint(equalTo: col.widthAnchor), line.widthAnchor.constraint(equalTo: col.widthAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if value.isEditable { super.mouseDown(with: event); return }
        open()
    }

    private func open() {
        guard let win = window else { return }
        let items = options + (allowsOwn ? ["Your own word\u{2026}"] : [])
        let panel = MenuPanel(items: items, chosen: value.stringValue, width: bounds.width) { [weak self] i in
            guard let self = self else { return }
            self.close()
            if self.allowsOwn && i == items.count - 1 { self.typeOwn() }
            else { self.set(items[i]) }
        }
        let origin = win.convertToScreen(convert(NSRect(x: 0, y: 0, width: 1, height: 1), to: nil)).origin
        panel.place(below: NSPoint(x: origin.x, y: origin.y - 6))
        win.addChildWindow(panel, ordered: .above)
        list = panel
        chevron.attributedStringValue = Design.attributed("\u{25B4}", .caption, colour: Design.quiet)
    }

    private func close() {
        if let m = list { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        list = nil
        chevron.attributedStringValue = Design.attributed("\u{25BE}", .caption, colour: Design.quiet)
    }

    private func set(_ s: String) {
        value.stringValue = s
        onChange?(s)
    }

    private func typeOwn() {
        value.isEditable = true
        value.isSelectable = true
        value.stringValue = ""
        value.placeholderAttributedString = Design.attributed("Your word", .headline, size: 17, colour: Design.soft)
        line.layer?.backgroundColor = Design.ink.cgColor
        window?.makeFirstResponder(value)
    }

    @objc private func typed() {
        let s = value.stringValue.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { onChange?(s) }
    }

    /// The menu: a Card under the field, rows at 13 with a Mist hover, a tick on the chosen one.
    final class MenuPanel: NSPanel {
        init(items: [String], chosen: String, width: CGFloat, pick: @escaping (Int) -> Void) {
            let rowHeight: CGFloat = 30
            let h = CGFloat(items.count) * rowHeight + 12
            super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: h), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            let card = NSView(frame: NSRect(x: 0, y: 0, width: width, height: h))
            card.wantsLayer = true
            card.layer?.backgroundColor = Design.card.cgColor
            card.layer?.borderColor = Design.rule.cgColor
            card.layer?.borderWidth = 1
            for (i, s) in items.enumerated() {
                let r = Row(title: s, chosen: s == chosen, frame: NSRect(x: 0, y: h - 6 - CGFloat(i + 1) * rowHeight, width: width, height: rowHeight)) { pick(i) }
                card.addSubview(r)
            }
            contentView = card
        }
        func place(below p: NSPoint) { setFrameTopLeftPoint(p) }

        final class Row: NSView {
            private let act: () -> Void
            private let title: String, chosen: Bool
            private var hover = false
            init(title: String, chosen: Bool, frame: NSRect, act: @escaping () -> Void) {
                self.title = title; self.chosen = chosen; self.act = act
                super.init(frame: frame)
                addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
            }
            required init?(coder: NSCoder) { fatalError() }
            override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
            override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
            override func mouseUp(with event: NSEvent) { act() }
            override func draw(_ dirtyRect: NSRect) {
                if hover { Design.mist.setFill(); bounds.fill() }
                let t = Design.attributed(title, .body)
                t.draw(at: NSPoint(x: 14, y: (bounds.height - t.size().height) / 2))
                if chosen {
                    let tick = Design.attributed("\u{2713}", .caption)
                    tick.draw(at: NSPoint(x: bounds.width - 14 - tick.size().width, y: (bounds.height - tick.size().height) / 2))
                }
            }
        }
    }
}

/// A row that offers one thing: a heading, a line or two of caption, and a button on the right,
/// all on a hairline. The welcome's permission rows, the Bring In choices and the Ready summary are
/// all this shape.
final class ChoiceRow: NSView {
    let button: SwissButton
    private let heading: NSTextField
    private let text: NSTextField
    private let line = NSView()

    init(_ title: String, _ detail: String, button: SwissButton?, width: CGFloat, buttonWidth: CGFloat = PermissionRow.buttonWidth) {
        heading = Design.text(title, .heading)
        text = Design.text(detail, .caption, colour: Design.quiet, wraps: true)
        self.button = button ?? SwissButton("", .secondary)
        super.init(frame: .zero)
        self.button.isHidden = button == nil
        self.button.fixedWidth = buttonWidth
        text.preferredMaxLayoutWidth = width - buttonWidth - Design.Wizard.gutter
        line.wantsLayer = true
        line.layer?.backgroundColor = Design.ink.cgColor
        let words = NSStackView(views: [heading, text])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        let row = NSStackView(views: [words, NSView(), self.button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        for v in [row, line] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            row.topAnchor.constraint(equalTo: topAnchor), row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            words.widthAnchor.constraint(equalToConstant: width - buttonWidth - Design.Wizard.gutter),
            line.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 12),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1), line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(detail: String) { text.attributedStringValue = Design.attributed(detail, .caption, colour: Design.quiet, lineHeight: true) }
}
