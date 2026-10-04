import AppKit

// ---------- The gamut map: where colours sit, and what each screen and press can hold ----------
//
// Three views of the same question, "can this device show or print this colour?":
//
//   Lab a*b*    Round, grey in the middle, hue as the angle and strength as the distance out. The
//               space colour differences are measured in, so what looks far apart is far apart.
//               A gamut here changes shape with lightness, so for one swatch the outlines are cut
//               at that swatch's own lightness; for a palette they are each gamut at its widest.
//   1976 u'v'   The horseshoe, redrawn so distances are far more even. Screens and video use it.
//   1931 xy     The horseshoe everyone recognises. Greens look far bigger than they are.
//
// The two horseshoes leave lightness out altogether. Whichever view is showing, the counts beside
// it and the ring round a swatch are worked out from the colour itself, not from the picture.

enum GamutView: Int, CaseIterable {
    case lab, uv, xy

    var title: String { ["Lab a*b*", "1976 u\u{2032}v\u{2032}", "1931 xy"][rawValue] }
    var about: String {
        switch self {
        case .lab: return "Grey in the middle, hue round the edge. Distances are true to the eye."
        case .uv: return "The horseshoe with even distances. Lightness is left out."
        case .xy: return "The classic horseshoe. Greens look bigger than they are; lightness is left out."
        }
    }
}

struct GamutPoint: Equatable {
    var x: Double, y: Double
}

/// The arithmetic of the map, apart from the drawing so the self-test can reach it.
enum GamutMaths {
    /// The spectral locus, 380 to 700 nm: CIE 1931 2-degree observer, the chromaticity of each wavelength.
    static let locus: [(nm: Int, x: Double, y: Double)] = [
        (380, 0.1741, 0.0050), (390, 0.1738, 0.0049), (400, 0.1733, 0.0048), (410, 0.1726, 0.0048), (420, 0.1714, 0.0051),
        (430, 0.1689, 0.0069), (440, 0.1644, 0.0109), (450, 0.1566, 0.0177), (460, 0.1440, 0.0297), (470, 0.1241, 0.0578),
        (475, 0.1096, 0.0868), (480, 0.0913, 0.1327), (485, 0.0687, 0.2007), (490, 0.0454, 0.2950), (495, 0.0235, 0.4127),
        (500, 0.0082, 0.5384), (505, 0.0039, 0.6548), (510, 0.0139, 0.7502), (515, 0.0389, 0.8120), (520, 0.0743, 0.8338),
        (525, 0.1142, 0.8262), (530, 0.1547, 0.8059), (540, 0.2296, 0.7543), (550, 0.3016, 0.6923), (560, 0.3731, 0.6245),
        (570, 0.4441, 0.5547), (580, 0.5125, 0.4866), (590, 0.5752, 0.4242), (600, 0.6270, 0.3725), (610, 0.6658, 0.3340),
        (620, 0.6915, 0.3083), (630, 0.7079, 0.2920), (640, 0.7190, 0.2809), (650, 0.7260, 0.2740), (660, 0.7300, 0.2700),
        (670, 0.7320, 0.2680), (680, 0.7334, 0.2666), (690, 0.7344, 0.2656), (700, 0.7347, 0.2653),
    ]

    private static let d50 = (x: 0.34567, y: 0.35850), d65 = (x: 0.3127, y: 0.3290)
    /// The master is kept under D50; the horseshoes are drawn round D65, as screens are.
    private static let toD65 = bradford(from: d50, to: d65)
    private static let fromD65 = bradford(from: d65, to: d50)
    static let white = GamutPoint(x: d65.x, y: d65.y)

    /// A colour's place on the 1931 diagram. Black has no chromaticity and is put at the white point.
    static func xy(_ master: XYZ) -> GamutPoint {
        let v = multiply(toD65, [master.x, master.y, master.z]), sum = v[0] + v[1] + v[2]
        return sum > 1e-9 ? GamutPoint(x: v[0] / sum, y: v[1] / sum) : white
    }

    /// The same place on the 1976 diagram.
    static func uv(_ p: GamutPoint) -> GamutPoint {
        let d = -2 * p.x + 12 * p.y + 3
        return GamutPoint(x: 4 * p.x / d, y: 9 * p.y / d)
    }

    /// And back, for colouring the 1976 diagram.
    static func xy(fromUV p: GamutPoint) -> GamutPoint {
        let d = 6 * p.x - 16 * p.y + 12
        return GamutPoint(x: 9 * p.x / d, y: 4 * p.y / d)
    }

    static func point(_ master: XYZ, in view: GamutView) -> GamutPoint {
        switch view {
        case .lab: let lab = master.lab; return GamutPoint(x: lab.a, y: lab.b)
        case .xy: return xy(master)
        case .uv: return uv(xy(master))
        }
    }

    /// The horseshoe's edge in a view, from violet round to red. Empty for the round view.
    static func locus(in view: GamutView) -> [GamutPoint] {
        switch view {
        case .lab: return []
        case .xy: return locus.map { GamutPoint(x: $0.x, y: $0.y) }
        case .uv: return locus.map { uv(GamutPoint(x: $0.x, y: $0.y)) }
        }
    }

    /// The colour a place on the 1931 diagram is drawn in: as bright as sRGB can make it, pulled into range.
    static func display(xy p: GamutPoint) -> [Double] {
        guard p.y > 1e-6 else { return [0, 0, 0] }
        let m = multiply(fromD65, [p.x / p.y, 1, (1 - p.x - p.y) / p.y])
        let linear = RGBSpace.srgb.linearValues(of: XYZ(x: m[0], y: m[1], z: m[2])).map { max($0, 0) }
        let top = max(linear.max() ?? 0, 1e-9)
        return linear.map { RGBSpace.srgb.encoded($0 / top) }
    }

    /// Whether a place on the 1931 diagram is inside the horseshoe.
    static func visible(xy p: GamutPoint) -> Bool {
        var inside = false, j = locus.count - 1
        for i in locus.indices {
            let a = locus[i], b = locus[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    // MARK: Outlines

    /// A screen space's triangle on a horseshoe: its red, green and blue.
    static func corners(of space: RGBSpace, in view: GamutView) -> [GamutPoint] {
        [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]].map { point(space.master(of: $0), in: view) }
    }

    /// A press's six-sided outline on a horseshoe: its solid inks and the overprints between them.
    static func corners(ofPress press: String, in view: GamutView) -> [GamutPoint] {
        let builds: [[Double]] = [[1, 0, 0, 0], [1, 1, 0, 0], [0, 1, 0, 0], [0, 1, 1, 0], [0, 0, 1, 0], [1, 0, 1, 0]]
        return builds.compactMap { PrintBuild.master(ofInks: $0, press: press).map { point($0, in: view) } }
    }

    static let hueSteps = 72

    /// How strong a colour of one hue can be at one lightness and still be held: the edge of a
    /// gamut along one spoke of the round view. Found by halving, from grey outwards.
    static func strongest(hue degrees: Double, lightness: Double, holds: (XYZ) -> Bool) -> Double {
        let angle = degrees * .pi / 180
        guard holds(LabD50(l: lightness, a: 0, b: 0).xyz) else { return 0 }
        var low = 0.0, high = 240.0
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if holds(LabD50(l: lightness, a: mid * cos(angle), b: mid * sin(angle)).xyz) { low = mid } else { high = mid }
        }
        return low
    }

    /// A gamut cut at one lightness, as a closed outline on the round view.
    static func slice(lightness: Double, steps: Int = hueSteps, holds: (XYZ) -> Bool) -> [GamutPoint] {
        (0..<steps).map { at in
            let degrees = Double(at) * 360 / Double(steps), c = strongest(hue: degrees, lightness: lightness, holds: holds)
            return GamutPoint(x: c * cos(degrees * .pi / 180), y: c * sin(degrees * .pi / 180))
        }
    }

    /// A gamut at its widest whatever the lightness: for each hue, the strongest colour found
    /// anywhere on the gamut's surface. `surface` is a spread of colours from that surface.
    static func widest(surface: [XYZ], steps: Int = hueSteps) -> [GamutPoint] {
        var best = [Double](repeating: 0, count: steps)
        for colour in surface {
            let lab = colour.lab, chroma = hypot(lab.a, lab.b)
            guard chroma > 1 else { continue }
            var degrees = atan2(lab.b, lab.a) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let bin = Int((degrees / 360 * Double(steps)).rounded()) % steps
            best[bin] = max(best[bin], chroma)
        }
        // A hue no sample fell on takes the mean of its nearest neighbours that had one.
        let filled = best
        for at in 0..<steps where filled[at] == 0 {
            var before = 0.0, after = 0.0
            for step in 1..<steps { if filled[(at + steps - step) % steps] > 0 { before = filled[(at + steps - step) % steps]; break } }
            for step in 1..<steps { if filled[(at + step) % steps] > 0 { after = filled[(at + step) % steps]; break } }
            best[at] = (before + after) / 2
        }
        // The samples fall unevenly on the hues, which leaves the edge ragged: each hue takes the
        // most of itself and its neighbours, then the three are averaged.
        func around(_ values: [Double], _ at: Int) -> (before: Double, here: Double, after: Double) {
            (values[(at + steps - 1) % steps], values[at], values[(at + 1) % steps])
        }
        var raised = [Double](repeating: 0, count: steps), smooth = [Double](repeating: 0, count: steps)
        for at in 0..<steps { let v = around(best, at); raised[at] = max(v.before, v.here, v.after) }
        for at in 0..<steps { let v = around(raised, at); smooth[at] = v.before * 0.25 + v.here * 0.5 + v.after * 0.25 }
        return (0..<steps).map { at in
            let angle = Double(at) * 2 * .pi / Double(steps)
            return GamutPoint(x: smooth[at] * cos(angle), y: smooth[at] * sin(angle))
        }
    }

    /// Colours spread over the six faces of a cube of three amounts, each 0 to 1: the surface of
    /// a screen space, or of a press's cyan, magenta and yellow.
    static func cubeFaces(_ n: Int) -> [[Double]] {
        var out: [[Double]] = []
        for axis in 0..<3 {
            for end in [0.0, 1.0] {
                for i in 0...n {
                    for j in 0...n {
                        var v = [Double(i) / Double(n), Double(j) / Double(n)]
                        v.insert(end, at: axis)
                        out.append(v)
                    }
                }
            }
        }
        return out
    }

    private static var cache: [String: [GamutPoint]] = [:]
    private static func cached(_ key: String, _ make: () -> [GamutPoint]) -> [GamutPoint] {
        if let have = cache[key] { return have }
        let made = make()
        cache[key] = made
        return made
    }

    /// A screen space on the round view: cut at `lightness`, or at its widest when nil.
    static func outline(of space: RGBSpace, lightness: Double?) -> [GamutPoint] {
        if let l = lightness {
            return cached("\(space.rawValue)@\(Int(l.rounded()))") { slice(lightness: l.rounded()) { $0.fits(space) } }
        }
        return cached("\(space.rawValue)@widest") { widest(surface: cubeFaces(60).map { space.master(of: $0) }) }
    }

    /// Whether a press can print a colour as it is: sent through the profile and back, it returns
    /// within what the eye can tell apart.
    static func prints(_ master: XYZ, press: String) -> Bool {
        guard let build = PrintBuild.of(master, press: press, intent: .relative) else { return false }
        return deltaE2000(build.printed.lab, master.lab) <= Rendering.visible
    }

    /// A press on the round view: cut at `lightness`, or at its widest when nil. Empty when the
    /// press profile is not on this Mac.
    static func outline(ofPress press: String, lightness: Double?) -> [GamutPoint] {
        guard PressProfiles.space(named: press) != nil else { return [] }
        if let l = lightness {
            return cached("press:\(press)@\(Int(l.rounded()))") { slice(lightness: l.rounded(), steps: 48) { prints($0, press: press) } }
        }
        return cached("press:\(press)@widest") {
            widest(surface: cubeFaces(22).compactMap { PrintBuild.master(ofInks: $0 + [0], press: press) })
        }
    }
}

/// Draws the map: the chart on the left, what the lines mean and how many colours each holds on the right.
enum GamutChart {
    private struct Domain {
        var minX: Double, maxX: Double, minY: Double, maxY: Double
        func place(_ p: GamutPoint, in rect: NSRect) -> NSPoint {
            NSPoint(x: rect.minX + CGFloat((p.x - minX) / (maxX - minX)) * rect.width,
                    y: rect.maxY - CGFloat((p.y - minY) / (maxY - minY)) * rect.height)
        }
    }

    private struct Line {
        let name: String
        let points: [GamutPoint]
        let colour: NSColor
        let dash: [CGFloat]
        let width: CGFloat
        let held: Int?
    }

    private static var washes: [String: NSImage] = [:]

    /// The colours behind the chart: each place in something like its own colour.
    private static func wash(_ view: GamutView, _ domain: Domain, lightness: Double) -> NSImage? {
        let key = "\(view.rawValue):\(Int(lightness)):\(Int(domain.maxX * 100))"
        if let have = washes[key] { return have }
        // Every pixel is coloured, inside the horseshoe or not: the smooth outline cuts the edge, so
        // the picture's own pixels never show as steps along it.
        let n = 360
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: n * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return nil }
        for row in 0..<n {
            for column in 0..<n {
                let p = GamutPoint(x: domain.minX + (Double(column) + 0.5) / Double(n) * (domain.maxX - domain.minX),
                                   y: domain.maxY - (Double(row) + 0.5) / Double(n) * (domain.maxY - domain.minY))
                var rgb: [Double]?
                switch view {
                case .xy: rgb = GamutMaths.display(xy: p)
                case .uv: rgb = GamutMaths.display(xy: GamutMaths.xy(fromUV: p))
                case .lab:
                    // As strong as sRGB can show at this lightness, in the place's own hue.
                    var low = 0.0, high = 1.0
                    for _ in 0..<7 {
                        let mid = (low + high) / 2
                        if LabD50(l: lightness, a: p.x * mid, b: p.y * mid).xyz.fits(.srgb) { low = mid } else { high = mid }
                    }
                    rgb = RGBSpace.srgb.values(of: LabD50(l: lightness, a: p.x * low, b: p.y * low).xyz)
                }
                let at = (row * n + column) * 4
                if let rgb = rgb {
                    for c in 0..<3 { data[at + c] = UInt8((min(max(rgb[c], 0), 1) * 255).rounded()) }
                    data[at + 3] = 255
                } else {
                    for c in 0..<4 { data[at + c] = 0 }
                }
            }
        }
        let image = NSImage(size: NSSize(width: n, height: n))
        image.addRepresentation(rep)
        washes[key] = image
        return image
    }

    private static func text(_ s: String, _ colour: NSColor, size: CGFloat = TextSize.caption, weight: NSFont.Weight = .regular) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour])
    }

    private static func path(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        for (at, p) in points.enumerated() { if at == 0 { path.move(to: p) } else { path.line(to: p) } }
        path.close()
        return path
    }

    /// A curve through every point, for an edge that is a curve in truth: the spectrum's edge and
    /// a gamut cut through Lab. `closed` carries the curve round from the last point to the first;
    /// otherwise the ends are joined by a straight line, as the line of purples is.
    private static func curve(_ points: [NSPoint], closed: Bool) -> NSBezierPath {
        let path = NSBezierPath(), n = points.count
        guard n > 2 else { return Self.path(points) }
        func at(_ i: Int) -> NSPoint { closed ? points[(i + n) % n] : points[min(max(i, 0), n - 1)] }
        path.move(to: points[0])
        for i in 0..<(closed ? n : n - 1) {
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            path.curve(to: p2, controlPoint1: NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                       controlPoint2: NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.close()
        return path
    }

    /// Draws into `bounds` of a flipped view. `detailed` adds scales and wavelengths, for the full page.
    static func draw(keys: [String], view: GamutView, in bounds: NSRect, detailed: Bool) {
        let colours = keys.compactMap { key in (ColourKeys.definition(of: key) ?? ColourDefinition.of(hex: key)).map { (key: key, colour: $0) } }
        guard !colours.isEmpty else { return }
        let press = PrintCondition.current.press ?? PressProfiles.generic
        let hasPress = PressProfiles.space(named: press) != nil
        // One swatch: the round view is cut at its lightness. A palette: each gamut at its widest.
        let lightness: Double? = colours.count == 1 ? min(max(colours[0].colour.master.lab.l, 1), 99) : nil
        let dots = colours.map { GamutMaths.point($0.colour.master, in: view) }
        let printable = colours.map { hasPress && GamutMaths.prints($0.colour.master, press: press) }
        func held(_ space: RGBSpace) -> Int { colours.filter { $0.colour.master.fits(space) }.count }

        let ink = NSColor.labelColor
        var lines: [Line] = []
        let spaces: [(RGBSpace, [CGFloat])] = [(.srgb, []), (.displayP3, [6, 3]), (.rec2020, [1.5, 3])]
        for (space, dash) in spaces {
            let points = view == .lab ? GamutMaths.outline(of: space, lightness: lightness) : GamutMaths.corners(of: space, in: view)
            lines.append(Line(name: space.name, points: points, colour: ink.withAlphaComponent(0.85), dash: dash, width: 1.5, held: held(space)))
        }
        if hasPress {
            let points = view == .lab ? GamutMaths.outline(ofPress: press, lightness: lightness) : GamutMaths.corners(ofPress: press, in: view)
            lines.append(Line(name: press, points: points, colour: .systemOrange, dash: [], width: 2, held: printable.filter { $0 }.count))
        }

        let domain: Domain
        switch view {
        case .xy: domain = Domain(minX: -0.06, maxX: 0.84, minY: -0.03, maxY: 0.87)
        case .uv: domain = Domain(minX: -0.03, maxX: 0.65, minY: -0.04, maxY: 0.64)
        case .lab:
            let far = (lines.flatMap { $0.points } + dots).map { hypot($0.x, $0.y) }.max() ?? 100
            let r = (max(far, 60) * 1.08 / 10).rounded(.up) * 10
            domain = Domain(minX: -r, maxX: r, minY: -r, maxY: r)
        }

        let side = max(40, min(bounds.height, bounds.width * 0.62))
        let chart = NSRect(x: bounds.minX, y: bounds.minY + (bounds.height - side) / 2, width: side, height: side)
        func place(_ p: GamutPoint) -> NSPoint { domain.place(p, in: chart) }

        Theme.grey(0.05).setFill()
        NSBezierPath(roundedRect: chart, xRadius: 8, yRadius: 8).fill()

        // The colours themselves, faint, inside the horseshoe or the disc.
        let edge = view == .lab ? NSBezierPath(ovalIn: chart.insetBy(dx: 1, dy: 1)) : curve(GamutMaths.locus(in: view).map(place), closed: false)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: chart, xRadius: 8, yRadius: 8).addClip()
        if let image = wash(view, domain, lightness: lightness ?? 65) {
            NSGraphicsContext.saveGraphicsState()
            edge.addClip()
            image.draw(in: chart, from: .zero, operation: .sourceOver, fraction: view == .lab ? 0.5 : 0.75, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            NSGraphicsContext.restoreGraphicsState()
        }

        // The scale: rings of equal strength on the round view, a grid on the horseshoes.
        let faint = ink.withAlphaComponent(0.16)
        faint.setStroke()
        if view == .lab {
            var ring = 50.0
            while ring < domain.maxX {
                let a = place(GamutPoint(x: -ring, y: ring)), b = place(GamutPoint(x: ring, y: -ring))
                let circle = NSBezierPath(ovalIn: NSRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
                circle.lineWidth = 1
                circle.stroke()
                if detailed, ring < domain.maxX - 30 { text("\(Int(ring))", ink.withAlphaComponent(0.5), size: 10).draw(at: NSPoint(x: place(GamutPoint(x: ring, y: 0)).x + 3, y: chart.midY + 2)) }
                ring += 50
            }
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: chart.minX, y: chart.midY)); cross.line(to: NSPoint(x: chart.maxX, y: chart.midY))
            cross.move(to: NSPoint(x: chart.midX, y: chart.minY)); cross.line(to: NSPoint(x: chart.midX, y: chart.maxY))
            cross.lineWidth = 1
            cross.stroke()
            if side > 180 {
                let dim = ink.withAlphaComponent(0.6)
                let labels: [(String, NSPoint, CGFloat, CGFloat)] = [
                    ("+a* Red", NSPoint(x: chart.maxX - 6, y: chart.midY + 3), 1, 0), ("\u{2212}a* Green", NSPoint(x: chart.minX + 6, y: chart.midY + 3), 0, 0),
                    ("+b* Yellow", NSPoint(x: chart.midX + 5, y: chart.minY + 5), 0, 0), ("\u{2212}b* Blue", NSPoint(x: chart.midX + 5, y: chart.maxY - 5), 0, 1),
                ]
                for (word, at, alignX, alignY) in labels {
                    let s = text(word, dim, size: 10), size = s.size()
                    s.draw(at: NSPoint(x: at.x - size.width * alignX, y: at.y - size.height * alignY))
                }
            }
        } else {
            let grid = NSBezierPath()
            var at = 0.0
            while at <= max(domain.maxX, domain.maxY) {
                if at <= domain.maxX { let x = place(GamutPoint(x: at, y: 0)).x; grid.move(to: NSPoint(x: x, y: chart.minY)); grid.line(to: NSPoint(x: x, y: chart.maxY)) }
                if at <= domain.maxY { let y = place(GamutPoint(x: 0, y: at)).y; grid.move(to: NSPoint(x: chart.minX, y: y)); grid.line(to: NSPoint(x: chart.maxX, y: y)) }
                if detailed, at > 0 {
                    let label = text(String(format: "%.1f", at), ink.withAlphaComponent(0.5), size: 10)
                    if at <= domain.maxX { label.draw(at: NSPoint(x: place(GamutPoint(x: at, y: 0)).x + 3, y: chart.maxY - 15)) }
                    if at <= domain.maxY { label.draw(at: NSPoint(x: chart.minX + 4, y: place(GamutPoint(x: 0, y: at)).y + 2)) }
                }
                at += 0.1
            }
            grid.lineWidth = 1
            grid.stroke()
            ink.withAlphaComponent(0.55).setStroke()
            edge.lineWidth = 1
            edge.stroke()
            if detailed {
                // Wavelengths round the edge, set just outside it.
                let middle = place(view == .xy ? GamutMaths.white : GamutMaths.uv(GamutMaths.white))
                for entry in GamutMaths.locus where [460, 480, 490, 500, 510, 520, 540, 560, 580, 600, 620].contains(entry.nm) {
                    let raw = GamutPoint(x: entry.x, y: entry.y), p = place(view == .xy ? raw : GamutMaths.uv(raw))
                    let away = hypot(p.x - middle.x, p.y - middle.y), ux = (p.x - middle.x) / away, uy = (p.y - middle.y) / away
                    let label = text("\(entry.nm)", ink.withAlphaComponent(0.6), size: 10), size = label.size()
                    label.draw(at: NSPoint(x: p.x + ux * 14 - size.width / 2, y: p.y + uy * 12 - size.height / 2))
                }
            }
            // The white the screens are built round.
            let w = place(view == .xy ? GamutMaths.white : GamutMaths.uv(GamutMaths.white))
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: w.x - 4, y: w.y)); mark.line(to: NSPoint(x: w.x + 4, y: w.y))
            mark.move(to: NSPoint(x: w.x, y: w.y - 4)); mark.line(to: NSPoint(x: w.x, y: w.y + 4))
            ink.withAlphaComponent(0.7).setStroke()
            mark.lineWidth = 1
            mark.stroke()
        }

        // What each screen and the press can hold.
        for line in lines where line.points.count > 2 {
            // A cut through Lab is a curve; a triangle on a horseshoe is straight lines.
            let outline = view == .lab ? curve(line.points.map(place), closed: true) : path(line.points.map(place))
            outline.lineWidth = line.width
            outline.lineJoinStyle = .round
            if !line.dash.isEmpty { outline.setLineDash(line.dash, count: line.dash.count, phase: 0) }
            line.colour.setStroke()
            outline.stroke()
        }

        // The colours: each a dot in its own colour, ringed in orange when the press cannot print it.
        let radius: CGFloat = detailed ? 7 : 5
        for (at, colour) in colours.enumerated() {
            let p = place(dots[at])
            let dot = NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            if hasPress, !printable[at] {
                let ring = NSBezierPath(ovalIn: NSRect(x: p.x - radius - 4, y: p.y - radius - 4, width: radius * 2 + 8, height: radius * 2 + 8))
                NSColor.systemOrange.setStroke()
                ring.lineWidth = 2
                ring.stroke()
            }
            colour.colour.master.display.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            dot.lineWidth = 3
            dot.stroke()
            NSColor.white.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Beside the chart: what each line is and how many of the colours it holds.
        let left = chart.maxX + 24, width = bounds.maxX - left
        guard width > 120 else { return }
        var y = chart.minY + 2
        let total = colours.count
        for line in lines {
            let sample = NSBezierPath()
            sample.move(to: NSPoint(x: left, y: y + 9)); sample.line(to: NSPoint(x: left + 26, y: y + 9))
            sample.lineWidth = line.width
            if !line.dash.isEmpty { sample.setLineDash(line.dash, count: line.dash.count, phase: 0) }
            line.colour.setStroke()
            sample.stroke()
            let all = line.held == total
            let count = total == 1 ? (all ? "Holds It" : "Cannot Hold It") : "Holds \(line.held ?? 0) Of \(total)"
            let name = text(line.name, ink, size: TextSize.body, weight: .semibold)
            name.draw(with: NSRect(x: left + 36, y: y, width: width - 36, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            text(count, all ? .secondaryLabelColor : .systemOrange, size: TextSize.caption, weight: all ? .regular : .semibold).draw(at: NSPoint(x: left + 36, y: y + 18))
            y += 42
        }
        guard chart.maxY - y > 40 else { return }
        var notes: [String] = []
        if view == .lab {
            notes.append(lightness.map { "Outlines cut at this colour\u{2019}s lightness, L* \(Int($0.rounded()))." } ?? "Outlines show each gamut at its widest, whatever the lightness.")
        }
        if hasPress, printable.contains(false) { notes.append("An orange ring marks a colour the press cannot print as it is.") }
        notes.append(view.about)
        let note = text(notes.joined(separator: " "), .secondaryLabelColor)
        note.draw(with: NSRect(x: left, y: y + 4, width: width, height: chart.maxY - y - 4), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
