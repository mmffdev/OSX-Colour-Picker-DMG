import Foundation

// ---------- What the splash's answers build ----------
//
// The answers to the splash's questions, and the catalogue structure they make: a collection named
// for the answers, its levels between (a client, then a stream, when the answers call for them),
// the first folders named as the user named them, the first member in the deepest of them, and the
// Master Template holding the groups chosen. Pure, so the self-test can build every combination of
// answers and check the tree it gives.

final class SplashDraft {
    static let ownWork = "Our own work"
    static let oneKind = "No, one kind"
    static let whoOptions = ["Clients", "Customers", "Contracts", "Brands", ownWork]
    static let streamOptions = ["Web", "Print", "Design", "Video", "Packaging"]
    static let makeOptions = ["Products", "Projects", "Ranges", "Jobs", "Campaigns"]

    /// Who the work is for: one of `whoOptions`, or a word of the user's own; nil until answered.
    var who: String?
    /// The streams chosen, in order; empty is one kind of work.
    var streams: [String] = []
    /// Whether the streams question has been answered, one way or the other.
    var streamsAnswered = false
    /// What is made, as the user chose it, plural: nil until answered.
    var make: String?
    /// The groups inside each member, in the Master Template's order.
    var groups: [SchemaRole] = SchemaRole.allCases
    /// The first names: the clients at the first level, and the members. Streams are named by their chips.
    var clients: [String] = []
    var members: [String] = []
    /// The collection's name, once settled on the tree; nil takes it from the answers.
    var collectionName: String?
    /// The catalogue's name as typed on the first section; nil keeps the name it has. Set renames it, nothing before.
    var catalogueName: String?
    /// The groups' names, where the tree renamed one.
    var groupNames: [SchemaRole: String] = [:]

    var isOwnWork: Bool { who == Self.ownWork }
    /// "Client" from "Clients", "Product" from "Products": the singular a level or a member is called by.
    static func singular(_ word: String) -> String {
        let w = word.trimmingCharacters(in: .whitespaces)
        if w.lowercased().hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.lowercased().hasSuffix("ses") || w.lowercased().hasSuffix("xes") { return String(w.dropLast(2)) }
        if w.lowercased().hasSuffix("s"), w.count > 2 { return String(w.dropLast()) }
        return w
    }
    var memberWord: String { Self.singular(make ?? "Project") }
    var clientWord: String { isOwnWork || who == nil ? "" : Self.singular(who!) }
    /// The collection: who the work is for, or "My Products" for the user's own.
    var collectionTitle: String { collectionName ?? (isOwnWork ? "My " + SchemaTrial.plural(memberWord) : (who ?? "Clients")) }
    /// The levels between, top down: the client's word, then Stream, as the answers call for them.
    var levelNames: [String] { (isOwnWork ? [] : [clientWord]) + (streams.isEmpty ? [] : ["Stream"]) }
    /// The Master Template: the member, holding the groups chosen, each under its name on the tree.
    var template: SchemaNode {
        SchemaNode(name: memberWord, children: groups.map { SchemaNode(name: groupNames[$0] ?? $0.title, role: $0) })
    }

    /// Builds the structure into a schema and a library: the collection with its folders, every client with every stream inside it,
    /// and the members in the deepest folder of the first chain. Returns the collection's id and the members' ids.
    @discardableResult
    func build(into schema: inout SchemaTrial.SchemaFile, library lib: inout Library, at date: Date = Date()) -> (collection: UUID, members: [UUID]) {
        var collection = SchemaCollection(name: collectionTitle, stack: template)
        let levels = levelNames
        collection.folderName = levels.first
        collection.levelNames = levels.count > 1 ? levels : nil
        var deepest: UUID?
        var folders: [SchemaFolder] = []
        if isOwnWork {
            for (j, s) in streams.enumerated() { let f = SchemaFolder(name: s); folders.append(f); if j == 0 { deepest = f.id } }
        } else {
            for (i, name) in clients.enumerated() {
                let c = SchemaFolder(name: name)
                folders.append(c)
                if i == 0 { deepest = c.id }
                for (j, s) in streams.enumerated() {
                    let f = SchemaFolder(name: s, parent: c.id)
                    folders.append(f)
                    if i == 0 && j == 0 { deepest = f.id }
                }
            }
        }
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
