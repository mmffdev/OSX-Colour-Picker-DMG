import AppKit

// ---------- Rail 1: favourites, library, projects with their palettes, loose palettes, tags ----------

final class SidebarNode: NSObject {
    enum Kind: Equatable {
        case favourites, library, loose, tags
        case project(UUID)
        case all
        case tag(String)
        case palette(UUID)
    }

    let kind: Kind
    var children: [SidebarNode] = []

    init(_ kind: Kind) { self.kind = kind }

    var isGroup: Bool {
        switch kind {
        case .favourites, .library, .loose, .tags, .project: return true
        default: return false
        }
    }

    var paletteID: UUID? { if case .palette(let id) = kind { return id }; return nil }
    var projectID: UUID? { if case .project(let id) = kind { return id }; return nil }
    var tag: String? { if case .tag(let t) = kind { return t }; return nil }
}

let paletteDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.palette")
let projectDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.project")

/// A round dot in the palette's identity colour.
final class DotView: NSView {
    var colour: NSColor = .gray { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 10, height: 10) }
    override func draw(_ dirtyRect: NSRect) {
        colour.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

/// A palette row: dot, name, pick mark, count, then star · duplicate · delete.
final class PaletteCell: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("palette")

    var onRename: ((String) -> Void)?
    var onStar: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?

    private let dot = DotView()
    private let name = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let target = NSImageView()
    private var star: NSButton!
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
        target.image = symbol("eyedropper", "Picks go here", size: 10)
        target.contentTintColor = .controlAccentColor
        target.toolTip = "New picks are added to this palette"
        star = symbolButton("star", tooltip: "Add to Favourites", target: self, action: #selector(starTapped))
        let duplicate = symbolButton("plus.square.on.square", tooltip: "Duplicate palette", target: self, action: #selector(duplicateTapped))
        let delete = symbolButton("trash", tooltip: "Delete palette", target: self, action: #selector(deleteTapped))
        for b in [duplicate, delete] { b.image = symbol(b.image == duplicate.image ? "plus.square.on.square" : "trash", "", size: 11); b.contentTintColor = .tertiaryLabelColor }

        let stack = NSStackView(views: [dot, name, target, count, star, duplicate, delete])
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
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ s: Swatch, isTarget: Bool) {
        committed = s.name
        name.stringValue = s.name
        dot.colour = identityColour(s.id)
        count.stringValue = "\(s.entries.count)"
        target.isHidden = !isTarget
        star.image = symbol(s.favourite ? "star.fill" : "star", "Favourite", size: 11)
        star.contentTintColor = s.favourite ? .systemYellow : .tertiaryLabelColor
        star.toolTip = s.favourite ? "Remove from Favourites" : "Add to Favourites"
        toolTip = s.tagList.isEmpty ? nil : "Tags: " + s.tagList.joined(separator: ", ")
    }

    func beginRenaming() { window?.makeFirstResponder(name) }

    @objc private func starTapped() { onStar?() }
    @objc private func duplicateTapped() { onDuplicate?() }
    @objc private func deleteTapped() { onDelete?() }

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

/// A project header: name plus a button for a new palette inside it.
final class ProjectHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("project")
    var onAdd: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private var add: NSButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = title
        add = symbolButton("plus.circle", tooltip: "New palette in this project", target: self, action: #selector(addTapped))
        add.image = symbol("plus.circle", "", size: 12)
        add.contentTintColor = .tertiaryLabelColor
        let stack = NSStackView(views: [title, add])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String) { title.stringValue = name }
    @objc private func addTapped() { onAdd?() }
}

final class SidebarOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDeleteKey?() } else { super.keyDown(with: event) }
    }
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let library: LibraryController
    var onSelect: ((Selection) -> Void)?
    var onExport: ((UUID) -> Void)?
    var onColourPanel: ((UUID) -> Void)?
    var onDesignPack: ((Selection) -> Void)?

    private let outline = SidebarOutlineView()
    private let favourites = SidebarNode(.favourites)
    private let libraryGroup = SidebarNode(.library)
    private let loose = SidebarNode(.loose)
    private let tags = SidebarNode(.tags)
    private var projectNodes: [UUID: SidebarNode] = [:]
    private var roots: [SidebarNode] = []
    private var selection: Selection = .all
    private var settingSelection = false

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        libraryGroup.children = [SidebarNode(.all)]
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

    // MARK: Contents

    func reload() {
        let lib = library.library
        favourites.children = library.favourites.map { SidebarNode(.palette($0.id)) }
        var projects: [SidebarNode] = []
        for p in lib.orderedProjects {
            let node = projectNodes[p.id] ?? SidebarNode(.project(p.id))
            projectNodes[p.id] = node
            node.children = lib.palettes(in: p.id).map { SidebarNode(.palette($0.id)) }
            projects.append(node)
        }
        loose.children = lib.palettes(in: nil).map { SidebarNode(.palette($0.id)) }
        tags.children = lib.allTags.map { SidebarNode(.tag($0)) }
        roots = [favourites, libraryGroup] + projects + [loose] + (tags.children.isEmpty ? [] : [tags])

        settingSelection = true
        outline.reloadData()
        for group in roots where !isCollapsed(group) { outline.expandItem(group) }
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
        case (.all, .all): return true
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
    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? SidebarNode)?.isGroup ?? false }
    func outlineView(_ o: NSOutlineView, isGroupItem item: Any) -> Bool { (item as? SidebarNode)?.isGroup ?? false }
    func outlineView(_ o: NSOutlineView, shouldSelectItem item: Any) -> Bool { !((item as? SidebarNode)?.isGroup ?? true) }
    func outlineView(_ o: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 28 }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let lib = library.library
        if let id = node.paletteID {
            guard let s = lib.swatch(id) else { return nil }
            let cell = o.makeView(withIdentifier: PaletteCell.identifier, owner: self) as? PaletteCell ?? {
                let c = PaletteCell(frame: .zero); c.identifier = PaletteCell.identifier; return c }()
            cell.configure(s, isTarget: lib.activeSwatchID == id)
            cell.onRename = { [weak self] name in self?.library.rename(id, to: name) }
            cell.onStar = { [weak self] in self?.library.toggleFavourite(id) }
            cell.onDuplicate = { [weak self] in self?.library.duplicate(id) }
            cell.onDelete = { [weak self] in self?.library.delete(palette: id) }
            return cell
        }
        if let id = node.projectID {
            let cell = o.makeView(withIdentifier: ProjectHeaderCell.identifier, owner: self) as? ProjectHeaderCell ?? {
                let c = ProjectHeaderCell(frame: .zero); c.identifier = ProjectHeaderCell.identifier; return c }()
            cell.configure(name: lib.project(id)?.name ?? "")
            cell.onAdd = { [weak self] in self?.library.addPalette(to: id) }
            return cell
        }

        let id = NSUserInterfaceItemIdentifier(node.isGroup ? "group" : "plain")
        let cell = o.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? plainCell(id, icon: !node.isGroup)
        switch node.kind {
        case .favourites: cell.textField?.stringValue = "Favourites"; cell.toolTip = node.children.isEmpty ? "Star a palette to keep it here" : nil
        case .library: cell.textField?.stringValue = "Library"
        case .loose: cell.textField?.stringValue = "Palettes"; cell.toolTip = "Palettes outside any project"
        case .tags: cell.textField?.stringValue = "Tags"
        case .all:
            cell.textField?.stringValue = "All Swatches"
            cell.imageView?.image = symbol("square.grid.3x3.fill", "All swatches", size: 12)
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(lib.colours.count)"
        case .tag(let t):
            cell.textField?.stringValue = t
            cell.imageView?.image = symbol("tag", "Tag", size: 11)
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
        case .tag(let t): selection = .tag(t)
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
            // Palettes land in a project or in the loose list; dropping on a palette row means beside it.
            if let t = target, t.projectID != nil || t.kind == .loose { return .move }
            if let t = target, t.paletteID != nil, let parent = o.parent(forItem: t) as? SidebarNode,
               parent.projectID != nil || parent.kind == .loose {
                o.setDropItem(parent, dropChildIndex: parent.children.firstIndex { $0 === t } ?? 0)
                return .move
            }
            return []
        }
        if project != nil {
            // Projects reorder among themselves at the top level.
            if target == nil, index >= 0 { return .move }
            if let t = target, t.projectID != nil, let i = roots.firstIndex(where: { $0 === t }) {
                o.setDropItem(nil, dropChildIndex: i)
                return .move
            }
            return []
        }
        return []
    }

    func outlineView(_ o: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let (palette, project) = dragged(info)
        let target = item as? SidebarNode
        if let id = palette, let t = target {
            let destination = t.projectID
            guard destination != nil || t.kind == .loose else { return false }
            var at = index < 0 ? t.children.count : index
            // Moving down within the same list: the row's own slot is about to close up.
            if let from = t.children.firstIndex(where: { $0.paletteID == id }), from < at { at -= 1 }
            library.move(palette: id, to: destination, index: at)
            return true
        }
        if let id = project, target == nil {
            let firstProject = 2, lastProject = 2 + projectNodes.count // roots: favourites, library, projects…, loose
            var ids = roots.compactMap { $0.projectID }
            guard let from = ids.firstIndex(of: id) else { return false }
            var to = min(max(index, firstProject), lastProject) - firstProject
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, _ object: Any? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = object
        }
        if let id = clicked?.paletteID, let s = library.library.swatch(id) {
            add("Rename", #selector(renameClicked(_:)), id)
            add(s.favourite ? "Remove from Favourites" : "Add to Favourites", #selector(starClicked(_:)), id)
            add(library.library.activeSwatchID == id ? "Stop Sending Picks Here" : "Send Picks Here", #selector(targetClicked(_:)), id)
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
            if !move.items.isEmpty { menu.addItem(withTitle: "Move to Project", action: nil, keyEquivalent: "").submenu = move }
            menu.addItem(.separator())
            add("Copy All", #selector(copyClicked(_:)), id)
            add("Export\u{2026}", #selector(exportClicked(_:)), id)
            add("Export Design Pack\u{2026}", #selector(packClicked(_:)), id)
            add("Add to macOS Colour Panel", #selector(panelClicked(_:)), id)
            menu.addItem(.separator())
            add("Delete Palette", #selector(deleteClicked(_:)), id)
        } else if let id = clicked?.projectID {
            add("New Palette in Project", #selector(newInProjectClicked(_:)), id)
            add("Rename Project\u{2026}", #selector(renameProjectClicked(_:)), id)
            add("Export Design Pack\u{2026}", #selector(projectPackClicked(_:)), id)
            menu.addItem(.separator())
            add("Delete Project", #selector(deleteProjectClicked(_:)), id)
        } else {
            menu.addItem(withTitle: "New Palette", action: #selector(LibraryController.newPalette), keyEquivalent: "").target = library
            menu.addItem(withTitle: "New Project\u{2026}", action: #selector(LibraryController.newProject), keyEquivalent: "").target = library
        }
    }

    private func id(_ s: NSMenuItem) -> UUID? { s.representedObject as? UUID }

    @objc private func renameClicked(_ s: NSMenuItem) { if let id = id(s) { beginRenaming(id) } }
    @objc private func starClicked(_ s: NSMenuItem) { if let id = id(s) { library.toggleFavourite(id) } }
    @objc private func duplicateClicked(_ s: NSMenuItem) { if let id = id(s) { library.duplicate(id) } }
    @objc private func exportClicked(_ s: NSMenuItem) { if let id = id(s) { onExport?(id) } }
    @objc private func packClicked(_ s: NSMenuItem) { if let id = id(s) { onDesignPack?(.palette(id)) } }
    @objc private func panelClicked(_ s: NSMenuItem) { if let id = id(s) { onColourPanel?(id) } }
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
    @objc private func newInProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.addPalette(to: id) } }
    @objc private func renameProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.renameProject(id) } }
    @objc private func projectPackClicked(_ s: NSMenuItem) { if let id = id(s) { library.exportDesignPack(project: id) } }
    @objc private func deleteProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.delete(project: id) } }
}
