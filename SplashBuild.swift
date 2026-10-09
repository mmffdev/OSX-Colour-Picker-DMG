import Foundation

// ---------- What the splash's answers build ----------
//
// The answers to the splash's questions, and the catalogue structure they make. Who the work is for
// gives the collections: every type picked (Clients, Brands, a word of your own) is a collection with
// the names given as its first level, and Our Own Work a collection with no such level. Each one
// named has its own categories of work (Products, Projects) as a level, each category its first member, named,
// and each member its streams (Web, Print); the Master Template
// holds the groups chosen, in their order. Every later question is asked once for each answer to the
// one before, so a second client or a second category only adds a block to the page. Pure, so the
// self-test can build every combination of answers and check the tree it gives.

final class SplashDraft: Codable {
    init() {}
    // Pending text belongs to its field; committed answers and their stable IDs survive a relaunch.
    private enum CodingKeys: String, CodingKey {
        case catalogueName, parties, categoriesOf, streamsOf, oneKindOf, groupsOf, groupsEverywhere
        case members, collectionNames, groupNames, types
    }
    static let ownWork = "Our own work"
    static let whoOptions = ["Clients", "Customers", "Contracts", "Brands"]
    static let streamOptions = ["Web", "Print", "Design", "Video", "Packaging"]
    static let categoryOptions = ["Products", "Projects", "Ranges", "Jobs", "Campaigns"]
    /// The groups inside each member, to start: the four the app fills itself.
    static let groupStart = SchemaRole.allCases.map { $0.title }
    /// The groups offered: the four, then the schema page's own types, so the splash and the Schema page never disagree.
    static let groupOptions = groupStart + SchemaTrial.nestedNames.filter { !groupStart.contains($0) }

    /// One of the first level: a client, a brand, named; or the user's own work, which has no name.
    struct Party: Equatable, Codable {
        var id = UUID()
        var type: String
        var name: String
        var isOwnWork: Bool { type == SplashDraft.ownWork }
        /// How the party is called on a block's caption.
        var title: String { isOwnWork ? SplashDraft.ownWork : name }
    }
    /// A word being typed, shown on the tree before it is taken: for a type's next name, a party's category, a category's stream or member, a leaf's group.
    enum Pending: Equatable { case party(String), category(UUID), stream(UUID, String), member(UUID, String), group(String) }

    /// The catalogue's name as typed on the first section; nil keeps the name it has. Set renames it, nothing before.
    var catalogueName: String?
    /// Who the work is for, in order: each a collection's type and a first-level name.
    var parties: [Party] = []
    /// Each party's categories of work, plural, in order; a level under the party as soon as any is chosen.
    var categoriesOf: [UUID: [String]] = [:]
    /// Each category's streams, by party and category, in order; a level inside its member unless `oneKind` sets them aside.
    var streamsOf: [String: [String]] = [:]
    /// The categories that are one kind of work, by party and category: their streams are kept but make no level, so unticking
    /// brings them back. Each category answers for itself (Rick, 2026-10-09): a Campaign may be one kind while Projects has streams.
    var oneKindOf: Set<String> = []
    /// One kind of work for every category at once: what the old single switch did, kept for the self-test and the tree.
    var oneKind: Bool {
        get { !chains.isEmpty && chains.allSatisfy { oneKindOf.contains(Self.key($0.party.id, $0.category)) } }
        set { oneKindOf = newValue ? Set(chains.map { Self.key($0.party.id, $0.category) }) : [] }
    }
    func isOneKind(_ party: UUID, _ category: String) -> Bool { oneKindOf.contains(Self.key(party, category)) }
    func setOneKind(_ on: Bool, _ party: UUID, _ category: String) { if on { oneKindOf.insert(Self.key(party, category)) } else { oneKindOf.remove(Self.key(party, category)) } }
    /// The groups inside each member, by stream (or directly inside a member without streams), in order.
    /// A leaf not yet answered has the four the app fills itself. The model is progressive: every layer the user adds is one more
    /// parent the layer below is asked for, and each may differ (Rick, 2026-10-09).
    var groupsOf: [String: [String]] = [:]
    /// The groups of every leaf at once: what the old single list did, kept for the self-test and the tree's start.
    var groups: [String] {
        get { leaves.first.map { groups(of: $0.key) } ?? groupsEverywhere }
        set { groupsOf = [:]; groupsEverywhere = newValue }
    }
    /// What a leaf not yet answered starts with.
    private var groupsEverywhere: [String] = groupStart
    func groups(of leaf: String) -> [String] { groupsOf[leaf] ?? groupsEverywhere }
    /// Each category's first member, by party and category.
    var members: [String: String] = [:]
    /// The collections' names, where the tree renamed one, by type.
    var collectionNames: [String: String] = [:]
    /// The groups' names, where the tree renamed one, by type.
    var groupNames: [String: String] = [:]
    var pending: (level: Pending, text: String)?

    static func key(_ party: UUID, _ category: String) -> String { party.uuidString + "/" + category }
    /// The key of a leaf: the category's, with the stream after it when there is one.
    static func leafKey(_ party: UUID, _ category: String, _ stream: String?) -> String { key(party, category) + (stream.map { "/" + $0 } ?? "") }

    /// One place for groups inside a member: its stream, or the member itself without streams.
    struct Leaf: Equatable {
        let party: Party, category: String, stream: String?
        var key: String { SplashDraft.leafKey(party.id, category, stream) }
        /// How the leaf is called on a block's caption: "Acme · Projects · Web".
        var title: String { ([party.title, category] + (stream.map { [$0] } ?? [])).joined(separator: " \u{00B7} ") }
    }
    /// Identify the actual project or product while choosing its assets.
    func assetHeading(for leaf: Leaf) -> String {
        let word = Self.memberWord(leaf.category)
        let name = member(of: leaf.party.id, leaf.category) ?? "(Not Named Yet)"
        return (["\(word) \(name)"] + (leaf.stream.map { ["Stream \($0)"] } ?? []) + ["Assets"]).joined(separator: " > ")
    }
    /// Every leaf, in order: the blocks the last question is asked in, one per stream, or one per category with no stream level.
    var leaves: [Leaf] {
        chains.flatMap { c -> [Leaf] in
            let active = activeStreams(of: c.party.id, c.category)
            return active.isEmpty ? [Leaf(party: c.party, category: c.category, stream: nil)] : active.map { Leaf(party: c.party, category: c.category, stream: $0) }
        }
    }
    var everyLeafGrouped: Bool { !leaves.isEmpty && leaves.allSatisfy { !groups(of: $0.key).isEmpty } }

    /// The collections, in the order their types were picked; a type stays while it waits for its first name.
    var types: [String] = []
    func parties(of type: String) -> [Party] { parties.filter { $0.type == type } }
    func names(of type: String) -> [String] { parties(of: type).filter { !$0.isOwnWork }.map { $0.name } }
    func categories(of party: UUID) -> [String] { categoriesOf[party] ?? [] }
    func streams(of party: UUID, _ category: String) -> [String] { streamsOf[Self.key(party, category)] ?? [] }
    func activeStreams(of party: UUID, _ category: String) -> [String] { isOneKind(party, category) ? [] : streams(of: party, category) }
    func member(of party: UUID, _ category: String) -> String? { members[Self.key(party, category)].flatMap { $0.isEmpty ? nil : $0 } }
    /// Every party and category, in order: the blocks a later question is asked in.
    var chains: [(party: Party, category: String)] { parties.flatMap { p in categories(of: p.id).map { (p, $0) } } }
    var everyoneCategorised: Bool { !parties.isEmpty && parties.allSatisfy { !categories(of: $0.id).isEmpty } }
    var anyoneNamed: Bool { chains.contains { member(of: $0.party.id, $0.category) != nil } }
    var anyStreams: Bool { chains.contains { !activeStreams(of: $0.party.id, $0.category).isEmpty } }
    /// Every category has said: streams of its own, or one kind of work.
    var streamsAnswered: Bool { !chains.isEmpty && chains.allSatisfy { isOneKind($0.party.id, $0.category) || !streams(of: $0.party.id, $0.category).isEmpty } }
    /// "Client" from "Clients", "Product" from "Products": the singular a level or a member is called by.
    static func singular(_ word: String) -> String {
        let w = word.trimmingCharacters(in: .whitespaces)
        if w.lowercased().hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.lowercased().hasSuffix("ses") || w.lowercased().hasSuffix("xes") { return String(w.dropLast(2)) }
        if w.lowercased().hasSuffix("s"), w.count > 2 { return String(w.dropLast()) }
        return w
    }
    /// The word for one of a category's members: "Product" from "Products".
    static func memberWord(_ category: String) -> String { singular(category) }
    /// The word for a member of a type's collection: of its first category, or "Project" before any is chosen.
    func memberWord(for type: String) -> String { Self.memberWord(parties(of: type).flatMap { categories(of: $0.id) }.first ?? "Projects") }
    /// The collection for a type: its name on the tree, the type itself, or "My Products" for the user's own.
    func collectionTitle(_ type: String) -> String { collectionNames[type] ?? (type == Self.ownWork ? "My " + SchemaTrial.plural(memberWord(for: type)) : type) }
    /// The levels above a member: the party and category. Streams belong in the member stack.
    func levelNames(for type: String) -> [String] {
        let mine = parties(of: type)
        let categorised = mine.contains { !categories(of: $0.id).isEmpty }
        return (type == Self.ownWork ? [] : [Self.singular(type)]) + (categorised ? ["Category"] : [])
    }
    /// The app's own group of that type, if it is one; a custom group has none and is a folder of files under its name.
    static func role(of group: String) -> SchemaRole? { SchemaRole.allCases.first { $0.title == group } }
    /// A member's tree from a list of groups, each typed and under its name on the tree.
    func stack(named name: String, groups list: [String]) -> SchemaNode {
        SchemaNode(name: name, children: list.map { SchemaNode(name: groupNames[$0] ?? $0, role: Self.role(of: $0), kind: $0) })
    }
    /// Streams belong inside the member, with each stream's own groups.
    func memberStack(_ party: Party, _ category: String) -> SchemaNode {
        let active = activeStreams(of: party.id, category)
        let name = Self.memberWord(category)
        if active.isEmpty { return stack(named: name, groups: groups(of: Self.leafKey(party.id, category, nil))) }
        return SchemaNode(name: name, children: active.map { stream in
            stack(named: stream, groups: groups(of: Self.leafKey(party.id, category, stream)))
        })
    }
    func template(for type: String) -> SchemaNode {
        guard let first = chains.first(where: { $0.party.type == type }) else {
            return stack(named: memberWord(for: type), groups: groups)
        }
        return memberStack(first.party, first.category)
    }

    /// Builds the structure into a schema and a library: a collection for every type, a folder for every one named in it, that
    /// one's categories inside it, and each category's first member containing its streams and groups.
    /// Returns the collections' ids and the members' ids.
    @discardableResult
    func build(into schema: inout SchemaTrial.SchemaFile, library lib: inout Library, at date: Date = Date()) -> (collections: [UUID], members: [UUID]) {
        var made: [UUID] = [], ids: [UUID] = []
        for type in types {
            let template = self.template(for: type)
            var collection = SchemaCollection(name: collectionTitle(type), stack: template)
            let levels = levelNames(for: type)
            collection.folderName = levels.first
            collection.levelNames = levels.count > 1 ? levels : nil
            var folders: [SchemaFolder] = []
            var places: [(name: String, folder: UUID?, stack: SchemaNode)] = []
            for p in parties(of: type) {
                var top: UUID?
                if !p.isOwnWork { let f = SchemaFolder(name: p.name); folders.append(f); top = f.id }
                for category in categories(of: p.id) {
                    let cf = SchemaFolder(name: category, parent: top)
                    folders.append(cf)
                    if let name = member(of: p.id, category) {
                        places.append((name, cf.id, memberStack(p, category)))
                    }
                }
            }
            collection.folders = folders
            schema.collections.append(collection)
            ids.append(collection.id)
            for place in places {
                let id = lib.createProject(named: place.name, at: date)
                schema.places[id.uuidString] = SchemaPlace(collection: collection.id, folder: place.folder)
                // Preserve each category's streams and each stream's group choices independently.
                schema.stacks = schema.stacks ?? [:]
                schema.stacks?[id.uuidString] = place.stack
                made.append(id)
            }
        }
        return (ids, made)
    }
}
