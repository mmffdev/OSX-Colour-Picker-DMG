import AppKit

// ---------- All Swatches: every colour in one even grid ----------

/// One square in the grid. `bars` are the palettes whose colour runs along its bottom edge.
struct Tile: Equatable {
    let hex: String
    let bars: [UUID]
    /// Set on the first tile of a run when arranged by palette, so the bar can carry the name.
    var runTitle: String?
    var tags: [String] = []
}

/// A palette being put together from swatches already in the library.
final class PaletteDraft {
    var name = ""
    private(set) var hexes: [String] = []
    var onChange: (() -> Void)?

    func contains(_ hex: String) -> Bool { hexes.contains(hex) }

    func toggle(_ hex: String) {
        if let i = hexes.firstIndex(of: hex) { hexes.remove(at: i) } else { hexes.append(hex) }
        onChange?()
    }

    func remove(_ hex: String) {
        hexes.removeAll { $0 == hex }
        onChange?()
    }

    func clear() {
        hexes = []
        name = ""
        onChange?()
    }
}

final class TileView: NSView {
    var hex = "" { didSet { needsDisplay = true } }
    var bars: [NSColor] = [] { didSet { needsDisplay = true } }
    var runTitle: String? { didSet { needsDisplay = true } }
    var tall = false { didSet { needsDisplay = true } }
    var chosen = false { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }

    static let gap: CGFloat = 5
    static let overlap: CGFloat = 3
    static let labels: CGFloat = 34
    static func barHeight(tall: Bool) -> CGFloat { Prefs.showPaletteBars ? (tall ? 15 : 5) : 0 }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        if #available(macOS 14.0, *) { clipsToBounds = false }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let barH = TileView.barHeight(tall: tall)
        let chip = NSRect(x: TileView.gap, y: TileView.gap, width: bounds.width - TileView.gap * 2,
                          height: bounds.height - TileView.gap - TileView.labels - barH - 4)
        let shape = NSBezierPath(roundedRect: chip, xRadius: 7, yRadius: 7)
        (colorFromHex(hex) ?? .gray).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()

        if selected || chosen {
            let ring = NSBezierPath(roundedRect: chip.insetBy(dx: -2.5, dy: -2.5), xRadius: 9, yRadius: 9)
            ring.lineWidth = 3
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
        if chosen {
            let badge = NSRect(x: chip.maxX - 24, y: chip.minY + 6, width: 18, height: 18)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: badge).fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: badge.minX + 4.5, y: badge.midY + 0.5))
            tick.line(to: NSPoint(x: badge.minX + 8, y: badge.maxY - 5))
            tick.line(to: NSPoint(x: badge.maxX - 4.5, y: badge.minY + 5.5))
            tick.lineWidth = 2
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        }

        let name = Prefs.showNames ? colourName(hex) : ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex)
        let code = Prefs.showNames ? ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex) : ""
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let textX = TileView.gap + 1, textW = bounds.width - TileView.gap * 2 - 2
        (name as NSString).draw(in: NSRect(x: textX, y: chip.maxY + 5, width: textW, height: 15), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        (code as NSString).draw(in: NSRect(x: textX, y: chip.maxY + 19, width: textW, height: 13), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style])

        // The bar spans the full width so that neighbouring tiles join into one line.
        guard barH > 0, !bars.isEmpty else { return }
        // Drawn a little past each side, so a run of tiles reads as one unbroken bar.
        let band = NSRect(x: -TileView.overlap, y: bounds.height - barH, width: bounds.width + TileView.overlap * 2, height: barH)
        let each = band.width / CGFloat(bars.count)
        for (i, colour) in bars.enumerated() {
            colour.setFill()
            NSRect(x: band.minX + CGFloat(i) * each, y: band.minY, width: each + 0.5, height: band.height).fill()
        }
        if tall, let title = runTitle, let first = bars.first {
            // Black on a light bar, white on a dark one.
            let ink = hexOf(first).map { colorFromHex(readableText(on: $0)) ?? .white } ?? .white
            (title as NSString).draw(in: band.insetBy(dx: 6 + TileView.overlap, dy: 1.5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold), .foregroundColor: ink, .paragraphStyle: style])
        }
    }
}

final class TileItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("tile")
    private var tile: TileView { view as! TileView }

    override func loadView() { view = TileView() }

    override var isSelected: Bool { didSet { tile.selected = isSelected } }

    func configure(_ t: Tile, tall: Bool, chosen: Bool, palettes: (UUID) -> String?) {
        tile.hex = t.hex
        tile.bars = t.bars.map(identityColour)
        tile.runTitle = t.runTitle
        tile.tall = tall
        tile.chosen = chosen
        tile.selected = isSelected
        let names = t.bars.compactMap(palettes)
        tile.toolTip = "\(colourName(t.hex))  \(t.hex)" + (names.isEmpty ? "\nNot in a palette" : "\nIn " + names.joined(separator: ", "))
            + (t.tags.isEmpty ? "" : "\nTags: " + t.tags.joined(separator: ", "))
    }
}

final class AllSwatchesViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSMenuDelegate {
    private let library: LibraryController
    let draft = PaletteDraft()
    /// Opens or closes rail 3.
    var onBuilding: ((Bool) -> Void)?
    /// The chosen swatches changed, so rail 3 should redraw.
    var onDraftChanged: (() -> Void)?
    var onEditTags: (([String]) -> Void)?

    private(set) var building = false
    private var tiles: [Tile] = []
    private var search = ""
    private var group: ColourGroup?
    private var tag: String?
    private var shownTags: [String] = []

    private let arrange = NSPopUpButton(frame: .zero, pullsDown: false)
    private let show = NSPopUpButton(frame: .zero, pullsDown: false)
    private var buildButton: NSButton!
    private let builderBar = NSStackView()
    private let nameField = NSTextField(string: "")
    private let chosenLabel = caption("")
    private var saveButton: NSButton!
    private var builderHeight: NSLayoutConstraint!
    private let grid = SwatchGridView()
    private let scroll = NSScrollView()
    private let layout = GridLayout()
    private let empty = NSTextField(wrappingLabelWithString: "")

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        draft.onChange = { [weak self] in self?.draftChanged() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()

        for p in [arrange, show] {
            p.controlSize = .small
            p.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            p.target = self
        }
        arrange.addItems(withTitles: Arrange.allCases.map { $0.title })
        arrange.selectItem(at: Prefs.arrange.rawValue)
        arrange.action = #selector(arrangeChanged)
        show.action = #selector(showChanged)
        fillShow()

        buildButton = NSButton(title: "Build Palette\u{2026}", target: self, action: #selector(startBuilding))
        buildButton.bezelStyle = .rounded
        buildButton.controlSize = .small
        buildButton.image = symbol("rectangle.stack.badge.plus", "Build palette", size: 11)
        buildButton.imagePosition = .imageLeading
        buildButton.toolTip = "Choose swatches from the library and save them as a new palette"

        let filter = NSStackView()
        filter.orientation = .horizontal
        filter.spacing = 8
        filter.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        filter.setViews([caption("Arrange by"), arrange, caption("Show"), show], in: .leading)
        filter.setViews([buildButton], in: .trailing)

        // The builder's own bar: name, count, save.
        nameField.placeholderString = "Palette name"
        nameField.target = self
        nameField.action = #selector(savePalette)
        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        saveButton = NSButton(title: "Save Palette", target: self, action: #selector(savePalette))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(stopBuilding))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let heading = NSTextField(labelWithString: "New palette")
        heading.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        builderBar.orientation = .horizontal
        builderBar.spacing = 10
        builderBar.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        builderBar.setViews([heading, nameField, chosenLabel], in: .leading)
        builderBar.setViews([cancel, saveButton], in: .trailing)
        builderBar.wantsLayer = true
        builderBar.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        builderBar.isHidden = true

        sizeTiles()
        grid.collectionViewLayout = layout
        grid.dataSource = self
        grid.delegate = self
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.register(TileItem.self, forItemWithIdentifier: TileItem.identifier)
        grid.onClick = { [weak self] ip in self?.clicked(ip) }
        grid.onDelete = { [weak self] in self?.library.deleteFromLibrary(self?.selected() ?? []) }
        grid.onCopy = { [weak self] in self?.library.copy(self?.selected() ?? []) }
        let menu = NSMenu()
        menu.delegate = self
        grid.menu = menu

        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false


        empty.alignment = .center
        empty.textColor = .tertiaryLabelColor
        empty.font = NSFont.systemFont(ofSize: 13)

        let line = hairline()
        for v in [builderBar, filter, line, scroll, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        builderHeight = builderBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            builderBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            builderBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            builderBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            builderHeight,
            filter.topAnchor.constraint(equalTo: builderBar.bottomAnchor),
            filter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filter.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filter.heightAnchor.constraint(equalToConstant: 40),
            line.topAnchor.constraint(equalTo: filter.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
    }

    /// Tiles touch, so that their bars join up. Called whenever a setting that changes their size does.
    private func sizeTiles() {
        layout.minimumWidth = CGFloat(Prefs.tileSize.points)
        layout.spacing = 0
        layout.margins = NSEdgeInsets(top: 10, left: 14, bottom: 20, right: 14)
        let bar = TileView.barHeight(tall: Prefs.arrange == .palette)
        layout.height = { w in (w - TileView.gap * 2) * 0.82 + TileView.gap + TileView.labels + 4 + bar + 6 }
        layout.invalidateLayout()
    }

    // MARK: Contents

    func setSearch(_ text: String) {
        search = text.trimmingCharacters(in: .whitespaces).lowercased()
        reload()
    }

    /// Shows only swatches carrying the tag (nil = everything).
    func setTag(_ t: String?) {
        tag = t
        group = nil
        _ = view
        fillShow()
        reload()
    }

    /// "All Colours", the colour groups, then every tag in use.
    private func fillShow() {
        shownTags = library.library.allTags
        show.removeAllItems()
        show.addItems(withTitles: ["All Colours"] + ColourGroup.allCases.map { $0.title })
        if !shownTags.isEmpty {
            show.menu?.addItem(.separator())
            for t in shownTags { show.addItem(withTitle: "Tag: \(t)") }
        }
        if let t = tag, let i = shownTags.firstIndex(where: { $0.lowercased() == t.lowercased() }) {
            show.selectItem(at: 1 + ColourGroup.allCases.count + 1 + i)
        } else if let g = group {
            show.selectItem(at: 1 + g.rawValue)
        } else {
            show.selectItem(at: 0)
        }
    }

    func reload() {
        _ = view
        if shownTags != library.library.allTags { fillShow() }
        tiles = AllSwatchesViewController.tiles(library.library, order: library.paletteOrder, arrange: Prefs.arrange,
                                                group: group, tag: tag, search: search)
        sizeTiles()
        grid.reloadData()
        empty.isHidden = !tiles.isEmpty
        if library.library.colours.isEmpty {
            empty.stringValue = "No swatches yet.\nPress \u{2318}P to pick a colour from the screen, drop an image on the window, or paste colours with \u{21E7}\u{2318}V."
        } else {
            empty.stringValue = "No swatches match" + (search.isEmpty ? " this filter." : " \u{201C}\(search)\u{201D}.")
        }
        draftChanged()
    }

    func reveal(_ hex: String) {
        guard !building, let i = tiles.firstIndex(where: { $0.hex == hex }) else { return }
        grid.layoutSubtreeIfNeeded()
        grid.deselectAll(nil)
        grid.selectItems(at: [IndexPath(item: i, section: 0)], scrollPosition: .centeredVertically)
    }

    /// The tiles to show, in order. Pure, so it can be tested.
    static func tiles(_ lib: Library, order: [Swatch], arrange: Arrange, group: ColourGroup?, tag: String? = nil, search: String) -> [Tile] {
        let tagged = tag.map { lib.hexes(tagged: $0) }
        func holders(_ hex: String) -> [UUID] { order.filter { s in s.entries.contains { $0.hex == hex } }.map { $0.id } }
        func tagsOf(_ hex: String) -> [String] {
            (lib.colours.first { $0.hex == hex }?.tags ?? []) + order.filter { s in s.entries.contains { $0.hex == hex } }.flatMap { $0.tagList }
        }
        func matches(_ hex: String, palette: String?) -> Bool {
            if let g = group, colourGroup(hex) != g { return false }
            if let t = tagged, !t.contains(hex) { return false }
            if search.isEmpty { return true }
            return hex.lowercased().contains(search) || colourName(hex).lowercased().contains(search)
                || (palette?.lowercased().contains(search) ?? false)
                || tagsOf(hex).contains { $0.lowercased().contains(search) }
        }

        if arrange == .palette {
            var out: [Tile] = []
            for s in order {
                let run = lib.hexes(inSwatch: s.id, by: .oldest).filter { matches($0, palette: s.name) }
                for (i, hex) in run.enumerated() { out.append(Tile(hex: hex, bars: [s.id], runTitle: i == 0 ? s.name : nil, tags: tagsOf(hex))) }
            }
            let loose = lib.catalogueHexes(by: .oldest).filter { holders($0).isEmpty && matches($0, palette: nil) }
            return out + loose.map { Tile(hex: $0, bars: [], runTitle: nil, tags: tagsOf($0)) }
        }

        var hexes = lib.catalogueHexes(by: arrange == .newest ? .newest : .oldest)
        hexes = hexes.filter { hex in
            matches(hex, palette: nil) || (!search.isEmpty && group.map { colourGroup(hex) == $0 } != false
                && order.contains { s in s.name.lowercased().contains(search) && s.entries.contains { $0.hex == hex } })
        }
        func v(_ hex: String) -> (h: Double, s: Double, l: Double) { ColourValues(hex)?.hslUnit ?? (0, 0, 0) }
        func grey(_ hex: String) -> Bool { colourGroup(hex) == .neutrals }
        switch arrange {
        case .group:
            hexes.sort { a, b in
                let (ga, gb) = (colourGroup(a).rawValue, colourGroup(b).rawValue)
                if ga != gb { return ga < gb }
                return v(a).l != v(b).l ? v(a).l > v(b).l : a < b
            }
        case .hue:
            hexes.sort { a, b in
                if grey(a) != grey(b) { return !grey(a) }
                if grey(a) { return v(a).l != v(b).l ? v(a).l > v(b).l : a < b }
                return v(a).h != v(b).h ? v(a).h < v(b).h : v(a).l > v(b).l
            }
        case .lightness: hexes.sort { v($0).l != v($1).l ? v($0).l > v($1).l : $0 < $1 }
        case .saturation: hexes.sort { v($0).s != v($1).s ? v($0).s > v($1).s : $0 < $1 }
        case .name: hexes.sort { colourName($0) != colourName($1) ? colourName($0) < colourName($1) : $0 < $1 }
        case .newest, .oldest, .palette: break
        }
        return hexes.map { Tile(hex: $0, bars: Array(holders($0).prefix(4)), runTitle: nil, tags: tagsOf($0)) }
    }

    // MARK: Grid

    func numberOfSections(in cv: NSCollectionView) -> Int { 1 }
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { tiles.count }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let item = cv.makeItem(withIdentifier: TileItem.identifier, for: ip) as! TileItem
        let t = tiles[ip.item]
        item.configure(t, tall: Prefs.arrange == .palette, chosen: building && draft.contains(t.hex)) { [weak self] id in
            self?.library.library.swatch(id)?.name
        }
        return item
    }

    private func clicked(_ ip: IndexPath) {
        guard ip.item < tiles.count else { return }
        library.copy(tiles[ip.item].hex)
    }

    private func selected() -> [String] {
        var seen = Set<String>()
        return grid.selectionIndexPaths.sorted { $0.item < $1.item }
            .compactMap { $0.item < tiles.count ? tiles[$0.item].hex : nil }
            .filter { seen.insert($0).inserted }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let chosen = selected()
        guard !chosen.isEmpty, !building else { return }
        SwatchMenu.fill(menu, for: chosen, in: nil, library: library, editTags: onEditTags)
    }

    // MARK: Filter bar

    @objc private func arrangeChanged() {
        Prefs.arrange = Arrange(rawValue: arrange.indexOfSelectedItem) ?? .palette
        reload()
    }

    @objc private func showChanged() {
        let i = show.indexOfSelectedItem
        let groups = ColourGroup.allCases.count
        group = nil; tag = nil
        if i >= 1 && i <= groups { group = ColourGroup(rawValue: i - 1) }
        else if i > groups + 1 { tag = shownTags[min(i - groups - 2, shownTags.count - 1)] }
        reload()
    }

    // MARK: Building a palette

    @objc func startBuilding() {
        _ = view
        guard !building else { view.window?.makeFirstResponder(nameField); return }
        guard !library.library.colours.isEmpty else { library.flash("Pick some colours first, then build a palette from them"); return }
        building = true
        draft.clear()
        nameField.stringValue = ""
        builderBar.isHidden = false
        builderHeight.constant = 46
        buildButton.isEnabled = false
        grid.deselectAll(nil)
        grid.onToggle = { [weak self] ip in
            guard let self = self, ip.item < self.tiles.count else { return }
            self.draft.toggle(self.tiles[ip.item].hex)
        }
        onBuilding?(true)
        grid.reloadData()
        view.window?.makeFirstResponder(nameField)
        library.flash("Click swatches to add them to the new palette")
    }

    @objc func stopBuilding() {
        guard building else { return }
        building = false
        builderBar.isHidden = true
        builderHeight.constant = 0
        buildButton.isEnabled = true
        grid.onToggle = nil
        draft.clear()
        onBuilding?(false)
        grid.reloadData()
    }

    @objc func savePalette() {
        guard building else { return }
        guard !draft.hexes.isEmpty else { library.flash("Click some swatches to add them first"); NSSound.beep(); return }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexes = draft.hexes
        stopBuilding()
        let id = library.createPalette(named: typed.isEmpty ? "Custom Palette" : typed, hexes: hexes, custom: true)
        let name = id.flatMap { library.library.swatch($0)?.name } ?? "palette"
        library.flash("Saved \(name) with \(plural(hexes.count, "swatch", "swatches"))")
    }

    /// Lays the grid out afresh for its current width.
    func relayout() {
        guard isViewLoaded else { return }
        layout.invalidateLayout()
        grid.needsLayout = true
    }

    func rehearse(name: String, hexes: [String]) {
        nameField.stringValue = name
        for h in hexes { if let n = normaliseHex(h), !draft.contains(n) { draft.toggle(n) } }
    }

    private func draftChanged() {
        defer { onDraftChanged?() }
        guard isViewLoaded else { return }
        draft.name = nameField.stringValue
        chosenLabel.stringValue = building ? (draft.hexes.isEmpty ? "Click swatches to add them" : "\(plural(draft.hexes.count, "swatch", "swatches")) chosen") : ""
        saveButton.isEnabled = !draft.hexes.isEmpty
        guard building else { return }
        for ip in grid.indexPathsForVisibleItems() {
            guard ip.item < tiles.count, let item = grid.item(at: ip) as? TileItem else { continue }
            let t = tiles[ip.item]
            item.configure(t, tall: Prefs.arrange == .palette, chosen: draft.contains(t.hex)) { [weak self] id in
                self?.library.library.swatch(id)?.name
            }
        }
    }
}

// ---------- Rail 3: the palette being built ----------

final class BuilderViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let draft: PaletteDraft
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private let table = NSTableView()
    private let count = caption("")
    private let hint = NSTextField(wrappingLabelWithString: "Click swatches in the grid to add them here.")
    private var save: NSButton!

    init(draft: PaletteDraft) {
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        let title = NSTextField(labelWithString: "New Palette")
        title.font = NSFont.systemFont(ofSize: 15, weight: .bold)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 40
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        hint.alignment = .center
        hint.textColor = .tertiaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 12)

        save = NSButton(title: "Save Palette", target: self, action: #selector(saveTapped))
        save.bezelStyle = .rounded
        save.controlSize = .large
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        let buttons = NSStackView(views: [cancel, save])
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let line = hairline()
        for v in [title, count, scroll, hint, line, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            count.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            count.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: count.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor),
            hint.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            line.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
    }

    func reload() {
        guard isViewLoaded else { return }
        table.reloadData()
        count.stringValue = plural(draft.hexes.count, "swatch", "swatches")
        hint.isHidden = !draft.hexes.isEmpty
        save.isEnabled = !draft.hexes.isEmpty
        if draft.hexes.count > 0 { table.scrollRowToVisible(draft.hexes.count - 1) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { draft.hexes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hex = draft.hexes[row]
        let cell = NSView()
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 6
        chip.layer?.backgroundColor = colorFromHex(hex)?.cgColor
        chip.layer?.borderWidth = 1
        chip.layer?.borderColor = NSColor.separatorColor.cgColor
        let name = NSTextField(labelWithString: colourName(hex))
        name.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let code = NSTextField(labelWithString: ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex))
        code.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        code.textColor = .secondaryLabelColor
        let remove = symbolButton("xmark.circle.fill", tooltip: "Remove from the new palette", target: self, action: #selector(removeTapped(_:)))
        remove.tag = row
        remove.contentTintColor = .tertiaryLabelColor

        let text = NSStackView(views: [name, code])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        for v in [chip, text, remove] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            chip.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            chip.widthAnchor.constraint(equalToConstant: 28),
            chip.heightAnchor.constraint(equalToConstant: 28),
            text.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -4),
            remove.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            remove.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func removeTapped(_ sender: NSButton) {
        guard sender.tag < draft.hexes.count else { return }
        draft.remove(draft.hexes[sender.tag])
    }

    @objc private func saveTapped() { onSave?() }
    @objc private func cancelTapped() { onCancel?() }
}
