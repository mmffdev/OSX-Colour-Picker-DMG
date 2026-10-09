import Foundation

// ---------- The catalogue as version 2 laid it out, read only to bring it across ----------
//
// From 2026-10-09 until the catalogue file of version 3, every level of a catalogue was a folder
// with a file of its own describing it: "Clients/Clients.colcollection", "Clients/Acme/Acme.colworkgroup",
// "Library/Palettes/Palettes.colassets", "Templates/Agency Job.coltemplate", and the index
// "Rick 001.colcatalogue" at version 2. Nothing writes that layout any more. Migration reads it here,
// describes its folders as a version 3 catalogue file so the writer can find them, and writes version 3.

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

/// What reading a version 2 tree gives back.
struct LegacyLoaded {
    var library: Library
    var schema: SchemaTrial.SchemaFile
    var index: CatalogueIndex
    var notes: [String]
}

enum LegacyTree {
    static let collection = "colcollection", workGroup = "colworkgroup", assets = "colassets", template = "coltemplate"
    private static func decoder() -> JSONDecoder { ColourFiles.decoder() }
    private static let fm = FileManager.default
    private static func names(in dir: URL) -> [String] { CatalogueTree.names(in: dir) }
    private static func subfolders(of dir: URL) -> [URL] { CatalogueTree.subfolders(of: dir) }
    private static func files(of dir: URL, extension ext: String) -> [URL] { CatalogueTree.files(of: dir, extension: ext) }
    private static func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? { CatalogueTree.read(type, at: url) }
    private static func document(in folder: URL, extension ext: String) -> URL? { CatalogueTree.document(in: folder, extension: ext) }

    /// The version 2 index in a folder, if that is what is there.
    static func index(in root: URL) -> CatalogueIndex? {
        guard let url = CatalogueFiles.legacyIndex(in: root), let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> CatalogueIndex? {
        guard let doc = try? decoder().decode(CatalogueIndex.self, from: data), doc.format == "colour-catalogue", doc.version == 2 else { return nil }
        return doc
    }

    /// Reads the whole version 2 tree.
    /// Reads the whole tree. `palettes` false reads only the shape, for the schema alone.
    static func read(root: URL, palettes wantPalettes: Bool = true) throws -> LegacyLoaded {
        guard let indexURL = CatalogueFiles.legacyIndex(in: root) else { throw TreeError.noIndex(root) }
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
                for url in files(of: dir, extension: ColourFiles.legacyPalette) {
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
                for sub in subfolders(of: dir) where document(in: sub, extension: LegacyTree.workGroup) == nil { walk(sub) }
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
                guard let file = document(in: sub, extension: LegacyTree.workGroup) else { continue }
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
            guard let file = document(in: sub, extension: LegacyTree.collection) else { continue }
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

        // The Library: the pool of what belongs to no job.
        let library = root.appendingPathComponent(TreeFiles.library)
        if wantPalettes {
            for pool in [TreeFiles.palettesPool, TreeFiles.typographyPool] {
                let dir = library.appendingPathComponent(pool)
                let assets = read(AssetsDocument.self, at: dir.appendingPathComponent(pool + "." + LegacyTree.assets))
                swatches += palettes(under: dir, member: nil, known: assets?.items ?? [])
            }
            if let loose = read(AssetsDocument.self, at: library.appendingPathComponent(TreeFiles.swatchesPool).appendingPathComponent(TreeFiles.swatchesPool + "." + LegacyTree.assets)) {
                takeColours(loose.colours ?? [])
            }
        }
        if let profiles = read(AssetsDocument.self, at: library.appendingPathComponent(TreeFiles.profilesPool).appendingPathComponent(TreeFiles.profilesPool + "." + LegacyTree.assets)) {
            lib.colourProfiles = profiles.profiles ?? []
        }

        // Templates.
        var templates: [SchemaTemplate] = []
        let templatesDir = root.appendingPathComponent(TreeFiles.templates)
        var foundTemplates: [TemplateDocument] = []
        for url in files(of: templatesDir, extension: LegacyTree.template) {
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
        _ = dirty
        return LegacyLoaded(library: lib, schema: schema, index: index, notes: notes)
    }

    /// The version 2 tree described as a version 3 catalogue file: every collection, level between and member where its
    /// folder is, with the folder of every group, so the writer moves what it must and leaves the rest where it lies. It
    /// lists no assets, so nothing is taken away for being unlisted.
    static func describe(root: URL, loaded: LegacyLoaded) -> CatalogueFile {
        func member(_ doc: WorkGroupDocument, folder: URL) -> MemberEntry {
            MemberEntry(id: doc.id, name: doc.name, folder: folder.lastPathComponent, createdAt: doc.project?.createdAt ?? doc.changedAt,
                        schema: nil, buckets: doc.buckets ?? [:], information: nil, assets: [], turned: nil)
        }
        var collections: [CollectionEntry] = []
        for sub in subfolders(of: root) where !TreeFiles.reserved.contains(sub.lastPathComponent) {
            guard let file = document(in: sub, extension: collection), let doc = read(CollectionDocument.self, at: file), doc.format == "colour-collection" else { continue }
            var entry = CollectionEntry(id: doc.id, name: doc.name, about: doc.about, folder: sub.lastPathComponent, groupName: doc.groupName,
                                        template: doc.template, templateID: doc.templateID, groups: [], members: [])
            for inner in subfolders(of: sub) {
                guard let wf = document(in: inner, extension: workGroup), let wg = read(WorkGroupDocument.self, at: wf) else { continue }
                if wg.kind == .group {
                    var g = GroupEntry(id: wg.id, name: wg.name, folder: inner.lastPathComponent, members: [])
                    for deeper in subfolders(of: inner) {
                        if let mf = document(in: deeper, extension: workGroup), let m = read(WorkGroupDocument.self, at: mf), m.kind == .member { g.members.append(member(m, folder: deeper)) }
                    }
                    entry.groups.append(g)
                } else {
                    entry.members.append(member(wg, folder: inner))
                }
            }
            collections.append(entry)
        }
        let i = loaded.index
        return CatalogueFile(id: i.id, name: i.name, about: i.about, createdAt: i.createdAt, changedAt: i.changedAt, library: i.library, activePalette: nil,
                             colours: [], tags: [], deleted: [], templates: [], collections: collections, libraryAssets: [], swatches: nil, profiles: nil)
    }
}
