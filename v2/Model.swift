import Foundation

// ---------- Data model ----------

struct Colour: Codable, Equatable {
    let hex: String
    let pickedAt: Date
}

struct SwatchEntry: Codable, Equatable {
    let hex: String
    let addedAt: Date
}

/// A named collection of colours. Colours always live in the catalogue too.
struct Swatch: Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var entries: [SwatchEntry]
}

struct Library: Codable, Equatable {
    var version = 2
    var colours: [Colour] = []
    var swatches: [Swatch] = []
    /// The swatch new picks are added to. nil = catalogue only.
    var activeSwatchID: UUID?
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

    /// "Swatch N", one higher than the highest default-style name in use.
    func nextDefaultSwatchName() -> String {
        let numbers = swatches.compactMap { s -> Int? in
            let parts = s.name.lowercased().split(separator: " ")
            guard parts.count == 2, parts[0] == "swatch" else { return nil }
            return Int(parts[1])
        }
        return "Swatch \((numbers.max() ?? 0) + 1)"
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
    mutating func renameSwatch(_ id: UUID, to raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = swatches.firstIndex(where: { $0.id == id }) else { return false }
        swatches[i].name = name
        return true
    }

    /// Removes the swatch only; its colours stay in the catalogue.
    mutating func deleteSwatch(_ id: UUID) {
        swatches.removeAll { $0.id == id }
        if activeSwatchID == id { activeSwatchID = nil }
    }

    /// Adds to the catalogue if new, without touching the date of an existing colour.
    @discardableResult
    mutating func addToCatalogue(_ raw: String, at date: Date = Date()) -> String? {
        guard let hex = normaliseHex(raw) else { return nil }
        if !colours.contains(where: { $0.hex == hex }) {
            colours.append(Colour(hex: hex, pickedAt: date))
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
                swatches[i].entries.append(SwatchEntry(hex: hex, addedAt: date))
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

    mutating func remove(_ hexes: Set<String>, fromSwatch id: UUID) {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return }
        swatches[i].entries.removeAll { hexes.contains($0.hex) }
    }

    /// Removes from the catalogue and from every swatch.
    mutating func deleteColours(_ hexes: Set<String>) {
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
            colours.append(Colour(hex: hex, pickedAt: c.pickedAt))
            added += 1
        }
        return added
    }
}

// ---------- Persistence ----------

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
    /// Set when an unreadable library file was moved aside during load.
    private(set) var quarantinedFile: URL?

    init(directory: URL, legacyURL: URL?) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("library.json")
        self.legacyURL = legacyURL
    }

    static let standard: LibraryStore = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // MMFFDEV_COLOUR2_HOME points the app at another folder, for trying things without touching real data.
        let override = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR2_HOME"].map { URL(fileURLWithPath: $0) }
        return LibraryStore(
            directory: override ?? support.appendingPathComponent("MMFFDev Colour 2"),
            legacyURL: support.appendingPathComponent("MMFFDev Colour").appendingPathComponent("library.json"))
    }()

    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return d
    }

    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func loadLegacy() -> [Colour] {
        guard let legacyURL = legacyURL, let data = try? Data(contentsOf: legacyURL) else { return [] }
        return (try? decoder.decode([Colour].self, from: data)) ?? []
    }

    /// First run seeds the library with a copy of the v1 colours.
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
        var lib = Library()
        lib.mergeLegacy(loadLegacy())
        try save(lib)
        return lib
    }

    func save(_ lib: Library) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try e.encode(lib).write(to: url, options: .atomic)
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
