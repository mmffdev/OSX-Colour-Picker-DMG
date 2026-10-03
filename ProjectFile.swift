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
    /// Steps taken in this project; filled once history exists.
    var history: [String] = []

    init(project: Project, in lib: Library) {
        self.project = project
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

    /// Dates are written the readable way, to the millisecond, so a file reads back exactly.
    private static let clock: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainClock = ISO8601DateFormatter()

    func data() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ProjectFile.clock.string(from: date))
        }
        return try e.encode(self)
    }

    static func read(_ data: Data) throws -> ProjectFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = clock.date(from: s) ?? plainClock.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(s)"))
            }
            return date
        }
        return try d.decode(ProjectFile.self, from: data)
    }
}

/// Where project files go: one master folder, and a folder of its own for any project that wants one.
enum ProjectFiles {
    /// The master folder; nil until chosen, when it defaults to "Projects" beside the library file.
    static var folder: URL? {
        get { preferences.string(forKey: "projectsFolder").map { URL(fileURLWithPath: $0) } }
        set { preferences.set(newValue?.path, forKey: "projectsFolder") }
    }

    static func folder(for project: Project, library: URL) -> URL {
        if let own = project.folder { return URL(fileURLWithPath: own) }
        return folder ?? library.deletingLastPathComponent().appendingPathComponent("Projects")
    }

    static func url(for project: Project, library: URL) -> URL {
        folder(for: project, library: library).appendingPathComponent(ProjectFile.fileName(for: project))
    }

    /// Writes every project's package, and only when its contents have changed since the last write.
    /// Returns the packages written. `written` carries what was last written, by project id.
    static func write(_ lib: Library, library: URL, written: inout [UUID: Data]) throws -> [URL] {
        var out: [URL] = []
        for p in lib.orderedProjects {
            let data = try ProjectFile(project: p, in: lib).data()
            if written[p.id] == data { continue }
            let package = url(for: p, library: library)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try data.write(to: package.appendingPathComponent(ProjectFile.inner), options: .atomic)
            written[p.id] = data
            out.append(package)
        }
        return out
    }

    /// Reads a package back.
    static func read(_ package: URL) throws -> ProjectFile {
        try ProjectFile.read(Data(contentsOf: package.appendingPathComponent(ProjectFile.inner)))
    }
}
