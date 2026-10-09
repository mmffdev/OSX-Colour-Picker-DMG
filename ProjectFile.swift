import Foundation

// ---------- The files of the app, and a member as earlier versions kept one ----------
//
// Every file has an extension of our own that says what it is, and every one is plain JSON that
// any text editor opens: it is the user's own work, and nothing is hidden. Since 2026-10-09 a
// member is a folder in the catalogue's tree (CatalogueTree.swift); the shape below is what
// earlier versions wrote, read here only to bring such a catalogue across.
//
//     Client A/Space/Client A.colspace         the member: its details and the order of its palettes
//     Client A/Config/Client A.coldata         its tags, and the tags and profiles it carries with it
//     Client A/History/Client A.colhistory     what happened to it, when project history is on
//     Client A/Palettes/Brand.colpalette       one palette and the colours it uses
//     Client A/Channels/Brand.colprint         that palette's settings for one purpose
//     Client A/Swatches/                       single colours, kept as files
//
// A file's name is a tidied form of the real name, which is kept inside the file along with the
// id of what it belongs to, so a rename or a stray copy never attaches it to the wrong thing.
// Earlier versions kept everything in a Config folder, first as one "Client A.config" and then
// as the files above nested inside it; both are still read, and tidied into this shape when saved.

/// What every file of ours says about itself.
enum ColourFiles {
    static let generator = Brand.name
    /// A space is one member of a collection, whatever the user calls it: a project, a client, a brand.
    static let project = "colspace", swatch = "colswatch", data = "coldata"
    /// Since version 3 every kind of file has an extension of its own, ".col" and three letters, that says which place in the app it opens.
    static let catalogue = "colcat", history = "colhis", palette = "colpal", typography = "coltyp", information = "colinf"
    static let swatches = "colswa", profiles = "colprf", share = "colshr"
    /// The extensions earlier versions gave the same files, read only to bring them across.
    static let legacyCatalogue = "colcatalogue", legacyHistory = "colhistory", legacyPalette = "colpalette", legacyShare = "colshare"
    /// The names earlier versions gave the same file: ".colproject", and before that one "config" file.
    static let earlierProject = "colproject", legacyProject = "config"
    /// Every extension found in a project's Palettes folder.
    static var paletteFolder: [String] { [legacyPalette] + Purpose.allCases.map { $0.fileExtension } }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Milliseconds since 1970: whole numbers, so a file reads back exactly as written.
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}

/// "Client A.colspace": the member itself. Its palettes are files of their own; this lists
/// them in order, and the colours in the order the library holds them.
struct ProjectDocument: Codable, Equatable {
    var format = "colour-space"
    /// The format tags this file has carried: today's, and the one earlier versions wrote.
    static let formats = ["colour-space", "colour-project"]
    var version = 2
    var generator = ColourFiles.generator
    var project: Project
    var palettes: [UUID]
    var colours: [String]
    /// The order its tags are held in; the tags themselves, and its profiles, are in its .coldata.
    var tagOrder: [TagKey]? = nil
    /// The purpose each of its palettes is turned to, for those that have ever been turned to one.
    var turned: [TurnedPalette]? = nil
    /// Written here by an earlier version, before .coldata held them. Still read.
    var tags: [TagInfo]? = nil
    var profiles: [ColourProfile]? = nil
}

/// The purpose one palette is turned to, as its project's file keeps it; no purpose is the palette as it is.
struct TurnedPalette: Codable, Equatable {
    var palette: UUID
    var purpose: Purpose? = nil
    var changedAt: Date
}

/// "Brand.colpalette": one palette and the library's record of each colour it uses.
struct PaletteDocument: Codable, Equatable {
    var format = "colour-palette"
    var version = 1
    var generator = ColourFiles.generator
    /// The project it sits in; nil for a palette on its own.
    var project: UUID?
    var palette: Swatch
    var colours: [Colour]
    /// The name the file was written under, without its extension: a file found under another name was renamed in Finder.
    var file: String? = nil
    /// The catalogue it was written in.
    var catalogue: UUID? = nil
}

/// "Brand.colprint": a palette's settings for one purpose.
struct PurposeDocument: Codable, Equatable {
    var format = "colour-purpose"
    var version = 1
    var generator = ColourFiles.generator
    /// The palette it belongs to, by id and, for whoever reads the file, by name.
    var palette: UUID
    var paletteName: String
    var settings: PurposeConfig
}

/// "Client A.colhistory": the steps that touched a project, oldest first.
struct HistoryDocument: Codable, Equatable {
    var format = "colour-history"
    var version = 1
    var generator = ColourFiles.generator
    var project: UUID
    var steps: [ProjectStep]
}

/// "Electric Violet.colswatch": one colour on its own, whole, the way it travels from one person
/// to another: how it was given, its master, and the name and notes it had in its palette.
struct SwatchDocument: Codable, Equatable {
    var format = "colour-swatch"
    var version = 1
    var generator = ColourFiles.generator
    var name: String
    var entry: SwatchEntry
    var colour: Colour

    /// A palette's colour as a file of its own; nil when the palette does not hold it.
    init?(_ key: String, in palette: UUID, of lib: Library) {
        guard let entry = lib.swatch(palette)?.entries.first(where: { $0.hex == key }),
              let colour = lib.colours.first(where: { $0.hex == key }) else { return nil }
        name = lib.name(of: key, in: palette)
        self.entry = entry
        self.colour = colour
    }

    static func fileName(_ name: String) -> String { filesystemName(name) + "." + ColourFiles.swatch }
    func data() throws -> Data { try ColourFiles.encoder().encode(self) }
    static func read(_ data: Data) throws -> SwatchDocument {
        let doc = try ColourFiles.decoder().decode(SwatchDocument.self, from: data)
        guard doc.format == "colour-swatch" else { throw CocoaError(.fileReadCorruptFile) }
        return doc
    }
}

/// A whole project in one piece: what the files of a project add up to, and what the one file of
/// an earlier version held.
struct ProjectFile: Codable, Equatable {
    var format = "mmffdev-colour-project"
    var version = 1
    var generator = Brand.name
    var project: Project
    /// The project's palettes, colours and typography alike, in sidebar order.
    var palettes: [Swatch]
    /// The library's record of each colour the palettes use: when it was picked and its tags.
    var colours: [Colour]
    /// Tags the project owns, and any global tag its palettes or colours wear.
    var tags: [TagInfo]
    /// The steps that touched this project, oldest first, when project history is on.
    var history: [ProjectStep] = []
    /// The colour profiles the project and its palettes work to, so the channels travel with it.
    var profiles: [ColourProfile]? = nil

    static func read(_ data: Data) throws -> ProjectFile { try ColourFiles.decoder().decode(ProjectFile.self, from: data) }

}

/// One step as a project file records it: what and when, not the whole library.
struct ProjectStep: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
}

/// Where earlier versions put a member's files: "Cookra/Space/Cookra.colspace", "Cookra/Palettes/…",
/// under a Projects folder beside the index or in a folder of the member's own.
enum ProjectFiles {
    static let projectFolder = "Space", configFolder = "Config", historyFolder = "History"
    /// What the Space folder was called before.
    static let earlierProjectFolder = "Project"
    static let palettesFolder = "Palettes", channelsFolder = "Channels", swatchesFolder = "Swatches"
    /// Every folder a project has, made when it is written so the shape is there to see.
    static let folders = [projectFolder, configFolder, historyFolder, palettesFolder, channelsFolder, swatchesFolder]
    static let fileExtension = ColourFiles.project
    /// A project's file under either name: today's, or the one an earlier version wrote.
    static func isProjectFile(_ url: URL) -> Bool { [ColourFiles.project, ColourFiles.earlierProject, ColourFiles.legacyProject].contains(url.pathExtension.lowercased()) }
    /// The one file the first version wrote.
    static func legacyURL(in root: URL, name: String) -> URL {
        root.appendingPathComponent(configFolder).appendingPathComponent(filesystemName(name) + "." + ColourFiles.legacyProject)
    }
    /// The project's file where an earlier version put it, nested in Config.
    static func nestedURL(in root: URL, name: String) -> URL {
        root.appendingPathComponent(configFolder).appendingPathComponent(filesystemName(name) + "." + fileExtension)
    }
    /// The project's file wherever it is: where it belongs, or where an earlier version left it.
    static func existingFile(in root: URL, name: String) -> URL? {
        let base = filesystemName(name)
        let earlier = [root.appendingPathComponent(earlierProjectFolder).appendingPathComponent(base + "." + ColourFiles.earlierProject),
                       root.appendingPathComponent(configFolder).appendingPathComponent(base + "." + ColourFiles.earlierProject)]
        return ([configURL(in: root, name: name), nestedURL(in: root, name: name)] + earlier + [legacyURL(in: root, name: name)])
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The folder members were kept under when the catalogue sat at the app's home, as earlier versions let the user choose it.
    static var folder: URL? { preferences.string(forKey: "projectsFolder").map { URL(fileURLWithPath: $0) } }

    static func master(library: URL, master: URL?) -> URL {
        master ?? library.deletingLastPathComponent().appendingPathComponent("Projects")
    }

    /// The project's folder: its own, or one named for it under the master folder. A folder kept
    /// as a relative path is inside the catalogue's folder, so it moves with the catalogue.
    static func root(for project: Project, library: URL, master: URL?) -> URL {
        if let own = project.folder { return resolve(own, beside: library) }
        return self.master(library: library, master: master).appendingPathComponent(filesystemName(project.name))
    }

    /// A folder as the catalogue keeps it: relative when it is inside the catalogue's folder, absolute otherwise.
    static func keep(_ folder: URL, beside library: URL) -> String {
        let home = library.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = folder.standardizedFileURL.path
        return path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path
    }

    static func resolve(_ kept: String, beside library: URL) -> URL {
        kept.hasPrefix("/") ? URL(fileURLWithPath: kept) : library.deletingLastPathComponent().appendingPathComponent(kept)
    }

    /// Where a project's own file belongs: "<root>/Space/<name>.colspace".
    static func configURL(in root: URL, name: String) -> URL {
        root.appendingPathComponent(projectFolder).appendingPathComponent(filesystemName(name) + "." + fileExtension)
    }

    /// The palettes in a Palettes folder that belong to `project`, and the colours they hold, each
    /// palette with the purposes found for it in any of the `channels` folders.
    static func palettes(in folder: URL, channels: [URL], project: UUID?) -> (palettes: [Swatch], colours: [Colour]) {
        let d = ColourFiles.decoder(), fm = FileManager.default
        var palettes: [Swatch] = [], colours: [Colour] = [], seen = Set<String>(), settings: [UUID: [PurposeConfig]] = [:]
        func files(_ dir: URL) -> [URL] { ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
        for url in files(folder) where url.pathExtension.lowercased() == ColourFiles.legacyPalette {
            guard let found = try? Data(contentsOf: url), let p = try? d.decode(PaletteDocument.self, from: found), p.project == project else { continue }
            palettes.append(p.palette)
            for colour in p.colours where seen.insert(colour.hex).inserted { colours.append(colour) }
        }
        for url in channels.flatMap(files) where Purpose.of(fileExtension: url.pathExtension) != nil {
            guard let found = try? Data(contentsOf: url), let s = try? d.decode(PurposeDocument.self, from: found) else { continue }
            if settings[s.palette]?.contains(where: { $0.purpose == s.settings.purpose }) != true { settings[s.palette, default: []].append(s.settings) }
        }
        for at in palettes.indices {
            let all = (palettes[at].purposes ?? []) + (settings[palettes[at].id] ?? [])
            palettes[at].purposes = all.isEmpty ? nil : Purpose.allCases.compactMap { purpose in all.first { $0.purpose == purpose } }
        }
        return (palettes, colours)
    }

    /// Reads a project back whole: from its file and the palette, purpose, data and history files
    /// in the folders beside it, or from how an earlier version kept them.
    static func read(_ file: URL) throws -> ProjectFile {
        let data = try Data(contentsOf: file), d = ColourFiles.decoder()
        guard let doc = try? d.decode(ProjectDocument.self, from: data), ProjectDocument.formats.contains(doc.format) else { return try ProjectFile.read(data) }
        let home = file.deletingLastPathComponent(), base = file.deletingPathExtension().lastPathComponent
        // In its Project folder, with the rest in folders beside that; or, as an earlier version
        // had it, in Config with everything nested there.
        let flat = [projectFolder, earlierProjectFolder].contains(home.lastPathComponent), root = home.deletingLastPathComponent()
        let paletteDir = flat ? root.appendingPathComponent(palettesFolder) : home.appendingPathComponent(palettesFolder)
        let channelDirs = flat ? [root.appendingPathComponent(channelsFolder), paletteDir] : [paletteDir]
        let dataFile = (flat ? root.appendingPathComponent(configFolder) : home).appendingPathComponent(base + "." + ColourFiles.data)
        let historyFiles = flat ? [root.appendingPathComponent(historyFolder), root.appendingPathComponent(configFolder)] : [home]
        let held = palettes(in: paletteDir, channels: channelDirs, project: doc.project.id)
        var tags = doc.tags ?? [], profiles = doc.profiles
        if let found = try? Data(contentsOf: dataFile), let own = try? d.decode(DataDocument.self, from: found), own.project == doc.project.id {
            tags = own.tags
            profiles = own.profiles.isEmpty ? nil : own.profiles
        }
        if let order = doc.tagOrder { tags = CatalogueFiles.ordered(tags, by: order) { TagKey(name: $0.name, project: $0.projectID) } }
        var whole = try ProjectFile.read(ColourFiles.encoder().encode(Whole(project: doc.project, palettes: [], colours: [], tags: tags, profiles: profiles)))
        whole.palettes = CatalogueFiles.ordered(held.palettes, by: doc.palettes) { $0.id }.filter { doc.palettes.contains($0.id) }
        for turned in doc.turned ?? [] {
            guard let at = whole.palettes.firstIndex(where: { $0.id == turned.palette }) else { continue }
            whole.palettes[at].purpose = turned.purpose
            whole.palettes[at].purposeChangedAt = turned.changedAt
        }
        whole.colours = CatalogueFiles.ordered(held.colours, by: doc.colours) { $0.hex }
        for folder in historyFiles {
            if let found = try? Data(contentsOf: folder.appendingPathComponent(base + "." + ColourFiles.legacyHistory)),
               let h = try? d.decode(HistoryDocument.self, from: found), h.project == doc.project.id { whole.history = h.steps; break }
        }
        return whole
    }

    /// The bare bones of a project in one piece, for putting one together from its files.
    private struct Whole: Codable {
        var format = "mmffdev-colour-project"
        var version = 1
        var generator = ColourFiles.generator
        var project: Project
        var palettes: [Swatch]
        var colours: [Colour]
        var tags: [TagInfo]
        var history: [ProjectStep] = []
        var profiles: [ColourProfile]? = nil
    }

    /// The project a file belongs to, without reading more than needed.
    static func projectID(of file: URL) -> UUID? {
        struct Head: Decodable { struct P: Decodable { let id: UUID }; let project: P }
        return (try? Data(contentsOf: file)).flatMap { try? ColourFiles.decoder().decode(Head.self, from: $0) }?.project.id
    }

    /// The folders inside a project's folder where its own file may be: where it belongs, and where an earlier version kept it.
    private static let homes = [projectFolder, earlierProjectFolder, configFolder]

    /// A project folder under `parent` that holds this project's file, by id.
    private static func findFolder(holding id: UUID, under parent: URL, fm: FileManager) -> URL? {
        for folder in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            for home in homes {
                for file in (try? fm.contentsOfDirectory(at: folder.appendingPathComponent(home), includingPropertiesForKeys: nil)) ?? []
                    where isProjectFile(file) && projectID(of: file) == id { return folder }
            }
        }
        return nil
    }
}
