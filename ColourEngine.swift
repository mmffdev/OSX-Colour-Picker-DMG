import AppKit

// ---------- The colour engine ----------
//
// One colour, defined once, proven everywhere. A colour is held as a MASTER that belongs to no
// device: CIE XYZ adapted to D50, in floating point, with no ceiling. Everything a medium needs,
// a hex, a CMYK build, a video code value, is a RENDERING of that master, with a figure for how
// faithful it is. COLOUR-MANAGEMENT.md at the repository root is the design this follows.
//
// Screen, video and rendering spaces are worked out here with plain matrix maths, so the same
// master gives the same numbers on every Mac and values above white are kept. Press profiles are
// ICC files and go through the system's colour engine, which is the only thing that can read them.

/// CIE XYZ adapted to D50, relative: the white of a surface is Y = 1. A light can exceed it.
struct XYZ: Codable, Equatable {
    var x: Double, y: Double, z: Double
    /// The D50 white every ICC profile is built round.
    static let d50 = XYZ(x: 0.96422, y: 1.0, z: 0.82521)
}

/// CIE L*a*b* against the D50 white: the space colours are compared in.
struct LabD50: Equatable {
    var l: Double, a: Double, b: Double
}

/// A surface has no brightness of its own and depends on the light it is seen under. A light is
/// emitted, by a screen or a render, and has a real brightness that can exceed white.
enum ColourKind: String, Codable { case surface, light }

/// The colour exactly as it was given: the space it was given in, and its numbers in that space.
struct ColourSource: Codable, Equatable {
    /// An RGBSpace's raw value, or "cmyk", "lab", "xyz".
    var space: String
    var values: [Double]
    /// For a CMYK source: the press profile the build belongs to.
    var press: String? = nil
}

/// A colour's full definition: what was given, the master worked out from it, and its kind.
struct ColourDefinition: Equatable {
    var source: ColourSource
    var master: XYZ
    var kind: ColourKind

    /// A colour known only by its sRGB hex: the hex is the source.
    static func of(hex: String) -> ColourDefinition? {
        guard let c = rgbComponents(hex) else { return nil }
        let values = [c.r, c.g, c.b]
        return ColourDefinition(source: ColourSource(space: RGBSpace.srgb.rawValue, values: values),
                                master: RGBSpace.srgb.master(of: values), kind: .surface)
    }

    /// The source in words: "sRGB  #E93627", "Display P3  0.917, 0.200, 0.139".
    var sourceText: String {
        if let space = RGBSpace(rawValue: source.space), source.values.count == 3 {
            return space.name + "  " + space.text(source.values)
        }
        return source.space.uppercased() + "  " + source.values.map { String(format: "%.4f", $0) }.joined(separator: ", ")
    }

    var masterText: String { String(format: "XYZ  %.4f, %.4f, %.4f  (D50)", master.x, master.y, master.z) }
}

// MARK: Three-by-three maths

typealias Matrix3 = [[Double]]

func multiply(_ m: Matrix3, _ v: [Double]) -> [Double] { m.map { $0[0] * v[0] + $0[1] * v[1] + $0[2] * v[2] } }

func multiply(_ a: Matrix3, _ b: Matrix3) -> Matrix3 {
    (0..<3).map { i in (0..<3).map { j in a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] } }
}

func inverse(_ m: Matrix3) -> Matrix3 {
    let a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2]
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]
}

/// Bradford chromatic adaptation: carries XYZ from one white to another. The standard method, exact both ways.
func bradford(from: (x: Double, y: Double), to: (x: Double, y: Double)) -> Matrix3 {
    let cone: Matrix3 = [[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367], [0.0389, -0.0685, 1.0296]]
    func white(_ w: (x: Double, y: Double)) -> [Double] { [w.x / w.y, 1, (1 - w.x - w.y) / w.y] }
    let s = multiply(cone, white(from)), d = multiply(cone, white(to))
    let scale: Matrix3 = [[d[0] / s[0], 0, 0], [0, d[1] / s[1], 0], [0, 0, d[2] / s[2]]]
    return multiply(inverse(cone), multiply(scale, cone))
}

// MARK: Screen, video and rendering spaces

/// A space that mixes its colours from three primaries: where each primary and its white sit, and
/// how its numbers are encoded.
enum RGBSpace: String, CaseIterable, Codable {
    case srgb, displayP3, adobeRGB, rec709, rec2020, acescg

    var name: String {
        switch self {
        case .srgb: return "sRGB"
        case .displayP3: return "Display P3"
        case .adobeRGB: return "Adobe RGB"
        case .rec709: return "Rec. 709"
        case .rec2020: return "Rec. 2020"
        case .acescg: return "ACEScg"
        }
    }

    /// Who uses it, in a line.
    var about: String {
        switch self {
        case .srgb: return "The web and most screens"
        case .displayP3: return "Recent Apple screens; wider reds and greens"
        case .adobeRGB: return "Photography and print preparation"
        case .rec709: return "HD video, gamma 2.4"
        case .rec2020: return "Ultra HD video, gamma 2.4"
        case .acescg: return "Rendering and visual effects; linear, no ceiling"
        }
    }

    /// The channel it belongs to.
    var channel: String {
        switch self {
        case .srgb, .displayP3, .adobeRGB: return "Screen"
        case .rec709, .rec2020: return "Video"
        case .acescg: return "Rendering"
        }
    }

    private var primaries: (r: (Double, Double), g: (Double, Double), b: (Double, Double), white: (x: Double, y: Double)) {
        let d65 = (x: 0.3127, y: 0.3290)
        switch self {
        case .srgb, .rec709: return ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060), d65)
        case .displayP3: return ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060), d65)
        case .adobeRGB: return ((0.640, 0.330), (0.210, 0.710), (0.150, 0.060), d65)
        case .rec2020: return ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046), d65)
        case .acescg: return ((0.713, 0.293), (0.165, 0.830), (0.128, 0.044), (x: 0.32168, y: 0.33767))
        }
    }

    /// Linear values of this space to the master: the primaries' own XYZ, scaled to the white, then adapted to D50.
    var toMaster: Matrix3 { RGBSpace.matrices[self]!.to }
    var fromMaster: Matrix3 { RGBSpace.matrices[self]!.from }

    private static let matrices: [RGBSpace: (to: Matrix3, from: Matrix3)] = {
        var out: [RGBSpace: (to: Matrix3, from: Matrix3)] = [:]
        for space in RGBSpace.allCases {
            let p = space.primaries
            func column(_ c: (Double, Double)) -> [Double] { [c.0 / c.1, 1, (1 - c.0 - c.1) / c.1] }
            let r = column(p.r), g = column(p.g), b = column(p.b)
            let raw: Matrix3 = [[r[0], g[0], b[0]], [r[1], g[1], b[1]], [r[2], g[2], b[2]]]
            let white = [p.white.x / p.white.y, 1, (1 - p.white.x - p.white.y) / p.white.y]
            let s = multiply(inverse(raw), white)
            let native: Matrix3 = raw.map { [$0[0] * s[0], $0[1] * s[1], $0[2] * s[2]] }
            let to = multiply(bradford(from: p.white, to: (x: 0.34567, y: 0.35850)), native)
            out[space] = (to, inverse(to))
        }
        return out
    }()

    /// An encoded value to a linear one. Mirrored about zero, so a value outside the range survives.
    func linear(_ v: Double) -> Double {
        let sign: Double = v < 0 ? -1 : 1, a = abs(v)
        switch self {
        case .srgb, .displayP3: return sign * (a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4))
        case .adobeRGB: return sign * pow(a, 563.0 / 256.0)
        case .rec709, .rec2020: return sign * pow(a, 2.4)
        case .acescg: return v
        }
    }

    func encoded(_ v: Double) -> Double {
        let sign: Double = v < 0 ? -1 : 1, a = abs(v)
        switch self {
        case .srgb, .displayP3: return sign * (a <= 0.0031308 ? 12.92 * a : 1.055 * pow(a, 1 / 2.4) - 0.055)
        case .adobeRGB: return sign * pow(a, 256.0 / 563.0)
        case .rec709, .rec2020: return sign * pow(a, 1 / 2.4)
        case .acescg: return v
        }
    }

    /// The master of a colour given in this space, as encoded values 0 to 1.
    func master(of values: [Double]) -> XYZ {
        let xyz = multiply(toMaster, values.map(linear))
        return XYZ(x: xyz[0], y: xyz[1], z: xyz[2])
    }

    /// The master expressed in this space, encoded and not clipped: a value below 0 or above 1
    /// says the space cannot show the colour.
    func values(of master: XYZ) -> [Double] { linearValues(of: master).map(encoded) }

    /// The same before encoding: how much of each primary the colour takes.
    func linearValues(of master: XYZ) -> [Double] { multiply(fromMaster, [master.x, master.y, master.z]) }

    /// How far outside 0 to 1 an amount of a primary may fall and still count as in range: two
    /// parts in a thousand, which no eye sees. Display P3's red sits that far outside Rec. 2020.
    static let slack = 0.002

    /// Values as this space's users write them.
    func text(_ v: [Double]) -> String {
        func whole(_ x: Double, _ top: Double) -> Int { Int((min(max(x, 0), 1) * top).rounded()) }
        switch self {
        case .srgb: return String(format: "#%02X%02X%02X", whole(v[0], 255), whole(v[1], 255), whole(v[2], 255))
        case .displayP3: return v.map { String(format: "%.3f", $0) }.joined(separator: ", ")
        case .adobeRGB: return v.map { "\(whole($0, 255))" }.joined(separator: ", ")
        case .rec709, .rec2020: return v.map { "\(whole($0, 1023))" }.joined(separator: ", ") + "  (10-bit, full range)"
        case .acescg: return v.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        }
    }
}

// MARK: Comparing colours

extension XYZ {
    var lab: LabD50 {
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(x / XYZ.d50.x), fy = f(y / XYZ.d50.y), fz = f(z / XYZ.d50.z)
        return LabD50(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }
}

extension LabD50 {
    var xyz: XYZ {
        func inv(_ t: Double) -> Double { t * t * t > 216.0 / 24389 ? t * t * t : (116 * t - 16) / (24389.0 / 27) }
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        return XYZ(x: inv(fx) * XYZ.d50.x, y: inv(fy) * XYZ.d50.y, z: inv(fz) * XYZ.d50.z)
    }
}

/// The colour difference CIEDE2000: 0 is identical, about 1 is the smallest the eye can see, and
/// above 2 two colours side by side are plainly not the same. Used for matching and for proofs.
func deltaE2000(_ p: LabD50, _ q: LabD50) -> Double {
    let rad = Double.pi / 180
    let c1 = hypot(p.a, p.b), c2 = hypot(q.a, q.b)
    let cBar7 = pow((c1 + c2) / 2, 7)
    let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25.0, 7))))
    let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
    let cp1 = hypot(a1, p.b), cp2 = hypot(a2, q.b)
    func hue(_ x: Double, _ y: Double) -> Double {
        if x == 0 && y == 0 { return 0 }
        let h = atan2(y, x) / rad
        return h < 0 ? h + 360 : h
    }
    let h1 = hue(a1, p.b), h2 = hue(a2, q.b)
    let dL = q.l - p.l, dC = cp2 - cp1
    var dh = 0.0
    if cp1 * cp2 != 0 {
        dh = h2 - h1
        if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
    }
    let dH = 2 * sqrt(cp1 * cp2) * sin(dh / 2 * rad)
    let lBar = (p.l + q.l) / 2, cpBar = (cp1 + cp2) / 2
    var hBar = h1 + h2
    if cp1 * cp2 != 0 {
        if abs(h1 - h2) <= 180 { hBar = (h1 + h2) / 2 }
        else if h1 + h2 < 360 { hBar = (h1 + h2 + 360) / 2 }
        else { hBar = (h1 + h2 - 360) / 2 }
    }
    let t = 1 - 0.17 * cos((hBar - 30) * rad) + 0.24 * cos(2 * hBar * rad) + 0.32 * cos((3 * hBar + 6) * rad) - 0.20 * cos((4 * hBar - 63) * rad)
    let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
    let cpBar7 = pow(cpBar, 7)
    let rc = 2 * sqrt(cpBar7 / (cpBar7 + pow(25.0, 7)))
    let sl = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
    let sc = 1 + 0.045 * cpBar
    let sh = 1 + 0.015 * cpBar * t
    let rt = -sin(2 * dTheta * rad) * rc
    return sqrt(pow(dL / sl, 2) + pow(dC / sc, 2) + pow(dH / sh, 2) + rt * (dC / sc) * (dH / sh))
}

// MARK: Rendering intents

/// The rule for bringing a colour a medium cannot show into its range.
///
/// Absolute colorimetric, which shows a colour on the paper's own white, is not here yet: the
/// system's engine will not run it from a master. It needs the paper white read from the profile.
enum RenderingIntent: String, Codable, CaseIterable {
    /// Keeps every colour in range exactly; brings one out of range to the nearest edge. The default for swatches.
    case relative
    /// Compresses everything to fit, shifting even colours in range. For images, not single colours.
    case perceptual

    var name: String {
        switch self {
        case .relative: return "Relative Colorimetric"
        case .perceptual: return "Perceptual"
        }
    }

    var system: CGColorRenderingIntent {
        switch self {
        case .relative: return .relativeColorimetric
        case .perceptual: return .perceptual
        }
    }
}

// MARK: Press profiles

/// The ICC press profiles on this Mac. A CMYK figure means something only with the profile it is for.
enum PressProfiles {
    struct Profile: Equatable {
        let name: String
        let path: String
    }

    /// Where profiles are looked for: the system's folders, the user's, and Adobe's.
    static let folders: [String] = [
        "/System/Library/ColorSync/Profiles", "/Library/ColorSync/Profiles", NSHomeDirectory() + "/Library/ColorSync/Profiles",
        "/Library/Application Support/Adobe/Color/Profiles", "/Library/Application Support/Adobe/Color/Profiles/Recommended",
    ]

    /// The profile every Mac has, used until the user chooses a press.
    static let generic = "Generic CMYK"

    /// Every CMYK profile found, by its own name, sorted.
    static let all: [Profile] = {
        var found: [String: Profile] = [:]
        let fm = FileManager.default
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.lowercased().hasSuffix(".icc") || item.lowercased().hasSuffix(".icm") {
                let path = folder + "/" + item
                guard let data = fm.contents(atPath: path), let space = CGColorSpace(iccData: data as CFData), space.model == .cmyk,
                      let name = NSColorSpace(cgColorSpace: space)?.localizedName, found[name] == nil else { continue }
                found[name] = Profile(name: name, path: path)
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    private static var spaces: [String: CGColorSpace] = [:]

    /// The colour space of a profile by name; nil when the profile is not on this Mac.
    static func space(named name: String) -> CGColorSpace? {
        if let have = spaces[name] { return have }
        guard let profile = all.first(where: { $0.name == name }), let data = FileManager.default.contents(atPath: profile.path),
              let space = CGColorSpace(iccData: data as CFData) else { return nil }
        spaces[name] = space
        return space
    }
}

private let masterSpace = CGColorSpace(name: CGColorSpace.genericXYZ)!

/// A build of the four inks for a master, through a press profile, and what that build looks like.
struct PrintBuild: Equatable {
    /// Cyan, magenta, yellow, black, each 0 to 1.
    let inks: [Double]
    /// The colour the build makes, back in the master's terms.
    let printed: XYZ
    /// The sum of the four inks as a percentage, which a press limits.
    var totalInk: Double { inks.reduce(0, +) * 100 }

    var text: String {
        let names = ["C", "M", "Y", "K"]
        return zip(names, inks).map { "\($0) \(Int(($1 * 100).rounded()))" }.joined(separator: "  ")
    }

    /// Sends a master through the profile and back. Black point compensation is left off: asked
    /// for through this engine it puts ink on pure white, which is wrong, so it waits for a route that can be trusted.
    static func of(_ master: XYZ, press: String, intent: RenderingIntent) -> PrintBuild? {
        guard let space = PressProfiles.space(named: press),
              let colour = CGColor(colorSpace: masterSpace, components: [CGFloat(master.x), CGFloat(master.y), CGFloat(master.z), 1]) else { return nil }
        guard let ink = colour.converted(to: space, intent: intent.system, options: nil), let c = ink.components, c.count >= 4,
              let back = ink.converted(to: masterSpace, intent: .relativeColorimetric, options: nil)?.components, back.count >= 3 else { return nil }
        return PrintBuild(inks: c.prefix(4).map { Double($0) }, printed: XYZ(x: Double(back[0]), y: Double(back[1]), z: Double(back[2])))
    }

    /// The master of a build typed in by hand: what those inks make on that press.
    static func master(ofInks inks: [Double], press: String) -> XYZ? {
        guard inks.count == 4, let space = PressProfiles.space(named: press),
              let colour = CGColor(colorSpace: space, components: inks.map { CGFloat($0) } + [1]),
              let back = colour.converted(to: masterSpace, intent: .relativeColorimetric, options: nil)?.components, back.count >= 3 else { return nil }
        return XYZ(x: Double(back[0]), y: Double(back[1]), z: Double(back[2]))
    }
}

// MARK: Renderings

/// One channel a colour is delivered to: a screen, video or rendering space, or a press.
struct ProfileChannel: Codable, Equatable {
    /// An RGBSpace's raw value, or "print".
    var space: String
    /// For print: the press profile's name.
    var press: String? = nil
    /// For print: how an out-of-range colour is brought in. nil is relative colorimetric.
    var intent: RenderingIntent? = nil

    static let print = "print"
    var isPrint: Bool { space == ProfileChannel.print }
    var rgb: RGBSpace? { RGBSpace(rawValue: space) }

    /// "sRGB", "Print: Coated FOGRA39 (ISO 12647-2:2004)".
    var name: String { rgb?.name ?? "Print: " + (press ?? PressProfiles.generic) }
}

/// A master expressed for one channel: the value to use, and how faithful it is.
struct Rendering: Equatable {
    let channel: ProfileChannel
    /// The value as that channel's users write it; nil when it could not be worked out.
    let value: String?
    /// The colour the channel actually gives, for showing beside the master.
    let shown: XYZ?
    /// The difference from the master, CIEDE2000.
    let difference: Double?
    /// Whether the channel can show the colour as it is.
    let inRange: Bool
    /// A line under the value: the intent and total ink for print, or why nothing could be worked out.
    let detail: String

    /// Above this the rendering is plainly not the master's colour.
    static let visible = 2.0

    static func of(_ definition: ColourDefinition, in channel: ProfileChannel) -> Rendering {
        let master = definition.master
        if let space = channel.rgb {
            let raw = space.values(of: master)
            // A light keeps values above white where the space has no ceiling; everything else stops at the range.
            let open = space == .acescg && definition.kind == .light
            let within = space.linearValues(of: master).allSatisfy { $0 >= -RGBSpace.slack && (open || $0 <= 1 + RGBSpace.slack) }
            let held = raw.map { open ? max($0, 0) : min(max($0, 0), 1) }
            let shown = space.master(of: held)
            return Rendering(channel: channel, value: space.text(held), shown: shown, difference: deltaE2000(master.lab, shown.lab), inRange: within,
                             detail: within ? space.about : "Outside \(space.name): the nearest it can show")
        }
        let press = channel.press ?? PressProfiles.generic, intent = channel.intent ?? .relative
        guard let build = PrintBuild.of(master, press: press, intent: intent) else {
            return Rendering(channel: channel, value: nil, shown: nil, difference: nil, inRange: false, detail: "The profile \u{201C}\(press)\u{201D} is not on this Mac")
        }
        let difference = deltaE2000(master.lab, build.printed.lab)
        return Rendering(channel: channel, value: build.text, shown: build.printed, difference: difference, inRange: difference <= Rendering.visible,
                         detail: "\(intent.name)  \u{00B7}  Total Ink \(Int(build.totalInk.rounded()))%")
    }
}

extension XYZ {
    /// The colour as this screen can show it: sRGB, held in range.
    var display: NSColor {
        let v = RGBSpace.srgb.values(of: self).map { CGFloat(min(max($0, 0), 1)) }
        return NSColor(srgbRed: v[0], green: v[1], blue: v[2], alpha: 1)
    }
}
