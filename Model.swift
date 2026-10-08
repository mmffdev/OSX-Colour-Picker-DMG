import Foundation

// ---------- Data model ----------

struct Colour: Codable, Equatable {
    /// The colour's key: "#RRGGBB" for a plain sRGB colour, or an id of its own ("c:…") for any
    /// other. See ColourIdentity.swift. Called `hex` for the sake of every library written so far.
    let hex: String
    var pickedAt: Date
    /// Free-form labels. The date lets a sync keep the newer set.
    var tags: [String]?
    var tagsChangedAt: Date?
    /// For a colour that is not a plain sRGB value: what was given, its device-independent master,
    /// and whether it is a surface or a light. A plain sRGB colour needs none: its hex is its source.
    var source: ColourSource?
    var master: XYZ?
    var kind: ColourKind?

    enum CodingKeys: String, CodingKey { case hex, pickedAt, tags, tagsChangedAt, source, master, kind }

    init(hex: String, pickedAt: Date, tags: [String]? = nil, tagsChangedAt: Date? = nil,
         source: ColourSource? = nil, master: XYZ? = nil, kind: ColourKind? = nil) {
        self.hex = hex; self.pickedAt = pickedAt; self.tags = tags; self.tagsChangedAt = tagsChangedAt
        self.source = source; self.master = master; self.kind = kind
        register()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hex = try c.decode(String.self, forKey: .hex)
        pickedAt = try c.decode(Date.self, forKey: .pickedAt)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        tagsChangedAt = try c.decodeIfPresent(Date.self, forKey: .tagsChangedAt)
        source = try c.decodeIfPresent(ColourSource.self, forKey: .source)
        master = try c.decodeIfPresent(XYZ.self, forKey: .master)
        kind = try c.decodeIfPresent(ColourKind.self, forKey: .kind)
        register()
    }

    /// The colour's full definition: what it carries, or its hex taken as an sRGB source.
    var definition: ColourDefinition? {
        if let source = source, let master = master { return ColourDefinition(source: source, master: master, kind: kind ?? .surface) }
        return ColourDefinition.of(hex: hex)
    }

    /// Lets the rest of the app find what a key of the other kind means, wherever the record came from.
    private func register() {
        if ColourKeys.isKey(hex), let source = source, let master = master {
            ColourKeys.register(hex, ColourDefinition(source: source, master: master, kind: kind ?? .surface))
        }
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
    /// The project form's answers, by ProjectField; nil until some are given.
    var details: [String: String]? = nil
    var detailsChangedAt: Date? = nil
    /// The project's own folder, when it has been given one; nil puts it under the master Projects folder.
    var folder: String? = nil
    /// Set once the project's file has been written. From then on a missing file is reported, never quietly remade.
    var fileKnown: Bool? = nil
    /// Locked: nothing in the project may change until it is unlocked. Kept in the project file too.
    var locked: Bool? = nil
    var isLocked: Bool { locked ?? false }
    /// The colour profile the project's palettes work to, unless one has its own; nil is the house default.
    var profile: UUID? = nil
    var profileChangedAt: Date? = nil
}

struct SwatchEntry: Codable, Equatable {
    let hex: String
    var addedAt: Date
    /// The user's own name for the colour in this palette; nil uses the standard name.
    var name: String? = nil
    var nameChangedAt: Date? = nil
    /// Why the colour is here: the designer's words on it in this palette. Kept in the project file with the rest.
    var note: String? = nil
    var noteChangedAt: Date? = nil
}

/// One pairing in a Typography palette: a text colour on a background, with the words and fonts
/// it was tried in, so it can be shown as a real example.
struct TypeStyle: Codable, Equatable {
    let id: UUID
    var name: String
    var ink: String
    var paper: String
    var heading: String
    var body: String
    /// Font families; nil is the system font. Kept by name, so a Mac without the font can say which one is missing.
    var headingFont: String?
    var bodyFont: String?

    /// The fonts this style names, heading first.
    var fonts: [String] { [headingFont, bodyFont].compactMap { $0 } }
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
    /// Order under Favourites, and order in the Palettes list. Each place a palette shows keeps an
    /// order of its own, so arranging one never disturbs another. nil = not arranged there yet.
    /// The dates let a sync keep the newer arrangement.
    var favouritePosition: Int? = nil
    var favouritePlacedAt: Date? = nil
    var listPosition: Int? = nil
    var listPlacedAt: Date? = nil
    /// Set on a Typography palette: its pairings, in order. nil is an ordinary palette of colours.
    /// A sync keeps the newer list whole.
    var styles: [TypeStyle]? = nil
    var stylesChangedAt: Date? = nil
    /// The palette this one was copied from, when it was taken into a project or out of one.
    var copiedFrom: UUID? = nil
    /// The colour profile this palette works to; nil uses its project's, or the house default.
    var profile: UUID? = nil
    var profileChangedAt: Date? = nil
    /// What the palette is for, each purpose with its own settings; see Purposes.swift. nil is none chosen.
    var purposes: [PurposeConfig]? = nil
    /// The one purpose the palette is turned to; nil shows it as it is. Kept in its project's file.
    var purpose: Purpose? = nil
    var purposeChangedAt: Date? = nil

    var isTypography: Bool { styles != nil }

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

/// What is known about a tag beyond its name. Tags themselves live on the swatches and palettes
/// that carry them; this adds a colour and a scope, and lets a tag exist before anything wears it.
struct TagInfo: Codable, Equatable {
    var name: String
    /// "#RRGGBB"; nil is the standard tag colour.
    var colour: String?
    /// The project the tag belongs to; nil is a global tag.
    var projectID: UUID?
    /// A deleted tag keeps its record, so that a sync does not bring it back.
    var removed: Bool?
    var changedAt: Date
}

struct Library: Codable, Equatable {
    var version = 2
    var colours: [Colour] = []
    var swatches: [Swatch] = []
    /// The swatch new picks are added to. nil = catalogue only.
    var activeSwatchID: UUID?
    var deleted: [Tombstone] = []
    var projects: [Project] = []
    var tagInfo: [TagInfo] = []
    /// The colour profiles this library's palettes and projects use: its own copies, so it stays whole when it travels.
    var colourProfiles: [ColourProfile] = []

    enum CodingKeys: String, CodingKey { case version, colours, swatches, activeSwatchID, deleted, projects, tagInfo = "tags", colourProfiles }

    // The "tags" key is left out while there is nothing to say, so older libraries stay as they were.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(colours, forKey: .colours)
        try c.encode(swatches, forKey: .swatches)
        try c.encodeIfPresent(activeSwatchID, forKey: .activeSwatchID)
        try c.encode(deleted, forKey: .deleted)
        try c.encode(projects, forKey: .projects)
        if !tagInfo.isEmpty { try c.encode(tagInfo, forKey: .tagInfo) }
        if !colourProfiles.isEmpty { try c.encode(colourProfiles, forKey: .colourProfiles) }
    }
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
        tagInfo = try c.decodeIfPresent([TagInfo].self, forKey: .tagInfo) ?? []
        colourProfiles = try c.decodeIfPresent([ColourProfile].self, forKey: .colourProfiles) ?? []
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
    // A key that is not a hex is read as the sRGB colour it shows as.
    guard let n = normaliseHex(hex) ?? ColourKeys.displayHex(hex), let v = UInt32(n.dropFirst(), radix: 16) else { return nil }
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

    /// Every palette once: project by project, then the ones outside any project.
    var projectOrder: [Swatch] { orderedProjects.flatMap { palettes(in: $0.id) } + palettes(in: nil) }

    /// By a place's own order. Palettes not yet arranged there come first, as `projectOrder` has them.
    private func arranged(_ list: [Swatch], by position: (Swatch) -> Int?) -> [Swatch] {
        list.enumerated().sorted { a, b in
            let (x, y) = (position(a.element) ?? Int.min, position(b.element) ?? Int.min)
            return x != y ? x < y : a.offset < b.offset
        }.map { $0.element }
    }

    /// The Palettes list: every palette, in the list's own order.
    var listedPalettes: [Swatch] { arranged(projectOrder) { $0.listPosition } }
    /// Favourites, in their own order.
    var orderedFavourites: [Swatch] { arranged(projectOrder.filter { $0.favourite }) { $0.favouritePosition } }

    // MARK: Typography palettes

    func nextTypographyName() -> String {
        let numbers = swatches.compactMap { s -> Int? in
            let parts = s.name.lowercased().split(separator: " ")
            guard parts.count == 2, parts[0] == "typography" else { return nil }
            return Int(parts[1])
        }
        return "Typography \((numbers.max() ?? 0) + 1)"
    }

    /// The name a new pairing gets in a Typography palette: "Typography Set 1", then 2, and so on.
    func nextStyleName(in id: UUID) -> String {
        let numbers = (swatch(id)?.styles ?? []).compactMap { s -> Int? in
            let parts = s.name.lowercased().split(separator: " ")
            guard parts.count == 3, parts[0] == "typography", parts[1] == "set" else { return nil }
            return Int(parts[2])
        }
        return "Typography Set \((numbers.max() ?? 0) + 1)"
    }

    /// Creates an empty Typography palette. It never becomes the target for picks.
    @discardableResult
    mutating func createTypography(named raw: String = "", in project: UUID? = nil, at date: Date = Date()) -> UUID {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = uniqueName(base.isEmpty ? nextTypographyName() : base, among: swatches.map { $0.name })
        swatches.append(Swatch(id: UUID(), name: name, createdAt: date, entries: [], styles: [], stylesChangedAt: date))
        let id = swatches[swatches.count - 1].id
        if let p = project { move(id, to: p, index: Int.max, at: date) }
        return id
    }

    /// Adds a pairing, or replaces the one with the same id. Its two colours join the palette and the library.
    mutating func setStyle(_ style: TypeStyle, in id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), var styles = swatches[i].styles,
              let ink = colourKey(style.ink), let paper = colourKey(style.paper) else { return }
        var clean = style
        clean.ink = ink; clean.paper = paper
        let name = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.name = name.isEmpty ? (styles.first { $0.id == style.id }?.name ?? nextStyleName(in: id)) : name
        if let at = styles.firstIndex(where: { $0.id == style.id }) {
            guard styles[at] != clean else { return }
            styles[at] = clean
        } else {
            styles.append(clean)
        }
        swatches[i].styles = styles
        swatches[i].stylesChangedAt = date
        add([ink, paper], toSwatch: id, at: date)
    }

    mutating func removeStyle(_ style: UUID, from id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), let styles = swatches[i].styles, styles.contains(where: { $0.id == style }) else { return }
        swatches[i].styles = styles.filter { $0.id != style }
        swatches[i].stylesChangedAt = date
    }

    /// Swaps one font family for another in every pairing of a Typography palette.
    mutating func replaceFont(_ old: String, with new: String?, in id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), var styles = swatches[i].styles else { return }
        for n in styles.indices {
            if styles[n].headingFont == old { styles[n].headingFont = new }
            if styles[n].bodyFont == old { styles[n].bodyFont = new }
        }
        guard styles != swatches[i].styles else { return }
        swatches[i].styles = styles
        swatches[i].stylesChangedAt = date
    }

    /// Sets the order of the Palettes list. Order inside projects and under Favourites is untouched.
    mutating func placeInList(_ ids: [UUID], at date: Date = Date()) {
        for (n, id) in ids.enumerated() {
            guard let i = swatches.firstIndex(where: { $0.id == id }) else { continue }
            if swatches[i].listPosition != n { swatches[i].listPosition = n; swatches[i].listPlacedAt = date }
        }
    }

    /// Sets the order under Favourites. Order inside projects and in the Palettes list is untouched.
    mutating func placeFavourites(_ ids: [UUID], at date: Date = Date()) {
        for (n, id) in ids.enumerated() {
            guard let i = swatches.firstIndex(where: { $0.id == id }) else { continue }
            if swatches[i].favouritePosition != n { swatches[i].favouritePosition = n; swatches[i].favouritePlacedAt = date }
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

    /// Keeps the project form's answers. Blank ones are dropped; nothing changes if they are the same.
    mutating func setProjectDetails(_ id: UUID, _ values: [String: String], at date: Date = Date()) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        let kept = ProjectField.tidy(values)
        guard kept != (projects[i].details ?? [:]) else { return }
        projects[i].details = kept.isEmpty ? nil : kept
        projects[i].detailsChangedAt = date
    }

    /// Removes the project only; its palettes drop into the loose list.
    mutating func setProjectFolder(_ id: UUID, _ path: String?) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].folder = path
    }

    mutating func setProjectLocked(_ id: UUID, _ on: Bool) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].locked = on ? true : nil
    }

    /// The name of a locked project that `after` would change, or nil. A project locked before and
    /// still locked after must be the same in every way; unlocking it is the one change allowed.
    func lockedProjectChanged(by after: Library) -> String? {
        for p in projects where p.isLocked {
            guard let later = after.project(p.id), later.isLocked else { continue }
            if later != p || after.palettes(in: p.id) != palettes(in: p.id) { return p.name }
        }
        // Deleting a locked project is a change to it too.
        for p in projects where p.isLocked && after.project(p.id) == nil { return p.name }
        return nil
    }

    mutating func markProjectFile(_ id: UUID, known: Bool) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].fileKnown = known
    }

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

    /// True when any colour in the palette has notes written on it.
    func hasNotes(_ id: UUID) -> Bool { swatch(id)?.entries.contains { $0.note != nil } ?? false }

    /// A copy of a palette put at `index` in `project` (nil = the loose Palettes list). The original
    /// stays where it is, untouched; the two are separate from then on. The copy keeps the name,
    /// the colours and their order, each colour's own name, the palette's tags and its pairings.
    /// Notes go with it only when asked for: they are one project's words on its colours.
    @discardableResult
    mutating func copyPalette(_ id: UUID, to project: UUID?, index: Int = Int.max, withNotes: Bool, at date: Date = Date()) -> UUID? {
        guard let source = swatch(id) else { return nil }
        if let p = project, self.project(p) == nil { return nil }
        var copy = Swatch(id: UUID(), name: source.name, createdAt: date, entries: source.entries.map { entry in
            var e = entry
            if !withNotes { e.note = nil; e.noteChangedAt = nil }
            return e
        })
        copy.isCustom = source.isCustom
        if let styles = source.styles {
            copy.styles = styles.map { TypeStyle(id: UUID(), name: $0.name, ink: $0.ink, paper: $0.paper, heading: $0.heading,
                                                 body: $0.body, headingFont: $0.headingFont, bodyFont: $0.bodyFont) }
            copy.stylesChangedAt = date
        }
        copy.copiedFrom = id
        swatches.append(copy)
        move(copy.id, to: project, index: index, at: date)
        // Through the usual door, so a tag that belongs to another project is not carried into this one.
        if let tags = source.tags { setTags(ofPalette: copy.id, tags, at: date) }
        // The copy works to the same profile as the original, unless its new home says otherwise later.
        if let own = source.profile, let i = swatches.firstIndex(where: { $0.id == copy.id }) { swatches[i].profile = own; swatches[i].profileChangedAt = date }
        return copy.id
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

    /// The projects a colour sits in, through the palettes that hold it.
    func projects(holding hex: String) -> Set<UUID> {
        Set(swatches.filter { s in s.entries.contains { $0.hex == hex } }.compactMap { $0.projectID })
    }

    /// The projects every one of the colours sits in: where a tag has to belong to suit them all.
    func projects(holdingAll hexes: [String]) -> Set<UUID> {
        guard let first = hexes.first else { return [] }
        return hexes.dropFirst().reduce(projects(holding: first)) { $0.intersection(projects(holding: $1)) }
    }

    /// Whether something in `projects` may wear the tag: a global tag always, a project's tag only inside that project.
    func mayWear(_ tag: String, in projects: Set<UUID>) -> Bool {
        guard let home = project(ofTag: tag) else { return true }
        return projects.contains(home)
    }

    /// `tags` without the project tags that do not belong here. One already worn is left alone.
    private func allowed(_ tags: [String], in projects: Set<UUID>, worn: [String]) -> [String] {
        let have = Set(worn.map { $0.lowercased() })
        return tags.filter { have.contains($0.lowercased()) || mayWear($0, in: projects) }
    }

    mutating func setTags(ofPalette id: UUID, _ raw: [String], at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return }
        let tags = allowed(Library.cleanTags(raw), in: Set([swatches[i].projectID].compactMap { $0 }), worn: swatches[i].tagList)
        guard tags != swatches[i].tagList else { return }
        swatches[i].tags = tags.isEmpty ? nil : tags
        swatches[i].tagsChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    mutating func setTags(ofColour hex: String, _ raw: [String], at date: Date = Date()) {
        guard let i = colours.firstIndex(where: { $0.hex == hex }) else { return }
        let tags = allowed(Library.cleanTags(raw), in: projects(holding: hex), worn: colours[i].tags ?? [])
        guard tags != (colours[i].tags ?? []) else { return }
        colours[i].tags = tags.isEmpty ? nil : tags
        colours[i].tagsChangedAt = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.up))
    }

    // MARK: Swatch names

    /// The user's own name for a colour in a palette, if they gave it one.
    func customName(of hex: String, in palette: UUID?) -> String? {
        palette.flatMap { swatch($0)?.entries.first { $0.hex == hex }?.name }
    }

    /// What the colour is called in a palette: the user's name for it there, or the standard one.
    func name(of hex: String, in palette: UUID?) -> String {
        customName(of: hex, in: palette) ?? colourName(hex)
    }

    /// Names the colour within one palette. Blank, or the standard name itself, goes back to the standard name.
    mutating func setName(_ raw: String?, of hex: String, in palette: UUID, at date: Date = Date()) {
        guard let s = swatches.firstIndex(where: { $0.id == palette }),
              let e = swatches[s].entries.firstIndex(where: { $0.hex == hex }) else { return }
        let typed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = typed.isEmpty || typed == colourName(hex) ? nil : typed
        guard swatches[s].entries[e].name != name else { return }
        swatches[s].entries[e].name = name
        swatches[s].entries[e].nameChangedAt = date
    }

    /// The description of a colour in a palette, if one has been written.
    func note(of hex: String, in palette: UUID?) -> String? {
        palette.flatMap { swatch($0)?.entries.first { $0.hex == hex }?.note }
    }

    /// Writes the description of a colour within one palette. Blank removes it.
    mutating func setNote(_ raw: String?, of hex: String, in palette: UUID, at date: Date = Date()) {
        guard let s = swatches.firstIndex(where: { $0.id == palette }),
              let e = swatches[s].entries.firstIndex(where: { $0.hex == hex }) else { return }
        let typed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note: String? = typed.isEmpty ? nil : typed
        guard swatches[s].entries[e].note != note else { return }
        swatches[s].entries[e].note = note
        swatches[s].entries[e].noteChangedAt = date
    }

    /// Every tag: those in use on swatches or palettes, and those made in the tag editor. Sorted.
    var allTags: [String] {
        var seen: [String: String] = [:]
        let made = tagInfo.filter { $0.removed != true }.map { $0.name }
        for t in made + colours.flatMap({ $0.tags ?? [] }) + swatches.flatMap({ $0.tagList }) where seen[t.lowercased()] == nil { seen[t.lowercased()] = t }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The tag's colour and scope, if it has been given any.
    func info(forTag name: String) -> TagInfo? {
        tagInfo.first { $0.name.lowercased() == name.lowercased() && $0.removed != true }
    }

    /// The project a tag belongs to, while that project still exists; nil is global.
    func project(ofTag name: String) -> UUID? {
        info(forTag: name)?.projectID.flatMap { project($0)?.id }
    }

    /// The tags to offer when tagging something in `project` (nil = outside any project): the
    /// global ones and that project's own.
    func tags(offeredIn project: UUID?) -> [String] {
        allTags.filter { let home = self.project(ofTag: $0); return home == nil || home == project }
    }

    /// Makes the tag, or changes its colour and scope.
    mutating func setTag(_ raw: String, colour: String?, project: UUID?, at date: Date = Date()) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let fresh = TagInfo(name: name, colour: colour.flatMap(normaliseHex), projectID: project, removed: nil, changedAt: date)
        if let i = tagInfo.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            var kept = fresh
            kept.name = tagInfo[i].removed == true ? name : tagInfo[i].name
            if tagInfo[i].colour != kept.colour || tagInfo[i].projectID != kept.projectID || tagInfo[i].removed == true { tagInfo[i] = kept }
        } else {
            tagInfo.append(fresh)
        }
    }

    /// Changes the tag's name wherever it is worn. Renaming onto an existing tag merges the two.
    @discardableResult
    mutating func renameTag(_ old: String, to raw: String, at date: Date = Date()) -> Bool {
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old, allTags.contains(where: { $0.lowercased() == old.lowercased() }) else { return false }
        func swap(_ tags: [String]) -> [String] { Library.cleanTags(tags.map { $0.lowercased() == old.lowercased() ? new : $0 }) }
        for i in colours.indices where (colours[i].tags ?? []).contains(where: { $0.lowercased() == old.lowercased() }) {
            setTags(ofColour: colours[i].hex, swap(colours[i].tags ?? []), at: date)
        }
        for i in swatches.indices where swatches[i].tagList.contains(where: { $0.lowercased() == old.lowercased() }) {
            setTags(ofPalette: swatches[i].id, swap(swatches[i].tagList), at: date)
        }
        let was = info(forTag: old)
        if new.lowercased() != old.lowercased() {
            if let i = tagInfo.firstIndex(where: { $0.name.lowercased() == old.lowercased() }) { tagInfo[i].removed = true; tagInfo[i].changedAt = date }
            // The tag it merges into keeps its own colour and scope; a new name inherits the old one's.
            if info(forTag: new) == nil { setTag(new, colour: was?.colour, project: was?.projectID, at: date) }
        } else if let i = tagInfo.firstIndex(where: { $0.name.lowercased() == old.lowercased() }) {
            tagInfo[i].name = new
            tagInfo[i].changedAt = date
        }
        return true
    }

    /// Takes the tag off everything that wears it and forgets its colour and scope.
    mutating func deleteTag(_ name: String, at date: Date = Date()) {
        let gone = name.lowercased()
        for i in colours.indices where (colours[i].tags ?? []).contains(where: { $0.lowercased() == gone }) {
            setTags(ofColour: colours[i].hex, (colours[i].tags ?? []).filter { $0.lowercased() != gone }, at: date)
        }
        for i in swatches.indices where swatches[i].tagList.contains(where: { $0.lowercased() == gone }) {
            setTags(ofPalette: swatches[i].id, swatches[i].tagList.filter { $0.lowercased() != gone }, at: date)
        }
        if let i = tagInfo.firstIndex(where: { $0.name.lowercased() == gone }) {
            tagInfo[i].removed = true
            tagInfo[i].changedAt = date
        } else {
            tagInfo.append(TagInfo(name: name, colour: nil, projectID: nil, removed: true, changedAt: date))
        }
    }

    /// What wears the tag: swatches tagged themselves, and palettes tagged as a whole.
    func uses(ofTag name: String) -> (swatches: [String], palettes: [Swatch]) {
        let t = name.lowercased()
        return (colours.filter { ($0.tags ?? []).contains { $0.lowercased() == t } }.map { $0.hex },
                swatches.filter { $0.tagList.contains { $0.lowercased() == t } })
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
        guard let hex = normaliseHex(raw) else {
            // A colour with a key of its own: already here, or known from another library and taken in whole.
            if colours.contains(where: { $0.hex == raw }) { return raw }
            guard let known = ColourKeys.definition(of: raw) else { return nil }
            colours.append(Colour(hex: raw, pickedAt: after([deletedAt(.colour, raw)], date), source: known.source, master: known.master, kind: known.kind))
            return raw
        }
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
/// A name made safe to be a file name on a Mac, on Windows and on Linux alike. What none of
/// them allows becomes a hyphen; a name Windows keeps for itself ("CON", "AUX", "COM1"…) gains an
/// underscore; and nothing ends in a dot or a space, which Windows drops. The real name is kept
/// inside the file, so nothing depends on this one being exact.
func filesystemName(_ raw: String) -> String {
    let bad = CharacterSet(charactersIn: "/:\\*?\"<>|").union(.controlCharacters).union(.newlines)
    var cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.map { bad.contains($0) ? "-" : $0 }))
        .precomposedStringWithCanonicalMapping   // one spelling of an accented letter, whichever system wrote it
        .trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned = String(cleaned.prefix(100))
    while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") { cleaned.removeLast() }
    if cleaned.isEmpty { return "Untitled" }
    let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
    let stem = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? cleaned
    return reserved.contains(stem.uppercased()) ? cleaned + "_" : cleaned
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

/// Writes library.json and the text files into a new "\(Brand.name) Export" folder under `folder`.
/// Returns the folder written. Never overwrites: a second export gets "... Export 2".
func writeExport(_ lib: Library, to folder: URL, by order: SortOrder) throws -> URL {
    let fm = FileManager.default
    let existing = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
    let dir = folder.appendingPathComponent(uniqueName("\(Brand.name) Export", among: existing))
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

    /// The one file an earlier version kept everything in. Read once, then kept as a backup.
    let earlierURL: URL
    /// The folder projects are kept under; nil puts them in "Projects" beside the catalogue.
    let projectsFolder: URL?
    /// Projects the catalogue lists whose files could not be reached at the last load. They are
    /// shown as unavailable, and never written over.
    private(set) var unavailable = Set<UUID>()
    private var written: [UUID: Data] = [:]

    /// `name` is the catalogue's, which its file is named for.
    init(directory: URL, legacyURL: URL?, previousURL: URL? = nil, name: String? = nil, projectsFolder: URL? = nil) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = CatalogueFiles.index(in: directory)
            ?? directory.appendingPathComponent(filesystemName(name ?? directory.lastPathComponent) + "." + ColourFiles.catalogue)
        self.earlierURL = directory.appendingPathComponent("library.json")
        self.projectsFolder = projectsFolder
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
        let fm = FileManager.default, stamp = Int(Date().timeIntervalSince1970)
        if fm.fileExists(atPath: url.path) {
            if let loaded = try? CatalogueFiles.read(index: url, master: projectsFolder) {
                unavailable = loaded.unavailable
                return loaded.library
            }
            // Never overwrite a file we could not read — move it aside for recovery.
            let aside = url.deletingLastPathComponent().appendingPathComponent("unreadable-\(stamp)." + ColourFiles.catalogue + ".txt")
            try? fm.moveItem(at: url, to: aside)
            quarantinedFile = aside
        } else if fm.fileExists(atPath: earlierURL.path) {
            // A catalogue an earlier version kept in one file: saved as a catalogue of project
            // files, and the one file kept among the backups.
            if let data = try? Data(contentsOf: earlierURL), let lib = try? decoder.decode(Library.self, from: data) {
                try save(lib, remaking: true)
                let backups = url.deletingLastPathComponent().appendingPathComponent("Backups")
                try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
                try? fm.moveItem(at: earlierURL, to: backups.appendingPathComponent("library before catalogue files \(stamp).json"))
                return lib
            }
            let aside = url.deletingLastPathComponent().appendingPathComponent("library.unreadable-\(stamp).json")
            try? fm.moveItem(at: earlierURL, to: aside)
            quarantinedFile = aside
        }
        var lib = loadPrevious() ?? Library()
        lib.mergeLegacy(loadLegacy())
        try save(lib)
        return lib
    }

    func save(_ lib: Library) throws { try save(lib, remaking: false) }

    private func save(_ lib: Library, remaking: Bool) throws {
        do {
            try CatalogueFiles.write(lib, index: url, master: projectsFolder, remaking: remaking, skipping: unavailable, written: &written)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.saveFailed(url, error)
        }
    }

    /// Re-reads from disk before changing anything, so picks made by the
    /// hotkey process while the window is open are never overwritten.
    @discardableResult
    func mutate(_ body: (inout Library) throws -> Void) throws -> Library {
        var lib = try load()
        try body(&lib)
        try save(lib)
        return lib
    }
}
