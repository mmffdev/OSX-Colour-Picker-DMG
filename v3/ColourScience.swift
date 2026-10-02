import Foundation

// ---------- cLab's colour maths: the artists' wheel, a perceptual space, and the harmony rules ----------
//
// The wheel is the painters' one (red, yellow and blue a third of a turn apart), which is what
// harmony rules were written for: opposite red sits green, not cyan. Adobe Color uses the same.
// OKLCH (Björn Ottosson's Oklab, as lightness / chroma / hue) is used wherever colours have to be
// compared by eye, because equal steps in it look equal.

struct OKLCH: Equatable {
    /// 0 (black) to 1 (white).
    var l: Double
    /// 0 (grey) upwards; the most a screen can show depends on lightness and hue.
    var c: Double
    /// Degrees, 0–360.
    var h: Double
}

private func oklabToLinear(_ l: Double, _ a: Double, _ b: Double) -> (r: Double, g: Double, b: Double) {
    let l_ = l + 0.3963377774 * a + 0.2158037573 * b
    let m_ = l - 0.1055613458 * a - 0.0638541728 * b
    let s_ = l - 0.0894841775 * a - 1.2914855480 * b
    let x = l_ * l_ * l_, y = m_ * m_ * m_, z = s_ * s_ * s_
    return (4.0767416621 * x - 3.3077115913 * y + 0.2309699292 * z,
            -1.2684380046 * x + 2.6097574011 * y - 0.3413193965 * z,
            -0.0041960863 * x - 0.7034186147 * y + 1.7076147010 * z)
}

private func linear(_ v: OKLCH) -> (r: Double, g: Double, b: Double) {
    let t = v.h * .pi / 180
    return oklabToLinear(v.l, v.c * cos(t), v.c * sin(t))
}

private func fromLinear(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

private func turned(_ h: Double) -> Double { (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

/// OKLCH from sRGB 0–1.
func oklchOf(_ rgb: (r: Double, g: Double, b: Double)) -> OKLCH {
    let r = toLinear(rgb.r), g = toLinear(rgb.g), b = toLinear(rgb.b)
    let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    let l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    let a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    let b2 = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    let chroma = (a * a + b2 * b2).squareRoot()
    // A grey has no hue; 0 keeps it steady rather than jumping about on rounding noise.
    return OKLCH(l: l, c: chroma, h: chroma < 1e-4 ? 0 : turned(atan2(b2, a) * 180 / .pi))
}

extension ColourValues {
    var oklch: OKLCH { let u = unit; return oklchOf(u) }
}

/// Whether a screen (sRGB) can show the colour as it stands.
func displayable(_ v: OKLCH) -> Bool {
    let c = linear(v), slack = 1e-4
    return min(c.r, c.g, c.b) >= -slack && max(c.r, c.g, c.b) <= 1 + slack
}

/// The strongest chroma a screen can show at this lightness and hue.
func maxChroma(l: Double, h: Double) -> Double {
    guard l > 0, l < 1 else { return 0 }
    // Found from the top down: near blue the screen's range has a dent in it, so a colour can be
    // a hair outside part-way along and back inside further out.
    let steps = 64, top = 0.4
    guard var lo = (0..<steps).reversed().map({ top * Double($0) / Double(steps) }).first(where: { displayable(OKLCH(l: l, c: $0, h: h)) })
    else { return 0 }
    var hi = lo + top / Double(steps)
    for _ in 0..<16 {
        let mid = (lo + hi) / 2
        if displayable(OKLCH(l: l, c: mid, h: h)) { lo = mid } else { hi = mid }
    }
    return lo
}

/// sRGB 0–1, with anything a screen cannot show clipped channel by channel.
func screenRGB(_ v: OKLCH) -> (r: Double, g: Double, b: Double) {
    let c = linear(v)
    func channel(_ x: Double) -> Double { fromLinear(min(max(x, 0), 1)) }
    return (channel(c.r), channel(c.g), channel(c.b))
}

/// "#RRGGBB". A colour too strong for the screen keeps its lightness and hue and gives up chroma.
func hexFrom(_ v: OKLCH) -> String {
    var v = OKLCH(l: min(max(v.l, 0), 1), c: max(v.c, 0), h: v.h)
    if !displayable(v) { v.c = min(v.c, maxChroma(l: v.l, h: v.h)) } // inside the dent, the clip is a hair's breadth
    let c = screenRGB(v)
    func byte(_ x: Double) -> Int { Int((x * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
}

// ---------- The artists' wheel ----------

/// Wheel angle against screen hue (the H of HSB), every 15 degrees: the table behind Adobe's wheel.
/// It gives the warm colours half the circle, so yellow sits a third of the way round from red and
/// blue two thirds, as on a painter's wheel.
private let artistsWheel: [(angle: Double, hue: Double)] = [
    (0, 0), (15, 8), (30, 17), (45, 26), (60, 34), (75, 41), (90, 48), (105, 54), (120, 60), (135, 81), (150, 103),
    (165, 123), (180, 138), (195, 155), (210, 171), (225, 187), (240, 204), (255, 219), (270, 234), (285, 251),
    (300, 267), (315, 282), (330, 298), (345, 329), (360, 360),
]

/// The screen hue at an angle on the wheel.
func screenHue(atWheel angle: Double) -> Double {
    let a = turned(angle)
    guard let i = artistsWheel.lastIndex(where: { $0.angle <= a }), i + 1 < artistsWheel.count else { return 0 }
    let lo = artistsWheel[i], hi = artistsWheel[i + 1]
    return lo.hue + (hi.hue - lo.hue) * (a - lo.angle) / (hi.angle - lo.angle)
}

/// Where a screen hue sits on the wheel.
func wheelAngle(ofHue hue: Double) -> Double {
    let h = turned(hue)
    guard let i = artistsWheel.lastIndex(where: { $0.hue <= h }), i + 1 < artistsWheel.count else { return 0 }
    let lo = artistsWheel[i], hi = artistsWheel[i + 1]
    return lo.angle + (hi.angle - lo.angle) * (h - lo.hue) / (hi.hue - lo.hue)
}

/// sRGB 0–1 from screen hue (degrees), saturation and brightness.
func rgbFrom(hue: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
    let h = turned(hue) / 60, c = v * s
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
    switch h {
    case ..<1: return (c + m, x + m, m)
    case ..<2: return (x + m, c + m, m)
    case ..<3: return (m, c + m, x + m)
    case ..<4: return (m, x + m, c + m)
    case ..<5: return (x + m, m, c + m)
    default: return (c + m, m, x + m)
    }
}

// ---------- A colour on the wheel ----------

/// `h` is the angle on the artists' wheel. `s` is the distance from the centre: 0 is white, 1 the
/// pure hue. `v` is brightness: 1 is the colour the wheel shows at that spot, 0 is black.
struct LabNode: Codable, Equatable {
    var h: Double
    var s: Double
    var v: Double
    var locked = false

    init(h: Double, s: Double, v: Double, locked: Bool = false) {
        self.h = turned(h); self.s = min(max(s, 0), 1); self.v = min(max(v, 0), 1); self.locked = locked
    }

    init?(hex: String) {
        guard let c = ColourValues(hex)?.hsvUnit else { return nil }
        self.init(h: wheelAngle(ofHue: c.h), s: c.s, v: c.v)
    }

    var rgb: (r: Double, g: Double, b: Double) { rgbFrom(hue: screenHue(atWheel: h), s: s, v: v) }
    /// How the eye reads it: lightness, chroma and perceptual hue.
    var oklch: OKLCH { oklchOf(rgb) }

    var hex: String {
        let c = rgb
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }

    /// The same place on the wheel for another hue.
    func turn(_ degrees: Double) -> LabNode { LabNode(h: h + degrees, s: s, v: v) }
    /// Towards black by `k` (0–1), and a step in from the rim so it shows as a circle of its own.
    func darker(_ k: Double) -> LabNode { LabNode(h: h, s: s * 0.85, v: v * (1 - k)) }
    /// Towards white by `k` (0–1): paler, and brought up to full brightness.
    func lighter(_ k: Double) -> LabNode { LabNode(h: h, s: s * (1 - k * 0.85), v: v + (1 - v) * k) }

    /// The same hue made as light to the eye as `lightness` (OKLCH, 0–1). Brightness is tried
    /// first; a hue that cannot get that light at this strength gives up strength to get there.
    func lit(_ lightness: Double) -> LabNode {
        func search(_ make: (Double) -> LabNode, rising: Bool) -> LabNode {
            var lo = 0.0, hi = 1.0
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if (make(mid).oklch.l < lightness) == rising { lo = mid } else { hi = mid }
            }
            return make((lo + hi) / 2)
        }
        if LabNode(h: h, s: s, v: 1).oklch.l >= lightness { return search({ LabNode(h: h, s: s, v: $0) }, rising: true) }
        return search({ LabNode(h: h, s: s * $0, v: 1) }, rising: false)
    }

    /// Where it sits on a wheel of radius 1 centred on the origin, x right and y up.
    var point: (x: Double, y: Double) { (s * cos(h * .pi / 180), s * sin(h * .pi / 180)) }
    /// Hue and strength for a point on that wheel; beyond the rim counts as on it.
    static func polar(x: Double, y: Double) -> (h: Double, s: Double) {
        (turned(atan2(y, x) * 180 / .pi), min((x * x + y * y).squareRoot(), 1))
    }
}

// ---------- Harmony rules ----------

enum LabRule: String, CaseIterable, Codable {
    case custom, analogous, complementary, splitComplementary, triad, square, compound, shades, monochromatic

    var title: String {
        switch self {
        case .custom: return "Custom"
        case .analogous: return "Analogous"
        case .complementary: return "Complementary"
        case .splitComplementary: return "Split Complementary"
        case .triad: return "Triad"
        case .square: return "Square"
        case .compound: return "Compound"
        case .shades: return "Shades"
        case .monochromatic: return "Monochromatic"
        }
    }

    /// One plain line on why the rule works.
    var why: String {
        switch self {
        case .custom: return "No rule: every colour moves on its own. Trust your eye."
        case .analogous: return "Neighbours on the wheel share most of their hue, so they sit together calmly, like a sunset."
        case .complementary: return "Opposite hues are as different as two colours can be, so each makes the other look stronger."
        case .splitComplementary: return "The two neighbours of the opposite hue give contrast with less tension than a straight opposite."
        case .triad: return "Three hues a third of a turn apart pull evenly against each other, so none of them wins."
        case .square: return "Four hues a quarter turn apart: two opposite pairs. Lively, so let one colour lead."
        case .compound: return "A neighbour for calm, plus the pair either side of the opposite for contrast."
        case .shades: return "One hue at one strength, changed only in lightness. It cannot clash."
        case .monochromatic: return "One hue, varied in lightness and strength. Depth without a second colour."
        }
    }

    /// Five colours built around `base`, and where the base sits among them. Custom has no arrangement.
    ///
    /// `vivid` runs from 0 to 1. At 1 a turned colour sits at the same place on the wheel as the
    /// base, for its own hue: as strong and as bright as the wheel shows it. At 0 it is made as
    /// light to the eye as the base instead, which is calmer but dulls hues that are only strong
    /// when lighter or darker (a yellow as dark as a strong blue is olive).
    func arrangement(around base: LabNode, vivid: Double = 1) -> (nodes: [LabNode], base: Int)? {
        let b = LabNode(h: base.h, s: base.s, v: base.v)
        func turn(_ degrees: Double) -> LabNode {
            let n = b.turn(degrees)
            guard vivid < 1 else { return n }
            let even = b.oklch.l
            return n.lit(even + vivid * (n.oklch.l - even))
        }
        switch self {
        case .custom: return nil
        case .analogous: return ([turn(-30), turn(-15), b, turn(15), turn(30)], 2)
        case .complementary: return ([b, turn(180), b.darker(0.45), turn(180).darker(0.45), b.lighter(0.6)], 0)
        case .splitComplementary: return ([b, turn(150), turn(210), b.lighter(0.6), turn(150).lighter(0.6)], 0)
        case .triad: return ([b, turn(120), turn(240), b.darker(0.45), turn(120).lighter(0.6)], 0)
        case .square: return ([b, turn(90), turn(180), turn(270), b.darker(0.45)], 0)
        case .compound: return ([b, turn(30), turn(165), turn(195), b.darker(0.45)], 0)
        case .shades:
            // Four more brightnesses of the same colour, skipping the step the base already fills.
            let steps = [1.0, 0.82, 0.64, 0.46, 0.28]
            let taken = steps.min { abs($0 - b.v) < abs($1 - b.v) }
            return ([b] + steps.filter { $0 != taken }.map { LabNode(h: b.h, s: b.s, v: $0) }, 0)
        case .monochromatic: return ([b, b.darker(0.4), b.lighter(0.35), b.lighter(0.6), b.lighter(0.85)], 0)
        }
    }
}

// ---------- What the wheel is holding ----------

struct LabState: Codable, Equatable {
    static let most = 8

    var rule = LabRule.analogous
    var nodes: [LabNode] = []
    var base = 0
    /// 0 keeps every colour as light as the base; 1 lets each hue be as strong as the wheel shows it.
    var vivid = 1.0

    /// Custom has no arrangement of its own, so it starts from the analogous one.
    init(rule: LabRule = .analogous, base: LabNode) {
        self.rule = rule == .custom ? .analogous : rule
        nodes = [base]
        rearrange()
        self.rule = rule
    }

    var hexes: [String] { nodes.map { $0.hex } }

    /// Rebuilds the colours from the base by the rule. Locked colours stay as they are.
    mutating func rearrange() {
        guard nodes.indices.contains(base), let made = rule.arrangement(around: nodes[base], vivid: vivid) else { return }
        let kept = nodes
        nodes = made.nodes
        nodes[made.base].locked = kept[base].locked
        // A lock belongs to a place in the strip; places line up when the base has not moved.
        if kept.count == nodes.count, made.base == base {
            for i in nodes.indices where i != base && kept[i].locked { nodes[i] = kept[i] }
        }
        base = made.base
    }

    mutating func setRule(_ new: LabRule) {
        let around = nodes[base]
        rule = new
        guard new != .custom else { return }
        nodes = [around]; base = 0
        rearrange()
    }

    /// A colour dragged to a new hue and strength. Under a rule the rest follow: the base carries
    /// everything with it, and any other colour turns and scales the whole arrangement.
    mutating func move(_ i: Int, h: Double, s: Double) {
        guard nodes.indices.contains(i) else { return }
        if rule == .custom || nodes[i].locked {
            nodes[i] = LabNode(h: h, s: s, v: nodes[i].v, locked: nodes[i].locked)
            return
        }
        let was = nodes[i], b = nodes[base]
        let scale = was.s > 0.02 ? s / was.s : 1
        nodes[base] = LabNode(h: b.h + (h - was.h), s: i == base ? s : min(b.s * scale, 1), v: b.v, locked: b.locked)
        rearrange()
    }

    mutating func setBrightness(_ v: Double, of i: Int) {
        guard nodes.indices.contains(i) else { return }
        nodes[i] = LabNode(h: nodes[i].h, s: nodes[i].s, v: v, locked: nodes[i].locked)
        if rule != .custom, i == base { rearrange() }
    }

    mutating func setVivid(_ amount: Double) {
        vivid = min(max(amount, 0), 1)
        rearrange()
    }

    mutating func makeBase(_ i: Int) {
        guard nodes.indices.contains(i) else { return }
        if rule == .custom { base = i; return }
        nodes = [nodes[i]]; base = 0
        rearrange()
    }

    mutating func toggleLock(_ i: Int) {
        guard nodes.indices.contains(i) else { return }
        nodes[i].locked.toggle()
    }

    /// Adding and removing colours leaves the rule behind: a rule decides how many there are.
    mutating func remove(_ i: Int) {
        guard nodes.count > 1, nodes.indices.contains(i) else { return }
        rule = .custom
        nodes.remove(at: i)
        if base == i { base = 0 } else if base > i { base -= 1 }
    }

    mutating func add() {
        guard nodes.count < LabState.most, let last = nodes.last else { return }
        rule = .custom
        // The golden angle lands each new hue as far as it can from the ones already there.
        nodes.append(LabNode(h: last.h + 137.508, s: last.s, v: last.v))
    }

    /// A fresh roll. `unit` supplies numbers in 0..<1. Locked colours survive it.
    mutating func randomise(_ unit: () -> Double) {
        // A roll lands out towards the rim and near full brightness, so it starts colourful.
        func fresh() -> LabNode { LabNode(h: unit() * 360, s: 0.6 + unit() * 0.4, v: 0.75 + unit() * 0.25) }
        if rule == .custom {
            var hue = unit() * 360
            for i in nodes.indices where !nodes[i].locked {
                let n = fresh()
                nodes[i] = LabNode(h: hue, s: n.s, v: n.v)
                hue += 137.508
            }
        } else if nodes[base].locked {
            // The base is staying put, so the roll changes the rule instead.
            let others = LabRule.allCases.filter { $0 != .custom && $0 != rule }
            setRule(others[min(Int(unit() * Double(others.count)), others.count - 1)])
        } else {
            nodes[base] = fresh()
            rearrange()
        }
    }
}

/// Steps back and forward through what the wheel has held.
struct LabHistory {
    private(set) var past: [LabState] = []
    private(set) var future: [LabState] = []
    private let most = 100

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Call with the state as it was before a change that has now happened.
    mutating func record(_ before: LabState, now: LabState) {
        guard before != now else { return }
        past.append(before)
        if past.count > most { past.removeFirst() }
        future = []
    }

    mutating func undo(from now: LabState) -> LabState? {
        guard let back = past.popLast() else { return nil }
        future.append(now)
        return back
    }

    mutating func redo(from now: LabState) -> LabState? {
        guard let on = future.popLast() else { return nil }
        past.append(now)
        return on
    }
}
