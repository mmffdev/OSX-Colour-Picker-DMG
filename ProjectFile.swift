import Foundation

// ---------- Project files ----------
//
// The library file is the master of everything. Each project also gets files of its own, kept
// current by the app: the whole project, so it can be handed over, moved, and later imported.
// They carry only metadata (names, colours, order, pairings, tags, details), so they stay small.
//
// On disk a project is a folder named for it, with a Config folder inside. Every file there has
// an extension of our own that says what it is, and every one is plain JSON that any text editor
// opens: it is the user's own work, and nothing is hidden.
//
//     Client A/Config/Client A.colproject            the project: its details, tags and profiles
//     Client A/Config/Client A.colhistory            what happened to it, when project history is on
//     Client A/Config/Palettes/Brand.colpalette      one palette and the colours it uses
//     Client A/Config/Palettes/Brand.colprint        that palette's settings for one purpose
//
// A file's name is a tidied form of the real name, which is kept inside the file along with the
// id of what it belongs to, so a rename or a stray copy never attaches it to the wrong thing.
// Earlier versions wrote everything into one "Client A.config"; that is still read.

/// What every file of ours says about itself.
enum ColourFiles {
    static let generator = "MMFFDev Colour 3"
    static let project = "colproject", palette = "colpalette", swatch = "colswatch", history = "colhistory"
    static let catalogue = "colcatalogue", data = "coldata"
    /// The one file an earlier version wrote.
    static let legacyProject = "config"
    /// Every extension found in a project's Palettes folder.
    static var paletteFolder: [String] { [palette] + Purpose.allCases.map { $0.fileExtension } }

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

/// "Client A.colproject": the project itself. Its palettes are files of their own; this lists
/// them in order, and the colours in the order the library holds them.
struct ProjectDocument: Codable, Equatable {
    var format = "colour-project"
    var version = 2
    var generator = ColourFiles.generator
    var project: Project
    var palettes: [UUID]
    var colours: [String]
    /// The order its tags are held in; the tags themselves, and its profiles, are in its .coldata.
    var tagOrder: [TagKey]? = nil
    /// Written here by an earlier version, before .coldata held them. Still read.
    var tags: [TagInfo]? = nil
    var profiles: [ColourProfile]? = nil
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
    var generator = "MMFFDev Colour 3"
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

    init(project: Project, in lib: Library, history steps: [HistoryStep] = []) {
        self.project = project
        history = steps.map { ProjectStep(id: $0.id, date: $0.date, title: $0.title) }
        palettes = lib.palettes(in: project.id)
        let hexes = Set(palettes.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        colours = lib.colours.filter { hexes.contains($0.hex) }
        let worn = Set(palettes.flatMap { $0.tagList } + colours.flatMap { $0.tags ?? [] })
        tags = lib.tagInfo.filter { $0.removed != true && ($0.projectID == project.id || worn.contains($0.name)) }
        let used = Set(([project.profile] + palettes.map { $0.profile }).compactMap { $0 })
        let carried = lib.colourProfiles.filter { used.contains($0.id) }
        profiles = carried.isEmpty ? nil : carried
    }

    /// The project in one piece. This is what tells whether anything has changed since it was last written.
    func data() throws -> Data { try ColourFiles.encoder().encode(self) }

    static func read(_ data: Data) throws -> ProjectFile { try ColourFiles.decoder().decode(ProjectFile.self, from: data) }

    /// The name each palette's files carry: its own, tidied, and told apart from another of the same name.
    var paletteFileNames: [UUID: String] {
        var taken: [String] = [], out: [UUID: String] = [:]
        for palette in palettes {
            let name = uniqueName(filesystemName(palette.name), among: taken)
            taken.append(name)
            out[palette.id] = name
        }
        return out
    }

    /// The project as the files it is kept in, each by its path under the Config folder.
    func documents() throws -> [(path: String, data: Data)] {
        let e = ColourFiles.encoder(), base = filesystemName(project.name), names = paletteFileNames
        var out: [(path: String, data: Data)] = []
        _ = names
        let doc = ProjectDocument(project: project, palettes: palettes.map { $0.id }, colours: colours.map { $0.hex },
                                  tagOrder: tags.map { TagKey(name: $0.name, project: $0.projectID) })
        out.append(("\(base).\(ColourFiles.project)", try e.encode(doc)))
        out.append(("\(base).\(ColourFiles.data)", try e.encode(DataDocument(project: project.id, tags: tags, profiles: profiles ?? []))))
        if !history.isEmpty {
            out.append(("\(base).\(ColourFiles.history)", try e.encode(HistoryDocument(project: project.id, steps: history))))
        }
        return out + (try ProjectFile.paletteDocuments(palettes, colours: colours, project: project.id))
    }

    /// Palettes as the files they are kept in: each with the colours it uses, and beside it a
    /// file for every purpose it serves.
    static func paletteDocuments(_ palettes: [Swatch], colours: [Colour], project: UUID?) throws -> [(path: String, data: Data)] {
        let e = ColourFiles.encoder()
        var out: [(path: String, data: Data)] = [], taken: [String] = []
        for palette in palettes {
            let name = uniqueName(filesystemName(palette.name), among: taken)
            taken.append(name)
            let keys = Set(palette.entries.map { $0.hex } + (palette.styles ?? []).flatMap { [$0.ink, $0.paper] })
            // A purpose the palette serves is a file of its own beside it, so it is not said twice.
            // One that was taken off stays here, marked, so that a sync does not bring it back.
            var plain = palette
            let off = (palette.purposes ?? []).filter { !$0.isLive }
            plain.purposes = off.isEmpty ? nil : off
            let file = PaletteDocument(project: project, palette: plain, colours: colours.filter { keys.contains($0.hex) })
            out.append(("\(ProjectFiles.palettesFolder)/\(name).\(ColourFiles.palette)", try e.encode(file)))
            for settings in palette.purposes ?? [] where settings.isLive {
                let side = PurposeDocument(palette: palette.id, paletteName: palette.name, settings: settings)
                out.append(("\(ProjectFiles.palettesFolder)/\(name).\(settings.purpose.fileExtension)", try e.encode(side)))
            }
        }
        return out
    }
}

/// One step as a project file records it: what and when, not the whole library.
struct ProjectStep: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
}

/// Where project files go. A project is a folder named for it, holding a Config folder with the
/// project's files inside: "Cookra/Config/Cookra.colproject". Exports will sit beside Config later.
///
///     <Projects folder>/<Project name>/Config/<Project name>.colproject
///
/// A project can have a folder of its own anywhere instead of sitting under the master folder.
enum ProjectFiles {
    static let configFolder = "Config"
    static let palettesFolder = "Palettes"
    static let fileExtension = ColourFiles.project
    /// A project's file under either name: today's, or the one an earlier version wrote.
    static func isProjectFile(_ url: URL) -> Bool { [ColourFiles.project, ColourFiles.legacyProject].contains(url.pathExtension.lowercased()) }
    static func legacyURL(in root: URL, name: String) -> URL {
        root.appendingPathComponent(configFolder).appendingPathComponent(filesystemName(name) + "." + ColourFiles.legacyProject)
    }

    /// The master folder; nil until chosen, when it defaults to "Projects" beside the library file.
    static var folder: URL? {
        get { preferences.string(forKey: "projectsFolder").map { URL(fileURLWithPath: $0) } }
        set { preferences.set(newValue?.path, forKey: "projectsFolder") }
    }

    static func master(library: URL, master: URL?) -> URL {
        master ?? library.deletingLastPathComponent().appendingPathComponent("Projects")
    }

    /// The project's folder: its own, or one named for it under the master folder.
    static func root(for project: Project, library: URL, master: URL?) -> URL {
        if let own = project.folder { return URL(fileURLWithPath: own) }
        return self.master(library: library, master: master).appendingPathComponent(filesystemName(project.name))
    }

    static func url(for project: Project, library: URL, master: URL?) -> URL {
        configURL(in: root(for: project, library: library, master: master), name: project.name)
    }

    static func configURL(in root: URL, name: String) -> URL {
        root.appendingPathComponent(configFolder).appendingPathComponent(filesystemName(name) + "." + fileExtension)
    }

    /// Why a project's file is not where it should be.
    enum Loss: Equatable {
        /// The file has existed and is gone; `expected` is where it was looked for.
        case missing(expected: URL)
        /// The folder it lives under (a drive, a cloud folder) is not there at all.
        case unavailable(folder: URL)
    }

    /// Projects whose file has existed and cannot be found now.
    static func lost(in lib: Library, library: URL, master: URL?) -> [UUID: Loss] {
        let fm = FileManager.default
        var out: [UUID: Loss] = [:]
        for p in lib.projects where p.fileKnown == true {
            let root = self.root(for: p, library: library, master: master)
            let above = p.folder == nil ? self.master(library: library, master: master) : root.deletingLastPathComponent()
            if !fm.fileExists(atPath: above.path) { out[p.id] = .unavailable(folder: above); continue }
            let file = configURL(in: root, name: p.name)
            if fm.fileExists(atPath: file.path) || fm.fileExists(atPath: legacyURL(in: root, name: p.name).path) { continue }
            // Renamed since the file was written: the folder and file still carry the old name.
            if let old = findFolder(holding: p.id, under: p.folder == nil ? above : root.deletingLastPathComponent(), fm: fm), old != root || p.folder != nil {
                continue
            }
            out[p.id] = .missing(expected: file)
        }
        return out
    }

    /// Writes every project's file, and only when its contents have changed since the last write.
    /// A project whose file has existed and is now gone is left alone: it is reported, not remade.
    /// Returns the files written and the projects written for the first time, which the caller marks.
    /// `touchHistory` false leaves each project's history file as it is: the catalogue is saved
    /// far more often than the history, which is written on its own.
    /// `remaking` writes every project, even one whose file has gone: for the one time a catalogue
    /// that held everything itself is turned into project files, when it is the only copy there is.
    static func write(_ lib: Library, library: URL, master: URL?, history: StepHistory? = nil, touchHistory: Bool = true, remaking: Bool = false,
                      written: inout [UUID: Data]) throws -> (files: [URL], firstTime: [UUID]) {
        let fm = FileManager.default
        let gone = remaking ? [:] : lost(in: lib, library: library, master: master)
        var files: [URL] = [], firstTime: [UUID] = []
        // Every project is written before anything is cleared away, so a palette moved from one
        // project to another is in its new home before it leaves its old one.
        var clearing: [(folder: URL, documents: [(path: String, data: Data)])] = []
        for p in lib.orderedProjects where gone[p.id] == nil {
            let whole = ProjectFile(project: p, in: lib, history: touchHistory ? history?.steps(in: p.id) ?? [] : [])
            let data = try whole.data()
            if written[p.id] == data { continue }
            var root = self.root(for: p, library: library, master: master)
            // A project renamed since its file was written: carry the folder over to the new name.
            if p.folder == nil, !fm.fileExists(atPath: root.path),
               let old = findFolder(holding: p.id, under: self.master(library: library, master: master), fm: fm), old != root {
                try fm.moveItem(at: old, to: root)
            }
            root = self.root(for: p, library: library, master: master)
            let config = root.appendingPathComponent(configFolder)
            try fm.createDirectory(at: config, withIntermediateDirectories: true)
            // The file carries the project's name; one left under an earlier name goes.
            let file = configURL(in: root, name: p.name)
            for other in (try? fm.contentsOfDirectory(at: config, includingPropertiesForKeys: nil)) ?? []
                where other != file && isProjectFile(other) && projectID(of: other) == p.id {
                try? fm.removeItem(at: other)
            }
            // Each file is written only when what it holds has changed, and whatever is left in the
            // folder from a palette, a purpose or a history that is no longer there goes.
            let documents = try whole.documents()
            try put(documents, in: config, clearing: false)
            clearing.append((config, documents))
            // The one file an earlier version wrote, under this name, has been replaced.
            try? fm.removeItem(at: legacyURL(in: root, name: p.name))
            written[p.id] = data
            files.append(file)
            if p.fileKnown != true { firstTime.append(p.id) }
        }
        for item in clearing { clear(item.folder, keeping: item.documents, history: touchHistory) }
        return (files, firstTime)
    }

    /// Writes files into a folder, each only when what it holds has changed, and then clears away
    /// whatever is left there from a palette or a purpose that is gone.
    static func put(_ documents: [(path: String, data: Data)], in folder: URL, clearing: Bool = true) throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(palettesFolder), withIntermediateDirectories: true)
        for document in documents {
            let at = folder.appendingPathComponent(document.path)
            if (try? Data(contentsOf: at)) != document.data { try document.data.write(to: at, options: .atomic) }
        }
        if clearing { clear(folder, keeping: documents, history: false) }
    }

    private static func clear(_ folder: URL, keeping documents: [(path: String, data: Data)], history: Bool) {
        let fm = FileManager.default
        let kept = Set(documents.map { folder.appendingPathComponent($0.path).standardizedFileURL.path })
        for stale in (try? fm.contentsOfDirectory(at: folder.appendingPathComponent(palettesFolder), includingPropertiesForKeys: nil)) ?? []
            where ColourFiles.paletteFolder.contains(stale.pathExtension.lowercased()) && !kept.contains(stale.standardizedFileURL.path) {
            try? fm.removeItem(at: stale)
        }
        guard history else { return }
        for stale in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where stale.pathExtension.lowercased() == ColourFiles.history && !kept.contains(stale.standardizedFileURL.path) {
            try? fm.removeItem(at: stale)
        }
    }

    /// The palettes in a Palettes folder that belong to `project`, each with its purposes, and the colours they hold.
    static func palettes(in folder: URL, project: UUID?) -> (palettes: [Swatch], colours: [Colour]) {
        let d = ColourFiles.decoder()
        var palettes: [Swatch] = [], colours: [Colour] = [], seen = Set<String>(), settings: [UUID: [PurposeConfig]] = [:]
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files {
            guard let found = try? Data(contentsOf: url) else { continue }
            if url.pathExtension.lowercased() == ColourFiles.palette, let p = try? d.decode(PaletteDocument.self, from: found), p.project == project {
                palettes.append(p.palette)
                for colour in p.colours where seen.insert(colour.hex).inserted { colours.append(colour) }
            } else if Purpose.of(fileExtension: url.pathExtension) != nil, let s = try? d.decode(PurposeDocument.self, from: found) {
                settings[s.palette, default: []].append(s.settings)
            }
        }
        for at in palettes.indices {
            let all = (palettes[at].purposes ?? []) + (settings[palettes[at].id] ?? [])
            palettes[at].purposes = all.isEmpty ? nil : Purpose.allCases.compactMap { purpose in all.first { $0.purpose == purpose } }
        }
        return (palettes, colours)
    }

    /// Reads a project back whole: from its file and the palette, purpose and history files beside
    /// it, or from the one file an earlier version wrote.
    static func read(_ file: URL) throws -> ProjectFile {
        let data = try Data(contentsOf: file), d = ColourFiles.decoder()
        guard let doc = try? d.decode(ProjectDocument.self, from: data), doc.format == "colour-project" else { return try ProjectFile.read(data) }
        let config = file.deletingLastPathComponent()
        let held = palettes(in: config.appendingPathComponent(palettesFolder), project: doc.project.id)
        var tags = doc.tags ?? [], profiles = doc.profiles
        if let found = try? Data(contentsOf: config.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "." + ColourFiles.data)),
           let own = try? d.decode(DataDocument.self, from: found), own.project == doc.project.id {
            tags = own.tags
            profiles = own.profiles.isEmpty ? nil : own.profiles
        }
        if let order = doc.tagOrder { tags = CatalogueFiles.ordered(tags, by: order) { TagKey(name: $0.name, project: $0.projectID) } }
        var whole = try ProjectFile.read(ColourFiles.encoder().encode(Whole(project: doc.project, palettes: [], colours: [], tags: tags, profiles: profiles)))
        whole.palettes = CatalogueFiles.ordered(held.palettes, by: doc.palettes) { $0.id }.filter { doc.palettes.contains($0.id) }
        whole.colours = CatalogueFiles.ordered(held.colours, by: doc.colours) { $0.hex }
        let steps = config.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "." + ColourFiles.history)
        if let found = try? Data(contentsOf: steps), let h = try? d.decode(HistoryDocument.self, from: found), h.project == doc.project.id { whole.history = h.steps }
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

    /// A project folder under `parent` whose Config holds this project's file, by id.
    private static func findFolder(holding id: UUID, under parent: URL, fm: FileManager) -> URL? {
        for folder in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            let config = folder.appendingPathComponent(configFolder)
            for file in (try? fm.contentsOfDirectory(at: config, includingPropertiesForKeys: nil)) ?? []
                where isProjectFile(file) && projectID(of: file) == id { return folder }
        }
        return nil
    }

    enum AdoptError: LocalizedError {
        case otherProject(String), notAProjectFile, nothingThere
        var errorDescription: String? {
            switch self {
            case .otherProject(let name): return "That is the file of a different project, \u{201C}\(name)\u{201D}."
            case .notAProjectFile: return "That is not a project file."
            case .nothingThere: return "No project file was found there."
            }
        }
    }

    /// Takes a found file (or a folder holding one) as the project's, builds the folder structure
    /// round it where it is missing, and returns the project's folder. The file must be this project's.
    @discardableResult
    static func adopt(_ chosen: URL, for project: Project) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: chosen.path, isDirectory: &isDir) else { throw AdoptError.nothingThere }
        var file = chosen
        if isDir.boolValue {
            // A folder: the project folder itself, its Config folder, or a folder with the file loose inside.
            // Listed by name under the folder as given, so the path keeps the form the caller used.
            let candidates = [chosen.appendingPathComponent(configFolder), chosen].flatMap { dir in
                ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { isProjectFile(URL(fileURLWithPath: $0)) }.map { dir.appendingPathComponent($0) }
            }
            guard let found = candidates.first(where: { projectID(of: $0) == project.id }) else {
                if let any = candidates.first, let other = try? read(any) { throw AdoptError.otherProject(other.project.name) }
                throw AdoptError.nothingThere
            }
            file = found
        }
        guard isProjectFile(file), let read = try? read(file) else { throw AdoptError.notAProjectFile }
        guard read.project.id == project.id else { throw AdoptError.otherProject(read.project.name) }
        let parent = file.deletingLastPathComponent()
        let root: URL
        if parent.lastPathComponent == configFolder {
            root = parent.deletingLastPathComponent()
        } else {
            // A file on its own: give it the folder structure, named for the project, beside it.
            root = parent.appendingPathComponent(filesystemName(project.name))
            try fm.createDirectory(at: root.appendingPathComponent(configFolder), withIntermediateDirectories: true)
            try fm.moveItem(at: file, to: configURL(in: root, name: project.name))
            // Its palettes, when they sit in a folder beside it, come too.
            let palettes = parent.appendingPathComponent(palettesFolder)
            if fm.fileExists(atPath: palettes.path) {
                try? fm.moveItem(at: palettes, to: root.appendingPathComponent(configFolder).appendingPathComponent(palettesFolder))
            }
        }
        return root
    }
}
