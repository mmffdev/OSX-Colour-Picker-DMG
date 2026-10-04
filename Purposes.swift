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
