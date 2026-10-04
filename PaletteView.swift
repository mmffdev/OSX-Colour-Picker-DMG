import AppKit

// ---------- A palette: one card per swatch ----------

/// One line of a card: label, values, copy mark. Click copies that line.
final class FormatRow: NSView {
    var onCopy: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let values = NSStackView()
    private let icon = NSImageView()
    private var hovering = false { didSet { needsDisplay = true } }
    private var ink = NSColor.white

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        values.orientation = .horizontal
        values.spacing = 0
        values.distribution = .fillEqually
        icon.image = symbol("doc.on.doc", "Copy", size: 11)

        for v in [label, values, icon] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 46),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            values.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            values.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -8),
            values.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ format: ColourFormat, hex: String, ink: NSColor) {
        self.ink = ink
        label.stringValue = format.label
        label.textColor = ink.withAlphaComponent(0.62)
        icon.contentTintColor = ink.withAlphaComponent(0.7)
        toolTip = "Copy \(format.label)  \(format.text(hex, lowercase: Prefs.lowercaseHex))" + (format == .cmyk ? "\nThe build for \(PrintCondition.name())" : "")
        setAccessibilityLabel(toolTip)

        values.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for field in format.fields(hex, lowercase: Prefs.lowercaseHex) {
            let t = NSTextField(labelWithString: field)
            t.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            t.textColor = ink
            t.alignment = .right
            values.addArrangedSubview(t)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        ink.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: -4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {} // keep the click from selecting the card
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onCopy?() }
    }
}

/// Every colour of a palette side by side in one strip, each the same width, with no gaps.
final class SpectrumView: NSView {
    var hexes: [String] = [] { didSet { needsDisplay = true } }
    var radius: CGFloat = 12
    /// Draws an outline when there are no colours, so a row of strips stays even.
    var outlinesWhenEmpty = false

    override func draw(_ dirtyRect: NSRect) {
        if hexes.isEmpty, outlinesWhenEmpty {
            NSColor.tertiaryLabelColor.setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius).stroke()
        }
        guard !hexes.isEmpty else { return }
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        let each = bounds.width / CGFloat(hexes.count)
        for (at, hex) in hexes.enumerated() {
            // Whole-point edges, so neighbours meet exactly.
            let left = (CGFloat(at) * each).rounded(), right = at == hexes.count - 1 ? bounds.width : (CGFloat(at + 1) * each).rounded()
            (colorFromHex(hex) ?? .clear).setFill()
            NSRect(x: left, y: 0, width: right - left, height: bounds.height).fill()
        }
    }
}

/// A swatch in a palette's grid: the colour as a plain block, and under it, on the page, its name
/// and its values, as All Swatches lays its tiles out. Nothing is written over the colour except
/// the source of a colour that is not a plain sRGB value, and the button for its actions.
/// The contrast of white and of black text on a colour: a heading in the columns' own style, then
/// a row each with the number at reading size and the verdict in a coloured tag, green for a
/// pass, amber for large text only, red for a fail.
final class ContrastReadout: NSView {
    static let rowHeight: CGFloat = 22
    static let height: CGFloat = 18 + 2 * rowHeight

    private let title = NSTextField(labelWithString: "")
    private var names: [NSTextField] = [], values: [NSTextField] = [], tags: [GradeTag] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = SidebarOutlineView.headingFont
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            title.topAnchor.constraint(equalTo: topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: ContrastReadout.height),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ]
        for at in 0..<2 {
            let name = NSTextField(labelWithString: ""), value = NSTextField(labelWithString: ""), tag = GradeTag()
            name.font = NSFont.systemFont(ofSize: TextSize.body)
            name.textColor = .secondaryLabelColor
            value.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.body, weight: .semibold)
            value.textColor = .labelColor
            let middle = 18 + ContrastReadout.rowHeight * (CGFloat(at) + 0.5)
            for v in [name, value, tag] as [NSView] {
                v.translatesAutoresizingMaskIntoConstraints = false
                addSubview(v)
                constraints.append(v.centerYAnchor.constraint(equalTo: topAnchor, constant: middle))
            }
            constraints += [
                name.leadingAnchor.constraint(equalTo: leadingAnchor),
                value.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 50),
                tag.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 104),
            ]
            names.append(name); values.append(value); tags.append(tag)
        }
        NSLayoutConstraint.activate(constraints)
        toolTip = "The contrast of white and of black text on this colour"
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ hex: String) {
        let contrast = Prefs.contrast(for: hex)
        title.stringValue = contrast.title
        for (at, row) in contrast.rows.prefix(2).enumerated() {
            names[at].stringValue = row.name
            values[at].stringValue = row.value
            tags[at].show(row.grade, row.verdict)
        }
    }
}

/// A verdict in a small coloured tag.
final class GradeTag: NSView {
    private var text = "", verdict = Prefs.ContrastVerdict.fail
    private var colour: NSColor { verdict == .pass ? .systemGreen : verdict == .partial ? .systemOrange : .systemRed }
    private var string: NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: TextSize.caption, weight: .bold), .foregroundColor: colour])
    }

    func show(_ text: String, _ verdict: Prefs.ContrastVerdict) {
        self.text = text
        self.verdict = verdict
        invalidateIntrinsicContentSize()
        needsDisplay = true
        setAccessibilityLabel(text)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: ceil(string.size().width) + 14, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        colour.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        let size = string.size()
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

final class ColourCard: NSCollectionViewItem, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("card")
    /// The narrowest a card gets; they widen to fill the row.
    static let width: CGFloat = 228
    static let chipHeight: CGFloat = 112
    static let rowHeight: CGFloat = 22

    /// Height for the rows and extras switched on in Settings.
    static var height: CGFloat {
        chipHeight + 8 + (Prefs.showNames ? 24 : 0) + CGFloat(Prefs.cardRows.count) * rowHeight + (Prefs.showContrast ? 8 + ContrastReadout.height : 0) + 4
    }

    var onCopyRow: ((ColourFormat) -> Void)?
    /// The halo button was pressed; hands over the button so the halo knows its trigger.
    var onHalo: ((NSView) -> Void)?
    weak var library: LibraryController?
    private(set) var hex = ""
    /// As a press on the halo button.
    func pressHalo() { onHalo?(halo) }
    private let chip = NSView()
    private let name = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    private let contrast = ContrastReadout()
    private let halo = HaloTriggerView()
    private let below = NSStackView()

    override func loadView() {
        let v = NSView()
        view = v
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 12
        chip.layer?.cornerCurve = .continuous
        chip.layer?.borderWidth = 1

        name.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        code.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .medium)
        code.lineBreakMode = .byTruncatingTail
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading

        halo.toolTip = "Actions"
        halo.onPress = { [weak self] in
            guard let self = self else { return }
            self.onHalo?(self.halo)
        }

        // Under the colour, top to bottom: the name, the values, the contrast. Whatever is switched off leaves no gap.
        below.setViews([name, rows, contrast], in: .top)
        below.orientation = .vertical
        below.alignment = .leading
        below.spacing = 4
        below.setCustomSpacing(8, after: rows)

        for s in [chip, below] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(s)
        }
        for s in [code, halo] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(s)
        }
        NSLayoutConstraint.activate([
            chip.topAnchor.constraint(equalTo: v.topAnchor),
            chip.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            chip.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            chip.heightAnchor.constraint(equalToConstant: ColourCard.chipHeight),
            halo.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -9), // its ring sits 3 points inside its frame
            halo.topAnchor.constraint(equalTo: chip.topAnchor, constant: 9),
            halo.widthAnchor.constraint(equalToConstant: 24),
            halo.heightAnchor.constraint(equalToConstant: 24),
            code.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
            code.trailingAnchor.constraint(lessThanOrEqualTo: chip.trailingAnchor, constant: -12),
            code.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -10),
            below.topAnchor.constraint(equalTo: chip.bottomAnchor, constant: 8),
            below.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 2),
            below.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -2),
            rows.widthAnchor.constraint(equalTo: below.widthAnchor),
            name.widthAnchor.constraint(lessThanOrEqualTo: below.widthAnchor),
        ])
    }

    override var isSelected: Bool { didSet { outline() } }

    private func outline() {
        let ink = colorFromHex(readableText(on: hex)) ?? .white
        chip.layer?.borderWidth = isSelected ? 3 : 1
        chip.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : ink.withAlphaComponent(0.16)).cgColor
    }

    /// The name was edited on the card; blank asks for the standard name back.
    var onRename: ((String) -> Void)?
    private var shownName = ""

    /// Whether a click landed on the name, where a double-click starts a rename.
    func isOverName(_ event: NSEvent) -> Bool {
        name.bounds.insetBy(dx: -4, dy: -3).contains(name.convert(event.locationInWindow, from: nil))
    }

    /// Turns the name into a text box. Return keeps what is typed; Esc puts the name back.
    func beginRenaming() {
        name.stringValue = shownName
        name.isEditable = true
        name.delegate = self
        view.window?.makeFirstResponder(name)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard name.isEditable else { return }
        name.isEditable = false
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed != shownName { onRename?(typed) } else { name.stringValue = shownName }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        name.abortEditing()
        name.isEditable = false
        name.stringValue = shownName
        view.window?.makeFirstResponder(view.superview)
        return true
    }

    /// `called` is the user's own name for the colour in this palette, when it has one.
    func configure(hex: String, called: String? = nil) {
        self.hex = hex
        shownName = called ?? colourName(hex)
        let ink = colorFromHex(readableText(on: hex)) ?? .white
        chip.layer?.backgroundColor = colorFromHex(hex)?.cgColor
        outline()

        // The title is the colour's name, never its hex: the hex is one of the values below, when ticked.
        name.stringValue = shownName
        name.textColor = .labelColor
        name.isHidden = !Prefs.showNames
        halo.ink = ink
        // A colour that is not a plain sRGB value says what it is, on the colour: its P3 values, its build, its Lab.
        code.stringValue = ColourKeys.isKey(hex) ? ColourKeys.label(hex) : ""
        code.textColor = ink.withAlphaComponent(0.8)
        let tags = library?.library.colours.first { $0.hex == hex }?.tags ?? []
        view.toolTip = "Click to copy \(Prefs.copyText(hex))" + (tags.isEmpty ? "" : "\nTags: " + tags.joined(separator: ", "))

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for format in Prefs.cardRows {
            let row = FormatRow(frame: .zero)
            row.configure(format, hex: hex, ink: .labelColor)
            row.onCopy = { [weak self] in self?.onCopyRow?(format) }
            row.translatesAutoresizingMaskIntoConstraints = false
            rows.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: ColourCard.rowHeight),
                row.widthAnchor.constraint(equalTo: rows.widthAnchor),
            ])
        }

        contrast.isHidden = !Prefs.showContrast
        rows.isHidden = Prefs.cardRows.isEmpty
        if Prefs.showContrast { contrast.show(hex) }
    }
}

final class PaletteViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTokenFieldDelegate,
                                   NSMenuDelegate, NSTextFieldDelegate {
    private let library: LibraryController
    /// +1 for the next palette, -1 for the previous one.
    var onPage: ((Int) -> Void)?
    private let halo = HaloMenu(label: "Swatch", hint: "Scroll to turn, click to choose", actions: [])
    private var haloHex = ""

    private(set) var paletteID: UUID?
    private var hexes: [String] = []
    private var search = ""
    /// The titled groups the page is split into; empty when it is one run.
    private var groups: [PaletteGroup] = []
    /// The grid's items in order: the colours, and the blank swatches that add one.
    private var slots: [PaletteSlot] = []
    private var slotCounts: [Int] = []
    /// Under the spectrum: how the page is grouped and what it shows.
    // rail2 for this page: how the page is displayed, the palette as a whole, the selected swatch, labels and tags.
    let contextRail = ContextRail()
    private let displayBucket = RailBucket("Display"), paletteBucket = RailBucket("Palette"), swatchBucket = RailBucket("Swatches")
    private let labelsBucket = RailBucket("Labels"), tagsBucket = RailBucket("Tags")
    private let purposeBucket = RailBucket("Purposes")
    private var purposeRows: [RailRow] = []
    private let contrastMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let groupMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showMenu = NSPopUpButton(frame: .zero, pullsDown: false)
    private var panelRows: [RailRow] = []
    private var labelRows: [RailRow] = []
    /// Under that, while Histogram is on: the choices every swatch's histogram follows.
    private let histogramBar = HistogramBar()
    private let bars = NSStackView()
    private let paletteHeading = sectionHeading("Palette")
    private let swatchesHeading = sectionHeading("Swatches")
    /// Over the spectrum: what can be done with the palette as a whole.


    private let nameField = NSTextField(labelWithString: "")
    private lazy var header = PageHeader(title: nameField, actions: [browsing, selecting, tagBar])
    private var star: NSButton!
    private var target: NSButton!
    private var tagButton: NSButton!
    private let tagBar = TagBar()
    private var tagging = false
    /// What the swatch menus and the halo call to tag swatches: the page's own tag bar.
    private lazy var onEditTags: ([String]) -> Void = { [weak self] hexes in self?.editTags(of: hexes) }
    private let wcag = NSButton(title: "WCAG", target: nil, action: nil)
    private let labels = PopoverButton(title: "Labels")
    private var labelsPopover = NSPopover()
    private var labelChecks: [NSButton] = []
    private let addTo = NSPopUpButton(frame: .zero, pullsDown: true)
    /// The bar's right-hand side: the palette's own actions, or actions on several selected swatches.
    private let browsing = NSStackView()
    private let selecting = NSStackView()
    private var restSubtitle = ""
    private let sort = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The colour profile this palette is proofed for: its own, or the one it inherits.
    private let profile = NSPopUpButton(frame: .zero, pullsDown: false)
    private let spectrum = SpectrumView()
    private let grid = SwatchGridView()
    private let scroll = PagingScrollView()
    /// The vertical view: one colour to a row with its notes and history.
    private lazy var list = SwatchListView(library: library)
    private lazy var gridButton = symbolButton("square.grid.2x2", tooltip: "Grid View", target: self, action: #selector(showGrid))
    private lazy var listButton = symbolButton("rectangle.grid.1x2", tooltip: "Vertical View, With Descriptions And History", target: self, action: #selector(showList))
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var committedName = ""
    private let spacing: CGFloat = 16, side: CGFloat = 20

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private let layout = GridLayout()

    /// Cards stretch to fill the row. Their height follows the rows switched on in Settings.
    private func sizeCards() {
        layout.minimumWidth = ColourCard.width
        layout.spacing = spacing
        layout.margins = NSEdgeInsets(top: 0, left: side, bottom: 24, right: side)   // the bar above keeps its own space
        layout.height = { _ in ColourCard.height }
        layout.headerHeight = GroupHeaderView.height
        // The blank swatch that adds a colour sits at the end of the last group.
        layout.groupCounts = slotCounts
        layout.invalidateLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layout.fitVisibleWidth()
    }

    override func loadView() {
        view = NSView()

        nameField.isEditable = true
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.delegate = self

        wcag.setButtonType(.pushOnPushOff)
        wcag.bezelStyle = .recessed
        wcag.controlSize = .small
        wcag.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        wcag.target = self
        wcag.action = #selector(wcagTapped)
        wcag.toolTip = "Show WCAG text contrast on each card"

        labels.target = self
        labels.action = #selector(showLabels)
        labels.toolTip = "Choose which values each card shows"
        // Ticks in a popover rather than a menu, so it stays open while several are chosen.
        labelChecks = (["Name"] + ColourFormat.cardRows.map { $0.label }).map {
            NSButton(checkboxWithTitle: $0, target: self, action: #selector(labelToggled))
        }
        labelsPopover = tickPopover(labelChecks)

        addTo.controlSize = .small
        addTo.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        addTo.addItem(withTitle: "Add to Palette")
        addTo.menu?.delegate = self
        func small(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.toolTip = tip
            return b
        }
        selecting.setViews([small("Copy", #selector(copyChosen), "Copy the selected swatches"), addTo,
                            symbolButton("tag", tooltip: "Tag the selected swatches", target: self, action: #selector(tagChosen)),
                            small("Remove", #selector(removeChosen), "Take the selected swatches out of this palette"),
                            small("Deselect", #selector(deselect), "Clear the selection")], in: .leading)
        selecting.spacing = 8
        selecting.isHidden = true

        tagButton = symbolButton("tag", tooltip: "Tags for this palette", target: self, action: #selector(tagsTapped))
        star = symbolButton("star", tooltip: "Add to Favourites", target: self, action: #selector(starTapped))
        target = symbolButton("eyedropper", tooltip: "Send picks here", target: self, action: #selector(targetTapped))
        let copyAll = symbolButton("doc.on.doc", tooltip: "Copy every swatch in this palette", target: self, action: #selector(copyAllTapped))
        let newColour = symbolButton("plus", tooltip: "New Colour: Type It As Display P3, CMYK, Lab Or Hex (\u{21E7}\u{2318}K)", target: library, action: #selector(LibraryController.newColour))

        sort.addItems(withTitles: ["Order Added", "Newest First", "Colour Order"])
        sort.controlSize = .small
        sort.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        sort.target = self
        sort.action = #selector(sortChanged)

        tagBar.onClose = { [weak self] in
            self?.tagging = false
            self?.updateHeader()
            self?.view.window?.makeFirstResponder(self?.grid)
        }
        tagBar.isHidden = true

        // The shared header: the name has the top row to itself; under it, the count on the left and the actions on the right.
        profile.controlSize = .small
        profile.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        profile.target = self
        profile.action = #selector(profileChanged)
        // The contrast, the profile, the order and the labels are on rail2 now.
        browsing.setViews([newColour, tagButton, star, target, copyAll], in: .leading)
        browsing.spacing = 12

        sizeCards()
        grid.collectionViewLayout = layout
        grid.dataSource = self
        grid.delegate = self
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.register(ColourCard.self, forItemWithIdentifier: ColourCard.identifier)
        grid.register(AddCard.self, forItemWithIdentifier: AddCard.identifier)
        grid.register(GroupHeaderView.self, forSupplementaryViewOfKind: GridLayout.headerKind, withIdentifier: GroupHeaderView.identifier)
        buildRail()
        list.onSelect = { [weak self] in self?.refreshRail() }
        list.onAdd = { [weak self] start in self?.library.startColour(start) }
        // A press on a swatch selects it; it no longer copies. The copy marks, the actions button and Copy still do.
        grid.onDelete = { [weak self] in self?.removeSelected() }
        grid.onCopy = { [weak self] in self?.copySelected() }
        grid.onFavourite = { [weak self] in self?.starTapped() }
        // A double-click on a card's name renames the colour; anywhere else on the card it is two clicks.
        grid.onDoubleClick = { [weak self] ip, event in
            guard let card = self?.grid.item(at: ip) as? ColourCard, Prefs.showNames, card.isOverName(event) else { return false }
            card.beginRenaming()
            return true
        }
        let menu = NSMenu()
        menu.delegate = self
        grid.menu = menu

        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.onPage = { [weak self] d in self?.onPage?(d) }

        empty.alignment = .center
        empty.textColor = .tertiaryLabelColor
        empty.font = NSFont.systemFont(ofSize: 13)

        header.trailing.setViews([gridButton, listButton], in: .leading)
        list.onOpen = { [weak self] hex, tab in self?.openSheet(for: hex, tab: tab) }
        list.onHalo = { [weak self] hex, trigger in self?.openHalo(for: hex, from: trigger) }
        header.trailing.isHidden = true
        histogramBar.onChange = { [weak self] in self?.reload() }
        bars.setViews([histogramBar], in: .top)
        bars.orientation = .vertical
        bars.alignment = .leading
        bars.spacing = PageStyle.barGap
        histogramBar.widthAnchor.constraint(equalTo: bars.widthAnchor).isActive = true
        // The page in two parts, each under its heading: the palette as a whole, then its swatches.
        for v in [header, paletteHeading, spectrum, swatchesHeading, bars, scroll, list, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        // The header's set height, unless its bar needs a second row; never left to stretch into the page below.
        let headerHeight = header.heightAnchor.constraint(equalToConstant: PageStyle.height)
        headerHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: PageStyle.height),   // taller while the tag bar shows its second row
            headerHeight,
            paletteHeading.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            paletteHeading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            spectrum.topAnchor.constraint(equalTo: paletteHeading.bottomAnchor, constant: 10),
            spectrum.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            spectrum.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            spectrum.heightAnchor.constraint(equalToConstant: 50),
            swatchesHeading.topAnchor.constraint(equalTo: spectrum.bottomAnchor, constant: 30),
            swatchesHeading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            bars.topAnchor.constraint(equalTo: swatchesHeading.bottomAnchor, constant: 10),
            bars.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            bars.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            scroll.topAnchor.constraint(equalTo: bars.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.topAnchor.constraint(equalTo: scroll.topAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    // MARK: Contents

    func show(_ id: UUID) {
        let switching = id != paletteID
        if switching { dismissSheet() }
        if switching { tagBar.end(saving: false) }
        paletteID = id
        reload()
        if switching {
            grid.deselectAll(nil)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            list.scrollToTop()
        }
    }

    func setSearch(_ text: String) {
        search = text.trimmingCharacters(in: .whitespaces).lowercased()
        reload()
    }

    func reload() {
        _ = view
        guard let id = paletteID, let s = library.library.swatch(id) else { return }
        let all = library.hexes(in: id)
        hexes = search.isEmpty ? all : all.filter {
            $0.lowercased().contains(search) || colourName($0).lowercased().contains(search)
                || (library.library.customName(of: $0, in: id)?.lowercased().contains(search) ?? false)
        }
        // The bar under the spectrum narrows the page, then splits it into titled groups. Grouped,
        // the colours run group by group, so the spectrum, the selection and the page all agree.
        let proofing = library.profile(forPalette: id).profile
        hexes = library.library.shown(hexes, filter: Prefs.paletteFilter, profile: proofing)
        groups = library.library.groups(of: hexes, by: Prefs.paletteGrouping, profile: proofing)
        if !groups.isEmpty { hexes = groups.flatMap { $0.keys } }
        (slots, slotCounts) = PaletteSlot.page(hexes, groups: groups, offersNew: !(s.projectID.flatMap { library.library.project($0)?.isLocked } ?? false) && search.isEmpty)
        histogramBar.refresh()
        histogramBar.isHidden = !(Prefs.histograms && Prefs.paletteListView)

        if view.window?.firstResponder !== nameField.currentEditor() || nameField.currentEditor() == nil {
            committedName = s.name
            nameField.stringValue = s.name
        }
        tagButton.image = symbol(s.tagList.isEmpty ? "tag" : "tag.fill", "Tags")
        tagButton.contentTintColor = s.tagList.isEmpty ? .secondaryLabelColor : .controlAccentColor
        tagButton.toolTip = s.tagList.isEmpty ? "Add tags to this palette" : "Tags: " + s.tagList.joined(separator: ", ")
        wcag.state = Prefs.showContrast ? .on : .off
        let isTarget = library.library.activeSwatchID == id
        var parts = [plural(s.entries.count, "Swatch", "Swatches")]
        if hexes.count != all.count { parts.append("\(hexes.count) Shown") }
        if s.custom { parts.append("Custom palette") }
        if isTarget { parts.append("Picks go here") }
        restSubtitle = parts.joined(separator: "  \u{00B7}  ")
        // A project palette says so: its project as a pill, and stripes behind the title.
        let project = s.projectID.flatMap { pid in library.library.project(pid).map { (pid, $0.name) } }
        header.setProject(project?.1) { [weak self] in if let pid = project?.0 { self?.library.onRevealProject?(pid) } }
        header.striped = project != nil
        header.lock = s.projectID.flatMap { library.library.project($0)?.isLocked }
        nameField.isEditable = !(header.lock ?? false)

        star.image = symbol(s.favourite ? "star.fill" : "star", "Favourite")
        star.contentTintColor = s.favourite ? .systemYellow : .secondaryLabelColor
        star.toolTip = s.favourite ? "Remove from Favourites" : "Add to Favourites"
        target.contentTintColor = isTarget ? .controlAccentColor : .secondaryLabelColor
        target.toolTip = isTarget ? "New picks are added to this palette. Click to stop." : "Send new picks to this palette"
        sort.selectItem(at: [SortOrder.oldest, .newest, .colour].firstIndex(of: library.paletteSort) ?? 0)
        fillProfiles(for: s)

        spectrum.hexes = hexes

        // Two views, switched from the title panel's right: cards, or one colour to a row with its notes.
        // The choice is the user's for every palette, so it holds from one palette to the next.
        let asList = Prefs.paletteListView
        header.trailing.isHidden = false
        for (button, name, on) in [(gridButton, "square.grid.2x2", !asList), (listButton, "rectangle.grid.1x2", asList)] {
            button.image = symbol(name, button.toolTip ?? "", size: PageHeader.titleSymbol, weight: .semibold)
            button.contentTintColor = on ? .labelColor : .tertiaryLabelColor
        }
        scroll.isHidden = asList
        list.isHidden = !asList
        // WCAG and Labels work on both views: what a card shows, a row's Meta column shows.
        if asList { list.show(hexes, in: id, locked: header.lock ?? false, offersNew: offersNew, groups: groups, panels: RowPanels.chosen) }

        sizeCards()
        grid.reloadData()
        updateHeader()

        empty.isHidden = !hexes.isEmpty || offersNew   // the blank swatch says what to do next
        empty.stringValue = !search.isEmpty ? "No swatches in this palette match \u{201C}\(search)\u{201D}."
            : !all.isEmpty ? "No Swatches Here Are \u{201C}\(Prefs.paletteFilter.title)\u{201D}."
            : "No swatches yet.\n" + (Shortcuts.display(for: "togglePicking").map { "Press \($0) to pick" } ?? "Pick")
                + " colours into this palette, or drop an image on the window."
        refreshRail()
    }

    /// The swatch's sheet, while one is up: notes and history for one colour, centred on this page.
    private var sheet: SwatchSheet?

    private func openSheet(for hex: String, tab: Int) {
        guard let id = paletteID, sheet == nil else { return }
        let new = SwatchSheet(hex: hex, palette: id, library: library, tab: tab, locked: header.lock ?? false)
        new.onClose = { [weak self] in
            self?.sheet = nil
            self?.view.window?.makeFirstResponder(self?.view)
        }
        sheet = new
        new.present(over: view)
    }

    /// Takes the sheet down, keeping what was typed; used when the page goes elsewhere.
    func dismissSheet() {
        sheet?.finish()
    }

    /// The profile menu: first what the palette inherits, then every profile it could have of its own.
    private func fillProfiles(for s: Swatch) {
        let inherited = s.projectID.map { library.profile(forProject: $0) } ?? library.profile(forPalette: nil)
        profile.removeAllItems()
        profile.addItem(withTitle: (s.projectID == nil ? "House Profile: " : "Project Profile: ") + inherited.profile.name)
        profile.menu?.addItem(.separator())
        for p in library.offeredProfiles {
            profile.addItem(withTitle: p.name)
            profile.lastItem?.representedObject = p.id.uuidString
            profile.lastItem?.toolTip = p.summary
        }
        let own = s.profile.flatMap { id in profile.itemArray.firstIndex { ($0.representedObject as? String) == id.uuidString } }
        profile.selectItem(at: own ?? 0)
        profile.isEnabled = !(header.lock ?? false)
        let using = library.profile(forPalette: s.id).profile
        profile.toolTip = "The colour profile this palette is proofed for: \(using.summary)"
    }

    @objc private func profileChanged() {
        guard let id = paletteID else { return }
        let chosen = (profile.selectedItem?.representedObject as? String).flatMap(UUID.init(uuidString:))
        library.setProfile(chosen.flatMap { want in library.offeredProfiles.first { $0.id == want } }, ofPalette: id)
    }

    @objc private func analysisTapped() { if let id = paletteID { library.analyse(palette: id) } }
    @objc private func showGrid() { setList(false) }
    @objc private func showList() { setList(true) }
    private func setList(_ on: Bool) {
        guard Prefs.paletteListView != on else { return }
        let chosen = selectedKey
        Prefs.paletteListView = on
        if !on { Prefs.histograms = false; Prefs.paletteChannels = false; Prefs.paletteHistory = false }   // the grid has nowhere to put them
        reload()
        select(chosen)
    }

    // MARK: rail2

    /// The swatch that is selected, in whichever view is showing; the first, when the grid has several.
    private var selectedKey: String? { Prefs.paletteListView ? list.selected : selected().first }

    /// Selects a swatch in whichever view is showing, so a selection survives a change of view.
    private func select(_ key: String?) {
        if Prefs.paletteListView {
            list.select(key)
        } else {
            grid.deselectAll(nil)
            if let key = key, let i = slots.firstIndex(of: .colour(key)) { grid.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: []) }
            updateHeader()
        }
        refreshRail()
    }

    private func menu(_ popup: NSPopUpButton, _ titles: [String], _ action: Selector) {
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
    }

    /// Builds this page's context rail: buckets of choices, switches and links, open to begin with.
    private func buildRail() {
        menu(contrastMenu, ["Off", "WCAG 2", "APCA"], #selector(contrastChosen))
        menu(groupMenu, PaletteGrouping.allCases.map { $0.title }, #selector(groupChosen))
        menu(showMenu, PaletteFilter.allCases.map { $0.title }, #selector(showChosen))
        displayBucket.set([
            RailRow("Contrast", symbol: "circle.lefthalf.filled", tip: "The Contrast Shown On Every Swatch: Off, WCAG 2, Or APCA", kind: .choice(contrastMenu)),
            RailRow("Profile", symbol: "dial.medium", tip: "The Colour Profile This Palette Is Proofed For", kind: .choice(profile)),
            RailRow("Order", symbol: "arrow.up.arrow.down", tip: "The Order The Swatches Are Shown In", kind: .choice(sort)),
        ])
        paletteBucket.set([
            RailRow("Palette Analysis", symbol: "chart.pie", tip: "The Whole Palette Looked At Ten Ways: Colour Vision, Contrast, Separation, Print Reach And More", kind: .link { [weak self] in self?.analysisTapped() }),
        ])
        let panels: [(String, String, String)] = [("Notes", "note.text", "Show Every Swatch's Notes"), ("History", "clock.arrow.circlepath", "Show What Happened To Every Swatch"),
                                                  ("Channels", "dial.medium", "Show Every Swatch's Value And Fidelity In Each Channel"), ("Histogram", "chart.bar.xaxis", "Show Every Swatch's Histogram")]
        panelRows = panels.enumerated().map { i, panel in RailRow(panel.0, symbol: panel.1, tip: panel.2, kind: .toggle { [weak self] in self?.panelToggled(i) }) }
        swatchBucket.set([
            RailRow("Group By", symbol: "rectangle.3.group", tip: "Split The Page Into Groups", kind: .choice(groupMenu)),
            RailRow("Display", symbol: "line.3.horizontal.decrease.circle", tip: "Show Only Some Colours", kind: .choice(showMenu)),
        ] + panelRows)
        labelRows = (["Name"] + ColourFormat.cardRows.map { $0.label }).enumerated().map { i, label in
            RailRow(label, symbol: i == 0 ? "textformat" : "number", tip: "Show \(label) On Every Swatch", kind: .toggle { [weak self] in self?.railLabelToggled(i) })
        }
        labelsBucket.set(labelRows)
        // What the palette is for. Each one that is on has settings of its own, kept in a file beside the palette's.
        purposeRows = Purpose.allCases.map { purpose in
            RailRow(purpose.title, symbol: purpose.symbol, tip: purpose.about, kind: .toggle { [weak self] in self?.purposeToggled(purpose) })
        }
        purposeBucket.set(purposeRows)
        contextRail.set([purposeBucket, displayBucket, paletteBucket, swatchBucket, labelsBucket, tagsBucket])
    }

    /// Brings the rail up to date with the page: what is chosen, what is on, and whether a swatch is selected.
    private func refreshRail() {
        guard isViewLoaded, let id = paletteID, let s = library.library.swatch(id) else { return }
        contrastMenu.selectItem(at: !Prefs.showContrast ? 0 : Prefs.contrastMethod == "apca" ? 2 : 1)
        groupMenu.selectItem(at: PaletteGrouping.allCases.firstIndex(of: Prefs.paletteGrouping) ?? 0)
        showMenu.selectItem(at: PaletteFilter.allCases.firstIndex(of: Prefs.paletteFilter) ?? 0)
        let serves = s.purposeList
        for (row, purpose) in zip(purposeRows, Purpose.allCases) {
            row.isOn = serves.contains(purpose)
            row.isEnabled = !(header.lock ?? false)
        }
        let asList = Prefs.paletteListView
        for (row, on) in zip(panelRows, [Prefs.paletteNotes && asList, Prefs.paletteHistory, Prefs.paletteChannels, Prefs.histograms]) { row.isOn = on }
        // Always there: these act on the whole page, and a filter that hides every swatch must stay within reach to be undone.
        swatchBucket.isHidden = false
        let shown = Prefs.cardRows
        for (i, row) in labelRows.enumerated() { row.isOn = i == 0 ? Prefs.showNames : shown.contains(ColourFormat.cardRows[i - 1]) }
        // The palette's own tags, as rail1 lists tags: a press shows everything with that tag.
        var tags: [NSView] = s.tagList.map { tag in
            RailRow("#" + tag, symbol: "tag", dot: tagColour(library.library.info(forTag: tag)), tip: "Show Everything Tagged \(tag)", kind: .link { [weak self] in self?.library.onShow?(.tag(tag), false) })
        }
        let edit = RailRow(s.tagList.isEmpty ? "Add Tags\u{2026}" : "Edit Tags\u{2026}", symbol: "pencil", tip: "Change This Palette's Tags", kind: .link { [weak self] in self?.tagsTapped() })
        edit.isEnabled = !(header.lock ?? false)
        tags.append(edit)
        tagsBucket.set(tags)
    }

    private func purposeToggled(_ purpose: Purpose) {
        guard let id = paletteID, let s = library.library.swatch(id) else { return }
        library.setPurpose(purpose, on: !s.purposeList.contains(purpose), ofPalette: id)
        refreshRail()
    }

    @objc private func contrastChosen() {
        let choice = contrastMenu.indexOfSelectedItem
        if choice > 0 { Prefs.contrastMethod = choice == 2 ? "apca" : "wcag" }
        Prefs.showContrast = choice > 0
        reload()
    }
    @objc private func groupChosen() {
        let chosen = selectedKey
        Prefs.paletteGrouping = PaletteGrouping.allCases[min(max(groupMenu.indexOfSelectedItem, 0), PaletteGrouping.allCases.count - 1)]
        reload()
        select(chosen)
    }
    @objc private func showChosen() {
        let chosen = selectedKey
        Prefs.paletteFilter = PaletteFilter.allCases[min(max(showMenu.indexOfSelectedItem, 0), PaletteFilter.allCases.count - 1)]
        reload()
        select(chosen)
    }

    /// Notes, History, Channels, Histogram: columns beside every swatch, which only the vertical view has.
    private func panelToggled(_ index: Int) {
        let chosen = selectedKey
        switch index {
        case 0: Prefs.paletteNotes = !(Prefs.paletteNotes && Prefs.paletteListView)
        case 1: Prefs.paletteHistory.toggle()
        case 2: Prefs.paletteChannels.toggle()
        default: Prefs.histograms.toggle()
        }
        if Prefs.paletteChannels || Prefs.paletteHistory || Prefs.histograms || index == 0 { Prefs.paletteListView = true }
        reload()
        select(chosen)
    }

    private func railLabelToggled(_ index: Int) {
        if index == 0 { Prefs.showNames.toggle(); return }
        let format = ColourFormat.cardRows[index - 1]
        var rows = Prefs.cardRows
        if rows.contains(format) { rows.removeAll { $0 == format } } else { rows.append(format) }
        Prefs.cardRows = ColourFormat.cardRows.filter { rows.contains($0) }
    }

    /// Lays the cards out afresh for the current width.
    func relayout() {
        guard isViewLoaded else { return }
        grid.collectionViewLayout?.invalidateLayout()
        grid.needsLayout = true
    }

    func reveal(_ hex: String) {
        guard let i = slots.firstIndex(of: .colour(hex)) else { return }
        grid.layoutSubtreeIfNeeded()
        grid.deselectAll(nil)
        grid.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: .centeredVertically)
    }

    func beginRenaming() {
        _ = view
        view.window?.makeFirstResponder(nameField)
    }

    // MARK: Grid

    func numberOfSections(in cv: NSCollectionView) -> Int { 1 }
    /// The blank swatch that adds a colour follows the last one, unless the project is locked or a search is narrowing the page.
    private var offersNew: Bool { !(header.lock ?? false) && search.isEmpty }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { slots.count }

    func collectionView(_ cv: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at ip: IndexPath) -> NSView {
        let view = cv.makeSupplementaryView(ofKind: kind, withIdentifier: GroupHeaderView.identifier, for: ip)
        if let title = view as? GroupHeaderView, groups.indices.contains(ip.item) { title.label.stringValue = GroupHeaderView.text(groups[ip.item]) }
        return view
    }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        guard slots.indices.contains(ip.item), case .colour(let hex) = slots[ip.item] else {
            let add = cv.makeItem(withIdentifier: AddCard.identifier, for: ip) as! AddCard
            var start: NewColourStart?
            if slots.indices.contains(ip.item), case .add(let asked) = slots[ip.item] { start = asked }
            add.tile.onPress = { [weak self] in self?.library.startColour(start) }
            return add
        }
        let card = cv.makeItem(withIdentifier: ColourCard.identifier, for: ip) as! ColourCard
        card.library = library
        card.configure(hex: hex, called: library.library.customName(of: hex, in: paletteID))
        card.onRename = { [weak self] name in
            if let id = self?.paletteID { self?.library.rename(swatch: hex, in: id, to: name) }
        }
        card.onCopyRow = { [weak self] format in self?.library.copy(hex, as: format) }
        card.onHalo = { [weak self] trigger in self?.openHalo(for: hex, from: trigger) }
        return card
    }

    /// For a trial run: opens the first swatch's halo from its own button, then chooses each of
    /// `ids` in turn, so a ring grown outside the first can be looked at.
    func rehearseHalo(choosing ids: [String]) {
        guard !Prefs.paletteListView, let card = grid.item(at: IndexPath(item: 0, section: 0)) as? ColourCard else { return }
        card.pressHalo()
        for (at, id) in ids.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + 0.35 * Double(at)) { [weak self] in self?.halo.choose(id: id) }
        }
    }

    /// Opens the swatch's actions as a halo with its centre on the button that was pressed.
    private func openHalo(for hex: String, from trigger: NSView) {
        haloHex = hex
        halo.caption = Prefs.showNames ? library.library.name(of: hex, in: paletteID) : ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex)
        halo.actions = SwatchMenu.ring(for: hex, in: paletteID, library: library, editTags: onEditTags)
        halo.open(over: trigger)
    }

    private func clicked(_ ip: IndexPath) {
        guard slots.indices.contains(ip.item), let hex = slots[ip.item].key else { return }
        library.copy(hex)
    }

    private func selected() -> [String] {
        grid.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap { slots.indices.contains($0.item) ? slots[$0.item].key : nil }
    }

    private func copySelected() { library.copy(selected()) }

    private func removeSelected() {
        guard let id = paletteID else { return }
        library.remove(selected(), from: id)
    }

    // MARK: Header actions

    @objc private func starTapped() { if let id = paletteID { library.toggleFavourite(id) } }

    @objc private func targetTapped() {
        guard let id = paletteID else { return }
        library.setTarget(library.library.activeSwatchID == id ? nil : id)
    }

    @objc private func copyAllTapped() {
        guard let id = paletteID else { return }
        library.copy(library.hexes(in: id), from: library.library.swatch(id)?.name)
    }

    @objc private func sortChanged() {
        library.paletteSort = [SortOrder.oldest, .newest, .colour][max(0, sort.indexOfSelectedItem)]
    }

    /// The tag icon: the action bar gives way to the tag bar, on this palette's own tags.
    @objc private func tagsTapped() {
        guard let id = paletteID, let s = library.library.swatch(id) else { return }
        startTagging("Palette tags", tags: s.tagList, projects: Set([s.projectID].compactMap { $0 })) { [weak self] tags, scoped in self?.library.setTags(ofPalette: id, tags, scoped: scoped) }
    }

    /// The same bar, on one swatch or several. They all end up with the tags left in the bar.
    private func editTags(of hexes: [String]) {
        guard let first = hexes.first else { return }
        let current = library.library.colours.first { $0.hex == first }?.tags ?? []
        let what = hexes.count == 1 ? "Tags for \(colourName(first))" : "Tags for \(plural(hexes.count, "Swatch", "Swatches"))"
        startTagging(what, tags: current, projects: library.library.projects(holdingAll: hexes)) { [weak self] tags, scoped in self?.library.setTags(ofSwatches: hexes, tags, scoped: scoped) }
    }

    private func startTagging(_ what: String, tags: [String], projects: Set<UUID>, commit: @escaping ([String], [String: UUID]) -> Void) {
        tagging = true
        updateHeader()
        tagBar.begin(what, tags: tags, in: library.library, projects: projects, commit: commit)
    }

    @objc private func wcagTapped() { Prefs.showContrast = wcag.state == .on }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let id = paletteID else { return }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == committedName { nameField.stringValue = committedName; return }
        committedName = typed
        library.rename(id, to: typed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            nameField.abortEditing()
            nameField.stringValue = committedName
            view.window?.makeFirstResponder(grid)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(grid)
            return true
        }
        return false
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === addTo.menu {
            menu.addItem(withTitle: "Add to Palette", action: nil, keyEquivalent: "")
            for s in library.paletteOrder where s.id != paletteID {
                let item = menu.addItem(withTitle: s.name, action: #selector(addChosen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.id
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "New Palette", action: #selector(addChosen(_:)), keyEquivalent: "").target = self
            return
        }
        let chosen = selected()
        guard !chosen.isEmpty else { return }
        SwatchMenu.fill(menu, for: chosen, in: paletteID, library: library, editTags: onEditTags)
    }

    // MARK: Several swatches selected

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateHeader(); refreshRail() }
    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateHeader(); refreshRail() }

    /// With two or more swatches selected the name gives way to a count and the bar to actions on them.
    private func updateHeader() {
        let many = selected().count > 1
        tagBar.isHidden = !tagging
        header.subtitle.isHidden = tagging
        header.gap.isHidden = tagging
        browsing.isHidden = many || tagging
        selecting.isHidden = !many || tagging
        let editingName = nameField.currentEditor() != nil
        nameField.isEditable = !many
        if many {
            nameField.stringValue = "\(selected().count) Swatches Selected"
            header.subtitle.stringValue = "Shift-click or \u{2318}-click to change the selection"
        } else {
            if !editingName { nameField.stringValue = committedName }
            header.subtitle.stringValue = restSubtitle
        }
    }

    @objc private func copyChosen() { library.copy(selected()) }
    @objc private func removeChosen() { removeSelected() }
    @objc private func deselect() { grid.deselectAll(nil); updateHeader() }
    @objc private func tagChosen() {
        editTags(of: selected())
    }
    @objc private func addChosen(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { library.add(selected(), to: id) }
        else { library.createPalette(named: "", hexes: selected(), rename: true) }
    }

    // MARK: Which values the cards show

    func rehearseLabels() { showLabels() }
    func rehearseTagBar(typing text: String) {
        tagsTapped()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tagBar.rehearse(typing: text) }
    }

    @objc private func showLabels() {
        if labelsPopover.isShown { labelsPopover.close(); return }
        let rows = Prefs.cardRows
        labelChecks[0].state = Prefs.showNames ? .on : .off
        for (box, format) in zip(labelChecks.dropFirst(), ColourFormat.cardRows) { box.state = rows.contains(format) ? .on : .off }
        labelsPopover.show(relativeTo: labels.bounds, of: labels, preferredEdge: .maxY)
    }

    @objc private func labelToggled() {
        Prefs.showNames = labelChecks[0].state == .on
        Prefs.cardRows = zip(labelChecks.dropFirst(), ColourFormat.cardRows).filter { $0.0.state == .on }.map { $0.1 }
    }
}

/// The right-click menu for swatches, shared by the palette page and All Swatches.
enum SwatchMenu {
    static func fill(_ menu: NSMenu, for hexes: [String], in palette: UUID?, library: LibraryController,
                     editTags: (([String]) -> Void)? = nil) {
        let handler = Handler(hexes: hexes, palette: palette, library: library)
        handler.editTags = editTags
        objc_setAssociatedObject(menu, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

        func add(_ to: NSMenu, _ title: String, _ action: Selector, _ object: Any? = nil) {
            let item = to.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = handler
            item.representedObject = object
        }

        add(menu, hexes.count == 1 ? "Copy \(Prefs.copyText(hexes[0]))" : "Copy \(hexes.count) Swatches", #selector(Handler.copyChosen))
        if hexes.count == 1 {
            let copyAs = NSMenu()
            for f in ColourFormat.allCases { add(copyAs, f.text(hexes[0], lowercase: Prefs.lowercaseHex), #selector(Handler.copyAs(_:)), f.rawValue) }
            let item = menu.addItem(withTitle: "Copy As", action: nil, keyEquivalent: "")
            item.submenu = copyAs
        }
        menu.addItem(.separator())

        let addTo = NSMenu()
        for s in library.paletteOrder where s.id != palette { add(addTo, s.name, #selector(Handler.addTo(_:)), s.id) }
        if !addTo.items.isEmpty { addTo.addItem(.separator()) }
        add(addTo, "New Palette", #selector(Handler.addToNew))
        menu.addItem(withTitle: "Add to Palette", action: nil, keyEquivalent: "").submenu = addTo

        if hexes.count == 1 {
            let make = NSMenu()
            for h in Harmony.allCases { add(make, h.title, #selector(Handler.make(_:)), h.rawValue) }
            menu.addItem(withTitle: "Make Palette", action: nil, keyEquivalent: "").submenu = make
            add(menu, "Open In cLab", #selector(Handler.openInLab))
        }

        menu.addItem(.separator())
        add(menu, "Tags\u{2026}", #selector(Handler.tags))
        menu.addItem(.separator())
        if palette != nil { add(menu, "Remove from Palette", #selector(Handler.removeChosen)) }
        add(menu, "Delete from Library", #selector(Handler.deleteChosen))
    }

    /// The same actions as a ring for the halo, for one swatch. The menu's submenus become rings
    /// of their own, grown outside the first; Escape steps back from one.
    static func ring(for hex: String, in palette: UUID?, library: LibraryController, editTags: (([String]) -> Void)? = nil) -> [HaloAction] {
        func group(_ id: String, _ label: String, _ symbol: String, _ description: String, _ inner: @escaping () -> [HaloAction]) -> HaloAction {
            HaloAction(id: id, label: label, symbol: symbol, description: description, children: inner)
        }
        func dot(_ colour: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
                colour.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
                return true
            }
        }
        let harmonySymbols: [Harmony: String] = [.complementary: "circle.lefthalf.fill", .analogous: "ellipsis", .triadic: "triangle",
            .splitComplementary: "arrow.triangle.branch", .tetradic: "square", .tintsAndShades: "sun.max", .scale: "slider.horizontal.3"]

        var actions = [
            HaloAction(id: "copy", label: "Copy \(Prefs.copyText(hex))", symbol: "doc.on.doc") { library.copy([hex]) },
            group("copy-as", "Copy As", "doc.on.clipboard", "Choose a format") {
                ColourFormat.allCases.map { f in
                    HaloAction(id: f.rawValue, label: f.text(hex, lowercase: Prefs.lowercaseHex), symbol: "doc.on.doc",
                               description: f.title.components(separatedBy: "  \u{2014}").first) { library.copy(hex, as: f) }
                }
            },
            group("add-to", "Add to Palette", "folder.badge.plus", "Choose a palette") {
                library.paletteOrder.filter { $0.id != palette }.map { s in
                    HaloAction(id: s.id.uuidString, label: s.name, icon: dot(identityColour(s.id)), description: "Add to this palette") { library.add([hex], to: s.id) }
                } + [HaloAction(id: "new", label: "New Palette", symbol: "plus") { library.createPalette(named: "", hexes: [hex], rename: true) }]
            },
            group("make", "Make Palette", "wand.and.stars", "Build a palette from this colour") {
                Harmony.allCases.map { h in
                    HaloAction(id: h.rawValue, label: h.title, symbol: harmonySymbols[h] ?? "circle") { library.makePalette(h, from: hex) }
                }
            },
            HaloAction(id: "lab", label: "Open In cLab", symbol: labSymbolName, description: "Build on this colour on the wheel") {
                library.onOpenLab?(hex)
            },
            HaloAction(id: "tags", label: "Tags\u{2026}", symbol: "tag") {
                editTags?([hex])
            },
            HaloAction(id: "analysis", label: "Analysis", symbol: "chart.pie", description: "Hue, lightness, colour blind simulation, light and dark") {
                library.analyse(swatch: hex, in: palette)
            },
        ]
        if let id = palette {
            actions.append(HaloAction(id: "remove", label: "Remove from Palette", symbol: "minus.circle") { library.remove([hex], from: id) })
        }
        if let id = palette {
            // The colour's name in this palette: typed in the middle of the halo, or put back to the standard one.
            let own = library.library.customName(of: hex, in: id)
            actions.insert(HaloAction(id: "rename", label: "Rename", symbol: "pencil", description: "Give this colour your own name in this palette",
                                      edit: (library.library.name(of: hex, in: id), colourName(hex), "Return saves \u{00B7} Empty resets",
                                             { library.rename(swatch: hex, in: id, to: $0) })), at: 1)
            if own != nil {
                actions.insert(HaloAction(id: "reset-name", label: "Reset Name", symbol: "arrow.counterclockwise",
                                          description: "Back to \(colourName(hex))") { library.rename(swatch: hex, in: id, to: nil) }, at: 2)
            }
        }
        actions.append(HaloAction(id: "delete", label: "Delete from Library", symbol: "trash") { library.deleteFromLibrary([hex]) })
        return actions
    }

    final class Handler: NSObject {
        let hexes: [String], palette: UUID?, library: LibraryController
        var editTags: (([String]) -> Void)?
        init(hexes: [String], palette: UUID?, library: LibraryController) {
            self.hexes = hexes; self.palette = palette; self.library = library
        }

        @objc func copyChosen() { library.copy(hexes) }
        @objc func tags() { editTags?(hexes) }
        @objc func copyAs(_ s: NSMenuItem) {
            if let raw = s.representedObject as? String, let f = ColourFormat(rawValue: raw) { library.copy(hexes[0], as: f) }
        }
        @objc func addTo(_ s: NSMenuItem) { if let id = s.representedObject as? UUID { library.add(hexes, to: id) } }
        @objc func addToNew() { library.createPalette(named: "", hexes: hexes, rename: true) }
        @objc func make(_ s: NSMenuItem) {
            if let raw = s.representedObject as? String, let h = Harmony(rawValue: raw) { library.makePalette(h, from: hexes[0]) }
        }
        @objc func openInLab() { library.onOpenLab?(hexes[0]) }
        @objc func removeChosen() { if let id = palette { library.remove(hexes, from: id) } }
        @objc func deleteChosen() { library.deleteFromLibrary(hexes) }
    }
}
