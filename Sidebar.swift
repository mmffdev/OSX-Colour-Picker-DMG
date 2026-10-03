import AppKit

// ---------- Rail 1: library, favourites, projects with their palettes, loose palettes, tags ----------

final class SidebarNode: NSObject {
    enum Kind: Equatable {
        case favourites, library, loose, tags
        /// The "cTools" heading, over the tools that work on colours already chosen.
        case tools
        /// The "Projects" heading; each project sits under it with its palettes inside.
        case projects
        case project(UUID)
        case all
        /// cLab, under All Swatches.
        case lab
        /// Contrast, under cTools.
        case contrast
        case tag(String)
        /// The "Edit Tags…" row at the foot of the tag list.
        case editTags
        /// The "Tags" bucket at the foot of a project, holding the tags that belong to it.
        case projectTags(UUID)
        /// The "Typography" heading, over every Typography palette.
        case typography
        /// The "Typography" bucket inside a project, above its tags, holding its Typography palettes.
        case projectTypography(UUID)
        case palette(UUID)
    }

    let kind: Kind
    var children: [SidebarNode] = []

    init(_ kind: Kind) { self.kind = kind }

    var isGroup: Bool {
        switch kind {
        case .favourites, .library, .loose, .tags, .projects, .tools, .typography: return true
        default: return false
        }
    }

    /// Headings open and close, and so do projects and the tag bucket inside each.
    var isExpandable: Bool {
        if case .projectTags = kind { return true }
        if case .projectTypography = kind { return true }
        return isGroup || projectID != nil
    }

    var paletteID: UUID? { if case .palette(let id) = kind { return id }; return nil }
    var projectID: UUID? { if case .project(let id) = kind { return id }; return nil }
    var tag: String? { if case .tag(let t) = kind { return t }; return nil }
}

let paletteDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.palette")
let projectDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.project")

/// A palette row: favourite star, a small strip of its colours, name, pick mark, count, then a gear that opens the palette's menu.
final class PaletteCell: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("palette")

    var onRename: ((String) -> Void)?
    /// The gear was pressed; hands over the button so the menu can open under it.
    var onGear: ((NSView) -> Void)?
    var onStar: (() -> Void)?

    private let strip = SpectrumView()
    private var star: NSButton!
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let target = NSImageView()
    private var committed = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.isEditable = true
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.delegate = self
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = name

        count.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .tertiaryLabelColor
        strip.radius = 3
        strip.outlinesWhenEmpty = true
        target.image = symbol("eyedropper", "Picks go here", size: 10)
        target.contentTintColor = .controlAccentColor
        target.toolTip = "New picks are added to this palette"
        let gear = symbolButton("gearshape", tooltip: "Palette actions", target: self, action: #selector(gearTapped(_:)))
        gear.image = symbol("gearshape", "Palette actions", size: 11)
        gear.contentTintColor = .tertiaryLabelColor

        star = symbolButton("star", tooltip: "Add to Favourites", target: self, action: #selector(starTapped))

        let stack = NSStackView(views: [star, strip, name, target, count, gear])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.setCustomSpacing(8, after: count)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            strip.widthAnchor.constraint(equalToConstant: 36),
            strip.heightAnchor.constraint(equalToConstant: 12),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: Swatch, isTarget: Bool) {
        committed = s.name
        name.stringValue = s.name
        strip.hexes = s.entries.map { $0.hex }
        star.image = symbol(s.favourite ? "star.fill" : "star", "Favourite", size: 11)
        star.contentTintColor = s.favourite ? .systemYellow : .tertiaryLabelColor
        star.toolTip = (s.favourite ? "Remove from Favourites" : "Add to Favourites") + " (\u{21E7}F)"
        count.stringValue = "\(s.styles?.count ?? s.entries.count)"   // a Typography palette counts its pairings
        target.isHidden = !isTarget
        toolTip = s.tagList.isEmpty ? nil : "Tags: " + s.tagList.joined(separator: ", ")
    }

    func beginRenaming() { window?.makeFirstResponder(name) }

    @objc private func gearTapped(_ sender: NSButton) { onGear?(sender) }
    @objc private func starTapped() { onStar?() }

    func controlTextDidEndEditing(_ obj: Notification) {
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == committed { name.stringValue = committed; return }
        committed = typed
        onRename?(typed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        name.abortEditing()
        name.stringValue = committed
        window?.makeFirstResponder(superview?.superview)
        return true
    }
}

/// A row with a plus button: a project (new palette inside it) or the Projects heading (new project).
final class ProjectHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("project")
    var onAdd: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let folder = NSImageView()
    private var add: NSButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = title
        folder.image = symbol("folder", "Project", size: 12)
        folder.contentTintColor = .secondaryLabelColor
        add = symbolButton("plus.circle", tooltip: "New palette in this project", target: self, action: #selector(addTapped))
        add.image = symbol("plus.circle", "", size: 12)
        add.contentTintColor = .tertiaryLabelColor
        add.imagePosition = .imageOnly
        let stack = NSStackView(views: [folder, title, add])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The plus sits on the title's own middle line, whatever height the button would take.
            add.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 16),
            add.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, heading: Bool = false, tooltip: String) {
        title.stringValue = name
        title.font = heading ? SidebarOutlineView.headingFont : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        title.textColor = .labelColor
        folder.isHidden = heading
        add.toolTip = tooltip
        add.setAccessibilityLabel(tooltip)
    }
    @objc private func addTapped() { onAdd?() }
}

final class SidebarOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?
    /// Shift-F on a row.
    var onFavouriteKey: (() -> Void)?

    // A project's tag bucket, and the tags inside it, sit one step further in, so the bucket's
    // disclosure arrow lines up under the stars of the palettes above it.
    private static let bucketInset: CGFloat = 16
    /// Bold and in the full text colour: grey headings were hard to read over a dark sidebar.
    static let headingFont = NSFont.systemFont(ofSize: 11, weight: .bold)

    // A click anywhere on a row that opens and closes does so, not only one on its arrow. A drag
    // still drags, and the arrow and the plus button keep their own clicks.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p)
        let node = item(atRow: row) as? SidebarNode
        let onArrow = row >= 0 && frameOfOutlineCell(atRow: row).insetBy(dx: -4, dy: 0).contains(p)
        let onButton = hitTest(superview?.convert(p, from: self) ?? p) is NSButton
        super.mouseDown(with: event)
        guard let bucket = node, bucket.isExpandable, !onArrow, !onButton, event.clickCount == 1,
              let now = window?.mouseLocationOutsideOfEventStream,
              hypot(now.x - event.locationInWindow.x, now.y - event.locationInWindow.y) < 4 else { return }
        if isItemExpanded(bucket) { animator().collapseItem(bucket) } else { animator().expandItem(bucket) }
    }

    private func isInTagBucket(_ row: Int) -> Bool {
        guard let node = item(atRow: row) as? SidebarNode else { return false }
        // A project's Tags and Typography buckets are inset alike, and so is what they hold.
        func bucket(_ kind: SidebarNode.Kind?) -> Bool {
            switch kind {
            case .projectTags?, .projectTypography?: return true
            default: return false
            }
        }
        return bucket(node.kind) || bucket((parent(forItem: node) as? SidebarNode)?.kind)
    }

    /// The space left under each main section, held as empty room at the top of the next heading's row.
    static let sectionGap: CGFloat = 20

    /// A main heading other than the first: its row is taller, and its contents sit at the bottom of it.
    private func hasGapAbove(_ row: Int) -> Bool { row > 0 && level(forRow: row) == 0 }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        if isInTagBucket(row) { frame.origin.x += SidebarOutlineView.bucketInset }
        if hasGapAbove(row) { frame.origin.y += SidebarOutlineView.sectionGap; frame.size.height -= SidebarOutlineView.sectionGap }
        return frame
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        if isInTagBucket(row) {
            frame.origin.x += SidebarOutlineView.bucketInset
            frame.size.width -= SidebarOutlineView.bucketInset
        }
        if hasGapAbove(row) { frame.origin.y += SidebarOutlineView.sectionGap; frame.size.height -= SidebarOutlineView.sectionGap }
        return frame
    }

    override func keyDown(with event: NSEvent) {
        let held = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 51 || event.keyCode == 117 { onDeleteKey?() }
        else if event.keyCode == 3, held == .shift { onFavouriteKey?() }
        else { super.keyDown(with: event) }
    }
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let library: LibraryController
    var onSelect: ((Selection) -> Void)?
    var onExport: ((UUID) -> Void)?
    var onColourPanel: ((UUID) -> Void)?
    var onAdobe: ((AdobeSend) -> Void)?
    var onDesignPack: ((Selection) -> Void)?

    private let outline = SidebarOutlineView()
    private let favourites = SidebarNode(.favourites)
    private let libraryGroup = SidebarNode(.library)
    private let toolsGroup = SidebarNode(.tools)
    private let typography = SidebarNode(.typography)
    private var typeBuckets: [UUID: SidebarNode] = [:]
    private let projectsGroup = SidebarNode(.projects)
    private var tagBuckets: [UUID: SidebarNode] = [:]
    private let loose = SidebarNode(.loose)
    private let tags = SidebarNode(.tags)
    private var projectNodes: [UUID: SidebarNode] = [:]
    private var roots: [SidebarNode] = []
    private var selection: Selection = .all
    private var settingSelection = false

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        libraryGroup.children = [SidebarNode(.all), SidebarNode(.lab)]
        toolsGroup.children = [SidebarNode(.contrast)]
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = 8
        outline.registerForDraggedTypes([paletteDragType, projectDragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.onDeleteKey = { [weak self] in
            guard let self = self, let id = (self.outline.item(atRow: self.outline.selectedRow) as? SidebarNode)?.paletteID else { return }
            self.library.delete(palette: id)
        }

        // Shift-F stars the selected palette, or every palette in the selected project.
        outline.onFavouriteKey = { [weak self] in
            guard let self = self, let node = self.outline.item(atRow: self.outline.selectedRow) as? SidebarNode else { return }
            if let id = node.paletteID { self.library.toggleFavourite(id) }
            else if let id = node.projectID { self.library.toggleFavourites(inProject: id) }
        }

        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        view = scroll
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    /// The list starts below the toolbar, set down so that the first row's middle is on the pages' title line.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scroll = view as? NSScrollView else { return }
        let extra = PageLayout.titleCentre - 14 // the first row is 28 points tall
        let top = view.safeAreaInsets.top + extra
        if scroll.automaticallyAdjustsContentInsets || scroll.contentInsets.top != top {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            scroll.scrollerInsets = NSEdgeInsets(top: -extra, left: 0, bottom: 0, right: 0)
        }
    }

    // MARK: Contents

    func reload() {
        let lib = library.library
        favourites.children = library.favourites.map { SidebarNode(.palette($0.id)) }
        var projects: [SidebarNode] = [], buckets: [SidebarNode] = []
        for p in lib.orderedProjects {
            let node = projectNodes[p.id] ?? SidebarNode(.project(p.id))
            projectNodes[p.id] = node
            let held = lib.palettes(in: p.id)
            node.children = held.filter { !$0.isTypography }.map { SidebarNode(.palette($0.id)) }
            // Its Typography palettes sit in a bucket of their own, above its tags.
            let type = held.filter { $0.isTypography }
            if !type.isEmpty {
                let bucket = typeBuckets[p.id] ?? SidebarNode(.projectTypography(p.id))
                typeBuckets[p.id] = bucket
                bucket.children = type.map { SidebarNode(.palette($0.id)) }
                node.children.append(bucket)
                buckets.append(bucket)
            }
            // The project's own tags sit in a bucket of their own, under its palettes.
            let own = lib.allTags.filter { lib.project(ofTag: $0) == p.id }
            if !own.isEmpty {
                let bucket = tagBuckets[p.id] ?? SidebarNode(.projectTags(p.id))
                tagBuckets[p.id] = bucket
                bucket.children = own.map { SidebarNode(.tag($0)) }
                node.children.append(bucket)
                buckets.append(bucket)
            }
            projects.append(node)
        }
        // The Palettes list holds every palette. One that lives in a project shows here as well as
        // under its project (the same palette, not a copy). The list keeps an order of its own.
        loose.children = lib.listedPalettes.filter { !$0.isTypography }.map { SidebarNode(.palette($0.id)) }
        // Typography palettes have a list of their own, kept in order the same way.
        typography.children = lib.listedPalettes.filter { $0.isTypography }.map { SidebarNode(.palette($0.id)) }
        // Every tag, global or not, for quick access; a project's own also sit in its bucket above.
        tags.children = lib.allTags.map { SidebarNode(.tag($0)) } + [SidebarNode(.editTags)]
        projectsGroup.children = projects
        roots = [libraryGroup, toolsGroup, favourites, projectsGroup, loose, typography, tags]

        settingSelection = true
        outline.reloadData()
        for group in roots + projects + buckets where !isCollapsed(group) { outline.expandItem(group) }
        settingSelection = false
        select(selection)
    }

    private func key(_ node: SidebarNode) -> String {
        if let id = node.projectID { return "sidebarCollapsed.project.\(id.uuidString)" }
        return "sidebarCollapsed.\(node.kind)"
    }
    private func isCollapsed(_ node: SidebarNode) -> Bool { preferences.bool(forKey: key(node)) }

    /// Highlights the row for `selection` without reporting it back as a user choice.
    func select(_ new: Selection) {
        selection = new
        settingSelection = true
        defer { settingSelection = false }
        if let current = outline.item(atRow: outline.selectedRow) as? SidebarNode, stands(current, for: new) { return }
        for row in (0..<outline.numberOfRows).reversed() {
            guard let node = outline.item(atRow: row) as? SidebarNode, stands(node, for: new) else { continue }
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
            return
        }
        outline.deselectAll(nil)
    }

    private func stands(_ node: SidebarNode, for selection: Selection) -> Bool {
        switch (node.kind, selection) {
        case (.all, .all), (.lab, .lab), (.contrast, .contrast): return true
        case (.palette(let a), .palette(let b)): return a == b
        case (.tag(let a), .tag(let b)): return a.lowercased() == b.lowercased()
        default: return false
        }
    }

    func beginRenaming(_ id: UUID) {
        for row in (0..<outline.numberOfRows).reversed() {
            guard (outline.item(atRow: row) as? SidebarNode)?.paletteID == id,
                  let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? PaletteCell else { continue }
            outline.scrollRowToVisible(row)
            cell.beginRenaming()
            return
        }
    }

    // MARK: Data source

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? SidebarNode)?.children.count ?? roots.count }
    func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? SidebarNode)?.children[index] ?? roots[index] }
    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? SidebarNode)?.isExpandable ?? false }
    // Headings are ordinary rows dressed as headings, not AppKit group rows: a group row puts its
    // disclosure arrow on the right and only on hover, and every arrow here is on the left.
    func outlineView(_ o: NSOutlineView, isGroupItem item: Any) -> Bool { false }
    func outlineView(_ o: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode, !node.isGroup else { return false }
        if case .projectTags = node.kind { return false }
        if case .projectTypography = node.kind { return false }
        return true
    }
    // Each main heading after the first carries the gap that separates it from the section above.
    func outlineView(_ o: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SidebarNode, node.isGroup, node !== roots.first else { return 28 }
        return 28 + SidebarOutlineView.sectionGap
    }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let lib = library.library
        if let id = node.paletteID {
            guard let s = lib.swatch(id) else { return nil }
            let cell = o.makeView(withIdentifier: PaletteCell.identifier, owner: self) as? PaletteCell ?? {
                let c = PaletteCell(frame: .zero); c.identifier = PaletteCell.identifier; return c }()
            cell.configure(s, isTarget: lib.activeSwatchID == id)
            // In the Palettes list, a palette held in a project says which.
            if (o.parent(forItem: item) as? SidebarNode)?.kind == .loose, let project = s.projectID.flatMap({ lib.project($0)?.name }) {
                cell.toolTip = "In project \(project)" + (cell.toolTip.map { "  \u{00B7}  \($0)" } ?? "")
            }
            cell.onRename = { [weak self] name in self?.library.rename(id, to: name) }
            cell.onStar = { [weak self] in self?.library.toggleFavourite(id) }
            cell.onGear = { [weak self] button in
                guard let self = self else { return }
                let menu = NSMenu()
                self.fill(menu, forPalette: id)
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
            }
            return cell
        }
        if let id = node.projectID {
            let cell = o.makeView(withIdentifier: ProjectHeaderCell.identifier, owner: self) as? ProjectHeaderCell ?? {
                let c = ProjectHeaderCell(frame: .zero); c.identifier = ProjectHeaderCell.identifier; return c }()
            cell.configure(name: lib.project(id)?.name ?? "", tooltip: "New palette in this project")
            cell.onAdd = { [weak self] in self?.library.addPalette(to: id) }
            return cell
        }
        if node.kind == .typography {
            let heading = NSUserInterfaceItemIdentifier("typography")
            let cell = o.makeView(withIdentifier: heading, owner: self) as? ProjectHeaderCell ?? {
                let c = ProjectHeaderCell(frame: .zero); c.identifier = heading; return c }()
            cell.configure(name: "Typography", heading: true, tooltip: "New Typography palette")
            cell.toolTip = node.children.isEmpty ? "Palettes of text and background pairings, with the words and fonts they were tried in. Press + to make the first." : nil
            cell.onAdd = { [weak self] in self?.library.newTypography() }
            return cell
        }
        if node.kind == .tags {
            let heading = NSUserInterfaceItemIdentifier("tags")
            let cell = o.makeView(withIdentifier: heading, owner: self) as? ProjectHeaderCell ?? {
                let c = ProjectHeaderCell(frame: .zero); c.identifier = heading; return c }()
            cell.configure(name: "Tags", heading: true, tooltip: "New tag")
            cell.onAdd = { [weak self] in
                guard let self = self else { return }
                self.library.showTagEditor(focusing: self.library.newTag())
            }
            return cell
        }
        if node.kind == .projects {
            let heading = NSUserInterfaceItemIdentifier("projects")
            let cell = o.makeView(withIdentifier: heading, owner: self) as? ProjectHeaderCell ?? {
                let c = ProjectHeaderCell(frame: .zero); c.identifier = heading; return c }()
            cell.configure(name: "Projects", heading: true, tooltip: "New project")
            cell.toolTip = node.children.isEmpty ? "Group palettes by client or piece of work. Press + to make the first project." : nil
            cell.onAdd = { [weak self] in self?.library.newProject() }
            return cell
        }

        let id = NSUserInterfaceItemIdentifier(node.isGroup ? "group" : "plain")
        let cell = o.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? plainCell(id, icon: !node.isGroup)
        if node.isGroup {
            cell.textField?.font = SidebarOutlineView.headingFont
            cell.textField?.textColor = .labelColor
        }
        switch node.kind {
        case .favourites: cell.textField?.stringValue = "Favourites"; cell.toolTip = node.children.isEmpty ? "Star a palette to keep it here" : nil
        case .library: cell.textField?.stringValue = "Library"
        case .loose: cell.textField?.stringValue = "Palettes"; cell.toolTip = "Every palette. Those in a project are listed under their project too"
        case .projectTypography:
            cell.textField?.stringValue = "Typography"
            cell.imageView?.image = symbol("textformat", "Project typography", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "Typography palettes that belong to this project"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(node.children.count)"
        case .projectTags:
            cell.textField?.stringValue = "Tags"
            cell.imageView?.image = symbol("tag", "Project tags", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "Tags that belong to this project"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(node.children.count)"
        case .editTags:
            cell.textField?.stringValue = "Edit Tags\u{2026}"
            cell.imageView?.image = symbol("slider.horizontal.3", "Edit tags", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "Rename, colour, scope and delete tags"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .all:
            cell.textField?.stringValue = "All Swatches"
            cell.imageView?.image = symbol("square.grid.3x3.fill", "All swatches", size: 12)
            cell.imageView?.contentTintColor = .controlAccentColor
            cell.toolTip = nil
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(lib.colours.count)"
        case .tools: cell.textField?.stringValue = "cTools"
        case .contrast:
            cell.textField?.stringValue = "Contrast"
            cell.imageView?.image = symbol("circle.lefthalf.filled", "Contrast", size: 12)
            cell.imageView?.contentTintColor = .controlAccentColor
            cell.toolTip = "Check a text colour against a background, and fix it"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .lab:
            cell.textField?.stringValue = "cLab"
            cell.imageView?.image = symbol(labSymbolName, "cLab", size: 12)
            cell.imageView?.contentTintColor = .controlAccentColor
            cell.toolTip = "The colour lab: build palettes on a colour wheel"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .tag(let t):
            cell.textField?.stringValue = t
            cell.imageView?.image = symbol(lib.info(forTag: t)?.colour == nil ? "tag" : "tag.fill", "Tag", size: 11)
            cell.imageView?.contentTintColor = tagColour(lib.info(forTag: t))
            cell.toolTip = lib.project(ofTag: t).flatMap { lib.project($0)?.name }.map { "Project tag: \($0)" }
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(lib.hexes(tagged: t).count)"
        default: break
        }
        return cell
    }

    private func plainCell(_ id: NSUserInterfaceItemIdentifier, icon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        cell.textField = text
        var views: [NSView] = [text]
        if icon {
            let image = NSImageView()
            image.contentTintColor = .controlAccentColor
            cell.imageView = image
            let count = NSTextField(labelWithString: "")
            count.tag = 7
            count.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            count.textColor = .tertiaryLabelColor
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)
            views = [image, text, count]
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Selection and expansion

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !settingSelection, let node = outline.item(atRow: outline.selectedRow) as? SidebarNode else { return }
        switch node.kind {
        case .palette(let id): selection = .palette(id)
        case .all: selection = .all
        case .lab: selection = .lab
        case .contrast: selection = .contrast
        case .tag(let t): selection = .tag(t)
        case .editTags:
            // Not a place to be: open the editor and put the highlight back where it was.
            library.showTagEditor()
            select(selection)
            return
        default: return
        }
        onSelect?(selection)
    }

    func outlineViewItemDidCollapse(_ n: Notification) {
        if !settingSelection, let node = n.userInfo?["NSObject"] as? SidebarNode { preferences.set(true, forKey: key(node)) }
    }

    func outlineViewItemDidExpand(_ n: Notification) {
        if !settingSelection, let node = n.userInfo?["NSObject"] as? SidebarNode { preferences.set(false, forKey: key(node)) }
    }

    // MARK: Drag and drop

    func outlineView(_ o: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? SidebarNode else { return nil }
        let pb = NSPasteboardItem()
        if let id = node.paletteID { pb.setString(id.uuidString, forType: paletteDragType); return pb }
        if let id = node.projectID { pb.setString(id.uuidString, forType: projectDragType); return pb }
        return nil
    }

    private func dragged(_ info: NSDraggingInfo) -> (palette: UUID?, project: UUID?) {
        let pb = info.draggingPasteboard
        return (pb.string(forType: paletteDragType).flatMap(UUID.init(uuidString:)),
                pb.string(forType: projectDragType).flatMap(UUID.init(uuidString:)))
    }

    func outlineView(_ o: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let (palette, project) = dragged(info)
        let target = item as? SidebarNode
        if palette != nil {
            // Palettes land in a project, or are put in order within Favourites or the Palettes list;
            // dropping on a palette row means beside it.
            func takes(_ place: SidebarNode) -> Bool {
                if place.projectID != nil { return true }
                // These lists are only arranged by dragging: what is in each is decided elsewhere.
                return [.favourites, .loose, .typography].contains(place.kind) && place.children.contains { $0.paletteID == palette }
            }
            if let t = target, takes(t) { return .move }
            if let t = target, t.paletteID != nil, let parent = o.parent(forItem: t) as? SidebarNode, takes(parent) {
                o.setDropItem(parent, dropChildIndex: parent.children.firstIndex { $0 === t } ?? 0)
                return .move
            }
            return []
        }
        if project != nil {
            // Projects reorder among themselves under the Projects heading.
            if target === projectsGroup, index >= 0 { return .move }
            if let t = target, t.projectID != nil, let i = projectsGroup.children.firstIndex(where: { $0 === t }) {
                o.setDropItem(projectsGroup, dropChildIndex: i)
                return .move
            }
            return []
        }
        return []
    }

    func outlineView(_ o: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let (palette, project) = dragged(info)
        let target = item as? SidebarNode
        if let id = palette, let t = target, [.favourites, .loose, .typography].contains(t.kind) {
            // Each of these lists has its own order; arranging one leaves projects and the other alone.
            var ids = t.children.compactMap { $0.paletteID }
            guard let from = ids.firstIndex(of: id) else { return false }
            var to = index < 0 ? ids.count : min(index, ids.count)
            ids.remove(at: from)
            if from < to { to -= 1 }
            ids.insert(id, at: min(to, ids.count))
            if t.kind == .favourites { library.placeFavourites(ids) } else { library.placeInList(ids) }
            return true
        }
        if let id = palette, let t = target, let destination = t.projectID {
            // Palettes come first in a project; its tag bucket, when it has one, is always last.
            let palettes = t.children.filter { $0.paletteID != nil }.count
            var at = index < 0 ? palettes : min(index, palettes)
            // Moving down within the same list: the row's own slot is about to close up.
            if let from = t.children.firstIndex(where: { $0.paletteID == id }), from < at { at -= 1 }
            library.move(palette: id, to: destination, index: at)
            return true
        }
        if let id = project, target === projectsGroup {
            var ids = projectsGroup.children.compactMap { $0.projectID }
            guard let from = ids.firstIndex(of: id) else { return false }
            var to = min(max(index, 0), ids.count)
            ids.remove(at: from)
            if from < to { to -= 1 }
            ids.insert(id, at: min(to, ids.count))
            library.placeProjects(ids)
            return true
        }
        return false
    }

    // MARK: Context menu

    private var clicked: SidebarNode? { outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? SidebarNode : nil }

    /// A palette's actions, for a right-click on its row and for the row's gear.
    private func fill(_ menu: NSMenu, forPalette id: UUID) {
        guard let s = library.library.swatch(id) else { return }
        func add(_ title: String, _ action: Selector, _ object: Any? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
        }
        do {
            add("Rename", #selector(renameClicked(_:)), id)
            add(s.favourite ? "Remove from Favourites" : "Add to Favourites", #selector(starClicked(_:)), id)
            if !s.isTypography {   // picks are colours; a Typography palette holds pairings
                add(library.library.activeSwatchID == id ? "Stop Sending Picks Here" : "Send Picks Here", #selector(targetClicked(_:)), id)
            }
            add("Duplicate", #selector(duplicateClicked(_:)), id)
            let move = NSMenu()
            for p in library.library.orderedProjects where p.id != s.projectID {
                let i = move.addItem(withTitle: p.name, action: #selector(moveClicked(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = [id, p.id]
            }
            if s.projectID != nil {
                if !move.items.isEmpty { move.addItem(.separator()) }
                let i = move.addItem(withTitle: "Out of its project", action: #selector(moveClicked(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = [id]
            }
            if !move.items.isEmpty { move.addItem(.separator()) }
            let fresh = move.addItem(withTitle: "New Project\u{2026}", action: #selector(moveToNewClicked(_:)), keyEquivalent: "")
            fresh.target = self; fresh.representedObject = id
            menu.addItem(withTitle: "Move to Project", action: nil, keyEquivalent: "").submenu = move
            menu.addItem(.separator())
            add("Copy All", #selector(copyClicked(_:)), id)
            add("Export\u{2026}", #selector(exportClicked(_:)), id)
            add("Export Design Pack\u{2026}", #selector(packClicked(_:)), id)
            add("Add to macOS Colour Panel", #selector(panelClicked(_:)), id)
            menu.addItem(adobeMenuItem(target: self, action: #selector(adobeClicked(_:)), palette: id))
            menu.addItem(.separator())
            add("Delete Palette", #selector(deleteClicked(_:)), id)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, _ object: Any? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
        }
        if let id = clicked?.paletteID {
            fill(menu, forPalette: id)
        } else if let id = clicked?.projectID {
            add("New Palette in Project", #selector(newInProjectClicked(_:)), id)
            add("Project Details\u{2026}", #selector(projectDetailsClicked(_:)), id)
            add("Rename Project\u{2026}", #selector(renameProjectClicked(_:)), id)
            add("Export Design Pack\u{2026}", #selector(projectPackClicked(_:)), id)
            menu.addItem(.separator())
            add("Delete Project", #selector(deleteProjectClicked(_:)), id)
        } else {
            menu.addItem(withTitle: "New Palette", action: #selector(LibraryController.newPalette), keyEquivalent: "").target = library
            menu.addItem(withTitle: "New Project\u{2026}", action: #selector(LibraryController.newProject), keyEquivalent: "").target = library
            menu.addItem(withTitle: "Project Templates\u{2026}", action: #selector(LibraryController.manageProjectTemplates), keyEquivalent: "").target = library
        }
    }

    private func id(_ s: NSMenuItem) -> UUID? { s.representedObject as? UUID }

    @objc private func renameClicked(_ s: NSMenuItem) { if let id = id(s) { beginRenaming(id) } }
    @objc private func starClicked(_ s: NSMenuItem) { if let id = id(s) { library.toggleFavourite(id) } }
    @objc private func duplicateClicked(_ s: NSMenuItem) { if let id = id(s) { library.duplicate(id) } }
    @objc private func exportClicked(_ s: NSMenuItem) { if let id = id(s) { onExport?(id) } }
    @objc private func packClicked(_ s: NSMenuItem) { if let id = id(s) { onDesignPack?(.palette(id)) } }
    @objc private func panelClicked(_ s: NSMenuItem) { if let id = id(s) { onColourPanel?(id) } }
    @objc private func adobeClicked(_ s: NSMenuItem) { if let send = s.representedObject as? AdobeSend { onAdobe?(send) } }
    @objc private func deleteClicked(_ s: NSMenuItem) { if let id = id(s) { library.delete(palette: id) } }
    @objc private func targetClicked(_ s: NSMenuItem) {
        if let id = id(s) { library.setTarget(library.library.activeSwatchID == id ? nil : id) }
    }
    @objc private func copyClicked(_ s: NSMenuItem) {
        if let id = id(s) { library.copy(library.hexes(in: id), from: library.library.swatch(id)?.name) }
    }
    @objc private func moveClicked(_ s: NSMenuItem) {
        guard let ids = s.representedObject as? [UUID], let palette = ids.first else { return }
        library.move(palette: palette, to: ids.count > 1 ? ids[1] : nil, index: Int.max)
    }
    @objc private func moveToNewClicked(_ s: NSMenuItem) { if let id = id(s) { library.startProject(moving: id) } }
    @objc private func newInProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.addPalette(to: id) } }
    @objc private func projectDetailsClicked(_ s: NSMenuItem) { if let id = id(s) { library.editProject(id) } }
    @objc private func renameProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.renameProject(id) } }
    @objc private func projectPackClicked(_ s: NSMenuItem) { if let id = id(s) { library.exportDesignPack(project: id) } }
    @objc private func deleteProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.delete(project: id) } }
}
