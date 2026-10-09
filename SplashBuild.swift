import Foundation

// ---------- What the splash's answers build ----------
//
// The answers to the splash's questions, and the catalogue structure they make. Who the work is for
// gives the collections: every type picked (Clients, Brands, a word of your own) is a collection with
// the names given as its first level, and Our Own Work a collection with no such level. Under each
// come the kinds of thing made (Products, Projects) as a level, then the streams of work (Web, Print)
// as a level, each only when any were chosen; the first member sits in the deepest folder of the
// first chain, and the Master Template holds the groups chosen, in their order. Pure, so the
// self-test can build every combination of answers and check the tree it gives.

final class SplashDraft {
    static let ownWork = "Our own work"
    static let whoOptions = ["Clients", "Customers", "Contracts", "Brands"]
    static let streamOptions = ["Web", "Print", "Design", "Video", "Packaging"]
    static let makeOptions = ["Products", "Projects", "Ranges", "Jobs", "Campaigns"]
    /// The groups inside each member, to start: the four the app fills itself.
    static let groupStart = SchemaRole.allCases.map { $0.title }
    /// The groups offered: the four, then the schema page's own types, so the splash and the Schema page never disagree.
    static let groupOptions = groupStart + SchemaTrial.nestedNames.filter { !groupStart.contains($0) }

    /// One of the first level: a client, a brand, named; or the user's own work, which has no name.
    struct Party: Equatable {
        var type: String
        var name: String
        var isOwnWork: Bool { type == SplashDraft.ownWork }
    }
    /// A word being typed, shown on the tree before it is taken.
    enum Pending: Equatable { case party(String), kind, stream, group, member }

    /// The catalogue's name as typed on the first section; nil keeps the name it has. Set renames it, nothing before.
    var catalogueName: String?
    /// Who the work is for, in order: each a collection's type and a first-level name.
    var parties: [Party] = []
    /// What is made, plural, in order; a level under each party as soon as any is chosen.
    var kinds: [String] = []
    /// The streams chosen, in order; a level under each kind unless `oneKind` sets them aside.
    var streams: [String] = []
    /// One kind of work: the streams are kept but make no level, so unticking brings them back.
    var oneKind = false
    /// The groups inside each member, by type, in the Master Template's order.
    var groups: [String] = groupStart
    /// The first members' names.
    var members: [String] = []
    /// The collections' names, where the tree renamed one, by type.
    var collectionNames: [String: String] = [:]
    /// The groups' names, where the tree renamed one, by type.
    var groupNames: [String: String] = [:]
    var pending: (level: Pending, text: String)?

    /// The collections, in the order their types were first picked.
    var types: [String] { parties.reduce(into: [String]()) { if !$0.contains($1.type) { $0.append($1.type) } } }
    func names(of type: String) -> [String] { parties.filter { $0.type == type && !$0.isOwnWork }.map { $0.name } }
    var streamsAnswered: Bool { oneKind || !streams.isEmpty }
    var activeStreams: [String] { oneKind ? [] : streams }
    /// "Client" from "Clients", "Product" from "Products": the singular a level or a member is called by.
    static func singular(_ word: String) -> String {
        let w = word.trimmingCharacters(in: .whitespaces)
        if w.lowercased().hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.lowercased().hasSuffix("ses") || w.lowercased().hasSuffix("xes") { return String(w.dropLast(2)) }
        if w.lowercased().hasSuffix("s"), w.count > 2 { return String(w.dropLast()) }
        return w
    }
    /// The word for one of the things made: of the first kind, or "Project" before the question is answered.
    var memberWord: String { Self.singular(kinds.first ?? "Project") }
    /// The collection for a type: its name on the tree, the type itself, or "My Products" for the user's own.
    func collectionTitle(_ type: String) -> String { collectionNames[type] ?? (type == Self.ownWork ? "My " + SchemaTrial.plural(memberWord) : type) }
    /// The levels between, top down: the party's word, Kind when any is made, Stream when streams are on.
    func levelNames(for type: String) -> [String] {
        (type == Self.ownWork ? [] : [Self.singular(type)]) + (kinds.isEmpty ? [] : ["Kind"]) + (activeStreams.isEmpty ? [] : ["Stream"])
    }
    /// The app's own group of that type, if it is one; a custom group has none and is a folder of files under its name.
    static func role(of group: String) -> SchemaRole? { SchemaRole.allCases.first { $0.title == group } }
    /// The Master Template: the member, holding the groups chosen, each typed and under its name on the tree.
    var template: SchemaNode {
        SchemaNode(name: memberWord, children: groups.map { SchemaNode(name: groupNames[$0] ?? $0, role: Self.role(of: $0), kind: $0) })
    }

    /// Builds the structure into a schema and a library: a collection for every type, its folders level by level inside every
    /// folder of the level above, and the members in the deepest folder of the first collection's first chain.
    /// Returns the collections' ids and the members' ids.
    @discardableResult
    func build(into schema: inout SchemaTrial.SchemaFile, library lib: inout Library, at date: Date = Date()) -> (collections: [UUID], members: [UUID]) {
        var made: [UUID] = [], ids: [UUID] = []
        for (n, type) in types.enumerated() {
            var collection = SchemaCollection(name: collectionTitle(type), stack: template)
            let levels = levelNames(for: type)
            collection.folderName = levels.first
            collection.levelNames = levels.count > 1 ? levels : nil
            var folders: [SchemaFolder] = []
            var parents: [UUID?] = [nil]
            for level in [names(of: type), kinds, activeStreams] where !level.isEmpty {
                var next: [UUID?] = []
                for p in parents { for name in level { let f = SchemaFolder(name: name, parent: p); folders.append(f); next.append(f.id) } }
                parents = next
            }
            collection.folders = folders
            schema.collections.append(collection)
            ids.append(collection.id)
            guard n == 0 else { continue }
            let deepest = parents.first ?? nil
            for name in members where !name.trimmingCharacters(in: .whitespaces).isEmpty {
                let id = lib.createProject(named: name, at: date)
                schema.places[id.uuidString] = SchemaPlace(collection: collection.id, folder: deepest)
                made.append(id)
            }
        }
        return (ids, made)
    }
}
