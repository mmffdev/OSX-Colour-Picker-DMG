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

    init(_ node: SchemaNode, level: Int, selected: Bool) {
        isSelected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let badge = NSTextField(labelWithString: "\(level)")
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.caption, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .center
        badge.toolTip = SchemaTrial.title(forLevel: level)
        let name = NSTextField(labelWithString: node.name.isEmpty ? "Unnamed" : node.name)
        name.font = NSFont.systemFont(ofSize: TextSize.body, weight: level == 1 ? .semibold : .regular)
        name.textColor = node.name.isEmpty ? .tertiaryLabelColor : .labelColor
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
        for v in [badge, name, actions] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let indent = 10 + CGFloat(level - 1) * 20
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
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

/// The Schema panel: the map of groups on the left, and on the right the level, name and description of the one that is selected.
final class SchemaPanel: SettingsPanel, NSTextFieldDelegate {
    private var root = SchemaTrial.saved
    private var selected: UUID?
    private let map = NSStackView()
    private let addNext = NSButton(title: "", target: nil, action: nil)
    private let levelTitle = NSTextField(labelWithString: "")
    /// The names on offer, as a column that scrolls inside the pane: Custom Name first, then the list for the level.
    private let names = NSStackView()
    private let namesScroll = FittedScrollView()
    private let customName = NSTextField()
    private let about = NSTextField()
    /// The rows holding the box for a name of the user's own and its label; they take no room while a listed name is chosen.
    private var customRow: NSGridRow!
    private var customHead: NSGridRow!
    private var shownLevel = 0

    private func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = .secondaryLabelColor
        l.alignment = .right
        return l
    }

    override func loadView() {
        selected = root.id
        // Left: the map.
        let mapTitle = NSTextField(labelWithString: "Structure")
        mapTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        map.orientation = .vertical
        map.alignment = .leading
        map.spacing = 2
        addNext.bezelStyle = .rounded
        addNext.target = self
        addNext.action = #selector(addNextTapped)
        let left = NSView(), right = NSView(), divider = NSBox()
        divider.boxType = .separator
        for v in [mapTitle, map, addNext] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; left.addSubview(v) }

        // Right: the selected group.
        levelTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let namesTitle = caption("Name")
        namesTitle.alignment = .left
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
        let hint = NSTextField(wrappingLabelWithString: "The sidebar follows this as you change it. Information, Palettes, Typography and Tags hold what they always have; any other group is a label for now, shown in every project and holding nothing. Removing a group hides it and loses nothing.")
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 250
        let customTitle = caption("Custom Name"), aboutTitle = caption("Description")
        customTitle.alignment = .left
        aboutTitle.alignment = .left
        let grid = NSGridView(views: [[customTitle], [customName], [aboutTitle], [about], [hint]])
        grid.rowSpacing = 6
        grid.column(at: 0).width = 250
        grid.row(at: 2).topPadding = 10
        grid.row(at: 4).topPadding = 10
        customRow = grid.row(at: 1)
        customHead = grid.row(at: 0)
        for v in [levelTitle, namesTitle, column, grid] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(v) }

        let v = NSView()
        for part in [left, divider, right] as [NSView] { part.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(part) }
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsPanel.minimumWidth),
            v.heightAnchor.constraint(equalToConstant: 470),
            left.topAnchor.constraint(equalTo: v.topAnchor, constant: 22),
            left.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -22),
            left.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 36),
            left.widthAnchor.constraint(equalToConstant: 400),
            divider.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 24),
            divider.topAnchor.constraint(equalTo: left.topAnchor),
            divider.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            right.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 28),
            right.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -36),
            right.topAnchor.constraint(equalTo: left.topAnchor),
            right.bottomAnchor.constraint(equalTo: left.bottomAnchor),

            mapTitle.topAnchor.constraint(equalTo: left.topAnchor),
            mapTitle.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),
            map.topAnchor.constraint(equalTo: mapTitle.bottomAnchor, constant: 12),
            map.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            // Under the last group on the map, at its right.
            addNext.topAnchor.constraint(equalTo: map.bottomAnchor, constant: 12),
            addNext.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),

            levelTitle.topAnchor.constraint(equalTo: right.topAnchor),
            levelTitle.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            // The names: a column the height of the pane, scrolling inside itself.
            namesTitle.topAnchor.constraint(equalTo: levelTitle.bottomAnchor, constant: 14),
            namesTitle.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            column.topAnchor.constraint(equalTo: namesTitle.bottomAnchor, constant: 6),
            column.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            column.widthAnchor.constraint(equalToConstant: 220),
            column.bottomAnchor.constraint(equalTo: right.bottomAnchor),
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

    private var current: (node: SchemaNode, level: Int)? { SchemaTrial.rows(of: root).first { $0.node.id == selected } }

    /// Draws the map and the selected group's details afresh.
    private func show(focusName: Bool = false) {
        if current == nil { selected = root.id }
        map.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (node, level) in SchemaTrial.rows(of: root) {
            let row = SchemaRowView(node, level: level, selected: node.id == selected)
            row.onSelect = { [weak self] in self?.selected = node.id; self?.show() }
            row.onChild = { [weak self] in self?.add(child: true, at: node.id) }
            row.onSibling = { [weak self] in self?.add(child: false, at: node.id) }
            row.onRemove = { [weak self] in
                guard let self = self else { return }
                self.root = SchemaTrial.removing(node.id, from: self.root)
                self.keep()
                self.show()
            }
            map.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: map.widthAnchor).isActive = true
        }
        guard let (node, level) = current else { return }
        addNext.title = level == 1 ? "Add \(SchemaTrial.title(forLevel: 2))" : "Add Next Level \(level) Group"
        levelTitle.stringValue = SchemaTrial.title(forLevel: level)
        let offered = SchemaTrial.names(forLevel: level)
        // A name of the user's own shows the box to type it in; a name from the list hides it.
        let custom = !offered.contains(node.name)
        names.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func add(_ row: SchemaNameRow, _ choose: @escaping () -> Void) {
            row.onChoose = choose
            names.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: names.widthAnchor).isActive = true
        }
        add(SchemaNameRow("Custom Name\u{2026}", chosen: custom, quiet: true)) { [weak self] in self?.choose(name: nil) }
        for name in offered { add(SchemaNameRow(name, chosen: !custom && name == node.name)) { [weak self] in self?.choose(name: name) } }
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
        if focusName, custom { view.window?.makeFirstResponder(customName) }
    }

    private func keep() { SchemaTrial.saved = root }

    private func add(child: Bool, at id: UUID) {
        let result = child ? SchemaTrial.addingChild(to: id, in: root) : SchemaTrial.addingSibling(after: id, in: root)
        root = result.tree
        if let made = result.added { selected = made }
        keep()
        view.window?.makeFirstResponder(nil)
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
        root = SchemaTrial.changing(id, in: root) { $0.name = name ?? "" }
        keep()
        view.window?.makeFirstResponder(nil)
        show(focusName: name == nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let id = selected, let field = obj.object as? NSTextField else { return }
        root = SchemaTrial.changing(id, in: root) { node in
            if field === customName { node.name = field.stringValue } else { node.about = field.stringValue }
        }
        keep()
        show()
    }
}
