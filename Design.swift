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
        case display, title, headline, heading, lead, body, bodyStrong, caption, label, numeral, action
        var size: CGFloat {
            switch self {
            case .display: return 88
            case .title: return 48
            case .headline: return 30
            case .heading: return 17
            case .lead: return 20
            case .body, .bodyStrong, .action: return 13
            case .caption, .label: return 11
            case .numeral: return 64
            }
        }
        var weight: Weight {
            switch self {
            case .display, .numeral: return .thin
            case .title, .lead: return .light
            case .headline, .body, .caption: return .regular
            case .heading, .bodyStrong, .label, .action: return .medium
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
            case .label: return 1.2
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
            case .label: return 0.06
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
        let text = style == .label ? s.uppercased() : s
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
    /// Every gap is a multiple of four.
    static func beat(_ n: Int) -> CGFloat { CGFloat(n) * 4 }

    // MARK: The mark

    /// The diagonal arrow: "go there", one thin stroke at 45°.
    static func arrow(_ size: CGFloat, colour: NSColor = ink) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            colour.setStroke()
            let p = NSBezierPath()
            let u = size / 16
            p.move(to: NSPoint(x: 3.5 * u, y: 3.5 * u)); p.line(to: NSPoint(x: 12.5 * u, y: 12.5 * u))
            p.move(to: NSPoint(x: 5.5 * u, y: 12.5 * u)); p.line(to: NSPoint(x: 12.5 * u, y: 12.5 * u)); p.line(to: NSPoint(x: 12.5 * u, y: 5.5 * u))
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
