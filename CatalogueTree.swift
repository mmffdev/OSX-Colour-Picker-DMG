import Foundation

// ---------- The catalogue on disk: one file for the structure, a file for each asset ----------
//
// Since version 3 (2026-10-09) a catalogue is one structure file and its assets. The structure file,
// "Rick 001.colcat", holds the whole tree and no payload: the collections with their Master Templates,
// the levels between, the members with their own schemas, the templates, the tags, and a link to every
// asset by id, kind and path. Everything with content is an asset file of its own kind:
//
//     Rick 001/Rick 001.colcat                      the structure and the index of every asset
//     Rick 001/Rick 001.colhis                      what was done, as operations, newest last
//     Rick 001/Library/Palettes/Scratch.colpal      a palette that belongs to no member
//     Rick 001/Library/Typography/Type 1.coltyp     a typography palette that belongs to no member
//     Rick 001/Library/Swatches/Rick 001 Swatches.colswa   the colours no palette holds
//     Rick 001/Library/Profiles/Rick 001 Profiles.colprf   the catalogue's colour profiles
//     Rick 001/Clients/MMFFDev/Web/Information/Web.colinf  a member's details
//     Rick 001/Clients/MMFFDev/Web/Palettes/Brand.colpal   a member's palette
//     Rick 001/Clients/MMFFDev/Web/Typography/Type.coltyp  a member's typography palette
//
// The folders follow the structure file: every collection, level between, member and group of a
// member's schema is a folder named as the user named it, and the app renames and moves them as the
// structure changes. Every asset says which catalogue and which member it belongs to, so the folders
// can be read back even when Finder has changed them: a folder renamed or moved in Finder is known by
// the assets inside it; a folder that vanishes beside one that appears is a rename; a folder added is
// taken in as a member, or as a collection at the root; a folder deleted takes its member with it.

/// The folder names the catalogue keeps for itself.
enum TreeFiles {
    static let library = "Library", templates = "Templates", backups = "Backups"
    static let palettesPool = "Palettes", typographyPool = "Typography", swatchesPool = "Swatches", profilesPool = "Profiles"
    static let pools = [palettesPool, typographyPool, swatchesPool, profilesPool]
    /// Folder names at the root that a collection may not take.
    static let reserved: Set<String> = [library, templates, backups, "Catalogues"]
    /// The self-test removes what it takes out; the app puts it in the Bin.
    static var removedGoesToBin = true
}

/// One asset as the structure file links it: what it is, what it is called, and where its file is.
struct AssetLink: Codable, Equatable {
    enum Kind: String, Codable { case palette, typography }
    var id: UUID
    var kind: Kind
    var name: String
    /// The file's path from the catalogue's folder, with "/" between the parts.
    var file: String
}

/// A member in the structure file: where its folder is, its own schema if it has shaped one, and its assets in order.
struct MemberEntry: Codable, Equatable {
    var id: UUID
    var name: String
    /// The folder it was written under: a folder found under another name was renamed in Finder.
    var folder: String
    var createdAt: Date
    /// Its own tree; nil while it follows its collection's Master Template.
    var schema: SchemaNode?
    /// The folder each group of its schema was written as, by the group's id, so a renamed group finds its folder.
    var buckets: [String: String]
    /// Its information pack, from the catalogue's folder.
    var information: String?
    /// Its palettes and typography palettes, in order.
    var assets: [AssetLink]
    /// The purpose each of its palettes is turned to, for those that have ever been turned to one.
    var turned: [TurnedPalette]?
}

/// A level between in the structure file: a client, say, and the members inside it.
struct GroupEntry: Codable, Equatable {
    var id: UUID
    var name: String
    var folder: String
    var members: [MemberEntry]
    /// The levels inside this one, since levels nest to any depth.
    var groups: [GroupEntry]? = nil

    /// Every member beneath, at any depth, each with the group it sits in directly.
    var allMembers: [(member: MemberEntry, group: UUID)] { members.map { ($0, id) } + (groups ?? []).flatMap { $0.allMembers } }
    var allGroups: [GroupEntry] { [self] + (groups ?? []).flatMap { $0.allGroups } }
}

/// A collection in the structure file: its details, its Master Template, its levels between and the members directly in it.
struct CollectionEntry: Codable, Equatable {
    var id: UUID
    var name: String
    var about: String
    var folder: String
    /// What the members are grouped under, such as "Client"; nil when they sit straight under the heading.
    var groupName: String?
    /// What each level between is called, top down; `groupName` is the first.
    var levelNames: [String]? = nil
    var template: SchemaNode
    var templateID: UUID?
    var groups: [GroupEntry]
    var members: [MemberEntry]

    /// Every member in the collection, at any depth, each with the group it sits in directly, or nil for one straight in the collection.
    var allMembers: [(member: MemberEntry, group: UUID?)] { members.map { ($0, nil) } + groups.flatMap { $0.allMembers.map { ($0.member, Optional($0.group)) } } }
    var allGroups: [GroupEntry] { groups.flatMap { $0.allGroups } }
}

/// "Rick 001.colcat": the catalogue's structure and the index of everything in it. It holds no payload.
struct CatalogueFile: Codable, Equatable {
    var format = "colour-catalogue"
    var version = 3
    var generator = ColourFiles.generator
    var id: UUID
    var name: String
    var about: String?
    var createdAt: Date
    var changedAt: Date
    /// The library's own version number.
    var library: Int
    /// The palette new picks go into.
    var activePalette: UUID?
    /// The order the catalogue's colours are held in.
    var colours: [String]
    /// Every tag: the global ones, and each member's, which say whose they are.
    var tags: [TagInfo]
    /// What was deleted and when, so that a sync does not bring it back.
    var deleted: [Tombstone]
    /// The shapes a member can be made from.
    var templates: [SchemaTemplate]
    var collections: [CollectionEntry]
    /// The Library's palettes and typography palettes, in order.
    var libraryAssets: [AssetLink]
    /// The Library's loose colours and its profiles, from the catalogue's folder.
    var swatches: String?
    var profiles: String?
}

/// "Web.colinf": a member's information pack, its record and details.
struct InformationDocument: Codable, Equatable {
    var format = "colour-information"
    var version = 1
    var generator = ColourFiles.generator
    /// The catalogue it was written in.
    var catalogue: UUID?
    var member: UUID
    var record: Project
}

/// "Rick 001 Swatches.colswa": the colours no palette holds.
struct SwatchesDocument: Codable, Equatable {
    var format = "colour-swatches"
    var version = 1
    var generator = ColourFiles.generator
    var catalogue: UUID?
    var colours: [Colour]
}

/// "Rick 001 Profiles.colprf": the catalogue's colour profiles.
struct ProfilesDocument: Codable, Equatable {
    var format = "colour-profiles"
    var version = 1
    var generator = ColourFiles.generator
    var catalogue: UUID?
    var profiles: [ColourProfile]
}

/// What reading the tree gives back: the library, the schema, and whether the disk said something the structure file had not.
struct TreeLoaded {
    var library: Library
    var schema: SchemaTrial.SchemaFile
    var catalogue: CatalogueFile
    /// True when Finder changed something the structure file does not yet say: the caller writes the tree back so it catches up.
    var dirty: Bool
    /// What was taken in, renamed, moved or found gone, for the log and the history.
    var notes: [String]
}

enum TreeError: LocalizedError {
    case noIndex(URL)
    case notThisVersion(URL)
    var errorDescription: String? {
        switch self {
        case .noIndex(let u): return "There is no catalogue in \(u.path)."
        case .notThisVersion(let u): return "\(u.lastPathComponent) is from an earlier version and has not been brought across yet."
        }
    }
}

enum CatalogueTree {
    private static func encoder() -> JSONEncoder { ColourFiles.encoder() }
    private static func decoder() -> JSONDecoder { ColourFiles.decoder() }
    private static let fm = FileManager.default

    // MARK: Looking

    /// The structure file in a folder, read as this version writes it; nil for none, or an earlier version's.
    static func catalogue(in root: URL) -> CatalogueFile? {
        guard let url = CatalogueFiles.index(in: root), let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> CatalogueFile? {
        guard let doc = try? decoder().decode(CatalogueFile.self, from: data), doc.format == "colour-catalogue", doc.version >= 3 else { return nil }
        return doc
    }
    /// Whether a folder holds a catalogue laid out as this version lays it out.
    static func isTree(_ root: URL) -> Bool { catalogue(in: root) != nil }

    // Every path is built from the folder it was asked for, never from what the file system says the folder's real path is,
    // so a folder reached through a link compares equal to itself wherever it was named.
    static func names(in dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    static func subfolders(of dir: URL) -> [URL] {
        names(in: dir).map { dir.appendingPathComponent($0) }.filter(isFolder)
    }
    static func files(of dir: URL, extension ext: String) -> [URL] {
        names(in: dir).filter { ($0 as NSString).pathExtension.lowercased() == ext }.map { dir.appendingPathComponent($0) }.filter { !isFolder($0) }
    }
    static func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(type, from: data)
    }
    /// The one document of a folder of an earlier layout: "Acme/Acme.colworkgroup", or whichever file of that kind is there.
    static func document(in folder: URL, extension ext: String) -> URL? {
        let named = folder.appendingPathComponent(folder.lastPathComponent + "." + ext)
        if fm.fileExists(atPath: named.path) { return named }
        return files(of: folder, extension: ext).first
    }
    /// A path under the root, with "/" between its parts.
    static func relative(_ url: URL, to root: URL) -> String {
        Array(url.pathComponents.dropFirst(root.pathComponents.count)).joined(separator: "/")
    }
    /// The file extension a palette is written under: typography palettes have their own.
    static func fileExtension(of palette: Swatch) -> String { palette.isTypography ? ColourFiles.typography : ColourFiles.palette }

    // MARK: The assets on disk

    /// An asset file found on disk, by the head of the file: what it is, its id, and the member it says it sits in.
    struct FoundAsset {
        enum Kind { case palette, typography, information }
        let url: URL
        let kind: Kind
        /// The palette's id; for an information pack, its member's.
        let id: UUID
        /// The member the file says it belongs to; nil for the Library.
        let owner: UUID?
    }
    private struct AssetHead: Decodable {
        struct P: Decodable { let id: UUID; let styles: [TypeStyle]? }
        let palette: P?
        let project: UUID?
        let member: UUID?
    }

    /// Every asset under the root, wherever Finder put it, except in the backups.
    static func scanAssets(root: URL) -> [FoundAsset] {
        var out: [FoundAsset] = []
        let kinds: Set<String> = [ColourFiles.palette, ColourFiles.typography, ColourFiles.legacyPalette, ColourFiles.information]
        func walk(_ dir: URL, depth: Int) {
            guard depth < 16 else { return }
            for name in names(in: dir) {
                let url = dir.appendingPathComponent(name)
                if isFolder(url) {
                    if depth == 0 && (name == TreeFiles.backups || name == "Catalogues") { continue }
                    walk(url, depth: depth + 1)
                    continue
                }
                let ext = (name as NSString).pathExtension.lowercased()
                guard kinds.contains(ext), let head = read(AssetHead.self, at: url) else { continue }
                if ext == ColourFiles.information {
                    if let m = head.member { out.append(FoundAsset(url: url, kind: .information, id: m, owner: m)) }
                    continue
                }
                guard let p = head.palette else { continue }
                // The palette itself says what it is; the extension is the hint.
                out.append(FoundAsset(url: url, kind: p.styles != nil ? .typography : .palette, id: p.id, owner: head.project))
            }
        }
        walk(root, depth: 0)
        return out
    }

    // MARK: Where the folders are

    /// The folders of a catalogue as they stand, matched to the structure file: by name, then by the assets inside them,
    /// then a folder gone beside one come as a rename. What is left over is new; what is still missing is gone.
    struct Resolution {
        var collections: [UUID: URL] = [:]
        var groups: [UUID: URL] = [:]
        var members: [UUID: URL] = [:]
        /// Where each member listed in the structure file is now.
        var places: [UUID: SchemaPlace] = [:]
        /// Folders added in Finder: collections at the root, with fresh ids, and members inside a collection or a level between.
        var newCollections: [(id: UUID, url: URL)] = []
        var newMembers: [(url: URL, place: SchemaPlace)] = []
        /// Collections, levels between and members whose folders are gone.
        var gone: Set<UUID> = []
        var notes: [String] = []
    }

    static func resolve(root: URL, catalogue cat: CatalogueFile?, assets: [FoundAsset]) -> Resolution {
        var r = Resolution()
        guard let cat = cat else { return r }
        func owners(under dir: URL) -> [UUID: Int] {
            let prefix = dir.path + "/"
            var count: [UUID: Int] = [:]
            for a in assets where a.url.path.hasPrefix(prefix) { if let o = a.owner { count[o, default: 0] += 1 } }
            return count
        }
        /// Each node to a folder of the same name, exactly, then ignoring case, which is all a case-only rename leaves.
        func byName(_ wanted: [(id: UUID, folder: String)], _ folders: inout [URL]) -> [UUID: URL] {
            var out: [UUID: URL] = [:]
            for pass in 0..<2 {
                for w in wanted where out[w.id] == nil {
                    guard let at = folders.firstIndex(where: { pass == 0 ? $0.lastPathComponent == w.folder : $0.lastPathComponent.lowercased() == w.folder.lowercased() }) else { continue }
                    out[w.id] = folders.remove(at: at)
                }
            }
            return out
        }
        /// Each node still missing to the leftover folder holding the most assets of its members, when one holds more than any other.
        func byAssets(_ wanted: [(id: UUID, members: Set<UUID>)], _ folders: inout [URL]) -> [UUID: URL] {
            var out: [UUID: URL] = [:]
            for w in wanted where !w.members.isEmpty {
                let scored = folders.indices.map { i in (i, owners(under: folders[i]).filter { w.members.contains($0.key) }.values.reduce(0, +)) }.filter { $0.1 > 0 }
                guard let best = scored.max(by: { $0.1 < $1.1 }), scored.filter({ $0.1 == best.1 }).count == 1 else { continue }
                out[w.id] = folders.remove(at: best.0)
            }
            return out
        }
        func membersOf(_ c: CollectionEntry) -> Set<UUID> { Set(c.allMembers.map { $0.member.id }) }

        // The collections, at the root.
        var rootFolders = subfolders(of: root).filter { !TreeFiles.reserved.contains($0.lastPathComponent) }
        var collURL = byName(cat.collections.map { ($0.id, $0.folder) }, &rootFolders)
        collURL.merge(byAssets(cat.collections.filter { collURL[$0.id] == nil }.map { ($0.id, membersOf($0)) }, &rootFolders)) { a, _ in a }
        var missing = cat.collections.filter { collURL[$0.id] == nil }
        if missing.count == 1 && rootFolders.count == 1 { collURL[missing[0].id] = rootFolders.removeFirst(); missing = [] }
        for c in cat.collections {
            guard let url = collURL[c.id] else { continue }
            if url.lastPathComponent != c.folder { r.notes.append("The collection \(c.name) was renamed to \(url.lastPathComponent) in Finder") }
        }
        for c in missing { r.gone.insert(c.id); r.notes.append("The collection \(c.name) was taken away in Finder") }
        r.collections = collURL
        for url in rootFolders {
            let id = UUID()
            r.newCollections.append((id, url))
            r.notes.append("Took in the collection \(url.lastPathComponent)")
        }

        // Inside each collection: its levels between, then the members.
        var leftovers: [(url: URL, place: SchemaPlace)] = []
        var lost: [(member: MemberEntry, place: SchemaPlace)] = []
        for c in cat.collections {
            guard let cu = collURL[c.id] else {
                // A collection gone takes everything in it, unless a member's folder turns up elsewhere.
                for m in c.members { lost.append((m, SchemaPlace(collection: c.id))) }
                for g in c.allGroups { r.gone.insert(g.id); for (m, gid) in g.allMembers where gid == g.id { lost.append((m, SchemaPlace(collection: c.id, folder: g.id))) } }
                continue
            }
            var kids = subfolders(of: cu)
            let direct = byName(c.members.map { ($0.id, $0.folder) }, &kids)
            for m in c.members {
                if let url = direct[m.id] { r.members[m.id] = url; r.places[m.id] = SchemaPlace(collection: c.id) }
                else { lost.append((m, SchemaPlace(collection: c.id))) }
            }
            // The levels between, nested: each group's folder is found among its parent's subfolders, by name, by the assets of its members, or by the folders inside it.
            func resolveGroups(_ groups: [GroupEntry], in folders: inout [URL], place: SchemaPlace) {
                var found = byName(groups.map { ($0.id, $0.folder) }, &folders)
                found.merge(byAssets(groups.filter { found[$0.id] == nil }.map { g in (g.id, Set(g.allMembers.map { $0.member.id })) }, &folders)) { a, _ in a }
                for g in groups where found[g.id] == nil {
                    let names = Set(g.members.map { $0.folder } + (g.groups ?? []).map { $0.folder })
                    let hits = folders.indices.filter { !Set(subfolders(of: folders[$0]).map { $0.lastPathComponent }).isDisjoint(with: names) }
                    if hits.count == 1 { found[g.id] = folders.remove(at: hits[0]) }
                }
                for g in groups {
                    guard let gu = found[g.id] else {
                        for gone in g.allGroups { r.gone.insert(gone.id) }
                        r.notes.append("\(g.name) was taken away in Finder")
                        for (m, gid) in g.allMembers { lost.append((m, SchemaPlace(collection: c.id, folder: gid))) }
                        continue
                    }
                    if gu.lastPathComponent != g.folder { r.notes.append("\(g.name) was renamed to \(gu.lastPathComponent) in Finder") }
                    r.groups[g.id] = gu
                    var inner = subfolders(of: gu)
                    let here = SchemaPlace(collection: c.id, folder: g.id)
                    let mine = byName(g.members.map { ($0.id, $0.folder) }, &inner)
                    for m in g.members {
                        if let url = mine[m.id] { r.members[m.id] = url; r.places[m.id] = here }
                        else { lost.append((m, here)) }
                    }
                    resolveGroups(g.groups ?? [], in: &inner, place: here)
                    leftovers += inner.map { ($0, here) }
                }
            }
            resolveGroups(c.groups, in: &kids, place: SchemaPlace(collection: c.id))
            leftovers += kids.map { ($0, SchemaPlace(collection: c.id)) }
        }
        // Members moved or renamed in Finder: known by the assets in their folders, wherever the folders went.
        var stillLost: [(member: MemberEntry, place: SchemaPlace)] = []
        for (m, place) in lost {
            let holding = leftovers.indices.compactMap { i -> (Int, Int)? in
                let o = owners(under: leftovers[i].url)
                guard let mine = o[m.id] else { return nil }
                return (i, o.values.reduce(0, +) - mine)
            }
            guard let best = holding.min(by: { $0.1 < $1.1 }) else { stillLost.append((m, place)); continue }
            let (url, now) = leftovers.remove(at: best.0)
            r.members[m.id] = url; r.places[m.id] = now
            if now != place { r.notes.append("\(m.name) was moved in Finder") }
        }
        // One gone and one come in the same place: a rename.
        var gone: [(member: MemberEntry, place: SchemaPlace)] = []
        for (m, place) in stillLost {
            let here = leftovers.indices.filter { leftovers[$0].place == place }
            let others = stillLost.filter { $0.place == place }
            if here.count == 1 && others.count == 1 {
                r.members[m.id] = leftovers.remove(at: here[0]).url; r.places[m.id] = place
            } else { gone.append((m, place)) }
        }
        for (m, _) in gone { r.gone.insert(m.id); r.notes.append("\(m.name) was taken away in Finder") }
        for c in cat.collections {
            for (m, _) in c.allMembers {
                if let url = r.members[m.id], url.lastPathComponent != m.folder { r.notes.append("\(m.name) was renamed to \(url.lastPathComponent) in Finder") }
            }
        }
        // What is left is new: a member, in the collection or level between it was dropped into.
        r.newMembers = leftovers
        for (url, _) in leftovers { r.notes.append("Took in \(url.lastPathComponent)") }
        for (id, url) in r.newCollections { r.newMembers += subfolders(of: url).map { ($0, SchemaPlace(collection: id)) } }
        return r
    }

    // MARK: Reading

    /// Reads the catalogue: the structure file, then the folders and assets as Finder has left them.
    /// `palettes` false reads only the shape, for the schema alone.
    static func read(root: URL, palettes wantPalettes: Bool = true) throws -> TreeLoaded {
        guard let indexURL = CatalogueFiles.index(in: root) else { throw TreeError.noIndex(root) }
        guard let data = try? Data(contentsOf: indexURL), let cat = decode(data) else { throw TreeError.notThisVersion(indexURL) }
        let assets = scanAssets(root: root)
        let res = resolve(root: root, catalogue: cat, assets: assets)
        var notes = res.notes
        var dirty = !notes.isEmpty
        var lib = Library()
        lib.version = cat.library
        lib.activeSwatchID = cat.activePalette
        lib.deleted = cat.deleted

        // The structure, as it stands after Finder.
        var collections: [SchemaCollection] = [], places: [String: SchemaPlace] = [:], stacks: [String: SchemaNode] = [:]
        var entries: [UUID: MemberEntry] = [:]
        for c in cat.collections where !res.gone.contains(c.id) {
            var made = SchemaCollection(id: c.id, name: c.name, about: c.about, folderName: c.groupName, folders: [], stack: c.template)
            made.templateID = c.templateID
            made.levelNames = c.levelNames
            if let url = res.collections[c.id], url.lastPathComponent != c.folder, url.lastPathComponent != filesystemName(c.name) { made.name = url.lastPathComponent }
            func take(_ groups: [GroupEntry], parent: UUID?) {
                for g in groups where !res.gone.contains(g.id) {
                    var folder = SchemaFolder(id: g.id, name: g.name, parent: parent)
                    if let url = res.groups[g.id], url.lastPathComponent != g.folder, url.lastPathComponent != filesystemName(g.name) { folder.name = url.lastPathComponent }
                    made.folders.append(folder)
                    take(g.groups ?? [], parent: g.id)
                }
            }
            take(c.groups, parent: nil)
            if !made.folders.isEmpty && made.folderName == nil { made.folderName = "Group" }
            collections.append(made)
            for (m, _) in c.allMembers { entries[m.id] = m }
        }
        for (id, url) in res.newCollections { collections.append(SchemaCollection(id: id, name: url.lastPathComponent, stack: SchemaTrial.start)) }

        // The members: each listed one still there, then each folder taken in.
        var projects: [Project] = [], memberURL: [UUID: URL] = [:]
        let infos = assets.filter { $0.kind == .information }
        func information(for id: UUID, under url: URL) -> Project? {
            let prefix = url.path + "/"
            guard let a = infos.first(where: { $0.id == id && $0.url.path.hasPrefix(prefix) }) ?? infos.first(where: { $0.id == id }) else { return nil }
            return read(InformationDocument.self, at: a.url)?.record
        }
        for c in cat.collections {
            for (m, _) in c.allMembers {
                guard let url = res.members[m.id], let place = res.places[m.id] else { continue }
                let pack = information(for: m.id, under: url)
                if pack == nil { dirty = true }
                var project = pack ?? Project(id: m.id, name: m.name, createdAt: m.createdAt)
                project.name = m.name
                if url.lastPathComponent != m.folder, url.lastPathComponent != filesystemName(m.name) { project.name = url.lastPathComponent; project.nameChangedAt = Date() }
                project.folder = nil; project.fileKnown = nil
                projects.append(project)
                memberURL[m.id] = url
                var where_ = place
                if let g = where_.folder, res.gone.contains(g) { where_.folder = nil }
                places[m.id.uuidString] = where_
                if let own = m.schema { stacks[m.id.uuidString] = own }
            }
        }
        for (url, place) in res.newMembers {
            // A member's folder copied in from elsewhere brings its information pack, and with it the member's id and details.
            let prefix = url.path + "/"
            var project = Project(id: UUID(), name: url.lastPathComponent, createdAt: Date())
            if let a = infos.first(where: { info in info.url.path.hasPrefix(prefix) && memberURL[info.id] == nil && !projects.contains { $0.id == info.id } }),
               let record = read(InformationDocument.self, at: a.url)?.record {
                project = record
                project.name = url.lastPathComponent
            }
            project.folder = nil; project.fileKnown = nil; project.position = nil
            projects.append(project)
            memberURL[project.id] = url
            places[project.id.uuidString] = place
        }

        // The assets: each where Finder has it, belonging to the member whose folder holds it, or to the Library.
        var swatches: [Swatch] = [], colours: [Colour] = [], seenColours = Set<String>(), seenPalettes = Set<UUID>()
        func takeColours(_ list: [Colour]) { for c in list where seenColours.insert(c.hex).inserted { colours.append(c) } }
        let library = root.appendingPathComponent(TreeFiles.library)
        let memberFolders = memberURL.map { ($0.key, $0.value.path + "/") }.sorted { $0.1.count > $1.1.count }
        func owner(of url: URL) -> (found: Bool, member: UUID?) {
            if let m = memberFolders.first(where: { url.path.hasPrefix($0.1) }) { return (true, m.0) }
            if url.path.hasPrefix(library.path + "/") { return (true, nil) }
            return (false, nil)
        }
        var linked: [UUID: AssetLink] = [:], order: [UUID?: [UUID]] = [:]
        for c in cat.collections { for (m, _) in c.allMembers { for a in m.assets { linked[a.id] = a }; order[m.id] = m.assets.map { $0.id } } }
        for a in cat.libraryAssets { linked[a.id] = a }
        order[nil] = cat.libraryAssets.map { $0.id }
        // A file at the path the structure file links is read before any copy of it elsewhere.
        func atLink(_ a: FoundAsset) -> Bool { linked[a.id].map { root.appendingPathComponent($0.file).path == a.url.path } ?? false }
        let palettesFound = assets.filter { $0.kind != .information && atLink($0) } + assets.filter { $0.kind != .information && !atLink($0) }
        var byOwner: [UUID?: [Swatch]] = [:]
        if wantPalettes {
            for a in palettesFound {
                let (found, member) = owner(of: a.url)
                guard found else { notes.append("\(a.url.lastPathComponent) sits outside any member and was left alone"); continue }
                guard let doc = read(PaletteDocument.self, at: a.url) else { notes.append("Could not read \(a.url.lastPathComponent)"); continue }
                guard seenPalettes.insert(doc.palette.id).inserted else { notes.append("\(a.url.lastPathComponent) is a second copy of a palette already read and was left alone"); continue }
                var p = doc.palette
                p.projectID = member
                let base = a.url.deletingPathExtension().lastPathComponent
                if let was = doc.file, was != base, filesystemName(p.name) == was {
                    notes.append("\(p.name) was renamed to \(base) in Finder")
                    p.name = base; p.nameChangedAt = Date(); dirty = true
                }
                if linked[p.id] == nil { notes.append("Took in \(a.url.lastPathComponent)"); dirty = true }
                if doc.project != member || linked[p.id].map({ root.appendingPathComponent($0.file).path != a.url.path }) ?? true { dirty = true }
                byOwner[member, default: []].append(p)
                takeColours(doc.colours)
            }
            for id in linked.keys where !seenPalettes.contains(id) { notes.append("\(linked[id]?.name ?? "A palette") was taken away in Finder"); dirty = true }
            for (key, list) in byOwner {
                var held = CatalogueFiles.ordered(list, by: order[key] ?? []) { $0.id }
                if let m = key, let entry = entries[m] {
                    for turned in entry.turned ?? [] {
                        guard let at = held.firstIndex(where: { $0.id == turned.palette }) else { continue }
                        held[at].purpose = turned.purpose
                        held[at].purposeChangedAt = turned.changedAt
                    }
                }
                swatches += held
            }
            if let file = cat.swatches.map({ root.appendingPathComponent($0) }) ?? files(of: library.appendingPathComponent(TreeFiles.swatchesPool), extension: ColourFiles.swatches).first,
               let doc = read(SwatchesDocument.self, at: file) { takeColours(doc.colours) }
        }
        if let file = cat.profiles.map({ root.appendingPathComponent($0) }) ?? files(of: library.appendingPathComponent(TreeFiles.profilesPool), extension: ColourFiles.profiles).first,
           let doc = read(ProfilesDocument.self, at: file) { lib.colourProfiles = doc.profiles }

        // The members' order is their positions; a member taken in from Finder goes last.
        var next = (projects.compactMap { $0.position }.max() ?? -1) + 1
        for i in projects.indices where projects[i].position == nil { projects[i].position = next; next += 1 }
        lib.projects = projects
        lib.swatches = swatches
        lib.colours = CatalogueFiles.ordered(colours, by: cat.colours) { $0.hex }
        let alive = Set(projects.map { $0.id })
        lib.tagInfo = cat.tags.filter { $0.projectID.map { alive.contains($0) } ?? true }
        if lib.tagInfo.count != cat.tags.count { dirty = true }
        let schema = SchemaTrial.SchemaFile(collections: collections, places: places, stacks: stacks.isEmpty ? nil : stacks, templates: cat.templates.isEmpty ? nil : cat.templates)
        return TreeLoaded(library: lib, schema: schema, catalogue: cat, dirty: dirty, notes: notes)
    }

    /// The folder of a member or a level between, by its id, wherever the tree has it.
    static func folder(ofWorkGroup id: UUID, in root: URL) -> URL? {
        let res = resolve(root: root, catalogue: catalogue(in: root), assets: scanAssets(root: root))
        return res.members[id] ?? res.groups[id]
    }
    /// A collection's folder, by its id.
    static func folder(ofCollection id: UUID, in root: URL) -> URL? {
        resolve(root: root, catalogue: catalogue(in: root), assets: scanAssets(root: root)).collections[id]
    }
    /// A palette's file, by its id, wherever the tree has it.
    static func file(ofPalette id: UUID, in root: URL) -> URL? {
        scanAssets(root: root).first { $0.id == id && $0.kind != .information }?.url
    }

    // MARK: Writing

    /// Writes the library and the schema: every folder and asset settled where the structure says, moved and renamed to
    /// match, then the structure file, then what the app listed and no longer has taken away. `carry`, when given,
    /// describes the folders of an earlier layout, for bringing one across.
    static func write(_ lib: Library, schema given: SchemaTrial.SchemaFile, index indexURL: URL, name: String? = nil, now: Date = Date(), carry: CatalogueFile? = nil) throws {
        var schema = given
        // A member always has a home: with no collection at all, the first one is made for it.
        if !lib.projects.isEmpty && schema.collections.isEmpty { schema.collections = SchemaTrial.SchemaFile.fresh.collections }
        let root = indexURL.deletingLastPathComponent()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let old = catalogue(in: root) ?? carry
        let found = scanAssets(root: root)
        let res = resolve(root: root, catalogue: old, assets: found)
        let catID = old?.id ?? UUID()
        let catName = name ?? old?.name ?? root.lastPathComponent

        // Where everything is now. A file at the path the structure file links wins over a copy of it elsewhere.
        var linkedPath: [UUID: String] = [:], knownPalettes = Set<UUID>(), oldMembers: [UUID: MemberEntry] = [:]
        for c in old?.collections ?? [] {
            for (m, _) in c.allMembers {
                oldMembers[m.id] = m
                for a in m.assets { linkedPath[a.id] = root.appendingPathComponent(a.file).path; knownPalettes.insert(a.id) }
            }
        }
        for a in old?.libraryAssets ?? [] { linkedPath[a.id] = root.appendingPathComponent(a.file).path; knownPalettes.insert(a.id) }
        var paletteAt: [UUID: URL] = [:], infoAt: [UUID: URL] = [:]
        for a in found {
            if a.kind == .information { if infoAt[a.id] == nil { infoAt[a.id] = a.url }; continue }
            if paletteAt[a.id] == nil || linkedPath[a.id] == a.url.path { paletteAt[a.id] = a.url }
        }
        var memberAt = res.members, groupAt = res.groups
        let collectionAt = res.collections
        // Folders added in Finder that the last read took in: a collection or member the structure file does not list yet takes the one of its name.
        var unclaimedCollections = res.newCollections.map { $0.url }, unclaimedMembers = res.newMembers.map { $0.url }
        func claim(_ name: String, in parent: URL?, from list: inout [URL]) -> URL? {
            guard let i = list.firstIndex(where: { url in url.lastPathComponent == name && (parent.map { url.deletingLastPathComponent().standardizedFileURL == $0.standardizedFileURL } ?? true) }) else { return nil }
            return list.remove(at: i)
        }
        /// A folder moved: everything found inside it is now under its new path.
        func rebase(from was: URL, to now: URL) {
            let a = was.standardizedFileURL.path + "/", b = now.standardizedFileURL.path + "/"
            func moved(_ url: URL) -> URL {
                let path = url.standardizedFileURL.path
                return path.hasPrefix(a) ? URL(fileURLWithPath: b + path.dropFirst(a.count)) : url
            }
            paletteAt = paletteAt.mapValues(moved); infoAt = infoAt.mapValues(moved)
            memberAt = memberAt.mapValues(moved); groupAt = groupAt.mapValues(moved)
        }
        var removing: [URL] = []
        var written: [(URL, Data)] = []
        let e = encoder()
        func link(_ s: Swatch, at url: URL) -> AssetLink { AssetLink(id: s.id, kind: s.isTypography ? .typography : .palette, name: s.name, file: relative(url, to: root)) }

        // The collections, each a folder at the root.
        var collectionURL: [UUID: URL] = [:]
        var rootNames = TreeFiles.reserved.union([indexURL.lastPathComponent])
        for c in schema.collections {
            let existing = collectionAt[c.id] ?? claim(filesystemName(c.name), in: root, from: &unclaimedCollections)
            let url = try settle(existing: existing, wanted: filesystemName(c.name), in: root, taken: &rootNames)
            if let was = existing, was != url { rebase(from: was, to: url) }
            collectionURL[c.id] = url
        }
        for c in old?.collections ?? [] where !schema.collections.contains(where: { $0.id == c.id }) {
            if let url = collectionAt[c.id] { removing.append(url) }
        }

        // The levels between, folders inside their collection, nested: each settled inside its parent's folder, parents first.
        var groupURL: [UUID: URL] = [:]
        var takenIn: [String: Set<String>] = [:]   // the names claimed in each folder, by the collection's or the folder's id
        for c in schema.collections {
            guard let home = collectionURL[c.id] else { continue }
            for f in c.folders.sorted(by: { c.chain(to: $0.id).count < c.chain(to: $1.id).count }) {
                let parentKey = f.parent?.uuidString ?? c.id.uuidString
                let parentURL = f.parent.flatMap { groupURL[$0] } ?? home
                var taken = takenIn[parentKey] ?? []
                let url = try settle(existing: groupAt[f.id], wanted: filesystemName(f.name), in: parentURL, taken: &taken)
                if let was = groupAt[f.id], was != url { rebase(from: was, to: url) }
                groupURL[f.id] = url
                takenIn[parentKey] = taken
            }
        }
        for c in old?.collections ?? [] {
            for g in c.allGroups where !schema.collections.contains(where: { $0.folders.contains { $0.id == g.id } }) { if let url = groupAt[g.id] { removing.append(url) } }
        }

        // The members, each a folder in its collection or its level between, with a folder for every group of its schema.
        var entries: [UUID: MemberEntry] = [:]
        let placesAll = schema.places
        for p in lib.orderedProjects {
            let c = SchemaTrial.collection(of: p.id, among: schema.collections, places: placesAll)
            let g = SchemaTrial.folder(of: p.id, among: schema.collections, places: placesAll)
            guard let cURL = collectionURL[c.id] else { continue }
            let parent: URL = g.flatMap { groupURL[$0] } ?? cURL
            let parentKey = (g.flatMap { groupURL[$0] != nil ? $0.uuidString : nil }) ?? c.id.uuidString
            var taken: Set<String> = takenIn[parentKey] ?? []
            let existingFolder = memberAt[p.id] ?? claim(filesystemName(p.name), in: parent, from: &unclaimedMembers)
            let folder = try settle(existing: existingFolder, wanted: filesystemName(p.name), in: parent, taken: &taken)
            if let was = existingFolder, was != folder { rebase(from: was, to: folder) }
            takenIn[parentKey] = taken

            // Its schema: its own, or the Master Template it follows.
            let tree = schema.stacks?[p.id.uuidString] ?? c.stack
            let was = oldMembers[p.id]
            var buckets: [String: String] = [:]
            var bucketURL: [UUID: URL] = [:]
            var bucketTaken: [UUID: Set<String>] = [:]
            var rootTaken: Set<String> = []
            func parentNode(of node: UUID) -> UUID? {
                func walk(_ n: SchemaNode) -> UUID? { n.children.contains { $0.id == node } ? n.id : n.children.lazy.compactMap(walk).first }
                return walk(tree)
            }
            // A group's folder is found by the group's id; a group the member never listed, as when the member moved to a
            // collection whose template has other ids, takes the folder of that name that is no longer spoken for.
            let treeIDs = Set(SchemaTrial.rows(of: tree).map { $0.node.id.uuidString })
            var spare = Set((was?.buckets ?? [:]).filter { !treeIDs.contains($0.key) }.map { $0.value })
            for row in SchemaTrial.rows(of: tree) where row.level >= 2 {
                let above = parentNode(of: row.node.id)
                let under = above.flatMap { bucketURL[$0] } ?? folder
                var takenHere = above.flatMap { bucketURL[$0] != nil ? bucketTaken[$0] : nil } ?? rootTaken
                var existing = (was?.buckets[row.node.id.uuidString]).map { under.appendingPathComponent($0) }.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                if existing == nil, spare.contains(filesystemName(row.node.name)), fm.fileExists(atPath: under.appendingPathComponent(filesystemName(row.node.name)).path) {
                    existing = under.appendingPathComponent(filesystemName(row.node.name))
                    spare.remove(filesystemName(row.node.name))
                }
                let url = try settle(existing: existing, wanted: filesystemName(row.node.name), in: under, taken: &takenHere)
                if let was = existing, was != url { rebase(from: was, to: url) }
                if let above = above, bucketURL[above] != nil { bucketTaken[above] = takenHere } else { rootTaken = takenHere }
                bucketURL[row.node.id] = url
                bucketTaken[row.node.id] = []
                buckets[row.node.id.uuidString] = url.lastPathComponent
            }
            for (nodeID, name) in was?.buckets ?? [:] where buckets[nodeID] == nil {
                // A group the schema no longer has: its folder goes, once anything in it has been written elsewhere.
                let gone = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: gone.path) && !bucketURL.values.contains(where: { $0.standardizedFileURL.path.hasPrefix(gone.standardizedFileURL.path + "/") || $0.standardizedFileURL == gone.standardizedFileURL }) { removing.append(gone) }
            }
            func bucket(for role: SchemaRole) -> URL? {
                guard let node = SchemaTrial.rows(of: tree).first(where: { SchemaTrial.role(of: $0.node) == role }) else { return nil }
                return bucketURL[node.node.id]
            }
            // Its palettes, each into the group of its kind; a member whose schema has no such group keeps them in a folder of that name.
            let held = lib.palettes(in: p.id)
            var fileTaken: [String: Set<String>] = [:]
            var links: [AssetLink] = []
            for palette in held {
                let role: SchemaRole = palette.isTypography ? .typography : .palettes
                let home = bucket(for: role) ?? folder.appendingPathComponent(role.title)
                var takenHere = fileTaken[home.path] ?? []
                let url = try settleFile(existing: paletteAt[palette.id], wanted: filesystemName(palette.name), extension: fileExtension(of: palette), in: home, taken: &takenHere)
                fileTaken[home.path] = takenHere
                paletteAt[palette.id] = url
                written.append((url, try e.encode(paletteDocument(palette, in: lib, member: p.id, file: url.deletingPathExtension().lastPathComponent, catalogue: catID))))
                links.append(link(palette, at: url))
            }
            // Its information pack, in its Information group, or in its own folder when its schema has none.
            let infoHome = bucket(for: .information) ?? folder
            var infoTaken = fileTaken[infoHome.path] ?? []
            let infoURL = try settleFile(existing: infoAt[p.id], wanted: filesystemName(p.name), extension: ColourFiles.information, in: infoHome, taken: &infoTaken)
            var record = p
            record.folder = nil; record.fileKnown = nil
            written.append((infoURL, try e.encode(InformationDocument(catalogue: catID, member: p.id, record: record))))
            let turned = held.compactMap { s in s.purposeChangedAt.map { TurnedPalette(palette: s.id, purpose: s.purpose, changedAt: $0) } }
            entries[p.id] = MemberEntry(id: p.id, name: p.name, folder: folder.lastPathComponent, createdAt: p.createdAt, schema: schema.stacks?[p.id.uuidString],
                                        buckets: buckets, information: relative(infoURL, to: root), assets: links, turned: turned.isEmpty ? nil : turned)
            memberAt[p.id] = folder
        }

        // The Library: palettes in no member, colours no palette holds, the profiles.
        let library = root.appendingPathComponent(TreeFiles.library)
        for pool in TreeFiles.pools { try fm.createDirectory(at: library.appendingPathComponent(pool), withIntermediateDirectories: true) }
        var libraryLinks: [AssetLink] = []
        var poolTaken: [String: Set<String>] = [:]
        for palette in lib.palettes(in: nil) {
            let home = library.appendingPathComponent(palette.isTypography ? TreeFiles.typographyPool : TreeFiles.palettesPool)
            var takenHere = poolTaken[home.path] ?? []
            let url = try settleFile(existing: paletteAt[palette.id], wanted: filesystemName(palette.name), extension: fileExtension(of: palette), in: home, taken: &takenHere)
            poolTaken[home.path] = takenHere
            paletteAt[palette.id] = url
            written.append((url, try e.encode(paletteDocument(palette, in: lib, member: nil, file: url.deletingPathExtension().lastPathComponent, catalogue: catID))))
            libraryLinks.append(link(palette, at: url))
        }
        let used = Set(lib.swatches.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let swatchesHome = library.appendingPathComponent(TreeFiles.swatchesPool), profilesHome = library.appendingPathComponent(TreeFiles.profilesPool)
        var none = Set<String>()
        let swatchesURL = try settleFile(existing: files(of: swatchesHome, extension: ColourFiles.swatches).first, wanted: filesystemName(catName) + " Swatches", extension: ColourFiles.swatches, in: swatchesHome, taken: &none)
        none = []
        let profilesURL = try settleFile(existing: files(of: profilesHome, extension: ColourFiles.profiles).first, wanted: filesystemName(catName) + " Profiles", extension: ColourFiles.profiles, in: profilesHome, taken: &none)
        written.append((swatchesURL, try e.encode(SwatchesDocument(catalogue: catID, colours: lib.colours.filter { !used.contains($0.hex) }))))
        written.append((profilesURL, try e.encode(ProfilesDocument(catalogue: catID, profiles: lib.colourProfiles))))

        // Everything written, each file only when what it holds has changed.
        for (url, data) in written {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        }

        // What the app listed and no longer has: palettes and members it deleted.
        let live = Set(lib.swatches.map { $0.id })
        for (id, url) in paletteAt where !live.contains(id) && knownPalettes.contains(id) { removing.append(url) }
        let livePaths = Array(memberAt.filter { lib.project($0.key) != nil }.values) + Array(groupURL.values) + Array(collectionURL.values)
        for id in oldMembers.keys where lib.project(id) == nil {
            guard let url = memberAt[id], !livePaths.contains(where: { $0.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path + "/") || $0.standardizedFileURL == url.standardizedFileURL }) else { continue }
            removing.append(url)
        }

        // The structure file, last, so it never names what is not yet there.
        let collections = schema.collections.map { c -> CollectionEntry in
            let inside = lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: schema.collections, places: placesAll).id == c.id }
            func entry(_ f: SchemaFolder) -> GroupEntry {
                let within = c.children(of: f.id).map(entry)
                return GroupEntry(id: f.id, name: f.name, folder: groupURL[f.id]?.lastPathComponent ?? filesystemName(f.name),
                                  members: inside.filter { SchemaTrial.folder(of: $0.id, among: schema.collections, places: placesAll) == f.id }.compactMap { entries[$0.id] },
                                  groups: within.isEmpty ? nil : within)
            }
            let groups = c.children(of: nil).map(entry)
            let direct = inside.filter { SchemaTrial.folder(of: $0.id, among: schema.collections, places: placesAll) == nil }.compactMap { entries[$0.id] }
            var made = CollectionEntry(id: c.id, name: c.name, about: c.about, folder: collectionURL[c.id]?.lastPathComponent ?? filesystemName(c.name), groupName: c.folderName,
                                       template: c.stack, templateID: c.templateID, groups: groups, members: direct)
            made.levelNames = c.levelNames
            return made
        }
        let file = CatalogueFile(id: catID, name: catName, about: old?.about, createdAt: old?.createdAt ?? now, changedAt: now, library: lib.version,
                                 activePalette: lib.activeSwatchID, colours: lib.colours.map { $0.hex }, tags: lib.tagInfo, deleted: lib.deleted,
                                 templates: schema.templates ?? [], collections: collections, libraryAssets: libraryLinks,
                                 swatches: relative(swatchesURL, to: root), profiles: relative(profilesURL, to: root))
        let before = catalogue(in: root)
        var sameDate = file
        sameDate.changedAt = before?.changedAt ?? now
        if sameDate != before {
            do { try e.encode(file).write(to: indexURL, options: .atomic) } catch { throw StoreError.saveFailed(indexURL, error) }
        }

        for url in removing.sorted(by: { $0.path.count > $1.path.count }) where fm.fileExists(atPath: url.path) { remove(url) }
    }

    /// The palette's file: the palette whole, settings and all, with the colours it uses, the member it sits in and the catalogue.
    static func paletteDocument(_ palette: Swatch, in lib: Library, member: UUID?, file: String, catalogue: UUID? = nil) -> PaletteDocument {
        let keys = Set(palette.entries.map { $0.hex } + (palette.styles ?? []).flatMap { [$0.ink, $0.paper] })
        var plain = palette
        // The purpose a member's palette is turned to is the member's to say.
        if member != nil { plain.purpose = nil; plain.purposeChangedAt = nil }
        var doc = PaletteDocument(project: member, palette: plain, colours: lib.colours.filter { keys.contains($0.hex) }, file: file)
        doc.catalogue = catalogue
        if palette.isTypography { doc.format = "colour-typography" }
        return doc
    }

    /// Takes the thing out: to the Bin in the app, outright in the self-test.
    static func remove(_ url: URL) {
        if TreeFiles.removedGoesToBin, (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil { return }
        try? fm.removeItem(at: url)
    }

    /// Puts a folder at `parent/<wanted>`, or the first free variant of it, moving the one that holds the same thing if it
    /// is somewhere else or under another name. `taken` is every name already claimed in `parent`.
    private static func settle(existing: URL?, wanted: String, in parent: URL, taken: inout Set<String>) throws -> URL {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if let e = existing, e.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL {
            let have = e.lastPathComponent
            // Kept where it is under the name it has, when that is the name wanted, or a variant of it that keeps clear of another.
            if have == wanted || (taken.contains(wanted) && isVariant(have, of: wanted)) { taken.insert(have); return e }
        }
        let others = Set(((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0 != existing?.lastPathComponent || existing?.deletingLastPathComponent().standardizedFileURL != parent.standardizedFileURL }.map { $0.lowercased() })
        let name = uniqueName(wanted, among: Array(taken) + Array(others))
        let dest = parent.appendingPathComponent(name)
        if let e = existing { try move(e, to: dest) } else { try fm.createDirectory(at: dest, withIntermediateDirectories: true) }
        taken.insert(name)
        return dest
    }

    /// The same for a file: `parent/<wanted>.<ext>`, moving the file that holds the same thing, and changing its extension when an earlier version gave it another.
    private static func settleFile(existing: URL?, wanted: String, extension ext: String, in parent: URL, taken: inout Set<String>) throws -> URL {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if let e = existing, e.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL, e.pathExtension.lowercased() == ext {
            let have = e.deletingPathExtension().lastPathComponent
            if have == wanted || (taken.contains(wanted) && isVariant(have, of: wanted)) { taken.insert(have); return e }
        }
        let others = Set(files(of: parent, extension: ext).filter { $0.standardizedFileURL != existing?.standardizedFileURL }.map { $0.deletingPathExtension().lastPathComponent })
        let name = uniqueName(wanted, among: Array(taken) + Array(others))
        let dest = parent.appendingPathComponent(name + "." + ext)
        if let e = existing { try move(e, to: dest) }
        taken.insert(name)
        return dest
    }

    /// "Brand 2" is a variant of "Brand".
    private static func isVariant(_ name: String, of wanted: String) -> Bool {
        guard name.hasPrefix(wanted + " ") else { return false }
        return Int(name.dropFirst(wanted.count + 1)) != nil
    }

    /// A move that also works when only the case of the name changes, which a case-insensitive disk refuses in one step.
    private static func move(_ from: URL, to: URL) throws {
        guard from.standardizedFileURL != to.standardizedFileURL else { return }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        if from.path.lowercased() == to.path.lowercased() {
            let temp = to.deletingLastPathComponent().appendingPathComponent(".moving-\(UUID().uuidString)")
            try fm.moveItem(at: from, to: temp)
            try fm.moveItem(at: temp, to: to)
        } else {
            try fm.moveItem(at: from, to: to)
        }
    }

    // MARK: Watching

    /// What the tree looks like, cheaply: every path and its modification date. Two signatures the same mean nothing changed.
    static func signature(root: URL) -> String {
        var lines: [String] = []
        func walk(_ dir: URL, depth: Int) {
            guard depth < 12 else { return }
            // The history is the app's own and written on its own clock, so it is not news.
            for name in names(in: dir) where !(depth == 0 && (name as NSString).pathExtension == ColourFiles.history) {
                let url = dir.appendingPathComponent(name)
                let v = try? fm.attributesOfItem(atPath: url.path)
                let stamp = (v?[.modificationDate] as? Date).map { String(format: "%.6f", $0.timeIntervalSince1970) } ?? "0"
                lines.append("\(url.path)|\(stamp)|\(v?[.size] as? Int ?? 0)")
                if isFolder(url), name != TreeFiles.backups, name != "Catalogues" { walk(url, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return lines.sorted().joined(separator: "\n")
    }

    // MARK: Making

    /// A new, empty catalogue: the structure file and the Library, with the first collection.
    static func make(at root: URL, name: String, schema: SchemaTrial.SchemaFile = .fresh, now: Date = Date()) throws -> URL {
        let indexURL = root.appendingPathComponent(filesystemName(name) + "." + ColourFiles.catalogue)
        try write(Library(), schema: schema, index: indexURL, name: name, now: now)
        return indexURL
    }
}
