import Foundation

// ---------- What the splash's answers build ----------
//
// The answers to the splash's questions, and the catalogue structure they make. Who the work is for
// gives the collections: every type picked (Clients, Brands, a word of your own) is a collection with
// the names given as its first level, and Our Own Work a collection with no such level. Each one
// named has its own categories of work (Products, Projects) as a level, each category its own
// streams (Web, Print) as a level, and each category its first member, named; the Master Template
// holds the groups chosen, in their order. Every later question is asked once for each answer to the
// one before, so a second client or a second category only adds a block to the page. Pure, so the
// self-test can build every combination of answers and check the tree it gives.

final class SplashDraft {
    static let ownWork = "Our own work"
    static let whoOptions = ["Clients", "Customers", "Contracts", "Brands"]
    static let streamOptions = ["Web", "Print", "Design", "Video", "Packaging"]
    static let categoryOptions = ["Products", "Projects", "Ranges", "Jobs", "Campaigns"]
    /// The groups inside each member, to start: the four the app fills itself.
    static let groupStart = SchemaRole.allCases.map { $0.title }
    /// The groups offered: the four, then the schema page's own types, so the splash and the Schema page never disagree.
    static let groupOptions = groupStart + SchemaTrial.nestedNames.filter { !groupStart.contains($0) }

    /// One of the first level: a client, a brand, named; or the user's own work, which has no name.
    struct Party: Equatable {
        var id = UUID()
        var type: String
        var name: String
        var isOwnWork: Bool { type == SplashDraft.ownWork }
        /// How the party is called on a block's caption.
        var title: String { isOwnWork ? SplashDraft.ownWork : name }
    }
    /// A word being typed, shown on the tree before it is taken: for a type's next name, a party's category, a category's stream or member, a group.
    enum Pending: Equatable { case party(String), category(UUID), stream(UUID, String), member(UUID, String), group }

    /// The catalogue's name as typed on the first section; nil keeps the name it has. Set renames it, nothing before.
    var catalogueName: String?
    /// Who the work is for, in order: each a collection's type and a first-level name.
    var parties: [Party] = []
    /// Each party's categories of work, plural, in order; a level under the party as soon as any is chosen.
    var categoriesOf: [UUID: [String]] = [:]
    /// Each category's streams, by party and category, in order; a level under the category unless `oneKind` sets them aside.
    var streamsOf: [String: [String]] = [:]
    /// One kind of work: the streams are kept but make no level, so unticking brings them back.
    var oneKind = false
    /// The groups inside each member, by type, in the Master Template's order.
    var groups: [String] = groupStart
    /// Each category's first member, by party and category.
    var members: [String: String] = [:]
    /// The collections' names, where the tree renamed one, by type.
    var collectionNames: [String: String] = [:]
    /// The groups' names, where the tree renamed one, by type.
    var groupNames: [String: String] = [:]
    var pending: (level: Pending, text: String)?

    static func key(_ party: UUID, _ category: String) -> String { party.uuidString + "/" + category }

    /// The collections, in the order their types were picked; a type stays while it waits for its first name.
    var types: [String] = []
    func parties(of type: String) -> [Party] { parties.filter { $0.type == type } }
    func names(of type: String) -> [String] { parties(of: type).filter { !$0.isOwnWork }.map { $0.name } }
    func categories(of party: UUID) -> [String] { categoriesOf[party] ?? [] }
    func streams(of party: UUID, _ category: String) -> [String] { streamsOf[Self.key(party, category)] ?? [] }
    func activeStreams(of party: UUID, _ category: String) -> [String] { oneKind ? [] : streams(of: party, category) }
    func member(of party: UUID, _ category: String) -> String? { members[Self.key(party, category)].flatMap { $0.isEmpty ? nil : $0 } }
    /// Every party and category, in order: the blocks a later question is asked in.
    var chains: [(party: Party, category: String)] { parties.flatMap { p in categories(of: p.id).map { (p, $0) } } }
    var everyoneCategorised: Bool { !parties.isEmpty && parties.allSatisfy { !categories(of: $0.id).isEmpty } }
    var anyoneNamed: Bool { chains.contains { member(of: $0.party.id, $0.category) != nil } }
    var anyStreams: Bool { !oneKind && chains.contains { !streams(of: $0.party.id, $0.category).isEmpty } }
    var streamsAnswered: Bool { oneKind || chains.contains { !streams(of: $0.party.id, $0.category).isEmpty } }
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
    /// The levels between, top down: the party's word, Category when any of the type's parties has one, Stream when any of their streams are on.
    func levelNames(for type: String) -> [String] {
        let mine = parties(of: type)
        let categorised = mine.contains { !categories(of: $0.id).isEmpty }
        let streamed = !oneKind && mine.contains { p in categories(of: p.id).contains { !streams(of: p.id, $0).isEmpty } }
        return (type == Self.ownWork ? [] : [Self.singular(type)]) + (categorised ? ["Category"] : []) + (streamed ? ["Stream"] : [])
    }
    /// The app's own group of that type, if it is one; a custom group has none and is a folder of files under its name.
    static func role(of group: String) -> SchemaRole? { SchemaRole.allCases.first { $0.title == group } }
    /// The Master Template for a type: the member, holding the groups chosen, each typed and under its name on the tree.
    func template(for type: String) -> SchemaNode {
        SchemaNode(name: memberWord(for: type), children: groups.map { SchemaNode(name: groupNames[$0] ?? $0, role: Self.role(of: $0), kind: $0) })
    }

    /// Builds the structure into a schema and a library: a collection for every type, a folder for every one named in it, that
    /// one's categories inside it, each category's streams inside that, and each category's first member in its deepest folder.
    /// Returns the collections' ids and the members' ids.
    @discardableResult
    func build(into schema: inout SchemaTrial.SchemaFile, library lib: inout Library, at date: Date = Date()) -> (collections: [UUID], members: [UUID]) {
        var made: [UUID] = [], ids: [UUID] = []
        for type in types {
            var collection = SchemaCollection(name: collectionTitle(type), stack: template(for: type))
            let levels = levelNames(for: type)
            collection.folderName = levels.first
            collection.levelNames = levels.count > 1 ? levels : nil
            var folders: [SchemaFolder] = []
            var places: [(name: String, folder: UUID?)] = []
            for p in parties(of: type) {
                var top: UUID?
                if !p.isOwnWork { let f = SchemaFolder(name: p.name); folders.append(f); top = f.id }
                for category in categories(of: p.id) {
                    let cf = SchemaFolder(name: category, parent: top)
                    folders.append(cf)
                    var deepest = cf.id
                    for (s, stream) in activeStreams(of: p.id, category).enumerated() {
                        let sf = SchemaFolder(name: stream, parent: cf.id)
                        folders.append(sf)
                        if s == 0 { deepest = sf.id }
                    }
                    if let name = member(of: p.id, category) { places.append((name, deepest)) }
                }
            }
            collection.folders = folders
            schema.collections.append(collection)
            ids.append(collection.id)
            for place in places {
                let id = lib.createProject(named: place.name, at: date)
                schema.places[id.uuidString] = SchemaPlace(collection: collection.id, folder: place.folder)
                made.append(id)
            }
        }
        return (ids, made)
    }
}
