import Foundation

// ---------- Colour values, formats, names, contrast, harmonies ----------
//
// A colour's key stands for an sRGB value here, or for the sRGB colour it shows as. CMYK is the
// build for a real press (see PrintCondition); the wide spaces and Lab of a colour with a key of
// its own come from its master, not from sRGB.

struct ColourValues {
    /// "#RRGGBB", uppercase.
    let hex: String
    let r: Int, g: Int, b: Int

    init?(_ raw: String) {
        // A key that is not a hex is read as the sRGB colour it shows as.
        guard let n = normaliseHex(raw) ?? ColourKeys.displayHex(raw), let v = UInt32(n.dropFirst(), radix: 16) else { return nil }
        hex = n
        r = Int((v >> 16) & 0xFF); g = Int((v >> 8) & 0xFF); b = Int(v & 0xFF)
    }

    var unit: (r: Double, g: Double, b: Double) { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }

    /// Hue 0–360, saturation and lightness 0–1.
    var hslUnit: (h: Double, s: Double, l: Double) {
        let (r, g, b) = unit
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return (hue(r, g, b, mx, d), s, l)
    }

    /// Hue 0–360, saturation and value 0–1.
    var hsvUnit: (h: Double, s: Double, v: Double) {
        let (r, g, b) = unit
        let mx = max(r, g, b), d = mx - min(r, g, b)
        return (hue(r, g, b, mx, d), mx == 0 ? 0 : d / mx, mx)
    }

    private func hue(_ r: Double, _ g: Double, _ b: Double, _ mx: Double, _ d: Double) -> Double {
        guard d > 0 else { return 0 }
        var h: Double
        if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    var hsl: (h: Int, s: Int, l: Int) { let v = hslUnit; return (whole(v.h) % 360, whole(v.s * 100), whole(v.l * 100)) }
    var hsv: (h: Int, s: Int, v: Int) { let v = hsvUnit; return (whole(v.h) % 360, whole(v.s * 100), whole(v.v * 100)) }

    /// Linear-light values, as 3D and compositing tools expect for a base colour.
    var linear: (r: Double, g: Double, b: Double) {
        let u = unit
        return (toLinear(u.r), toLinear(u.g), toLinear(u.b))
    }

    // The same colour written in wider colour spaces, 0–255 per channel. A stored colour is
    // sRGB, so it always fits inside these; the numbers are what to type to get the same colour.

    private func converted(_ m: [Double], encode: (Double) -> Double) -> (r: Int, g: Int, b: Int) {
        let l = linear
        func channel(_ row: Int) -> Int {
            let v = m[row * 3] * l.r + m[row * 3 + 1] * l.g + m[row * 3 + 2] * l.b
            return whole(min(max(encode(min(max(v, 0), 1)), 0), 1) * 255)
        }
        return (channel(0), channel(1), channel(2))
    }

    /// Display P3: P3 primaries with the sRGB curve.
    var p3: (r: Int, g: Int, b: Int) {
        converted([0.8224621, 0.1775380, 0.0000000, 0.0331941, 0.9668058, 0.0000000, 0.0170827, 0.0723974, 0.9105199]) {
            $0 <= 0.0031308 ? $0 * 12.92 : 1.055 * pow($0, 1 / 2.4) - 0.055
        }
    }

    /// Adobe RGB (1998): its own primaries and a 2.2 gamma (563/256).
    var adobeRGB: (r: Int, g: Int, b: Int) {
        converted([0.7151627, 0.2848373, 0.0000000, 0.0000000, 1.0000000, 0.0000000, 0.0000000, 0.0411619, 0.9588381]) {
            pow($0, 256.0 / 563)
        }
    }

    /// ITU-R BT.2020, with the standard's own transfer curve.
    var rec2020: (r: Int, g: Int, b: Int) {
        converted([0.6274039, 0.3292830, 0.0433131, 0.0690973, 0.9195404, 0.0113623, 0.0163914, 0.0880133, 0.8955953]) {
            $0 < 0.0181 ? 4.5 * $0 : 1.0993 * pow($0, 0.45) - 0.0993
        }
    }

    /// CIE L*a*b* under D50, the white point print and ColorSync use.
    var lab: (l: Double, a: Double, b: Double) {
        let c = linear
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let x = f((0.4360747 * c.r + 0.3850649 * c.g + 0.1430804 * c.b) / 0.96422)
        let y = f(0.2225045 * c.r + 0.7168786 * c.g + 0.0606169 * c.b)
        let z = f((0.0139322 * c.r + 0.0971045 * c.g + 0.7141733 * c.b) / 0.82521)
        return (116 * y - 16, 500 * (x - y), 200 * (y - z))
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    var luminance: Double { let l = linear; return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b }

    private func whole(_ v: Double) -> Int { Int(v.rounded()) }
}

func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }

func hexFrom(h: Double, s: Double, l: Double) -> String {
    let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let s = min(max(s, 0), 1), l = min(max(l, 0), 1)
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    let (r, g, b): (Double, Double, Double)
    switch hue {
    case ..<60: (r, g, b) = (c, x, 0)
    case ..<120: (r, g, b) = (x, c, 0)
    case ..<180: (r, g, b) = (0, c, x)
    case ..<240: (r, g, b) = (0, x, c)
    case ..<300: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }
    func byte(_ v: Double) -> Int { Int(((v + m) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
}

/// CIE L*a*b* (D65) from sRGB 0–1.
func labOf(_ rgb: (r: Double, g: Double, b: Double)) -> (l: Double, a: Double, b: Double) {
    let r = toLinear(rgb.r), g = toLinear(rgb.g), b = toLinear(rgb.b)
    func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
    let x = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
    let y = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
    let z = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))
}

// ---------- Copy formats ----------

enum ColourFormat: String, CaseIterable {
    case hex, hexBare, rgb, cssRGB, hsl, cssHSL, hsv, cmyk, float, linear, swiftUI, nsColor, uiColor
    case p3, adobeRGB, rec2020, lab

    /// The rows a colour card can show, in order.
    static let cardRows: [ColourFormat] = [.hex, .rgb, .hsl, .hsv, .cmyk, .p3, .adobeRGB, .rec2020, .lab]
    /// The rows a card shows until Settings says otherwise.
    static let defaultCardRows: [ColourFormat] = [.hex, .rgb, .hsl, .hsv, .cmyk]

    var title: String {
        switch self {
        case .hex: return "HEX  \u{2014}  #4F8093"
        case .hexBare: return "HEX without #  \u{2014}  4F8093"
        case .rgb: return "RGB  \u{2014}  79, 128, 147"
        case .cssRGB: return "CSS rgb()  \u{2014}  rgb(79 128 147)"
        case .hsl: return "HSL  \u{2014}  197, 30%, 44%"
        case .cssHSL: return "CSS hsl()  \u{2014}  hsl(197 30% 44%)"
        case .hsv: return "HSV / HSB  \u{2014}  197, 46%, 58%"
        case .cmyk: return "CMYK, for the profile's press  \u{2014}  " + text("#4F8093")
        case .float: return "Float RGB 0\u{2013}1  \u{2014}  0.310, 0.502, 0.576"
        case .linear: return "Linear RGB 0\u{2013}1 (3D, shaders)  \u{2014}  0.078, 0.216, 0.292"
        case .swiftUI: return "SwiftUI Color"
        case .nsColor: return "AppKit NSColor"
        case .uiColor: return "UIKit UIColor"
        case .p3: return "Display P3  \u{2014}  " + text("#4F8093")
        case .adobeRGB: return "Adobe RGB  \u{2014}  " + text("#4F8093")
        case .rec2020: return "BT.2020  \u{2014}  " + text("#4F8093")
        case .lab: return "L*a*b* (D50)  \u{2014}  " + text("#4F8093")
        }
    }

    /// Short label for a card row and for status messages.
    var label: String {
        switch self {
        case .hex, .hexBare: return "HEX"
        case .rgb, .cssRGB: return "RGB"
        case .hsl, .cssHSL: return "HSL"
        case .hsv: return "HSV"
        case .cmyk: return "CMYK"
        case .float: return "Float"
        case .linear: return "Linear"
        case .swiftUI: return "SwiftUI"
        case .nsColor: return "NSColor"
        case .uiColor: return "UIColor"
        case .p3: return "P3"
        case .adobeRGB: return "Adobe"
        case .rec2020: return "BT.2020"
        case .lab: return "L*a*b*"
        }
    }

    func text(_ raw: String, lowercase: Bool = false) -> String {
        guard let v = ColourValues(raw) else { return raw }
        func f(_ d: Double) -> String { String(format: "%.3f", d) }
        let u = v.unit
        switch self {
        case .hex: return lowercase ? v.hex.lowercased() : v.hex
        case .hexBare: return String((lowercase ? v.hex.lowercased() : v.hex).dropFirst())
        case .rgb: return "\(v.r), \(v.g), \(v.b)"
        case .cssRGB: return "rgb(\(v.r) \(v.g) \(v.b))"
        case .hsl: return "\(v.hsl.h), \(v.hsl.s)%, \(v.hsl.l)%"
        case .cssHSL: return "hsl(\(v.hsl.h) \(v.hsl.s)% \(v.hsl.l)%)"
        case .hsv: return "\(v.hsv.h), \(v.hsv.s)%, \(v.hsv.v)%"
        case .cmyk: return fields(raw).joined(separator: ", ")
        case .float: return "\(f(u.r)), \(f(u.g)), \(f(u.b))"
        case .linear: return "\(f(v.linear.r)), \(f(v.linear.g)), \(f(v.linear.b))"
        case .swiftUI: return "Color(red: \(f(u.r)), green: \(f(u.g)), blue: \(f(u.b)))"
        case .nsColor: return "NSColor(srgbRed: \(f(u.r)), green: \(f(u.g)), blue: \(f(u.b)), alpha: 1)"
        case .uiColor: return "UIColor(red: \(f(u.r)), green: \(f(u.g)), blue: \(f(u.b)), alpha: 1)"
        case .p3, .adobeRGB, .rec2020, .lab: return fields(raw).joined(separator: ", ")
        }
    }

    /// The separate numbers shown across a card row.
    func fields(_ raw: String, lowercase: Bool = false) -> [String] {
        guard let v = ColourValues(raw) else { return [raw] }
        // A colour with a key of its own: its wide values and Lab come from its master, so nothing sRGB cannot hold is lost.
        if let wide = ColourKeys.definition(of: raw) {
            func bytes(_ space: RGBSpace) -> [String] { space.values(of: wide.master).map { "\(Int((min(max($0, 0), 1) * 255).rounded()))" } }
            switch self {
            case .p3: return bytes(.displayP3)
            case .adobeRGB: return bytes(.adobeRGB)
            case .rec2020: return bytes(.rec2020)
            case .lab: let lab = wide.master.lab; return [lab.l, lab.a, lab.b].map { String(format: "%.1f", $0 == 0 ? 0 : $0) }
            default: break
            }
        }
        switch self {
        case .hex, .hexBare: return [ColourFormat.hexBare.text(raw, lowercase: lowercase)]
        case .rgb, .cssRGB: return ["\(v.r)", "\(v.g)", "\(v.b)"]
        case .hsl, .cssHSL: return ["\(v.hsl.h)", "\(v.hsl.s)", "\(v.hsl.l)"]
        case .hsv: return ["\(v.hsv.h)", "\(v.hsv.s)", "\(v.hsv.v)"]
        case .cmyk: return PrintCondition.inks(of: raw)?.map { "\($0)" } ?? ["\u{2014}"]
        case .p3: return ["\(v.p3.r)", "\(v.p3.g)", "\(v.p3.b)"]
        case .adobeRGB: return ["\(v.adobeRGB.r)", "\(v.adobeRGB.g)", "\(v.adobeRGB.b)"]
        case .rec2020: return ["\(v.rec2020.r)", "\(v.rec2020.g)", "\(v.rec2020.b)"]
        case .lab: return [v.lab.l, v.lab.a, v.lab.b].map { String(format: "%.1f", $0 == 0 ? 0 : $0) }
        default: return [text(raw, lowercase: lowercase)]
        }
    }
}

// ---------- Contrast (WCAG 2.x) ----------

/// 1 (identical) to 21 (black on white).
func contrastRatio(_ a: String, _ b: String) -> Double {
    guard let x = ColourValues(a)?.luminance, let y = ColourValues(b)?.luminance else { return 1 }
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

/// The WCAG level a ratio reaches for body text.
func contrastGrade(_ ratio: Double) -> String {
    if ratio >= 7 { return "AAA" }
    if ratio >= 4.5 { return "AA" }
    if ratio >= 3 { return "AA large" }
    return "fail"
}

/// Black or white, whichever reads better on the colour.
func readableText(on hex: String) -> String {
    contrastRatio(hex, "#FFFFFF") >= contrastRatio(hex, "#000000") ? "#FFFFFF" : "#000000"
}

// ---------- Grouping ----------

enum ColourGroup: Int, CaseIterable {
    case reds, oranges, yellows, greens, teals, blues, purples, pinks, browns, neutrals

    var title: String {
        switch self {
        case .reds: return "Reds"
        case .oranges: return "Oranges"
        case .yellows: return "Yellows"
        case .greens: return "Greens"
        case .teals: return "Teals"
        case .blues: return "Blues"
        case .purples: return "Purples"
        case .pinks: return "Pinks"
        case .browns: return "Browns"
        case .neutrals: return "Neutrals"
        }
    }
}

func colourGroup(_ hex: String) -> ColourGroup {
    guard let v = ColourValues(hex) else { return .neutrals }
    let (h, s, l) = v.hslUnit
    if s < 0.12 || l < 0.07 || l > 0.96 { return .neutrals }
    if (12..<50).contains(h) && l < 0.42 && s < 0.8 { return .browns }
    switch h {
    case ..<14: return .reds
    case ..<45: return .oranges
    case ..<70: return .yellows
    case ..<160: return .greens
    case ..<200: return .teals
    case ..<255: return .blues
    case ..<290: return .purples
    case ..<345: return .pinks
    default: return .reds
    }
}

// ---------- Harmonies and scales ----------

enum Harmony: String, CaseIterable {
    case complementary, analogous, triadic, splitComplementary, tetradic, tintsAndShades, scale

    var title: String {
        switch self {
        case .complementary: return "Complementary"
        case .analogous: return "Analogous"
        case .triadic: return "Triadic"
        case .splitComplementary: return "Split Complementary"
        case .tetradic: return "Tetradic"
        case .tintsAndShades: return "Tints & Shades"
        case .scale: return "Scale 50\u{2013}950"
        }
    }

    /// The colours, starting from (or built around) `hex`.
    func colours(from hex: String) -> [String] {
        guard let v = ColourValues(hex) else { return [] }
        let (h, s, l) = v.hslUnit
        func turn(_ degrees: Double) -> String { hexFrom(h: h + degrees, s: s, l: l) }
        switch self {
        case .complementary: return [v.hex, turn(180)]
        case .analogous: return [turn(-30), v.hex, turn(30)]
        case .triadic: return [v.hex, turn(120), turn(240)]
        case .splitComplementary: return [v.hex, turn(150), turn(210)]
        case .tetradic: return [v.hex, turn(90), turn(180), turn(270)]
        case .tintsAndShades:
            let lighter = [0.8, 0.6, 0.4, 0.2].map { hexFrom(h: h, s: s, l: l + (1 - l) * $0) }
            let darker = [0.2, 0.4, 0.6, 0.8].map { hexFrom(h: h, s: s, l: l * (1 - $0)) }
            return lighter + [v.hex] + darker
        case .scale:
            return Harmony.scaleSteps.map { hexFrom(h: h, s: s, l: $0.lightness) }
        }
    }

    /// The eleven steps design systems use, lightest to darkest.
    static let scaleSteps: [(step: Int, lightness: Double)] = [
        (50, 0.97), (100, 0.93), (200, 0.86), (300, 0.76), (400, 0.64), (500, 0.52),
        (600, 0.43), (700, 0.35), (800, 0.27), (900, 0.20), (950, 0.12),
    ]
}

// ---------- Names ----------
//
// The CSS named colours: a public standard, free to embed. Each colour is given the name of the
// nearest one, so names are approximate — "Steel Blue" means "close to steel blue".

let namedColours: [(name: String, hex: String)] = [
    ("Alice Blue", "#F0F8FF"), ("Antique White", "#FAEBD7"), ("Aqua", "#00FFFF"), ("Aquamarine", "#7FFFD4"),
    ("Azure", "#F0FFFF"), ("Beige", "#F5F5DC"), ("Bisque", "#FFE4C4"), ("Black", "#000000"),
    ("Blanched Almond", "#FFEBCD"), ("Blue", "#0000FF"), ("Blue Violet", "#8A2BE2"), ("Brown", "#A52A2A"),
    ("Burlywood", "#DEB887"), ("Cadet Blue", "#5F9EA0"), ("Chartreuse", "#7FFF00"), ("Chocolate", "#D2691E"),
    ("Coral", "#FF7F50"), ("Cornflower Blue", "#6495ED"), ("Cornsilk", "#FFF8DC"), ("Crimson", "#DC143C"),
    ("Dark Blue", "#00008B"), ("Dark Cyan", "#008B8B"), ("Dark Goldenrod", "#B8860B"), ("Dark Grey", "#A9A9A9"),
    ("Dark Green", "#006400"), ("Dark Khaki", "#BDB76B"), ("Dark Magenta", "#8B008B"), ("Dark Olive Green", "#556B2F"),
    ("Dark Orange", "#FF8C00"), ("Dark Orchid", "#9932CC"), ("Dark Red", "#8B0000"), ("Dark Salmon", "#E9967A"),
    ("Dark Sea Green", "#8FBC8F"), ("Dark Slate Blue", "#483D8B"), ("Dark Slate Grey", "#2F4F4F"),
    ("Dark Turquoise", "#00CED1"), ("Dark Violet", "#9400D3"), ("Deep Pink", "#FF1493"), ("Deep Sky Blue", "#00BFFF"),
    ("Dim Grey", "#696969"), ("Dodger Blue", "#1E90FF"), ("Firebrick", "#B22222"), ("Floral White", "#FFFAF0"),
    ("Forest Green", "#228B22"), ("Fuchsia", "#FF00FF"), ("Gainsboro", "#DCDCDC"), ("Ghost White", "#F8F8FF"),
    ("Gold", "#FFD700"), ("Goldenrod", "#DAA520"), ("Grey", "#808080"), ("Green", "#008000"),
    ("Green Yellow", "#ADFF2F"), ("Honeydew", "#F0FFF0"), ("Hot Pink", "#FF69B4"), ("Indian Red", "#CD5C5C"),
    ("Indigo", "#4B0082"), ("Ivory", "#FFFFF0"), ("Khaki", "#F0E68C"), ("Lavender", "#E6E6FA"),
    ("Lavender Blush", "#FFF0F5"), ("Lawn Green", "#7CFC00"), ("Lemon Chiffon", "#FFFACD"), ("Light Blue", "#ADD8E6"),
    ("Light Coral", "#F08080"), ("Light Cyan", "#E0FFFF"), ("Light Goldenrod", "#FAFAD2"), ("Light Grey", "#D3D3D3"),
    ("Light Green", "#90EE90"), ("Light Pink", "#FFB6C1"), ("Light Salmon", "#FFA07A"), ("Light Sea Green", "#20B2AA"),
    ("Light Sky Blue", "#87CEFA"), ("Light Slate Grey", "#778899"), ("Light Steel Blue", "#B0C4DE"),
    ("Light Yellow", "#FFFFE0"), ("Lime", "#00FF00"), ("Lime Green", "#32CD32"), ("Linen", "#FAF0E6"),
    ("Maroon", "#800000"), ("Medium Aquamarine", "#66CDAA"), ("Medium Blue", "#0000CD"), ("Medium Orchid", "#BA55D3"),
    ("Medium Purple", "#9370DB"), ("Medium Sea Green", "#3CB371"), ("Medium Slate Blue", "#7B68EE"),
    ("Medium Spring Green", "#00FA9A"), ("Medium Turquoise", "#48D1CC"), ("Medium Violet Red", "#C71585"),
    ("Midnight Blue", "#191970"), ("Mint Cream", "#F5FFFA"), ("Misty Rose", "#FFE4E1"), ("Moccasin", "#FFE4B5"),
    ("Navajo White", "#FFDEAD"), ("Navy", "#000080"), ("Old Lace", "#FDF5E6"), ("Olive", "#808000"),
    ("Olive Drab", "#6B8E23"), ("Orange", "#FFA500"), ("Orange Red", "#FF4500"), ("Orchid", "#DA70D6"),
    ("Pale Goldenrod", "#EEE8AA"), ("Pale Green", "#98FB98"), ("Pale Turquoise", "#AFEEEE"),
    ("Pale Violet Red", "#DB7093"), ("Papaya Whip", "#FFEFD5"), ("Peach Puff", "#FFDAB9"), ("Peru", "#CD853F"),
    ("Pink", "#FFC0CB"), ("Plum", "#DDA0DD"), ("Powder Blue", "#B0E0E6"), ("Purple", "#800080"),
    ("Rebecca Purple", "#663399"), ("Red", "#FF0000"), ("Rosy Brown", "#BC8F8F"), ("Royal Blue", "#4169E1"),
    ("Saddle Brown", "#8B4513"), ("Salmon", "#FA8072"), ("Sandy Brown", "#F4A460"), ("Sea Green", "#2E8B57"),
    ("Seashell", "#FFF5EE"), ("Sienna", "#A0522D"), ("Silver", "#C0C0C0"), ("Sky Blue", "#87CEEB"),
    ("Slate Blue", "#6A5ACD"), ("Slate Grey", "#708090"), ("Snow", "#FFFAFA"), ("Spring Green", "#00FF7F"),
    ("Steel Blue", "#4682B4"), ("Tan", "#D2B48C"), ("Teal", "#008080"), ("Thistle", "#D8BFD8"),
    ("Tomato", "#FF6347"), ("Turquoise", "#40E0D0"), ("Violet", "#EE82EE"), ("Wheat", "#F5DEB3"),
    ("White", "#FFFFFF"), ("White Smoke", "#F5F5F5"), ("Yellow", "#FFFF00"), ("Yellow Green", "#9ACD32"),
]

/// Every name the app knows: the web colours, then the longer list for the gaps between them.
/// Where both name the very same colour, the web name is the one kept.
let allNamedColours: [(name: String, hex: String)] = {
    var seen = Set(namedColours.map { $0.hex })
    return namedColours + moreNamedColours.filter { seen.insert($0.hex).inserted }
}()

private let namedLab: [(name: String, lab: (l: Double, a: Double, b: Double))] = allNamedColours.compactMap { n in
    ColourValues(n.hex).map { (n.name, labOf($0.unit)) }
}

private var nameCache: [String: String] = [:]

/// The nearest colour name, judged perceptually.
func colourName(_ hex: String) -> String {
    guard let v = ColourValues(hex) else { return hex }
    if let hit = nameCache[v.hex] { return hit }
    let p = labOf(v.unit)
    var best = "", bestD = Double.greatestFiniteMagnitude
    for n in namedLab {
        let d = (p.l - n.lab.l) * (p.l - n.lab.l) + (p.a - n.lab.a) * (p.a - n.lab.a) + (p.b - n.lab.b) * (p.b - n.lab.b)
        if d < bestD { bestD = d; best = n.name }
    }
    nameCache[v.hex] = best
    return best
}

/// "Steel Blue" → "steel-blue". Safe in CSS, code and file names.
func slug(_ s: String) -> String {
    var out = "", dash = false
    for ch in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
        if ch.isLetter || ch.isNumber { out.append(ch); dash = false }
        else if !dash && !out.isEmpty { out.append("-"); dash = true }
    }
    while out.hasSuffix("-") { out.removeLast() }
    return out.isEmpty ? "colour" : out
}

/// Every hex colour found in a piece of text — CSS, JSON, a chat message. In order, no repeats.
func hexColours(in text: String) -> [String] {
    var found: [String] = []
    let chars = Array(text)
    var i = 0
    while i < chars.count {
        guard chars[i] == "#" else { i += 1; continue }
        var j = i + 1
        while j < chars.count, chars[j].isHexDigit, j - i <= 8 { j += 1 }
        let digits = String(chars[(i + 1)..<j])
        let boundary = j >= chars.count || !(chars[j].isLetter || chars[j].isNumber)
        if boundary, [3, 6, 8].contains(digits.count) {
            var six = digits
            if digits.count == 3 { six = digits.map { "\($0)\($0)" }.joined() }
            if digits.count == 8 { six = String(digits.prefix(6)) } // drop alpha
            if let hex = normaliseHex(six), !found.contains(hex) { found.append(hex) }
        }
        i = max(j, i + 1)
    }
    return found
}
