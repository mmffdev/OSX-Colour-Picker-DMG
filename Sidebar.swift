import AppKit

// ---------- Rail 1: library, favourites, projects with their palettes, loose palettes, tags ----------

final class SidebarNode: NSObject {
    enum Kind: Equatable {
        case favourites, library, loose, tags
        /// The "Tools" heading, over Colour Lab and Contrast.
        case tools
        /// The "Projects" heading; each project sits under it with its palettes inside.
        case projects
        case project(UUID)
        case all
        /// Colour Lab, under Tools.
        case lab
        /// Contrast, under Tools.
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
        /// The "Information" bucket inside a project, always first, holding its pages.
        case projectInformation(UUID)
        /// The Overview page in a project's Information bucket.
        case overview(UUID)
        /// The "Palettes" bucket inside a project, after Information, holding its palettes of colours.
        case projectPalettes(UUID)
        case palette(UUID)
        /// A group from the schema that is a label only, inside a project: the project, then the schema group.
        case schemaGroup(UUID, UUID)
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
        if case .projectPalettes = kind { return true }
        if case .projectInformation = kind { return true }
        if case .schemaGroup = kind { return !children.isEmpty }
        return isGroup || projectID != nil
    }

    var paletteID: UUID? { if case .palette(let id) = kind { return id }; return nil }
    var projectID: UUID? { if case .project(let id) = kind { return id }; return nil }
    var tag: String? { if case .tag(let t) = kind { return t }; return nil }
    /// The project a Palettes bucket belongs to.
    var bucketProjectID: UUID? { if case .projectPalettes(let id) = kind { return id }; return nil }
}

let paletteDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.palette")
let projectDragType = NSPasteboard.PasteboardType("com.mmffdev.colour3.project")

/// A palette row: favourite star, a small strip of its colours, the mark of the purpose it is turned to, name, pick mark, then its count.
/// Under the pointer the count gives its place to a gear that opens the palette's menu, so the name keeps the width of both.
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
    /// The purpose the palette is turned to, as rail2 shows it; not there when it is turned to none.
    private let purpose = NSImageView()
    private var committed = ""
    private var gear: NSButton!
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { count.isHidden = hovering; gear.isHidden = !hovering } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func prepareForReuse() { super.prepareForReuse(); hovering = false }

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
        gear = symbolButton("gearshape", tooltip: "Palette actions", target: self, action: #selector(gearTapped(_:)))
        gear.isHidden = true
        count.alignment = .right
        gear.image = symbol("gearshape", "Palette actions", size: 11)
        gear.contentTintColor = .tertiaryLabelColor

        star = symbolButton("star", tooltip: "Add to Favourites", target: self, action: #selector(starTapped))

        purpose.contentTintColor = .secondaryLabelColor
        purpose.setContentHuggingPriority(.required, for: .horizontal)
        // The count and the gear share the row's last column: one or the other shows.
        let tail = NSView()
        for v in [count, gear!] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; tail.addSubview(v) }
        let stack = NSStackView(views: [star, strip, purpose, name, target, tail])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarOutlineView.trailingPad),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            strip.widthAnchor.constraint(equalToConstant: 24),
            strip.heightAnchor.constraint(equalToConstant: 12),
            // The gear is the right-hand column every row shares; the project row's padlock sits on it.
            tail.widthAnchor.constraint(equalToConstant: SidebarOutlineView.trailingIcon),
            tail.heightAnchor.constraint(equalToConstant: SidebarOutlineView.trailingIcon),
            gear.centerXAnchor.constraint(equalTo: tail.centerXAnchor),
            gear.centerYAnchor.constraint(equalTo: tail.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: tail.trailingAnchor),
            count.centerYAnchor.constraint(equalTo: tail.centerYAnchor),
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
        // Every palette of colours is turned to a purpose; one that has not been given one is turned to the default.
        purpose.isHidden = s.isTypography
        let turned = s.purpose ?? Prefs.defaultPurpose
        purpose.image = symbol(turned.symbol, turned.title, size: 11)
        purpose.toolTip = "Turned To \(turned.title)"
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
    /// The cell sets its own text: as a heading it is the rails' small grey, which the list would otherwise resize.
    override var rowSizeStyle: NSTableView.RowSizeStyle { get { .custom } set {} }
    static let identifier = NSUserInterfaceItemIdentifier("project")
    var onAdd: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let folder = NSImageView()
    private let warning = NSImageView()
    private var add: NSButton!
    private var lock: NSButton!
    var onLock: (() -> Void)?

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
        warning.image = symbol("exclamationmark.triangle.fill", "Project file missing", size: 12)
        warning.contentTintColor = .systemOrange
        warning.toolTip = "The project's file is missing. Click to see what happened."
        warning.isHidden = true
        lock = symbolButton("lock.open", tooltip: "Lock the project so nothing in it can change", target: self, action: #selector(lockTapped))
        lock.image = symbol("lock.open", "", size: 11)
        lock.contentTintColor = .tertiaryLabelColor
        lock.imagePosition = .imageOnly
        // The padlock sits on its own at the far right: a spacer takes up the slack after the plus.
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let stack = NSStackView(views: [folder, title, warning, add, spacer, lock])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarOutlineView.trailingPad),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The plus sits on the title's own middle line, whatever height the button would take.
            add.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 16),
            add.heightAnchor.constraint(equalToConstant: 16),
            lock.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: SidebarOutlineView.trailingIcon),
            lock.heightAnchor.constraint(equalToConstant: SidebarOutlineView.trailingIcon),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, heading: Bool = false, tooltip: String, lost: Bool = false, locked: Bool? = nil) {
        title.stringValue = name
        warning.isHidden = !lost
        lock.isHidden = locked == nil
        if let locked = locked {
            lock.image = symbol(locked ? "lock.fill" : "lock.open", "", size: 11)
            lock.contentTintColor = locked ? .systemOrange : .tertiaryLabelColor
            lock.toolTip = locked ? "Locked: nothing in the project can change. Click to unlock" : "Lock the project so nothing in it can change"
        }
        add.isHidden = locked == true
        title.font = heading ? SidebarOutlineView.headingFont : RailStyle.bodyFont
        title.textColor = heading ? RailStyle.headingColour : .labelColor
        folder.isHidden = heading
        add.toolTip = tooltip
        add.setAccessibilityLabel(tooltip)
    }
    @objc private func addTapped() { onAdd?() }
    @objc private func lockTapped() { onLock?() }
}

/// The sidebar's own background: the theme's, flat, in place of the system's tinted sidebar.
final class SidebarBackdrop: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// A row that draws its selection in the theme's colours and turns its text to match, when the
/// theme says; otherwise the system draws it.
final class ThemedRowView: NSTableRowView {
    private var tinted: [NSTextField: NSColor] = [:]

    override var isEmphasized: Bool {
        get { false }   // never the system's accent: the theme draws the selection
        set { super.isEmphasized = newValue }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Theme.sidebarSelectionBackground.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 0), xRadius: 6, yRadius: 6).fill()
    }

    override var isSelected: Bool {
        didSet { recolour() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        recolour()
    }

    /// Every label in the row takes the theme's text colour while selected, and its own colour back after.
    func recolour() {
        let colour = Theme.sidebarSelectionText
        func labels(in v: NSView) -> [NSTextField] { v.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? labels(in: $0) } }
        if isSelected {
            for l in labels(in: self) {
                if tinted[l] == nil { tinted[l] = l.textColor ?? .labelColor }
                l.textColor = colour
            }
        } else {
            for (l, own) in tinted { l.textColor = own }
            tinted = [:]
        }
    }
}

/// One of the strip's icons: a button that says when the pointer is on it.
final class StripButton: NSButton {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// What slides out beside rail1's strip: a rail holding one bucket's contents, over the page, with an edge and a shadow.
final class SlideOutRail: HoverView {
    static let width: CGFloat = 250
    let rail = ContextRail()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        shadow = { let s = NSShadow(); s.shadowBlurRadius = 18; s.shadowOffset = NSSize(width: 6, height: 0); s.shadowColor = NSColor.black.withAlphaComponent(0.28); return s }()
        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: topAnchor), rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor), rail.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
    // Presses stop here: nothing under the slide-out is pressed through it.
    override func mouseDown(with event: NSEvent) {}
}

/// A cell whose text the list does not resize to the system's sidebar size.
final class HeadingCellView: NSTableCellView {
    override var rowSizeStyle: NSTableView.RowSizeStyle { get { .custom } set {} }
}

final class SidebarOutlineView: NSOutlineView {
    /// The right-hand column of icons (gears, padlocks) is this wide and this far from the edge on every row.
    static let trailingIcon: CGFloat = 16
    static let trailingPad: CGFloat = 4
    var onDeleteKey: (() -> Void)?
    /// Shift-F on a row.
    var onFavouriteKey: (() -> Void)?

    // Every level is one step in from the one above (RailStyle.step, which rail2 shares). A row
    // that opens has its arrow at its level and its icon one step on; a row that does not open
    // starts at its level. So a child's arrow, or its star, sits under its parent's icon.
    /// A heading, here and over every column on the pages: the rails' own, small, semibold and grey.
    static var headingFont: NSFont { RailStyle.headingFont }

    // A main heading's arrow is at the row's far right, and shows only while the pointer is on the row.
    private var hoveredRow = -1 { didSet { if hoveredRow != oldValue { showArrows() } } }
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseMoved(with event: NSEvent) { hoveredRow = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hoveredRow = -1 }
    override func layout() { super.layout(); showArrows() }

    private func showArrows() {
        let rows = self.rows(in: visibleRect)
        guard rows.length > 0 else { return }
        for row in rows.location..<(rows.location + rows.length) {
            guard let view = rowView(atRow: row, makeIfNecessary: false) else { continue }
            let main = level(forRow: row) == 0
            for button in view.subviews where button is NSButton && (button.identifier == NSOutlineView.disclosureButtonIdentifier || button.identifier == NSOutlineView.showHideButtonIdentifier) {
                button.alphaValue = !main || row == hoveredRow ? 1 : 0
            }
        }
    }

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

    /// The space left under each main section, held as empty room at the top of the next heading's row.
    static let sectionGap: CGFloat = 20

    /// A main heading other than the first: its row is taller, and its contents sit at the bottom of it.
    private func hasGapAbove(_ row: Int) -> Bool { row > 0 && level(forRow: row) == 0 }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        if level(forRow: row) == 0 { frame.origin.x = visibleRect.maxX - SidebarOutlineView.trailingPad - frame.width - 2 }
        if hasGapAbove(row) { frame.origin.y += SidebarOutlineView.sectionGap; frame.size.height -= SidebarOutlineView.sectionGap }
        return frame
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        // Where the first row's arrow is drawn is where level 0 starts; each level is a step further in.
        let first = numberOfRows > 0 ? super.frameOfOutlineCell(atRow: 0) : .zero
        if first.width > 0 {
            let start = first.minX + CGFloat(level(forRow: row)) * RailStyle.step, main = level(forRow: row) == 0
            // A main heading starts on the rail's own edge, its arrow being at the far right; what it holds sits one step in.
            let x = isExpandable(item(atRow: row)) && !main ? start + RailStyle.step : start
            frame.size.width -= x - frame.origin.x
            frame.origin.x = x
            if main { frame.size.width -= first.width + 6 }
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
    private var paletteBuckets: [UUID: SidebarNode] = [:]
    private var infoBuckets: [UUID: SidebarNode] = [:]
    private var typeBuckets: [UUID: SidebarNode] = [:]
    private let projectsGroup = SidebarNode(.projects)
    private var tagBuckets: [UUID: SidebarNode] = [:]
    private let loose = SidebarNode(.loose)
    private let tags = SidebarNode(.tags)
    private var projectNodes: [UUID: SidebarNode] = [:]
    private var roots: [SidebarNode] = []
    private var selection: Selection = .all
    /// The schema's label-only groups as they stand in each project, kept so they stay open or shut across a reload.
    private var schemaNodes: [String: SidebarNode] = [:]
    /// What each schema group is called, for the cell that shows it, and what the app's own groups have been named.
    private var schemaNames: [UUID: String] = [:]
    private var roleNames: [SchemaRole: String] = [:]

    // rail1 closed: a narrow strip of icons. The pages open from it; a bucket's icon opens the rail on that bucket.
    static let compactWidth: CGFloat = 56
    /// Narrower than this, the rail is the strip of icons; from here up, the tree.
    static let compactBelow: CGFloat = 140
    /// Asks the window to open the rail to its full width.
    var onWantsFull: (() -> Void)?
    private let titlePanel = TitlePanel("Catalogue")
    private let strip = NSStackView()
    private var stripButtons: [NSButton] = []
    private(set) var isCompact = false
    /// What the strip holds, top to bottom: a page it opens, or a bucket it opens the rail on. nil is a gap.
    private lazy var stripItems: [(symbol: String, title: String, page: Selection?, bucket: SidebarNode?)?] = [
        ("sidebar.leading", "Open The Catalogue", nil, nil), nil,
        ("square.grid.3x3.fill", "All Swatches", .all, nil),
        (NSImage(systemSymbolName: "flask.fill", accessibilityDescription: nil) != nil ? "flask.fill" : "testtube.2", "Colour Lab", .lab, nil),
        ("circle.lefthalf.filled", "Contrast", .contrast, nil), nil,
        ("star", "Favourites", nil, favourites), ("folder", "Projects", nil, projectsGroup),
        ("swatchpalette", "Palettes", nil, loose), ("textformat", "Typography", nil, typography), ("tag", "Tags", nil, tags),
    ]

    private func buildStrip() {
        strip.orientation = .vertical
        strip.alignment = .centerX
        strip.spacing = 6
        for (at, entry) in stripItems.enumerated() {
            guard let entry = entry else {
                if let last = strip.arrangedSubviews.last { strip.setCustomSpacing(18, after: last) }
                continue
            }
            let b = StripButton(image: symbol(entry.symbol, entry.title, size: 15), target: self, action: #selector(stripTapped(_:)))
            b.isBordered = false
            b.toolTip = entry.bucket == nil ? entry.title : nil   // a bucket's icon slides its contents out, which says what it is
            b.setAccessibilityLabel(entry.title)
            b.tag = at
            b.onHover = { [weak self, weak b] over in if let b = b { self?.stripHover(b, over) } }
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 34).isActive = true
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            strip.addArrangedSubview(b)
            stripButtons.append(b)
        }
        strip.isHidden = true
        tintStrip()
    }

    /// The page that is showing stands out on the strip.
    private func tintStrip() {
        for b in stripButtons {
            guard stripItems.indices.contains(b.tag), let entry = stripItems[b.tag] else { continue }
            b.contentTintColor = entry.page != nil && entry.page == selection ? .labelColor : .secondaryLabelColor
        }
    }

    // MARK: The slide-out

    private var slideOut: SlideOutRail?
    private var slideOutFor = -1
    private var overStrip = false, overSlideOut = false
    private var closing: DispatchWorkItem?

    /// The pointer came onto, or left, one of the strip's icons.
    private func stripHover(_ button: NSButton, _ over: Bool) {
        overStrip = over
        guard over else { closeSlideOutSoon(); return }
        guard isCompact, stripItems.indices.contains(button.tag), let entry = stripItems[button.tag], let bucket = entry.bucket else { closeSlideOut(); return }
        closing?.cancel()
        if slideOutFor != button.tag { openSlideOut(for: bucket, named: entry.title, tag: button.tag) }
    }

    /// What a bucket holds, as rows that go where they say and shut the slide-out behind them.
    private func slideOutBuckets(for bucket: SidebarNode) -> [RailBucket] {
        let lib = library.library
        func go(_ to: Selection) -> RailRow.Kind { .link { [weak self] in self?.closeSlideOut(); self?.onSelect?(to) } }
        func palette(_ s: Swatch) -> RailRow {
            RailRow(s.name, symbol: s.isTypography ? "textformat" : "swatchpalette", dot: s.isTypography ? nil : s.entries.first.flatMap { colorFromHex($0.hex) },
                    tip: s.name, kind: go(.palette(s.id)))
        }
        func one(_ rows: [NSView], none: String) -> [RailBucket] {
            let b = RailBucket("")
            b.showsHeading = false
            b.set(rows.isEmpty ? [RailRow(none, symbol: "circle.dashed", kind: .link {})] : rows)
            return [b]
        }
        switch bucket.kind {
        case .favourites: return one(library.favourites.map(palette), none: "No Favourites Yet")
        case .loose: return one(lib.swatches.filter { $0.projectID == nil && !$0.isTypography }.map(palette), none: "No Palettes Yet")
        case .typography: return one(lib.swatches.filter { $0.projectID == nil && $0.isTypography }.map(palette), none: "No Typography Yet")
        case .tags: return one(lib.allTags.map { tag in RailRow("#" + tag, symbol: "tag", dot: tagColour(lib.info(forTag: tag)), kind: go(.tag(tag))) }, none: "No Tags Yet")
        case .projects:
            // Each project is a bucket of its own: its overview, then its palettes.
            let all = lib.orderedProjects.map { p -> RailBucket in
                let b = RailBucket(p.name)
                b.set([RailRow("Overview", symbol: "doc.text", kind: go(.overview(p.id)))] + lib.swatches.filter { $0.projectID == p.id }.map(palette))
                return b
            }
            return all.isEmpty ? one([], none: "No Projects Yet") : all
        default: return []
        }
    }

    private func openSlideOut(for bucket: SidebarNode, named name: String, tag: Int) {
        guard let host = view.window?.contentView else { return }
        slideOut?.removeFromSuperview()
        let panel = SlideOutRail()
        panel.rail.title.title.stringValue = name
        panel.rail.set(slideOutBuckets(for: bucket))
        panel.onHover = { [weak self] over in
            self?.overSlideOut = over
            if over { self?.closing?.cancel() } else { self?.closeSlideOutSoon() }
        }
        // Beside the strip, from under the toolbar to the foot of the rail, over the page.
        let strip = view.convert(view.bounds, to: host), top = view.safeAreaInsets.top
        let height = strip.height - top, y = host.isFlipped ? strip.minY + top : strip.minY
        let rest = NSRect(x: strip.maxX, y: y, width: SlideOutRail.width, height: height)
        panel.frame = rest.offsetBy(dx: -14, dy: 0)
        panel.alphaValue = 0
        host.addSubview(panel)
        slideOut = panel
        slideOutFor = tag
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().frame = rest
            panel.animator().alphaValue = 1
        }
    }

    /// Shuts the slide-out a moment after the pointer has left both it and the strip, so crossing from one to the other keeps it open.
    private func closeSlideOutSoon() {
        closing?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.overStrip, !self.overSlideOut else { return }
            self.closeSlideOut()
        }
        closing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func closeSlideOut() {
        closing?.cancel()
        guard let panel = slideOut else { return }
        slideOut = nil
        slideOutFor = -1
        overSlideOut = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.removeFromSuperview() })
    }

    /// For a trial run: slides out the strip's bucket with this title.
    func rehearseSlideOut(_ title: String) {
        guard let at = stripItems.firstIndex(where: { $0?.title == title }), let bucket = stripItems[at]?.bucket else { return }
        overStrip = true
        openSlideOut(for: bucket, named: title, tag: at)
    }

    @objc private func stripTapped(_ sender: NSButton) {
        closeSlideOut()
        guard stripItems.indices.contains(sender.tag), let entry = stripItems[sender.tag] else { return }
        if let page = entry.page { onSelect?(page); return }
        onWantsFull?()
        // Opened on a bucket: the bucket open, and brought to the top of what shows.
        guard let bucket = entry.bucket else { return }
        outline.expandItem(bucket)
        let row = outline.row(forItem: bucket)
        if row >= 0 { outline.scrollRowToVisible(min(outline.numberOfRows - 1, row + 8)); outline.scrollRowToVisible(row) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let compact = view.bounds.width < SidebarViewController.compactBelow
        guard compact != isCompact else { return }
        isCompact = compact
        titlePanel.isHidden = compact
        scroll.isHidden = compact
        strip.isHidden = !compact
        if !compact { closeSlideOut() }
    }
    private var settingSelection = false

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        libraryGroup.children = [SidebarNode(.all)]
        toolsGroup.children = [SidebarNode(.lab), SidebarNode(.contrast)]
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
        outline.indentationPerLevel = RailStyle.step
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

        let scroll = LetGoScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        // Solid, not see-through: the list and its scroll view both paint the theme's background.
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        outline.backgroundColor = Theme.background
        outline.usesAlternatingRowBackgroundColors = false
        self.scroll = scroll
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(schemaChanged), name: .schemaDidChange, object: nil)
        // Under the full-width toolbar, with a flat background of its own; the first row sits on the pages' title line.
        // rail1 begins with its title panel, as every rail and the page do.
        let root = SidebarBackdrop()
        let title = titlePanel
        buildStrip()
        root.addSubview(title)
        root.addSubview(scroll)
        root.addSubview(strip)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        strip.translatesAutoresizingMaskIntoConstraints = false
        // The strip is centred on the rail's closed width, so it stays put while the rail opens and shuts around it.
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 12),
            strip.centerXAnchor.constraint(equalTo: root.leadingAnchor, constant: SidebarViewController.compactWidth / 2),
            title.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    private var scroll: NSScrollView!

    @objc private func schemaChanged() { reload() }

    @objc private func themeChanged() {
        scroll.backgroundColor = Theme.background
        outline.backgroundColor = Theme.background
        view.needsDisplay = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reload()
    }

    /// The list starts below the toolbar, set down so that the first row's middle is on the pages' title line.


    // MARK: Contents

    func reload() {
        let lib = library.library
        favourites.children = library.favourites.map { SidebarNode(.palette($0.id)) }
        var projects: [SidebarNode] = [], buckets: [SidebarNode] = []
        let schema = SchemaTrial.saved
        schemaNames = Dictionary(SchemaTrial.rows(of: schema).map { ($0.node.id, $0.node.name) }, uniquingKeysWith: { first, _ in first })
        roleNames = Dictionary(schema.children.compactMap { group in SchemaTrial.role(of: group).map { ($0, group.name) } }, uniquingKeysWith: { first, _ in first })
        for p in lib.orderedProjects {
            let node = projectNodes[p.id] ?? SidebarNode(.project(p.id))
            projectNodes[p.id] = node
            let held = lib.palettes(in: p.id)
            // What a project shows, and in what order, is the schema's: the app's own groups hold what they
            // always have, and any other group is a label, with the groups nested inside it.
            node.children = []
            let own = lib.allTags.filter { lib.project(ofTag: $0) == p.id }
            func label(_ group: SchemaNode) -> SidebarNode {
                let key = p.id.uuidString + group.id.uuidString
                let made = schemaNodes[key] ?? SidebarNode(.schemaGroup(p.id, group.id))
                schemaNodes[key] = made
                made.children = group.children.map(label)
                buckets.append(made)
                return made
            }
            for group in schema.children {
                switch SchemaTrial.role(of: group) {
                case .information?:
                    // Every project has its Overview page.
                    let info = infoBuckets[p.id] ?? SidebarNode(.projectInformation(p.id))
                    infoBuckets[p.id] = info
                    if info.children.isEmpty { info.children = [SidebarNode(.overview(p.id))] }
                    node.children.append(info)
                    buckets.append(info)
                case .palettes?:
                    let colours = held.filter { !$0.isTypography }
                    guard !colours.isEmpty else { continue }
                    let bucket = paletteBuckets[p.id] ?? SidebarNode(.projectPalettes(p.id))
                    paletteBuckets[p.id] = bucket
                    bucket.children = colours.map { SidebarNode(.palette($0.id)) }
                    node.children.append(bucket)
                    buckets.append(bucket)
                case .typography?:
                    let type = held.filter { $0.isTypography }
                    guard !type.isEmpty else { continue }
                    let bucket = typeBuckets[p.id] ?? SidebarNode(.projectTypography(p.id))
                    typeBuckets[p.id] = bucket
                    bucket.children = type.map { SidebarNode(.palette($0.id)) }
                    node.children.append(bucket)
                    buckets.append(bucket)
                case .tags?:
                    guard !own.isEmpty else { continue }
                    let bucket = tagBuckets[p.id] ?? SidebarNode(.projectTags(p.id))
                    tagBuckets[p.id] = bucket
                    bucket.children = own.map { SidebarNode(.tag($0)) }
                    node.children.append(bucket)
                    buckets.append(bucket)
                case nil:
                    node.children.append(label(group))
                }
            }
            projects.append(node)
        }
        // The Palettes list is the stock: palettes outside any project. A project's palettes are its
        // own copies and are listed under it only. The list keeps an order of its own.
        loose.children = lib.listedPalettes.filter { !$0.isTypography && $0.projectID == nil }.map { SidebarNode(.palette($0.id)) }
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

    /// Opens a project in the list and scrolls to it, without changing what the page shows.
    func reveal(project id: UUID) {
        guard let node = projectNodes[id] else { return }
        outline.expandItem(projectsGroup)
        outline.expandItem(node)
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        // A brief highlight so the eye lands on it, then the real selection comes back.
        settingSelection = true
        outline.selectRowIndexes([row], byExtendingSelection: false)
        settingSelection = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in guard let self = self else { return }; self.select(self.selection) }
    }

    /// Highlights the row for `selection` without reporting it back as a user choice.
    func select(_ new: Selection) {
        selection = new
        tintStrip()
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
        case (.overview(let a), .overview(let b)): return a == b
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
    func outlineView(_ o: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("themedRow")
        return o.makeView(withIdentifier: id, owner: self) as? ThemedRowView ?? { let r = ThemedRowView(); r.identifier = id; return r }()
    }
    func outlineView(_ o: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode, !node.isGroup else { return false }
        if case .projectTags = node.kind { return false }
        if case .projectTypography = node.kind { return false }
        if case .projectPalettes = node.kind { return false }
        if case .projectInformation = node.kind { return false }
        if case .schemaGroup = node.kind { return false }
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
            let locked = lib.project(id)?.isLocked ?? false
            cell.configure(name: lib.project(id)?.name ?? "", tooltip: "New palette in this project", lost: library.lostProjects[id] != nil, locked: locked)
            cell.onAdd = { [weak self] in self?.library.addPalette(to: id) }
            cell.onLock = { [weak self] in self?.library.setProjectLocked(id, !locked) }
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
            cell.configure(name: SchemaTrial.plural(SchemaTrial.primaryName), heading: true, tooltip: "New \(SchemaTrial.primaryName)")
            cell.toolTip = node.children.isEmpty ? "Group palettes by client or piece of work. Press + to make the first project." : nil
            cell.onAdd = { [weak self] in self?.library.newProject() }
            return cell
        }

        let id = NSUserInterfaceItemIdentifier(node.isGroup ? "group" : "plain")
        let cell = o.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? plainCell(id, icon: !node.isGroup)
        if node.isGroup {
            cell.textField?.font = SidebarOutlineView.headingFont
            cell.textField?.textColor = RailStyle.headingColour
        }
        switch node.kind {
        case .favourites: cell.textField?.stringValue = "Favourites"; cell.toolTip = node.children.isEmpty ? "Star a palette to keep it here" : nil
        case .library: cell.textField?.stringValue = "Library"
        case .loose: cell.textField?.stringValue = "Palettes"; cell.toolTip = "Your stock of palettes. A project takes a copy, so these never change with a project"
        case .schemaGroup(_, let group):
            cell.textField?.stringValue = schemaNames[group].flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed"
            cell.imageView?.image = symbol("square.dashed", "Group", size: 11)
            cell.imageView?.contentTintColor = .tertiaryLabelColor
            cell.toolTip = "A Group From Settings \u{25B8} Schema. It Is A Label For Now, And Holds Nothing Yet."
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .projectPalettes:
            cell.textField?.stringValue = roleNames[.palettes] ?? "Palettes"
            cell.imageView?.image = symbol("swatchpalette", "Project palettes", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "Palettes that belong to this project"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(node.children.count)"
        case .projectInformation:
            cell.textField?.stringValue = roleNames[.information] ?? "Information"
            cell.imageView?.image = symbol("info.circle", "Project information", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "What this project is: its pages of information"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .overview:
            cell.textField?.stringValue = "Overview"
            cell.imageView?.image = symbol("doc.text", "Overview", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "The project at a glance"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .projectTypography:
            cell.textField?.stringValue = roleNames[.typography] ?? "Typography"
            cell.imageView?.image = symbol("textformat", "Project typography", size: 11)
            cell.imageView?.contentTintColor = .secondaryLabelColor
            cell.toolTip = "Typography palettes that belong to this project"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = "\(node.children.count)"
        case .projectTags:
            cell.textField?.stringValue = roleNames[.tags] ?? "Tags"
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
        case .tools: cell.textField?.stringValue = "Tools"
        case .contrast:
            cell.textField?.stringValue = "Contrast"
            cell.imageView?.image = symbol("circle.lefthalf.filled", "Contrast", size: 12)
            cell.imageView?.contentTintColor = .controlAccentColor
            cell.toolTip = "Check a text colour against a background, and fix it"
            (cell.viewWithTag(7) as? NSTextField)?.stringValue = ""
        case .lab:
            cell.textField?.stringValue = "Colour Lab"
            cell.imageView?.image = symbol(labSymbolName, "Colour Lab", size: 12)
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
        // A heading keeps the font it is given: a sidebar list otherwise sets every cell's text to the system's sidebar size.
        let cell = icon ? NSTableCellView() : HeadingCellView()
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
        case .overview(let id): selection = .overview(id)
        case .tag(let t): selection = .tag(t)
        case .editTags:
            // Not a place to be: open the editor and put the highlight back where it was.
            library.showTagEditor()
            select(selection)
            return
        case .project(let id) where library.lostProjects[id] != nil:
            library.showLostProject(id)
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
            let home = palette.flatMap { library.library.swatch($0)?.projectID }
            // Into another list a palette goes as a copy, and the pointer says so.
            func drop(on place: SidebarNode) -> NSDragOperation {
                if [.favourites, .typography].contains(place.kind) { return .move }   // only ever put in order
                let there: UUID? = place.kind == .loose ? nil : (place.projectID ?? place.bucketProjectID)
                return there == home ? .move : .copy
            }
            func takes(_ place: SidebarNode) -> Bool {
                if place.projectID != nil { return true }
                if case .projectPalettes = place.kind { return true }
                if place.kind == .loose, home != nil { return true }   // a project's palette, copied back to stock
                // These lists are only arranged by dragging: what is in each is decided elsewhere.
                return [.favourites, .loose, .typography].contains(place.kind) && place.children.contains { $0.paletteID == palette }
            }
            if let t = target, takes(t) { return drop(on: t) }
            if let t = target, t.paletteID != nil, let parent = o.parent(forItem: t) as? SidebarNode, takes(parent) {
                o.setDropItem(parent, dropChildIndex: parent.children.firstIndex { $0 === t } ?? 0)
                return drop(on: parent)
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
            guard let from = ids.firstIndex(of: id) else {
                // Not one of this list's own: a project's palette dropped on Palettes is copied to stock.
                guard t.kind == .loose else { return false }
                library.move(palette: id, to: nil, index: Int.max)
                return true
            }
            var to = index < 0 ? ids.count : min(index, ids.count)
            ids.remove(at: from)
            if from < to { to -= 1 }
            ids.insert(id, at: min(to, ids.count))
            if t.kind == .favourites { library.placeFavourites(ids) } else { library.placeInList(ids) }
            return true
        }
        if let id = palette, let t = target, let destination = t.projectID ?? t.bucketProjectID {
            // Within the project's Palettes bucket the order is the drop's; on the project itself, the end.
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
            // A project owns its palettes, so a palette goes to another home as a copy; the original stays.
            let copy = NSMenu()
            for p in library.library.orderedProjects where p.id != s.projectID {
                let i = copy.addItem(withTitle: p.name, action: #selector(copyToProjectClicked(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = [id, p.id]
            }
            if !copy.items.isEmpty { copy.addItem(.separator()) }
            let fresh = copy.addItem(withTitle: "New Project\u{2026}", action: #selector(moveToNewClicked(_:)), keyEquivalent: "")
            fresh.target = self; fresh.representedObject = id
            if s.projectID != nil {
                let loose = copy.addItem(withTitle: "Palettes, Outside Any Project", action: #selector(copyToProjectClicked(_:)), keyEquivalent: "")
                loose.target = self; loose.representedObject = [id]
            }
            menu.addItem(withTitle: "Copy To Project", action: nil, keyEquivalent: "").submenu = copy
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
            add("Show Project File", #selector(projectFileClicked(_:)), id)
            add("Keep Project In\u{2026}", #selector(moveProjectClicked(_:)), id)
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
    @objc private func copyToProjectClicked(_ s: NSMenuItem) {
        guard let ids = s.representedObject as? [UUID], let palette = ids.first else { return }
        library.copy(palette: palette, to: ids.count > 1 ? ids[1] : nil)
    }
    @objc private func newInProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.addPalette(to: id) } }
    @objc private func projectDetailsClicked(_ s: NSMenuItem) { if let id = id(s) { library.editProject(id) } }
    @objc private func renameProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.renameProject(id) } }
    @objc private func projectFileClicked(_ s: NSMenuItem) { if let id = id(s) { library.showProjectFile(id) } }
    @objc private func moveProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.moveProject(id) } }
    @objc private func projectPackClicked(_ s: NSMenuItem) { if let id = id(s) { library.exportDesignPack(project: id) } }
    @objc private func deleteProjectClicked(_ s: NSMenuItem) { if let id = id(s) { library.delete(project: id) } }
}
