import Foundation

// ---------- The catalogue as earlier versions kept it ----------
//
// Until 2026-10-09 a catalogue was an index listing its members, each a folder of its own files,
// with Unfiled for what belonged to no member. The reader here is kept for one purpose: bringing
// such a catalogue across into the tree (see Migration.swift and CatalogueTree.swift). Nothing is
// written in this shape any more.

/// One project as the index lists it: enough to name it and find it, no more.
struct ProjectRef: Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    /// The project's own folder, when it has one; nil puts it under the Projects folder.
    var folder: String? = nil
}

/// A tag by what tells it apart: its name and the project it belongs to.
struct TagKey: Codable, Equatable, Hashable {
    var name: String
    var project: UUID?
}

/// "Client Name.colcatalogue".
struct CatalogueDocument: Codable, Equatable {
    var format = "colour-catalogue"
    var version = 1
    var generator = ColourFiles.generator
    /// The library's own version number.
    var library: Int
    var projects: [ProjectRef]
    /// The order palettes, colours and tags are held in, so a catalogue reads back exactly as it was.
    var palettes: [UUID]
    var colours: [String]
    var tags: [TagKey]
    /// The palette new picks go into.
    var activePalette: UUID? = nil
    /// What was deleted and when, so that a sync does not bring it back.
    var deleted: [Tombstone]
    /// The user's notes on the catalogue, kept in its own file so they travel with it.
    var about: String? = nil
}

/// "Brand.coldata": what a project holds besides its palettes. For Unfiled it is the home of
/// everything that belongs to no project.
struct DataDocument: Codable, Equatable {
    var format = "colour-data"
    var version = 1
    var generator = ColourFiles.generator
    /// The project it belongs to; nil for Unfiled.
    var project: UUID?
    /// Colours kept here because no palette file holds them.
    var colours: [Colour] = []
    /// The project's own tags, and with them any global tag it wears, so it can travel.
    var tags: [TagInfo] = []
    var profiles: [ColourProfile] = []
}

enum CatalogueFiles {
    static let unfiled = "Unfiled"

    /// What could not be read when a catalogue was loaded.
    struct Loaded {
        var library: Library
        /// Projects the index lists whose files could not be reached.
        var unavailable: Set<UUID>
    }

    static func unfiledFolder(beside index: URL) -> URL { index.deletingLastPathComponent().appendingPathComponent(unfiled) }

    /// The catalogue's notes, from its index.
    static func about(index: URL) -> String {
        (try? Data(contentsOf: index)).flatMap { CatalogueTree.decode($0) }?.about ?? ""
    }

    /// Writes the catalogue's notes into its index, touching nothing else in it.
    static func setAbout(_ text: String, index: URL) throws {
        guard let data = try? Data(contentsOf: index), var doc = CatalogueTree.decode(data) else { return }
        doc.about = text.isEmpty ? nil : text
        try ColourFiles.encoder().encode(doc).write(to: index, options: .atomic)
    }

    /// Loads a catalogue: the index, then every project it lists, then Unfiled, joined into one library.
    static func read(index: URL, master: URL?) throws -> Loaded {
        let d = ColourFiles.decoder()
        let doc = try d.decode(CatalogueDocument.self, from: Data(contentsOf: index))
        guard doc.format == "colour-catalogue" else { throw CocoaError(.fileReadCorruptFile) }
        var lib = Library()
        lib.version = doc.library
        lib.activeSwatchID = doc.activePalette
        lib.deleted = doc.deleted
        var unavailable = Set<UUID>()
        var swatches: [Swatch] = [], colours: [String: Colour] = [:], tags: [TagInfo] = []

        for ref in doc.projects {
            // Where the project should be; the index knows its name and its folder, which is all that takes.
            let stub = Project(id: ref.id, name: ref.name, createdAt: ref.createdAt, folder: ref.folder, fileKnown: true)
            let root = ProjectFiles.root(for: stub, library: index, master: master)
            guard let found = ProjectFiles.existingFile(in: root, name: ref.name), let whole = try? ProjectFiles.read(found), whole.project.id == ref.id else {
                lib.projects.append(stub)
                unavailable.insert(ref.id)
                continue
            }
            // Where the project is, is the catalogue's to say: the project's own file cannot know it has been moved.
            // A folder that is just the usual place under the master folder is kept as no folder at all.
            var project = whole.project
            let usual = ProjectFiles.keep(ProjectFiles.master(library: index, master: master).appendingPathComponent(filesystemName(ref.name)), beside: index)
            project.folder = ref.folder == usual ? nil : ref.folder
            lib.projects.append(project)
            swatches += whole.palettes
            for colour in whole.colours where colours[colour.hex] == nil { colours[colour.hex] = colour }
            tags += whole.tags.filter { $0.projectID == ref.id }
        }

        let folder = unfiledFolder(beside: index)
        let dataFiles = [folder.appendingPathComponent(ProjectFiles.configFolder), folder].map { $0.appendingPathComponent("\(unfiled).\(ColourFiles.data)") }
        if let found = dataFiles.lazy.compactMap({ try? Data(contentsOf: $0) }).first, let data = try? d.decode(DataDocument.self, from: found) {
            for colour in data.colours where colours[colour.hex] == nil { colours[colour.hex] = colour }
            tags += data.tags
            lib.colourProfiles = data.profiles
        }
        let looseDir = folder.appendingPathComponent(ProjectFiles.palettesFolder)
        let loose = ProjectFiles.palettes(in: looseDir, channels: [folder.appendingPathComponent(ProjectFiles.channelsFolder), looseDir], project: nil)
        swatches += loose.palettes
        for colour in loose.colours where colours[colour.hex] == nil { colours[colour.hex] = colour }

        // Back into the order they were held in; anything the index does not list goes after.
        lib.swatches = ordered(swatches, by: doc.palettes) { $0.id }
        lib.colours = ordered(Array(colours.values), by: doc.colours) { $0.hex }
        lib.tagInfo = ordered(tags, by: doc.tags) { TagKey(name: $0.name, project: $0.projectID) }
        return Loaded(library: lib, unavailable: unavailable)
    }

    /// `items` in the order of `keys`; whatever has no place in `keys` follows, in the order given.
    static func ordered<Item, Key: Hashable>(_ items: [Item], by keys: [Key], key: (Item) -> Key) -> [Item] {
        var place: [Key: Int] = [:]
        for (at, k) in keys.enumerated() where place[k] == nil { place[k] = at }
        let known = items.filter { place[key($0)] != nil }.sorted { place[key($0)]! < place[key($1)]! }
        return known + items.filter { place[key($0)] == nil }
    }

    /// The catalogue's structure file in a folder, ".colcat", if there is one.
    static func index(in directory: URL) -> URL? { file(in: directory, extension: ColourFiles.catalogue) }
    /// An earlier version's index, ".colcatalogue", if there is one: read only to bring it across.
    static func legacyIndex(in directory: URL) -> URL? { file(in: directory, extension: ColourFiles.legacyCatalogue) }
    /// Either: whatever says a catalogue lives in this folder.
    static func anyIndex(in directory: URL) -> URL? { index(in: directory) ?? legacyIndex(in: directory) }
    private static func file(in directory: URL, extension ext: String) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { ($0 as NSString).pathExtension.lowercased() == ext && !$0.hasPrefix(".") }
            .sorted().first.map { directory.appendingPathComponent($0) }
    }
}
