import AppKit
import UniformTypeIdentifiers

enum ViewMode: Int {
    case all, swatches
}

struct Section {
    let swatchID: UUID?
    let hexes: [String]
}

// ---------- Colour tile ----------

final class SwatchItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("swatch")

    var hex: String = ""
    private let swatchView = NSView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 10
        swatchView.layer?.borderWidth = 1
        swatchView.layer?.borderColor = NSColor.separatorColor.cgColor
        view.addSubview(swatchView)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height
        let labelH: CGFloat = 16
        swatchView.frame = NSRect(x: 0, y: labelH + 4, width: w, height: h - labelH - 4)
        label.frame = NSRect(x: 0, y: 0, width: w, height: labelH)
    }

    override var isSelected: Bool {
        didSet {
            swatchView.layer?.borderWidth = isSelected ? 3 : 1
            swatchView.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : .separatorColor).cgColor
        }
    }

    func configure(hex: String) {
        self.hex = hex
        label.stringValue = hex
        swatchView.layer?.backgroundColor = colorFromHex(hex)?.cgColor ?? NSColor.gray.cgColor
    }
}

// ---------- Swatch header (name, rename, copy all) ----------

final class SwatchHeaderView: NSView, NSCollectionViewElement, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("swatchHeader")

    var onRename: ((String) -> Void)?
    var onCopyAll: (() -> Void)?
    var onMakeActive: (() -> Void)?
    var onDelete: (() -> Void)?

    private let nameField = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var editButton: NSButton!
    private var copyButton: NSButton!
    private var targetButton: NSButton!
    private var deleteButton: NSButton!
    private var editingWidth: NSLayoutConstraint!
    private var committedName = ""

    var isEditingName: Bool { nameField.isEditable }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        nameField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.focusRingType = .default
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editingWidth = nameField.widthAnchor.constraint(equalToConstant: 260)
        editingWidth.priority = .defaultHigh

        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        editButton = symbolButton("pencil", tooltip: "Rename swatch", target: self, action: #selector(editTapped))
        copyButton = symbolButton("doc.on.doc", tooltip: "Copy all hex values", target: self, action: #selector(copyTapped))
        targetButton = symbolButton("eyedropper", tooltip: "", target: self, action: #selector(targetTapped))
        deleteButton = symbolButton("trash", tooltip: "Delete swatch", target: self, action: #selector(deleteTapped))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        stack.setViews([nameField, editButton, copyButton, countLabel], in: .leading)
        stack.setViews([targetButton, deleteButton], in: .trailing)
        stack.setCustomSpacing(12, after: copyButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(nameDoubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(doubleClick)
    }

    // Headers pin while scrolling, so they need an opaque, appearance-aware fill.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setEditing(false)
        onRename = nil; onCopyAll = nil; onMakeActive = nil; onDelete = nil
    }

    func configure(name: String, count: Int, isActive: Bool) {
        committedName = name
        nameField.stringValue = name
        if count == 0 {
            countLabel.stringValue = isActive ? "Empty — picked colours land here" : "Empty"
        } else {
            countLabel.stringValue = plural(count, "colour")
        }
        copyButton.isEnabled = count > 0
        targetButton.contentTintColor = isActive ? .controlAccentColor : .tertiaryLabelColor
        let tip = isActive ? "New picks are added to this swatch" : "Add new picks to this swatch"
        targetButton.toolTip = tip
        targetButton.setAccessibilityLabel(tip)
    }

    // MARK: Inline rename

    func beginEditing() {
        guard !isEditingName else { return }
        committedName = nameField.stringValue
        setEditing(true)
        window?.makeFirstResponder(nameField)
    }

    private func setEditing(_ on: Bool) {
        nameField.isEditable = on
        nameField.isSelectable = on
        nameField.drawsBackground = on
        nameField.backgroundColor = on ? .textBackgroundColor : .clear
        editingWidth.isActive = on
    }

    private func finishEditing(commit: Bool) {
        guard isEditingName else { return }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        setEditing(false)
        if commit, !typed.isEmpty, typed != committedName {
            nameField.stringValue = typed
            committedName = typed
            onRename?(typed)
        } else {
            nameField.stringValue = committedName
        }
        returnFocusToGrid()
    }

    private func returnFocusToGrid() {
        var v: NSView? = superview
        while let candidate = v, !(candidate is NSCollectionView) { v = candidate.superview }
        let grid = v
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isEditingName else { return }
            self.window?.makeFirstResponder(grid)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditing(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            nameField.abortEditing()
            finishEditing(commit: false)
            return true
        }
        return false
    }

    // MARK: Actions

    @objc private func editTapped() { beginEditing() }
    @objc private func copyTapped() { onCopyAll?() }
    @objc private func targetTapped() { onMakeActive?() }
    @objc private func deleteTapped() { onDelete?() }

    @objc private func nameDoubleClicked(_ g: NSClickGestureRecognizer) {
        let p = g.location(in: self)
        if nameField.convert(nameField.bounds, to: self).contains(p) { beginEditing() }
    }
}

// ---------- Grid ----------

final class GridCollectionView: NSCollectionView {
    weak var controller: LibraryWindowController?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // delete, forward delete
            controller?.deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    // Right-click acts on the tile under the pointer, not a stale selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: p), !selectionIndexPaths.contains(ip) {
            deselectAll(nil)
            selectItems(at: [ip], scrollPosition: [])
        }
        return super.menu(for: event)
    }

    @objc func copy(_ sender: Any?) {
        controller?.copySelected()
    }
}

// ---------- Drop target ----------

/// Shown over the window while an image is being dragged in: grey dashed frame, icon, caption.
final class DropOverlayView: NSView {
    private let icon = NSImageView()
    private let caption = NSTextField(labelWithString: "Drop image to create a palette")

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]

        let config = NSImage.SymbolConfiguration(pointSize: 54, weight: .light)
        icon.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Drop here")?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .secondaryLabelColor

        caption.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center

        let stack = NSStackView(views: [icon, caption])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Never takes clicks or drags away from the window underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        bounds.fill()

        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 18), xRadius: 16, yRadius: 16)
        NSColor.gray.withAlphaComponent(0.10).setFill()
        frame.fill()
        frame.lineWidth = 2
        frame.setLineDash([10, 7], count: 2, phase: 0)
        NSColor.gray.setStroke()
        frame.stroke()
    }
}

/// Content view that accepts image files dragged in from Finder.
final class DropTargetView: NSView {
    var onDropImage: ((URL) -> Void)?
    private let overlay = DropOverlayView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func imageURL(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL]
        return urls?.first
    }

    private func setOverlay(visible: Bool) {
        if visible {
            overlay.frame = bounds
            addSubview(overlay, positioned: .above, relativeTo: nil) // on top of everything added since
        } else {
            overlay.removeFromSuperview()
        }
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard imageURL(in: info) != nil else { return [] }
        setOverlay(visible: true)
        return .copy
    }

    override func draggingExited(_ info: NSDraggingInfo?) { setOverlay(visible: false) }
    override func draggingEnded(_ info: NSDraggingInfo) { setOverlay(visible: false) }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        setOverlay(visible: false)
        guard let url = imageURL(in: info) else { return false }
        onDropImage?(url)
        return true
    }
}

// ---------- Window ----------

final class LibraryWindowController: NSWindowController, NSCollectionViewDataSource,
                                     NSCollectionViewDelegateFlowLayout, NSMenuDelegate {
    private var store: LibraryStore!
    private var library = Library()
    private var sections: [Section] = []
    private var loadedStamp: Date?
    private var reportedQuarantine: URL?
    private var flashToken = 0

    private var mode: ViewMode = .all
    private var sortOrder: SortOrder = .newest

    private var collectionView: GridCollectionView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!
    private var modeControl: NSSegmentedControl!
    private var sortPopup: NSPopUpButton!
    private var targetPopup: NSPopUpButton!
    private var pickBtn: NSButton!
    private var picking = false

    /// The catalogue this window is showing.
    private(set) var catalogue = Catalogues.mainName
    /// Filled by the File ▸ Catalogue submenu each time it opens.
    let catalogueMenu = NSMenu(title: "Catalogue")
    /// Called when the catalogue or sync state changes, so Settings can redraw.
    var onStateChanged: (() -> Void)?

    private(set) var syncStatus = "Not synced yet."
    private var syncAsking = false
    private var syncPaused = false
    private var lastSyncComplaint: String?

    private let modeKey = "viewMode"
    private let sortKey = "sortOrder"

    convenience init(store: LibraryStore) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "MMFFDev Colour 2"
        win.minSize = NSSize(width: 600, height: 360)
        win.center()
        win.setFrameAutosaveName("MMFFDevColour2MainWindow")
        let drop = DropTargetView(frame: win.contentView?.bounds ?? .zero)
        win.contentView = drop
        self.init(window: win)
        self.store = store
        catalogue = Catalogues.currentName
        win.title = "MMFFDev Colour 2 \u{2014} \(catalogue)"
        catalogueMenu.delegate = self
        drop.onDropImage = { [weak self] url in self?.importPalette(from: url) }
        mode = ViewMode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .all
        sortOrder = SortOrder(rawValue: UserDefaults.standard.integer(forKey: sortKey)) ?? .newest
        build()
        reload()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadOnFocus),
            name: NSWindow.didBecomeKeyNotification, object: win)
    }

    // MARK: Layout

    private func bar(leading: [NSView], trailing: [NSView]) -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        bar.setViews(leading, in: .leading)
        bar.setViews(trailing, in: .trailing)
        return bar
    }

    private func caption(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = .secondaryLabelColor
        l.font = NSFont.systemFont(ofSize: 12)
        return l
    }

    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    private func build() {
        guard let content = window?.contentView else { return }

        // Action bar
        pickBtn = NSButton(title: "Pick a Colour", target: self, action: #selector(pickFromWindow))
        pickBtn.bezelStyle = .rounded
        let newSwatchBtn = NSButton(title: "New Swatch", target: self, action: #selector(newSwatch))
        newSwatchBtn.bezelStyle = .rounded
        if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            newSwatchBtn.image = plus
            newSwatchBtn.imagePosition = .imageLeading
        }

        targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)
        targetPopup.toolTip = "Where newly picked colours are added"
        targetPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        let actionBar = bar(leading: [pickBtn!, newSwatchBtn],
                            trailing: [caption("Picks go to"), targetPopup])

        // Filter bar
        modeControl = NSSegmentedControl(labels: ["All Colours", "Swatches"], trackingMode: .selectOne,
                                         target: self, action: #selector(modeChanged))
        modeControl.selectedSegment = mode.rawValue

        sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sortPopup.addItems(withTitles: SortOrder.allCases.map { $0.title })
        sortPopup.selectItem(at: sortOrder.rawValue)
        sortPopup.target = self
        sortPopup.action = #selector(sortChanged)
        sortPopup.controlSize = .small
        sortPopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        modeControl.controlSize = .small
        modeControl.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        countLabel = caption("")
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let filterBar = bar(leading: [modeControl, caption("Sort"), sortPopup], trailing: [countLabel])

        // Scroll + collection
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 108)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14
        layout.sectionHeadersPinToVisibleBounds = true

        let cv = GridCollectionView(frame: NSRect(x: 0, y: 0, width: 720, height: 400))
        cv.controller = self
        cv.collectionViewLayout = layout
        cv.dataSource = self
        cv.delegate = self
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.backgroundColors = [.clear]
        cv.register(SwatchItem.self, forItemWithIdentifier: SwatchItem.identifier)
        cv.register(SwatchHeaderView.self,
                    forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                    withIdentifier: SwatchHeaderView.identifier)

        let ctxMenu = NSMenu()
        ctxMenu.delegate = self
        cv.menu = ctxMenu

        scroll.documentView = cv
        collectionView = cv

        emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.alignment = .center

        let top = separator(), mid = separator()
        for v in [actionBar, top, filterBar, mid, scroll, emptyLabel!] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            actionBar.topAnchor.constraint(equalTo: content.topAnchor),
            actionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 48),

            top.topAnchor.constraint(equalTo: actionBar.bottomAnchor),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            filterBar.topAnchor.constraint(equalTo: top.bottomAnchor),
            filterBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 38),

            mid.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            mid.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            mid.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: mid.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
        ])
    }

    // MARK: Loading

    @objc private func reloadOnFocus() {
        if window?.firstResponder is NSText { return } // inline rename in progress
        if store.modificationDate != loadedStamp { reload() }
        sync()
    }

    func reload() {
        do {
            library = try store.load()
        } catch {
            show(error)
        }
        loadedStamp = store.modificationDate
        rebuild()
        if let aside = store.quarantinedFile, aside != reportedQuarantine {
            reportedQuarantine = aside
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "The library file could not be read"
            a.informativeText = "It has been kept at \(aside.path) and a fresh library was started."
            if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
        }
    }

    private func apply(_ body: (inout Library) -> Void) {
        do {
            library = try store.mutate(body)
            loadedStamp = store.modificationDate
        } catch {
            show(error)
        }
        rebuild()
        sync()
    }

    private func show(_ error: Error) {
        let a = NSAlert(error: error)
        if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    private var swatchesNewestFirst: [Swatch] { library.swatches.reversed() }

    private func rebuild() {
        switch mode {
        case .all:
            sections = [Section(swatchID: nil, hexes: library.catalogueHexes(by: sortOrder))]
        case .swatches:
            sections = swatchesNewestFirst.map {
                Section(swatchID: $0.id, hexes: library.hexes(inSwatch: $0.id, by: sortOrder))
            }
        }
        collectionView.reloadData()
        rebuildTargetPopup()
        updateStatus()

        switch mode {
        case .all:
            emptyLabel.stringValue = "No colours yet — press ⌘P or click \u{201C}Pick a Colour\u{201D}."
            emptyLabel.isHidden = !library.colours.isEmpty
        case .swatches:
            emptyLabel.stringValue = "No swatches yet — click \u{201C}New Swatch\u{201D} to start one."
            emptyLabel.isHidden = !library.swatches.isEmpty
        }
    }

    private func rebuildTargetPopup() {
        targetPopup.removeAllItems()
        targetPopup.addItem(withTitle: "Library only")
        if !library.swatches.isEmpty { targetPopup.menu?.addItem(.separator()) }
        for s in swatchesNewestFirst {
            let item = NSMenuItem(title: s.name, action: nil, keyEquivalent: "")
            item.representedObject = s.id
            targetPopup.menu?.addItem(item)
        }
        if let id = library.activeSwatch?.id,
           let i = targetPopup.itemArray.firstIndex(where: { $0.representedObject as? UUID == id }) {
            targetPopup.selectItem(at: i)
        } else {
            targetPopup.selectItem(at: 0)
        }
    }

    private func updateStatus() {
        flashToken += 1
        if picking {
            let into = library.activeSwatch.map { " into \($0.name)" } ?? ""
            countLabel.stringValue = "Picking\(into) — press Esc or click this window to stop"
            countLabel.textColor = .labelColor
            return
        }
        let colours = plural(library.colours.count, "colour")
        switch mode {
        case .all: countLabel.stringValue = library.colours.isEmpty ? "" : colours
        case .swatches: countLabel.stringValue = "\(plural(library.swatches.count, "swatch", "swatches")) · \(colours) in library"
        }
        countLabel.textColor = .secondaryLabelColor
    }

    /// Briefly replaces the count with a confirmation message.
    private func flash(_ message: String) {
        flashToken += 1
        let token = flashToken
        countLabel.stringValue = message
        countLabel.textColor = .labelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self, self.flashToken == token else { return }
            self.updateStatus()
        }
    }

    // MARK: Data source

    func numberOfSections(in cv: NSCollectionView) -> Int { sections.count }

    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { sections[s].hexes.count }

    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let item = cv.makeItem(withIdentifier: SwatchItem.identifier, for: ip) as! SwatchItem
        item.configure(hex: sections[ip.section].hexes[ip.item])
        return item
    }

    func collectionView(_ cv: NSCollectionView,
                        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at ip: IndexPath) -> NSView {
        let header = cv.makeSupplementaryView(ofKind: kind, withIdentifier: SwatchHeaderView.identifier,
                                              for: ip) as! SwatchHeaderView
        guard let id = sections[ip.section].swatchID, let swatch = library.swatch(id) else { return header }
        header.configure(name: swatch.name, count: swatch.entries.count,
                         isActive: library.activeSwatchID == id)
        header.onRename = { [weak self] name in self?.rename(id, to: name) }
        header.onCopyAll = { [weak self] in self?.copyAll(id) }
        header.onMakeActive = { [weak self] in self?.setTarget(id) }
        header.onDelete = { [weak self] in self?.confirmDelete(id) }
        return header
    }

    // MARK: Flow layout

    func collectionView(_ cv: NSCollectionView, layout: NSCollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> NSSize {
        mode == .swatches ? NSSize(width: cv.bounds.width, height: 40) : .zero
    }

    func collectionView(_ cv: NSCollectionView, layout: NSCollectionViewLayout,
                        insetForSectionAt section: Int) -> NSEdgeInsets {
        mode == .swatches
            ? NSEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)
            : NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    }

    // MARK: Selection

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let ip = indexPaths.first, let hex = hex(at: ip) else { return }
        copyToClipboard(hex)
        playShutter()
        flash("Copied \(hex)")
    }

    private func hex(at ip: IndexPath) -> String? {
        guard ip.section < sections.count, ip.item < sections[ip.section].hexes.count else { return nil }
        return sections[ip.section].hexes[ip.item]
    }

    /// Selected hexes in the order they appear on screen.
    private func selectedHexes() -> [String] {
        collectionView.selectionIndexPaths
            .sorted { ($0.section, $0.item) < ($1.section, $1.item) }
            .compactMap { hex(at: $0) }
    }

    private func reveal(_ hex: String) {
        let preferred = library.activeSwatchID
        var found: IndexPath?
        for (s, section) in sections.enumerated() {
            guard let i = section.hexes.firstIndex(of: hex) else { continue }
            let ip = IndexPath(item: i, section: s)
            if found == nil || section.swatchID == preferred { found = ip }
        }
        guard let ip = found else { return }
        collectionView.layoutSubtreeIfNeeded()
        collectionView.selectItems(at: [ip], scrollPosition: .centeredVertically)
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === catalogueMenu { fillCatalogueMenu(); return }
        menu.removeAllItems()
        let count = collectionView.selectionIndexPaths.count
        guard count > 0 else { return }

        menu.addItem(withTitle: count == 1 ? "Copy Hex" : "Copy \(count) Hex Values",
                     action: #selector(copySelected), keyEquivalent: "").target = self

        let addItem = NSMenuItem(title: "Add to Swatch", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for s in swatchesNewestFirst {
            let item = sub.addItem(withTitle: s.name, action: #selector(addSelectedToSwatch(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.id
        }
        if !library.swatches.isEmpty { sub.addItem(.separator()) }
        sub.addItem(withTitle: "New Swatch", action: #selector(addSelectedToNewSwatch), keyEquivalent: "").target = self
        addItem.submenu = sub
        menu.addItem(addItem)

        menu.addItem(.separator())
        if mode == .swatches {
            menu.addItem(withTitle: "Remove from Swatch", action: #selector(removeSelectedFromSwatch),
                         keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Delete from Library", action: #selector(deleteSelectedFromLibrary),
                     keyEquivalent: "").target = self
    }

    // MARK: Actions — colours

    /// Starts a picking session: the loupe comes back after every pick until Esc,
    /// a click on this window, or a second press of the button / ⌘P.
    @objc func pickFromWindow() {
        if picking { stopPicking(); return }
        picking = true
        pickBtn.title = "Stop Picking"
        updateStatus()
        sampleNext()
    }

    private func stopPicking() {
        guard picking else { return }
        picking = false
        pickBtn.title = "Pick a Colour"
        updateStatus()
        sync() // held back while the loupe was up
    }

    private func sampleNext() {
        guard picking else { return }
        NSColorSampler().show { [weak self] color in
            guard let self = self, self.picking else { return }
            // Esc gives no colour; a click on our own window means "I'm done".
            guard let color = color, let hex = hexOf(color), !self.clickLandedOnThisWindow() else {
                self.stopPicking()
                return
            }
            playShutter()
            copyToClipboard(hex)
            self.apply { $0.addPick(hex) }
            self.reveal(hex)
            if let s = self.library.activeSwatch {
                self.flash("Picked \(hex) → \(s.name)")
            } else {
                self.flash("Picked \(hex)")
            }
            DispatchQueue.main.async { self.sampleNext() }
        }
    }

    private func clickLandedOnThisWindow() -> Bool {
        guard let w = window else { return false }
        let p = NSEvent.mouseLocation
        guard w.frame.contains(p) else { return false }
        let top = NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0)
        return top <= 0 || top == w.windowNumber || NSApp.window(withWindowNumber: top) != nil
    }

    @objc func copySelected() {
        let hexes = selectedHexes()
        guard !hexes.isEmpty else { return }
        copyToClipboard(hexList(hexes))
        playShutter()
        flash(hexes.count == 1 ? "Copied \(hexes[0])" : "Copied \(plural(hexes.count, "colour"))")
    }

    /// Delete key: in a swatch it removes from that swatch; in All Colours it deletes from the library.
    @objc func deleteSelected() {
        if mode == .swatches { removeSelectedFromSwatch() } else { deleteSelectedFromLibrary() }
    }

    @objc func removeSelectedFromSwatch() {
        var bySwatch: [UUID: Set<String>] = [:]
        for ip in collectionView.selectionIndexPaths {
            guard let hex = hex(at: ip), let id = sections[ip.section].swatchID else { continue }
            bySwatch[id, default: []].insert(hex)
        }
        guard !bySwatch.isEmpty else { return }
        apply { lib in
            for (id, hexes) in bySwatch { lib.remove(hexes, fromSwatch: id) }
        }
    }

    @objc func deleteSelectedFromLibrary() {
        let hexes = Set(selectedHexes())
        guard !hexes.isEmpty else { return }
        let used = library.swatchCount(containingAnyOf: hexes)
        guard used > 0, let w = window else {
            apply { $0.deleteColours(hexes) }
            return
        }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete \(plural(hexes.count, "colour")) from the library?"
        a.informativeText = "This also removes \(hexes.count == 1 ? "it" : "them") from \(used == 1 ? "1 swatch" : "\(used) swatches")."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.apply { $0.deleteColours(hexes) } }
        }
    }

    @objc func addSelectedToSwatch(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        let hexes = selectedHexes()
        var added = 0
        apply { added = $0.add(hexes, toSwatch: id) }
        let name = library.swatch(id)?.name ?? "swatch"
        flash(added == 0 ? "Already in \(name)" : "Added \(plural(added, "colour")) to \(name)")
    }

    @objc func addSelectedToNewSwatch() {
        let hexes = selectedHexes()
        var id: UUID?
        apply { lib in
            let new = lib.createSwatch()
            lib.add(hexes, toSwatch: new)
            id = new
        }
        if let id = id { showSwatchAndRename(id) }
    }

    // MARK: Actions — swatches

    @objc func newSwatch() {
        var id: UUID?
        apply { id = $0.createSwatch() }
        if let id = id { showSwatchAndRename(id) }
    }

    /// Switches to the Swatches view and puts the new swatch's name straight into edit mode.
    private func showSwatchAndRename(_ id: UUID) {
        if mode != .swatches {
            mode = .swatches
            modeControl.selectedSegment = mode.rawValue
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
            rebuild()
        }
        guard let section = sections.firstIndex(where: { $0.swatchID == id }) else { return }
        collectionView.layoutSubtreeIfNeeded()
        if let clip = collectionView.enclosingScrollView?.contentView {
            clip.scroll(to: .zero)
            collectionView.enclosingScrollView?.reflectScrolledClipView(clip)
        }
        DispatchQueue.main.async { [weak self] in
            let header = self?.collectionView.supplementaryView(
                forElementKind: NSCollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: section)) as? SwatchHeaderView
            header?.beginEditing()
        }
    }

    private func rename(_ id: UUID, to name: String) {
        // Deferred: this is called while the name field is still ending its edit.
        DispatchQueue.main.async { [weak self] in
            self?.apply { $0.renameSwatch(id, to: name) }
        }
    }

    private func copyAll(_ id: UUID) {
        let hexes = library.hexes(inSwatch: id, by: sortOrder)
        guard !hexes.isEmpty else { return }
        copyToClipboard(hexList(hexes))
        playShutter()
        flash("Copied \(plural(hexes.count, "colour")) from \(library.swatch(id)?.name ?? "swatch")")
    }

    private func setTarget(_ id: UUID?) {
        apply { $0.activeSwatchID = id }
        if let s = library.activeSwatch {
            flash("Picks now go to \(s.name)")
        } else {
            flash("Picks now go to the library only")
        }
    }

    private func confirmDelete(_ id: UUID) {
        guard let swatch = library.swatch(id) else { return }
        guard !swatch.entries.isEmpty, let w = window else {
            apply { $0.deleteSwatch(id) }
            return
        }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete \u{201C}\(swatch.name)\u{201D}?"
        a.informativeText = "Its \(plural(swatch.entries.count, "colour")) will stay in your library."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.apply { $0.deleteSwatch(id) } }
        }
    }

    // MARK: Actions — bars and menu

    @objc private func modeChanged() {
        mode = ViewMode(rawValue: modeControl.selectedSegment) ?? .all
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        rebuild()
    }

    @objc private func sortChanged() {
        sortOrder = SortOrder(rawValue: sortPopup.indexOfSelectedItem) ?? .newest
        UserDefaults.standard.set(sortOrder.rawValue, forKey: sortKey)
        rebuild()
    }

    @objc private func targetChanged() {
        setTarget(targetPopup.selectedItem?.representedObject as? UUID)
    }

    @objc func importFromV1() {
        let legacy = store.loadLegacy()
        var added = 0
        apply { added = $0.mergeLegacy(legacy) }
        flash(added == 0 ? "Nothing new to import from MMFFDev Colour"
                         : "Imported \(plural(added, "colour")) from MMFFDev Colour")
    }

    // MARK: Actions — export and palettes

    @objc func exportLibrary() {
        guard let w = window else { return }
        if library.colours.isEmpty { flash("Nothing to export yet"); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose where to put the export folder"
        panel.beginSheetModal(for: w) { [weak self] response in
            guard let self = self, response == .OK, let folder = panel.url else { return }
            do {
                let out = try writeExport(self.library, to: folder, by: self.sortOrder)
                self.flash("Exported \(plural(self.library.colours.count, "colour")) to \(out.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                self.show(error)
            }
        }
    }

    @objc func paletteFromImage() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Create Palette"
        panel.message = "Choose an image to build a swatch from"
        panel.beginSheetModal(for: w) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.importPalette(from: url)
        }
    }

    func importPalette(from url: URL, colours count: Int = 8) {
        let title = url.deletingPathExtension().lastPathComponent
        guard let image = loadCGImage(url) else {
            flash("Couldn\u{2019}t read \(url.lastPathComponent) as an image")
            return
        }
        let hexes = extractPalette(from: image, count: count)
        guard !hexes.isEmpty else { flash("No colours found in \(url.lastPathComponent)"); return }
        var id: UUID!
        apply { id = $0.createSwatch(named: title, hexes: hexes) }
        if mode != .swatches {
            mode = .swatches
            modeControl.selectedSegment = mode.rawValue
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
            rebuild()
        }
        if let first = hexes.first { reveal(first) }
        flash("Created \(library.swatch(id)?.name ?? title) with \(plural(hexes.count, "colour")) from the image")
    }

    // MARK: Catalogues

    /// Catalogues on this Mac, plus any in the sync folder that this Mac hasn't opened yet.
    func availableCatalogues() -> [String] {
        var names = Catalogues.standard.names()
        if let folder = SyncSettings.folder {
            for n in SyncEngine.catalogues(in: folder).sorted() where !names.contains(n) { names.append(n) }
        }
        return names
    }

    private func fillCatalogueMenu() {
        catalogueMenu.removeAllItems()
        for name in availableCatalogues() {
            let item = catalogueMenu.addItem(withTitle: name, action: #selector(catalogueMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.state = name == catalogue ? .on : .off
        }
        catalogueMenu.addItem(.separator())
        catalogueMenu.addItem(withTitle: "New Catalogue\u{2026}", action: #selector(newCatalogue), keyEquivalent: "").target = self
        catalogueMenu.addItem(withTitle: "Open Catalogue File\u{2026}", action: #selector(openCatalogueFile), keyEquivalent: "").target = self
    }

    @objc private func catalogueMenuChosen(_ sender: NSMenuItem) { open(catalogue: sender.title) }

    func open(catalogue requested: String) {
        guard requested != catalogue else { return }
        stopPicking()
        var name = requested
        if !Catalogues.standard.names().contains(name) { // so far it only exists in the sync folder
            do { name = try Catalogues.standard.create(name) } catch { show(error); return }
        }
        catalogue = name
        Catalogues.currentName = name
        store = Catalogues.standard.store(for: name)
        reportedQuarantine = nil
        syncPaused = false
        lastSyncComplaint = nil
        syncStatus = "Not synced yet."
        window?.title = "MMFFDev Colour 2 \u{2014} \(name)"
        collectionView.deselectAll(nil)
        reload()
        flash("Opened \(name)")
        sync()
        onStateChanged?()
    }

    @objc func newCatalogue() {
        let a = NSAlert()
        a.messageText = "New Catalogue"
        a.informativeText = "A catalogue is a separate library with its own colours and swatches."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Catalogue name"
        a.accessoryView = field
        a.addButton(withTitle: "Create")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do { open(catalogue: try Catalogues.standard.create(name)) } catch { show(error) }
    }

    @objc func openCatalogueFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Open as Catalogue"
        panel.message = "Choose a library.json from an export or a backup. It is copied, never changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { open(catalogue: try Catalogues.standard.importFile(url)) } catch { show(error) }
    }

    // MARK: Sync

    private func engine() -> SyncEngine? {
        SyncSettings.folder.map {
            SyncEngine(store: store, chosenFolder: $0, catalogue: catalogue,
                       machine: SyncSettings.machineName, backupsToKeep: SyncSettings.backupsToKeep)
        }
    }

    /// File ▸ Sync Now, and the button in Settings. Also un-pauses after "Not Now".
    @objc func syncNow() {
        syncPaused = false
        lastSyncComplaint = nil
        guard SyncSettings.folder != nil else { flash("Choose a sync folder in Settings first"); return }
        sync(loud: true)
    }

    func syncTurnedOff() {
        syncPaused = false
        syncStatus = "Not synced yet."
        onStateChanged?()
    }

    /// Runs after launch, on returning to the window, and after every change.
    /// `loud` reports problems in a sheet; otherwise they only show in the status line.
    func sync(loud: Bool = false) {
        guard let engine = engine(), !syncAsking, !picking, !syncPaused || loud else { return }
        do {
            switch try engine.check() {
            case .firstSync:
                try engine.push(try store.load())
                synced("Saved \(catalogue) to the sync folder", announce: true)
            case .inSync:
                synced(nil, announce: loud)
            case .quiet(let plan):
                try engine.settle(plan)
                if !plan.incoming.isEmpty || canonical(plan.merged) != canonical(plan.local) { reloadAfterSync() }
                synced(plan.incoming.isEmpty ? nil : "Loaded \(catalogue) from the sync folder",
                       announce: loud || !plan.incoming.isEmpty)
            case .incoming(let plan):
                if SyncSettings.askBeforeMerging { ask(plan) } else { finish(.merge) }
            }
        } catch {
            complain(error, loud: loud)
        }
    }

    private func ask(_ plan: SyncPlan) {
        guard let w = window else { return }
        syncAsking = true
        func bullets(_ c: LibraryChange) -> String { c.lines.map { "   \u{2022} \($0)" }.joined(separator: "\n") }
        var text = "From the synced copy:\n" + bullets(plan.incoming)
        if !plan.outgoing.isEmpty { text += "\n\nFrom this Mac:\n" + bullets(plan.outgoing) }
        text += "\n\nMerge keeps everything from both. Whatever you choose, both copies are backed up first."

        let a = NSAlert()
        a.messageText = "The synced copy of \u{201C}\(catalogue)\u{201D} has changes"
        a.informativeText = text
        a.addButton(withTitle: "Merge")
        a.addButton(withTitle: "Use Synced Copy")
        a.addButton(withTitle: "Keep This Mac\u{2019}s")
        a.addButton(withTitle: "Not Now")
        a.beginSheetModal(for: w) { [weak self] response in
            guard let self = self else { return }
            self.syncAsking = false
            switch response {
            case .alertFirstButtonReturn: self.finish(.merge)
            case .alertSecondButtonReturn: self.finish(.useSynced)
            case .alertThirdButtonReturn: self.finish(.keepLocal)
            default:
                self.syncPaused = true
                self.syncStatus = "Paused \u{2014} the synced copy has changes. Choose Sync Now to decide."
                self.onStateChanged?()
            }
        }
    }

    /// Checks again first, so the decision is applied to what is there now, not when the question was asked.
    private func finish(_ choice: SyncChoice) {
        guard let engine = engine() else { return }
        do {
            switch try engine.check() {
            case .incoming(let plan), .quiet(let plan):
                try engine.perform(choice, plan: plan)
                reloadAfterSync()
                switch choice {
                case .merge: synced("Merged: " + (plan.incoming.lines + plan.outgoing.lines.map { $0 + " sent" }).joined(separator: ", "), announce: true)
                case .useSynced: synced("Now using the synced copy", announce: true)
                case .keepLocal: synced("Kept this Mac\u{2019}s copy", announce: true)
                }
            case .firstSync:
                try engine.push(try store.load())
                synced(nil, announce: false)
            case .inSync:
                synced(nil, announce: false)
            }
        } catch {
            complain(error, loud: true)
        }
    }

    private func reloadAfterSync() {
        do { library = try store.load() } catch { show(error) }
        loadedStamp = store.modificationDate
        rebuild()
    }

    private func synced(_ message: String?, announce: Bool) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        syncStatus = "In sync \u{2014} last checked \(f.string(from: Date()))."
        lastSyncComplaint = nil
        syncPaused = false
        if announce { flash(message ?? "\(catalogue) is in sync") }
        onStateChanged?()
    }

    private func complain(_ error: Error, loud: Bool) {
        let text = error.localizedDescription
        syncStatus = "Not synced: \(text)"
        onStateChanged?()
        if loud { show(error) }
        else if text != lastSyncComplaint { flash("Sync: \(text)") } // once, not on every change
        lastSyncComplaint = text
    }
}
