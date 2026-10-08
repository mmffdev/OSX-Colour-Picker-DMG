import AppKit

// ---------- The design: Colorgain's own look, in numbers ----------
//
// The rules are in .claude/c_design_guide.md and its children; the living specimen is the style
// sheet artifact. This file is those rules as the app reads them: one family, six weights, ten
// text styles, six greys, eight step colours, a grid and a beat. Nothing on a screen takes a font,
// a grey or a gap from anywhere else.

enum Design {
    // MARK: Type

    /// Helvetica Neue by weight. Falls back to the system font only if a weight is missing, which no Mac does.
    static func font(_ size: CGFloat, _ weight: Weight) -> NSFont {
        NSFont(name: weight.postScriptName, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight.system)
    }
    enum Weight {
        case ultraLight, thin, light, regular, medium, bold
        var postScriptName: String {
            switch self {
            case .ultraLight: return "HelveticaNeue-UltraLight"
            case .thin: return "HelveticaNeue-Thin"
            case .light: return "HelveticaNeue-Light"
            case .regular: return "HelveticaNeue"
            case .medium: return "HelveticaNeue-Medium"
            case .bold: return "HelveticaNeue-Bold"
            }
        }
        var system: NSFont.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }
    }

    /// The ten styles: size, weight, line height as a multiple, tracking as a fraction of the size.
    enum Text {
        case display, title, headline, heading, lead, body, bodyStrong, caption, label, section, numeral, action
        var size: CGFloat {
            switch self {
            case .display: return 88
            case .title: return 48
            case .headline: return 30
            case .heading: return 17
            case .lead: return 20
            case .body, .bodyStrong, .action: return 13
            case .caption, .label: return 11
            case .section: return 13
            case .numeral: return 64
            }
        }
        var weight: Weight {
            switch self {
            case .display, .numeral: return .thin
            case .title, .lead: return .light
            case .headline, .body, .caption: return .regular
            case .heading, .bodyStrong, .label, .section, .action: return .medium
            }
        }
        var lineHeight: CGFloat {
            switch self {
            case .display: return 0.92
            case .title: return 1.0
            case .headline: return 1.1
            case .heading: return 1.25
            case .lead: return 1.38
            case .body, .bodyStrong: return 1.55
            case .caption: return 1.45
            case .label, .section: return 1.2
            case .numeral: return 0.9
            case .action: return 1.2
            }
        }
        var tracking: CGFloat {
            switch self {
            case .display: return -0.045
            case .title: return -0.03
            case .headline: return -0.018
            case .heading: return -0.005
            case .lead: return -0.01
            case .numeral: return -0.04
            case .label, .section: return 0.06
            default: return 0
            }
        }
        func font(_ size: CGFloat? = nil) -> NSFont { Design.font(size ?? self.size, weight) }
    }

    /// A label in one of the ten styles, its tracking and line height set, ink unless told otherwise.
    static func text(_ s: String, _ style: Text, size: CGFloat? = nil, colour: NSColor = Design.ink, wraps: Bool = false) -> NSTextField {
        let l = wraps ? NSTextField(wrappingLabelWithString: "") : NSTextField(labelWithString: "")
        l.font = style.font(size ?? style.size)
        l.attributedStringValue = attributed(s, style, size: size, colour: colour, lineHeight: wraps)
        l.textColor = colour
        return l
    }

    /// `lineHeight` sets the style's line height, for text that wraps; a single-line label leaves it
    /// to the font, since a taller line pushes the glyphs out of a one-line cell.
    static func attributed(_ s: String, _ style: Text, size: CGFloat? = nil, colour: NSColor = Design.ink, align: NSTextAlignment = .left, lineHeight: Bool = false) -> NSAttributedString {
        let sz = size ?? style.size
        let p = NSMutableParagraphStyle()
        if lineHeight {
            p.minimumLineHeight = (sz * style.lineHeight).rounded()
            p.maximumLineHeight = p.minimumLineHeight
        }
        p.alignment = align
        p.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [.font: style.font(sz), .foregroundColor: colour, .paragraphStyle: p, .kern: sz * style.tracking]
        if style == .numeral || style == .caption || style == .label {
            attrs[.font] = NSFont(descriptor: style.font(sz).fontDescriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector]]]), size: sz) ?? style.font(sz)
        }
        let text = style == .label || style == .section ? s.uppercased() : s
        return NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: Colour

    static let paper = hex("#C4C4C4")
    /// The step being worked, and every other step card. Rick's trial of 2026-10-07.
    static let active = hex("#FCC80A")
    static let inactive = hex("#B8B5AF")
    static let card = hex("#F8F7F5")
    static let mist = hex("#E3E2DE")
    static let rule = hex("#CFCDC7")
    static let soft = hex("#A3A19B")
    static let quiet = hex("#6B6964")
    static let ink = hex("#161616")
    /// The one accent: focus rings and the grid overlay, nothing else.
    static let orange = hex("#EC7A3C")

    struct StepColour { let name: String; let hex: String; var colour: NSColor { Design.hex(hex) } }
    /// The eight step colours in order, mixed from orange, pale blue and teal, at full strength. The
    /// numerals on them are always ink, as on the Spotify concept, so every colour must carry ink at 3:1.
    static let steps: [StepColour] = [
        StepColour(name: "Apricot", hex: "#F2D3B4"),
        StepColour(name: "Pale Blue", hex: "#A9CFE3"),
        StepColour(name: "Harbour Teal", hex: "#5FB3A8"),
        StepColour(name: "Sand", hex: "#E8D9A8"),
        StepColour(name: "Orange", hex: "#F0803A"),
        StepColour(name: "Sky", hex: "#7FB2D6"),
        StepColour(name: "Deep Teal", hex: "#2F8F86"),
        StepColour(name: "Signal Red", hex: "#C9382C"),
    ]
    static func step(_ i: Int) -> StepColour { steps[max(0, min(steps.count - 1, i))] }

    static func hex(_ h: String) -> NSColor {
        var s = h; if s.hasPrefix("#") { s.removeFirst() }
        let n = UInt32(s, radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    /// `fraction` of the way from `a` to `b`, in sRGB.
    static func mix(_ a: NSColor, _ b: NSColor, _ fraction: CGFloat) -> NSColor {
        (a.usingColorSpace(.sRGB) ?? a).blended(withFraction: fraction, of: b.usingColorSpace(.sRGB) ?? b) ?? a
    }

    // MARK: Grid and beat

    enum Wizard {
        static let size = NSSize(width: 1040, height: 660)
        static let margin: CGFloat = 48
        static let gutter: CGFloat = 24
        static let columns = 12
        static let band: CGFloat = 10
        /// Square. Swiss has no rounded corners.
        static let radius: CGFloat = 0
        /// The x of a column's left edge and the width of a run of columns, inside the margins.
        static func column(_ c: Int) -> CGFloat { margin + CGFloat(c - 1) * (columnWidth + gutter) }
        static var columnWidth: CGFloat { (size.width - 2 * margin - CGFloat(columns - 1) * gutter) / CGFloat(columns) }
        static func span(_ from: Int, _ to: Int) -> CGFloat { CGFloat(to - from + 1) * columnWidth + CGFloat(to - from) * gutter }
    }
    /// The app window's grid (c_c_c_design_grid_app.md): twelve columns inside 24 margins with 16 gutters,
    /// a 64 header and a 48 footer. The window resizes, so every measure takes the width it is at.
    enum App {
        /// The height is chosen so the rows, from under the areas' rule to the footer, come to whole units: 25 at first, 17 at least.
        static let size = NSSize(width: 1440, height: 893)      // 64 + 1 + 80, then 25 units, then 48
        static let least = NSSize(width: 1120, height: 669)     // the same with 17 units
        static let margin: CGFloat = 24
        static let gutter: CGFloat = 16
        static let columns = 12
        static let header: CGFloat = 64
        static let footer: CGFloat = 48
        /// The page's clear space above its title.
        static let pageTop: CGFloat = 34
        /// Master Inner: the beat every row under an area's rule keeps, and where a line of text sits in a
        /// row. Every row is a multiple of the unit, so a row in one area shares its baseline with a row in
        /// another; a two-line row is two units, a header row one. The overlay draws it (Rick, 2026-10-08).
        /// The beat: 28 since 2026-10-08, the height a 24 unit plus the band's four points turned out to be; every row, every
        /// list and the grid itself stand on it. The text sits on the line 17 in, so capitals are centred and the descenders have air.
        static let unit: CGFloat = 28
        static let textBaseline: CGFloat = 17
        /// A row's ground is its unit, no more; kept as the one place to say so.
        static let groundBelow: CGFloat = 0
        static func ground(_ box: NSRect) -> NSRect { NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height + groundBelow) }
        /// The grid drawn over the window, on while the window is being built; the backslash key turns it off and on.
        static var masterGrid = false
        static let gridColour = hex("#FCC80A")
        static func columnWidth(in width: CGFloat) -> CGFloat { (width - 2 * margin - CGFloat(columns - 1) * gutter) / CGFloat(columns) }
        static func column(_ c: Int, in width: CGFloat) -> CGFloat { margin + CGFloat(c - 1) * (columnWidth(in: width) + gutter) }
        static func span(_ from: Int, _ to: Int, in width: CGFloat) -> CGFloat { CGFloat(to - from + 1) * columnWidth(in: width) + CGFloat(to - from) * gutter }
    }
    /// Every gap is a multiple of four.
    static func beat(_ n: Int) -> CGFloat { CGFloat(n) * 4 }

    // MARK: The mark

    /// The diagonal arrow: "go there", one thin stroke at 45°.
    /// `back` turns it 180: the same stroke pointing down and left, "close what is open".
    static func arrow(_ size: CGFloat, colour: NSColor = ink, back: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            colour.setStroke()
            let p = NSBezierPath()
            let u = size / 16
            func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { back ? NSPoint(x: (16 - x) * u, y: (16 - y) * u) : NSPoint(x: x * u, y: y * u) }
            p.move(to: pt(3.5, 3.5)); p.line(to: pt(12.5, 12.5))
            p.move(to: pt(5.5, 12.5)); p.line(to: pt(12.5, 12.5)); p.line(to: pt(12.5, 5.5))
            p.lineWidth = size >= 24 ? 1.1 : 1.3
            p.lineCapStyle = .butt
            p.stroke()
            return true
        }
    }

    // MARK: A hairline

    static func hairline(_ colour: NSColor = rule) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = colour.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}

/// The lines that tie a tree's rows to their parents, all right angles: a stem down from under the parent's mark, starting
/// just below the parent's words; a tee into a child that has siblings after it, an elbow into the last; the stems of
/// ancestors with later siblings passing straight through. Each row says where its mark's centre is and where the mark begins.
enum TreeLines {
    struct Row {
        var top: CGFloat, height: CGFloat, level: Int
        /// The centre of the row's own mark, the level number or the icon, where a stem to its children hangs from.
        var anchor: CGFloat
        /// Where the mark begins, which a tail from the parent's stem reaches, two points short.
        var markLeft: CGFloat
        var baseline: CGFloat
    }
    static func draw(_ rows: [Row], colour: NSColor) {
        colour.setFill()
        func stem(_ x: CGFloat, from y0: CGFloat, to y1: CGFloat) { NSRect(x: x.rounded() - 1, y: y0, width: 1, height: y1 - y0).fill() }
        /// Whether a row at `level` comes after row `i` before any row shallower than it: a later sibling of the row at that level.
        func later(_ level: Int, after i: Int) -> Bool {
            for k in rows.indices where k > i { if rows[k].level < level { return false }; if rows[k].level == level { return true } }
            return false
        }
        for (i, r) in rows.enumerated() where r.level > 0 {
            guard let p = rows[..<i].lastIndex(where: { $0.level == r.level - 1 }) else { continue }
            // The arm sits on the centre of the number and the words: two points above the line they sit on.
            let x = rows[p].anchor, tailY = (r.top + r.baseline - 2).rounded()
            stem(x, from: r.top, to: later(r.level, after: i) ? r.top + r.height : tailY)
            NSRect(x: x.rounded() - 1, y: tailY - 1, width: r.markLeft - 2 - (x.rounded() - 1), height: 1).fill()
            // The ancestors' stems, where an ancestor still has a sibling to come.
            var at = p, level = r.level - 1
            while level >= 1, let gp = rows[..<at].lastIndex(where: { $0.level == level - 1 }) {
                if later(level, after: i) { stem(rows[gp].anchor, from: r.top, to: r.top + r.height) }
                at = gp; level -= 1
            }
        }
        for (i, r) in rows.enumerated() where i + 1 < rows.count && rows[i + 1].level == r.level + 1 {
            stem(r.anchor, from: (r.top + r.baseline + 4).rounded(), to: r.top + r.height)
        }
    }
}

/// A row's mark on rail1: the old sidebar's icons, drawn 12 high in the given colour.
enum RowMark {
    static func image(_ name: String, colour: NSColor) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        let c = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular).applying(NSImage.SymbolConfiguration(paletteColors: [colour]))
        return base.withSymbolConfiguration(c) ?? base
    }
    /// Drawn with its centre on the row's text line, in a 14 box starting at `x`.
    static func draw(_ name: String, x: CGFloat, baseline: CGFloat, colour: NSColor) {
        let img = image(name, colour: colour), size = img.size
        let r = NSRect(x: x + (14 - size.width) / 2, y: baseline - 5 - size.height / 2, width: size.width, height: size.height)
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// The rollover, first made for the schema page: a pane in the grid's colour that flies out from the left edge under the
/// pointer, eased, the whole flight in a tenth of a second, and stays out on whatever is locked, the chosen row. One clock
/// for any set of keys; the owner says which keys there are, which are locked, and what to redraw as the panes move.
final class Rollover<Key: Hashable> {
    private(set) var hover: Key?
    private var reveal: [Key: CGFloat] = [:]
    private var clock: Timer?
    private var lastTick = Date()
    var keys: () -> [Key] = { [] }
    var locked: (Key) -> Bool = { _ in false }
    var redraw: () -> Void = {}
    deinit { clock?.invalidate() }

    /// Where a pane should be: out under the pointer and on what is locked, home for the rest.
    func goal(_ k: Key) -> CGFloat { k == hover || locked(k) ? 1 : 0 }
    /// Starts the clock if any pane is away from where it should be; it stops itself when every pane has arrived.
    func settle() {
        let moving = keys().contains { (reveal[$0] ?? 0) != goal($0) }
        guard moving, clock == nil else { return }
        lastTick = Date()
        clock = Timer.scheduledTimer(withTimeInterval: 1 / 90, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            // Fast: the whole flight in a tenth of a second, so the wave follows the pointer without lag.
            let now = Date(), step = CGFloat(now.timeIntervalSince(self.lastTick) / 0.1)
            self.lastTick = now
            var done = true
            for k in self.keys() {
                let g = self.goal(k), v = self.reveal[k] ?? 0
                if v == g { continue }
                let next = v < g ? min(g, v + step) : max(g, v - step)
                self.reveal[k] = next
                if next != g { done = false }
            }
            self.reveal = self.reveal.filter { $0.value > 0 }
            self.redraw()
            if done { t.invalidate(); self.clock = nil }
        }
        RunLoop.main.add(clock!, forMode: .common)
    }
    /// The pointer is over another key, or over none.
    func moved(_ over: Key?) { if over != hover { hover = over; settle() } }
    /// Draws a key's pane, as far out as it has flown: from the left edge to `reach`, over `box` and one point above it, over the rule.
    func pane(_ k: Key, box: NSRect, reach: CGFloat) {
        guard let v = reveal[k], v > 0 else { return }
        let eased = 1 - pow(1 - v, 3)
        fill(NSRect(x: 0, y: box.minY - 1, width: (reach * eased).rounded(), height: box.height + 1), Design.App.gridColour)
    }
}

/// The caret on a row that holds others: pointing right when they are hidden, down when they show. A thin stroke in the
/// house manner, six points across its longer side, centred on `centre`, which a row puts on its mark's centre line.
enum Caret {
    static func draw(open: Bool, centre c: NSPoint, colour: NSColor) {
        colour.setStroke()
        let p = NSBezierPath(); p.lineWidth = 1.2; p.lineJoinStyle = .miter; p.lineCapStyle = .butt
        if open {
            p.move(to: NSPoint(x: c.x - 3.5, y: c.y - 1.75)); p.line(to: NSPoint(x: c.x, y: c.y + 1.75)); p.line(to: NSPoint(x: c.x + 3.5, y: c.y - 1.75))
        } else {
            p.move(to: NSPoint(x: c.x - 1.75, y: c.y - 3.5)); p.line(to: NSPoint(x: c.x + 1.75, y: c.y)); p.line(to: NSPoint(x: c.x - 1.75, y: c.y + 3.5))
        }
        p.stroke()
    }
}

extension Design {
    /// The halo's own mark: a ring, as the dial is, with a smaller ring inside it. Drawn in a 16 box.
    static func haloMark(in g: NSRect, colour: NSColor) {
        colour.setStroke()
        let outer = NSBezierPath(ovalIn: g.insetBy(dx: 2, dy: 2)); outer.lineWidth = 2; outer.stroke()
        let inner = NSBezierPath(ovalIn: g.insetBy(dx: 5.5, dy: 5.5)); inner.lineWidth = 1; inner.stroke()
    }
}
