import Foundation

// ---------- Purposes ----------
//
// What a palette is for. A palette holds its colours once; each purpose it serves is a way of
// looking at those same colours for one kind of work, with settings of its own. A palette can
// serve several purposes at once, and it serves a purpose exactly when it has that purpose's
// settings: on disk, a file beside the palette named for it, "Autumn Range.colprint".

enum Purpose: String, Codable, CaseIterable {
    case web, print, photo, video, cine
    case threeD = "3d"

    var title: String {
        switch self {
        case .web: return "Screen & Web"
        case .print: return "Print"
        case .photo: return "Photography"
        case .video: return "Video & Broadcast"
        case .cine: return "Cinema & VFX"
        case .threeD: return "3D & Games"
        }
    }

    /// Who it is for, in a line.
    var about: String {
        switch self {
        case .web: return "Interfaces, products and the web: sRGB, Display P3 and contrast"
        case .print: return "Brand, packaging and editorial: the press, ink builds and what it cannot print"
        case .photo: return "Photography and retouching: Adobe RGB (1998), ProPhoto and screen to print"
        case .video: return "Editing, grading and streaming delivery: Rec. 709, Rec. 2020 and legal range"
        case .cine: return "Film, grading and effects: ACES, camera encodings and DCI-P3"
        case .threeD: return "3D and game engines: linear values for shaders and textures"
        }
    }

    var symbol: String {
        switch self {
        case .web: return "macwindow"
        case .print: return "printer"
        case .photo: return "camera"
        case .video: return "play.rectangle"
        case .cine: return "film"
        case .threeD: return "cube"
        }
    }

    /// The profile a palette works to for this purpose until it is given another.
    var starter: ColourProfile {
        let at: Int
        switch self {
        case .web: at = 0
        case .print: at = 1
        case .video: at = 2
        case .threeD: at = 3
        case .photo: at = 5
        case .cine: at = 6
        }
        return ColourProfiles.starters[at]
    }

    /// The values a card shows for this purpose until others are chosen.
    var starterLabels: [ColourFormat] {
        switch self {
        case .web: return [.hex, .rgb, .hsl, .p3]
        case .print: return [.hex, .cmyk, .lab]
        case .photo: return [.hex, .p3, .adobeRGB, .lab]
        case .video: return [.hex, .rgb, .rec2020]
        case .cine: return [.p3, .rec2020, .lab]
        case .threeD: return [.hex, .rgb, .hsv]
        }
    }

    /// The extension of its settings file: "colweb", "colprint" and so on.
    var fileExtension: String { "col" + rawValue }

    static func of(fileExtension: String) -> Purpose? { allCases.first { $0.fileExtension == fileExtension.lowercased() } }
}

/// A palette's settings for one purpose. Its being there is what makes the palette serve that
/// purpose; taking a purpose off keeps the record, marked removed, so a sync does not bring it back.
struct PurposeConfig: Codable, Equatable {
    let id: UUID
    var purpose: Purpose
    /// The colour profile the palette works to for this purpose; nil is the palette's own.
    var profile: UUID? = nil
    /// The values each card shows for this purpose, by ColourFormat; nil is the purpose's own set.
    var labels: [String]? = nil
    var removed: Bool? = nil
    /// With the id, this is what a sync goes by.
    var changedAt: Date

    var isLive: Bool { removed != true }
}

extension Swatch {
    /// The purposes the palette serves, in the order they are always listed.
    var purposeList: [Purpose] {
        let live = Set((purposes ?? []).filter { $0.isLive }.map { $0.purpose })
        return Purpose.allCases.filter { live.contains($0) }
    }

    func config(for purpose: Purpose) -> PurposeConfig? { purposes?.first { $0.purpose == purpose && $0.isLive } }
}

extension Library {
    /// Puts a purpose on a palette, or takes it off. Its settings are kept either way, so a
    /// purpose put back comes back as it was.
    mutating func setPurpose(_ purpose: Purpose, on: Bool, ofPalette id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }) else { return }
        var list = swatches[i].purposes ?? []
        if let at = list.firstIndex(where: { $0.purpose == purpose }) {
            guard list[at].isLive != on else { return }
            list[at].removed = on ? nil : true
            list[at].changedAt = date
        } else {
            guard on else { return }
            list.append(PurposeConfig(id: UUID(), purpose: purpose, changedAt: date))
        }
        // Always in the one order, so the same purposes are the same list whichever was chosen first.
        swatches[i].purposes = Purpose.allCases.compactMap { purpose in list.first { $0.purpose == purpose } }
    }

    /// Turns a palette to one purpose, or to none. A purpose chosen for the first time is given
    /// its settings, which is what marks the palette as set up for it.
    mutating func choosePurpose(_ purpose: Purpose?, ofPalette id: UUID, at date: Date = Date()) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), swatches[i].purpose != purpose else { return }
        if let purpose = purpose { setPurpose(purpose, on: true, ofPalette: id, at: date) }
        swatches[i].purpose = purpose
        swatches[i].purposeChangedAt = date
    }

    /// Changes a palette's settings for a purpose it serves.
    mutating func setPurposeSettings(_ purpose: Purpose, ofPalette id: UUID, at date: Date = Date(), _ change: (inout PurposeConfig) -> Void) {
        guard let i = swatches.firstIndex(where: { $0.id == id }), var list = swatches[i].purposes,
              let at = list.firstIndex(where: { $0.purpose == purpose && $0.isLive }) else { return }
        var changed = list[at]
        change(&changed)
        guard changed != list[at] else { return }
        changed.changedAt = date
        list[at] = changed
        swatches[i].purposes = list
    }

    /// Gives a palette a profile for one purpose; nil goes back to the purpose's own.
    mutating func setProfile(_ profile: ColourProfile?, for purpose: Purpose, ofPalette id: UUID, at date: Date = Date()) {
        if let profile = profile { keep(profile: profile) }
        setPurposeSettings(purpose, ofPalette: id, at: date) { $0.profile = profile?.id }
    }

    /// What a profile makes of some colours, in a line: how many it holds, and which channels cannot hold the rest.
    func verdict(on keys: [String], for profile: ColourProfile) -> (holds: Bool, tag: String, detail: String) {
        let colours = keys.compactMap { definition(of: $0) }
        guard !colours.isEmpty else { return (true, "No Colours", "Nothing to check yet.") }
        var failing: [String] = []
        var out = Set<Int>()
        for channel in profile.channels {
            let missed = colours.indices.filter { !Rendering.of(colours[$0], in: channel).inRange }
            if !missed.isEmpty { failing.append("\(channel.name) cannot hold \(missed.count)"); out.formUnion(missed) }
        }
        if failing.isEmpty { return (true, "All \(colours.count) Hold", "Every colour is in range for " + profile.summary + ".") }
        return (false, "\(out.count) Of \(colours.count) Out Of Range", failing.joined(separator: "  \u{00B7}  "))
    }

    /// Two Macs' purposes for one palette, joined: for each purpose, whichever was changed last.
    static func merged(_ local: [PurposeConfig]?, _ remote: [PurposeConfig]?) -> [PurposeConfig]? {
        guard local != nil || remote != nil else { return nil }
        var out: [PurposeConfig] = []
        for purpose in Purpose.allCases {
            let l = local?.first { $0.purpose == purpose }, r = remote?.first { $0.purpose == purpose }
            switch (l, r) {
            case let (l?, r?): out.append(r.changedAt > l.changedAt ? r : l)
            case let (l?, nil): out.append(l)
            case let (nil, r?): out.append(r)
            default: break
            }
        }
        return out
    }
}
