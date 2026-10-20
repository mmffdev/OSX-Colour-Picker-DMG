import AppKit

// ---------- railInfo and its first pane, Tags ----------
//
// railInfo is the rail that opens right of rail1, 360 wide like the others and nothing at rest: the actionbar, the
// viewport and its bars move across as it opens and back as it closes; it never lies over them. One full-rail panel,
// headed Options for now, with a left-facing chevron before the title that closes it; what the panel holds is any pane
// that answers InfoRailContent. The frame keeps the rail and the slide (StudioWindow.swift, "railInfo"); this file is the
// contract and the Tags pane.
//
// Tags: the asset at the top as the Bloom panel shows it, its name on one line and its spectrum under it; then the modal's
// system in the rail, the tags on the asset as words separated by commas, a tag to add from the library, a colour for the
// tags that have none yet, and Save; then the tag library as the tree with the connectors, Global and the catalogue as
// its two roots and every tag a row off one of them with its colour down its left edge, its edit and its count. Edit
// replaces the pane with the one tag: its name, its colour, Save; Escape goes back, and Escape again closes the rail.

/// What a pane in railInfo answers to.
protocol InfoRailContent: AnyObject {
    /// Escape while the rail is open: true when the pane took it (an inner state closed); false lets the rail close.
    func escapeInfoRail() -> Bool
}

/// What is being tagged.
struct TagRequest {
    enum Subject { case palette(UUID), palettes([UUID]), colours([String]) }
    let subject: Subject
    let window: NSWindow?
}

final class TagsInfoPane: NSView, WorkspaceScrollableContent, InfoRailContent, NSOutlineViewDataSource, NSOutlineViewDelegate {
    // The beat, top down. The asset's name and spectrum sit where the Bloom panel puts them. The note is a box of three
    // lines whatever it says (law 6), so the controls under it never move between an asset and the next.
    private static let inset: CGFloat = 16
    private static let titleBaseline: CGFloat = 21, spectrumTop: CGFloat = 36, spectrumHeight: CGFloat = 20
    private static let headingBaseline: CGFloat = 92
    private static let noteTop: CGFloat = 104, noteHeight: CGFloat = 63
    /// A block is a caption on its first line and its control 24 under the block's top, as the modal's dropdown row.
    private static let block1: CGFloat = 176, block2: CGFloat = 252, block3: CGFloat = 328
    private static let saveTop: CGFloat = 404, dividerY: CGFloat = 464, libraryBaseline: CGFloat = 500, treeTop: CGFloat = 516
    private static let editSaveTop: CGFloat = 316, editBottom: CGFloat = 364

    private let library: LibraryController
    private var request: TagRequest
    private var subjectName = "", spectrum: [NSColor] = [], within = Set<UUID>(), newScope = TagScope.global
    /// The tag being edited, in place of the list; nil is the list.
    private var editing: String?
    private var newColour: String?, editColour: String?

    private let field = SwissBlockTextField(frame: .zero)
    private let choice = ChoiceRow(caption: "Available Tags")
    private let well = ColourWell()
    private let save = SwissButton("Save Tags", .primary)
    private let editField = SwissBlockTextField(frame: .zero)
    private let editWell = ColourWell()
    private let editSave = SwissButton("Save Tag", .primary)
    private let tree = WorkspaceBranchTree(frame: .zero)
    private let globalRoot = Node(.root(global: true)), catalogueRoot = Node(.root(global: false))

    final class Node: NSObject {
        enum Value { case root(global: Bool), tag(String) }
        let value: Value
        var children: [Node] = []
        init(_ value: Value) { self.value = value }
    }

    override var isFlipped: Bool { true }
    var panelContentPadding: CGFloat { Self.inset }
    private var rowsHeight: CGFloat { CGFloat(tree.numberOfRows) * tree.rowHeight }
    var minimumContentHeight: CGFloat { editing == nil ? Self.treeTop + rowsHeight : Self.editBottom }

    init(request: TagRequest, library: LibraryController) {
        self.library = library; self.request = request
        super.init(frame: .zero)
        for f in [field, editField] {
            f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
            f.font = Design.font(17, .regular); f.textColor = Design.ink
            f.cell?.sendsActionOnEndEditing = false
            addSubview(f)
        }
        field.placeholderAttributedString = Design.attributed("Brand, Spring 2027, Approved", .headline, size: 17, colour: Design.soft)
        field.setAccessibilityLabel("Tags"); field.target = self; field.action = #selector(saveTags)
        editField.placeholderAttributedString = Design.attributed("Tag", .headline, size: 17, colour: Design.soft)
        editField.setAccessibilityLabel("Tag Name"); editField.target = self; editField.action = #selector(saveEdit)
        choice.onPick = { [weak self] word in self?.add(word) }
        addSubview(choice)
        well.run = { [weak self] in self?.pickColour(forEdit: false) }; well.setAccessibilityLabel("Assign Colour"); addSubview(well)
        editWell.run = { [weak self] in self?.pickColour(forEdit: true) }; editWell.setAccessibilityLabel("Assign Colour"); addSubview(editWell)
        save.target = self; save.action = #selector(saveTags); addSubview(save)
        editSave.target = self; editSave.action = #selector(saveEdit); addSubview(editSave)
        buildTree()
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: nil)
        show(request)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    // ---------- the asset ----------

    /// The pane turns to another asset: its name, its spectrum, its tags in the field; the library under it stays.
    func show(_ request: TagRequest) {
        self.request = request
        let lib = library.library
        switch request.subject {
        case .palette(let id):
            let s = lib.swatch(id)
            subjectName = s?.name ?? "Palette"
            spectrum = (s?.entries ?? []).map { lib.definition(of: $0.hex)?.master.display ?? Design.hex($0.hex) }
            within = Set([s?.projectID].compactMap { $0 })
            newScope = s?.projectID.map { .member($0) } ?? .global
            field.stringValue = (s?.tagList ?? []).joined(separator: ", ")
        case .palettes(let ids):
            let records = ids.compactMap { lib.swatch($0) }
            subjectName = "\(records.count) Selected Palettes"
            spectrum = records.flatMap(\.entries).map { lib.definition(of: $0.hex)?.master.display ?? Design.hex($0.hex) }
            within = Set(records.compactMap(\.projectID))
            newScope = .global
            let common = records.dropFirst().reduce(Set(records.first?.tagList ?? [])) { $0.intersection($1.tagList) }
            field.stringValue = common.sorted().joined(separator: ", ")
        case .colours(let hexes):
            subjectName = hexes.count == 1 ? colourName(hexes[0]) : plural(hexes.count, "colour")
            spectrum = hexes.map { lib.definition(of: $0)?.master.display ?? Design.hex($0) }
            within = lib.projects(holdingAll: hexes)
            newScope = within.count == 1 ? .member(within.first!) : .global
            field.stringValue = (lib.colours.first { $0.hex == hexes.first }?.tags ?? []).joined(separator: ", ")
        }
        newColour = nil; editing = nil
        rebuild()
        setAccessibilityLabel("Tags on " + subjectName)
    }

    /// The tags the asset may wear, for the dropdown: Global over the global ones, the catalogue over the rest.
    private func offered() -> [String] {
        let lib = library.library
        let project: UUID? = within.count == 1 ? within.first : nil
        return within.count > 1 ? lib.allTags : lib.tags(offeredIn: project)
    }

    private func add(_ word: String) {
        var tags = TagPanel.split(field.stringValue)
        guard !tags.contains(where: { $0.lowercased() == word.lowercased() }) else { return }
        tags.append(word)
        field.stringValue = tags.joined(separator: ", ")
    }

    @objc private func saveTags() {
        let tags = TagPanel.split(field.stringValue)
        switch request.subject {
        case .palette(let id): library.setTags(ofPalette: id, tags, newScope: newScope)
        case .palettes(let ids): for id in ids { library.setTags(ofPalette: id, tags, newScope: newScope) }
        case .colours(let hexes): library.setTags(ofSwatches: hexes, tags, newScope: newScope)
        }
        // The colour goes on the tags in the field that have none of their own: the ones made now, and any bare before.
        if let hex = newColour {
            for tag in tags where library.library.info(forTag: tag)?.colour == nil && library.library.allTags.contains(where: { $0.lowercased() == tag.lowercased() }) {
                library.setColour(hex, ofTag: tag)
            }
        }
        newColour = nil
        show(request)
    }

    // ---------- the colour ----------

    private func pickColour(forEdit: Bool) {
        guard let root = window?.contentView else { return }
        let name = forEdit ? (editing ?? "Tag") : "New Tags"
        let current = forEdit ? editColour : newColour
        let target = StudioColourPicker.Target(group: "Tags", name: name, key: "tag-colour",
            read: { Design.hex(current ?? (hexOf(Design.card) ?? "#F8F7F5")) },
            write: { [weak self] hex in
                guard let self else { return }
                if forEdit { self.editColour = hex } else { self.newColour = hex }
                self.needsDisplay = true; self.refreshWells()
            })
        StudioColourPicker(target: "tag-colour", targets: [target], onReset: { [weak self] in
            guard let self else { return }
            if forEdit { self.editColour = nil } else { self.newColour = nil }
            self.needsDisplay = true; self.refreshWells()
        }, commitOnPick: true).present(over: root)
    }
    private func refreshWells() { well.colour = newColour; editWell.colour = editColour }

    // ---------- the edit ----------

    private func beginEdit(_ tag: String) {
        editing = tag
        editField.stringValue = tag
        editColour = library.library.info(forTag: tag)?.colour
        refreshWells(); needsLayout = true; needsDisplay = true; arrangeRail()
        window?.makeFirstResponder(editField)
    }
    private func endEdit() {
        editing = nil
        window?.makeFirstResponder(nil)
        needsLayout = true; needsDisplay = true; arrangeRail()
    }
    @objc private func saveEdit() {
        guard let old = editing else { return }
        let new = editField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = new.isEmpty ? old : new
        if name != old { library.renameTag(old, to: name) }
        if library.library.info(forTag: name)?.colour != editColour { library.setColour(editColour, ofTag: name) }
        endEdit()
        show(request)
    }
    func escapeInfoRail() -> Bool {
        guard editing != nil else { return false }
        endEdit(); return true
    }

    // ---------- the library ----------

    private func buildTree() {
        let column = NSTableColumn(identifier: .init("Tags"))
        tree.addTableColumn(column); tree.outlineTableColumn = column; tree.headerView = nil
        tree.rowHeight = 34; tree.intercellSpacing = .zero; tree.indentationPerLevel = 0
        tree.backgroundColor = Design.card; tree.style = .plain; tree.focusRingType = .none
        tree.leadingDisclosure = true; tree.expandsOnSelection = false; tree.allowsEmptySelection = true
        tree.swatchFamily = .charcoal; tree.outlinedRows = true
        tree.delegate = self; tree.dataSource = self
        tree.setAccessibilityLabel("Tag Library")
        tree.rowColour = { item in
            guard let node = item as? Node, case .root(let global) = node.value else { return nil }
            return global ? WorkspaceBranchTree.tint(0) : (WorkspaceNodeAppearance.colour("catalogue") ?? Design.houseYellow)
        }
        tree.rowFill = { item in if let node = item as? Node, case .root = node.value { return true }; return false }
        tree.rowClear = { item in if let node = item as? Node, case .tag = node.value { return true }; return false }
        tree.rowLeadingAccent = { [weak self] item in
            guard let self, let node = item as? Node, case .tag(let name) = node.value else { return nil }
            return self.library.library.info(forTag: name)?.colour.map(Design.hex) ?? Design.soft
        }
        addSubview(tree); tree.installConnectors(in: self)
    }
    /// The two roots and their tags from the library as it stands, and the dropdown's rows with them.
    private func rebuild() {
        let lib = library.library
        let all = lib.allTags
        let globals = all.filter { lib.scope(ofTag: $0) == .global }, scoped = all.filter { lib.scope(ofTag: $0) != .global }
        globalRoot.children = globals.map { Node(.tag($0)) }
        catalogueRoot.children = scoped.map { Node(.tag($0)) }
        tree.reloadData()
        tree.expandItem(globalRoot); tree.expandItem(catalogueRoot)
        tree.refreshSurfaces()
        let M = SwissDropdown.MenuPanel.self
        let wearable = Set(offered().map { $0.lowercased() })
        var items: [String] = []
        let g = globals.filter { wearable.contains($0.lowercased()) }, c = scoped.filter { wearable.contains($0.lowercased()) }
        if !g.isEmpty { items += [M.heading("Global")] + g }
        if !c.isEmpty { items += (items.isEmpty ? [] : [M.divider]) + [M.heading(library.catalogue)] + c }
        choice.items = items
        choice.prompt = items.isEmpty ? "No Tags Yet" : "Choose A Tag"
        refreshWells()
        needsLayout = true; needsDisplay = true; arrangeRail()
    }
    @objc private func libraryChanged() { rebuild() }
    private func arrangeRail() {
        var view: NSView? = superview
        while let v = view { if let panel = v as? WorkspacePanel { panel.rail?.arrange(); return }; view = v.superview }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? 2 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? (index == 0 ? globalRoot : catalogueRoot) }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { let row = WorkspaceBranchTree.Row(); row.accordion = tree; return row }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let cell = WorkspaceBranchTree.Cell(frame: .zero)
        cell.leadingDisclosure = true; cell.star.isHidden = true; cell.compactMetadata = true
        let title: String
        switch node.value {
        case .root(let global):
            title = global ? "Global" : library.catalogue
            cell.symbol = global ? "globe" : "folder"
            cell.countLabel.stringValue = node.children.isEmpty ? "(0)" : String(node.children.count); cell.countLabel.isHidden = false
        case .tag(let name):
            title = name
            cell.symbol = "tag"
            let uses = library.library.uses(ofTag: name)
            cell.countLabel.stringValue = "(\(uses.swatches.count + uses.palettes.count))"; cell.countLabel.isHidden = false
            cell.inlineActionBeforeCount = true
            cell.catalogueAction.isHidden = false; cell.catalogueAction.symbol = "slider.horizontal.3"
            cell.catalogueAction.setAccessibilityLabel("Edit Tag: " + name); cell.catalogueAction.toolTip = "Edit Tag"
            cell.catalogueAction.run = { [weak self] in self?.beginEdit(name) }
        }
        let label = NSTextField(labelWithString: title)
        label.font = Design.Text.body.font(); label.textColor = Design.ink; label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label); cell.textField = label; cell.toolTip = title
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard tree.selectedRow >= 0, let node = tree.item(atRow: tree.selectedRow) as? Node else { return }
        tree.deselectAll(nil)
        if case .tag(let name) = node.value { beginEdit(name) }
    }

    // ---------- drawing and placing ----------

    override func layout() {
        super.layout()
        let x = Self.inset, w = max(40, bounds.width - 2 * Self.inset)
        let list = editing == nil
        for v in [field, choice, well, save, tree] as [NSView] { v.isHidden = !list }
        for v in [editField, editWell, editSave] as [NSView] { v.isHidden = list }
        if list {
            field.frame = NSRect(x: x, y: Self.block1 + 24, width: w, height: 24)
            choice.frame = NSRect(x: x, y: Self.block2, width: w, height: ChoiceRow.height)
            well.frame = NSRect(x: x, y: Self.block3 + 24, width: 28, height: 28)
            let sw = save.intrinsicContentSize.width
            save.frame = NSRect(x: x + w - sw, y: Self.saveTop, width: sw, height: SwissButton.height)
            tree.frame = NSRect(x: 0, y: Self.treeTop, width: bounds.width, height: max(34, rowsHeight))
            tree.tableColumns.first?.width = bounds.width
        } else {
            editField.frame = NSRect(x: x, y: Self.block1 + 24, width: w, height: 24)
            editWell.frame = NSRect(x: x, y: Self.block2 + 24, width: 28, height: 28)
            let sw = editSave.intrinsicContentSize.width
            editSave.frame = NSRect(x: x + w - sw, y: Self.editSaveTop, width: sw, height: SwissButton.height)
        }
        tree.layoutConnectors()
    }
    override func draw(_ dirtyRect: NSRect) {
        let x = Self.inset, w = max(40, bounds.width - 2 * Self.inset)
        // The asset as the Bloom panel shows it: its name on the first line, its spectrum under it.
        Design.attributed(subjectName, .bodyStrong).draw(x: x, baseline: Self.titleBaseline, width: w)
        PaletteSpectrum.draw(spectrum, in: NSRect(x: x, y: Self.spectrumTop, width: w, height: Self.spectrumHeight))
        let heading: String, note: String
        if let tag = editing {
            heading = "Edit Tag \u{00B7} " + tag
            note = "Change the name or the colour. Save keeps the tag on every colour and palette wearing it; Escape goes back without a change."
        } else {
            heading = "Tags"
            note = "The tags on \(subjectName), separated by commas. A tag that is new takes the asset's scope; Assign Colour colours the tags that have none."
        }
        Design.attributed(heading, .heading).draw(x: x, baseline: Self.headingBaseline, width: w)
        Design.attributed(note, .body, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: x, y: Self.noteTop, width: w, height: Self.noteHeight))
        func caption(_ s: String, _ top: CGFloat) { Design.attributed(s, .label, colour: Design.quiet).draw(x: x, baseline: top + 12) }
        func colourWords(_ hex: String?, _ top: CGFloat) {
            Design.attributed(hex?.uppercased() ?? "No Colour", .body, colour: hex == nil ? Design.quiet : Design.ink).draw(x: x + 40, baseline: top + 24 + 19)
        }
        if editing == nil {
            caption("Tags", Self.block1)
            hairline(x: x, y: Self.block1 + 52, width: w)
            caption("Assign Colour", Self.block3); colourWords(newColour, Self.block3)
            hairline(x: x, y: Self.dividerY, width: w)
            Design.attributed("Tag Library", .heading).draw(x: x, baseline: Self.libraryBaseline, width: w)
        } else {
            caption("Tag", Self.block1)
            hairline(x: x, y: Self.block1 + 52, width: w)
            caption("Assign Colour", Self.block2); colourWords(editColour, Self.block2)
        }
    }

    /// The library's tags as the house dropdown offers them, under a caption. Picking one hands the word to the field
    /// above and the row shows its prompt again: the words live in the field, not here.
    private final class ChoiceRow: ClickCursorView, Overlay {
        override var handCursorRects: [NSRect] { [bounds] }
        static let height: CGFloat = 56
        var items: [String] = [] { didSet { needsDisplay = true } }
        var prompt = "Choose A Tag" { didSet { needsDisplay = true } }
        var onPick: ((String) -> Void)?
        private var dropped: SwissDropdown.MenuPanel?
        private let caption: String
        init(caption: String) { self.caption = caption; super.init(frame: .zero); setAccessibilityRole(.popUpButton); setAccessibilityLabel(caption) }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        private var hasRows: Bool { items.contains { SwissDropdown.MenuPanel.kind($0) == 0 } }
        var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
        var dismissOnOutsideClick: Bool { true }
        func handleOverlayEscape() -> Bool { dismissOverlay(); return true }
        func containsOverlayEvent(_ event: NSEvent) -> Bool {
            if event.window === dropped { return true }
            return event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
        }
        func dismissOverlay() {
            if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
            dropped = nil; Overlays.closed(self); needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            Design.attributed(caption, .label, colour: Design.quiet).draw(x: 0, baseline: 12)
            Design.attributed(prompt, .body, colour: hasRows ? Design.ink : Design.quiet).draw(x: 8, baseline: 43, width: bounds.width - 44)
            DropdownSkin.draw(in: NSRect(x: 0, y: 24, width: bounds.width, height: 28), up: dropped != nil)
        }
        override func mouseDown(with event: NSEvent) {
            if dropped != nil { dismissOverlay(); return }
            guard let win = window, hasRows else { return }
            let rows = items
            let panel = SwissDropdown.MenuPanel(items: rows, chosen: "", width: bounds.width) { [weak self] i in
                guard let self else { return }
                self.dismissOverlay()
                guard rows.indices.contains(i), SwissDropdown.MenuPanel.kind(rows[i]) == 0 else { return }
                self.onPick?(rows[i].trimmingCharacters(in: .whitespaces))
            }
            let s = win.convertToScreen(convert(bounds, to: nil))
            panel.place(below: NSPoint(x: s.minX, y: s.minY - 4))
            win.addChildWindow(panel, ordered: .above)
            dropped = panel; Overlays.opened(self); needsDisplay = true
        }
    }

    /// The colour square beside Assign Colour: the colour, or the paper with a diagonal when there is none. Opens the picker.
    private final class ColourWell: ClickCursorButton {
        var colour: String? { didSet { needsDisplay = true } }
        var run: (() -> Void)?
        init() { super.init(frame: .zero); isBordered = false; target = self; action = #selector(pressed); toolTip = "Choose A Colour" }
        required init?(coder: NSCoder) { fatalError() }
        @objc private func pressed() { run?() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func draw(_ dirtyRect: NSRect) {
            let box = bounds.insetBy(dx: 0.5, dy: 0.5)
            (colour.map(Design.hex) ?? Design.card).setFill(); box.fill()
            if colour == nil {
                let slash = NSBezierPath(); slash.move(to: NSPoint(x: box.minX, y: box.maxY)); slash.line(to: NSPoint(x: box.maxX, y: box.minY))
                slash.lineWidth = 1; Design.rule.setStroke(); slash.stroke()
            }
            (isHighlighted ? Design.ink : Design.rule).setStroke()
            let edge = NSBezierPath(rect: box); edge.lineWidth = 1; edge.stroke()
        }
    }
}
