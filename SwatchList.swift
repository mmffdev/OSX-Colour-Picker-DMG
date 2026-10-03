import AppKit

// ---------- The vertical view of a project palette ----------
//
// One colour to a row: the colour itself, what it is called, and beside it two tabs. Description
// is the designer's words on why the colour is here, kept in the project's file with the palette.
// History lists everything that happened to that colour in this palette, read from the library's
// history, and plays it back. Only palettes in a project have this view.

enum SwatchListStyle {
    static let rowHeight: CGFloat = 132
    static let rowGap: CGFloat = 12
    static let tileWidth: CGFloat = 132
    static let infoWidth: CGFloat = 170
    static let gap: CGFloat = 16
    /// The widest the description and history run: a line of text stays readable on a wide window.
    static let textWidth: CGFloat = 720
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SwatchListView: NSView {
    private let library: LibraryController
    private let scroll = LetGoScrollView()
    private let stack = NSStackView()
    private var rows: [SwatchRow] = []
    private var palette: UUID?
    /// The tab each colour was left on, so a reload does not flip it back.
    private var tabs: [String: Int] = [:]

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SwatchListStyle.rowGap
        let page = FlippedView()
        for v in [stack, page] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        page.addSubview(stack)
        scroll.documentView = page
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: PageStyle.side),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -PageStyle.side),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the colours in order. The same colours as before are refreshed where they stand, so
    /// a description being typed in one row is not lost when another is saved.
    func show(_ hexes: [String], in palette: UUID, locked: Bool) {
        if palette != self.palette { tabs = [:] }
        if palette == self.palette, rows.map({ $0.hex }) == hexes {
            rows.forEach { $0.refresh(locked: locked) }
            return
        }
        self.palette = palette
        rows.forEach { $0.removeFromSuperview() }
        rows = hexes.map { hex in
            let row = SwatchRow(hex: hex, palette: palette, library: library, tab: tabs[hex] ?? 0)
            row.onTab = { [weak self] tab in self?.tabs[hex] = tab }
            return row
        }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            row.refresh(locked: locked)
        }
    }

    func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// One colour: its tile, its name and values, then Description or History.
final class SwatchRow: NSView, NSTextFieldDelegate {
    let hex: String
    private let palette: UUID
    private weak var library: LibraryController?
    var onTab: ((Int) -> Void)?

    private let tile = NSView()
    private let name = NSTextField(labelWithString: "")
    private let values = NSStackView()
    private let tabs = ToggleBar(labels: ["Description", "History"])
    private lazy var play = toolButton("Play Back", "play.fill", "Walk through what happened to this colour, oldest first", target: self, action: #selector(playTapped))
    private let note = NSTextField()
    private let noteBox = NSView()
    private let steps = NSStackView()
    private let stepsScroll = LetGoScrollView()
    private let none = caption("", size: TextSize.body)
    private var lines: [(row: NSStackView, step: SwatchStep)] = []
    private var playing: Timer?

    init(hex: String, palette: UUID, library: LibraryController, tab: Int) {
        self.hex = hex
        self.palette = palette
        self.library = library
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        tile.wantsLayer = true
        tile.layer?.backgroundColor = colorFromHex(hex)?.cgColor
        tile.layer?.cornerRadius = 10
        tile.layer?.cornerCurve = .continuous
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        tile.toolTip = "Click to copy"
        tile.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(copyTapped)))

        name.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        values.orientation = .vertical
        values.alignment = .leading
        values.spacing = 2
        let info = NSStackView(views: [name, values])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 6

        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.selectedSegment = tab
        tabs.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let top = NSStackView(views: [tabs, spacer, play])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = PageStyle.barSpacing

        note.isBordered = false
        note.drawsBackground = false
        note.focusRingType = .none
        note.font = NSFont.systemFont(ofSize: TextSize.body)
        note.placeholderString = "Notes\u{2026}"
        note.cell?.wraps = true
        note.cell?.isScrollable = false
        note.cell?.usesSingleLineMode = false
        note.lineBreakMode = .byWordWrapping
        note.delegate = self
        noteBox.wantsLayer = true
        noteBox.layer?.cornerRadius = 8
        noteBox.layer?.cornerCurve = .continuous
        noteBox.addSubview(note)

        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 4
        let page = FlippedView()
        for v in [steps, page] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        page.addSubview(steps)
        stepsScroll.documentView = page
        stepsScroll.hasVerticalScroller = true
        stepsScroll.autohidesScrollers = true
        stepsScroll.drawsBackground = false

        for v in [tile, info, top, noteBox, stepsScroll, none, note] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in [tile, info, top, noteBox, stepsScroll, none] as [NSView] { addSubview(v) }
        let s = SwatchListStyle.self
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: s.rowHeight),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor),
            tile.topAnchor.constraint(equalTo: topAnchor),
            tile.bottomAnchor.constraint(equalTo: bottomAnchor),
            tile.widthAnchor.constraint(equalToConstant: s.tileWidth),
            info.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: s.gap),
            info.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            info.widthAnchor.constraint(equalToConstant: s.infoWidth),
            top.leadingAnchor.constraint(equalTo: info.trailingAnchor, constant: s.gap),
            fill(top.trailingAnchor.constraint(equalTo: trailingAnchor)),
            top.widthAnchor.constraint(lessThanOrEqualToConstant: s.textWidth),
            top.topAnchor.constraint(equalTo: topAnchor),
            top.heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            tabs.heightAnchor.constraint(equalTo: play.heightAnchor),
        ])
        for box in [noteBox, stepsScroll] as [NSView] {
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: top.leadingAnchor),
                box.trailingAnchor.constraint(equalTo: top.trailingAnchor),
                box.topAnchor.constraint(equalTo: top.bottomAnchor, constant: PageStyle.barGap),
                box.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            note.leadingAnchor.constraint(equalTo: noteBox.leadingAnchor, constant: 10),
            note.trailingAnchor.constraint(equalTo: noteBox.trailingAnchor, constant: -10),
            note.topAnchor.constraint(equalTo: noteBox.topAnchor, constant: 8),
            note.bottomAnchor.constraint(lessThanOrEqualTo: noteBox.bottomAnchor, constant: -8),
            page.topAnchor.constraint(equalTo: stepsScroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: stepsScroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: stepsScroll.contentView.trailingAnchor),
            steps.topAnchor.constraint(equalTo: page.topAnchor, constant: 2),
            steps.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            steps.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            steps.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            none.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            none.topAnchor.constraint(equalTo: top.bottomAnchor, constant: PageStyle.barGap + 2),
            none.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Fills the row when it can, giving way to the cap on the text's width.
    private func fill(_ c: NSLayoutConstraint) -> NSLayoutConstraint { c.priority = .defaultHigh; return c }

    override func updateLayer() {
        super.updateLayer()
        noteBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        tile.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
    }
    override var wantsUpdateLayer: Bool { true }

    /// Brings the row up to date with the library. A description being typed is left alone.
    func refresh(locked: Bool) {
        guard let library = library else { return }
        if playing == nil { name.stringValue = library.library.name(of: hex, in: palette) }
        values.views.forEach { $0.removeFromSuperview() }
        var formats = Prefs.cardRows
        if !formats.contains(.hex) { formats.insert(.hex, at: 0) }
        for format in formats.prefix(4) {
            // Labels padded to one width, so the values stand in a column.
            let line = caption(format.label.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0) + format.text(hex, lowercase: Prefs.lowercaseHex))
            line.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
            values.addArrangedSubview(line)
        }
        if note.currentEditor() == nil { note.stringValue = library.library.note(of: hex, in: palette) ?? "" }
        note.isEditable = !locked
        note.toolTip = locked ? "The project is locked: unlock it to write here" : nil
        fillSteps()
        showTab()
        needsDisplay = true
    }

    private func fillSteps() {
        guard let library = library else { return }
        steps.views.forEach { $0.removeFromSuperview() }
        lines = library.history.steps(changing: hex, in: palette).map { step in
            let icon = NSImageView(image: symbol(stepSymbol(for: step.step.title), step.step.title, size: 11))
            icon.contentTintColor = .secondaryLabelColor
            icon.imageAlignment = .alignLeft
            let what = NSTextField(labelWithString: step.what)
            what.font = NSFont.systemFont(ofSize: TextSize.body)
            what.lineBreakMode = .byTruncatingTail
            what.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            what.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            let when = caption(stepStamp(step.step.date))
            when.setContentCompressionResistancePriority(.required, for: .horizontal)
            when.setContentHuggingPriority(.required, for: .horizontal)
            let row = NSStackView(views: [icon, what, when])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.distribution = .fill
            row.spacing = 8
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            steps.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: steps.widthAnchor).isActive = true
            return (row, step)
        }
        none.stringValue = library.historyEnabled ? "Nothing has happened to this colour here since history began."
            : "History is off for this library. Turn it on in Settings, under History."
        play.isEnabled = lines.count > 1
    }

    private func showTab() {
        let history = tabs.selectedSegment == 1
        noteBox.isHidden = history
        stepsScroll.isHidden = !history || lines.isEmpty
        none.isHidden = !history || !lines.isEmpty
        play.isHidden = !history
    }

    @objc private func tabChanged() {
        stopPlaying()
        onTab?(tabs.selectedSegment)
        showTab()
    }

    @objc private func copyTapped() { library?.copy(hex) }

    // MARK: Description

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let library = library else { return }
        let typed = note.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != (library.library.note(of: hex, in: palette) ?? "") else { return }
        library.describe(swatch: hex, in: palette, as: typed)
    }

    /// Return ends the description; Option-Return starts a new line in it.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        return false
    }

    // MARK: Play back

    /// Walks the colour's steps, oldest first: each line lights in turn and the name shows what it
    /// was called then. Nothing in the library changes; this only shows what happened.
    @objc private func playTapped() {
        stopPlaying()
        guard lines.count > 1 else { return }
        var at = 0
        light(0)
        playing = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            at += 1
            if at < self.lines.count { self.light(at) } else { self.stopPlaying() }
        }
    }

    private func light(_ index: Int?) {
        for (i, line) in lines.enumerated() {
            let on = index == nil || i == index
            for case let label as NSTextField in line.row.views.prefix(2) { label.textColor = on ? .labelColor : .tertiaryLabelColor }
            (line.row.views.first as? NSImageView)?.contentTintColor = i == index ? .controlAccentColor : .secondaryLabelColor
        }
        guard let index = index, lines.indices.contains(index) else { return }
        let entry = lines[index].step.entry
        name.stringValue = entry.map { $0.name ?? colourName(hex) } ?? colourName(hex)
        tile.alphaValue = entry == nil ? 0.25 : 1
        lines[index].row.scrollToVisible(lines[index].row.bounds)
    }

    private func stopPlaying() {
        playing?.invalidate()
        playing = nil
        light(nil)
        tile.alphaValue = 1
        if let library = library { name.stringValue = library.library.name(of: hex, in: palette) }
    }
}
