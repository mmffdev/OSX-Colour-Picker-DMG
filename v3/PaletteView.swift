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
            label.widthAnchor.constraint(equalToConstant: 40),
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

final class ColourCard: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("card")
    /// The narrowest a card gets; they widen to fill the row.
    static let width: CGFloat = 228

    /// Height for the rows and extras switched on in Settings.
    static var height: CGFloat {
        68 + CGFloat(Prefs.cardRows.count) * 25 + (Prefs.showContrast ? 30 : 0) + 12
    }

    var onCopyRow: ((ColourFormat) -> Void)?
    weak var library: LibraryController?
    private(set) var hex = ""
    private let name = NSTextField(labelWithString: "")
    private let code = NSTextField(labelWithString: "")
    private let rows = NSStackView()
    private let contrast = NSTextField(labelWithString: "")
    private let ring = CAShapeLayer()

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
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .leading

        for s in [name, code, rows, contrast] as [NSView] {
            s.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(s)
        }
        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: v.topAnchor, constant: 14),
            name.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            name.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            code.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            code.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            rows.topAnchor.constraint(equalTo: v.topAnchor, constant: 68),
            rows.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            contrast.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            contrast.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            contrast.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14),
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
    var onEditTags: (([String]) -> Void)?

    private(set) var paletteID: UUID?
    private var hexes: [String] = []
    private var search = ""

    private let nameField = NSTextField(labelWithString: "")
    private let subtitle = caption("")
    private var star: NSButton!
    private var target: NSButton!
    private let sort = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tagsField = NSTokenField(frame: .zero)
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

    override func loadView() {
        view = NSView()

        nameField.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.isEditable = true
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.delegate = self
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        star = symbolButton("star", tooltip: "Add to Favourites", target: self, action: #selector(starTapped))
        target = symbolButton("eyedropper", tooltip: "Send picks here", target: self, action: #selector(targetTapped))
        let copyAll = symbolButton("doc.on.doc", tooltip: "Copy every swatch in this palette", target: self, action: #selector(copyAllTapped))

        sort.addItems(withTitles: ["Order Added", "Newest First", "Colour Order"])
        sort.controlSize = .small
        sort.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        sort.target = self
        sort.action = #selector(sortChanged)

        tagsField.tokenStyle = .rounded
        tagsField.placeholderString = "Add tags\u{2026}"
        tagsField.isBordered = false
        tagsField.drawsBackground = false
        tagsField.focusRingType = .none
        tagsField.font = NSFont.systemFont(ofSize: 11)
        tagsField.controlSize = .small
        tagsField.delegate = self
        tagsField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        tagsField.toolTip = "Tags for this palette. Separate with commas; press Return to save."

        let titles = NSStackView(views: [nameField, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        header.setViews([titles], in: .leading)
        header.setViews([tagsField, star, target, copyAll, sort], in: .trailing)

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

        for v in [header, scroll, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 58),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
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
        let isTarget = library.library.activeSwatchID == id
        var parts = [plural(s.entries.count, "swatch", "swatches")]
        if !search.isEmpty { parts.append("\(hexes.count) shown") }
        if s.custom { parts.append("custom palette") }
        if isTarget { parts.append("picks go here") }
        subtitle.stringValue = parts.joined(separator: "  \u{00B7}  ")

        if tagsField.currentEditor() == nil { tagsField.objectValue = s.tagList }
        star.image = symbol(s.favourite ? "star.fill" : "star", "Favourite")
        star.contentTintColor = s.favourite ? .systemYellow : .secondaryLabelColor
        star.toolTip = s.favourite ? "Remove from Favourites" : "Add to Favourites"
        target.contentTintColor = isTarget ? .controlAccentColor : .secondaryLabelColor
        target.toolTip = isTarget ? "New picks are added to this palette. Click to stop." : "Send new picks to this palette"
        sort.selectItem(at: [SortOrder.oldest, .newest, .colour].firstIndex(of: library.paletteSort) ?? 0)

        sizeCards()
        grid.reloadData()

        empty.isHidden = !hexes.isEmpty
        empty.stringValue = !search.isEmpty ? "No swatches in this palette match \u{201C}\(search)\u{201D}."
            : "No swatches yet.\nPress \u{2318}P to pick colours into this palette, or drop an image on the window."
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
        return card
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

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let id = paletteID else { return }
        if (obj.object as? NSTokenField) === tagsField {
            library.setTags(ofPalette: id, (tagsField.objectValue as? [String]) ?? [])
            return
        }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == committedName { nameField.stringValue = committedName; return }
        committedName = typed
        library.rename(id, to: typed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === tagsField {
            if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
                view.window?.makeFirstResponder(grid)
                return true
            }
            return false
        }
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
        let chosen = selected()
        guard !chosen.isEmpty else { return }
        SwatchMenu.fill(menu, for: chosen, in: paletteID, library: library, editTags: onEditTags)
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

    final class Handler: NSObject {
        let hexes: [String], palette: UUID?, library: LibraryController
        var editTags: (([String]) -> Void)?
        init(hexes: [String], palette: UUID?, library: LibraryController) {
            self.hexes = hexes; self.palette = palette; self.library = library
        }

        @objc func copyChosen() { library.copy(hexes) }
        @objc func tags() { if let e = editTags { e(hexes) } else { library.editTags(ofSwatches: hexes) } }
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
