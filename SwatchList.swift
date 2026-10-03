import AppKit

// ---------- The vertical view of a project palette ----------
//
// One colour to a row: the colour itself, what it is called, and the notes written on it, as text.
// Edit opens the swatch's sheet, where the notes are written and the colour's history is read.
// Notes are kept on the palette's entry for that colour: in the library for a loose palette, and in
// the project's file too for a project's. Any palette can be seen this way.

enum SwatchListStyle {
    static let rowHeight: CGFloat = 132
    static let rowGap: CGFloat = 12
    static let tileWidth: CGFloat = 132
    static let infoWidth: CGFloat = 170
    static let gap: CGFloat = 16
    /// The sheet: its width, its inset from the page's top and bottom, and the padding inside it.
    static let sheetWidth: CGFloat = 560
    static let sheetInset: CGFloat = 16
    static let sheetPad: CGFloat = 20
    static let sheetSwatch: CGFloat = 120
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The colour's values, one to a line, labels padded so the values stand in a column.
private func valueLines(for hex: String, limit: Int) -> [NSTextField] {
    var formats = Prefs.cardRows
    if !formats.contains(.hex) { formats.insert(.hex, at: 0) }
    return formats.prefix(limit).map { format in
        let line = caption(format.label.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0) + format.text(hex, lowercase: Prefs.lowercaseHex))
        line.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        return line
    }
}

final class SwatchListView: NSView {
    private let library: LibraryController
    private let scroll = LetGoScrollView()
    private let stack = NSStackView()
    private var rows: [SwatchRow] = []
    private var palette: UUID?
    /// Opens a colour's sheet: the colour, and whether on Notes (0) or History (1).
    var onOpen: ((String, Int) -> Void)?

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

    /// Shows the colours in order. The same colours as before are refreshed where they stand.
    func show(_ hexes: [String], in palette: UUID, locked: Bool) {
        if palette == self.palette, rows.map({ $0.hex }) == hexes {
            rows.forEach { $0.refresh(locked: locked) }
            return
        }
        self.palette = palette
        rows.forEach { $0.removeFromSuperview() }
        rows = hexes.map { hex in
            let row = SwatchRow(hex: hex, palette: palette, library: library)
            row.onOpen = { [weak self] tab in self?.onOpen?(hex, tab) }
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

/// One colour: its tile, its name and values, then its notes as text, with Edit and History.
final class SwatchRow: NSView {
    let hex: String
    private let palette: UUID
    private weak var library: LibraryController?
    var onOpen: ((Int) -> Void)?

    private let tile = NSView()
    private let name = NSTextField(labelWithString: "")
    private let values = NSStackView()
    private lazy var edit = toolButton("Edit Notes", "pencil", "Write Notes On This Colour", target: self, action: #selector(editTapped))
    private lazy var channels = toolButton("Channels", "dial.medium", "See This Colour's Value And Fidelity In Each Channel Of The Palette's Profile", target: self, action: #selector(channelsTapped))
    private lazy var history = toolButton("History", "clock.arrow.circlepath", "See What Happened To This Colour In This Palette", target: self, action: #selector(historyTapped))
    private let note = NSTextField(wrappingLabelWithString: "")

    init(hex: String, palette: UUID, library: LibraryController) {
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

        let bar = NSStackView(views: [edit, channels, history])
        bar.orientation = .horizontal
        bar.spacing = PageStyle.barSpacing

        note.font = NSFont.systemFont(ofSize: TextSize.body)
        note.maximumNumberOfLines = 5
        note.lineBreakMode = .byTruncatingTail
        note.cell?.truncatesLastVisibleLine = true
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The text is the way in too: a double-click on it opens the sheet.
        let twice = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        twice.numberOfClicksRequired = 2
        note.addGestureRecognizer(twice)

        for v in [tile, info, bar, note] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
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
            bar.leadingAnchor.constraint(equalTo: info.trailingAnchor, constant: s.gap),
            bar.topAnchor.constraint(equalTo: topAnchor),
            note.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: trailingAnchor),
            note.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: PageStyle.barGap),
            note.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        super.updateLayer()
        tile.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
    }
    override var wantsUpdateLayer: Bool { true }

    func refresh(locked: Bool) {
        guard let library = library else { return }
        name.stringValue = library.library.name(of: hex, in: palette)
        values.views.forEach { $0.removeFromSuperview() }
        valueLines(for: hex, limit: 4).forEach { values.addArrangedSubview($0) }
        let text = library.library.note(of: hex, in: palette)
        note.stringValue = text ?? "No Notes Yet."
        note.textColor = text == nil ? .tertiaryLabelColor : .labelColor
        edit.title = locked ? "View Notes" : "Edit Notes"
        edit.invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    @objc private func copyTapped() { library?.copy(hex) }
    @objc private func editTapped() { onOpen?(0) }
    @objc private func channelsTapped() { onOpen?(1) }
    @objc private func historyTapped() { onOpen?(2) }
}

// ---------- The swatch's sheet ----------
//
// A tall panel locked to the dead centre of the page, above everything in the window, the side
// panes included: if they have been dragged so wide that the page has no room, the sheet lies over
// them. Top to bottom: the colour's name, the colour, a bar that switches between Notes and
// History, then one or the other. Done keeps the notes; Cancel, Escape, leaves them as they were.

final class SwatchSheet: NSView, NSTextViewDelegate {
    private let hex: String
    private let palette: UUID
    private weak var library: LibraryController?
    private let locked: Bool
    var onClose: (() -> Void)?

    private let panel = SheetPanel()
    private let name = NSTextField(labelWithString: "")
    private let swatch = NSView()
    private let tabs = ToggleBar(labels: ["Notes", "Channels", "History"])
    private let proofs = NSStackView()
    private let proofsScroll = LetGoScrollView()
    private lazy var play = toolButton("Play Back", "play.fill", "Walk Through What Happened To This Colour, Oldest First", target: self, action: #selector(playTapped))
    private lazy var done = toolButton("Done", "checkmark", "Keep The Notes And Close (\u{2318}Return)", target: self, action: #selector(doneTapped))
    private lazy var cancel = toolButton("Cancel", "xmark", "Close Without Keeping Changes (Escape)", target: self, action: #selector(cancelTapped))
    private let text = NSTextView()
    private let textScroll = NSScrollView()
    private let textBox = NSView()
    private let steps = NSStackView()
    private let stepsScroll = LetGoScrollView()
    private let none = caption("", size: TextSize.body)
    private let lockNote = caption("")
    private var lines: [(row: NSStackView, step: SwatchStep)] = []
    private var playing: Timer?

    init(hex: String, palette: UUID, library: LibraryController, tab: Int, locked: Bool) {
        self.hex = hex
        self.palette = palette
        self.library = library
        self.locked = locked
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.shadow = { let s = NSShadow(); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -8); s.shadowColor = NSColor.black.withAlphaComponent(0.45); return s }()

        name.font = PageStyle.titleFont
        name.lineBreakMode = .byTruncatingTail
        name.stringValue = library.library.name(of: hex, in: palette)

        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = colorFromHex(hex)?.cgColor
        swatch.layer?.cornerRadius = 10
        swatch.layer?.cornerCurve = .continuous
        swatch.layer?.borderWidth = 1
        let values = NSStackView(views: valueLines(for: hex, limit: 9))
        values.orientation = .vertical
        values.alignment = .leading
        values.spacing = 2

        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.selectedSegment = tab
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let bar = NSStackView(views: [tabs, spacer, play])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = PageStyle.barSpacing

        text.isRichText = false
        text.font = NSFont.systemFont(ofSize: TextSize.body)
        text.textColor = .labelColor
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 8, height: 10)
        text.isEditable = !locked
        text.allowsUndo = true
        text.delegate = self
        text.string = library.library.note(of: hex, in: palette) ?? ""
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        textScroll.documentView = text
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.drawsBackground = false
        textBox.wantsLayer = true
        textBox.layer?.cornerRadius = 8
        textBox.layer?.cornerCurve = .continuous
        textBox.addSubview(textScroll)

        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 6
        let page = FlippedView()
        page.addSubview(steps)
        stepsScroll.documentView = page
        stepsScroll.hasVerticalScroller = true
        stepsScroll.autohidesScrollers = true
        stepsScroll.drawsBackground = false

        proofs.orientation = .vertical
        proofs.alignment = .leading
        proofs.spacing = 14
        let proofPage = FlippedView()
        proofPage.addSubview(proofs)
        proofsScroll.documentView = proofPage
        proofsScroll.hasVerticalScroller = true
        proofsScroll.autohidesScrollers = true
        proofsScroll.drawsBackground = false
        for v in [proofs, proofPage] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            proofPage.topAnchor.constraint(equalTo: proofsScroll.contentView.topAnchor),
            proofPage.leadingAnchor.constraint(equalTo: proofsScroll.contentView.leadingAnchor),
            proofPage.trailingAnchor.constraint(equalTo: proofsScroll.contentView.trailingAnchor),
            proofs.topAnchor.constraint(equalTo: proofPage.topAnchor, constant: 2),
            proofs.leadingAnchor.constraint(equalTo: proofPage.leadingAnchor),
            proofs.trailingAnchor.constraint(equalTo: proofPage.trailingAnchor),
            proofs.bottomAnchor.constraint(equalTo: proofPage.bottomAnchor),
        ])

        lockNote.stringValue = locked ? "The project is locked. Unlock it to change these notes." : "Return starts a new line. \u{2318}Return keeps the notes."
        let lockSpacer = NSView()
        lockSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        lockNote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let foot = NSStackView(views: [lockNote, lockSpacer, cancel, done])
        foot.orientation = .horizontal
        foot.alignment = .centerY
        foot.spacing = PageStyle.barSpacing

        addSubview(panel)
        let parts: [NSView] = [name, swatch, values, bar, textBox, proofsScroll, stepsScroll, none, foot]
        for v in parts + [panel, textScroll, steps, page] { v.translatesAutoresizingMaskIntoConstraints = false }
        parts.forEach { panel.addSubview($0) }
        let s = SwatchListStyle.self, pad = s.sheetPad
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: s.sheetWidth),
            name.topAnchor.constraint(equalTo: panel.topAnchor, constant: pad),
            name.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: pad),
            name.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -pad),
            swatch.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 12),
            swatch.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            swatch.heightAnchor.constraint(equalToConstant: s.sheetSwatch),
            swatch.trailingAnchor.constraint(equalTo: values.leadingAnchor, constant: -s.gap),
            values.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            values.topAnchor.constraint(equalTo: swatch.topAnchor, constant: 2),
            values.widthAnchor.constraint(equalToConstant: s.infoWidth),
            bar.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: 16),
            bar.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            foot.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            foot.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            foot.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -pad),
            foot.heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            none.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            none.trailingAnchor.constraint(lessThanOrEqualTo: name.trailingAnchor),
            none.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: PageStyle.barGap + 2),
            textScroll.topAnchor.constraint(equalTo: textBox.topAnchor),
            textScroll.leadingAnchor.constraint(equalTo: textBox.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: textBox.trailingAnchor),
            textScroll.bottomAnchor.constraint(equalTo: textBox.bottomAnchor),
            page.topAnchor.constraint(equalTo: stepsScroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: stepsScroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: stepsScroll.contentView.trailingAnchor),
            steps.topAnchor.constraint(equalTo: page.topAnchor, constant: 2),
            steps.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            steps.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            steps.bottomAnchor.constraint(equalTo: page.bottomAnchor),
        ])
        for box in [textBox, proofsScroll, stepsScroll] as [NSView] {
            NSLayoutConstraint.activate([
                box.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                box.trailingAnchor.constraint(equalTo: name.trailingAnchor),
                box.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: PageStyle.barGap),
                box.bottomAnchor.constraint(equalTo: foot.topAnchor, constant: -16),
            ])
        }
        fillSteps()
        fillProofs()
        showTab()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The colour in every channel of the palette's profile: the value to use, how far it sits
    /// from the master, and whether the channel can show it at all.
    private func fillProofs() {
        guard let library = library, let definition = library.library.definition(of: hex) else { return }
        proofs.views.forEach { $0.removeFromSuperview() }
        let using = library.profile(forPalette: palette)
        let from = using.origin == .palette ? "This Palette's Own" : using.origin == .project ? "From The Project" : "The House Profile"
        func fact(_ label: String, _ value: String) -> NSView {
            let l = caption(label.uppercased().padding(toLength: 9, withPad: " ", startingAt: 0) + value)
            l.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
            l.isSelectable = true
            return l
        }
        let facts = NSStackView(views: [fact("Source", definition.sourceText), fact("Master", definition.masterText),
                                        fact("Kind", definition.kind == .surface ? "Surface: ink or paint, seen by the light that falls on it" : "Light: emitted, with a brightness of its own"),
                                        fact("Profile", "\(using.profile.name)  (\(from))")])
        facts.orientation = .vertical
        facts.alignment = .leading
        facts.spacing = 2
        proofs.addArrangedSubview(facts)
        // A screen can only show what it can show: when the colour is beyond it, the chips are the nearest it has and the numbers are the truth.
        if !definition.master.shows(on: window?.screen ?? NSScreen.main) {
            let beyond = caption("Beyond This Screen: The Chips Show The Nearest It Can. Trust The Numbers.")
            beyond.textColor = .systemOrange
            proofs.addArrangedSubview(beyond)
        }
        if using.profile.channels.isEmpty {
            proofs.addArrangedSubview(caption("This profile has no channels. Add some in Settings, under Colour.", size: TextSize.body))
        }
        for channel in using.profile.channels {
            let row = proofRow(Rendering.of(definition, in: channel), master: definition.master)
            proofs.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: proofs.widthAnchor).isActive = true
        }
    }

    /// One channel: the master beside what the channel gives, its name, the value, and the verdict.
    private func proofRow(_ r: Rendering, master: XYZ) -> NSView {
        func chip(_ colour: NSColor?, _ tip: String) -> NSView {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = (colour ?? .clear).cgColor
            v.layer?.borderWidth = 0.5
            v.layer?.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
            v.toolTip = tip
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 26).isActive = true
            v.heightAnchor.constraint(equalToConstant: 34).isActive = true
            return v
        }
        // The master and the channel's colour side by side, touching, so a shift shows as an edge between them.
        let pair = NSStackView(views: [chip(master.display, "The Master, As Near As This Screen Can Show It"), chip(r.shown?.display, "What This Channel Gives")])
        pair.spacing = 0
        let title = NSTextField(labelWithString: r.channel.name)
        title.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let detail = caption(r.detail)
        detail.lineBreakMode = .byTruncatingTail
        let names = NSStackView(views: [title, detail])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 1
        // The names take the spare width, so every row's name starts on one left edge beside its chips.
        names.setHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        names.setClippingResistancePriority(.defaultLow, for: .horizontal)
        let value = NSTextField(labelWithString: r.value ?? "No Value")
        value.font = NSFont.monospacedSystemFont(ofSize: TextSize.body, weight: .regular)
        value.textColor = r.value == nil ? .tertiaryLabelColor : .labelColor
        value.alignment = .right
        value.isSelectable = true
        let verdict = caption(r.difference.map { String(format: "\u{0394}E %.1f", $0) + (r.inRange ? "  \u{00B7}  In Range" : "  \u{00B7}  Out Of Range") } ?? "Not Worked Out")
        verdict.alignment = .right
        verdict.textColor = r.inRange ? .secondaryLabelColor : .systemOrange
        let figures = NSStackView(views: [value, verdict])
        figures.orientation = .vertical
        figures.alignment = .trailing
        figures.spacing = 1
        figures.setHuggingPriority(.required, for: .horizontal)
        figures.setClippingResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [pair, names, figures])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Lays the sheet over the whole window and centres its panel on `page`, the full height of it.
    func present(over page: NSView) {
        guard let root = page.window?.contentView else { return }
        root.addSubview(self, positioned: .above, relativeTo: nil)
        let centre = panel.centerXAnchor.constraint(equalTo: page.centerXAnchor)
        centre.priority = .defaultHigh   // dead centre of the page, unless that would leave the window
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: root.topAnchor),
            bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trailingAnchor.constraint(equalTo: root.trailingAnchor),
            centre,
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 8),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
            panel.topAnchor.constraint(equalTo: page.safeAreaLayoutGuide.topAnchor, constant: SwatchListStyle.sheetInset),
            panel.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -SwatchListStyle.sheetInset),
        ])
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
        window?.makeFirstResponder(tabs.selectedSegment == 0 && !locked ? text : self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        panel.layer?.backgroundColor = Theme.grey(0.05).cgColor
        panel.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
        swatch.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        textBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
    }
    override var wantsUpdateLayer: Bool { true }

    // MARK: Closing

    private var changed: Bool { text.string.trimmingCharacters(in: .whitespacesAndNewlines) != (library?.library.note(of: hex, in: palette) ?? "") }

    private func close(keeping: Bool) {
        stopPlaying()
        if keeping, !locked, changed { library?.describe(swatch: hex, in: palette, as: text.string) }
        removeFromSuperview()
        onClose?()
    }

    /// Keeps what was typed and closes: for when the page is about to go elsewhere.
    func finish() { close(keeping: true) }

    @objc private func doneTapped() { close(keeping: true) }
    @objc private func cancelTapped() { close(keeping: false) }
    override func cancelOperation(_ sender: Any?) { close(keeping: false) }

    /// A click outside the panel is Done: what was typed is kept, never thrown away by a stray click.
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { close(keeping: true) }
    }
    // Nothing behind the sheet is reachable while it is up.
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 || event.keyCode == 76 { close(keeping: true); return true }
        return super.performKeyEquivalent(with: event)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(keeping: false); return true }
        return false
    }

    // MARK: Notes and history

    @objc private func tabChanged() {
        stopPlaying()
        showTab()
        if tabs.selectedSegment == 0, !locked { window?.makeFirstResponder(text) }
    }

    private func showTab() {
        let notes = tabs.selectedSegment == 0, history = tabs.selectedSegment == 2
        textBox.isHidden = !notes
        proofsScroll.isHidden = tabs.selectedSegment != 1
        stepsScroll.isHidden = !history || lines.isEmpty
        none.isHidden = !history || !lines.isEmpty
        play.isHidden = !history
        lockNote.isHidden = !notes
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
            (line.row.views.first as? NSImageView)?.contentTintColor = i == index ? .labelColor : .secondaryLabelColor
        }
        guard let index = index, lines.indices.contains(index) else { return }
        let entry = lines[index].step.entry
        name.stringValue = entry.map { $0.name ?? colourName(hex) } ?? colourName(hex)
        swatch.alphaValue = entry == nil ? 0.25 : 1
        lines[index].row.scrollToVisible(lines[index].row.bounds)
    }

    private func stopPlaying() {
        playing?.invalidate()
        playing = nil
        light(nil)
        swatch.alphaValue = 1
        if let library = library { name.stringValue = library.library.name(of: hex, in: palette) }
    }
}

/// The sheet's panel: clicks on it stay on it.
private final class SheetPanel: NSView {
    override func mouseDown(with event: NSEvent) {}
}
