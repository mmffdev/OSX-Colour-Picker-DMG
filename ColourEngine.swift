import AppKit
import ColorSync

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

    /// The white the numbers came in under: fixed by the space for RGB, D50 for a press build and for L*a*b* or XYZ
    /// typed in, which is the ICC standard until a reading keeps its own illuminant.
    var whiteName: String {
        if let space = RGBSpace(rawValue: self.space) { return space.whiteName }
        return Illuminant.d50.label
    }
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
    (0..<3).map { i -> [Double] in
        (0..<3).map { j -> Double in a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j] }
    }
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
    case srgb, displayP3, adobeRGB, prophoto, rec709, rec2020, p3D65, dciP3, acescg, linearSRGB

    var name: String {
        switch self {
        case .prophoto: return "ProPhoto RGB"
        case .p3D65: return "P3-D65"
        case .dciP3: return "DCI-P3"
        case .srgb: return "sRGB"
        case .displayP3: return "Display P3"
        case .adobeRGB: return "Adobe RGB"
        case .rec709: return "Rec. 709"
        case .rec2020: return "Rec. 2020"
        case .acescg: return "ACEScg"
        case .linearSRGB: return "Linear sRGB"
        }
    }

    /// Who uses it, in a line.
    var about: String {
        switch self {
        case .prophoto: return "Photographers' working space; 16-bit only"
        case .p3D65: return "Streaming and HDR grading suites, gamma 2.6"
        case .dciP3: return "Cinema projection, gamma 2.6"
        case .srgb: return "The web and most screens"
        case .displayP3: return "Recent Apple screens; wider reds and greens"
        case .adobeRGB: return "Photography and print preparation"
        case .rec709: return "HD video, gamma 2.4"
        case .rec2020: return "Ultra HD video, gamma 2.4"
        case .acescg: return "Rendering and visual effects; linear, no ceiling"
        case .linearSRGB: return "3D engines, shaders and textures; sRGB without its curve"
        }
    }

    /// The channel it belongs to.
    var channel: String {
        switch self {
        case .srgb, .displayP3, .adobeRGB: return "Screen"
        case .prophoto: return "Photo"
        case .p3D65, .dciP3: return "Cinema"
        case .rec709, .rec2020: return "Video"
        case .acescg, .linearSRGB: return "Rendering"
        }
    }

    private var primaries: (r: (Double, Double), g: (Double, Double), b: (Double, Double), white: (x: Double, y: Double)) {
        let d65 = (x: 0.3127, y: 0.3290)
        switch self {
        case .srgb, .rec709, .linearSRGB: return ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060), d65)
        case .displayP3, .p3D65: return ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060), d65)
        // The same primaries under the projector's own white, which is a little greener than daylight.
        case .dciP3: return ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060), (x: 0.314, y: 0.351))
        // ROMM RGB: its green and blue lie outside real colour, and its white is the master's own D50.
        case .prophoto: return ((0.7347, 0.2653), (0.1596, 0.8404), (0.0366, 0.0001), (x: 0.34567, y: 0.35850))
        case .adobeRGB: return ((0.640, 0.330), (0.210, 0.710), (0.150, 0.060), d65)
        case .rec2020: return ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046), d65)
        case .acescg: return ((0.713, 0.293), (0.165, 0.830), (0.128, 0.044), (x: 0.32168, y: 0.33767))
        }
    }

    /// The white the space's own standard fixes, as the source row names it: the "in" the master was carried from.
    /// Every one is for the 2 degree observer; DCI's is the projector's calibration white, not a CIE illuminant.
    var whiteName: String {
        switch self {
        case .srgb, .rec709, .linearSRGB, .displayP3, .p3D65, .adobeRGB, .rec2020: return "D65 \u{00B7} 2\u{00B0}"
        case .prophoto: return "D50 \u{00B7} 2\u{00B0}"
        case .dciP3: return "DCI White"
        case .acescg: return "D60 \u{00B7} 2\u{00B0}"
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
        case .p3D65, .dciP3: return sign * pow(a, 2.6)
        case .prophoto: return sign * (a < 16.0 / 512 ? a / 16 : pow(a, 1.8))
        case .acescg, .linearSRGB: return v
        }
    }

    func encoded(_ v: Double) -> Double {
        let sign: Double = v < 0 ? -1 : 1, a = abs(v)
        switch self {
        case .srgb, .displayP3: return sign * (a <= 0.0031308 ? 12.92 * a : 1.055 * pow(a, 1 / 2.4) - 0.055)
        case .adobeRGB: return sign * pow(a, 256.0 / 563.0)
        case .rec709, .rec2020: return sign * pow(a, 1 / 2.4)
        case .p3D65, .dciP3: return sign * pow(a, 1 / 2.6)
        case .prophoto: return sign * (a < 1.0 / 512 ? 16 * a : pow(a, 1 / 1.8))
        case .acescg, .linearSRGB: return v
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

    var isVideo: Bool { self == .rec709 || self == .rec2020 }

    /// A value 0 to 1 as a 10-bit video code: 0 to 1023 in full range, 64 to 940 in broadcast legal range.
    static func videoCode(_ v: Double, legal: Bool) -> Int {
        let held = min(max(v, 0), 1)
        return Int((legal ? 64 + held * 876 : held * 1023).rounded())
    }

    /// The luma weights of a video space's red and blue; green takes the rest.
    private var luma: (r: Double, b: Double) { self == .rec2020 ? (0.2627, 0.0593) : (0.2126, 0.0722) }

    /// A video colour as its signal carries it: brightness, then how far blue and red sit from it.
    /// 10-bit codes. Legal range is 64 to 940 for brightness and 64 to 960 for the two differences,
    /// with 512 meaning no colour; full range runs 0 to 1023.
    func yCbCr(_ v: [Double], legal: Bool) -> [Int] {
        let c = v.map { min(max($0, 0), 1) }, k = luma
        let y = k.r * c[0] + (1 - k.r - k.b) * c[1] + k.b * c[2]
        let cb = (c[2] - y) / (2 * (1 - k.b)), cr = (c[0] - y) / (2 * (1 - k.r))
        func code(_ x: Double) -> Int { Int(min(max(x, 0), 1023).rounded()) }
        return legal ? [code(64 + 876 * y), code(512 + 896 * cb), code(512 + 896 * cr)] : [code(1023 * y), code(512 + 1023 * cb), code(512 + 1023 * cr)]
    }

    /// Values as this space's users write them.
    func text(_ v: [Double], legal: Bool = false) -> String {
        func whole(_ x: Double, _ top: Double) -> Int { Int((min(max(x, 0), 1) * top).rounded()) }
        switch self {
        case .srgb: return String(format: "#%02X%02X%02X", whole(v[0], 255), whole(v[1], 255), whole(v[2], 255))
        case .displayP3, .p3D65: return v.map { String(format: "%.3f", $0) }.joined(separator: ", ")
        // Cinema masters are 12-bit; ProPhoto is never 8-bit, so it is written as decimals.
        case .dciP3: return v.map { "\(whole($0, 4095))" }.joined(separator: ", ") + "  (12-bit)"
        case .prophoto: return v.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        case .adobeRGB: return v.map { "\(whole($0, 255))" }.joined(separator: ", ")
        case .rec709, .rec2020: return v.map { "\(RGBSpace.videoCode($0, legal: legal))" }.joined(separator: ", ") + (legal ? "  (10-bit, legal range)" : "  (10-bit, full range)")
        case .acescg, .linearSRGB: return v.map { String(format: "%.4f", $0) }.joined(separator: ", ")
        }
    }
}

// MARK: Illuminants

/// A CIE standard illuminant seen by one of the two standard observers: the white a house quotes its
/// numbers under. The master stays XYZ under D50, the ICC standard; an illuminant carries it to another
/// white by Bradford for the numbers only, so a textile mill reading D65 and 10 degrees sees its own figures.
struct Illuminant: Equatable, CaseIterable {
    /// The CIE's name: A, C, D50, D55, D65, D75.
    let name: String
    /// The standard observer's field, 2 or 10 degrees.
    let observer: Int
    /// The illuminant's white, Y = 1 (ASTM E308).
    let white: XYZ

    static let allCases: [Illuminant] = [
        Illuminant(name: "A", observer: 2, white: XYZ(x: 1.09850, y: 1, z: 0.35585)),
        Illuminant(name: "A", observer: 10, white: XYZ(x: 1.11144, y: 1, z: 0.35200)),
        Illuminant(name: "C", observer: 2, white: XYZ(x: 0.98074, y: 1, z: 1.18232)),
        Illuminant(name: "C", observer: 10, white: XYZ(x: 0.97285, y: 1, z: 1.16145)),
        Illuminant(name: "D50", observer: 2, white: XYZ.d50),
        Illuminant(name: "D50", observer: 10, white: XYZ(x: 0.96720, y: 1, z: 0.81427)),
        Illuminant(name: "D55", observer: 2, white: XYZ(x: 0.95682, y: 1, z: 0.92149)),
        Illuminant(name: "D55", observer: 10, white: XYZ(x: 0.95799, y: 1, z: 0.90926)),
        Illuminant(name: "D65", observer: 2, white: XYZ(x: 0.95047, y: 1, z: 1.08883)),
        Illuminant(name: "D65", observer: 10, white: XYZ(x: 0.94811, y: 1, z: 1.07304)),
        Illuminant(name: "D75", observer: 2, white: XYZ(x: 0.94972, y: 1, z: 1.22638)),
        Illuminant(name: "D75", observer: 10, white: XYZ(x: 0.94416, y: 1, z: 1.20641)),
    ]
    /// The master's own white: D50 for the 2 degree observer, which every ICC profile is built round.
    static let d50 = allCases[4]

    /// "D65 · 10°", as a menu writes it.
    var label: String { "\(name) \u{00B7} \(observer)\u{00B0}" }
    /// A key for keeping a choice: "d65-10".
    var key: String { "\(name.lowercased())-\(observer)" }
    static func named(_ key: String?) -> Illuminant? { allCases.first { $0.key == key } }
}

extension XYZ {
    /// Where the colour sits on the chromaticity diagram, for the adaptation.
    var chromaticity: (x: Double, y: Double) {
        let s = x + y + z
        return s == 0 ? XYZ.d50.chromaticity : (x: x / s, y: y / s)
    }
    /// The master carried from D50 to an illuminant's white by Bradford, so its numbers can be quoted under that white.
    func adapted(to illuminant: Illuminant) -> XYZ {
        if illuminant == .d50 { return self }
        let v = multiply(bradford(from: XYZ.d50.chromaticity, to: illuminant.white.chromaticity), [x, y, z])
        return XYZ(x: v[0], y: v[1], z: v[2])
    }
    /// L*a*b* against an illuminant's white, for a colour already adapted to it.
    func lab(under illuminant: Illuminant) -> LabD50 {
        let w = illuminant.white
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(x / w.x), fy = f(y / w.y), fz = f(z / w.z)
        return LabD50(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }
}

// MARK: Comparing colours

extension XYZ {
    var lab: LabD50 { lab(under: .d50) }
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

/// The ways a house compares two colours. CIEDE2000 is the CIE's current formula and the default; the older
/// ones are kept because a press house or a textile mill may still write its tolerances in them. CIE94 and
/// CMC weight the first colour as the reference, so they are not symmetric: the master is always given first.
enum DifferenceMethod: String, CaseIterable {
    case ciede2000, cie94, cmc21, cmc11, cie76

    var label: String {
        switch self {
        case .ciede2000: return "CIEDE2000"
        case .cie94: return "CIE94"
        case .cmc21: return "CMC 2:1"
        case .cmc11: return "CMC 1:1"
        case .cie76: return "CIE76"
        }
    }
    /// The difference's own name, for a label over the number.
    var short: String {
        switch self {
        case .ciede2000: return "\u{0394}E2000"
        case .cie94: return "\u{0394}E94"
        case .cmc21: return "\u{0394}E CMC 2:1"
        case .cmc11: return "\u{0394}E CMC 1:1"
        case .cie76: return "\u{0394}E76"
        }
    }
    /// What the user needs to know about the method, in a few lines: how to read it, and that the master is the reference where that matters.
    var note: String {
        switch self {
        case .ciede2000: return "CIEDE2000, the CIE's current formula: 1 is about the smallest step the eye can see, 2 plainly another colour."
        case .cie94: return "CIE94 weights the master as the reference, so the two swapped give another number."
        case .cmc21: return "CMC 2:1, textiles' acceptability ratio, takes the master as reference: swapped, the two give another number."
        case .cmc11: return "CMC 1:1, textiles' perceptibility ratio, takes the master as reference: swapped, the two give another number."
        case .cie76: return "CIE76, the plain distance in L*a*b*, as older houses compare: it overstates the difference in saturated colours."
        }
    }

    /// The difference from the reference to the sample.
    func difference(_ reference: LabD50, _ sample: LabD50) -> Double {
        let dL = sample.l - reference.l, da = sample.a - reference.a, db = sample.b - reference.b
        let c1 = hypot(reference.a, reference.b), c2 = hypot(sample.a, sample.b), dC = c2 - c1
        let dH = sqrt(max(0, da * da + db * db - dC * dC))
        switch self {
        case .ciede2000: return deltaE2000(reference, sample)
        case .cie76: return sqrt(dL * dL + da * da + db * db)
        case .cie94:
            // The graphic arts weights: K1 0.045, K2 0.015, kL 1.
            let sc = 1 + 0.045 * c1, sh = 1 + 0.015 * c1
            return sqrt(dL * dL + pow(dC / sc, 2) + pow(dH / sh, 2))
        case .cmc21, .cmc11:
            let l = self == .cmc21 ? 2.0 : 1.0
            let sl = reference.l < 16 ? 0.511 : 0.040975 * reference.l / (1 + 0.01765 * reference.l)
            let sc = 0.0638 * c1 / (1 + 0.0131 * c1) + 0.638
            var h1 = atan2(reference.b, reference.a) * 180 / .pi
            if h1 < 0 { h1 += 360 }
            let rad = Double.pi / 180
            let t = h1 >= 164 && h1 <= 345 ? 0.56 + abs(0.2 * cos((h1 + 168) * rad)) : 0.36 + abs(0.4 * cos((h1 + 35) * rad))
            let c14 = pow(c1, 4), f = sqrt(c14 / (c14 + 1900))
            let sh = sc * (f * t + 1 - f)
            return sqrt(pow(dL / (l * sl), 2) + pow(dC / sc, 2) + pow(dH / sh, 2))
        }
    }
}

// MARK: Rendering intents

/// The rule for bringing a colour a medium cannot show into its range.
enum RenderingIntent: String, Codable, CaseIterable {
    /// Keeps every colour in range exactly; brings one out of range to the nearest edge. The default for swatches.
    case relative
    /// As relative, and measured against the paper's own white, so the proof shows the colour on that stock.
    /// The system's engine will not run this from a master, so the app applies the paper white itself.
    case absolute
    /// Compresses everything to fit, shifting even colours in range. For images, not single colours.
    case perceptual

    var name: String {
        switch self {
        case .relative: return "Relative Colorimetric"
        case .absolute: return "Absolute Colorimetric"
        case .perceptual: return "Perceptual"
        }
    }

    /// What it does, in a line, for the Settings pane.
    var about: String {
        switch self {
        case .relative: return "A colour in range is kept exactly; one out of range goes to the nearest edge"
        case .absolute: return "As relative, shown on the paper's own white: the proof of how it will look on that stock"
        case .perceptual: return "Everything is compressed to fit, so even colours in range shift. For images"
        }
    }

    /// What the system's engine is asked for. Absolute is relative with the paper white applied by the app.
    var system: CGColorRenderingIntent { self == .perceptual ? .perceptual : .relativeColorimetric }
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

    /// Every CMYK profile found, by its own name, sorted. ColorSync is asked first, since it knows every
    /// profile installed wherever it sits, which matters under the sandbox where the folders above cannot
    /// all be looked in; the folders are then walked as well, for a profile ColorSync has yet to notice.
    static let all: [Profile] = {
        var found: [String: Profile] = [:]
        let fm = FileManager.default
        func consider(_ path: String) {
            guard path.lowercased().hasSuffix(".icc") || path.lowercased().hasSuffix(".icm"),
                  let data = fm.contents(atPath: path), let space = CGColorSpace(iccData: data as CFData), space.model == .cmyk,
                  let name = NSColorSpace(cgColorSpace: space)?.localizedName, found[name] == nil else { return }
            found[name] = Profile(name: name, path: path)
        }
        for path in installedProfilePaths() { consider(path) }
        for folder in folders {
            for item in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] { consider(folder + "/" + item) }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// The file of every profile ColorSync has installed, CMYK ones only.
    private static func installedProfilePaths() -> [String] {
        final class Found { var paths: [String] = [] }
        let found = Found()
        var seed: UInt32 = 0
        ColorSyncIterateInstalledProfiles({ info, user in
            guard let info = info as? [String: Any], let user = user else { return true }
            let found = Unmanaged<Found>.fromOpaque(user).takeUnretainedValue()
            if let space = info[kColorSyncProfileColorSpace.takeUnretainedValue() as String] as? String,
               space == kColorSyncSigCmykData.takeUnretainedValue() as String,
               let url = info[kColorSyncProfileURL.takeUnretainedValue() as String] as? URL {
                found.paths.append(url.path)
            }
            return true
        }, &seed, Unmanaged.passUnretained(found).toOpaque(), nil)
        return found.paths
    }

    private static var spaces: [String: CGColorSpace] = [:]
    private static var whites: [String: XYZ] = [:]
    private static var blacks: [String: Double] = [:]

    /// The paper white a profile was measured on, read from the profile's own file ("wtpt"). D50,
    /// a perfect white, when the profile gives none.
    static func paperWhite(of name: String) -> XYZ {
        if let have = whites[name] { return have }
        let white = all.first { $0.name == name }.flatMap { FileManager.default.contents(atPath: $0.path) }.flatMap(mediaWhite(inProfile:)) ?? XYZ.d50
        whites[name] = white
        return white
    }

    /// Reads the media white point from ICC profile data: a header of 128 bytes, a table of tags,
    /// and under the tag "wtpt" three fixed-point numbers.
    static func mediaWhite(inProfile data: Data) -> XYZ? {
        func word(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= data.count else { return nil }
            return data.subdata(in: at..<at + 4).reduce(0) { $0 << 8 | UInt32($1) }
        }
        guard let count = word(128), count < 512 else { return nil }
        for i in 0..<Int(count) {
            let entry = 132 + i * 12
            guard let signature = word(entry), signature == 0x77747074, let offset = word(entry + 4), let size = word(entry + 8), size >= 20 else { continue }
            let at = Int(offset) + 8   // past the type name and four reserved bytes
            guard let x = word(at), let y = word(at + 4), let z = word(at + 8) else { return nil }
            func fixed(_ v: UInt32) -> Double { Double(Int32(bitPattern: v)) / 65536 }
            let white = XYZ(x: fixed(x), y: fixed(y), z: fixed(z))
            return white.y > 0.5 && white.y <= 1.01 ? white : nil   // a sane paper, or nothing
        }
        return nil
    }

    /// How bright the press's darkest black is, as a fraction of its white: what pure black comes back as.
    static func blackLevel(of name: String) -> Double {
        if let have = blacks[name] { return have }
        var level = 0.0
        if let space = space(named: name), let black = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.genericXYZ)!, components: [0, 0, 0, 1]),
           let ink = black.converted(to: space, intent: .relativeColorimetric, options: nil),
           let back = ink.converted(to: CGColorSpace(name: CGColorSpace.genericXYZ)!, intent: .relativeColorimetric, options: nil)?.components, back.count >= 3 {
            level = min(max(Double(back[1]), 0), 0.2)
        }
        blacks[name] = level
        return level
    }

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

    /// Sends a master through the profile and back.
    ///
    /// Absolute colorimetric: the master is first expressed against the paper's white, and the
    /// result is shown on that paper. Black point compensation: the master is scaled so that pure
    /// black lands on the press's darkest black and white stays white, which keeps dark colours
    /// apart at the cost of lifting them slightly. Both are worked out here; the system's engine
    /// is asked only for the plain conversion, which is the part it does reliably.
    static func of(_ master: XYZ, press: String, intent: RenderingIntent, blackPoint: Bool = false) -> PrintBuild? {
        guard let space = PressProfiles.space(named: press) else { return nil }
        let white = intent == .absolute ? PressProfiles.paperWhite(of: press) : XYZ.d50
        var given = XYZ(x: master.x * XYZ.d50.x / white.x, y: master.y * XYZ.d50.y / white.y, z: master.z * XYZ.d50.z / white.z)
        if blackPoint, intent != .perceptual {
            let black = PressProfiles.blackLevel(of: press)
            given = XYZ(x: given.x * (1 - black) + black * XYZ.d50.x, y: given.y * (1 - black) + black * XYZ.d50.y, z: given.z * (1 - black) + black * XYZ.d50.z)
        }
        guard let colour = CGColor(colorSpace: masterSpace, components: [CGFloat(given.x), CGFloat(given.y), CGFloat(given.z), 1]),
              let ink = colour.converted(to: space, intent: intent.system, options: nil), let c = ink.components, c.count >= 4,
              let back = ink.converted(to: masterSpace, intent: .relativeColorimetric, options: nil)?.components, back.count >= 3 else { return nil }
        // What the build looks like: against a perfect white, or on its own paper for an absolute proof.
        let printed = XYZ(x: Double(back[0]) * white.x / XYZ.d50.x, y: Double(back[1]) * white.y / XYZ.d50.y, z: Double(back[2]) * white.z / XYZ.d50.z)
        return PrintBuild(inks: c.prefix(4).map { Double($0) }, printed: printed)
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
    /// For print: black point compensation. nil is off, so a colour in range is kept exactly.
    var blackPoint: Bool? = nil
    /// For video: code values in broadcast legal range (64 to 940). nil is full range (0 to 1023).
    var legal: Bool? = nil

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
            // sRGB is written both ways its users write it: the hex, then the same three values as numbers.
            let written = space == .srgb ? space.text(held) + "   " + held.map { "\(Int((min(max($0, 0), 1) * 255).rounded()))" }.joined(separator: ", ")
                : space.text(held, legal: channel.legal ?? false)
            return Rendering(channel: channel, value: written, shown: shown, difference: deltaE2000(master.lab, shown.lab), inRange: within,
                             detail: (space.isVideo ? "Y\u{2032}CbCr " + space.yCbCr(held, legal: channel.legal ?? false).map { "\($0)" }.joined(separator: ", ") + "  \u{00B7}  " : "")
                                + (within ? space.about : "Outside \(space.name): the nearest it can show"))
        }
        let press = channel.press ?? PressProfiles.generic, intent = channel.intent ?? .relative, blackPoint = channel.blackPoint ?? false
        // A colour given as a build for this very press is delivered as given: the build is the truth, not a round trip through maths.
        if definition.source.space == "cmyk", definition.source.press == press, definition.source.values.count == 4 {
            let build = PrintBuild(inks: definition.source.values, printed: master)
            return Rendering(channel: channel, value: build.text, shown: master, difference: 0, inRange: true,
                             detail: "As Given  \u{00B7}  Total Ink \(Int(build.totalInk.rounded()))%")
        }
        guard let build = PrintBuild.of(master, press: press, intent: intent, blackPoint: blackPoint) else {
            return Rendering(channel: channel, value: nil, shown: nil, difference: nil, inRange: false, detail: "The profile \u{201C}\(press)\u{201D} is not on this Mac")
        }
        let difference = deltaE2000(master.lab, build.printed.lab)
        let extras = (blackPoint && intent != .perceptual ? "  \u{00B7}  Black Point Compensation" : "")
        return Rendering(channel: channel, value: build.text, shown: build.printed, difference: difference, inRange: difference <= Rendering.visible,
                         detail: "\(intent.name)\(extras)  \u{00B7}  Total Ink \(Int(build.totalInk.rounded()))%")
    }
}

extension XYZ {
    /// The colour for painting on screen: Display P3, held in range, so a wide screen shows a
    /// colour beyond sRGB as it is and the system brings it in for a screen that cannot.
    var display: NSColor {
        let v = RGBSpace.displayP3.values(of: self).map { CGFloat(min(max($0, 0), 1)) }
        return NSColor(displayP3Red: v[0], green: v[1], blue: v[2], alpha: 1)
    }

    /// Whether a space can hold the colour as it is.
    func fits(_ space: RGBSpace) -> Bool {
        space.linearValues(of: self).allSatisfy { $0 >= -RGBSpace.slack && $0 <= 1 + RGBSpace.slack }
    }

    /// Whether a screen can show the colour as it is: within Display P3 on a wide screen, within sRGB on any other.
    func shows(on screen: NSScreen?) -> Bool {
        fits(screen?.canRepresent(.p3) == true ? .displayP3 : .srgb)
    }
}
