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
    /// What is written under the chip, top to bottom; set from Prefs when the grid is sized.
    static var shown: [String] = ["name", "hex"]
    /// Offered in the Labels menu, in this order.
    static let labelChoices: [(key: String, title: String)] = [("name", "Name")]
        + ColourFormat.cardRows.map { ($0.rawValue, $0.label) }
    static var labels: CGFloat { shown.isEmpty ? 2 : 8 + shown.reduce(0) { $0 + ($1 == "name" ? 15 : 13) } }
    /// Room for the "RGB", "BT.2020" column in front of each value.
    static let labelColumn: CGFloat = 44
    /// How wide a tile must be to show its widest value whole, with its label and copy mark.
    static var widthNeeded: CGFloat {
        let longest = shown.compactMap { ColourFormat(rawValue: $0) }.map { format -> Int in
            switch format {
            case .hex: return 7
            case .hsl, .hsv: return 14
            case .cmyk, .lab: return 18
            default: return 13
            }
        }.max()
        guard let characters = longest else { return 0 }
        return gap * 2 + 2 + labelColumn + CGFloat(characters) * 5.8 + 16
    }

    /// A copy mark was pressed: "name" or a ColourFormat raw value.
    var onCopy: ((String) -> Void)?
    private var pressed: String?

    /// The lines under the chip, top to bottom, each with the square its copy mark sits in.
    private func lines() -> [(key: String, row: NSRect, mark: NSRect)] {
        let chipBottom = bounds.height - TileView.labels - TileView.barHeight(tall: tall) - 4
        var y = chipBottom + 5
        return TileView.shown.map { key in
            let h: CGFloat = key == "name" ? 15 : 13
            let row = NSRect(x: TileView.gap + 1, y: y, width: bounds.width - TileView.gap * 2 - 2, height: h)
            y += h
            return (key, row, NSRect(x: row.maxX - 13, y: row.minY, width: 13, height: h))
        }
    }

    // A press on a copy mark copies that line; anywhere else goes on to the grid, to select.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressed = lines().first { $0.mark.insetBy(dx: -3, dy: 0).contains(p) }?.key
        if pressed == nil { super.mouseDown(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let key = pressed else { super.mouseUp(with: event); return }
        pressed = nil
        let p = convert(event.locationInWindow, from: nil)
        if lines().contains(where: { $0.key == key && $0.mark.insetBy(dx: -3, dy: 0).contains(p) }) { onCopy?(key) }
    }
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

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let mark = symbol("doc.on.doc", "Copy", size: 8)
        for line in lines() {
            let text = NSRect(x: line.row.minX, y: line.row.minY, width: line.row.width - 16, height: line.row.height)
            if line.key == "name" {
                (colourName(hex) as NSString).draw(in: text, withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
            } else if let format = ColourFormat(rawValue: line.key) {
                (format.label as NSString).draw(in: NSRect(x: text.minX, y: text.minY + 1, width: TileView.labelColumn, height: text.height), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 8.5, weight: .bold), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: style])
                (format.text(hex, lowercase: Prefs.lowercaseHex) as NSString).draw(
                    in: NSRect(x: text.minX + TileView.labelColumn, y: text.minY, width: text.width - TileView.labelColumn, height: text.height), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style])
            }
            // The copy mark, tinted to sit back from the text.
            if let ctx = NSGraphicsContext.current?.cgContext {
                let size = mark.size, box = NSRect(x: line.mark.midX - size.width / 2, y: line.mark.midY - size.height / 2, width: size.width, height: size.height)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                mark.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSColor.tertiaryLabelColor.setFill()
                box.insetBy(dx: -1, dy: -1).fill(using: .sourceAtop)
                ctx.endTransparencyLayer()
            }
        }

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

    func configure(_ t: Tile, tall: Bool, chosen: Bool, onCopy: @escaping (String) -> Void, palettes: (UUID) -> String?) {
        tile.onCopy = onCopy
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
    private let tagBar = TagBar()
    private let barGap = NSView()
    private var tagging = false
    /// What the swatch menu calls to tag swatches: the page's own tag bar.
    private lazy var onEditTags: ([String]) -> Void = { [weak self] hexes in self?.editTags(of: hexes) }

    private(set) var building = false
    private var tiles: [Tile] = []
    private var search = ""
    private var group: ColourGroup?
    private var tag: String?
    private var shownTags: [String] = []
    private enum ProjectFilter: Equatable { case all, loose, project(UUID) }
    private var projectFilter = ProjectFilter.all
    private var shownProjects: [Project] = []

    private let arrange = NSPopUpButton(frame: .zero, pullsDown: false)
    private let show = NSPopUpButton(frame: .zero, pullsDown: false)
    private let projects = NSPopUpButton(frame: .zero, pullsDown: false)
    private let labels = PopoverButton(title: "Labels")
    private var labelsPopover = NSPopover()
    private var labelChecks: [NSButton] = []
    private let addTo = NSPopUpButton(frame: .zero, pullsDown: true)
    private let titleLabel = NSTextField(labelWithString: "All Swatches")
    private let subtitle = caption("")
    /// The bar's right-hand side: filters while browsing, actions while several swatches are selected.
    private let browsing = NSStackView()
    private let selecting = NSStackView()
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

        for p in [arrange, show, projects, addTo] {
            p.controlSize = .small
            p.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            p.target = self
        }
        arrange.addItems(withTitles: Arrange.allCases.map { $0.title })
        arrange.selectItem(at: Prefs.arrange.rawValue)
        arrange.action = #selector(arrangeChanged)
        show.action = #selector(showChanged)
        fillShow()
        projects.action = #selector(projectChanged)
        fillProjects()
        projects.toolTip = "Show only the swatches in one project\u{2019}s palettes"
        labels.target = self
        labels.action = #selector(showLabels)
        labels.toolTip = "Choose what is written under each swatch"
        // Ticks in a popover rather than a menu, so it stays open while several are chosen.
        labelChecks = TileView.labelChoices.enumerated().map { at, choice in
            let box = NSButton(checkboxWithTitle: choice.title, target: self, action: #selector(labelToggled(_:)))
            box.tag = at
            return box
        }
        labelsPopover = tickPopover(labelChecks)
        addTo.addItem(withTitle: "Add to Palette")
        addTo.menu?.delegate = self

        buildButton = NSButton(title: "Build Palette\u{2026}", target: self, action: #selector(startBuilding))
        buildButton.bezelStyle = .rounded
        buildButton.controlSize = .small
        buildButton.image = symbol("rectangle.stack.badge.plus", "Build palette", size: 11)
        buildButton.imagePosition = .imageLeading
        buildButton.toolTip = "Choose swatches from the library and save them as a new palette"

        // Same shape as a palette page: the title on its own row, then the count on the left and the
        // controls on the right. With several swatches selected, the controls give way to actions.
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        func small(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.toolTip = tip
            return b
        }
        arrange.toolTip = "Arrange by"
        show.toolTip = "Show a colour group or a tag"
        buildButton.title = ""
        buildButton.imagePosition = .imageOnly
        buildButton.setAccessibilityLabel("Build Palette")
        browsing.setViews([arrange, show, projects, labels, buildButton], in: .leading)
        selecting.setViews([small("Copy", #selector(copySelected), "Copy the selected swatches"), addTo,
                            symbolButton("tag", tooltip: "Tag the selected swatches", target: self, action: #selector(tagSelected)),
                            small("Delete", #selector(deleteSelected), "Delete the selected swatches from the library"),
                            small("Deselect", #selector(deselect), "Clear the selection")], in: .leading)
        for bar in [browsing, selecting] {
            bar.orientation = .horizontal
            bar.spacing = 8
        }
        selecting.isHidden = true
        let gap = barGap
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagBar.isHidden = true
        tagBar.onClose = { [weak self] in
            self?.tagging = false
            self?.updateHeader()
            self?.view.window?.makeFirstResponder(self?.grid)
        }
        let bar = NSStackView(views: [subtitle, gap, browsing, selecting, tagBar])
        bar.orientation = .horizontal
        bar.spacing = 12
        bar.alignment = .centerY
        let filter = NSStackView(views: [titleLabel, bar])
        filter.orientation = .vertical
        filter.alignment = .leading
        filter.spacing = 2
        filter.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        NSLayoutConstraint.activate([
            titleLabel.trailingAnchor.constraint(equalTo: filter.trailingAnchor, constant: -20),
            bar.trailingAnchor.constraint(equalTo: filter.trailingAnchor, constant: -20),
        ])

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

        for v in [builderBar, filter, scroll, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        builderHeight = builderBar.heightAnchor.constraint(equalToConstant: 0)
        // 66 points unless its contents need more; never left to stretch into the page below.
        let filterHeight = filter.heightAnchor.constraint(equalToConstant: 66)
        filterHeight.priority = .defaultHigh
        // The title sits on the same line as every other page's, unless the builder bar needs the room.
        let titleLine = titleLabel.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: PageLayout.titleCentre)
        titleLine.priority = .defaultHigh
        NSLayoutConstraint.activate([
            builderBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            builderBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            builderBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            builderHeight,
            filter.topAnchor.constraint(greaterThanOrEqualTo: builderBar.bottomAnchor, constant: 6),
            titleLine,
            filter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filter.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filter.heightAnchor.constraint(greaterThanOrEqualToConstant: 66),   // taller while the tag bar shows its second row
            filterHeight,
            scroll.topAnchor.constraint(equalTo: filter.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
    }

    /// Tiles touch, so that their bars join up. Called whenever a setting that changes their size does.
    override func viewDidLayout() {
        super.viewDidLayout()
        layout.fitVisibleWidth()
    }

    private func sizeTiles() {
        TileView.shown = Prefs.tileLabels
        // Wide enough for the chosen size and for the longest value written under a tile.
        layout.minimumWidth = max(CGFloat(Prefs.tileSize.points), TileView.widthNeeded)
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
        if shownProjects != library.library.orderedProjects { fillProjects() }
        // A project filter narrows both the palettes that are walked and the swatches that count.
        var order = library.paletteOrder
        var only: Set<String>?
        if projectFilter != .all {
            let wanted: UUID? = { if case .project(let id) = projectFilter { return id } else { return nil } }()
            order = order.filter { $0.projectID == wanted }
            only = Set(order.flatMap { $0.entries.map { $0.hex } })
        }
        tiles = AllSwatchesViewController.tiles(library.library, order: order, arrange: Prefs.arrange,
                                                group: group, tag: tag, only: only, search: search)
        sizeTiles()
        grid.reloadData()
        updateHeader()
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
    static func tiles(_ lib: Library, order: [Swatch], arrange: Arrange, group: ColourGroup?, tag: String? = nil,
                      only: Set<String>? = nil, search: String) -> [Tile] {
        let tagged = tag.map { lib.hexes(tagged: $0) }
        func holders(_ hex: String) -> [UUID] { order.filter { s in s.entries.contains { $0.hex == hex } }.map { $0.id } }
        func tagsOf(_ hex: String) -> [String] {
            (lib.colours.first { $0.hex == hex }?.tags ?? []) + order.filter { s in s.entries.contains { $0.hex == hex } }.flatMap { $0.tagList }
        }
        func matches(_ hex: String, palette: String?) -> Bool {
            if let g = group, colourGroup(hex) != g { return false }
            if let t = tagged, !t.contains(hex) { return false }
            if let o = only, !o.contains(hex) { return false }
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
            matches(hex, palette: nil) || only?.contains(hex) != false && (!search.isEmpty && group.map { colourGroup(hex) == $0 } != false
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
        item.configure(t, tall: Prefs.arrange == .palette, chosen: building && draft.contains(t.hex), onCopy: copier(t.hex)) { [weak self] id in
            self?.library.library.swatch(id)?.name
        }
        return item
    }

    /// What a tile's copy marks do: copy the name, or the colour in that line's format.
    private func copier(_ hex: String) -> (String) -> Void {
        { [weak self] key in
            if let format = ColourFormat(rawValue: key) { self?.library.copy(hex, as: format); return }
            copyToClipboard(colourName(hex))
            self?.library.flash("Copied \(colourName(hex))")
        }
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

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateHeader() }
    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateHeader() }

    /// The title, the count line, and which side of the bar is showing.
    private func updateHeader() {
        let chosen = building ? [] : selected()
        let many = chosen.count > 1
        tagBar.isHidden = !tagging
        subtitle.isHidden = tagging
        barGap.isHidden = tagging
        browsing.isHidden = many || tagging
        selecting.isHidden = !many || tagging
        if many {
            titleLabel.stringValue = "\(chosen.count) Swatches Selected"
            subtitle.stringValue = "Shift-click or \u{2318}-click to change the selection"
            return
        }
        titleLabel.stringValue = "All Swatches"
        let total = library.library.colours.count, showing = Set(tiles.map { $0.hex }).count
        var parts = [plural(total, "Swatch", "Swatches")]
        if showing != total { parts.append("\(showing) Shown") }
        if let t = tag { parts.append("Tagged \(t)") }
        subtitle.stringValue = parts.joined(separator: "  \u{00B7}  ")
    }

    @objc private func copySelected() { library.copy(selected()) }
    @objc private func deleteSelected() { library.deleteFromLibrary(selected()) }
    @objc private func deselect() { grid.deselectAll(nil); updateHeader() }
    @objc private func tagSelected() { editTags(of: selected()) }

    /// Swaps the action bar for the tag bar, on one swatch or several. They all end up with the tags left in the bar.
    private func editTags(of hexes: [String]) {
        guard let first = hexes.first else { return }
        let current = library.library.colours.first { $0.hex == first }?.tags ?? []
        let what = hexes.count == 1 ? "Tags for \(colourName(first))" : "Tags for \(plural(hexes.count, "Swatch", "Swatches"))"
        tagging = true
        updateHeader()
        tagBar.begin(what, tags: current, in: library.library, projects: library.library.projects(holdingAll: hexes)) { [weak self] tags, scoped in
            self?.library.setTags(ofSwatches: hexes, tags, scoped: scoped)
        }
    }
    @objc private func addSelected(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { library.add(selected(), to: id) }
        else { library.createPalette(named: "", hexes: selected(), rename: true) }
    }

    func rehearseLabels() { showLabels() }

    @objc private func showLabels() {
        if labelsPopover.isShown { labelsPopover.close(); return }
        let on = Prefs.tileLabels
        for (box, choice) in zip(labelChecks, TileView.labelChoices) { box.state = on.contains(choice.key) ? .on : .off }
        labelsPopover.show(relativeTo: labels.bounds, of: labels, preferredEdge: .maxY)
    }

    @objc private func labelToggled(_ sender: NSButton) {
        Prefs.tileLabels = zip(labelChecks, TileView.labelChoices).filter { $0.0.state == .on }.map { $0.1.key }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === addTo.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: "Add to Palette", action: nil, keyEquivalent: "")
            for s in library.paletteOrder {
                let item = menu.addItem(withTitle: s.name, action: #selector(addSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.id
            }
            if !library.paletteOrder.isEmpty { menu.addItem(.separator()) }
            menu.addItem(withTitle: "New Palette", action: #selector(addSelected(_:)), keyEquivalent: "").target = self
            return
        }
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

    /// "All Projects", each project, then the palettes in none. Hidden while there are no projects.
    private func fillProjects() {
        shownProjects = library.library.orderedProjects
        if case .project(let id) = projectFilter, !shownProjects.contains(where: { $0.id == id }) { projectFilter = .all }
        projects.removeAllItems()
        projects.addItem(withTitle: "All Projects")
        for p in shownProjects {
            projects.addItem(withTitle: p.name)
            projects.lastItem?.representedObject = p.id
        }
        projects.menu?.addItem(.separator())
        projects.addItem(withTitle: "Not in a Project")
        projects.isHidden = shownProjects.isEmpty
        if shownProjects.isEmpty { projectFilter = .all }
        switch projectFilter {
        case .all: projects.selectItem(at: 0)
        case .loose: projects.selectItem(at: projects.numberOfItems - 1)
        case .project(let id): projects.selectItem(at: 1 + (shownProjects.firstIndex { $0.id == id } ?? 0))
        }
    }

    @objc private func projectChanged() {
        if let id = projects.selectedItem?.representedObject as? UUID { projectFilter = .project(id) }
        else { projectFilter = projects.indexOfSelectedItem == 0 ? .all : .loose }
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
        chosenLabel.stringValue = building ? (draft.hexes.isEmpty ? "Click swatches to add them" : "\(plural(draft.hexes.count, "Swatch", "Swatches")) chosen") : ""
        saveButton.isEnabled = !draft.hexes.isEmpty
        guard building else { return }
        for ip in grid.indexPathsForVisibleItems() {
            guard ip.item < tiles.count, let item = grid.item(at: ip) as? TileItem else { continue }
            let t = tiles[ip.item]
            item.configure(t, tall: Prefs.arrange == .palette, chosen: draft.contains(t.hex), onCopy: copier(t.hex)) { [weak self] id in
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
        hint.font = NSFont.systemFont(ofSize: TextSize.body)

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
        count.stringValue = plural(draft.hexes.count, "Swatch", "Swatches")
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
        name.font = NSFont.systemFont(ofSize: TextSize.body, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let code = NSTextField(labelWithString: ColourFormat.hex.text(hex, lowercase: Prefs.lowercaseHex))
        code.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
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
