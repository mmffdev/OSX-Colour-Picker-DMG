import AppKit

// ---------- Settings ▸ Schema ----------
//
// How a catalogue is laid out, as the user names it, from the top down:
//
//   Level 0  a collection: Projects, Clients, Our Own Work. Each is a heading in rail1.
//   Level 1  optionally, what its members are grouped under: a Client, holding its Contracts.
//   then     the member itself: a Project, a Contract. This is the app's project, with its files.
//   below    the groups inside a member, as deep as wanted: the member's stack.
//
// Every collection has a default stack that its members follow, and any member can be given a
// stack of its own. Four of a stack's groups are the app's own, and hold what they always have:
// Information, Palettes, Typography and Tags. Any other group is a label only, for now: it shows
// in the member and holds nothing.
//
// All of it is kept with the app's settings for the moment, not in the catalogue's files, so it
// does not travel to another Mac yet. Which collection a project is in is kept by the project's
// id, so nothing in a project's own files is touched.

/// One group in a stack: what it is called, what it is for, and the groups inside it.
struct SchemaNode: Codable, Equatable {
    var id = UUID()
    var name: String
    var about = ""
    var children: [SchemaNode] = []
    /// Which of the app's own groups this is, whatever it has been renamed to; nil for a group that is a label only.
    var role: SchemaRole? = nil
    /// The type chosen for the group on the schema page, which its name starts as and may leave: a group typed Assets
    /// can be called Props and still be the Assets of its level, so no sibling can be typed Assets again.
    var kind: String? = nil
}

/// The groups inside a project that the app fills itself.
enum SchemaRole: String, Codable, CaseIterable {
    case information, palettes, typography, tags
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What a collection's members are grouped under: one client, say.
struct SchemaFolder: Codable, Equatable {
    var id = UUID()
    var name: String
    /// The folder this one sits in, for a level below the first; nil at the first level. Since 2026-10-09 levels nest to any depth.
    var parent: UUID? = nil
}

/// A collection: its heading, how its members are grouped if they are, and the stack they follow.
struct SchemaCollection: Codable, Equatable {
    var id = UUID()
    var name: String
    var about = ""
    /// What the members are grouped under, such as "Client"; nil when they sit straight under the heading.
    var folderName: String? = nil
    var folders: [SchemaFolder] = []
    /// The default stack. Its top is the member itself, named for what a member is called: Project, Contract.
    var stack: SchemaNode
    /// The template file the Master Template was copied from, if any; the copy is the collection's own from then on.
    var templateID: UUID? = nil
    /// What each level between the heading and a member is called, top down, such as Client then Stream; `folderName` is the first of them.
    var levelNames: [String]? = nil

    /// The levels between, top down: `levelNames`, or the one `folderName`, or none.
    var levels: [String] { levelNames ?? (folderName.map { [$0] } ?? []) }
    /// The folders directly inside `parent`, or at the first level for nil.
    func children(of parent: UUID?) -> [SchemaFolder] { folders.filter { $0.parent == parent } }
    /// The folders from the first level down to `folder`, itself last; empty when it is not here.
    func chain(to folder: UUID) -> [SchemaFolder] {
        var out: [SchemaFolder] = [], at: UUID? = folder, guardCount = 0
        while let id = at, let f = folders.first(where: { $0.id == id }), guardCount < 64 { out.insert(f, at: 0); at = f.parent; guardCount += 1 }
        return out
    }
    /// What a folder at this depth is called: the level's name, or the last level's for one deeper than the names go.
    func levelName(atDepth d: Int) -> String {
        let l = levels
        return l.isEmpty ? "Group" : l[min(d, l.count - 1)]
    }
    /// Every folder beneath `folder`, at any depth, itself not included.
    func descendants(of folder: UUID) -> [SchemaFolder] { children(of: folder).flatMap { [$0] + descendants(of: $0.id) } }
}

/// A shape a work group can be made from, kept as a file of its own in the catalogue's Templates folder.
struct SchemaTemplate: Codable, Equatable {
    var id = UUID()
    var name: String
    var about = ""
    var stack: SchemaNode
    var changedAt: Date
}

/// Where a project sits: its collection, and the folder in it, if any.
struct SchemaPlace: Codable, Equatable {
    var collection: UUID
    var folder: UUID? = nil
}

extension Notification.Name {
    static let schemaDidChange = Notification.Name("schemaDidChange")
}

enum SchemaTrial {
    /// Names offered for a collection, for what groups its members, for a member, and for the groups inside one.
    static let collectionNames = ["Projects", "Clients", "Customers", "Our Own Work", "Studio", "Internal", "Brands", "Campaigns", "Productions", "Personal", "Archive"]
    static let folderNames = ["Client", "Customer", "Brand", "Account", "Agency", "Department", "Team", "Publisher", "Studio"]
    static let primaryNames = ["Project", "Contract", "Client", "Customer", "Group", "Brand", "Campaign", "Job", "Production", "Title", "Account"]
    static let nestedNames = ["Palettes", "Typography", "Assets", "Characters", "Environments", "Props", "Vehicles", "Textures", "Materials",
                              "Interface", "Icons", "Logos", "Photography", "Illustration", "Video", "Print", "Packaging", "Social", "Web",
                              "Deliverables", "References", "Scope", "Documents", "Information"]

    static func names(forLevel level: Int) -> [String] { level == 1 ? primaryNames : nestedNames }

    /// "Level 0: Collection", "Level 1: Primary Group", "Level 2: Secondary Group", and so on down.
    static func title(forLevel level: Int) -> String {
        if level == 0 { return "Level 0: Collection" }
        let words = ["Primary", "Secondary", "Tertiary", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth"]
        return "Level \(level): " + (words.indices.contains(level - 1) ? words[level - 1] + " Group" : "Group")
    }

    /// The structure the app has always had: a Project, holding Information, Palettes, Typography and Tags.
    static var start: SchemaNode {
        SchemaNode(name: "Project", children: SchemaRole.allCases.map { SchemaNode(name: $0.title, role: $0) })
    }

    // MARK: Collections

    /// The first collection is the one every project was in before there were collections, and is where a project with no place of its own still is.
    static let firstCollection = UUID(uuidString: "C0110000-0000-4000-8000-000000000001") ?? UUID()

    // MARK: Where the schema is kept: in the catalogue's folders

    /// A catalogue's schema is the catalogue's own. Since 2026-10-09 it is the tree of folders itself: each collection's
    /// file holds its Master Template, each member's file holds its own tree, and where a member sits is where its
    /// folder is. In memory it is one `SchemaFile`, read from the tree with the library and written back with it.
    struct SchemaFile: Codable, Equatable {
        var collections: [SchemaCollection]
        var places: [String: SchemaPlace]
        /// The members that have shaped a tree of their own, by the member's id; the rest follow their collection's Master Template.
        var stacks: [String: SchemaNode]?
        /// The templates kept in the catalogue, in the order the index lists them.
        var templates: [SchemaTemplate]?
        /// What a catalogue starts with: the one collection the app has always had.
        static var fresh: SchemaFile { SchemaFile(collections: [SchemaCollection(id: firstCollection, name: "Projects", stack: start)], places: [:]) }
    }
    private static var directory: URL?
    private static var held: SchemaFile?
    /// The store the schema is written through, when a catalogue is open.
    private static var store: LibraryStore?
    /// The library as it stands, from the controller, for the catalogue at this folder and no other, so a schema change is
    /// written with it; nil, or another folder, reads the tree afresh.
    static var library: ((URL) -> Library?)?

    /// The controller points here at the open catalogue whenever it opens one; the schema is read from its tree and written back with the library on every change.
    static func use(store: LibraryStore) {
        let url = store.url.deletingLastPathComponent()
        self.store = store
        guard url.standardizedFileURL != directory?.standardizedFileURL else { return }
        directory = url; held = nil
        NotificationCenter.default.post(name: .schemaDidChange, object: nil)
    }
    static func use(directory url: URL) { use(store: LibraryStore(directory: url, legacyURL: nil)) }
    /// The schema the store read with the library, so it is not read twice.
    static func adopt(_ f: SchemaFile, for dir: URL) {
        guard dir.standardizedFileURL == directory?.standardizedFileURL else { return }
        held = f
    }
    /// The schema held for this folder, if it is the open catalogue's.
    static func schema(for dir: URL) -> SchemaFile? { dir.standardizedFileURL == directory?.standardizedFileURL ? file : nil }
    /// Another catalogue's schema, read from its tree; the open catalogue's is the live one.
    static func read(in dir: URL) -> SchemaFile {
        if dir.standardizedFileURL == directory?.standardizedFileURL { return file }
        return (try? CatalogueTree.read(root: dir, palettes: false).schema) ?? .fresh
    }
    private static var file: SchemaFile {
        if let f = held { return f }
        let f = directory.flatMap { try? CatalogueTree.read(root: $0, palettes: false).schema } ?? .fresh
        held = f
        return f
    }
    private static func write(_ f: SchemaFile) {
        let before = file
        held = f
        if let store = store {
            do { try store.save(library?(store.root) ?? store.load(), schema: f) } catch { Diagnostics.log("schema", "could not write the tree: \(error.localizedDescription)") }
        }
        NotificationCenter.default.post(name: .schemaDidChange, object: nil, userInfo: ["before": before, "after": f])
    }

    /// The whole schema at once, as a share brings it: written through the store like any change.
    static func replace(_ f: SchemaFile) { write(f) }

    /// Every collection, in rail1's order.
    static var collections: [SchemaCollection] {
        get { file.collections }
        set { var f = file; f.collections = newValue; write(f) }
    }

    /// The first collection's default stack: what the schema was before there were collections.
    static var saved: SchemaNode {
        get { collections.first?.stack ?? start }
        set { var all = collections.isEmpty ? SchemaFile.fresh.collections : collections; all[0].stack = newValue; collections = all }
    }

    static var places: [String: SchemaPlace] {
        get { file.places }
        set { var f = file; f.places = newValue; write(f) }
    }
    /// Places a member in another catalogue's schema, written straight to that catalogue's tree.
    static func place(_ project: UUID, in collection: UUID, folder: UUID?, catalogue dir: URL) {
        if dir.standardizedFileURL == directory?.standardizedFileURL { place(project, in: collection, folder: folder); return }
        let other = LibraryStore(directory: dir, legacyURL: nil)
        guard let lib = try? other.load() else { return }
        var f = other.schema
        f.places[project.uuidString] = SchemaPlace(collection: collection, folder: folder)
        try? other.save(lib, schema: f)
    }

    // MARK: Templates

    /// The templates kept in the catalogue, in order.
    static var templates: [SchemaTemplate] {
        get { file.templates ?? [] }
        set { var f = file; f.templates = newValue.isEmpty ? nil : newValue; write(f) }
    }
    /// Keeps a tree as a template of the catalogue, under a name no other template has. Returns the template.
    @discardableResult
    static func saveTemplate(_ stack: SchemaNode, named raw: String, about: String = "", at date: Date = Date()) -> SchemaTemplate {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = uniqueName(base.isEmpty ? "Template" : base, among: templates.map { $0.name })
        let t = SchemaTemplate(name: name, about: about, stack: stack, changedAt: date)
        templates = templates + [t]
        return t
    }
    static func removeTemplate(_ id: UUID) { templates = templates.filter { $0.id != id } }
    /// Makes a template the collection's Master Template: a copy, the collection's own from then on.
    static func apply(template id: UUID, toCollection cid: UUID) {
        guard let t = templates.first(where: { $0.id == id }) else { return }
        changeCollection(cid) { c in
            var stack = t.stack
            stack.name = c.stack.name   // what a member is called stays the collection's
            c.stack = stack
            c.templateID = id
        }
    }
    /// Gives a member a tree of its own, copied from a template.
    static func apply(template id: UUID, toMember pid: UUID) {
        guard let t = templates.first(where: { $0.id == id }) else { return }
        var stack = t.stack
        stack.name = collection(of: pid).stack.name
        setSchema(stack, for: pid)
    }

    /// The collection a project is in: the one it was placed in, while that is still there; otherwise the first; with none at
    /// all, the one a catalogue starts with, which the writer makes the moment a member needs it.
    static func collection(of project: UUID, among all: [SchemaCollection], places: [String: SchemaPlace]) -> SchemaCollection {
        places[project.uuidString].flatMap { place in all.first { $0.id == place.collection } } ?? all.first ?? SchemaFile.fresh.collections[0]
    }
    /// Where a new member goes when nothing says otherwise: the first collection, made now if the catalogue has none.
    static func homeForNewMember() -> SchemaCollection {
        if let first = collections.first { return first }
        collections = SchemaFile.fresh.collections
        return collections[0]
    }
    static func collection(of project: UUID) -> SchemaCollection { collection(of: project, among: collections, places: places) }

    /// The folder a project is in, while its collection groups its members and still has that folder.
    static func folder(of project: UUID, among all: [SchemaCollection], places: [String: SchemaPlace]) -> UUID? {
        let home = collection(of: project, among: all, places: places)
        guard home.folderName != nil, let folder = places[project.uuidString]?.folder, home.folders.contains(where: { $0.id == folder }) else { return nil }
        return folder
    }

    /// Puts a project in a collection, and in one of its folders or none.
    static func place(_ project: UUID, in collection: UUID, folder: UUID?) {
        var all = places
        all[project.uuidString] = SchemaPlace(collection: collection, folder: folder)
        places = all
    }

    static func changeCollection(_ id: UUID, _ change: (inout SchemaCollection) -> Void) {
        var all = collections
        guard let at = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[at])
        collections = all
    }

    // MARK: Stacks

    // A member follows its collection's Master Template until its tree is shaped on the schema page: the first change
    // copies the template into a tree of the member's own, kept in the catalogue's schema file, and from then on the
    // member's tree is its own. Nothing is copied on creation, so a member left alone follows the template as it changes.
    static var own: [String: SchemaNode] {
        get { file.stacks ?? [:] }
        set { var f = file; f.stacks = newValue.isEmpty ? nil : newValue; write(f) }
    }
    static func hasOwn(_ project: UUID) -> Bool { own[project.uuidString] != nil }
    /// The stack a project shows: its own, or its collection's default.
    static func schema(for project: UUID) -> SchemaNode { own[project.uuidString] ?? collection(of: project).stack }
    /// Gives a project a stack of its own, or, with nil, puts it back on its collection's default.
    static func setSchema(_ tree: SchemaNode?, for project: UUID) {
        var all = own
        all[project.uuidString] = tree
        own = all
    }

    /// Which of the app's own groups a group directly inside a member is: the role it was given,
    /// or, for one added by name, the role of that name.
    static func role(of node: SchemaNode) -> SchemaRole? { node.role ?? SchemaRole.allCases.first { $0.title == node.kind } ?? SchemaRole.allCases.first { $0.title == node.name } }
    /// What a group is typed as: the type it was given, or its name when it was only ever named.
    static func type(of node: SchemaNode) -> String { node.kind ?? node.name }

    /// The name for several of a thing: Projects, Companies, Classes.
    static func plural(_ name: String) -> String {
        let lower = name.lowercased()
        guard let last = lower.last else { return name }
        if last == "y", let before = lower.dropLast().last, !"aeiou".contains(before) { return name.dropLast() + "ies" }
        if last == "s" || last == "x" || lower.hasSuffix("ch") || lower.hasSuffix("sh") { return name + "es" }
        return name + "s"
    }

    /// What a member of a collection is called: the name at the top of its default stack.
    static func memberName(of collection: SchemaCollection) -> String {
        let n = collection.stack.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Project" : n
    }

    // MARK: A stack's tree

    /// Every group, top to bottom as the map shows it, with its level: the member is 1.
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
        let used = Set(taken.map { type(of: $0) })
        return names(forLevel: level).first { !used.contains($0) } ?? "New Group"
    }
    /// A new group among these: named and typed as the first type its level has free.
    static func freshNode(level: Int, among taken: [SchemaNode]) -> SchemaNode {
        let name = freshName(level: level, among: taken)
        return SchemaNode(name: name, kind: name)
    }

    /// Adds a group inside the one with this id, last. Returns the tree and the new group's id.
    static func addingChild(to id: UUID, in root: SchemaNode) -> (tree: SchemaNode, added: UUID?) {
        guard let level = rows(of: root).first(where: { $0.node.id == id })?.level else { return (root, nil) }
        var made: UUID?
        let tree = changing(id, in: root) { parent in
            let node = freshNode(level: level + 1, among: parent.children)
            made = node.id
            parent.children.append(node)
        }
        return (tree, made)
    }

    /// Adds a group straight after the one with this id, at its level. The member itself has no siblings.
    static func addingSibling(after id: UUID, in root: SchemaNode) -> (tree: SchemaNode, added: UUID?) {
        var made: UUID?
        func walk(_ n: SchemaNode, _ level: Int) -> SchemaNode {
            var out = n
            if let at = out.children.firstIndex(where: { $0.id == id }) {
                let node = freshNode(level: level + 1, among: out.children)
                made = node.id
                out.children.insert(node, at: at + 1)
                return out
            }
            out.children = out.children.map { walk($0, level + 1) }
            return out
        }
        return (walk(root, 1), made)
    }

    /// Puts a group at this place among its siblings, counting as the list stands before it is taken out.
    static func moving(_ id: UUID, to index: Int, in root: SchemaNode) -> SchemaNode {
        var out = root
        if let from = out.children.firstIndex(where: { $0.id == id }) {
            let node = out.children.remove(at: from)
            var to = min(max(index, 0), out.children.count + 1)
            if from < to { to -= 1 }
            out.children.insert(node, at: min(to, out.children.count))
            return out
        }
        out.children = out.children.map { moving(id, to: index, in: $0) }
        return out
    }

    /// Takes a group out, with everything inside it. The member itself stays.
    static func removing(_ id: UUID, from root: SchemaNode) -> SchemaNode {
        var out = root
        out.children = out.children.filter { $0.id != id }.map { removing(id, from: $0) }
        return out
    }
}

/// One row on the map: its level, its name, what it holds, and, while it is selected or under the pointer, what can be done with it.
private final class SchemaRowView: HoverView {
    var onSelect: (() -> Void)?
    /// Set on a row that can be put in another order among its siblings: the drag ends with where it was dropped,
    /// as an index among the rows that share its parent.
    var onMove: ((Int) -> Void)? { didSet { grip.isHidden = onMove == nil || !(over || isSelected) } }
    /// The rows this one can be dropped among, in order, itself included.
    var siblings: [SchemaRowView] = []
    private let grip = SchemaGrip()
    private var dropLine: CGFloat? { didSet { needsDisplay = true } }
    private let isSelected: Bool
    private let actions = NSStackView()
    private var runs: [() -> Void] = []
    private var over = false { didSet { actions.isHidden = !(over || isSelected); grip.isHidden = onMove == nil || !(over || isSelected); needsDisplay = true } }

    /// `does` is what the row offers, left to right: a symbol, what it says, and what it does.
    init(_ text: String, level: Int, tip: String, selected: Bool, holds: String? = nil, strong: Bool = false, does: [(symbol: String, tip: String, run: () -> Void)]) {
        isSelected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let badge = NSTextField(labelWithString: "\(level)")
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.caption, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .center
        badge.toolTip = tip
        let name = NSTextField(labelWithString: text.isEmpty ? "Unnamed" : text)
        name.font = NSFont.systemFont(ofSize: TextSize.body, weight: strong ? .semibold : .regular)
        name.textColor = text.isEmpty ? .tertiaryLabelColor : .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let held = NSTextField(labelWithString: holds ?? "")
        held.font = NSFont.systemFont(ofSize: TextSize.caption)
        held.textColor = .secondaryLabelColor
        held.setContentCompressionResistancePriority(.required, for: .horizontal)
        runs = does.map { $0.run }
        let buttons = does.enumerated().map { at, one -> NSButton in
            let b = symbolButton(one.symbol, tooltip: one.tip, target: self, action: #selector(actionTapped(_:)))
            b.image = symbol(one.symbol, one.tip, size: 12)
            b.contentTintColor = .secondaryLabelColor
            b.tag = at
            return b
        }
        actions.setViews(buttons, in: .trailing)
        actions.spacing = 10
        actions.isHidden = !selected
        grip.isHidden = true
        grip.toolTip = "Drag To Put This Group In Another Order"
        for v in [grip, badge, name, held, actions] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let indent = 10 + CGFloat(level) * 20
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            grip.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -4),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 10),
            grip.heightAnchor.constraint(equalToConstant: 14),
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

    @objc private func actionTapped(_ sender: NSButton) { if runs.indices.contains(sender.tag) { runs[sender.tag]() } }

    override func mouseDown(with event: NSEvent) {
        guard onMove != nil, grip.frame.insetBy(dx: -6, dy: -8).contains(convert(event.locationInWindow, from: nil)) else { onSelect?(); return }
        drag(from: event)
    }

    /// The row follows the pointer up and down its siblings; a line shows where it would land, and letting go puts it there.
    private func drag(from start: NSEvent) {
        guard let window = window, let parent = superview else { return }
        let mine = siblings.firstIndex { $0 === self } ?? 0
        var target = mine
        var moved = false
        func slot(for event: NSEvent) -> Int {
            let y = parent.convert(event.locationInWindow, from: nil).y
            // Rows are listed top to bottom; the parent's y runs the way its flipping says.
            var at = siblings.count
            for (i, row) in siblings.enumerated() {
                let f = row.frame
                let above = parent.isFlipped ? y < f.midY : y > f.midY
                if above { at = i; break }
            }
            return at
        }
        while true {
            guard let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if event.type == .leftMouseUp { break }
            moved = true
            let at = slot(for: event)
            if at != target {
                target = at
                siblings.forEach { $0.dropLine = nil }
                // The line sits on the top edge of the row at the slot, or under the last when past the end.
                if at < siblings.count { siblings[at].dropLine = parent.isFlipped ? 0 : siblings[at].bounds.height }
                else if let last = siblings.last { last.dropLine = parent.isFlipped ? last.bounds.height : 0 }
            }
            alphaValue = 0.5
        }
        alphaValue = 1
        siblings.forEach { $0.dropLine = nil }
        guard moved else { onSelect?(); return }
        if target != mine, target != mine + 1 { onMove?(target) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || over {
            NSColor.labelColor.withAlphaComponent(isSelected ? 0.10 : 0.05).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        if let y = dropLine {
            NSColor.controlAccentColor.setFill()
            let x = grip.frame.minX
            NSBezierPath(roundedRect: NSRect(x: x, y: max(0, min(y - 1, bounds.height - 2)), width: bounds.width - x - 10, height: 2), xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// The handle a row is dragged by: two columns of three dots.
private final class SchemaGrip: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        for col in 0..<2 {
            for row in 0..<3 {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(col) * 5 + 1, y: CGFloat(row) * 5 + 1, width: 3, height: 3)).fill()
            }
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
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

/// The Schema panel. At its head, which collection and which stack are showing. Under that, the
/// map on the left, from the collection down, and on the right the level, name and description of
/// the row that is selected, or, when a group that holds things is being removed, what to do with them.
final class SchemaPanel: SettingsPanel, NSTextFieldDelegate {
    /// What a selected row on the map is.
    private enum Target {
        /// Level 0: the collection.
        case collection
        /// What the collection's members are grouped under.
        case tier
        /// The top of a project's own stack: the project itself.
        case member(UUID)
        /// A group in the stack, with its level in the stack: the top is 1.
        case node(SchemaNode, Int)
    }
    private enum Making { case nothing, collection, member }

    private var collectionID = SchemaTrial.firstCollection
    /// The project whose stack is showing; nil is the collection's default.
    private var stack: UUID?
    private var root = SchemaTrial.saved
    /// The row that is selected: the collection's id, the tier's, or a group's.
    private var selected: UUID?
    private static let tierRow = UUID(uuidString: "C0110000-0000-4000-8000-0000000000F1") ?? UUID()
    /// A group that holds things and has been asked to go: the right pane asks what becomes of them.
    private var removing: UUID?
    private var making = Making.nothing

    private let collectionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stackPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// Over each column, a few lines on where the user is and what can be done there.
    private let leftHelp = NSTextField(wrappingLabelWithString: "")
    private let rightHelp = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let newName = NSTextField()
    private let createButton = NSButton(title: "Create", target: nil, action: nil)
    private let cancelCreate = NSButton(title: "Cancel", target: nil, action: nil)
    private let newRow = NSStackView()
    private var makingRows: [NSGridRow] = []
    private let map = NSStackView()
    private let addNext = NSButton(title: "", target: nil, action: nil)
    /// Under the map while a member's own stack is open: the member and all it holds, gone after a slide.
    private let removeMemberButton = NSButton(title: "", target: nil, action: nil)
    private let levelTitle = NSTextField(labelWithString: "")
    /// The names on offer, as a column that scrolls inside the pane: Custom Name first, then the list for the level.
    private let names = NSStackView()
    private let namesScroll = FittedScrollView()
    private let customName = NSTextField()
    private let about = NSTextField()
    private var customRow: NSGridRow!, customHead: NSGridRow!, aboutRow: NSGridRow!, aboutHead: NSGridRow!
    private var shownList: [String] = []
    private let detail = NSView()
    private let removal = NSStackView()

    private var lib: Library { library.library }
    private var all: [SchemaCollection] = SchemaTrial.collections
    private var collection: SchemaCollection { all.first { $0.id == collectionID } ?? all.first ?? SchemaTrial.SchemaFile.fresh.collections[0] }
    /// What a member of the collection showing is called: Project, Contract.
    private var member: String { SchemaTrial.memberName(of: collection) }
    /// How far the stack's levels are pushed down: by one when the collection groups its members.
    private var offset: Int { collection.folderName == nil ? 0 : 1 }
    /// The projects in the collection showing.
    private var members: [Project] {
        let places = SchemaTrial.places
        return lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: all, places: places).id == collectionID }
    }

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
        selected = collectionID
        // The head: which collection, which stack, and making a new one of either.
        collectionPopup.target = self
        collectionPopup.action = #selector(collectionChosen)
        stackPopup.target = self
        stackPopup.action = #selector(stackChosen)
        for help in [leftHelp, rightHelp] {
            help.textColor = .secondaryLabelColor
            help.preferredMaxLayoutWidth = 420
        }
        for (b, action) in [(resetButton, #selector(resetTapped)), (createButton, #selector(createTapped)), (cancelCreate, #selector(cancelCreateTapped))] {
            b.bezelStyle = .rounded
            b.target = self
            b.action = action
        }
        newName.delegate = self
        newName.target = self
        newName.action = #selector(createTapped)
        // The box for a new name sits under the dropdowns, on their edges, with its buttons under it: one neat stack.
        newRow.setViews([createButton, cancelCreate], in: .leading)
        newRow.spacing = 8
        let heads = NSGridView(views: [[caption("Collection"), collectionPopup, NSGridCell.emptyContentView], [caption("Stack"), stackPopup, resetButton],
                                       [NSGridCell.emptyContentView, newName, NSGridCell.emptyContentView], [NSGridCell.emptyContentView, newRow, NSGridCell.emptyContentView]])
        heads.rowSpacing = 8
        heads.columnSpacing = 8
        heads.column(at: 0).xPlacement = .trailing
        makingRows = [heads.row(at: 2), heads.row(at: 3)]

        // Left: the map.
        let mapTitle = NSTextField(labelWithString: "Structure")
        mapTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        map.orientation = .vertical
        map.alignment = .leading
        map.spacing = 2
        addNext.bezelStyle = .rounded
        addNext.target = self
        addNext.action = #selector(addNextTapped)
        removeMemberButton.bezelStyle = .rounded
        removeMemberButton.image = symbol("trash", "Remove", size: 11)
        removeMemberButton.imagePosition = .imageLeading
        removeMemberButton.target = self
        removeMemberButton.action = #selector(removeMemberTapped)
        removeMemberButton.isHidden = true
        // Each column is a title, its words, then its controls, on one line across both.
        let top = NSStackView(views: [mapTitle, leftHelp])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 10
        let left = NSView(), right = NSView(), divider = NSBox()
        divider.boxType = .separator
        for v in [top, heads, map, addNext, removeMemberButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; left.addSubview(v) }

        // Right: the selected row.
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
        about.placeholderString = "What This Holds"
        about.delegate = self
        about.usesSingleLineMode = false
        about.cell?.wraps = true
        about.cell?.isScrollable = false
        let grid = NSGridView(views: [[caption("Custom Name")], [customName], [caption("Description")], [about]])
        grid.rowSpacing = 6
        grid.column(at: 0).width = 250
        grid.row(at: 2).topPadding = 10
        customHead = grid.row(at: 0)
        customRow = grid.row(at: 1)
        aboutHead = grid.row(at: 2)
        aboutRow = grid.row(at: 3)
        for v in [namesTitle, column, grid] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; detail.addSubview(v) }
        removal.orientation = .vertical
        removal.alignment = .leading
        removal.spacing = 16
        let topRight = NSStackView(views: [levelTitle, rightHelp])
        topRight.orientation = .vertical
        topRight.alignment = .leading
        topRight.spacing = 10
        for v in [topRight, detail, removal] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; right.addSubview(v) }

        let v = NSView()
        for part in [left, divider, right] as [NSView] { part.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(part) }
        // One line under both sets of words, below whichever is taller, that the controls on each side hang from.
        let line = NSLayoutGuide()
        v.addLayoutGuide(line)
        let hugs = [top, topRight].map { line.topAnchor.constraint(equalTo: $0.bottomAnchor) }
        hugs.forEach { $0.priority = .defaultLow }
        NSLayoutConstraint.activate(hugs)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsPanel.minimumWidth),
            v.heightAnchor.constraint(equalToConstant: 620),
            left.topAnchor.constraint(equalTo: v.topAnchor, constant: 22),
            left.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -22),
            left.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 36),
            left.widthAnchor.constraint(equalToConstant: 440),
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
            collectionPopup.widthAnchor.constraint(equalToConstant: 220),
            stackPopup.widthAnchor.constraint(equalToConstant: 220),
            newName.widthAnchor.constraint(equalToConstant: 220),
            line.topAnchor.constraint(greaterThanOrEqualTo: top.bottomAnchor),
            line.topAnchor.constraint(greaterThanOrEqualTo: topRight.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0),
            line.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            heads.topAnchor.constraint(equalTo: line.topAnchor, constant: 22),
            heads.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            map.topAnchor.constraint(equalTo: heads.bottomAnchor, constant: 22),
            map.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            // Under the last group on the map, at its right.
            addNext.topAnchor.constraint(equalTo: map.bottomAnchor, constant: 12),
            addNext.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),
            removeMemberButton.topAnchor.constraint(equalTo: addNext.topAnchor),
            removeMemberButton.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 10),

            topRight.topAnchor.constraint(equalTo: right.topAnchor),
            topRight.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            topRight.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor),
            detail.topAnchor.constraint(equalTo: line.topAnchor, constant: 22),
            detail.leadingAnchor.constraint(equalTo: right.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: right.trailingAnchor),
            detail.bottomAnchor.constraint(equalTo: right.bottomAnchor),
            removal.topAnchor.constraint(equalTo: line.topAnchor, constant: 22),
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
            // Beside the column: the name typed by hand, and the description.
            grid.topAnchor.constraint(equalTo: namesTitle.topAnchor),
            grid.leadingAnchor.constraint(equalTo: column.trailingAnchor, constant: 24),
            about.heightAnchor.constraint(equalToConstant: 64),
        ])
        view = v
        load()
        show()
    }

    /// For a trial run: "<project name>" shows that project's stack, "<project name>/<group name>" presses the bin on one of its
    /// groups, and "collection:<name>" shows that collection, and "new" opens the box for a new collection's name.
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !rehearsed, let ask = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_SCHEMA"] else { return }
        rehearsed = true
        if ask == "new" { making = .collection; show(); return }
        if ask.hasPrefix("group:"), let row = SchemaTrial.rows(of: root).first(where: { $0.node.name == ask.dropFirst("group:".count) }) { selected = row.node.id; show(); return }
        if ask.hasPrefix("collection:") {
            let want = ask.dropFirst("collection:".count).split(separator: "/", maxSplits: 1).map(String.init)
            if let found = all.first(where: { $0.name == want[0] }) {
                collectionID = found.id; stack = nil; load(); selected = collectionID; show()
                if want.count > 1, want[1] == "remove" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.removeCollection() } }
            }
            return
        }
        let parts = ask.split(separator: "/", maxSplits: 1).map(String.init)
        guard let project = lib.orderedProjects.first(where: { $0.name == parts[0] }) else { return }
        collectionID = SchemaTrial.collection(of: project.id).id
        stack = project.id
        load()
        selected = root.id
        if parts.count > 1, parts[1] == "remove" { show(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.removeMember(project.id) }; return }
        if parts.count > 1, let row = SchemaTrial.rows(of: root).first(where: { $0.node.name == parts[1] }) { remove(row.node, level: row.level) } else { show() }
    }
    private var rehearsed = false

    override func refresh() {
        guard isViewLoaded else { return }
        load()
        show()
    }

    /// Reads what is showing from where it is kept.
    private func load() {
        all = SchemaTrial.collections
        if !all.contains(where: { $0.id == collectionID }) { collectionID = (all.first ?? SchemaTrial.SchemaFile.fresh.collections[0]).id; stack = nil }
        // A project that has gone, or has moved to another collection, takes its stack off the panel.
        if let id = stack, !members.contains(where: { $0.id == id }) { stack = nil }
        root = stack.map { SchemaTrial.schema(for: $0) } ?? collection.stack
    }

    private var current: (node: SchemaNode, level: Int)? { SchemaTrial.rows(of: root).first { $0.node.id == selected } }

    private var target: Target? {
        if selected == collectionID { return .collection }
        if selected == SchemaPanel.tierRow { return collection.folderName == nil ? nil : .tier }
        guard let (node, level) = current else { return nil }
        if level == 1, let project = stack { return .member(project) }
        return .node(node, level)
    }

    // MARK: What a group holds

    /// The projects a group on this stack stands in: the one whose stack it is, or every member that follows the default.
    private var holders: [UUID] { stack.map { [$0] } ?? members.map { $0.id }.filter { !SchemaTrial.hasOwn($0) } }

    private func palettes(_ role: SchemaRole, in project: UUID) -> [UUID] {
        lib.palettes(in: project).filter { $0.isTypography == (role == .typography) }.map { $0.id }
    }
    private func tags(in project: UUID) -> [String] { lib.allTags.filter { lib.project(ofTag: $0) == project } }

    /// How many things one of the app's own groups holds, across `holders`. Information holds the Overview page, which is the project's own, and counts as nothing to lose.
    private func count(_ node: SchemaNode, level: Int) -> Int {
        guard level == 2, let role = SchemaTrial.role(of: node) else { return 0 }
        switch role {
        case .information: return 0
        case .palettes, .typography: return holders.reduce(0) { $0 + palettes(role, in: $1).count }
        case .tags: return holders.reduce(0) { $0 + tags(in: $1).count }
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
        if target == nil { selected = collectionID }
        if let going = removing, !SchemaTrial.rows(of: root).contains(where: { $0.node.id == going }) { removing = nil }
        let here = collection, inside = members

        // The head.
        collectionPopup.removeAllItems()
        for c in all {
            collectionPopup.addItem(withTitle: c.name.isEmpty ? "Unnamed" : c.name)
            collectionPopup.lastItem?.representedObject = c.id
        }
        collectionPopup.menu?.addItem(.separator())
        collectionPopup.addItem(withTitle: "New Collection\u{2026}")
        collectionPopup.lastItem?.tag = -1
        if let at = collectionPopup.itemArray.firstIndex(where: { $0.representedObject as? UUID == collectionID }) { collectionPopup.selectItem(at: at) }
        stackPopup.removeAllItems()
        stackPopup.addItem(withTitle: "Default")
        stackPopup.menu?.addItem(.separator())
        for p in inside {
            stackPopup.addItem(withTitle: p.name)
            stackPopup.lastItem?.representedObject = p.id
            stackPopup.lastItem?.image = symbol(SchemaTrial.hasOwn(p.id) ? "square.stack.3d.up.fill" : "square.stack.3d.up", "", size: 11)
        }
        if !inside.isEmpty { stackPopup.menu?.addItem(.separator()) }
        stackPopup.addItem(withTitle: "New \(member)\u{2026}")
        stackPopup.lastItem?.tag = -1
        if let id = stack, let at = stackPopup.itemArray.firstIndex(where: { $0.representedObject as? UUID == id }) { stackPopup.selectItem(at: at) } else { stackPopup.selectItem(at: 0) }
        let own = stack.map { SchemaTrial.hasOwn($0) } ?? false
        resetButton.isHidden = !own
        let following = inside.filter { !SchemaTrial.hasOwn($0.id) }.count
        let heading = here.name.isEmpty ? "this collection" : here.name
        let others = all.filter { $0.id != here.id }.map { $0.name }
        var words = "You are in the \(heading) collection"
        if let project = stack.flatMap({ lib.project($0) }) {
            words += ", on \(project.name)'s own stack. " + (own ? "It has a stack of its own, and follows nothing: what is built below is its alone. Use Default puts it back with the others."
                                                               : "It follows Default. Change anything below and it takes a stack of its own, leaving the others as they are.")
        } else {
            words += ". Below is its Default stack: the structure every member of \(heading) follows unless it has a stack of its own. \(following) of \(inside.count) follow it."
        }
        words += "\n\nEach collection has a tree of its own, so one can be laid out for client work and another, such as In House, for your own. "
        words += others.isEmpty ? "To make another, choose New Collection under Collection." : "You also have \(others.joined(separator: ", ")). Choose one under Collection, or New Collection to make another."
        words += " To shape one member differently from the rest, choose it under Stack."
        leftHelp.stringValue = words
        makingRows.forEach { $0.isHidden = making == .nothing }
        newName.placeholderString = making == .collection ? "Name The New Collection" : "Name The New Member"

        // The map: the collection, what groups its members if anything does, then the stack.
        map.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func add(_ row: SchemaRowView, _ id: UUID) {
            row.onSelect = { [weak self] in self?.removing = nil; self?.selected = id; self?.view.window?.makeFirstResponder(nil); self?.show() }
            map.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: map.widthAnchor).isActive = true
        }
        var does: [(symbol: String, tip: String, run: () -> Void)] = []
        if here.folderName == nil {
            does.append(("arrow.turn.down.right", "Add A Level Beneath, To Group The Members", { [weak self] in self?.addTier() }))
        }
        if here.id != all.first?.id {
            does.append(("trash", inside.isEmpty ? "Remove This Collection" : "Remove This Collection And Everything In It", { [weak self] in self?.removeCollection() }))
        }
        add(SchemaRowView(here.name, level: 0, tip: SchemaTrial.title(forLevel: 0), selected: selected == collectionID,
                          holds: inside.isEmpty ? nil : "\(inside.count) \(inside.count == 1 ? member : SchemaTrial.plural(member))", strong: true, does: does), collectionID)
        if let tier = here.folderName {
            add(SchemaRowView(tier, level: 1, tip: SchemaTrial.title(forLevel: 1), selected: selected == SchemaPanel.tierRow,
                              holds: here.folders.isEmpty ? nil : "\(here.folders.count) Made",
                              does: [("trash", "Remove This Level: The Members Sit Straight Under \(here.name) Again", { [weak self] in self?.removeTier() })]), SchemaPanel.tierRow)
        }
        let projectName = stack.flatMap { lib.project($0)?.name }
        var rowsOf: [UUID: SchemaRowView] = [:]
        var parentOf: [UUID: UUID] = [:]
        for (node, _) in SchemaTrial.rows(of: root) { for child in node.children { parentOf[child.id] = node.id } }
        for (node, level) in SchemaTrial.rows(of: root) {
            let n = count(node, level: level)
            var does: [(symbol: String, tip: String, run: () -> Void)] = [("arrow.turn.down.right", "Add A Group Inside This One", { [weak self] in self?.add(child: true, at: node.id) })]
            if level > 1 {
                does.append(("plus", "Add The Next Group At This Level", { [weak self] in self?.add(child: false, at: node.id) }))
                does.append(("trash", "Remove This Group And Everything Inside It", { [weak self] in self?.remove(node, level: level) }))
            } else if let project = stack {
                // The member itself, with everything it holds: asked for with a slide, never a click.
                does.append(("trash", "Remove This \(member) And Everything In It", { [weak self] in self?.removeMember(project) }))
            }
            let row = SchemaRowView(level == 1 ? projectName ?? node.name : node.name, level: level + offset, tip: SchemaTrial.title(forLevel: level + offset),
                                    selected: node.id == selected, holds: n > 0 ? "\(n) \(noun(SchemaTrial.role(of: node), n))" : nil, strong: level == 1, does: does)
            if level > 1 { row.onMove = { [weak self] at in self?.move(node.id, to: at) } }
            rowsOf[node.id] = row
            add(row, node.id)
        }
        // Groups are dragged among the rows that share their parent.
        for (node, _) in SchemaTrial.rows(of: root) {
            let rows = node.children.compactMap { rowsOf[$0.id] }
            rows.forEach { $0.siblings = rows }
        }

        if let project = stack, let name = lib.project(project)?.name {
            removeMemberButton.isHidden = false
            removeMemberButton.title = "Remove \(name)\u{2026}"
            removeMemberButton.toolTip = "Remove This \(member) And Everything In It, After A Slide To Confirm"
        } else {
            removeMemberButton.isHidden = true
        }
        guard let what = target else { return }
        // The button under the map adds to the stack; it has nothing to add for the collection or its grouping level.
        if case .node(_, let level) = what {
            addNext.isHidden = false
            addNext.title = level == 1 ? "Add \(SchemaTrial.title(forLevel: 2 + offset))" : "Add Next Level \(level + offset) Group"
        } else if case .member = what {
            addNext.isHidden = false
            addNext.title = "Add \(SchemaTrial.title(forLevel: 2 + offset))"
        } else {
            addNext.isHidden = true
        }

        // The right pane: what to do with a group's contents, or the row's own details.
        if case .node(let node, let level) = what, removing == node.id {
            levelTitle.stringValue = SchemaTrial.title(forLevel: level + offset)
            rightHelp.stringValue = "You are removing a group from \(heading) that holds things. Say what becomes of them first."
            removal.isHidden = false
            detail.isHidden = true
            showRemoval(node, level: level)
            return
        }
        removal.isHidden = true
        detail.isHidden = false

        // What the row is called now, the names on offer for it, what is said about it, and a word of help.
        var name = "", offered: [String] = [], said: String? = nil, help = "", fixed = false
        let memberWord = member.lowercased(), members = SchemaTrial.plural(member).lowercased()
        switch what {
        case .collection:
            levelTitle.stringValue = SchemaTrial.title(forLevel: 0)
            name = here.name; offered = SchemaTrial.collectionNames; said = here.about
            help = "You are editing the \(heading) collection itself: its name, which heads it in the sidebar, and a line on what it is for. "
                + (here.folderName == nil ? "Its \(members) sit straight under the heading. The arrow on its row adds a level between, to group them."
                                          : "Its \(members) are grouped under a level between, named on the next row.")
        case .tier:
            levelTitle.stringValue = SchemaTrial.title(forLevel: 1)
            name = here.folderName ?? ""; offered = SchemaTrial.folderNames
            help = "You are editing the level that groups the \(members) of \(heading). Name what one of them is. Each one is made in the sidebar, with the plus beside \(heading), and the \(members) are made inside it with the plus on its own row."
        case .member(let project):
            levelTitle.stringValue = SchemaTrial.title(forLevel: 1 + offset)
            name = lib.project(project)?.name ?? ""; fixed = true; said = root.about
            help = "You are editing \(name), one \(memberWord) in \(heading). Type over its name and press Return to rename it. The groups below are its own, and the sidebar shows them under it. Remove, under the map, takes it and all it holds away for good."
        case .node(let node, let level):
            levelTitle.stringValue = SchemaTrial.title(forLevel: level + offset)
            name = node.name; offered = SchemaTrial.names(forLevel: level); said = node.about
            help = level == 1 ? "You are editing what a \(memberWord) of \(heading) is called. Every \(memberWord) is a project of the app's, with files of its own; the sidebar makes one with the plus."
                : level == 2 ? "You are editing a group inside each \(memberWord) of \(heading): the sidebar shows it under every one. Information, Palettes, Typography and Tags hold what they always have, whatever they are called. Any other group is a label for now, holding nothing."
                : "You are editing a group \(level - 1) levels inside each \(memberWord) of \(heading). Groups this deep are labels for now: they show in the sidebar and hold nothing yet."
        }
        // A name of the user's own shows the box to type it in; a name from the list hides it. A member's name is always typed.
        let custom = fixed || renaming || !offered.contains(name)
        names.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func offer(_ row: SchemaNameRow, _ choose: @escaping () -> Void) {
            row.onChoose = choose
            names.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: names.widthAnchor).isActive = true
        }
        if fixed {
            offer(SchemaNameRow(name, chosen: true)) { [weak self] in if let self = self { self.view.window?.makeFirstResponder(self.customName) } }
        } else {
            offer(SchemaNameRow("Custom Name\u{2026}", chosen: custom, quiet: true)) { [weak self] in self?.choose(name: nil) }
            for one in offered { offer(SchemaNameRow(one, chosen: !custom && one == name)) { [weak self] in self?.choose(name: one) } }
        }
        // A different list starts its column at the top.
        if offered != shownList {
            shownList = offered
            namesScroll.contentView.scroll(to: .zero)
            namesScroll.reflectScrolledClipView(namesScroll.contentView)
        }
        customRow.isHidden = !custom
        customHead.isHidden = !custom
        aboutHead.topPadding = custom ? 10 : 0   // with nothing above it, Description sits level with Name
        (customHead.cell(at: 0).contentView as? NSTextField)?.stringValue = fixed ? "Name" : "Custom Name"
        aboutRow.isHidden = said == nil
        aboutHead.isHidden = said == nil
        if customName.currentEditor() == nil { customName.stringValue = custom ? name : "" }
        if about.currentEditor() == nil { about.stringValue = said ?? "" }
        rightHelp.stringValue = help
        if focusName, custom {
            view.window?.makeFirstResponder(customName)
            if renaming { customName.currentEditor()?.selectAll(nil) }
        }
        renaming = false
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
            removal.addArrangedSubview(words("These are spread over the \(holders.count) that follow Default. On Default the group can be renamed, and they stay where they are. To delete them, choose each member under Stack and remove the group there."))
            removal.addArrangedSubview(push("Keep The \(noun(role, n)) And Rename The Group", #selector(keepAndRename)))
        }
        removal.addArrangedSubview(push("Cancel", #selector(cancelRemoval)))
    }

    // MARK: Changing the stack

    /// Keeps the stack that is showing. A project that was following the default gets a stack of its own the first time anything on it is changed.
    private func keep() {
        if let id = stack { SchemaTrial.setSchema(root, for: id) } else { let tree = root; SchemaTrial.changeCollection(collectionID) { $0.stack = tree } }
        all = SchemaTrial.collections
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

    @objc private func removeMemberTapped() { if let project = stack { removeMember(project) } }

    /// The member and all it holds, gone for good once the slide completes.
    private func removeMember(_ project: UUID) {
        library.dump(project: project, over: view.window) { [weak self] in
            guard let self = self else { return }
            self.removing = nil
            self.stack = nil
            self.load()
            self.selected = self.collectionID
            self.show()
        }
    }

    /// A group dragged to another place among its siblings.
    private func move(_ id: UUID, to index: Int) {
        removing = nil
        root = SchemaTrial.moving(id, to: index, in: root)
        selected = id
        keep()
        view.window?.makeFirstResponder(nil)
        show()
    }

    /// The bin on a group: gone at once when it holds nothing; asked about when it holds something.
    private func remove(_ node: SchemaNode, level: Int) {
        let n = count(node, level: level)
        guard n == 0 else {
            selected = node.id
            show()
            askAboutContents(of: node, level: level, holding: n)
            return
        }
        root = SchemaTrial.removing(node.id, from: root)
        keep()
        show()
    }

    /// A group that holds things cannot simply go. The panel says so, offers to keep them under another
    /// name, and only a slide deletes them with the group.
    private func askAboutContents(of node: SchemaNode, level: Int, holding n: Int) {
        let role = SchemaTrial.role(of: node), things = "\(n) \(noun(role, n))"
        let keep = SlideConfirm.Option(title: "Keep The \(noun(role, n)) And Rename The Group") { [weak self] in self?.keepAndRename() }
        guard let project = stack else {
            // On Default they are spread over every member that follows it; deleting is done member by member.
            let note = "Its \(things) are spread over the \(holders.count) that follow Default, and would be left with nowhere to show. On Default the group can be renamed and they stay where they are. To delete them, choose each member under Stack and remove the group there."
            SlideConfirm.ask(over: view.window, title: "\(node.name) Holds \(things)", note: note, options: [keep], commit: "Remove") { }
            return
        }
        let name = lib.project(project)?.name ?? ""
        var note = "A group that holds things cannot simply go: they would still be in \(name), with nowhere to show. Keep them and give the group another name, or delete the \(things) and remove the group. "
        note += role == .tags ? "A deleted tag comes off everything that carries it." : "A deleted palette leaves its colours in All Swatches, and the deletion is recorded as a step in History."
        if lib.project(project)?.isLocked == true { note += " \(name) is locked, so nothing in it can be deleted until it is unlocked in the sidebar." }
        SlideConfirm.ask(over: view.window, title: "\(node.name) Holds \(things)", note: note + " This cannot be undone.", options: [keep], commit: "Delete And Remove") { [weak self] in
            self?.deleteAndRemove()
        }
    }

    @objc private func cancelRemoval() { removing = nil; show() }

    /// Keeps what the group holds: the group stays, and its name is ready to be changed.
    @objc private func keepAndRename() {
        removing = nil
        guard let id = selected else { return }
        // It keeps its part, whatever it is called next; and its name until a new one is typed, so walking away changes nothing.
        root = SchemaTrial.changing(id, in: root) { $0.role = SchemaTrial.role(of: $0) }
        keep()
        renaming = true
        show(focusName: true)
    }
    /// Set by Keep And Rename: the name box opens with the present name selected, instead of the list's tick.
    private var renaming = false

    /// Deletes what the group holds in this project, then takes the group off its stack.
    @objc private func deleteAndRemove() {
        guard let project = stack, let (node, _) = current, let role = SchemaTrial.role(of: node) else { return }
        library.erase(role: role, of: project)
        removing = nil
        // Only if they have really gone: a locked project refuses the change.
        guard count(node, level: 2) == 0 else { show(); return }
        root = SchemaTrial.removing(node.id, from: root)
        keep()
        show()
    }

    /// Under the map: the next group at the selected one's level, or the first inside the member.
    @objc private func addNextTapped() {
        guard let (node, level) = current else { return }
        add(child: level == 1, at: node.id)
    }

    // MARK: Names

    /// Gives the selected row a name: the collection's, the grouping level's, the project's own, or a group's.
    private func setName(_ name: String, done: Bool) {
        guard let what = target else { return }
        switch what {
        case .collection: SchemaTrial.changeCollection(collectionID) { $0.name = name }; all = SchemaTrial.collections
        case .tier: SchemaTrial.changeCollection(collectionID) { $0.folderName = name }; all = SchemaTrial.collections
        case .member(let project):
            // The project's own name: kept when the typing is finished, not letter by letter, as it renames its files.
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard done, !typed.isEmpty, typed != lib.project(project)?.name else { return }
            library.apply("Rename Project") { _ = $0.renameProject(project, to: typed) }
        case .node(let node, _):
            // One of the app's own groups keeps its part under its new name.
            root = SchemaTrial.changing(node.id, in: root) { $0.role = SchemaTrial.role(of: $0); $0.name = name }
            keep()
        }
    }

    /// A name from the column, or nil for Custom, which empties the name ready to be typed.
    private func choose(name: String?) {
        guard let what = target else { return }
        if name == nil {
            // Already a name of the user's own: go to it, and keep it.
            let now: String, offered: [String]
            switch what {
            case .collection: now = collection.name; offered = SchemaTrial.collectionNames
            case .tier: now = collection.folderName ?? ""; offered = SchemaTrial.folderNames
            case .member: return
            case .node(let node, let level): now = node.name; offered = SchemaTrial.names(forLevel: level)
            }
            if !offered.contains(now) { view.window?.makeFirstResponder(customName); return }
        }
        view.window?.makeFirstResponder(nil)
        setName(name ?? "", done: true)
        show(focusName: name == nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === customName || field === about else { return }
        if field === customName {
            setName(field.stringValue, done: false)
        } else if let what = target {
            let text = field.stringValue
            switch what {
            case .collection: SchemaTrial.changeCollection(collectionID) { $0.about = text }; all = SchemaTrial.collections
            case .tier: break
            case .member: root.about = text; keep()
            case .node(let node, _): root = SchemaTrial.changing(node.id, in: root) { $0.about = text }; keep()
            }
        }
        show()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === customName else { return }
        setName(field.stringValue, done: true)
        load()
        show()
    }

    // MARK: Collections

    /// Groups the collection's members under a level of their own: a Client, holding its Contracts.
    private func addTier() {
        SchemaTrial.changeCollection(collectionID) { $0.folderName = SchemaTrial.folderNames[0] }
        all = SchemaTrial.collections
        selected = SchemaPanel.tierRow
        show()
    }

    /// Takes the grouping level away. The folders made in it are let go; the members stay in the collection.
    private func removeTier() {
        SchemaTrial.changeCollection(collectionID) { $0.folderName = nil; $0.folders = [] }
        all = SchemaTrial.collections
        selected = collectionID
        show()
    }

    /// Takes a collection away. Its members are not touched: with no collection of their own they are in the first one again.
    private func removeCollection() {
        guard collectionID != all.first?.id else { return }
        library.dump(collection: collectionID, over: view.window) { [weak self] in
            guard let self = self else { return }
            self.collectionID = SchemaTrial.firstCollection
            self.stack = nil
            self.load()
            self.selected = self.collectionID
            self.show()
        }
    }

    @objc private func collectionChosen() {
        removing = nil
        view.window?.makeFirstResponder(nil)
        if collectionPopup.selectedItem?.tag == -1 {
            making = .collection
            show()
            view.window?.makeFirstResponder(newName)
            return
        }
        making = .nothing
        collectionID = collectionPopup.selectedItem?.representedObject as? UUID ?? (all.first ?? SchemaTrial.SchemaFile.fresh.collections[0]).id
        stack = nil
        load()
        selected = collectionID
        show()
    }

    // MARK: Stacks

    @objc private func stackChosen() {
        removing = nil
        view.window?.makeFirstResponder(nil)
        if stackPopup.selectedItem?.tag == -1 {
            making = .member
            show()
            view.window?.makeFirstResponder(newName)
            return
        }
        making = .nothing
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
        making = .nothing
        newName.stringValue = ""
        show()
    }

    /// Makes what the name box is for: a collection, starting with the stack of the one showing; or a
    /// member of this collection, a real project, with a stack of its own to shape.
    @objc private func createTapped() {
        let name = newName.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard making != .nothing, ProjectField.problem(name: name, values: [:]) == nil else { NSSound.beep(); return }
        if making == .collection {
            let made = SchemaCollection(name: name, stack: collection.stack)
            SchemaTrial.collections = all + [made]
            collectionID = made.id
            stack = nil
            load()
            selected = collectionID
        } else {
            var made: UUID?
            library.apply("New Project") { lib in
                let id = lib.createProject(named: name)
                let organisation = ProjectField.tidy(Prefs.organisation)
                if !organisation.isEmpty { lib.setProjectDetails(id, organisation) }
                made = id
            }
            guard let id = made, lib.project(id) != nil else { NSSound.beep(); return }
            SchemaTrial.place(id, in: collectionID, folder: nil)
            stack = id
            load()
            selected = root.id
        }
        making = .nothing
        newName.stringValue = ""
        show()
    }
}
