import AppKit

// ---------- The lighthouse: the splash's picture, one level a section ----------
//
// A lighthouse on a stepped stone island in a cut-away block of sea, drawn in a gentle two-point
// perspective from a low camera: what stands nearer is drawn a little larger, every vertical stays
// vertical. Each section of the splash raises one level: the sea and the island, the foot of the
// tower, a red band, the middle, a second red band, the gallery, then the lamp, which lights when
// the last section locks. A level rises out of the roof of the one below over 720 ms with a little
// overshoot, and sinks back in 380 ms. The water moves the whole time: the edges lap, ripples
// spread from the island, crests bob at the stone. With Reduce Motion on, levels simply appear and
// the water holds still.
//
// Agreed with Rick on 2026-10-09 on the design page "Colorgain Lighthouse Finished", version 3.

final class LighthouseView: NSView {
    /// How far each level has risen, 0 to 1: the sea and island, four sections of the tower, the gallery, the lamp.
    private(set) var progress: [CGFloat] = Array(repeating: 0, count: 7)
    private struct Move { let from: CGFloat, to: CGFloat, start: TimeInterval, length: TimeInterval }
    private var moves: [Int: Move] = [:]
    private var timer: Timer?
    private let born = Date()
    private var lampCentre: CGPoint?
    private var beamStart: TimeInterval = 0
    private var lit = false
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: The camera

    private let C = cos(CGFloat.pi / 6), S: CGFloat = 0.3, persp: CGFloat = 0.028
    private let AX: CGFloat = 3.6, AY: CGFloat = 3.6, sea: CGFloat = 1.5, sand: CGFloat = 0.16, brown: CGFloat = 0.32, top: CGFloat = 10.1
    private let margin: CGFloat = 16
    private var s: CGFloat = 1, cx: CGFloat = 0, cy: CGFloat = 0
    /// Where the finial's top is wanted, from the view's top; the block's foot stands a margin above the view's foot.
    var headroom: CGFloat = 84 { didSet { needsDisplay = true } }

    private func fit() {
        let kNear = 1 / (1 - (AX + AY) * persp)
        s = (bounds.height - margin - headroom) / (top + ((AX + AY) * S + sea + sand + brown) * kNear)
        cx = bounds.midX
        cy = headroom + top * s
    }
    private func P(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let k = 1 / (1 - (x + y) * persp)
        return CGPoint(x: cx + (x - y) * C * s * k, y: cy + (x + y) * S * s * k - z * s * k)
    }

    // MARK: Colour and drawing

    private struct Paint { let face: (CGFloat, CGFloat, CGFloat); let roof: (CGFloat, CGFloat, CGFloat) }
    private let cream = Paint(face: (241, 236, 226), roof: (251, 249, 244))
    private let red = Paint(face: (182, 98, 88), roof: (205, 130, 118))
    private let iron = Paint(face: (44, 44, 46), roof: (60, 60, 62))   // the cornices, the rails, the lamp's frame
    private let stone = Paint(face: (216, 210, 199), roof: (232, 228, 220))
    private let stone2 = Paint(face: (196, 189, 177), roof: (222, 217, 208))
    private let glass = Paint(face: (246, 226, 158), roof: (246, 226, 158))
    private func rgb(_ c: (CGFloat, CGFloat, CGFloat), _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: a) }
    /// Light from the upper left: faces turned that way are lit, faces turned right fall into shade.
    private func shade(_ c: (CGFloat, CGFloat, CGFloat), _ angle: CGFloat, _ lift: CGFloat = 0) -> NSColor {
        let k = 0.6 + 0.4 * (0.5 + 0.5 * cos(angle - 1.95)) + lift
        func v(_ x: CGFloat) -> CGFloat { min(255, max(0, x * k)) / 255 }
        return NSColor(srgbRed: v(c.0), green: v(c.1), blue: v(c.2), alpha: 1)
    }
    private func path(_ pts: [CGPoint], close: Bool = true) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: pts[0])
        for q in pts.dropFirst() { p.line(to: q) }
        if close { p.close() }
        p.lineJoinStyle = .round
        return p
    }
    private func poly(_ pts: [CGPoint], _ fill: NSColor?, _ stroke: NSColor? = nil, width: CGFloat = 0.8) {
        let p = path(pts)
        if let f = fill { f.setFill(); p.fill() }
        if let st = stroke { st.setStroke(); p.lineWidth = width; p.stroke() }
    }
    private func line(_ a: CGPoint, _ b: CGPoint, _ colour: NSColor, width: CGFloat) {
        colour.setStroke()
        let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = width; p.lineCapStyle = .round; p.stroke()
    }
    private func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    private func ring(_ r: CGFloat, _ z: CGFloat, _ n: Int, _ rot: CGFloat) -> [(CGFloat, CGFloat, CGFloat)] {
        (0..<n).map { i in let a = rot + CGFloat(i) * 2 * .pi / CGFloat(n); return (r * cos(a), r * sin(a), z) }
    }
    private let rot8 = CGFloat.pi / 8, rot4 = CGFloat.pi / 4
    /// A face is seen when it turns toward the viewer, whose eye looks along x + y.
    private func seen(_ a: CGFloat) -> Bool { cos(a - .pi / 4) > 0.01 }

    /// A prism with n sides, tapering from r0 to r1, with an optional decoration on any face given (face, angle, a map from face coordinates to the view).
    private func prism(n: Int = 8, rot: CGFloat? = nil, r0: CGFloat, r1: CGFloat, z: CGFloat, h: CGFloat, _ c: Paint, roof: Bool = true,
                       decorate: ((Int, CGFloat, (CGFloat, CGFloat) -> CGPoint) -> Void)? = nil) {
        let rot = rot ?? rot8
        let bot = ring(r0, z, n, rot), top = ring(r1, z + h, n, rot)
        var faces: [(i: Int, a: CGFloat, d: CGFloat)] = []
        for i in 0..<n {
            let a = rot + (CGFloat(i) + 0.5) * 2 * .pi / CGFloat(n)
            if seen(a) { faces.append((i, a, cos(a - .pi / 4))) }
        }
        for f in faces.sorted(by: { $0.d < $1.d }) {
            let j = (f.i + 1) % n
            let b0 = P(bot[f.i].0, bot[f.i].1, bot[f.i].2), b1 = P(bot[j].0, bot[j].1, bot[j].2)
            let t1 = P(top[j].0, top[j].1, top[j].2), t0 = P(top[f.i].0, top[f.i].1, top[f.i].2)
            poly([b0, b1, t1, t0], shade(c.face, f.a), shade(c.face, f.a, -0.12))
            decorate?(f.i, f.a) { u, v in self.mix(self.mix(b0, b1, u), self.mix(t0, t1, u), v) }
        }
        if roof { poly(top.map { P($0.0, $0.1, $0.2) }, rgb(c.roof), rgb((c.face.0 * 0.82, c.face.1 * 0.82, c.face.2 * 0.82))) }
    }
    /// An octagonal roof rising to a point.
    private func pyramid(z: CGFloat, r: CGFloat, h: CGFloat, _ c: Paint) {
        let base = ring(r, z, 8, rot8), apex = P(0, 0, z + h)
        var faces: [(i: Int, a: CGFloat, d: CGFloat)] = []
        for i in 0..<8 { let a = rot8 + (CGFloat(i) + 0.5) * .pi / 4; if seen(a) { faces.append((i, a, cos(a - .pi / 4))) } }
        for f in faces.sorted(by: { $0.d < $1.d }) {
            let j = (f.i + 1) % 8
            poly([P(base[f.i].0, base[f.i].1, base[f.i].2), P(base[j].0, base[j].1, base[j].2), apex], shade(c.face, f.a, 0.04), shade(c.face, f.a, -0.1))
        }
    }
    private func windowOn(_ q: (CGFloat, CGFloat) -> CGPoint, _ u0: CGFloat, _ u1: CGFloat, _ v0: CGFloat, _ v1: CGFloat) {
        poly([q(u0, v0), q(u1, v0), q(u1, v1), q(u0, v1)], NSColor(srgbRed: 40 / 255, green: 46 / 255, blue: 52 / 255, alpha: 0.88))
        let a = q(u0, v0), b = q(u1, v0)
        line(CGPoint(x: a.x, y: a.y + 1.5), CGPoint(x: b.x, y: b.y + 1.5), NSColor.white.withAlphaComponent(0.55), width: 1)
    }

    // MARK: The sea

    private var edges: [((CGFloat, CGFloat), (CGFloat, CGFloat), CGFloat)] { [((-AX, -AY), (AX, -AY), 1), ((AX, -AY), (AX, AY), 2), ((AX, AY), (-AX, AY), 3), ((-AX, AY), (-AX, -AY), 4)] }
    /// The waterline along an edge: a slow swell and a quicker chop, moving along it.
    private func waterline(_ p0: (CGFloat, CGFloat), _ p1: (CGFloat, CGFloat), _ t: CGFloat, _ phase: CGFloat, _ n: Int) -> [(CGFloat, CGFloat, CGFloat)] {
        (0...n).map { i in
            let u = CGFloat(i) / CGFloat(n)
            let z = 0.07 * sin(u * 5.1 + t * 1.6 + phase) + 0.025 * sin(u * 11.7 - t * 2.9 + phase * 2)
            return (p0.0 + (p1.0 - p0.0) * u, p0.1 + (p1.1 - p0.1) * u, z)
        }
    }
    /// A rounded square in the plane, for the ripples.
    private func rounded(_ r: CGFloat, _ z: CGFloat, _ n: Int) -> [CGPoint] {
        (0..<n).map { i in
            let t = CGFloat(i) * 2 * .pi / CGFloat(n), c = cos(t), si = sin(t)
            return P(r * (c < 0 ? -1 : 1) * sqrt(abs(c)), r * (si < 0 ? -1 : 1) * sqrt(abs(si)), z)
        }
    }
    private func drawSea(_ e: CGFloat, _ t: CGFloat) {
        let g = max(0, min(1, e))
        guard g > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let lines = edges.map { waterline($0.0, $0.1, t, $0.2 * 1.7, 28) }
        // The two near faces: the sand at the sea bed over the brown beneath, flat, then the water above, translucent so the island's footing shows.
        for k in [1, 2] {
            let ed = edges[k], ang: CGFloat = k == 1 ? 0 : .pi / 2
            let b0 = ed.0, b1 = ed.1
            poly([P(b0.0, b0.1, -sea - sand - brown), P(b1.0, b1.1, -sea - sand - brown), P(b1.0, b1.1, -sea - sand), P(b0.0, b0.1, -sea - sand)], shade((122, 96, 66), ang), shade((122, 96, 66), ang, -0.2))
            poly([P(b0.0, b0.1, -sea - sand), P(b1.0, b1.1, -sea - sand), P(b1.0, b1.1, -sea), P(b0.0, b0.1, -sea)], shade((214, 200, 160), ang), shade((214, 200, 160), ang, -0.2))
            let topLine = lines[k].map { P($0.0, $0.1, $0.2) }
            let face = path(topLine + [P(b1.0, b1.1, -sea), P(b0.0, b0.1, -sea)])
            NSGraphicsContext.saveGraphicsState()
            face.addClip()
            let gr = NSGradient(colorsAndLocations: (NSColor(srgbRed: 124 / 255, green: 196 / 255, blue: 206 / 255, alpha: 0.82 * g), 0),
                                (NSColor(srgbRed: 80 / 255, green: 162 / 255, blue: 178 / 255, alpha: 0.86 * g), 0.3),
                                (NSColor(srgbRed: 40 / 255, green: 98 / 255, blue: 120 / 255, alpha: 0.92 * g), 1))!
            gr.draw(from: CGPoint(x: 0, y: topLine[0].y), to: CGPoint(x: 0, y: P(b0.0, b0.1, -sea).y), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.5 * g).setStroke()
            let lp = path(topLine, close: false); lp.lineWidth = 1.2; lp.stroke()
        }
        // The surface, drawn on all four lapping edges, with light drifting across it.
        var surface: [CGPoint] = []
        for l in lines { for p in l.dropLast() { surface.append(P(p.0, p.1, p.2)) } }
        poly(surface, NSColor(srgbRed: 196 / 255, green: 226 / 255, blue: 230 / 255, alpha: 0.9 * g))
        NSGraphicsContext.saveGraphicsState()
        path(surface).addClip()
        for k in 0..<7 {
            let u = -AX + (CGFloat(k) * 1.03 + t * 0.35).truncatingRemainder(dividingBy: 2 * AX)
            poly([P(u, -AY, 0), P(u + 0.9, -AY, 0), P(u + 0.3, AY, 0), P(u - 0.6, AY, 0)], NSColor.white.withAlphaComponent(0.07 * g))
        }
        NSGraphicsContext.restoreGraphicsState()
        // Foam along every edge.
        NSColor.white.withAlphaComponent(0.85 * g).setStroke()
        let sp = path(surface); sp.lineWidth = 1.6; sp.stroke()
        NSColor.white.withAlphaComponent(0.35 * g).setStroke(); sp.lineWidth = 4; sp.stroke()
        // The ripples: rounded squares spreading from the island, fading as they go, three in flight at once.
        for r in 0..<3 {
            let ph = ((t / 3.6) + CGFloat(r) / 3).truncatingRemainder(dividingBy: 1), rad = 2.75 + ph * (AY - 2.85)
            let fade = (1 - ph) * (ph < 0.12 ? ph / 0.12 : 1) * g
            let rp = path(rounded(rad, 0.01, 64)); rp.lineWidth = 1.4 - ph * 0.6
            NSColor.white.withAlphaComponent(0.7 * fade).setStroke(); rp.stroke()
            let rq = path(rounded(rad + 0.06, 0.01, 64)); rq.lineWidth = 2.2
            NSColor(srgbRed: 60 / 255, green: 130 / 255, blue: 150 / 255, alpha: 0.22 * fade).setStroke(); rq.stroke()
        }
        // Crests bobbing at the stone.
        for w in 0..<12 {
            let ang = CGFloat(w) * 0.524 + 0.3, rr = 2.85 + 0.15 * sin(t * 1.3 + CGFloat(w))
            let xx = rr * cos(ang) * 1.15, yy = rr * sin(ang) * 1.15
            if abs(xx) > AX - 0.3 || abs(yy) > AY - 0.3 { continue }
            let c0 = P(xx - 0.16, yy, 0), c1 = P(xx, yy + 0.02, 0.02 + 0.015 * sin(t * 2 + CGFloat(w))), c2 = P(xx + 0.16, yy, 0)
            NSColor.white.withAlphaComponent(0.8 * g).setStroke()
            let cp = NSBezierPath(); cp.move(to: c0); cp.curve(to: c2, controlPoint1: CGPoint(x: c1.x, y: c1.y - 2), controlPoint2: CGPoint(x: c1.x, y: c1.y - 2)); cp.lineWidth = 1.2; cp.stroke()
        }
        // The island's shadow on the water, cast to the lower right.
        poly([P(-2.3, -2.3, 0), P(2.9, -2.3, 0), P(2.9, 2.9, 0), P(-2.3, 2.9, 0)], NSColor(srgbRed: 30 / 255, green: 70 / 255, blue: 80 / 255, alpha: 0.14 * g))
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: The island and the tower

    private let islandTop: CGFloat = 0.72
    private func drawFooting(_ e: CGFloat) {
        guard e > 0 else { return }
        prism(n: 4, rot: rot4, r0: 2.75 * sqrt(2), r1: 2.55 * sqrt(2), z: -sea, h: sea, Paint(face: (168, 160, 146), roof: (168, 160, 146)), roof: false)
    }
    private func drawIsland(_ e: CGFloat) {
        guard e > 0 else { return }
        prism(n: 4, rot: rot4, r0: 2.55 * sqrt(2), r1: 2.55 * sqrt(2), z: 0, h: 0.36 * e, stone2)
        if e > 0.35 { prism(n: 4, rot: rot4, r0: 2.0 * sqrt(2), r1: 2.0 * sqrt(2), z: 0.36 * min(e, 1), h: 0.36 * max(0, (e - 0.35) / 0.65), stone) }
    }
    private struct Section { let paint: Int; let h: CGFloat; let r0: CGFloat; let r1: CGFloat; let door: Bool; let windows: [Int] }
    private let sections = [Section(paint: 0, h: 1.9, r0: 1.36, r1: 1.22, door: true, windows: []),
                            Section(paint: 1, h: 1.45, r0: 1.18, r1: 1.07, door: false, windows: [0]),
                            Section(paint: 0, h: 1.45, r0: 1.04, r1: 0.95, door: false, windows: [1, 7]),
                            Section(paint: 1, h: 1.3, r0: 0.92, r1: 0.85, door: false, windows: [0])]
    private let cornice: CGFloat = 0.13
    private var zAt: [CGFloat] {
        var out = [islandTop + 0.14]
        for (i, sec) in sections.enumerated() { out.append(out[i] + sec.h + cornice) }
        return out
    }
    private func drawSection(_ i: Int, _ e: CGFloat) {
        guard e > 0 else { return }
        let sec = sections[i], z = zAt[i], grow = 0.8 + 0.2 * min(1, e), h = sec.h * e
        prism(r0: sec.r0 * grow, r1: sec.r1 * grow, z: z, h: h, sec.paint == 0 ? cream : red, roof: e < 0.55) { f, _, q in
            guard e >= 0.6 else { return }
            if sec.door && f == 0 {
                let b0 = q(0.38, 0), b1 = q(0.62, 0), t1 = q(0.62, 0.36), t0 = q(0.38, 0.36), top = q(0.5, 0.46)
                let d = NSBezierPath(); d.move(to: b0); d.line(to: b1); d.line(to: t1)
                d.curve(to: t0, controlPoint1: CGPoint(x: top.x, y: top.y - 4), controlPoint2: CGPoint(x: top.x, y: top.y - 4)); d.close()
                NSColor(srgbRed: 120 / 255, green: 56 / 255, blue: 50 / 255, alpha: 1).setFill(); d.fill()
                self.windowOn(q, 0.42, 0.58, 0.62, 0.8)
            }
            if sec.windows.contains(f) { self.windowOn(q, 0.38, 0.62, 0.36, 0.7) }
        }
        // The cornice: an iron band that oversails the level, its flat top the level's roof.
        let t = max(0, min(1, (e - 0.55) / 0.45))
        if t > 0 { prism(r0: (sec.r1 + 0.09) * grow, r1: (sec.r1 + 0.11) * grow, z: z + h, h: cornice * t, iron) }
    }
    private func railing(_ r: CGFloat, _ z: CGFloat, _ hgt: CGFloat, front: Bool) {
        let n = 16, pts = ring(r, z, n, rot8 / 2), colour = rgb(iron.face)
        for i in 0..<n {
            let a = rot8 / 2 + CGFloat(i) * 2 * .pi / CGFloat(n)
            if (cos(a - .pi / 4) >= 0) != front { continue }
            let b = P(pts[i].0, pts[i].1, z), t = P(pts[i].0, pts[i].1, z + hgt)
            line(b, t, colour, width: 1.4)
            let j = (i + 1) % n, aj = rot8 / 2 + (CGFloat(i) + 0.5) * 2 * .pi / CGFloat(n)
            if (cos(aj - .pi / 4) >= 0) == front {
                line(t, P(pts[j].0, pts[j].1, z + hgt), colour, width: 1.6)
                line(P(pts[i].0, pts[i].1, z + hgt * 0.5), P(pts[j].0, pts[j].1, z + hgt * 0.5), colour, width: 0.9)
            }
        }
    }
    private func drawGallery(_ e: CGFloat, lamp: CGFloat) {
        guard e > 0 else { return }
        let g = min(1, e), zG = zAt[4]
        prism(r0: 0.86, r1: 0.86 + 0.32 * g, z: zG, h: 0.26 * e, iron, roof: false)
        let z = zG + 0.26 * e
        prism(r0: 1.2 * (0.85 + 0.15 * g), r1: 1.2 * (0.85 + 0.15 * g), z: z, h: 0.14 * e, iron)
        let deck = z + 0.14 * e, rh = 0.42 * max(0, (e - 0.4) / 0.6)
        if rh > 0 { railing(1.1, deck, rh, front: false) }
        drawLamp(lamp, deck: deck)
        if rh > 0 { railing(1.1, deck, rh, front: true) }
    }
    private func drawLamp(_ e: CGFloat, deck: CGFloat) {
        guard e > 0 else { return }
        let g = min(1, e)
        var z = deck
        prism(r0: 0.72, r1: 0.72, z: z, h: 0.12 * e, iron)
        z += 0.12 * e
        let gh = 0.78 * e
        prism(r0: 0.6 * (0.8 + 0.2 * g), r1: 0.6 * (0.8 + 0.2 * g), z: z, h: gh, glass, roof: false) { _, _, q in
            // Mullions at the edges of each pane, and a bar across the middle.
            for l in [(0, 0, 0, 1), (1, 0, 1, 1), (0, 0.5, 1, 0.5)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                self.line(q(l.0, l.1), q(l.2, l.3), self.rgb(self.iron.face), width: 1.2)
            }
        }
        z += gh
        let t = max(0, min(1, (e - 0.45) / 0.55))
        if t > 0 {
            prism(r0: 0.74, r1: 0.74, z: z, h: 0.08, iron)
            pyramid(z: z + 0.08, r: 0.8, h: 0.62 * t, red)
            if t > 0.8 {
                let top = P(0, 0, z + 0.08 + 0.62 * t), tip = P(0, 0, z + 0.08 + 0.62 * t + 0.32)
                line(top, tip, rgb(iron.face), width: 1.6)
                rgb(iron.face).setFill()
                NSBezierPath(ovalIn: CGRect(x: top.x - 0.09 * s, y: top.y - 0.19 * s, width: 0.18 * s, height: 0.18 * s)).fill()
            }
        }
        lampCentre = P(0, 0, deck + 0.12 + 0.39)
    }

    // MARK: Drawing it all

    override func draw(_ dirtyRect: NSRect) {
        fit()
        let now = Date().timeIntervalSince(born)
        let t: CGFloat = reduceMotion ? 0 : CGFloat(now)
        lit = progress[6] >= 1 && moves.isEmpty
        if lit, let lc = lampCentre {
            // The lamp lit: a warm glow behind everything, kept inside the picture.
            let pulse: CGFloat = reduceMotion ? 1 : 0.85 + 0.15 * sin(CGFloat(now - beamStart) * 1.67)
            let radius = min(3.2 * s, lc.y - margin)
            let glow = NSGradient(starting: NSColor(srgbRed: 246 / 255, green: 214 / 255, blue: 120 / 255, alpha: 0.5 * pulse), ending: NSColor(srgbRed: 246 / 255, green: 214 / 255, blue: 120 / 255, alpha: 0))!
            glow.draw(fromCenter: lc, radius: 2, toCenter: lc, radius: radius, options: [])
        }
        drawFooting(progress[0])
        drawSea(progress[0], t)
        drawIsland(progress[0])
        for i in 0..<4 { drawSection(i, progress[i + 1]) }
        drawGallery(progress[5], lamp: progress[6])
        if lit, let lc = lampCentre, !reduceMotion {
            // The beam sweeping once round in eight seconds, each end stopping short of the picture's edge so its fade is complete.
            let ang = CGFloat(now - beamStart) / 8 * 2 * .pi
            for a in [ang, ang + .pi] {
                let dx = cos(a), dy = sin(a) * 0.5
                var len = 6 * s
                if dx > 0 { len = min(len, (bounds.width - margin - lc.x) / dx) } else if dx < 0 { len = min(len, (margin - lc.x) / dx) }
                if dy > 0 { len = min(len, (bounds.height - margin - lc.y) / dy) } else if dy < 0 { len = min(len, (margin - lc.y) / dy) }
                len = max(0, len)
                let end = CGPoint(x: lc.x + dx * len, y: lc.y + dy * len)
                let tri = path([lc, CGPoint(x: end.x - dy * len * 0.18, y: end.y + dx * len * 0.09), CGPoint(x: end.x + dy * len * 0.18, y: end.y - dx * len * 0.09)])
                NSGraphicsContext.saveGraphicsState()
                tri.addClip()
                NSGradient(starting: NSColor(srgbRed: 246 / 255, green: 226 / 255, blue: 158 / 255, alpha: 0.55), ending: NSColor(srgbRed: 246 / 255, green: 226 / 255, blue: 158 / 255, alpha: 0))!.draw(from: lc, to: end, options: [])
                NSGraphicsContext.restoreGraphicsState()
            }
            drawLamp(progress[6], deck: zAt[4] + 0.26 + 0.14)   // the lamp over its own beam
        }
    }

    // MARK: Motion

    /// Raises level `i` into place, or sinks it away, the water running meanwhile.
    func set(level i: Int, to value: CGFloat) {
        guard progress.indices.contains(i) else { return }
        if reduceMotion { progress[i] = value; moves[i] = nil; if value >= 1 && i == 6 { beamStart = Date().timeIntervalSince(born) }; needsDisplay = true; return }
        let now = Date().timeIntervalSince(born)
        moves[i] = Move(from: progress[i], to: value, start: now, length: value > progress[i] ? 0.72 : 0.38)
        run()
    }
    private func run() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func tick() {
        let now = Date().timeIntervalSince(born)
        for (i, m) in moves {
            let u = CGFloat(min(1, (now - m.start) / m.length))
            // Rising overshoots a touch and settles; sinking just gathers pace.
            let eased: CGFloat = m.to > m.from ? { let k: CGFloat = 1.55, x = u - 1; return x * x * ((k + 1) * x + k) + 1 }() : u * u * u
            progress[i] = m.from + (m.to - m.from) * eased
            if u >= 1 { progress[i] = m.to; moves[i] = nil; if i == 6, m.to >= 1 { beamStart = now } }
        }
        needsDisplay = true
        // The water runs as long as the view is up, unless motion is reduced, when only a move needs the clock.
        if reduceMotion && moves.isEmpty { timer?.invalidate(); timer = nil }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate(); timer = nil } else if !reduceMotion { run() }
    }
}
