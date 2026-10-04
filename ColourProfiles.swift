import Foundation

// ---------- Colour profiles ----------
//
// A colour profile is a named set of channels: the media a piece of work is delivered to, such as
// "sRGB and Display P3" or "sRGB, and print on coated FOGRA39". A palette selects one, because a
// project often holds a web palette and a print palette that need different channels. A palette
// with none uses its project's; a project with none uses the house default from Settings.
//
// The house's profiles are kept in one plain file on this Mac. A profile a library uses is copied
// into that library, and into the project's own file, so both stay whole when they travel.

struct ColourProfile: Codable, Equatable {
    let id: UUID
    var name: String
    var channels: [ProfileChannel]
    /// When it was last changed. With the id, this is what a sync goes by.
    var changedAt: Date

    func holds(_ space: String) -> Bool { channels.contains { $0.space == space } }
    var print: ProfileChannel? { channels.first { $0.isPrint } }

    /// The channels in words: "sRGB, Display P3, Print: Generic CMYK".
    var summary: String { channels.isEmpty ? "No Channels" : channels.map { $0.name }.joined(separator: ", ") }
}

enum ColourProfiles {
    private static func made(_ id: String, _ name: String, _ spaces: [RGBSpace], print: Bool = false) -> ColourProfile {
        var channels = spaces.map { ProfileChannel(space: $0.rawValue) }
        if print { channels.append(ProfileChannel(space: ProfileChannel.print, press: PressProfiles.generic, intent: .relative)) }
        return ColourProfile(id: UUID(uuidString: id)!, name: name, channels: channels, changedAt: Date(timeIntervalSince1970: 0))
    }

    /// What every Mac starts with. Their ids are fixed, so two Macs mean the same profile by them.
    static let starters: [ColourProfile] = [
        made("C0100000-0000-4000-8000-000000000001", "Screen And Web", [.srgb, .displayP3]),
        made("C0100000-0000-4000-8000-000000000002", "Print", [.srgb], print: true),
        made("C0100000-0000-4000-8000-000000000003", "Video", [.rec709, .rec2020, .displayP3]),
        made("C0100000-0000-4000-8000-000000000004", "Rendering And Effects", [.acescg, .linearSRGB, .rec709, .srgb]),
        made("C0100000-0000-4000-8000-000000000005", "Every Channel", RGBSpace.allCases, print: true),
    ]

    static var url: URL { Catalogues.standard.root.appendingPathComponent("colour-profiles.json") }

    /// The house's profiles: what was saved, or the starters when nothing has been.
    static func load(from url: URL = url) -> [ColourProfile] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: url), let saved = try? d.decode([ColourProfile].self, from: data), !saved.isEmpty else { return starters }
        return saved
    }

    static func save(_ profiles: [ColourProfile], to url: URL = url) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(profiles).write(to: url, options: .atomic)
    }

    /// The profile a palette with no choice of its own, in a project with none, falls back to.
    static var houseDefault: UUID? {
        get { preferences.string(forKey: "colourProfile.default").flatMap(UUID.init(uuidString:)) }
        set { preferences.set(newValue?.uuidString, forKey: "colourProfile.default") }
    }
}

/// Where the profile a palette is using came from.
enum ProfileOrigin: Equatable { case palette, project, house }

extension Library {
    /// A profile this library has a copy of.
    func profileRecord(_ id: UUID) -> ColourProfile? { colourProfiles.first { $0.id == id } }

    /// Keeps a copy of a profile in the library, replacing an older copy of the same one.
    mutating func keep(profile: ColourProfile) {
        if let i = colourProfiles.firstIndex(where: { $0.id == profile.id }) {
            if colourProfiles[i] != profile { colourProfiles[i] = profile }
        } else {
            colourProfiles.append(profile)
        }
    }

    /// Gives a palette a profile of its own; nil goes back to its project's, or the house's.
    mutating func setProfile(_ profile: ColourProfile?, ofPalette id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), swatches[i].profile != profile?.id else { return }
        if let profile = profile { keep(profile: profile) }
        swatches[i].profile = profile?.id
        swatches[i].profileChangedAt = date
    }

    /// Gives a project its profile, which every palette in it uses unless it has its own.
    mutating func setProfile(_ profile: ColourProfile?, ofProject id: UUID, at date: Date = Date()) {
        guard let i = projects.firstIndex(where: { $0.id == id }), projects[i].profile != profile?.id else { return }
        if let profile = profile { keep(profile: profile) }
        projects[i].profile = profile?.id
        projects[i].profileChangedAt = date
    }

    /// The profile a palette works to: its own, else its project's, else the house default, else the first on offer.
    /// A profile is read from the library's own copy, and from the house's when the library has none.
    func profile(forPalette id: UUID?, house: [ColourProfile], houseDefault: UUID?) -> (profile: ColourProfile, origin: ProfileOrigin) {
        func find(_ id: UUID?) -> ColourProfile? { id.flatMap { newest($0, house: house) } }
        let palette = id.flatMap { swatch($0) }
        if let own = find(palette?.profile) { return (own, .palette) }
        if let projects = find(palette?.projectID.flatMap { project($0)?.profile }) { return (projects, .project) }
        return (find(houseDefault) ?? house.first ?? ColourProfiles.starters[0], .house)
    }

    /// The profile a project's palettes use by default.
    func profile(forProject id: UUID, house: [ColourProfile], houseDefault: UUID?) -> (profile: ColourProfile, origin: ProfileOrigin) {
        if let want = project(id)?.profile, let found = newest(want, house: house) { return (found, .project) }
        return (houseDefault.flatMap { want in house.first { $0.id == want } } ?? house.first ?? ColourProfiles.starters[0], .house)
    }

    /// A profile by id: the library's own copy or the house's, whichever was changed later, so an
    /// edit made in Settings shows at once and a library still works on a Mac that lacks the profile.
    func newest(_ id: UUID, house: [ColourProfile]) -> ColourProfile? {
        let mine = profileRecord(id), theirs = house.first { $0.id == id }
        guard let a = mine, let b = theirs else { return mine ?? theirs }
        return b.changedAt > a.changedAt ? b : a
    }

    /// A colour's full definition. One known only by its hex has the hex as its sRGB source.
    func definition(of hex: String) -> ColourDefinition? {
        colours.first { $0.hex == hex }?.definition ?? ColourKeys.definition(of: hex) ?? ColourDefinition.of(hex: hex)
    }
}
