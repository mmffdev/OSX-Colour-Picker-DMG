import Foundation

// ---------- The catalogue on disk: a tree that follows the schema ----------
//
// Since 2026-10-09 the folders of a catalogue are the tree the app shows. Every level is a folder
// named as the user named it, holding one readable file that describes it, so Finder, the app,
// a backup and a colleague all see the same thing. Nothing structural lives anywhere else.
//
//     Rick 001/Rick 001.colcatalogue            the index: the catalogue's name and id, its global
//                                               tags, the order of its collections, what was deleted
//     Rick 001/Rick 001.colhistory              what was done, as operations, newest last
//     Rick 001/Library/Palettes/…               the pool: work that belongs to no job
//     Rick 001/Library/Palettes/Palettes.colassets   the order of the pool
//     Rick 001/Library/Typography/…
//     Rick 001/Library/Swatches/Swatches.colassets   colours no palette holds
//     Rick 001/Library/Profiles/Profiles.colassets   the catalogue's colour profiles
//     Rick 001/Templates/Agency Job.coltemplate      a shape a work group can be made from
//     Rick 001/Clients/Clients.colcollection         a collection: its details, its Master Template,
//                                                    the order of what is in it
//     Rick 001/Clients/Acme/Acme.colworkgroup        a level between, a client, holding work groups
//     Rick 001/Clients/Acme/Website/Website.colworkgroup   a member: its details, its own schema,
//                                                    its tags, the order of its palettes
//     Rick 001/Clients/Acme/Website/Palettes/Brand.colpalette   one palette, settings and all
//     Rick 001/Clients/Acme/Website/Typography/…     every group of the member's schema is a folder
//
// Two rules decide everything. The disk decides what exists: a folder or file that is there is in
// the catalogue, one that is gone is gone. The files decide the order: each level lists what it
// holds in the order the rails show, and that list is also what the app knows about, so a folder
// the app has never listed was added in Finder and is taken in, and one the app listed and no
// longer wants is the app's to remove. Every rename or move in the app moves the folder or file
// the same instant; every rename in Finder shows in the app on the next read.

/// The files of the tree, and the folder names the catalogue keeps for itself.
enum TreeFiles {
    static let collection = "colcollection", workGroup = "colworkgroup", assets = "colassets", template = "coltemplate"
    static let library = "Library", templates = "Templates", backups = "Backups"
    static let palettesPool = "Palettes", typographyPool = "Typography", swatchesPool = "Swatches", profilesPool = "Profiles"
    static let pools = [palettesPool, typographyPool, swatchesPool, profilesPool]
    /// Folder names at the root that a collection may not take.
    static let reserved: Set<String> = [library, templates, backups, "Catalogues"]
    /// The self-test removes what it takes out; the app puts it in the Bin.
    static var removedGoesToBin = true
}

/// "Rick 001.colcatalogue": the index. Version 2 lists no members: the folders are the members.
struct CatalogueIndex: Codable, Equatable {
    var format = "colour-catalogue"
    var version = 2
    var generator = ColourFiles.generator
    var id: UUID
    var name: String
    var createdAt: Date
    var changedAt: Date
    /// The library's own version number.
    var library: Int
    /// The collections in rail order, by id: the app's list of what it knows at the root.
    var collections: [UUID]
    /// The templates the app knows, by id.
    var templates: [UUID]
    /// The order the catalogue's colours are held in.
    var colours: [String]
    /// Tags that belong to no member: the global ones, and those of a level between.
    var tags: [TagInfo]
    /// The palette new picks go into.
    var activePalette: UUID?
    /// What was deleted and when, so that a sync does not bring it back.
    var deleted: [Tombstone]
    /// The user's notes on the catalogue.
    var about: String?
}

/// "Clients.colcollection": a collection and what it holds.
struct CollectionDocument: Codable, Equatable {
    var format = "colour-collection"
    var version = 1
    var generator = ColourFiles.generator
    var id: UUID
    var name: String
    var about: String
    /// The folder this was written under: a folder found under another name was renamed in Finder.
    var folder: String
    /// What the members are grouped under, such as "Client"; nil when they sit straight under the heading.
    var groupName: String?
    /// The Master Template: the shape a new member of this collection is made from.
    var template: SchemaNode
    /// The template file the Master Template was taken from, if any.
    var templateID: UUID?
    /// The levels between and the members directly inside, in rail order: what the app knows is here.
    var members: [UUID]
    var changedAt: Date
}

/// "Website.colworkgroup": a member, with its own schema; or "Acme.colworkgroup", a level between that holds members.
struct WorkGroupDocument: Codable, Equatable {
    enum Kind: String, Codable { case member, group }
    var format = "colour-workgroup"
    var version = 1
    var generator = ColourFiles.generator
    var id: UUID
    var name: String
    var folder: String
    var kind: Kind
    /// A member's record: its details, dates, lock and profile.
    var project: Project?
    /// A member's tree: the shape its folders follow. Its own once it has shaped one; until then the Master Template as it stood when this was written.
    var schema: SchemaNode?
    /// True while the member follows its collection's Master Template, so a change to the template reaches it; absent once the tree is its own.
    var followsTemplate: Bool?
    /// A member's own tags.
    var tags: [TagInfo]?
    /// A member's palettes in order, colours and typography alike: what the app knows is here.
    var palettes: [UUID]?
    /// The order of the colours its palettes use.
    var colours: [String]?
    /// The purpose each of its palettes is turned to, for those that have ever been turned to one.
    var turned: [TurnedPalette]?
    /// The folder each group of the schema was written as, by the group's id, so a renamed group finds its folder.
    var buckets: [String: String]?
    /// A level between: the members inside it, in order.
    var members: [UUID]?
    var changedAt: Date
}

/// "Palettes.colassets": one pool of the Library, and its order.
struct AssetsDocument: Codable, Equatable {
    var format = "colour-assets"
    var version = 1
    var generator = ColourFiles.generator
    var pool: String
    /// The palettes in order, for the Palettes and Typography pools.
    var items: [UUID]?
    /// Colours no palette holds, for the Swatches pool.
    var colours: [Colour]?
    /// The catalogue's colour profiles, for the Profiles pool.
    var profiles: [ColourProfile]?
    var changedAt: Date
}

/// "Agency Job.coltemplate": a shape a work group can be made from.
struct TemplateDocument: Codable, Equatable {
    var format = "colour-template"
    var version = 1
    var generator = ColourFiles.generator
    var id: UUID
    var name: String
    var about: String
    var file: String
    var stack: SchemaNode
    var changedAt: Date
}

/// What reading the tree gives back: the library, the schema, and whether the disk said something the files had not.
struct TreeLoaded {
    var library: Library
    var schema: SchemaTrial.SchemaFile
    var index: CatalogueIndex
    /// True when a folder or file was found that the files did not list, or under a name they did not give: the caller writes the tree back so the files catch up.
    var dirty: Bool
    /// What was taken in or renamed, for the log and the history.
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

    /// The index in a folder, read as this version writes it; nil for an earlier version's index.
    static func index(in root: URL) -> CatalogueIndex? {
        guard let url = CatalogueFiles.index(in: root), let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> CatalogueIndex? {
        guard let doc = try? decoder().decode(CatalogueIndex.self, from: data), doc.format == "colour-catalogue", doc.version >= 2 else { return nil }
        return doc
    }
    /// Whether a folder holds a catalogue laid out as this version lays it out.
    static func isTree(_ root: URL) -> Bool { index(in: root) != nil }

    // Every path is built from the folder it was asked for, never from what the file system says the folder's real path is,
    // so a folder reached through a link compares equal to itself wherever it was named.
    private static func names(in dir: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    private static func subfolders(of dir: URL) -> [URL] {
        names(in: dir).map { dir.appendingPathComponent($0) }.filter(isFolder)
    }
    private static func files(of dir: URL, extension ext: String) -> [URL] {
        names(in: dir).filter { ($0 as NSString).pathExtension.lowercased() == ext }.map { dir.appendingPathComponent($0) }.filter { !isFolder($0) }
    }
    private static func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(type, from: data)
    }
    /// The one document of a folder: "Acme/Acme.colworkgroup", or whichever file of that kind is there.
    private static func document(in folder: URL, extension ext: String) -> URL? {
        let named = folder.appendingPathComponent(folder.lastPathComponent + "." + ext)
        if fm.fileExists(atPath: named.path) { return named }
        return files(of: folder, extension: ext).first
    }

    // MARK: Reading

    /// Reads the whole tree. `palettes` false reads only the shape, for the schema alone.
    static func read(root: URL, palettes wantPalettes: Bool = true) throws -> TreeLoaded {
        guard let indexURL = CatalogueFiles.index(in: root) else { throw TreeError.noIndex(root) }
        guard let data = try? Data(contentsOf: indexURL), let index = decode(data) else { throw TreeError.notThisVersion(indexURL) }
        var lib = Library()
        lib.version = index.library
        lib.activeSwatchID = index.activePalette
        lib.deleted = index.deleted
        var dirty = false, notes: [String] = []
        var swatches: [Swatch] = [], colours: [Colour] = [], seenColours = Set<String>(), seenPalettes = Set<UUID>()
        var tags: [TagInfo] = index.tags
        var collections: [SchemaCollection] = [], places: [String: SchemaPlace] = [:], stacks: [String: SchemaNode] = [:]
        var projects: [Project] = []

        func takeColours(_ list: [Colour]) { for c in list where seenColours.insert(c.hex).inserted { colours.append(c) } }

        /// Every palette under a member's folder, in no particular folder: the role buckets are where the app puts them, Finder may put them anywhere.
        func palettes(under folder: URL, member: UUID?, known: [UUID]) -> [Swatch] {
            var found: [(Swatch, URL)] = []
            func walk(_ dir: URL) {
                for url in files(of: dir, extension: ColourFiles.palette) {
                    guard let doc = read(PaletteDocument.self, at: url) else { notes.append("Could not read \(url.lastPathComponent)"); continue }
                    guard seenPalettes.insert(doc.palette.id).inserted else { notes.append("\(url.lastPathComponent) is a second copy of a palette already read and was left alone"); continue }
                    var p = doc.palette
                    p.projectID = member
                    let base = url.deletingPathExtension().lastPathComponent
                    if let was = doc.file, was != base, filesystemName(p.name) == was {
                        notes.append("\(p.name) was renamed to \(base) in Finder")
                        p.name = base; p.nameChangedAt = Date(); dirty = true
                    }
                    if doc.project != member { dirty = true }
                    found.append((p, url))
                    takeColours(doc.colours)
                }
                // A member holds no work groups; a folder with a work group file inside a member is a stray and is not walked.
                for sub in subfolders(of: dir) where document(in: sub, extension: TreeFiles.workGroup) == nil { walk(sub) }
            }
            walk(folder)
            let ordered = CatalogueFiles.ordered(found, by: known) { $0.0.id }
            if ordered.contains(where: { !known.contains($0.0.id) }) { dirty = true; notes.append(contentsOf: ordered.filter { !known.contains($0.0.id) }.map { "Took in \($0.1.lastPathComponent)" }) }
            return ordered.map { $0.0 }
        }

        /// A member's folder: its record, its tree, its tags and its palettes.
        func readMember(_ folder: URL, doc: WorkGroupDocument, collection: SchemaCollection, group: UUID?) {
            var project = doc.project ?? Project(id: doc.id, name: doc.name, createdAt: doc.changedAt)
            project.folder = nil; project.fileKnown = nil
            if doc.folder != folder.lastPathComponent {
                notes.append("\(project.name) was renamed to \(folder.lastPathComponent) in Finder")
                project.name = folder.lastPathComponent; project.nameChangedAt = Date(); dirty = true
            }
            guard !projects.contains(where: { $0.id == project.id }) else { notes.append("\(folder.lastPathComponent) is a second copy of a member already read and was left alone"); return }
            projects.append(project)
            places[project.id.uuidString] = SchemaPlace(collection: collection.id, folder: group)
            if let own = doc.schema, doc.followsTemplate != true { stacks[project.id.uuidString] = own }
            if doc.schema == nil { dirty = true }
            tags += (doc.tags ?? []).filter { $0.projectID == project.id }
            guard wantPalettes else { return }
            var held = palettes(under: folder, member: project.id, known: doc.palettes ?? [])
            for turned in doc.turned ?? [] {
                guard let at = held.firstIndex(where: { $0.id == turned.palette }) else { continue }
                held[at].purpose = turned.purpose
                held[at].purposeChangedAt = turned.changedAt
            }
            swatches += held
        }

        /// The folders inside a collection or a level between that hold work groups, in the listed order, then the rest.
        func workGroups(in folder: URL, known: [UUID]) -> [(URL, WorkGroupDocument)] {
            var found: [(URL, WorkGroupDocument)] = []
            for sub in subfolders(of: folder) {
                guard let file = document(in: sub, extension: TreeFiles.workGroup) else { continue }
                guard let doc = read(WorkGroupDocument.self, at: file), doc.format == "colour-workgroup" else { notes.append("Could not read \(file.lastPathComponent)"); continue }
                found.append((sub, doc))
            }
            let ordered = CatalogueFiles.ordered(found, by: known) { $0.1.id }
            for (url, doc) in ordered where !known.contains(doc.id) { dirty = true; notes.append("Took in \(url.lastPathComponent)") }
            return ordered
        }

        // The collections: every folder at the root with a collection file, in the index's order, then any the index does not list.
        var foundCollections: [(URL, CollectionDocument)] = []
        for sub in subfolders(of: root) where !TreeFiles.reserved.contains(sub.lastPathComponent) {
            guard let file = document(in: sub, extension: TreeFiles.collection) else { continue }
            guard let doc = read(CollectionDocument.self, at: file), doc.format == "colour-collection" else { notes.append("Could not read \(file.lastPathComponent)"); continue }
            foundCollections.append((sub, doc))
        }
        foundCollections = CatalogueFiles.ordered(foundCollections, by: index.collections) { $0.1.id }
        for (url, doc) in foundCollections where !index.collections.contains(doc.id) { dirty = true; notes.append("Took in the collection \(url.lastPathComponent)") }
        for (folder, doc) in foundCollections {
            var c = SchemaCollection(id: doc.id, name: doc.name, about: doc.about, folderName: doc.groupName, folders: [], stack: doc.template)
            c.templateID = doc.templateID
            if doc.folder != folder.lastPathComponent {
                notes.append("\(doc.name) was renamed to \(folder.lastPathComponent) in Finder")
                c.name = folder.lastPathComponent; dirty = true
            }
            guard !collections.contains(where: { $0.id == c.id }) else { notes.append("\(folder.lastPathComponent) is a second copy of a collection already read and was left alone"); continue }
            // Inside: levels between and members, in the collection's order.
            var groups: [SchemaFolder] = []
            var membersHere: [(URL, WorkGroupDocument)] = []
            for (sub, wg) in workGroups(in: folder, known: doc.members) {
                if wg.kind == .group {
                    var g = SchemaFolder(id: wg.id, name: wg.name)
                    if wg.folder != sub.lastPathComponent { notes.append("\(wg.name) was renamed to \(sub.lastPathComponent) in Finder"); g.name = sub.lastPathComponent; dirty = true }
                    guard !groups.contains(where: { $0.id == g.id }) else { continue }
                    groups.append(g)
                    if c.folderName == nil { c.folderName = "Group"; dirty = true }
                    for (inner, member) in workGroups(in: sub, known: wg.members ?? []) where member.kind == .member {
                        membersHere.append((inner, member))
                        readMember(inner, doc: member, collection: c, group: g.id)
                    }
                } else {
                    membersHere.append((sub, wg))
                    readMember(sub, doc: wg, collection: c, group: nil)
                }
            }
            c.folders = groups
            collections.append(c)
        }
        if collections.isEmpty {
            collections = [SchemaCollection(id: SchemaTrial.firstCollection, name: "Projects", stack: SchemaTrial.start)]
            dirty = true
        }

        // The Library: the pool of what belongs to no job.
        let library = root.appendingPathComponent(TreeFiles.library)
        if wantPalettes {
            for pool in [TreeFiles.palettesPool, TreeFiles.typographyPool] {
                let dir = library.appendingPathComponent(pool)
                let assets = read(AssetsDocument.self, at: dir.appendingPathComponent(pool + "." + TreeFiles.assets))
                swatches += palettes(under: dir, member: nil, known: assets?.items ?? [])
            }
            if let loose = read(AssetsDocument.self, at: library.appendingPathComponent(TreeFiles.swatchesPool).appendingPathComponent(TreeFiles.swatchesPool + "." + TreeFiles.assets)) {
                takeColours(loose.colours ?? [])
            }
        }
        if let profiles = read(AssetsDocument.self, at: library.appendingPathComponent(TreeFiles.profilesPool).appendingPathComponent(TreeFiles.profilesPool + "." + TreeFiles.assets)) {
            lib.colourProfiles = profiles.profiles ?? []
        }

        // Templates.
        var templates: [SchemaTemplate] = []
        let templatesDir = root.appendingPathComponent(TreeFiles.templates)
        var foundTemplates: [TemplateDocument] = []
        for url in files(of: templatesDir, extension: TreeFiles.template) {
            guard let doc = read(TemplateDocument.self, at: url), doc.format == "colour-template" else { notes.append("Could not read \(url.lastPathComponent)"); continue }
            guard !foundTemplates.contains(where: { $0.id == doc.id }) else { continue }
            var t = doc
            let base = url.deletingPathExtension().lastPathComponent
            if t.file != base { notes.append("The template \(t.name) was renamed to \(base) in Finder"); t.name = base; dirty = true }
            foundTemplates.append(t)
        }
        foundTemplates = CatalogueFiles.ordered(foundTemplates, by: index.templates) { $0.id }
        for t in foundTemplates where !index.templates.contains(t.id) { dirty = true; notes.append("Took in the template \(t.name)") }
        templates = foundTemplates.map { SchemaTemplate(id: $0.id, name: $0.name, about: $0.about, stack: $0.stack, changedAt: $0.changedAt) }

        // The members' order is their positions; a member taken in from Finder goes last.
        var next = (projects.compactMap { $0.position }.max() ?? -1) + 1
        for i in projects.indices where projects[i].position == nil { projects[i].position = next; next += 1 }
        lib.projects = projects
        lib.swatches = swatches
        lib.colours = CatalogueFiles.ordered(colours, by: index.colours) { $0.hex }
        lib.tagInfo = tags
        let schema = SchemaTrial.SchemaFile(collections: collections, places: places, stacks: stacks.isEmpty ? nil : stacks, templates: templates.isEmpty ? nil : templates)
        return TreeLoaded(library: lib, schema: schema, index: index, dirty: dirty, notes: notes)
    }

    // MARK: The disk as it stands

    /// Where everything with an id is on disk, found by reading the head of each file, and what the files say the app knows.
    private struct DiskMap {
        var collections: [UUID: URL] = [:]
        var knownCollections: [UUID] = []
        var workGroups: [UUID: URL] = [:]
        var groupDocs: [UUID: WorkGroupDocument] = [:]
        var collectionDocs: [UUID: CollectionDocument] = [:]
        var palettes: [UUID: URL] = [:]
        var knownPalettes = Set<UUID>()
        var knownWorkGroups = Set<UUID>()
        var templates: [UUID: URL] = [:]
        var knownTemplates: [UUID] = []
        var poolDocs: [String: AssetsDocument] = [:]

        /// A folder was moved or renamed: everything the scan found inside it is now under the new path.
        mutating func rebase(from old: URL, to new: URL) {
            let was = old.standardizedFileURL.path + "/", now = new.standardizedFileURL.path + "/"
            func moved(_ url: URL) -> URL {
                let path = url.standardizedFileURL.path
                return path.hasPrefix(was) ? URL(fileURLWithPath: now + path.dropFirst(was.count)) : url
            }
            palettes = palettes.mapValues(moved)
            workGroups = workGroups.mapValues(moved)
        }
    }
    private struct PaletteHead: Decodable { struct P: Decodable { let id: UUID }; let palette: P }

    private static func scan(root: URL) -> DiskMap {
        var map = DiskMap()
        if let index = index(in: root) { map.knownCollections = index.collections; map.knownTemplates = index.templates }
        func palettes(under dir: URL) {
            for url in files(of: dir, extension: ColourFiles.palette) {
                if let head = read(PaletteHead.self, at: url), map.palettes[head.palette.id] == nil { map.palettes[head.palette.id] = url }
            }
            for sub in subfolders(of: dir) where document(in: sub, extension: TreeFiles.workGroup) == nil { palettes(under: sub) }
        }
        func workGroups(in dir: URL) {
            for sub in subfolders(of: dir) {
                guard let file = document(in: sub, extension: TreeFiles.workGroup), let doc = read(WorkGroupDocument.self, at: file) else { continue }
                guard map.workGroups[doc.id] == nil else { continue }
                map.workGroups[doc.id] = sub
                map.groupDocs[doc.id] = doc
                map.knownPalettes.formUnion(doc.palettes ?? [])
                map.knownWorkGroups.formUnion(doc.members ?? [])
                if doc.kind == .group { workGroups(in: sub) } else { palettes(under: sub) }
            }
        }
        for sub in subfolders(of: root) where !TreeFiles.reserved.contains(sub.lastPathComponent) {
            guard let file = document(in: sub, extension: TreeFiles.collection), let doc = read(CollectionDocument.self, at: file) else { continue }
            guard map.collections[doc.id] == nil else { continue }
            map.collections[doc.id] = sub
            map.collectionDocs[doc.id] = doc
            map.knownWorkGroups.formUnion(doc.members)
            workGroups(in: sub)
        }
        let library = root.appendingPathComponent(TreeFiles.library)
        for pool in TreeFiles.pools {
            let dir = library.appendingPathComponent(pool)
            if let doc = read(AssetsDocument.self, at: dir.appendingPathComponent(pool + "." + TreeFiles.assets)) {
                map.poolDocs[pool] = doc
                map.knownPalettes.formUnion(doc.items ?? [])
            }
            palettes(under: dir)
        }
        for url in files(of: root.appendingPathComponent(TreeFiles.templates), extension: TreeFiles.template) {
            if let doc = read(TemplateDocument.self, at: url), map.templates[doc.id] == nil { map.templates[doc.id] = url }
        }
        return map
    }

    /// The folder of a member or a level between, by its id, wherever the tree has it.
    static func folder(ofWorkGroup id: UUID, in root: URL) -> URL? { scan(root: root).workGroups[id] }
    /// A palette's file, by its id, wherever the tree has it.
    static func file(ofPalette id: UUID, in root: URL) -> URL? { scan(root: root).palettes[id] }

    // MARK: Writing

    /// Writes the library and the schema as the tree, moving and renaming folders and files to match, and taking away
    /// what the app listed and no longer has. Everything is written before anything is taken away, so a palette
    /// moved from one member to another is in its new home before its old one is cleared.
    static func write(_ lib: Library, schema given: SchemaTrial.SchemaFile, index indexURL: URL, name: String? = nil, now: Date = Date()) throws {
        var schema = given
        if schema.collections.isEmpty { schema.collections = SchemaTrial.SchemaFile.fresh.collections }
        let root = indexURL.deletingLastPathComponent()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var disk = scan(root: root)
        let old = index(in: root)
        var removing: [URL] = []
        let e = encoder()

        // The collections, each a folder at the root.
        var collectionURL: [UUID: URL] = [:]
        var rootNames = TreeFiles.reserved.union([indexURL.lastPathComponent])
        for c in schema.collections {
            let url = try settle(existing: disk.collections[c.id], wanted: filesystemName(c.name), in: root, taken: &rootNames)
            if let was = disk.collections[c.id], was != url { disk.rebase(from: was, to: url) }
            collectionURL[c.id] = url
        }
        for id in disk.knownCollections where !schema.collections.contains(where: { $0.id == id }) {
            if let url = disk.collections[id] { removing.append(url) }
        }

        // The levels between, folders inside their collection.
        var groupURL: [UUID: URL] = [:]
        var collectionTaken: [UUID: Set<String>] = [:]
        for c in schema.collections {
            guard let home = collectionURL[c.id] else { continue }
            var taken: Set<String> = [home.lastPathComponent + "." + TreeFiles.collection]
            for f in c.folders {
                let url = try settle(existing: disk.workGroups[f.id], wanted: filesystemName(f.name), in: home, taken: &taken)
                if let was = disk.workGroups[f.id], was != url { disk.rebase(from: was, to: url) }
                groupURL[f.id] = url
            }
            collectionTaken[c.id] = taken
        }

        // The members, each a folder in its collection or in its level between, with a folder for every group of its schema.
        var memberURL: [UUID: URL] = [:]
        var groupTaken: [UUID: Set<String>] = [:]
        var memberDocs: [(URL, WorkGroupDocument)] = []
        var paletteURL: [UUID: URL] = [:]
        var written: [(URL, Data)] = []
        let placesAll = schema.places
        for p in lib.orderedProjects {
            let c = SchemaTrial.collection(of: p.id, among: schema.collections, places: placesAll)
            let g = SchemaTrial.folder(of: p.id, among: schema.collections, places: placesAll)
            let parent: URL
            if let g = g, let url = groupURL[g] { parent = url } else { parent = collectionURL[c.id]! }
            var taken: Set<String>
            if let g = g, groupURL[g] != nil { taken = groupTaken[g] ?? [parent.lastPathComponent + "." + TreeFiles.workGroup] }
            else { taken = collectionTaken[c.id] ?? [] }
            let folder = try settle(existing: disk.workGroups[p.id], wanted: filesystemName(p.name), in: parent, taken: &taken)
            if let was = disk.workGroups[p.id], was != folder { disk.rebase(from: was, to: folder) }
            if let g = g, groupURL[g] != nil { groupTaken[g] = taken } else { collectionTaken[c.id] = taken }
            memberURL[p.id] = folder

            // Its schema: its own, copied from the Master Template when it had none.
            let tree = schema.stacks?[p.id.uuidString] ?? c.stack
            let was = disk.groupDocs[p.id]
            var buckets: [String: String] = [:]
            var bucketURL: [UUID: URL] = [:]
            var bucketTaken: [UUID: Set<String>] = [:]
            var rootTaken: Set<String> = [folder.lastPathComponent + "." + TreeFiles.workGroup]
            func parentURL(of node: UUID, in root: SchemaNode) -> UUID? {
                func walk(_ n: SchemaNode) -> UUID? { n.children.contains { $0.id == node } ? n.id : n.children.lazy.compactMap(walk).first }
                return walk(root)
            }
            // A group's folder is found by the group's id; a group the member's file never listed, as when the member moved to a
            // collection whose template has other ids, takes the folder of that name that is no longer spoken for.
            let treeIDs = Set(SchemaTrial.rows(of: tree).map { $0.node.id.uuidString })
            var spare = Set((was?.buckets ?? [:]).filter { !treeIDs.contains($0.key) }.map { $0.value })
            for row in SchemaTrial.rows(of: tree) where row.level >= 2 {
                let above = parentURL(of: row.node.id, in: tree)
                let under = above.flatMap { bucketURL[$0] } ?? folder
                var takenHere = above.flatMap { bucketURL[$0] != nil ? bucketTaken[$0] : nil } ?? rootTaken
                var existing = (was?.buckets?[row.node.id.uuidString]).map { under.appendingPathComponent($0) }.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                if existing == nil, spare.contains(filesystemName(row.node.name)), fm.fileExists(atPath: under.appendingPathComponent(filesystemName(row.node.name)).path) {
                    existing = under.appendingPathComponent(filesystemName(row.node.name))
                    spare.remove(filesystemName(row.node.name))
                }
                let url = try settle(existing: existing, wanted: filesystemName(row.node.name), in: under, taken: &takenHere)
                if let was = existing, was != url { disk.rebase(from: was, to: url) }
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
            // Its palettes, each into the group of its kind.
            func bucket(for role: SchemaRole) -> URL {
                if let node = SchemaTrial.rows(of: tree).first(where: { SchemaTrial.role(of: $0.node) == role }), let url = bucketURL[node.node.id] { return url }
                let fallback = folder.appendingPathComponent(role.title)
                try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
                return fallback
            }
            let held = lib.palettes(in: p.id)
            var fileTaken: [String: Set<String>] = [:]
            for palette in held {
                let home = bucket(for: palette.isTypography ? .typography : .palettes)
                var takenHere = fileTaken[home.path] ?? []
                let url = try settleFile(existing: disk.palettes[palette.id], wanted: filesystemName(palette.name), extension: ColourFiles.palette, in: home, taken: &takenHere)
                fileTaken[home.path] = takenHere
                paletteURL[palette.id] = url
                written.append((url, try e.encode(paletteDocument(palette, in: lib, member: p.id, file: url.deletingPathExtension().lastPathComponent))))
            }
            var record = p
            record.folder = nil; record.fileKnown = nil
            let doc = WorkGroupDocument(id: p.id, name: p.name, folder: folder.lastPathComponent, kind: .member, project: record, schema: tree,
                                        followsTemplate: schema.stacks?[p.id.uuidString] == nil ? true : nil,
                                        tags: lib.tagInfo.filter { $0.projectID == p.id }, palettes: held.map { $0.id },
                                        colours: lib.colours.map { $0.hex }.filter { hex in held.contains { s in s.entries.contains { $0.hex == hex } || (s.styles ?? []).contains { $0.ink == hex || $0.paper == hex } } },
                                        turned: { let all = held.compactMap { s in s.purposeChangedAt.map { TurnedPalette(palette: s.id, purpose: s.purpose, changedAt: $0) } }; return all.isEmpty ? nil : all }(),
                                        buckets: buckets, members: nil, changedAt: was.map { $0.changedAt } ?? now)
            memberDocs.append((folder.appendingPathComponent(folder.lastPathComponent + "." + TreeFiles.workGroup), doc))
        }

        // The Library: palettes in no member, colours no palette holds, the profiles.
        let library = root.appendingPathComponent(TreeFiles.library)
        for pool in TreeFiles.pools { try fm.createDirectory(at: library.appendingPathComponent(pool), withIntermediateDirectories: true) }
        let loose = lib.palettes(in: nil)
        for (pool, kind) in [(TreeFiles.palettesPool, false), (TreeFiles.typographyPool, true)] {
            let home = library.appendingPathComponent(pool)
            let mine = loose.filter { $0.isTypography == kind }
            var takenHere: Set<String> = [pool + "." + TreeFiles.assets]
            for palette in mine {
                let url = try settleFile(existing: disk.palettes[palette.id], wanted: filesystemName(palette.name), extension: ColourFiles.palette, in: home, taken: &takenHere)
                paletteURL[palette.id] = url
                written.append((url, try e.encode(paletteDocument(palette, in: lib, member: nil, file: url.deletingPathExtension().lastPathComponent))))
            }
            let doc = AssetsDocument(pool: pool, items: mine.map { $0.id }, changedAt: disk.poolDocs[pool]?.changedAt ?? now)
            written.append((home.appendingPathComponent(pool + "." + TreeFiles.assets), try e.encode(doc)))
        }
        let used = Set(lib.swatches.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let swatchesDoc = AssetsDocument(pool: TreeFiles.swatchesPool, colours: lib.colours.filter { !used.contains($0.hex) }, changedAt: disk.poolDocs[TreeFiles.swatchesPool]?.changedAt ?? now)
        written.append((library.appendingPathComponent(TreeFiles.swatchesPool).appendingPathComponent(TreeFiles.swatchesPool + "." + TreeFiles.assets), try e.encode(swatchesDoc)))
        let profilesDoc = AssetsDocument(pool: TreeFiles.profilesPool, profiles: lib.colourProfiles, changedAt: disk.poolDocs[TreeFiles.profilesPool]?.changedAt ?? now)
        written.append((library.appendingPathComponent(TreeFiles.profilesPool).appendingPathComponent(TreeFiles.profilesPool + "." + TreeFiles.assets), try e.encode(profilesDoc)))

        // The levels between and the collections, now that what they hold is known.
        for c in schema.collections {
            guard let home = collectionURL[c.id] else { continue }
            let members = lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: schema.collections, places: placesAll).id == c.id }
            for f in c.folders {
                guard let url = groupURL[f.id] else { continue }
                let inside = members.filter { SchemaTrial.folder(of: $0.id, among: schema.collections, places: placesAll) == f.id }.map { $0.id }
                let doc = WorkGroupDocument(id: f.id, name: f.name, folder: url.lastPathComponent, kind: .group, members: inside, changedAt: disk.groupDocs[f.id]?.changedAt ?? now)
                written.append((url.appendingPathComponent(url.lastPathComponent + "." + TreeFiles.workGroup), try e.encode(doc)))
            }
            let direct = members.filter { SchemaTrial.folder(of: $0.id, among: schema.collections, places: placesAll) == nil }.map { $0.id }
            let doc = CollectionDocument(id: c.id, name: c.name, about: c.about, folder: home.lastPathComponent, groupName: c.folderName, template: c.stack,
                                         templateID: c.templateID, members: c.folders.map { $0.id } + direct, changedAt: disk.collectionDocs[c.id]?.changedAt ?? now)
            written.append((home.appendingPathComponent(home.lastPathComponent + "." + TreeFiles.collection), try e.encode(doc)))
        }
        for (url, doc) in memberDocs { written.append((url, try e.encode(doc))) }

        // Templates.
        let templatesDir = root.appendingPathComponent(TreeFiles.templates)
        try fm.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        var templateTaken = Set<String>()
        for t in schema.templates ?? [] {
            let url = try settleFile(existing: disk.templates[t.id], wanted: filesystemName(t.name), extension: TreeFiles.template, in: templatesDir, taken: &templateTaken)
            let doc = TemplateDocument(id: t.id, name: t.name, about: t.about, file: url.deletingPathExtension().lastPathComponent, stack: t.stack, changedAt: t.changedAt)
            written.append((url, try e.encode(doc)))
        }
        for id in disk.knownTemplates where !(schema.templates ?? []).contains(where: { $0.id == id }) {
            if let url = disk.templates[id] { removing.append(url) }
        }

        // Everything written, each file only when what it holds has changed.
        for (url, data) in written {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        }
        // A document left under another name in a folder whose name changed goes.
        for (url, _) in memberDocs { tidyDocuments(in: url.deletingLastPathComponent(), extension: TreeFiles.workGroup, keeping: url) }
        for url in groupURL.values { tidyDocuments(in: url, extension: TreeFiles.workGroup, keeping: url.appendingPathComponent(url.lastPathComponent + "." + TreeFiles.workGroup)) }
        for url in collectionURL.values { tidyDocuments(in: url, extension: TreeFiles.collection, keeping: url.appendingPathComponent(url.lastPathComponent + "." + TreeFiles.collection)) }

        // What the app listed and no longer has: palettes, members and levels between it deleted.
        for (id, url) in disk.palettes where lib.swatch(id) == nil && disk.knownPalettes.contains(id) { removing.append(url) }
        for (id, url) in disk.workGroups where disk.knownWorkGroups.contains(id) && lib.project(id) == nil && !schema.collections.contains(where: { c in c.folders.contains { $0.id == id } }) {
            removing.append(url)
        }

        // The index, last, so it never names what is not yet there.
        let index = CatalogueIndex(id: old?.id ?? UUID(), name: name ?? old?.name ?? root.lastPathComponent, createdAt: old?.createdAt ?? now, changedAt: now,
                                   library: lib.version, collections: schema.collections.map { $0.id }, templates: (schema.templates ?? []).map { $0.id },
                                   colours: lib.colours.map { $0.hex }, tags: lib.tagInfo.filter { $0.projectID == nil }, activePalette: lib.activeSwatchID,
                                   deleted: lib.deleted, about: old?.about)
        var indexWithoutDate = index, oldWithoutDate = old
        indexWithoutDate.changedAt = old?.changedAt ?? now
        oldWithoutDate?.changedAt = indexWithoutDate.changedAt
        if indexWithoutDate != oldWithoutDate {
            do { try e.encode(index).write(to: indexURL, options: .atomic) } catch { throw StoreError.saveFailed(indexURL, error) }
        }

        for url in removing.sorted(by: { $0.path.count > $1.path.count }) where fm.fileExists(atPath: url.path) { remove(url) }
    }

    /// The palette's file: the palette whole, settings and all, with the colours it uses.
    static func paletteDocument(_ palette: Swatch, in lib: Library, member: UUID?, file: String) -> PaletteDocument {
        let keys = Set(palette.entries.map { $0.hex } + (palette.styles ?? []).flatMap { [$0.ink, $0.paper] })
        var plain = palette
        // The purpose a member's palette is turned to is the member's to say.
        if member != nil { plain.purpose = nil; plain.purposeChangedAt = nil }
        return PaletteDocument(project: member, palette: plain, colours: lib.colours.filter { keys.contains($0.hex) }, file: file)
    }

    /// Takes the thing out: to the Bin in the app, outright in the self-test.
    static func remove(_ url: URL) {
        if TreeFiles.removedGoesToBin, (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil { return }
        try? fm.removeItem(at: url)
    }

    private static func tidyDocuments(in folder: URL, extension ext: String, keeping: URL) {
        for other in files(of: folder, extension: ext) where other.lastPathComponent != keeping.lastPathComponent { try? fm.removeItem(at: other) }
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
        let others = Set(((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0 != existing?.lastPathComponent }.map { $0.lowercased() })
        let name = uniqueName(wanted, among: Array(taken) + Array(others))
        let dest = parent.appendingPathComponent(name)
        if let e = existing { try move(e, to: dest) } else { try fm.createDirectory(at: dest, withIntermediateDirectories: true) }
        taken.insert(name)
        return dest
    }

    /// The same for a file: `parent/<wanted>.<ext>`, moving the file that holds the same thing.
    private static func settleFile(existing: URL?, wanted: String, extension ext: String, in parent: URL, taken: inout Set<String>) throws -> URL {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if let e = existing, e.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL {
            let have = e.deletingPathExtension().lastPathComponent
            if have == wanted || (taken.contains(wanted) && isVariant(have, of: wanted)) { taken.insert(have); return e }
        }
        let others = Set(files(of: parent, extension: ext).filter { $0 != existing }.map { $0.deletingPathExtension().lastPathComponent })
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

    /// A new, empty catalogue as the tree: the index, the Library, the Templates folder and the first collection.
    static func make(at root: URL, name: String, schema: SchemaTrial.SchemaFile = .fresh, now: Date = Date()) throws -> URL {
        let indexURL = root.appendingPathComponent(filesystemName(name) + "." + ColourFiles.catalogue)
        try write(Library(), schema: schema, index: indexURL, name: name, now: now)
        return indexURL
    }
}
