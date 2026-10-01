import Foundation

// ---------- Data model ----------

struct Colour: Codable, Equatable {
    let hex: String
    var pickedAt: Date
    /// Free-form labels. The date lets a sync keep the newer set.
    var tags: [String]?
    var tagsChangedAt: Date?

    init(hex: String, pickedAt: Date, tags: [String]? = nil, tagsChangedAt: Date? = nil) {
        self.hex = hex; self.pickedAt = pickedAt; self.tags = tags; self.tagsChangedAt = tagsChangedAt
    }
}

/// A folder of palettes in the sidebar: a client, a product, a piece of work.
struct Project: Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var nameChangedAt: Date?
    var position: Int?
    var positionChangedAt: Date?
}

struct SwatchEntry: Codable, Equatable {
    let hex: String
    var addedAt: Date
}

/// A named collection of colours. Colours always live in the catalogue too.
struct Swatch: Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var entries: [SwatchEntry]
    /// When the name was last edited, so a sync keeps the newer name. nil = never renamed.
    var nameChangedAt: Date?
    /// Starred palettes are listed under Favourites. The date lets a sync keep the newer choice.
    var isFavourite: Bool?
    var favouriteChangedAt: Date?
    /// Built from colours already in the library, rather than picked or taken from an image.
    var isCustom: Bool?
    /// The project this palette sits in; nil is the loose "Palettes" list.
    var projectID: UUID?
    /// Order within its project. `placedAt` lets a sync keep the newer arrangement.
    var position: Int?
    var placedAt: Date?
    var tags: [String]?
    var tagsChangedAt: Date?

    var favourite: Bool { isFavourite ?? false }
    var custom: Bool { isCustom ?? false }
    var tagList: [String] { tags ?? [] }
}

/// A record that something was deleted, and when. Lets a sync tell "deleted on this Mac"
/// apart from "added on the other one", so deletions stick and later re-additions survive.
struct Tombstone: Codable, Equatable {
    enum Kind: String, Codable { case colour, swatch, entry, project }
    let kind: Kind
    /// Colour: its hex. Swatch: its UUID. Entry: "UUID/hex".
    let key: String
    let deletedAt: Date
}

struct Library: Codable, Equatable {
    var version = 2
    var colours: [Colour] = []
    var swatches: [Swatch] = []
    /// The swatch new picks are added to. nil = catalogue only.
    var activeSwatchID: UUID?
    var deleted: [Tombstone] = []
    var projects: [Project] = []

    enum CodingKeys: String, CodingKey { case version, colours, swatches, activeSwatchID, deleted, projects }
}

extension Library {
    // Libraries written before sync existed have no "deleted" key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        version = try c.decode(Int.self, forKey: .version)
        colours = try c.decode([Colour].self, forKey: .colours)
        swatches = try c.decode([Swatch].self, forKey: .swatches)
        activeSwatchID = try c.decodeIfPresent(UUID.self, forKey: .activeSwatchID)
        deleted = try c.decodeIfPresent([Tombstone].self, forKey: .deleted) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
    }

    static func entryKey(_ swatch: UUID, _ hex: String) -> String { "\(swatch.uuidString)/\(hex)" }

    func deletedAt(_ kind: Tombstone.Kind, _ key: String) -> Date? {
        deleted.first { $0.kind == kind && $0.key == key }?.deletedAt
    }

    /// Records a deletion. Rounded up to a whole second, the precision dates are saved at,
    /// so it is never earlier than the thing it deletes.
    mutating func bury(_ kind: Tombstone.Kind, _ key: String, at date: Date) {
        let t = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
        deleted.removeAll { $0.kind == kind && $0.key == key }
        deleted.append(Tombstone(kind: kind, key: key, deletedAt: t))
    }

    /// `date`, moved later if needed so that it falls after any earlier deletion of the same thing.
    func after(_ deletions: [Date?], _ date: Date) -> Date {
        guard let latest = deletions.compactMap({ $0 }).max(), latest >= date else { return date }
        return latest.addingTimeInterval(1)
    }
}

// ---------- Hex helpers ----------

/// Returns "#RRGGBB" uppercase, or nil if the input is not a 6-digit hex colour.
func normaliseHex(_ raw: String) -> String? {
    var h = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, h.allSatisfy({ $0.isHexDigit }) else { return nil }
    return "#" + h
}

func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
    guard let n = normaliseHex(hex), let v = UInt32(n.dropFirst(), radix: 16) else { return nil }
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

func hexList(_ hexes: [String]) -> String {
    hexes.joined(separator: ", ")
}

// ---------- Sorting ----------

enum SortOrder: Int, CaseIterable {
    case newest, oldest, colour

    var title: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .colour: return "Colour Order"
        }
    }
}

struct ColourSortKey: Comparable {
    let group: Int          // 0 = chromatic, 1 = greys
    let hueBucket: Int      // 12 x 30° buckets, reds first
    let luminance: Double
    let hex: String

    static func < (a: ColourSortKey, b: ColourSortKey) -> Bool {
        if a.group != b.group { return a.group < b.group }
        if a.hueBucket != b.hueBucket { return a.hueBucket < b.hueBucket }
        if a.luminance != b.luminance { return a.luminance > b.luminance } // light to dark
        return a.hex < b.hex
    }
}

func colourSortKey(_ hex: String) -> ColourSortKey {
    guard let (r, g, b) = rgbComponents(hex) else {
        return ColourSortKey(group: 2, hueBucket: 0, luminance: 0, hex: hex)
    }
    let mx = max(r, g, b), mn = min(r, g, b), delta = mx - mn
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    let saturation = mx == 0 ? 0 : delta / mx
    if saturation < 0.12 || mx < 0.1 {
        return ColourSortKey(group: 1, hueBucket: 0, luminance: luminance, hex: hex)
    }
    var hue: Double
    if mx == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
    else if mx == g { hue = (b - r) / delta + 2 }
    else { hue = (r - g) / delta + 4 }
    hue *= 60
    if hue < 0 { hue += 360 }
    // Shift by 15° so reds either side of 0° land in the same bucket.
    let bucket = Int((hue + 15).truncatingRemainder(dividingBy: 360) / 30)
    return ColourSortKey(group: 0, hueBucket: bucket, luminance: luminance, hex: hex)
}

func sortedHexes(_ items: [(hex: String, date: Date)], by order: SortOrder) -> [String] {
    switch order {
    case .newest:
        return items.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset > $1.offset }
            .map { $0.element.hex }
    case .oldest:
        return items.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map { $0.element.hex }
    case .colour:
        return items.map { colourSortKey($0.hex) }.sorted().map { $0.hex }
    }
}

// ---------- Library operations ----------

extension Library {
    func swatch(_ id: UUID) -> Swatch? { swatches.first { $0.id == id } }

    var activeSwatch: Swatch? { activeSwatchID.flatMap { swatch($0) } }

    func catalogueHexes(by order: SortOrder) -> [String] {
        sortedHexes(colours.map { ($0.hex, $0.pickedAt) }, by: order)
    }

    func hexes(inSwatch id: UUID, by order: SortOrder) -> [String] {
        guard let s = swatch(id) else { return [] }
        return sortedHexes(s.entries.map { ($0.hex, $0.addedAt) }, by: order)
    }

    /// "Palette N", one higher than the highest default-style name in use.
    func nextDefaultSwatchName() -> String {
        let numbers = swatches.compactMap { s -> Int? in
            let parts = s.name.lowercased().split(separator: " ")
            guard parts.count == 2, parts[0] == "palette" else { return nil }
            return Int(parts[1])
        }
        return "Palette \((numbers.max() ?? 0) + 1)"
    }

    /// Creates a swatch with a default name and makes it the target for new picks.
    @discardableResult
    mutating func createSwatch(at date: Date = Date()) -> UUID {
        let s = Swatch(id: UUID(), name: nextDefaultSwatchName(), createdAt: date, entries: [])
        swatches.append(s)
        activeSwatchID = s.id
        return s.id
    }

    /// Returns false (and changes nothing) if the name is blank or the swatch is gone.
    @discardableResult
    mutating func renameSwatch(_ id: UUID, to raw: String, at date: Date = Date()) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = swatches.firstIndex(where: { $0.id == id }) else { return false }
        if swatches[i].name != name {
            swatches[i].name = name
            swatches[i].nameChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
        }
        return true
    }

    // MARK: Projects and order

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    /// Projects in sidebar order.
    var orderedProjects: [Project] {
        projects.sorted { a, b in
            let (x, y) = (a.position ?? Int.max, b.position ?? Int.max)
            return x != y ? x < y : a.createdAt < b.createdAt
        }
    }

    /// Palettes in one project (nil = the loose list), in their kept order, newest first when unplaced.
    func palettes(in projectID: UUID?) -> [Swatch] {
        swatches.filter { $0.projectID == projectID }.sorted { a, b in
            let (x, y) = (a.position ?? Int.max, b.position ?? Int.max)
            return x != y ? x < y : a.createdAt > b.createdAt
        }
    }

    @discardableResult
    mutating func createProject(named raw: String, at date: Date = Date()) -> UUID {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = uniqueName(base.isEmpty ? "New Project" : base, among: projects.map { $0.name })
        let p = Project(id: UUID(), name: name, createdAt: date, nameChangedAt: nil,
                        position: (projects.compactMap { $0.position }.max() ?? -1) + 1, positionChangedAt: date)
        projects.append(p)
        return p.id
    }

    @discardableResult
    mutating func renameProject(_ id: UUID, to raw: String, at date: Date = Date()) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = projects.firstIndex(where: { $0.id == id }) else { return false }
        if projects[i].name != name {
            projects[i].name = name
            projects[i].nameChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
        }
        return true
    }

    /// Removes the project only; its palettes drop into the loose list.
    mutating func deleteProject(_ id: UUID, at date: Date = Date()) {
        guard projects.contains(where: { $0.id == id }) else { return }
        bury(.project, id.uuidString, at: date)
        projects.removeAll { $0.id == id }
        for i in swatches.indices where swatches[i].projectID == id {
            swatches[i].projectID = nil
            swatches[i].placedAt = date
        }
    }

    /// Puts a palette at `index` within `project` (nil = loose list), renumbering both lists.
    mutating func move(_ paletteID: UUID, to project: UUID?, index: Int, at date: Date = Date()) {
        guard let s = swatches.firstIndex(where: { $0.id == paletteID }) else { return }
        if let p = project, self.project(p) == nil { return }
        let from = swatches[s].projectID
        var order = palettes(in: project).map { $0.id }.filter { $0 != paletteID }
        order.insert(paletteID, at: min(max(0, index), order.count))
        swatches[s].projectID = project
        place(order, at: date)
        if from != project { place(palettes(in: from).map { $0.id }, at: date) }
    }

    /// Gives an ordered set of palettes positions 0, 1, 2 …
    mutating func place(_ ids: [UUID], at date: Date = Date()) {
        for (n, id) in ids.enumerated() {
            guard let i = swatches.firstIndex(where: { $0.id == id }) else { continue }
            if swatches[i].position != n { swatches[i].position = n; swatches[i].placedAt = date }
        }
    }

    mutating func placeProjects(_ ids: [UUID], at date: Date = Date()) {
        for (n, id) in ids.enumerated() {
            guard let i = projects.firstIndex(where: { $0.id == id }) else { continue }
            if projects[i].position != n { projects[i].position = n; projects[i].positionChangedAt = date }
        }
    }

    // MARK: Tags

    /// Trimmed, de-duplicated without regard to case, in the order given.
    static func cleanTags(_ raw: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in raw {
            let tag = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            out.append(tag)
        }
        return out
    }

    mutating func setTags(ofPalette id: UUID, _ raw: [String], at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return }
        let tags = Library.cleanTags(raw)
        guard tags != swatches[i].tagList else { return }
        swatches[i].tags = tags.isEmpty ? nil : tags
        swatches[i].tagsChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    mutating func setTags(ofColour hex: String, _ raw: [String], at date: Date = Date()) {
        guard let i = colours.firstIndex(where: { $0.hex == hex }) else { return }
        let tags = Library.cleanTags(raw)
        guard tags != (colours[i].tags ?? []) else { return }
        colours[i].tags = tags.isEmpty ? nil : tags
        colours[i].tagsChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    /// Every tag in use, on swatches or palettes, sorted.
    var allTags: [String] {
        var seen: [String: String] = [:]
        for t in colours.flatMap({ $0.tags ?? [] }) + swatches.flatMap({ $0.tagList }) where seen[t.lowercased()] == nil { seen[t.lowercased()] = t }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Swatches carrying the tag themselves or sitting in a palette that carries it.
    func hexes(tagged tag: String) -> Set<String> {
        let t = tag.lowercased()
        var out = Set(colours.filter { ($0.tags ?? []).contains { $0.lowercased() == t } }.map { $0.hex })
        for s in swatches where s.tagList.contains(where: { $0.lowercased() == t }) { out.formUnion(s.entries.map { $0.hex }) }
        return out
    }

    mutating func setFavourite(_ id: UUID, _ on: Bool, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), swatches[i].favourite != on else { return }
        swatches[i].isFavourite = on
        swatches[i].favouriteChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    /// Removes the swatch only; its colours stay in the catalogue.
    mutating func deleteSwatch(_ id: UUID, at date: Date = Date()) {
        if swatches.contains(where: { $0.id == id }) { bury(.swatch, id.uuidString, at: date) }
        swatches.removeAll { $0.id == id }
        if activeSwatchID == id { activeSwatchID = nil }
    }

    /// Adds to the catalogue if new, without touching the date of an existing colour.
    @discardableResult
    mutating func addToCatalogue(_ raw: String, at date: Date = Date()) -> String? {
        guard let hex = normaliseHex(raw) else { return nil }
        if !colours.contains(where: { $0.hex == hex }) {
            colours.append(Colour(hex: hex, pickedAt: after([deletedAt(.colour, hex)], date)))
        }
        return hex
    }

    /// Returns how many colours were newly added to the swatch.
    @discardableResult
    mutating func add(_ hexes: [String], toSwatch id: UUID, at date: Date = Date()) -> Int {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return 0 }
        var added = 0
        for raw in hexes {
            guard let hex = addToCatalogue(raw, at: date) else { continue }
            if !swatches[i].entries.contains(where: { $0.hex == hex }) {
                let when = after([deletedAt(.entry, Library.entryKey(id, hex)), deletedAt(.colour, hex)], date)
                swatches[i].entries.append(SwatchEntry(hex: hex, addedAt: when))
                added += 1
            }
        }
        return added
    }

    /// A fresh pick: into the catalogue, and into the active swatch if there is one.
    @discardableResult
    mutating func addPick(_ raw: String, at date: Date = Date()) -> String? {
        guard let hex = addToCatalogue(raw, at: date) else { return nil }
        if let id = activeSwatchID {
            if swatch(id) != nil { add([hex], toSwatch: id, at: date) }
            else { activeSwatchID = nil }
        }
        return hex
    }

    mutating func remove(_ hexes: Set<String>, fromSwatch id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return }
        for e in swatches[i].entries where hexes.contains(e.hex) { bury(.entry, Library.entryKey(id, e.hex), at: date) }
        swatches[i].entries.removeAll { hexes.contains($0.hex) }
    }

    /// Removes from the catalogue and from every swatch.
    mutating func deleteColours(_ hexes: Set<String>, at date: Date = Date()) {
        // A colour's tombstone also covers its place in every swatch.
        for c in colours where hexes.contains(c.hex) { bury(.colour, c.hex, at: date) }
        colours.removeAll { hexes.contains($0.hex) }
        for i in swatches.indices {
            swatches[i].entries.removeAll { hexes.contains($0.hex) }
        }
    }

    func swatchCount(containingAnyOf hexes: Set<String>) -> Int {
        swatches.filter { s in s.entries.contains { hexes.contains($0.hex) } }.count
    }

    /// Returns how many colours were new to the catalogue.
    @discardableResult
    mutating func mergeLegacy(_ legacy: [Colour]) -> Int {
        var added = 0
        for c in legacy {
            guard let hex = normaliseHex(c.hex), !colours.contains(where: { $0.hex == hex }) else { continue }
            colours.append(Colour(hex: hex, pickedAt: after([deletedAt(.colour, hex)], c.pickedAt)))
            added += 1
        }
        return added
    }
}

// ---------- Naming ----------

/// Safe as a single path component: no separators or control characters, trimmed, never empty.
func filesystemName(_ raw: String) -> String {
    let bad = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
    let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.map { bad.contains($0) ? "-" : $0 }))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(100))
}

/// `name`, or "name 2", "name 3"... — the first not already in `taken` (case-insensitive).
func uniqueName(_ name: String, among taken: [String]) -> String {
    let lower = Set(taken.map { $0.lowercased() })
    if !lower.contains(name.lowercased()) { return name }
    var n = 2
    while lower.contains("\(name) \(n)".lowercased()) { n += 1 }
    return "\(name) \(n)"
}

// ---------- Export ----------

struct ExportFile: Equatable {
    let name: String
    let contents: String
}

extension Library {
    /// Creates a swatch with the given (uniqued) name holding `hexes`, and makes it the pick target.
    @discardableResult
    mutating func createSwatch(named raw: String, hexes: [String], custom: Bool = false, at date: Date = Date()) -> UUID {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = uniqueName(base.isEmpty ? nextDefaultSwatchName() : base, among: swatches.map { $0.name })
        let s = Swatch(id: UUID(), name: name, createdAt: date, entries: [], isCustom: custom ? true : nil)
        swatches.append(s)
        add(hexes, toSwatch: s.id, at: date)
        activeSwatchID = s.id
        return s.id
    }

    /// Plain-text files: "All Colours.txt" plus one per non-empty swatch. Empty library gives none.
    func exportFiles(by order: SortOrder) -> [ExportFile] {
        var files: [ExportFile] = []
        var taken: [String] = []
        func add(_ title: String, _ hexes: [String]) {
            guard !hexes.isEmpty else { return }
            let name = uniqueName(filesystemName(title), among: taken)
            taken.append(name)
            files.append(ExportFile(name: name + ".txt", contents: hexList(hexes) + "\n"))
        }
        add("All Colours", catalogueHexes(by: order))
        for s in swatches { add(s.name, hexes(inSwatch: s.id, by: order)) }
        return files
    }
}

/// Writes library.json and the text files into a new "MMFFDev Colour 3 Export" folder under `folder`.
/// Returns the folder written. Never overwrites: a second export gets "... Export 2".
func writeExport(_ lib: Library, to folder: URL, by order: SortOrder) throws -> URL {
    let fm = FileManager.default
    let existing = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
    let dir = folder.appendingPathComponent(uniqueName("MMFFDev Colour 3 Export", among: existing))
    try fm.createDirectory(at: dir, withIntermediateDirectories: false)
    try JSONEncoder.library.encode(lib).write(to: dir.appendingPathComponent("library.json"), options: .atomic)
    for f in lib.exportFiles(by: order) {
        try f.contents.write(to: dir.appendingPathComponent(f.name), atomically: true, encoding: .utf8)
    }
    return dir
}

// ---------- Persistence ----------

extension JSONEncoder {
    static var library: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var library: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

enum StoreError: LocalizedError {
    case saveFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let url, let e):
            return "Could not save the library to \(url.path): \(e.localizedDescription)"
        }
    }
}

final class LibraryStore {
    let url: URL
    /// The v1 library. Read for import, never written.
    let legacyURL: URL?
    /// The v2 library. Read for import, never written.
    let previousURL: URL?
    /// Set when an unreadable library file was moved aside during load.
    private(set) var quarantinedFile: URL?

    init(directory: URL, legacyURL: URL?, previousURL: URL? = nil) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("library.json")
        self.legacyURL = legacyURL
        self.previousURL = previousURL
    }

    /// The store for the catalogue last opened on this Mac.
    static var standard: LibraryStore { Catalogues.standard.store(for: Catalogues.currentName) }

    private var decoder: JSONDecoder { .library }

    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func loadLegacy() -> [Colour] {
        guard let legacyURL = legacyURL, let data = try? Data(contentsOf: legacyURL) else { return [] }
        return (try? decoder.decode([Colour].self, from: data)) ?? []
    }

    func loadPrevious() -> Library? {
        guard let previousURL = previousURL, let data = try? Data(contentsOf: previousURL) else { return nil }
        return try? decoder.decode(Library.self, from: data)
    }

    /// First run seeds the library with a copy of the v2 library, or failing that the v1 colours.
    func load() throws -> Library {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url), let lib = try? decoder.decode(Library.self, from: data) {
                return lib
            }
            // Never overwrite a file we could not read — move it aside for recovery.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appendingPathComponent("library.unreadable-\(stamp).json")
            try? fm.moveItem(at: url, to: aside)
            quarantinedFile = aside
        }
        var lib = loadPrevious() ?? Library()
        lib.mergeLegacy(loadLegacy())
        try save(lib)
        return lib
    }

    func save(_ lib: Library) throws {
        do {
            try JSONEncoder.library.encode(lib).write(to: url, options: .atomic)
        } catch {
            throw StoreError.saveFailed(url, error)
        }
    }

    /// Re-reads from disk before changing anything, so picks made by the
    /// hotkey process while the window is open are never overwritten.
    @discardableResult
    func mutate(_ body: (inout Library) -> Void) throws -> Library {
        var lib = try load()
        body(&lib)
        try save(lib)
        return lib
    }
}
