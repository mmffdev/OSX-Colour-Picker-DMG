import Foundation

// ---------- Project files ----------
//
// The library file is the master of everything. Each project also gets a file of its own, kept
// current by the app: the whole project, so it can be handed over, moved, and later imported.
// It carries only metadata (names, colours, order, pairings, tags, details), so it stays small.
//
// On disk a project is a package: a folder named "Client A.mmffproject" that Finder shows as one
// file, holding project.json now and, later, history and a preview beside it. Plain JSON, not
// encrypted: it is the user's own work, and anything may read it.

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

    init(project: Project, in lib: Library, history steps: [HistoryStep] = []) {
        self.project = project
        history = steps.map { ProjectStep(id: $0.id, date: $0.date, title: $0.title) }
        palettes = lib.palettes(in: project.id)
        let hexes = Set(palettes.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        colours = lib.colours.filter { hexes.contains($0.hex) }
        let worn = Set(palettes.flatMap { $0.tagList } + colours.flatMap { $0.tags ?? [] })
        tags = lib.tagInfo.filter { $0.removed != true && ($0.projectID == project.id || worn.contains($0.name)) }
    }

    /// "Client A.mmffproject": the package folder.
    static func fileName(for project: Project) -> String { filesystemName(project.name) + ".mmffproject" }
    /// The file inside the package that holds the project.
    static let inner = "project.json"

    /// Dates are kept as milliseconds since 1970: whole numbers, so a file reads back exactly as written.
    func data() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970
        return try e.encode(self)
    }

    static func read(_ data: Data) throws -> ProjectFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return try d.decode(ProjectFile.self, from: data)
    }
}

/// One step as a project file records it: what and when, not the whole library.
struct ProjectStep: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
}

/// Where project files go. A project is a folder named for it, holding a Config folder with the
/// project's file inside: "Cookra/Config/Cookra.config". Exports will sit beside Config later.
///
///     <Projects folder>/<Project name>/Config/<Project name>.config
///
/// A project can have a folder of its own anywhere instead of sitting under the master folder.
enum ProjectFiles {
    static let configFolder = "Config"
    static let fileExtension = "config"

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
            if fm.fileExists(atPath: file.path) { continue }
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
    static func write(_ lib: Library, library: URL, master: URL?, history: StepHistory? = nil, written: inout [UUID: Data]) throws -> (files: [URL], firstTime: [UUID]) {
        let fm = FileManager.default
        let gone = lost(in: lib, library: library, master: master)
        var files: [URL] = [], firstTime: [UUID] = []
        for p in lib.orderedProjects where gone[p.id] == nil {
            let data = try ProjectFile(project: p, in: lib, history: history?.steps(in: p.id) ?? []).data()
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
                where other != file && other.pathExtension == fileExtension && projectID(of: other) == p.id {
                try? fm.removeItem(at: other)
            }
            try data.write(to: file, options: .atomic)
            written[p.id] = data
            files.append(file)
            if p.fileKnown != true { firstTime.append(p.id) }
        }
        return (files, firstTime)
    }

    /// Reads a project's file back.
    static func read(_ file: URL) throws -> ProjectFile { try ProjectFile.read(Data(contentsOf: file)) }

    /// The project a file belongs to, without reading more than needed.
    static func projectID(of file: URL) -> UUID? { (try? read(file))?.project.id }

    /// A project folder under `parent` whose Config holds this project's file, by id.
    private static func findFolder(holding id: UUID, under parent: URL, fm: FileManager) -> URL? {
        for folder in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            let config = folder.appendingPathComponent(configFolder)
            for file in (try? fm.contentsOfDirectory(at: config, includingPropertiesForKeys: nil)) ?? []
                where file.pathExtension == fileExtension && projectID(of: file) == id { return folder }
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
                ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { ($0 as NSString).pathExtension == fileExtension }.map { dir.appendingPathComponent($0) }
            }
            guard let found = candidates.first(where: { projectID(of: $0) == project.id }) else {
                if let any = candidates.first, let other = try? read(any) { throw AdoptError.otherProject(other.project.name) }
                throw AdoptError.nothingThere
            }
            file = found
        }
        guard file.pathExtension == fileExtension, let read = try? read(file) else { throw AdoptError.notAProjectFile }
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
        }
        return root
    }
}
