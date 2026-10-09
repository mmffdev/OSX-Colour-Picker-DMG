import Foundation

// ---------- What the splash's answers build ----------
//
// The answers to the splash's questions, and the catalogue structure they make: a collection named
// for the answers, its levels between (a client, then a stream, then a kind of thing made, each only
// when the answers call for it), the first folders named as the user named them, the first member
// in the deepest of them, and the Master Template holding the groups chosen, in their order. Pure,
// so the self-test can build every combination of answers and check the tree it gives.

final class SplashDraft {
    static let ownWork = "Our own work"
    static let whoOptions = ["Clients", "Customers", "Contracts", "Brands", ownWork]
    static let streamOptions = ["Web", "Print", "Design", "Video", "Packaging"]
    static let makeOptions = ["Products", "Projects", "Ranges", "Jobs", "Campaigns"]
    /// The groups inside each member, to start: the four the app fills itself.
    static let groupStart = SchemaRole.allCases.map { $0.title }
    /// The groups offered: the four, then the schema page's own types, so the splash and the Schema page never disagree.
    static let groupOptions = groupStart + SchemaTrial.nestedNames.filter { !groupStart.contains($0) }

    /// The catalogue's name as typed on the first section; nil keeps the name it has. Set renames it, nothing before.
    var catalogueName: String?
    /// Who the work is for: one of `whoOptions`, or a word of the user's own; nil until answered.
    var who: String?
    /// The streams chosen, in order; empty with `oneKind` is one kind of work, no level.
    var streams: [String] = []
    /// The streams question answered the other way: one kind of work, so there is no stream level.
    var oneKind = false
    /// What is made, plural, in order; more than one kind is a level of its own under the streams.
    var kinds: [String] = []
    /// The groups inside each member, by type, in the Master Template's order.
    var groups: [String] = groupStart
    /// The first names: the clients at the first level, and the members. Streams and kinds are named by their choices.
    var clients: [String] = []
    var members: [String] = []
    /// The collection's name, once settled on the tree; nil takes it from the answers.
    var collectionName: String?
    /// The groups' names, where the tree renamed one, by type.
    var groupNames: [String: String] = [:]

    var streamsAnswered: Bool { oneKind || !streams.isEmpty }
    var isOwnWork: Bool { who == Self.ownWork }
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
    var clientWord: String { isOwnWork || who == nil ? "" : Self.singular(who!) }
    /// The collection: who the work is for, or "My Products" for the user's own.
    var collectionTitle: String { collectionName ?? (isOwnWork ? "My " + SchemaTrial.plural(memberWord) : (who ?? "Clients")) }
    /// The levels between, top down: the client's word, Stream when there are streams, Kind when more than one kind is made.
    var levelNames: [String] { (isOwnWork ? [] : [clientWord]) + (streams.isEmpty ? [] : ["Stream"]) + (kinds.count > 1 ? ["Kind"] : []) }
    /// The app's own group of that type, if it is one; a custom group has none and is a folder of files under its name.
    static func role(of group: String) -> SchemaRole? { SchemaRole.allCases.first { $0.title == group } }
    /// The Master Template: the member, holding the groups chosen, each typed and under its name on the tree.
    var template: SchemaNode {
        SchemaNode(name: memberWord, children: groups.map { SchemaNode(name: groupNames[$0] ?? $0, role: Self.role(of: $0), kind: $0) })
    }

    /// Builds the structure into a schema and a library: the collection with its folders, every level's folders inside every
    /// folder of the level above, and the members in the deepest folder of the first chain. Returns the collection's id and the members' ids.
    @discardableResult
    func build(into schema: inout SchemaTrial.SchemaFile, library lib: inout Library, at date: Date = Date()) -> (collection: UUID, members: [UUID]) {
        var collection = SchemaCollection(name: collectionTitle, stack: template)
        let levels = levelNames
        collection.folderName = levels.first
        collection.levelNames = levels.count > 1 ? levels : nil
        var folders: [SchemaFolder] = []
        var parents: [UUID?] = [nil]
        for level in [isOwnWork ? [] : clients, streams, kinds.count > 1 ? kinds : []] where !level.isEmpty {
            var next: [UUID?] = []
            for p in parents { for name in level { let f = SchemaFolder(name: name, parent: p); folders.append(f); next.append(f.id) } }
            parents = next
        }
        let deepest = parents.first ?? nil
        collection.folders = folders
        schema.collections.append(collection)
        var made: [UUID] = []
        for name in members where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            let id = lib.createProject(named: name, at: date)
            schema.places[id.uuidString] = SchemaPlace(collection: collection.id, folder: deepest)
            made.append(id)
        }
        return (collection.id, made)
    }
}
