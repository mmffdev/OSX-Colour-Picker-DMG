import AppKit

// ---------- Settings ▸ Schema ----------
//
// How a catalogue is laid out, as the user names it: what the main group is called (Project,
// Client, Brand…), and the groups nested inside it, as deep as they like. rail1 reads it: the
// main group's name heads the list of projects, and each project shows the schema's groups in
// the schema's order. Four of the groups are the app's own, and hold what they always have:
// Information, Palettes, Typography and Tags. Any other group is a label only, for now: it shows
// in every project and holds nothing. Taking one of the app's own out of the schema hides it in
// rail1 and loses nothing: the palettes and tags are still in the project's files.

/// One group in the schema: what it is called, what it is for, and the groups inside it.
struct SchemaNode: Codable, Equatable {
    var id = UUID()
    var name: String
    var about = ""
    var children: [SchemaNode] = []
    /// Which of the app's own groups this is, whatever it has been renamed to; nil for a group that is a label only.
    var role: SchemaRole? = nil
}

/// The groups inside a project that the app fills itself.
enum SchemaRole: String, Codable, CaseIterable {
    case information, palettes, typography, tags
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

extension Notification.Name {
    static let schemaDidChange = Notification.Name("schemaDidChange")
}

enum SchemaTrial {
    /// Names offered for the main group, and for the groups inside it.
    static let primaryNames = ["Project", "Client", "Customer", "Group", "Brand", "Campaign", "Job", "Production", "Title", "Account"]
    static let nestedNames = ["Palettes", "Typography", "Assets", "Characters", "Environments", "Props", "Vehicles", "Textures", "Materials",
                              "Interface", "Icons", "Logos", "Photography", "Illustration", "Video", "Print", "Packaging", "Social", "Web",
                              "Deliverables", "References", "Scope", "Documents", "Information"]

    static func names(forLevel level: Int) -> [String] { level == 1 ? primaryNames : nestedNames }

    /// "Level 1: Primary Group", "Level 2: Secondary Group", and so on down.
    static func title(forLevel level: Int) -> String {
        let words = ["Primary", "Secondary", "Tertiary", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth"]
        return "Level \(level): " + (words.indices.contains(level - 1) ? words[level - 1] + " Group" : "Group")
    }

    /// The structure the app has always had: a Project, holding Information, Palettes, Typography and Tags.
    static var start: SchemaNode {
        SchemaNode(name: "Project", children: SchemaRole.allCases.map { SchemaNode(name: $0.title, role: $0) })
    }

    /// The schema in use; the app's own structure until it is changed. Kept under a key of its own,
    /// so a tree built while the panel was only a trial does not rearrange rail1.
    static var saved: SchemaNode {
        get { preferences.data(forKey: "schema.tree").flatMap { try? JSONDecoder().decode(SchemaNode.self, from: $0) } ?? start }
        set {
            if let data = try? JSONEncoder().encode(newValue) { preferences.set(data, forKey: "schema.tree") }
            NotificationCenter.default.post(name: .schemaDidChange, object: nil)
        }
    }

    // A project follows the schema above, the default, until it is given a stack of its own. Its own
    // is kept here by the project's id. (Kept with the app's settings for now, not in the project's
    // file: it does not travel with the project to another Mac yet.)
    static var own: [String: SchemaNode] {
        get { preferences.data(forKey: "schema.projects").flatMap { try? JSONDecoder().decode([String: SchemaNode].self, from: $0) } ?? [:] }
        set {
            if let data = try? JSONEncoder().encode(newValue) { preferences.set(data, forKey: "schema.projects") }
            NotificationCenter.default.post(name: .schemaDidChange, object: nil)
        }
    }
    static func hasOwn(_ project: UUID) -> Bool { own[project.uuidString] != nil }
    /// The stack a project shows: its own, or the default.
    static func schema(for project: UUID) -> SchemaNode { own[project.uuidString] ?? saved }
    /// Gives a project a stack of its own, or, with nil, puts it back on the default.
    static func setSchema(_ tree: SchemaNode?, for project: UUID) {
        var all = own
        all[project.uuidString] = tree
        own = all
    }

    /// Which of the app's own groups a group directly inside the main one is: the role it was given,
    /// or, for one added by name, the role of that name.
    static func role(of node: SchemaNode) -> SchemaRole? { node.role ?? SchemaRole.allCases.first { $0.title == node.name } }

    /// The name for several of a thing: Projects, Companies, Classes.
    static func plural(_ name: String) -> String {
        let lower = name.lowercased()
        guard let last = lower.last else { return name }
        if last == "y", let before = lower.dropLast().last, !"aeiou".contains(before) { return name.dropLast() + "ies" }
        if last == "s" || last == "x" || lower.hasSuffix("ch") || lower.hasSuffix("sh") { return name + "es" }
        return name + "s"
    }

    /// What the main group is called, and several of them.
    static var primaryName: String { let n = saved.name.trimmingCharacters(in: .whitespaces); return n.isEmpty ? "Project" : n }

    /// Every group, top to bottom as the map shows it, with its level: the main group is 1.
    static func rows(of root: SchemaNode) -> [(node: SchemaNode, level: Int)] {
        func walk(_ n: SchemaNode, _ level: Int) -> [(node: SchemaNode, level: Int)] { [(n, level)] + n.children.flatMap { walk($0, level + 1) } }
        return walk(root, 1)
    }

    /// Changes the group with this id, wherever it is.
    static func changing(_ id: UUID, in root: SchemaNode, _ change: (inout SchemaNode) -> Void) -> SchemaNode {
        var out = root
        if out.id == id { change(&out); return out }
        out.children = out.children.map { changing(id, in: $0, change) }
        return out
    }

    /// A name for a new group among these: the first on offer that none of them has taken.
    static func freshName(level: Int, among taken: [SchemaNode]) -> String {
        let used = Set(taken.map { $0.name })
        return names(forLevel: level).first { !used.contains($0) } ?? "New Group"
    }

    /// Adds a group inside the one with this id, last. Returns the tree and the new group's id.
    static func addingChild(to id: UUID, in root: SchemaNode) -> (tree: SchemaNode, added: UUID?) {
        guard let level = rows(of: root).first(where: { $0.node.id == id })?.level else { return (root, nil) }
        var made: UUID?
        let tree = changing(id, in: root) { parent in
            let node = SchemaNode(name: freshName(level: level + 1, among: parent.children))
            made = node.id
            parent.children.append(node)
        }
        return (tree, made)
    }

    /// Adds a group straight after the one with this id, at its level. The main group has no siblings.
    static func addingSibling(after id: UUID, in root: SchemaNode) -> (tree: SchemaNode, added: UUID?) {
        var made: UUID?
        func walk(_ n: SchemaNode, _ level: Int) -> SchemaNode {
            var out = n
            if let at = out.children.firstIndex(where: { $0.id == id }) {
                let node = SchemaNode(name: freshName(level: level + 1, among: out.children))
                made = node.id
                out.children.insert(node, at: at + 1)
                return out
            }
            out.children = out.children.map { walk($0, level + 1) }
            return out
        }
        return (walk(root, 1), made)
    }

    /// Takes a group out, with everything inside it. The main group stays.
    static func removing(_ id: UUID, from root: SchemaNode) -> SchemaNode {
        var out = root
        out.children = out.children.filter { $0.id != id }.map { removing(id, from: $0) }
        return out
    }
}

/// One group on the map: its level, its name, and, while it is selected or under the pointer, what can be done with it.
private final class SchemaRowView: HoverView {
    var onSelect: (() -> Void)?, onChild: (() -> Void)?, onSibling: (() -> Void)?, onRemove: (() -> Void)?
    private let isSelected: Bool
    private let actions = NSStackView()
    private var over = false { didSet { actions.isHidden = !(over || isSelected); needsDisplay = true } }

    /// `shown` is the name the row carries; `holds`, when given, says what is inside the group, such as "3 Palettes".
    init(_ node: SchemaNode, level: Int, selected: Bool, shown: String? = nil, holds: String? = nil) {
        isSelected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let badge = NSTextField(labelWithString: "\(level)")
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.caption, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .center
        badge.toolTip = SchemaTrial.title(forLevel: level)
        let text = shown ?? node.name
        let name = NSTextField(labelWithString: text.isEmpty ? "Unnamed" : text)
        let held = NSTextField(labelWithString: holds ?? "")
        held.font = NSFont.systemFont(ofSize: TextSize.caption)
        held.textColor = .secondaryLabelColor
        held.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.font = NSFont.systemFont(ofSize: TextSize.body, weight: level == 1 ? .semibold : .regular)
        name.textColor = text.isEmpty ? .tertiaryLabelColor : .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        func action(_ symbolName: String, _ tip: String, _ selector: Selector) -> NSButton {
            let b = symbolButton(symbolName, tooltip: tip, target: self, action: selector)
            b.image = symbol(symbolName, tip, size: 12)
            b.contentTintColor = .secondaryLabelColor
            return b
        }
        var buttons = [action("arrow.turn.down.right", "Add A Group Inside This One", #selector(childTapped))]
        if level > 1 {
            buttons.append(action("plus", "Add The Next Group At This Level", #selector(siblingTapped)))
            buttons.append(action("trash", "Remove This Group And Everything Inside It", #selector(removeTapped)))
        }
        actions.setViews(buttons, in: .trailing)
        actions.spacing = 10
        actions.isHidden = !selected
        for v in [badge, name, held, actions] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let indent = 10 + CGFloat(level - 1) * 20
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            held.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            held.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            held.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        onHover = { [weak self] on in self?.over = on }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func childTapped() { onChild?() }
    @objc private func siblingTapped() { onSibling?() }
    @objc private func removeTapped() { onRemove?() }
    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || over else { return }
        NSColor.labelColor.withAlphaComponent(isSelected ? 0.10 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

/// One name in the column of names on offer: ticked when it is the selected group's.
private final class SchemaNameRow: HoverView {
    var onChoose: (() -> Void)?
    private let chosen: Bool
    private var over = false { didSet { needsDisplay = true } }

    init(_ text: String, chosen: Bool, quiet: Bool = false) {
        self.chosen = chosen
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: text)
        title.font = NSFont.systemFont(ofSize: TextSize.body, weight: chosen ? .semibold : .regular)
        title.textColor = quiet && !chosen ? .secondaryLabelColor : .labelColor
        title.lineBreakMode = .byTruncatingTail
        let tick = NSImageView(image: symbol("checkmark", "Chosen", size: 11, weight: .semibold))
        tick.contentTintColor = .labelColor
        tick.isHidden = !chosen
        for v in [title, tick] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: tick.leadingAnchor, constant: -6),
            tick.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            tick.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        onHover = { [weak self] on in self?.over = on }
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onChoose?() }
    override func draw(_ dirtyRect: NSRect) {
        guard chosen || over else { return }
        NSColor.labelColor.withAlphaComponent(chosen ? 0.10 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

private final class SchemaFlipped: NSView {
    override var isFlipped: Bool { true }
}

/// The Schema panel. At its head, which stack is being shown: the default, or one project's. Under
/// that, the map of groups on the left, and on the right the level, name and description of the
/// one that is selected, or, when a group that holds things is being removed, what to do with them.
final class SchemaPanel: SettingsPanel, NSTextFieldDelegate {
    /// The project whose stack is showing; nil is the default.
    private var stack: UUID?
    private var root = SchemaTrial.saved
    private var selected: UUID?
    /// A group that holds things and has been asked to go: the right pane asks what becomes of them.
    private var removing: UUID?
    private var creating = false

    private let stackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stackNote = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let newName = NSTextField()
    private let createButton = NSButton(title: "Create", target: nil, action: nil)
    private let cancelCreate = NSButton(title: "Cancel", target: nil, action: nil)
    private let newRow = NSStackView()
    private let map = NSStackView()
    private let addNext = NSButton(title: "", target: nil, action: nil)
    private let levelTitle = NSTextField(labelWithString: "")
    /// The names on offer, as a column that scrolls inside the pane: Custom Name first, then the list for the level.
    private let names = NSStackView()
    private let namesScroll = FittedScrollView()
    private let customName = NSTextField()
    private let about = NSTextField()
    private let hint = NSTextField(wrappingLabelWithString: "")
    /// The rows holding the box for a name of the user's own and its label; they take no room while a listed name is chosen.
    private var customRow: NSGridRow!
    private var customHead: NSGridRow!
    private var shownLevel = 0
    private let detail = NSView()
    private let removal = NSStackView()

    private var lib: Library { library.library }
    private var primary: String { SchemaTrial.primaryName }

    private func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        return l
    }
    private func push(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    override func loadView() {
        selected = root.id
        // The head: which stack, and making a new one.
        stackPopup.target = self
        stackPopup.action = #selector(stackChosen)
        stackNote.textColor = .secondaryLabelColor
        stackNote.preferredMaxLayoutWidth = 400
        for (b, action) in [(resetButton, #selector(resetTapped)), (createButton, #selector(createTapped)), (cancelCreate, #selector(cancelCreateTapped))] {
            b.bezelStyle = .rounded
            b.target = self
            b.action = action
        }
        newName.delegate = self
        newName.target = self
        newName.action = #selector(createTapped)
        newRow.setViews([newName, createButton, cancelCreate], in: .leading)
        newRow.spacing = 8
        let head = NSStackView(views: [caption("Stack"), stackPopup, resetButton])
        head.spacing = 8

        // Left: the map.
        let mapTitle = NSTextField(labelWithString: "Structure")
        mapTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        map.orientation = .vertical
        map.alignment = .leading
        map.spacing = 2
        addNext.bezelStyle = .rounded
        addNext.target = self
        addNext.action = #selector(addNextTapped)
        let top = NSStackView(views: [head, stackNote, newRow])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 8
        let left = NSView(), right = NSView(), divider = NSBox()
        divider.boxType = .separator
        for v in [top, mapTitle, map, addNext] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; left.addSubview(v) }

        // Right: the selected group.
        levelTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let namesTitle = caption("Name")
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 1
        let page = SchemaFlipped()
        for v in [names, page] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        page.addSubview(names)
        namesScroll.documentView = page
        namesScroll.hasVerticalScroller = true
        namesScroll.autohidesScrollers = true
        namesScroll.drawsBackground = false
        let column = NSBox()
        column.boxType = .custom
        column.cornerRadius = 8
        column.borderWidth = 1
        column.borderColor = .separatorColor
        column.fillColor = .clear
        column.contentViewMargins = .zero
        namesScroll.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(namesScroll)
        customName.placeholderString = "Type A Name"
        customName.delegate = self
        about.placeholderString = "What This Group Holds"
        about.delegate = self
        about.usesSingleLineMode = false
        about.cell?.wraps = true
        about.cell?.isScrollable = false
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 250
        let grid = NSGridView(views: [[caption("Custom Name")], [customName], [caption("Description")], [about], [hint]])
        grid.rowSpacing = 6
        grid.column(at: 0).width = 250
        grid.row(at: 2).topPadding = 10
        grid.row(at: 4).topPadding = 10
        customRow = grid.row(at: 1)
        customHead = grid.row(at: 0)
        for v in [namesTitle, column, grid] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; detail.addSubview(v) }
        removal.orientation = .vertical
        removal.alignment = .leading
        removal.spacing = 12
        for v in [levelTitle, detail, removal] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(v) }

        let v = NSView()
        for part in [left, divider, right] as [NSView] { part.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(part) }
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsPanel.minimumWidth),
            v.heightAnchor.constraint(equalToConstant: 560),
            left.topAnchor.constraint(equalTo: v.topAnchor, constant: 22),
            left.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -22),
            left.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 36),
            left.widthAnchor.constraint(equalToConstant: 420),
            divider.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 24),
            divider.topAnchor.constraint(equalTo: left.topAnchor),
            divider.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            right.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 28),
            right.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -36),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),

            top.topAnchor.constraint(equalTo: left.topAnchor),
            top.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            top.trailingAnchor.constraint(lessThanOrEqualTo: left.trailingAnchor),
            stackPopup.widthAnchor.constraint(equalToConstant: 220),
            newName.widthAnchor.constraint(equalToConstant: 220),
            mapTitle.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 20),
            mapTitle.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            map.topAnchor.constraint(equalTo: mapTitle.bottomAnchor, constant: 10),
            map.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            // Under the last group on the map, at its right.
            addNext.topAnchor.constraint(equalTo: map.bottomAnchor, constant: 12),
            addNext.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),

            levelTitle.topAnchor.constraint(equalTo: right.topAnchor),
            levelTitle.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            detail.topAnchor.constraint(equalTo: levelTitle.bottomAnchor, constant: 14),
            detail.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: right.bottomAnchor),
            removal.topAnchor.constraint(equalTo: levelTitle.bottomAnchor, constant: 14),
            removal.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            removal.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor),
            // The names: a column the height of the pane, scrolling inside itself.
            namesTitle.topAnchor.constraint(equalTo: detail.topAnchor),
            namesTitle.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            column.topAnchor.constraint(equalTo: namesTitle.bottomAnchor, constant: 6),
            column.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            column.widthAnchor.constraint(equalToConstant: 220),
            column.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
            namesScroll.topAnchor.constraint(equalTo: column.topAnchor, constant: 4),
            namesScroll.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -4),
            namesScroll.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 2),
            namesScroll.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -2),
            page.topAnchor.constraint(equalTo: namesScroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: namesScroll.contentView.leadingAnchor),
            page.widthAnchor.constraint(equalTo: namesScroll.contentView.widthAnchor),
            names.topAnchor.constraint(equalTo: page.topAnchor),
            names.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            names.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            names.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            // Beside the column: the name typed by hand when Custom is chosen, and the description.
            grid.topAnchor.constraint(equalTo: namesTitle.topAnchor),
            grid.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: 24),
            about.heightAnchor.constraint(equalToConstant: 64),
        ])
        view = v
        show()
    }

    /// For a trial run: "<project name>" shows that project's stack, and "<project name>/<group name>" presses the bin on one of its groups.
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !rehearsed, let ask = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_SCHEMA"] else { return }
        rehearsed = true
        let parts = ask.split(separator: "/", maxSplits: 1).map(String.init)
        guard let project = lib.orderedProjects.first(where: { $0.name == parts[0] }) else { return }
        stack = project.id
        load()
        selected = root.id
        if parts.count > 1, let row = SchemaTrial.rows(of: root).first(where: { $0.node.name == parts[1] }) { remove(row.node, level: row.level) } else { show() }
    }
    private var rehearsed = false

    override func refresh() {
        guard isViewLoaded else { return }
        // A project that has gone takes its stack off the panel.
        if let id = stack, lib.project(id) == nil { stack = nil }
        load()
        show()
    }

    /// Reads the stack that is showing from where it is kept.
    private func load() { root = stack.map { SchemaTrial.schema(for: $0) } ?? SchemaTrial.saved }

    private var current: (node: SchemaNode, level: Int)? { SchemaTrial.rows(of: root).first { $0.node.id == selected } }

    // MARK: What a group holds

    /// The projects a group on this stack stands in: the one whose stack it is, or every project that follows the default.
    private var projects: [UUID] { stack.map { [$0] } ?? lib.orderedProjects.map { $0.id }.filter { !SchemaTrial.hasOwn($0) } }

    private func palettes(_ role: SchemaRole, in project: UUID) -> [UUID] {
        lib.palettes(in: project).filter { $0.isTypography == (role == .typography) }.map { $0.id }
    }
    private func tags(in project: UUID) -> [String] { lib.allTags.filter { lib.project(ofTag: $0) == project } }

    /// How many things one of the app's own groups holds, across `projects`. Information holds the Overview page, which is the project's own, and counts as nothing to lose.
    private func count(_ node: SchemaNode, level: Int) -> Int {
        guard level == 2, let role = SchemaTrial.role(of: node) else { return 0 }
        switch role {
        case .information: return 0
        case .palettes, .typography: return projects.reduce(0) { $0 + palettes(role, in: $1).count }
        case .tags: return projects.reduce(0) { $0 + tags(in: $1).count }
        }
    }
    private func noun(_ role: SchemaRole?, _ n: Int) -> String {
        switch role {
        case .typography?: return n == 1 ? "Typography Palette" : "Typography Palettes"
        case .tags?: return n == 1 ? "Tag" : "Tags"
        default: return n == 1 ? "Palette" : "Palettes"
        }
    }

    // MARK: Showing

    /// Draws the head, the map and the right pane afresh.
    private func show(focusName: Bool = false) {
        if current == nil { selected = root.id }
        if let going = removing, !SchemaTrial.rows(of: root).contains(where: { $0.node.id == going }) { removing = nil }

        // The head.
        stackPopup.removeAllItems()
        stackPopup.addItem(withTitle: "Default")
        stackPopup.menu?.addItem(.separator())
        for p in lib.orderedProjects {
            stackPopup.addItem(withTitle: p.name)
            stackPopup.lastItem?.representedObject = p.id
            stackPopup.lastItem?.image = symbol(SchemaTrial.hasOwn(p.id) ? "square.stack.3d.up.fill" : "square.stack.3d.up", "", size: 11)
        }
        stackPopup.menu?.addItem(.separator())
        stackPopup.addItem(withTitle: "New \(primary)\u{2026}")
        stackPopup.lastItem?.tag = -1
        if let id = stack, let at = stackPopup.itemArray.firstIndex(where: { $0.representedObject as? UUID == id }) { stackPopup.selectItem(at: at) } else { stackPopup.selectItem(at: 0) }
        let own = stack.map { SchemaTrial.hasOwn($0) } ?? false
        resetButton.isHidden = !own
        let following = lib.orderedProjects.filter { !SchemaTrial.hasOwn($0.id) }.count
        stackNote.stringValue = stack == nil ? "What Every \(primary) Follows Unless It Has A Stack Of Its Own. \(following) Of \(lib.orderedProjects.count) Follow It."
            : own ? "This \(primary) Has A Stack Of Its Own." : "This \(primary) Follows Default. Change Anything Here And It Gets A Stack Of Its Own."
        newRow.isHidden = !creating
        newName.placeholderString = "Name The New \(primary)"

        // The map.
        map.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let projectName = stack.flatMap { lib.project($0)?.name }
        for (node, level) in SchemaTrial.rows(of: root) {
            let n = count(node, level: level)
            let row = SchemaRowView(node, level: level, selected: node.id == selected, shown: level == 1 ? projectName : nil,
                                    holds: n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil)
            row.onSelect = { [weak self] in self?.removing = nil; self?.selected = node.id; self?.show() }
            row.onChild = { [weak self] in self?.add(child: true, at: node.id) }
            row.onSibling = { [weak self] in self?.add(child: false, at: node.id) }
            row.onRemove = { [weak self] in self?.remove(node, level: level) }
            map.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: map.widthAnchor).isActive = true
        }
        guard let (node, level) = current else { return }
        addNext.title = level == 1 ? "Add \(SchemaTrial.title(forLevel: 2))" : "Add Next Level \(level) Group"
        levelTitle.stringValue = SchemaTrial.title(forLevel: level)

        // The right pane: what to do with a group's contents, or the group's own details.
        let asking = removing == node.id
        removal.isHidden = !asking
        detail.isHidden = asking
        if asking { showRemoval(node, level: level); return }

        // On a project's stack the main group is the project itself, which is named on its own page.
        let named = level == 1 && stack != nil
        let offered = named ? [] : SchemaTrial.names(forLevel: level)
        // A name of the user's own shows the box to type it in; a name from the list hides it.
        let custom = !named && !offered.contains(node.name)
        names.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func add(_ row: SchemaNameRow, _ choose: @escaping () -> Void) {
            row.onChoose = choose
            names.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: names.widthAnchor).isActive = true
        }
        if named {
            add(SchemaNameRow(projectName ?? "", chosen: true)) {}
        } else {
            add(SchemaNameRow("Custom Name\u{2026}", chosen: custom, quiet: true)) { [weak self] in self?.choose(name: nil) }
            for name in offered { add(SchemaNameRow(name, chosen: !custom && name == node.name)) { [weak self] in self?.choose(name: name) } }
        }
        // A different group's level starts its column at the top.
        if level != shownLevel {
            shownLevel = level
            namesScroll.contentView.scroll(to: .zero)
            namesScroll.reflectScrolledClipView(namesScroll.contentView)
        }
        customRow.isHidden = !custom
        customHead.isHidden = !custom
        if customName.currentEditor() == nil { customName.stringValue = custom ? node.name : "" }
        if about.currentEditor() == nil { about.stringValue = node.about }
        hint.stringValue = named ? "This stack is the \(primary) \(projectName ?? "") itself. What a \(primary) is called is set on the Default stack."
            : "The sidebar follows this as you change it. Information, Palettes, Typography and Tags hold what they always have; any other group is a label for now, holding nothing."
        if focusName, custom { view.window?.makeFirstResponder(customName) }
    }

    /// A group that holds things has been asked to go: say what it holds, and offer to keep them under a new name, or to delete them.
    private func showRemoval(_ node: SchemaNode, level: Int) {
        removal.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let role = SchemaTrial.role(of: node), n = count(node, level: level), things = "\(n) \(noun(role, n))"
        let title = NSTextField(labelWithString: "\(node.name) Holds \(things)")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        func words(_ text: String) -> NSTextField {
            let l = NSTextField(wrappingLabelWithString: text)
            l.textColor = .secondaryLabelColor
            l.preferredMaxLayoutWidth = 440
            return l
        }
        removal.addArrangedSubview(title)
        if let project = stack {
            let name = lib.project(project)?.name ?? ""
            removal.addArrangedSubview(words("A group that holds things cannot simply go: they would still be in \(name), with nowhere to show. Keep them and give the group another name, or delete them and remove the group."))
            removal.addArrangedSubview(push("Keep The \(noun(role, n)) And Rename The Group", #selector(keepAndRename)))
            let delete = push("Delete The \(things) And Remove The Group", #selector(deleteAndRemove))
            delete.hasDestructiveAction = true
            delete.contentTintColor = .systemRed
            removal.addArrangedSubview(delete)
            if lib.project(project)?.isLocked == true {
                delete.isEnabled = false
                removal.addArrangedSubview(words("\(name) is locked, so nothing in it can be deleted. Unlock it in the sidebar first."))
            } else {
                removal.addArrangedSubview(words(role == .tags ? "Deleting a tag takes it off everything that carries it." : "Deleting a palette leaves its colours in All Swatches, and the deletion is recorded as a step in History."))
            }
        } else {
            removal.addArrangedSubview(words("These are spread over the \(projects.count) that follow Default. On Default the group can be renamed, and they stay where they are. To delete them, choose each \(primary) under Stack and remove the group there."))
            removal.addArrangedSubview(push("Keep The \(noun(role, n)) And Rename The Group", #selector(keepAndRename)))
        }
        removal.addArrangedSubview(push("Cancel", #selector(cancelRemoval)))
    }

    // MARK: Changing

    /// Keeps the stack that is showing. A project that was following the default gets a stack of its own the first time anything on it is changed.
    private func keep() {
        if let id = stack { SchemaTrial.setSchema(root, for: id) } else { SchemaTrial.saved = root }
    }

    private func add(child: Bool, at id: UUID) {
        removing = nil
        let result = child ? SchemaTrial.addingChild(to: id, in: root) : SchemaTrial.addingSibling(after: id, in: root)
        root = result.tree
        if let made = result.added { selected = made }
        keep()
        view.window?.makeFirstResponder(nil)
        show()
    }

    /// The bin on a group: gone at once when it holds nothing; asked about when it holds something.
    private func remove(_ node: SchemaNode, level: Int) {
        guard count(node, level: level) == 0 else {
            removing = node.id
            selected = node.id
            show()
            return
        }
        root = SchemaTrial.removing(node.id, from: root)
        keep()
        show()
    }

    @objc private func cancelRemoval() { removing = nil; show() }

    /// Keeps what the group holds: the group stays, and its name is ready to be changed.
    @objc private func keepAndRename() {
        removing = nil
        guard let id = selected else { return }
        root = SchemaTrial.changing(id, in: root) { $0.role = SchemaTrial.role(of: $0); $0.name = "" }   // it keeps its part, whatever it is called next
        keep()
        show(focusName: true)
    }

    /// Deletes what the group holds in this project, then takes the group off its stack.
    @objc private func deleteAndRemove() {
        guard let project = stack, let (node, _) = current, let role = SchemaTrial.role(of: node) else { return }
        switch role {
        case .palettes, .typography:
            let ids = palettes(role, in: project)
            library.apply(role == .typography ? "Delete Typography Palettes" : "Delete Palettes") { lib in ids.forEach { lib.deleteSwatch($0) } }
        case .tags: library.deleteTags(tags(in: project))
        case .information: break
        }
        removing = nil
        // Only if they have really gone: a locked project refuses the change.
        guard count(node, level: 2) == 0 else { show(); return }
        root = SchemaTrial.removing(node.id, from: root)
        keep()
        show()
    }

    /// Under the map: the next group at the selected one's level, or the first inside the main group.
    @objc private func addNextTapped() {
        guard let (node, level) = current else { return }
        add(child: level == 1, at: node.id)
    }

    /// A name from the column, or nil for Custom, which empties the name ready to be typed.
    private func choose(name: String?) {
        guard let id = selected else { return }
        if name == nil, let now = current, !SchemaTrial.names(forLevel: now.level).contains(now.node.name) {
            view.window?.makeFirstResponder(customName)   // already a name of the user's own: go to it, and keep it
            return
        }
        // One of the app's own groups keeps its part under its new name.
        root = SchemaTrial.changing(id, in: root) { $0.role = SchemaTrial.role(of: $0); $0.name = name ?? "" }
        keep()
        view.window?.makeFirstResponder(nil)
        show(focusName: name == nil)
    }

    // MARK: Stacks

    @objc private func stackChosen() {
        removing = nil
        view.window?.makeFirstResponder(nil)
        if stackPopup.selectedItem?.tag == -1 {
            creating = true
            show()
            view.window?.makeFirstResponder(newName)
            return
        }
        creating = false
        stack = stackPopup.selectedItem?.representedObject as? UUID
        load()
        selected = root.id
        show()
    }

    /// Puts a project back on the default, letting go of its own stack.
    @objc private func resetTapped() {
        guard let id = stack else { return }
        SchemaTrial.setSchema(nil, for: id)
        removing = nil
        load()
        selected = root.id
        show()
    }

    @objc private func cancelCreateTapped() {
        creating = false
        newName.stringValue = ""
        show()
    }

    /// Makes a new project, as New Project does, and gives it a stack of its own to shape, starting as the default.
    @objc private func createTapped() {
        let name = newName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard creating, ProjectField.problem(name: name, values: [:]) == nil else { NSSound.beep(); return }
        var made: UUID?
        library.apply("New Project") { lib in
            let id = lib.createProject(named: name)
            let organisation = ProjectField.tidy(Prefs.organisation)
            if !organisation.isEmpty { lib.setProjectDetails(id, organisation) }
            made = id
        }
        guard let id = made, lib.project(id) != nil else { NSSound.beep(); return }
        SchemaTrial.setSchema(SchemaTrial.saved, for: id)
        creating = false
        newName.stringValue = ""
        stack = id
        load()
        selected = root.id
        show()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let id = selected, let field = obj.object as? NSTextField, field === customName || field === about else { return }
        root = SchemaTrial.changing(id, in: root) { node in
            if field === customName { node.name = field.stringValue } else { node.about = field.stringValue }
        }
        keep()
        show()
    }
}
