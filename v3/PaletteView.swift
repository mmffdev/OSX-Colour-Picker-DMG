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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 46),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
        toolTip = "Copy \(format.label)  \(format.text(hex, lowercase: Prefs.lowercaseHex))"
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
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
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

final class ColourCard: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("card")
    /// The narrowest a card gets; they widen to fill the row.
    static let width: CGFloat = 228

    /// Height for the rows and extras switched on in Settings.
    static var height: CGFloat {
        68 + CGFloat(Prefs.cardRows.count) * 25 + (Prefs.showContrast ? 46 : 0) + 12
    }

    var onCopyRow: ((ColourFormat) -> Void)?
    /// The halo button was pressed; hands over the button so the halo knows its trigger.
    var onHalo: ((NSView) -> Void)?
    weak var library: LibraryController?
    private(set) var hex = ""
    private let name = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    private let contrast = NSTextField(labelWithString: "")
    private let contrastTitle = NSTextField(labelWithString: "WCAG TEXT CONTRAST")
    private let ring = CAShapeLayer()
    private let halo = HaloTriggerView()

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.cornerCurve = .continuous
        v.layer?.borderWidth = 1
        view = v

        name.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        name.lineBreakMode = .byTruncatingTail
        code.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        contrast.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        contrast.lineBreakMode = .byTruncatingTail
        contrastTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading

        halo.toolTip = "Actions"
        halo.onPress = { [weak self] in
            guard let self = self else { return }
            self.onHalo?(self.halo)
        }

        for s in [name, code, rows, contrastTitle, contrast, halo] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(s)
        }
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: v.topAnchor, constant: 14),
            name.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            name.trailingAnchor.constraint(equalTo: halo.leadingAnchor, constant: -8),
            halo.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -11), // its ring sits 3 points inside its frame
            halo.widthAnchor.constraint(equalToConstant: 24),
            halo.heightAnchor.constraint(equalToConstant: 24),
            halo.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            code.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            code.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            rows.topAnchor.constraint(equalTo: v.topAnchor, constant: 68),
            rows.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            contrast.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            contrast.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            contrast.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14),
            contrastTitle.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            contrastTitle.bottomAnchor.constraint(equalTo: contrast.topAnchor, constant: -3),
        ])
    }

    override var isSelected: Bool { didSet { outline() } }

    private func outline() {
        let ink = colorFromHex(readableText(on: hex)) ?? .white
        view.layer?.borderWidth = isSelected ? 3 : 1
        view.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : ink.withAlphaComponent(0.16)).cgColor
    }

    func configure(hex: String) {
        self.hex = hex
        let ink = colorFromHex(readableText(on: hex)) ?? .white
        view.layer?.backgroundColor = colorFromHex(hex)?.cgColor
        outline()

        name.stringValue = Prefs.showNames ? colourName(hex) : ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex)
        name.textColor = ink
        halo.ink = ink
        code.stringValue = Prefs.showNames ? ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex) : ""
        code.textColor = ink.withAlphaComponent(0.75)
        let tags = library?.library.colours.first { $0.hex == hex }?.tags ?? []
        view.toolTip = "Click to copy \(Prefs.copyText(hex))" + (tags.isEmpty ? "" : "\nTags: " + tags.joined(separator: ", "))

        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for format in Prefs.cardRows {
            let row = FormatRow(frame: .zero)
            row.configure(format, hex: hex, ink: ink)
            row.onCopy = { [weak self] in self?.onCopyRow?(format) }
            row.translatesAutoresizingMaskIntoConstraints = false
            rows.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 25),
                row.widthAnchor.constraint(equalTo: rows.widthAnchor),
            ])
        }

        contrast.isHidden = !Prefs.showContrast
        contrastTitle.isHidden = !Prefs.showContrast
        contrastTitle.textColor = ink.withAlphaComponent(0.62)
        if Prefs.showContrast {
            let white = contrastRatio(hex, "#FFFFFF"), black = contrastRatio(hex, "#000000")
            contrast.stringValue = String(format: "White %.1f %@  \u{00B7}  Black %.1f %@",
                                          white, contrastGrade(white), black, contrastGrade(black))
            contrast.textColor = ink.withAlphaComponent(0.7)
            contrast.toolTip = "Contrast ratio of white and of black text on this colour, with its WCAG grade"
        }
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

    private let nameField = NSTextField(labelWithString: "")
    private let subtitle = caption("")
    private var star: NSButton!
    private var target: NSButton!
    private var tagButton: NSButton!
    private let tagBar = TagBar()
    private let barGap = NSView()
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
    private let spectrum = SpectrumView()
    private let grid = SwatchGridView()
    private let scroll = PagingScrollView()
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
        layout.margins = NSEdgeInsets(top: 8, left: side, bottom: 24, right: side)
        layout.height = { _ in ColourCard.height }
        layout.invalidateLayout()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layout.fitVisibleWidth()
    }

    override func loadView() {
        view = NSView()

        nameField.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        nameField.lineBreakMode = .byTruncatingTail
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

        // The name has the top row to itself; under it, the count on the left and the actions on the right.
        let gap = barGap
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        browsing.setViews([tagButton, star, target, copyAll, wcag, labels, sort], in: .leading)
        browsing.spacing = 12
        let bar = NSStackView(views: [subtitle, gap, browsing, selecting, tagBar])
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.alignment = .centerY

        let header = NSStackView(views: [nameField, bar])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        header.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        NSLayoutConstraint.activate([
            nameField.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            bar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
        ])

        sizeCards()
        grid.collectionViewLayout = layout
        grid.dataSource = self
        grid.delegate = self
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.register(ColourCard.self, forItemWithIdentifier: ColourCard.identifier)
        grid.onClick = { [weak self] ip in self?.clicked(ip) }
        grid.onDelete = { [weak self] in self?.removeSelected() }
        grid.onCopy = { [weak self] in self?.copySelected() }
        grid.onFavourite = { [weak self] in self?.starTapped() }
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

        for v in [header, spectrum, scroll, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        // 66 points unless its contents need more; never left to stretch into the page below.
        let headerHeight = header.heightAnchor.constraint(equalToConstant: 66)
        headerHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),   // taller while the tag bar shows its second row
            headerHeight,
            spectrum.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            spectrum.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            spectrum.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            spectrum.heightAnchor.constraint(equalToConstant: 50),
            scroll.topAnchor.constraint(equalTo: spectrum.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    // MARK: Contents

    func show(_ id: UUID) {
        let switching = id != paletteID
        if switching { tagBar.end(saving: false) }
        paletteID = id
        reload()
        if switching {
            grid.deselectAll(nil)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
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
        }

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
        if !search.isEmpty { parts.append("\(hexes.count) Shown") }
        if s.custom { parts.append("Custom palette") }
        if isTarget { parts.append("Picks go here") }
        restSubtitle = parts.joined(separator: "  \u{00B7}  ")

        star.image = symbol(s.favourite ? "star.fill" : "star", "Favourite")
        star.contentTintColor = s.favourite ? .systemYellow : .secondaryLabelColor
        star.toolTip = s.favourite ? "Remove from Favourites" : "Add to Favourites"
        target.contentTintColor = isTarget ? .controlAccentColor : .secondaryLabelColor
        target.toolTip = isTarget ? "New picks are added to this palette. Click to stop." : "Send new picks to this palette"
        sort.selectItem(at: [SortOrder.oldest, .newest, .colour].firstIndex(of: library.paletteSort) ?? 0)

        spectrum.hexes = hexes

        sizeCards()
        grid.reloadData()
        updateHeader()

        empty.isHidden = !hexes.isEmpty
        empty.stringValue = !search.isEmpty ? "No swatches in this palette match \u{201C}\(search)\u{201D}."
            : "No swatches yet.\n" + (Shortcuts.display(for: "togglePicking").map { "Press \($0) to pick" } ?? "Pick")
                + " colours into this palette, or drop an image on the window."
    }

    /// Lays the cards out afresh for the current width.
    func relayout() {
        guard isViewLoaded else { return }
        grid.collectionViewLayout?.invalidateLayout()
        grid.needsLayout = true
    }

    func reveal(_ hex: String) {
        guard let i = hexes.firstIndex(of: hex) else { return }
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
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { hexes.count }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let card = cv.makeItem(withIdentifier: ColourCard.identifier, for: ip) as! ColourCard
        let hex = hexes[ip.item]
        card.library = library
        card.configure(hex: hex)
        card.onCopyRow = { [weak self] format in self?.library.copy(hex, as: format) }
        card.onHalo = { [weak self] trigger in self?.openHalo(for: hex, from: trigger) }
        return card
    }

    /// Opens the swatch's actions as a halo in the middle of the page. A second press on the
    /// same button, with the halo still open, chooses whatever is under the wedge.
    private func openHalo(for hex: String, from trigger: NSView) {
        if halo.isOpen, haloHex == hex { halo.chooseSelected(); return }
        haloHex = hex
        halo.caption = Prefs.showNames ? colourName(hex) : ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex)
        halo.actions = SwatchMenu.ring(for: hex, in: paletteID, library: library, editTags: onEditTags) { [weak self] in self?.halo.actions = $0 }
        halo.open(centredIn: grid.enclosingScrollView ?? view, trigger: trigger)
    }

    private func clicked(_ ip: IndexPath) {
        guard ip.item < hexes.count else { return }
        library.copy(hexes[ip.item])
    }

    private func selected() -> [String] {
        grid.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap { $0.item < hexes.count ? hexes[$0.item] : nil }
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
        startTagging("Palette tags", tags: s.tagList) { [weak self] tags, scoped in self?.library.setTags(ofPalette: id, tags, scoped: scoped) }
    }

    /// The same bar, on one swatch or several. They all end up with the tags left in the bar.
    private func editTags(of hexes: [String]) {
        guard let first = hexes.first else { return }
        let current = library.library.colours.first { $0.hex == first }?.tags ?? []
        let what = hexes.count == 1 ? "Tags for \(colourName(first))" : "Tags for \(plural(hexes.count, "Swatch", "Swatches"))"
        startTagging(what, tags: current) { [weak self] tags, scoped in self?.library.setTags(ofSwatches: hexes, tags, scoped: scoped) }
    }

    private func startTagging(_ what: String, tags: [String], commit: @escaping ([String], [String: UUID]) -> Void) {
        let project = paletteID.flatMap { library.library.swatch($0)?.projectID }
        tagging = true
        updateHeader()
        tagBar.begin(what, tags: tags, in: library.library, project: project, commit: commit)
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

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateHeader() }
    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateHeader() }

    /// With two or more swatches selected the name gives way to a count and the bar to actions on them.
    private func updateHeader() {
        let many = selected().count > 1
        tagBar.isHidden = !tagging
        subtitle.isHidden = tagging
        barGap.isHidden = tagging
        browsing.isHidden = many || tagging
        selecting.isHidden = !many || tagging
        let editingName = nameField.currentEditor() != nil
        nameField.isEditable = !many
        if many {
            nameField.stringValue = "\(selected().count) Swatches Selected"
            subtitle.stringValue = "Shift-click or \u{2318}-click to change the selection"
        } else {
            if !editingName { nameField.stringValue = committedName }
            subtitle.stringValue = restSubtitle
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
        }

        menu.addItem(.separator())
        add(menu, "Tags\u{2026}", #selector(Handler.tags))
        menu.addItem(.separator())
        if palette != nil { add(menu, "Remove from Palette", #selector(Handler.removeChosen)) }
        add(menu, "Delete from Library", #selector(Handler.deleteChosen))
    }

    /// The same actions as a ring for the halo, for one swatch. The menu's submenus become rings
    /// of their own, each with a way back; `show` swaps a ring into the open halo.
    static func ring(for hex: String, in palette: UUID?, library: LibraryController, editTags: (([String]) -> Void)? = nil,
                     show: @escaping ([HaloAction]) -> Void) -> [HaloAction] {
        func group(_ id: String, _ label: String, _ symbol: String, _ description: String, _ inner: @escaping () -> [HaloAction]) -> HaloAction {
            HaloAction(id: id, label: label, symbol: symbol, description: description, keepsOpen: true) {
                show(inner() + [HaloAction(id: "back", label: "Back", symbol: "arrow.uturn.backward", description: label, keepsOpen: true) {
                    show(ring(for: hex, in: palette, library: library, editTags: editTags, show: show))
                }])
            }
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
            HaloAction(id: "tags", label: "Tags\u{2026}", symbol: "tag") {
                editTags?([hex])
            },
        ]
        if let id = palette {
            actions.append(HaloAction(id: "remove", label: "Remove from Palette", symbol: "minus.circle") { library.remove([hex], from: id) })
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
        @objc func removeChosen() { if let id = palette { library.remove(hexes, from: id) } }
        @objc func deleteChosen() { library.deleteFromLibrary(hexes) }
    }
}
