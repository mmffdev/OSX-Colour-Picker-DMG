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
    static let infoWidth: CGFloat = 228   // a grid card's narrowest, so the same rows fit
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
private func valueLines(for hex: String, limit: Int, alwaysHex: Bool = true) -> [NSTextField] {
    var formats = Prefs.cardRows
    if alwaysHex, !formats.contains(.hex) { formats.insert(.hex, at: 0) }
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
    private var titles: [NSView] = []
    private var shownGroups: [PaletteGroup] = []
    private var palette: UUID?
    /// Opens a colour's sheet: the colour, and whether on Notes (0) or History (1).
    var onOpen: ((String, Int) -> Void)?
    /// A blank swatch was pressed: the page's one, or a group's own, which says what kind of colour to start.
    var onAdd: ((NewColourStart?) -> Void)?
    private var addRows: [NSView] = []
    private var shownOffer = false

    /// A row holding one blank swatch, the size of the swatch tiles above it.
    private func addRow(_ start: NewColourStart?) -> NSView {
        let row = NSView(), tile = AddSwatchTile(radius: 10)
        tile.onPress = { [weak self] in self?.onAdd?(start) }
        for v in [row, tile] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        row.addSubview(tile)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: SwatchListStyle.rowHeight),
            tile.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            tile.topAnchor.constraint(equalTo: row.topAnchor),
            tile.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            tile.widthAnchor.constraint(equalToConstant: SwatchListStyle.tileWidth),
        ])
        return row
    }

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
            stack.topAnchor.constraint(equalTo: page.topAnchor),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: PageStyle.side),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -PageStyle.side),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -24),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the colours in order. The same colours as before are refreshed where they stand.
    func show(_ hexes: [String], in palette: UUID, locked: Bool, offersNew: Bool = false, groups: [PaletteGroup] = [], panels: RowPanels = RowPanels()) {
        // What the bar above has switched on is shown on every swatch at once.
        defer { rows.forEach { $0.show(panels, among: hexes) } }
        if palette == self.palette, rows.map({ $0.hex }) == hexes, groups == shownGroups, offersNew == shownOffer, !stack.arrangedSubviews.isEmpty || !offersNew {
            rows.forEach { $0.refresh(locked: locked) }
            return
        }
        self.palette = palette
        shownGroups = groups
        shownOffer = offersNew
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        titles = []
        addRows = []
        let made = Dictionary(uniqueKeysWithValues: hexes.map { hex -> (String, SwatchRow) in
            let row = SwatchRow(hex: hex, palette: palette, library: library)
            row.onOpen = { [weak self] tab in self?.onOpen?(hex, tab) }
            return (hex, row)
        })
        rows = hexes.compactMap { made[$0] }
        // The same page the grid lays out: the colours group by group, with the blank swatches where they fall.
        let page = PaletteSlot.page(hexes, groups: groups, offersNew: offersNew)
        var starts: [Int: PaletteGroup] = [:]
        var at = 0
        for (group, count) in zip(groups, page.counts) { starts[at] = group; at += count }
        for (i, slot) in page.slots.enumerated() {
            if let group = starts[i] {
                let title = NSTextField(labelWithString: GroupHeaderView.text(group))
                title.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
                title.textColor = .secondaryLabelColor
                if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(SwatchListStyle.rowGap + 10, after: last) }
                stack.addArrangedSubview(title)
                titles.append(title)
            }
            let row: NSView
            switch slot {
            case .colour(let hex):
                guard let made = made[hex] else { continue }
                made.refresh(locked: locked)
                row = made
            case .add(let start):
                row = addRow(start)
                addRows.append(row)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// What the bar above the swatches has switched on for every one of them.
struct RowPanels: Equatable {
    var channels = false
    var notes = true
    var history = false
    var histogram = false
    var type = HistogramType.rgb
    var split = false

    static var chosen: RowPanels {
        RowPanels(channels: Prefs.paletteChannels, notes: Prefs.paletteNotes, history: Prefs.paletteHistory, histogram: Prefs.histograms, type: Prefs.histogramType, split: Prefs.histogramSplit)
    }
}

/// One colour: its tile, its name and values, then four slots side by side, each switched on or
/// off for every swatch from the bar above: Histogram, Channels, Notes, History. The slots that
/// are on share the row's width equally. The row has no buttons of its own: pressing the notes,
/// or the colour's name, opens its sheet.
final class SwatchRow: NSView {
    static let panelWidth: CGFloat = 460
    let hex: String
    private let palette: UUID
    private weak var library: LibraryController?
    var onOpen: ((Int) -> Void)?

    private let histogramPanel = HistogramPanel()
    private let channelsPanel = NSStackView()
    private let historyPanel = NSStackView()
    private let histogramSlot = NSStackView()
    private let notesSlot = NSStackView()
    private var slotsWidth: NSLayoutConstraint!
    static let slotGap: CGFloat = 28
    /// History is a narrow column, like the rail it copies; the other slots share what is left.
    static let historyWidth: CGFloat = 300
    private var shown: RowPanels?
    private var shownAmong: [String] = []

    private let tile = NSView()
    private let name = NSTextField(labelWithString: "")
    private let values = NSStackView()
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

        name.font = NSFont.systemFont(ofSize: 15, weight: .semibold)   // as on a grid card
        name.lineBreakMode = .byTruncatingTail
        values.orientation = .vertical
        values.alignment = .leading
        values.spacing = 0
        // The values are a column like the others, under a heading of their own.
        let info = NSStackView(views: [heading("Meta"), name, values])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 4
        info.setCustomSpacing(6, after: info.views[0])
        values.widthAnchor.constraint(equalTo: info.widthAnchor).isActive = true

        note.font = NSFont.systemFont(ofSize: TextSize.body)
        note.maximumNumberOfLines = 5
        note.lineBreakMode = .byTruncatingTail
        note.cell?.truncatesLastVisibleLine = true
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The text is the way in: a press on it opens the colour's sheet, on its notes.
        note.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(editTapped)))

        // The name is a way in too, for when the notes are switched off.
        name.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(editTapped)))
        name.toolTip = "Click For This Colour's Notes, Channels And History"

        histogramSlot.setViews([heading("Histogram"), histogramPanel], in: .top)
        notesSlot.setViews([heading("Notes"), note], in: .top)
        for slot in [histogramSlot, channelsPanel, notesSlot, historyPanel] {
            slot.orientation = .vertical
            slot.alignment = .leading
            slot.spacing = 6
            slot.isHidden = true
            slot.translatesAutoresizingMaskIntoConstraints = false
        }
        historyPanel.spacing = 3
        histogramPanel.widthAnchor.constraint(equalTo: histogramSlot.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: notesSlot.widthAnchor).isActive = true
        // Beside the values: the four slots in a row, sharing the width between those that are on.
        // The row grows to the tallest of them and the swatches below move down; the tile keeps its size.
        let body = NSStackView(views: [histogramSlot, channelsPanel, notesSlot, historyPanel])
        body.orientation = .horizontal
        body.alignment = .top
        body.distribution = .fill
        historyPanel.widthAnchor.constraint(equalToConstant: SwatchRow.historyWidth).isActive = true
        for (one, other) in [(histogramSlot, channelsPanel), (channelsPanel, notesSlot), (histogramSlot, notesSlot)] {
            let same = one.widthAnchor.constraint(equalTo: other.widthAnchor)
            same.priority = NSLayoutConstraint.Priority(999)
            same.isActive = true
        }
        body.spacing = SwatchRow.slotGap
        // As wide as its slots want, up to the row's edge.
        slotsWidth = body.widthAnchor.constraint(equalToConstant: SwatchRow.panelWidth)
        slotsWidth.priority = .defaultHigh
        for v in [tile, info, body] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let s = SwatchListStyle.self
        let least = heightAnchor.constraint(equalToConstant: s.rowHeight)
        least.priority = .defaultLow
        NSLayoutConstraint.activate([
            least,
            heightAnchor.constraint(greaterThanOrEqualToConstant: s.rowHeight),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor),
            tile.topAnchor.constraint(equalTo: topAnchor),
            tile.heightAnchor.constraint(equalToConstant: s.rowHeight),
            tile.widthAnchor.constraint(equalToConstant: s.tileWidth),
            info.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: s.gap),
            info.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            info.widthAnchor.constraint(equalToConstant: s.infoWidth),
            info.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),   // a long list of values makes the row taller
            body.leadingAnchor.constraint(equalTo: info.trailingAnchor, constant: s.gap),
            body.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            slotsWidth,
            body.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            body.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
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
        // The very rows a grid card has: each value ticked under Labels, in columns, with its copy mark;
        // then the contrast when WCAG is on.
        name.isHidden = !Prefs.showNames
        for format in Prefs.cardRows {
            let row = FormatRow(frame: .zero)
            row.configure(format, hex: hex, ink: .labelColor)
            row.onCopy = { [weak self] in if let self = self { self.library?.copy(self.hex, as: format) } }
            row.translatesAutoresizingMaskIntoConstraints = false
            values.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: ColourCard.rowHeight),
                row.widthAnchor.constraint(equalTo: values.widthAnchor),
            ])
        }
        if Prefs.showContrast {
            let white = contrastRatio(hex, "#FFFFFF"), black = contrastRatio(hex, "#000000")
            let title = NSTextField(labelWithString: "WCAG Text Contrast")
            title.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            title.textColor = NSColor.labelColor.withAlphaComponent(0.62)
            let grade = NSTextField(labelWithString: String(format: "White %.1f %@  \u{00B7}  Black %.1f %@", white, contrastGrade(white), black, contrastGrade(black)))
            grade.font = NSFont.systemFont(ofSize: TextSize.caption, weight: .medium)
            grade.textColor = .secondaryLabelColor
            grade.lineBreakMode = .byTruncatingTail
            grade.toolTip = "Contrast ratio of white and of black text on this colour, with its WCAG grade"
            if let last = values.views.last { values.setCustomSpacing(8, after: last) }
            values.addArrangedSubview(title)
            values.setCustomSpacing(2, after: title)
            values.addArrangedSubview(grade)
        }
        values.isHidden = values.views.isEmpty
        let text = library.library.note(of: hex, in: palette)
        note.stringValue = text ?? (locked ? "No Notes." : "No Notes Yet. Click To Write Some.")
        note.textColor = text == nil ? .tertiaryLabelColor : .labelColor
        note.toolTip = locked ? "Click To Read This Colour's Notes, Channels And History" : "Click To Write Notes On This Colour, And See Its Channels And History"
        shown = nil   // what the panels say may have changed with the library
        needsDisplay = true
    }

    /// Shows what the bar above has switched on. `among` is the page's colours, drawn faintly behind the histogram.
    func show(_ panels: RowPanels, among population: [String]) {
        guard panels != shown || population != shownAmong else { return }
        shown = panels
        shownAmong = population
        histogramSlot.isHidden = !panels.histogram
        notesSlot.isHidden = !panels.notes
        let wide = CGFloat([panels.histogram, panels.channels, panels.notes].filter { $0 }.count), on = wide + (panels.history ? 1 : 0)
        slotsWidth.constant = wide * SwatchRow.panelWidth + (panels.history ? SwatchRow.historyWidth : 0) + max(0, on - 1) * SwatchRow.slotGap
        if panels.histogram { histogramPanel.show(hex, among: population, type: panels.type, split: panels.split) }
        channelsPanel.isHidden = !panels.channels
        if panels.channels { fillChannels() }
        historyPanel.isHidden = !panels.history
        if panels.history { fillHistory() }
    }

    /// A column's heading: the sidebar's bucket headings exactly, bold and in the full text colour.
    private func heading(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = SidebarOutlineView.headingFont
        l.textColor = .labelColor
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    /// Every channel of the palette's profile: the master beside what the channel gives, the value and the verdict.
    private func fillChannels() {
        channelsPanel.views.forEach { $0.removeFromSuperview() }
        guard let library = library, let definition = library.library.definition(of: hex) else { return }
        let profile = library.profile(forPalette: palette).profile
        channelsPanel.addArrangedSubview(heading("Channels  \u{00B7}  \(profile.name)"))
        if profile.channels.isEmpty { channelsPanel.addArrangedSubview(caption("This Profile Has No Channels. Add Some In Settings, Under Colour.")) }
        for channel in profile.channels {
            let row = SwatchSheet.proofRow(Rendering.of(definition, in: channel), master: definition.master)
            channelsPanel.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: channelsPanel.widthAnchor).isActive = true
        }
    }

    /// What happened to the colour in this palette, newest first; the sheet has the whole of a long history.
    private func fillHistory() {
        historyPanel.views.forEach { $0.removeFromSuperview() }
        guard let library = library else { return }
        historyPanel.addArrangedSubview(heading("History"))
        let steps = library.history.steps(changing: hex, in: palette)
        if steps.isEmpty {
            historyPanel.addArrangedSubview(caption(library.historyEnabled ? "Nothing Has Happened To This Colour Here Since History Began." : "History Is Off For This Library."))
        }
        // The History rail's own rows: the step's symbol, its title and time, this colour's swatch and what the step did to it.
        let limit = 6
        for step in steps.reversed().prefix(limit) {
            let cell = StepCell()
            cell.inRail = false
            cell.show(step.step, colour: hex, what: step.what)
            cell.translatesAutoresizingMaskIntoConstraints = false
            historyPanel.addArrangedSubview(cell)
            cell.heightAnchor.constraint(equalToConstant: StepCell.height).isActive = true
            cell.widthAnchor.constraint(equalTo: historyPanel.widthAnchor).isActive = true
        }
        if steps.count > limit { historyPanel.addArrangedSubview(caption("And \(steps.count - limit) Earlier. Click The Notes For All Of It.")) }
    }

    @objc private func copyTapped() { library?.copy(hex) }
    @objc private func editTapped() { onOpen?(0) }
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
            let row = SwatchSheet.proofRow(Rendering.of(definition, in: channel), master: definition.master)
            proofs.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: proofs.widthAnchor).isActive = true
        }
    }

    /// One channel: the master beside what the channel gives, its name, the value, and the verdict.
    static func proofRow(_ r: Rendering, master: XYZ) -> NSView {
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
