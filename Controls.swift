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

// MARK: - Slide to confirm, Colorgain's own

/// The track for anything that cannot be undone: light chevrons on the Card ground inside a one-point
/// Rule, "Slide To Remove" across it, and a Mist handle that is dragged to the far right. Let go short
/// of the end and it springs home; at the end it is armed, and whoever holds it turns its way out into
/// the way through.
final class SwissSlide: NSView {
    static let height: CGFloat = 40
    private static let handle: CGFloat = 40, tile: CGFloat = 24, band: CGFloat = 8, slant: CGFloat = 9
    var words = "Slide To Remove" { didSet { needsDisplay = true } }
    var onArmed: ((Bool) -> Void)?
    private(set) var armed = false
    private var offset: CGFloat = 0 { didSet { needsDisplay = true } }
    private var grabbed: CGFloat?

    override var isFlipped: Bool { true }
    private var span: CGFloat { max(0, bounds.width - Self.handle) }
    private var grip: NSRect { NSRect(x: offset, y: 0, width: Self.handle, height: bounds.height) }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        Design.card.setFill(); bounds.fill()
        NSBezierPath(rect: bounds).addClip()
        // The chevrons, pointing the way, in Mist.
        Design.mist.setFill()
        var x: CGFloat = Self.handle + 6
        while x < bounds.width {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 8)); p.line(to: NSPoint(x: x + Self.band, y: 8)); p.line(to: NSPoint(x: x + Self.band + Self.slant, y: h / 2))
            p.line(to: NSPoint(x: x + Self.band, y: h - 8)); p.line(to: NSPoint(x: x, y: h - 8)); p.line(to: NSPoint(x: x + Self.slant, y: h / 2))
            p.close(); p.fill()
            x += Self.tile
        }
        // The words, centred in the track, behind a small clear ground.
        let t = Design.attributed(words, .action, colour: Design.quiet)
        let ts = t.size()
        let tx = (bounds.width - ts.width) / 2
        Design.card.setFill(); NSRect(x: tx - 8, y: 0, width: ts.width + 16, height: h).fill()
        t.draw(at: NSPoint(x: tx, y: (h - ts.height) / 2))
        // The handle: a Mist block carrying an ink chevron.
        let g = grip
        Design.mist.setFill(); g.fill()
        Design.ink.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.2
        glyph.move(to: NSPoint(x: g.midX - 3, y: g.midY - 5)); glyph.line(to: NSPoint(x: g.midX + 3, y: g.midY)); glyph.line(to: NSPoint(x: g.midX - 3, y: g.midY + 5))
        glyph.stroke()
        Design.rule.setStroke()
        let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        grabbed = grip.contains(p) ? p.x - offset : nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let g = grabbed else { return }
        let p = convert(event.locationInWindow, from: nil)
        offset = max(0, min(span, p.x - g))
        let now = offset >= span - 1
        if now != armed { armed = now; onArmed?(armed) }
    }
    override func mouseUp(with event: NSEvent) {
        grabbed = nil
        if !armed { offset = 0 }
    }
    func reset() { armed = false; offset = 0; onArmed?(false) }
}

/// The confirm panel as the design draws it: a Card over the window on the wizard's grid, the title
/// and the note in the words' columns, a choice where there is one, the slide across, and the one
/// button at the right that is Keep It until the slide is home, then becomes the act itself.
enum SwissConfirm {
    static func ask(over window: NSWindow?, title: String, note: String, commit: String, then: @escaping () -> Void) {
        ask(over: window, title: title, note: note, commit: commit, options: []) { _ in then() }
    }

    /// With `options`, rows to choose one of before sliding; the first is chosen to begin with, and the
    /// chosen one's index comes back with the act.
    static func ask(over window: NSWindow?, title: String, note: String, commit: String, options: [String], then: @escaping (Int) -> Void) {
        let panel = ConfirmPanel(title: title, note: note, commit: commit, options: options)
        panel.present(over: window, then: then)
    }

    /// A plain word with one way out: no slide, nothing to confirm.
    static func tell(over window: NSWindow?, title: String, note: String) {
        let panel = ConfirmPanel(title: title, note: note, commit: nil, options: [])
        panel.present(over: window) { _ in }
    }

    /// A name asked for: a field on a hairline, the one button primary, a word under the field when the name will not do.
    static func name(over window: NSWindow?, title: String, note: String, placeholder: String, confirm: String, check: @escaping (String) -> String?, then: @escaping (String) -> Void) {
        let panel = ConfirmPanel(title: title, note: note, commit: nil, options: [], must: confirm, naming: (placeholder, check))
        panel.present(over: window) { _ in then(panel.text) }
    }

    /// A choice between ways on: rows to pick from, Go as the one button; Escape is the last way, the one that changes nothing.
    static func choose(over window: NSWindow?, title: String, note: String, choices: [String], then: @escaping (Int) -> Void) {
        let panel = ConfirmPanel(title: title, note: note, commit: nil, options: choices, must: "Go", escapes: true)
        panel.present(over: window) { i in then(i) }
        panel.onEscape = { then(choices.count - 1) }
    }

    /// A word that must be acted on: the one button is the act, primary, and Escape does nothing.
    static func require(over window: NSWindow?, title: String, note: String, action: String, then: @escaping () -> Void) {
        let panel = ConfirmPanel(title: title, note: note, commit: nil, options: [], must: action)
        panel.present(over: window) { _ in then() }
    }

    final class ConfirmPanel: NSPanel {
        private var done: ((Int) -> Void)?
        private let slide = SwissSlide()
        private let choices: ChoiceRows?
        private let button: SwissButton
        private let commit: String?
        private let must: String?
        private let escapes: Bool
        private let field: NSTextField?
        private let problem = Design.text("", .caption, colour: Design.orange)
        private let check: ((String) -> String?)?
        var onEscape: (() -> Void)?
        var text: String { field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        private weak var host: NSWindow?

        init(title: String, note: String, commit: String?, options: [String], must: String? = nil, escapes: Bool = false, naming: (String, (String) -> String?)? = nil) {
            self.commit = commit
            self.must = must
            self.escapes = escapes
            self.check = naming?.1
            if let (placeholder, _) = naming {
                let f = NSTextField(string: "")
                f.isBordered = false
                f.drawsBackground = false
                f.focusRingType = .none
                f.font = Design.font(17, .regular)
                f.textColor = Design.ink
                f.placeholderAttributedString = Design.attributed(placeholder, .headline, size: 17, colour: Design.soft)
                field = f
            } else { field = nil }
            button = must.map { SwissButton($0, .primary) } ?? SwissButton(commit == nil ? "Close" : "Keep It", .secondary)
            choices = options.isEmpty ? nil : ChoiceRows(options)
            let w: CGFloat = 560, margin: CGFloat = 40
            super.init(contentRect: NSRect(x: 0, y: 0, width: w, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            let card = Card(frame: NSRect(x: 0, y: 0, width: w, height: 300))
            contentView = card
            let heading = Design.text(title, .headline, size: 24)
            let words = Design.text(note, .body, colour: Design.quiet, wraps: true)
            words.preferredMaxLayoutWidth = w - 2 * margin
            slide.words = "Slide To " + (commit ?? "")
            slide.onArmed = { [weak self] armed in self?.arm(armed) }
            slide.isHidden = commit == nil
            button.target = self
            button.action = #selector(pressed)
            let bw: CGFloat = must == nil ? 132 : button.intrinsicContentSize.width
            button.fixedWidth = bw
            for v in [heading, words, slide, button] { card.addSubview(v) }
            if let c = choices { card.addSubview(c) }
            if let f = field { f.target = self; f.action = #selector(pressed); card.addSubview(f); card.addSubview(problem); card.addSubview(Design.hairline(Design.rule)) }
            // Placed by frame, top down: the title, the note, the choices, the slide, the button on its own row.
            let hs = heading.attributedStringValue.size()
            heading.frame = NSRect(x: margin, y: margin, width: w - 2 * margin, height: hs.height + 2)
            let wh = words.attributedStringValue.boundingRect(with: NSSize(width: w - 2 * margin, height: 400), options: [.usesLineFragmentOrigin]).height
            words.frame = NSRect(x: margin, y: heading.frame.maxY + 12, width: w - 2 * margin, height: wh + 4)
            var y = words.frame.maxY + 28
            if let f = field, let line = card.subviews.last {
                // The field at 17 on a hairline, the problem's line under it.
                f.frame = NSRect(x: margin, y: y, width: w - 2 * margin, height: 24)
                line.frame = NSRect(x: margin, y: y + 28, width: w - 2 * margin, height: 1)
                problem.frame = NSRect(x: margin, y: y + 34, width: w - 2 * margin, height: 16)
                y += 28 + 22 + 16
            }
            if let c = choices {
                c.frame = NSRect(x: margin, y: y, width: w - 2 * margin, height: c.height)
                y = c.frame.maxY + 28
            }
            if commit != nil {
                slide.frame = NSRect(x: margin, y: y, width: w - 2 * margin, height: SwissSlide.height)
                y = slide.frame.maxY + 28
            }
            button.frame = NSRect(x: w - margin - bw, y: y, width: bw, height: 32)
            let h = button.frame.maxY + margin
            setContentSize(NSSize(width: w, height: h))
            card.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }

        private func arm(_ armed: Bool) {
            guard let commit = commit else { return }
            button.title = armed ? commit : "Keep It"
            button.setKind(armed ? .primary : .secondary)
            button.arrow = armed
        }

        @objc private func pressed() {
            if let check = check {
                // The name must do before the panel goes: the problem is said under the field, and the field keeps the focus.
                if let wrong = check(text) ?? (text.isEmpty ? "Give it a name." : nil) {
                    problem.attributedStringValue = Design.attributed(wrong, .caption, colour: Design.orange)
                    makeFirstResponder(field)
                    return
                }
            }
            let go = must != nil || (commit != nil && slide.armed)
            close(then: go)
        }

        override func cancelOperation(_ sender: Any?) {
            if escapes { close(then: false); onEscape?() } else if must == nil { close(then: false) }
        }
        override var canBecomeKey: Bool { true }

        /// The veil over the host while the panel is up: a half-ink window that takes every click.
        private var veil: NSWindow?

        func present(over window: NSWindow?, then: @escaping (Int) -> Void) {
            done = then
            host = window
            guard let w = window else { center(); makeKeyAndOrderFront(nil); return }
            // Not an AppKit sheet, which rounds its corners: a veil over the host, and the panel centred above it.
            let v = NSWindow(contentRect: w.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            v.isOpaque = false
            v.backgroundColor = Design.ink.withAlphaComponent(0.45)
            v.hasShadow = false
            v.ignoresMouseEvents = false
            w.addChildWindow(v, ordered: .above)
            veil = v
            let f = w.frame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.midY - frame.height / 2))
            w.addChildWindow(self, ordered: .above)
            makeKeyAndOrderFront(nil)
            if let f = field { makeFirstResponder(f) }
        }

        private func close(then go: Bool) {
            if let w = host {
                w.removeChildWindow(self)
                if let v = veil { w.removeChildWindow(v); v.orderOut(nil); veil = nil }
                w.makeKey()
            }
            orderOut(nil)
            if go { done?(choices?.chosen ?? 0) }
            done = nil
        }

        /// The choice rows: a square before each word, ink-filled on the chosen one, 28 to a row.
        final class ChoiceRows: NSView {
            private let options: [String]
            private(set) var chosen = 0
            static let row: CGFloat = 28, square: CGFloat = 12, step: CGFloat = 24
            var height: CGFloat { CGFloat(options.count) * Self.row }
            init(_ options: [String]) { self.options = options; super.init(frame: .zero) }
            required init?(coder: NSCoder) { fatalError() }
            override var isFlipped: Bool { true }
            override func draw(_ dirtyRect: NSRect) {
                for (i, o) in options.enumerated() {
                    let y = CGFloat(i) * Self.row, b = y + 19
                    let sq = NSRect(x: 0, y: b - 10, width: Self.square, height: Self.square)
                    (i == chosen ? Design.ink : Design.card).setFill(); sq.fill()
                    Design.ink.setStroke()
                    let edge = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
                    let t = Design.attributed(o, .body, colour: i == chosen ? Design.ink : Design.quiet)
                    t.draw(at: NSPoint(x: Self.step, y: b - Design.Text.body.font().ascender))
                }
            }
            override func mouseDown(with event: NSEvent) {
                let p = convert(event.locationInWindow, from: nil)
                let i = Int(p.y / Self.row)
                if options.indices.contains(i) { chosen = i; needsDisplay = true }
            }
        }

        /// The Card: the panel's ground with its one-point Rule edge, flipped so the frames read top down.
        final class Card: NSView {
            override var isFlipped: Bool { true }
            override func draw(_ dirtyRect: NSRect) {
                Design.card.setFill(); bounds.fill()
                Design.rule.setStroke()
                let edge = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); edge.lineWidth = 1; edge.stroke()
            }
        }
    }
}
