import Foundation

// ---------- The catalogue on disk ----------
//
// A catalogue is the index a user opens: which projects there are, and the few things that
// belong to the catalogue as a whole. It is not a second copy of anything. The work itself is in
// the projects, each a folder of its own files, and each project is the only home of what is in it.
//
//     Client Name.colcatalogue                 the index: the projects, the order of things, what was deleted
//     Unfiled/Unfiled.coldata                  what belongs to no project: global tags, the house's
//                                              profiles, and colours no palette uses
//     Unfiled/Palettes/Loose.colpalette        palettes that sit in no project
//
//     <Projects>/Brand/Config/Brand.colproject the project
//     <Projects>/Brand/Config/Brand.coldata    its own tags, and the tags and profiles it carries with it
//     <Projects>/Brand/Config/Brand.colhistory
//     <Projects>/Brand/Config/Palettes/…       its palettes, each with the colours it uses and its purposes
//
// In memory the app still works on one Library. Saving splits it into these files; loading joins
// them. A project whose files cannot be reached (a drive unplugged, a folder moved) stays in the
// index and is shown as unavailable; it is never taken to have been deleted, and never written
// over, so it comes back whole when its files do.

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

    /// Saves a library as a catalogue: each project into its own files, what belongs to no
    /// project into Unfiled, and the index last, so the index never names what is not yet there.
    /// `remaking` is for turning an earlier one-file catalogue into these files: every project is
    /// written, including any whose folder had gone, because that one file was the only copy.
    static func write(_ lib: Library, index: URL, master: URL?, remaking: Bool = false, written: inout [UUID: Data]) throws {
        let fm = FileManager.default, e = ColourFiles.encoder()
        _ = try ProjectFiles.write(lib, library: index, master: master, touchHistory: false, remaking: remaking, written: &written)

        let real = Set(lib.projects.map { $0.id })
        let loose = lib.swatches.filter { $0.projectID.map { !real.contains($0) } ?? true }
        let used = Set(lib.swatches.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let data = DataDocument(project: nil, colours: lib.colours.filter { !used.contains($0.hex) },
                                tags: lib.tagInfo.filter { $0.projectID.map { !real.contains($0) } ?? true }, profiles: lib.colourProfiles)
        let folder = unfiledFolder(beside: index), palettes = folder.appendingPathComponent(ProjectFiles.palettesFolder)
        try fm.createDirectory(at: palettes, withIntermediateDirectories: true)
        var documents: [(path: String, data: Data)] = [("\(unfiled).\(ColourFiles.data)", try e.encode(data))]
        documents += try ProjectFile.paletteDocuments(loose, colours: lib.colours, project: nil)
        try ProjectFiles.put(documents, in: folder)

        let doc = CatalogueDocument(library: lib.version,
                                    projects: lib.projects.map { ProjectRef(id: $0.id, name: $0.name, createdAt: $0.createdAt, folder: $0.folder) },
                                    palettes: lib.swatches.map { $0.id }, colours: lib.colours.map { $0.hex },
                                    tags: lib.tagInfo.map { TagKey(name: $0.name, project: $0.projectID) },
                                    activePalette: lib.activeSwatchID, deleted: lib.deleted)
        // Always written, changed or not: its date is how another copy of the app sees there is something new.
        do { try e.encode(doc).write(to: index, options: .atomic) } catch { throw StoreError.saveFailed(index, error) }
    }

    /// Loads a catalogue: the index, then every project it lists, then Unfiled, joined into one library.
    static func read(index: URL, master: URL?) throws -> Loaded {
        let fm = FileManager.default, d = ColourFiles.decoder()
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
            let file = [ProjectFiles.configURL(in: root, name: ref.name), ProjectFiles.legacyURL(in: root, name: ref.name)].first { fm.fileExists(atPath: $0.path) }
            guard let found = file, let whole = try? ProjectFiles.read(found), whole.project.id == ref.id else {
                lib.projects.append(stub)
                unavailable.insert(ref.id)
                continue
            }
            lib.projects.append(whole.project)
            swatches += whole.palettes
            for colour in whole.colours where colours[colour.hex] == nil { colours[colour.hex] = colour }
            tags += whole.tags.filter { $0.projectID == ref.id }
        }

        let folder = unfiledFolder(beside: index)
        if let found = try? Data(contentsOf: folder.appendingPathComponent("\(unfiled).\(ColourFiles.data)")), let data = try? d.decode(DataDocument.self, from: found) {
            for colour in data.colours where colours[colour.hex] == nil { colours[colour.hex] = colour }
            tags += data.tags
            lib.colourProfiles = data.profiles
        }
        let loose = ProjectFiles.palettes(in: folder.appendingPathComponent(ProjectFiles.palettesFolder), project: nil)
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

    /// The catalogue file in a folder, if there is one.
    static func index(in directory: URL) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { ($0 as NSString).pathExtension.lowercased() == ColourFiles.catalogue && !$0.hasPrefix(".") }
            .sorted().first.map { directory.appendingPathComponent($0) }
    }
}
