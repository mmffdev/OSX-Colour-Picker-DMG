import AppKit

// ---------- Analysis: a palette, or one swatch, looked at seven ways ----------
//
// A page of panels, each a different reading of the same colours: as a list, round the hue
// circle, by lightness alone, as people with a colour vision deficiency see them, as a gradient,
// as pairs, and on a light and a dark ground. It opens for a whole palette or for one swatch; a
// swatch has no gradient and no pairs. Every panel can be opened to fill the page.

/// How a colour looks to someone with a colour vision deficiency. The matrices are Machado,
/// Oliveira and Fernandes (2009), applied to linear sRGB: full strength for the "-opia" kinds,
/// six tenths for the commoner "-omaly" kinds.
enum ColourVision: CaseIterable {
    case deuteranomaly, deuteranopia, protanomaly, protanopia, tritanopia

    var name: String {
        switch self {
        case .deuteranomaly: return "Deuteranomaly"
        case .deuteranopia: return "Deuteranopia"
        case .protanomaly: return "Protanomaly"
        case .protanopia: return "Protanopia"
        case .tritanopia: return "Tritanopia"
        }
    }

    /// How common it is, among men and among women.
    var prevalence: String {
        switch self {
        case .deuteranomaly: return "Men 5.0%  Women 0.35%"
        case .deuteranopia: return "Men 1.2%  Women 0.01%"
        case .protanomaly: return "Men 1.3%  Women 0.02%"
        case .protanopia: return "Men 1.0%  Women 0.03%"
        case .tritanopia: return "About 0.01% Of People"
        }
    }

    private var matrix: [[Double]] {
        switch self {
        case .deuteranomaly: return [[0.498864, 0.674741, -0.173604], [0.205199, 0.754872, 0.039929], [-0.011131, 0.030969, 0.980162]]
        case .deuteranopia: return [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
        case .protanomaly: return [[0.385450, 0.769005, -0.154455], [0.100526, 0.829802, 0.069673], [-0.007442, -0.022190, 1.029632]]
        case .protanopia: return [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]
        case .tritanopia: return [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]
        }
    }

    /// The colour as seen, as sRGB values 0 to 1.
    func seen(_ key: String) -> [Double]? {
        guard let v = ColourValues(key) else { return nil }
        let l = v.linear, rgb = [l.r, l.g, l.b]
        return matrix.map { row in RGBSpace.srgb.encoded(min(max(row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2], 0), 1)) }
    }

    func colour(_ key: String) -> NSColor {
        guard let v = seen(key) else { return .gray }
        return NSColor(srgbRed: CGFloat(v[0]), green: CGFloat(v[1]), blue: CGFloat(v[2]), alpha: 1)
    }
}

/// The panels, in the order they are shown: what a decision turns on first (can everyone tell
/// these apart, can they be read, will they print), then the palette's character (tone, hue),
/// then how it looks put together.
enum AnalysisKind: CaseIterable {
    case vision, contrast, separation, print, luminance, hue, combos, lightDark, gradient, list

    var title: String {
        switch self {
        case .vision: return "Colour Vision"
        case .contrast: return "Contrast Grid"
        case .separation: return "Separation"
        case .print: return "Print Reach"
        case .luminance: return "Tone"
        case .hue: return "Hue Wheel"
        case .combos: return "Pairings"
        case .lightDark: return "On White, On Black"
        case .gradient: return "Blend"
        case .list: return "Bands"
        }
    }

    var about: String {
        switch self {
        case .vision: return "Each colour as people with the commonest colour vision deficiencies see it"
        case .contrast: return "Each colour as text on every other, with the contrast ratio; a ring marks a pass for body text"
        case .separation: return "How far apart every pair is; orange where some colour blind viewers would struggle to tell them apart"
        case .print: return "Each colour over what the palette's press gives, with the difference"
        case .luminance: return "Each colour with its hue taken away: how light it looks, as a percentage"
        case .hue: return "Where each colour sits round the hue circle; greys gather in the middle"
        case .combos: return "Each colour as a ground with the next colour set on it"
        case .lightDark: return "Each colour on pure white and on the deepest black"
        case .gradient: return "The colours run into one another, in order"
        case .list: return "Every colour, top to bottom, with nothing between them"
        }
    }

    /// Whether the panel needs more than one colour to say anything.
    var needsSeveral: Bool { [.contrast, .separation, .combos, .gradient, .list].contains(self) }

    /// The panels for these colours: all of them for a palette, those that mean something for one swatch.
    static func offered(for count: Int) -> [AnalysisKind] { allCases.filter { count > 1 || !$0.needsSeveral } }
}

/// How far apart two colours are, for ordinary vision and at the worst for the colour vision
/// deficiencies simulated. CIEDE2000; under about 6 two colours are hard to tell apart at a glance.
func separation(_ a: String, _ b: String) -> (seen: Double, worst: Double)? {
    guard let one = (ColourKeys.definition(of: a) ?? ColourDefinition.of(hex: a))?.master, let two = (ColourKeys.definition(of: b) ?? ColourDefinition.of(hex: b))?.master else { return nil }
    let seen = deltaE2000(one.lab, two.lab)
    let simulated = ColourVision.allCases.compactMap { kind -> Double? in
        guard let p = kind.seen(a), let q = kind.seen(b) else { return nil }
        return deltaE2000(RGBSpace.srgb.master(of: p).lab, RGBSpace.srgb.master(of: q).lab)
    }
    return (seen, min(seen, simulated.min() ?? seen))
}

/// Below this, two colours are hard to tell apart at a glance.
let separationFloor = 6.0

/// How light a colour is, 0 to 100: L* of its master, which is how light it looks, not how much light it sends.
func lightness(of key: String) -> Double {
    (ColourKeys.definition(of: key) ?? ColourDefinition.of(hex: key))?.master.lab.l ?? 0
}

/// One panel's picture.
final class AnalysisPlot: NSView {
    let kind: AnalysisKind
    var keys: [String] = [] { didSet { needsDisplay = true } }

    init(_ kind: AnalysisKind) {
        self.kind = kind
        super.init(frame: .zero)
        toolTip = kind.about
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func fill(_ key: String) -> NSColor { colorFromHex(key) ?? .gray }
    private func text(_ s: String, _ colour: NSColor, size: CGFloat = TextSize.caption, weight: NSFont.Weight = .regular) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: colour])
    }
    private func centred(_ s: NSAttributedString, in rect: NSRect) {
        let size = s.size()
        s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !keys.isEmpty, bounds.width > 20, bounds.height > 20 else { return }
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).addClip()
        switch kind {
        case .list: drawList()
        case .contrast: drawContrast()
        case .separation: drawSeparation()
        case .print: drawPrint()
        case .hue: drawHue()
        case .luminance: drawLuminance()
        case .vision: drawVision()
        case .gradient: drawGradient()
        case .combos: drawCombos()
        case .lightDark: drawLightDark()
        }
    }

    /// The cells of a grid of every colour against every other, with a row and a column of the colours themselves.
    private func cells() -> (key: CGFloat, cell: NSSize) {
        let key: CGFloat = min(28, bounds.height / CGFloat(keys.count + 1))
        return (key, NSSize(width: (bounds.width - key) / CGFloat(keys.count), height: (bounds.height - key) / CGFloat(keys.count)))
    }
    private func keyStrips(_ key: CGFloat, _ cell: NSSize) {
        for (i, k) in keys.enumerated() {
            fill(k).setFill()
            NSRect(x: key + CGFloat(i) * cell.width, y: 0, width: cell.width + 1, height: key).fill()
            NSRect(x: 0, y: key + CGFloat(i) * cell.height, width: key, height: cell.height + 1).fill()
        }
        Theme.background.setFill()
        NSRect(x: 0, y: 0, width: key, height: key).fill()
    }

    /// Rows are grounds, columns are text: each cell is "Aa" in the column's colour on the row's, with the ratio.
    private func drawContrast() {
        let (key, cell) = cells()
        keyStrips(key, cell)
        for (row, ground) in keys.enumerated() {
            for (column, ink) in keys.enumerated() {
                let rect = NSRect(x: key + CGFloat(column) * cell.width, y: key + CGFloat(row) * cell.height, width: cell.width + 1, height: cell.height + 1)
                fill(ground).setFill()
                rect.fill()
                guard row != column, cell.width > 26, cell.height > 18 else { continue }
                let ratio = contrastRatio(ground, ink), plain = colorFromHex(readableText(on: displayHex(ground))) ?? .white
                let sample = text("Aa", fill(ink), size: min(22, cell.height * 0.42), weight: .semibold)
                let figure = text(String(format: "%.1f", ratio), plain.withAlphaComponent(0.75), size: 9.5, weight: .medium)
                let tall = cell.height > 44
                centred(sample, in: tall ? NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.68) : rect)
                if tall { centred(figure, in: NSRect(x: rect.minX, y: rect.minY + rect.height * 0.6, width: rect.width, height: rect.height * 0.34)) }
                // A ring in the corner where body text passes (4.5 to 1); a faint one where only large text does (3 to 1).
                if ratio >= 3 {
                    let mark = NSBezierPath(ovalIn: NSRect(x: rect.maxX - 13, y: rect.minY + 5, width: 7, height: 7))
                    plain.withAlphaComponent(ratio >= 4.5 ? 0.9 : 0.35).setStroke()
                    mark.lineWidth = 1.5
                    mark.stroke()
                }
            }
        }
    }

    /// Each cell is the pair side by side, with how far apart they are. Orange where a colour blind viewer would struggle.
    private func drawSeparation() {
        let (key, cell) = cells()
        keyStrips(key, cell)
        for (row, one) in keys.enumerated() {
            for (column, two) in keys.enumerated() {
                let rect = NSRect(x: key + CGFloat(column) * cell.width, y: key + CGFloat(row) * cell.height, width: cell.width + 1, height: cell.height + 1)
                guard row != column, let apart = separation(one, two) else { Theme.grey(0.04).setFill(); rect.fill(); continue }
                fill(one).setFill()
                NSRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height).fill()
                fill(two).setFill()
                NSRect(x: rect.midX, y: rect.minY, width: rect.width / 2 + 1, height: rect.height).fill()
                guard cell.width > 30, cell.height > 18 else { continue }
                let close = apart.worst < separationFloor
                let label = text(String(format: "%.0f", apart.seen) + (close && apart.worst < apart.seen - 0.5 ? String(format: " \u{2192} %.0f", apart.worst) : ""), close ? .black : .white, size: 10, weight: .semibold)
                let size = label.size(), pill = NSRect(x: rect.midX - size.width / 2 - 6, y: rect.midY - size.height / 2 - 2, width: size.width + 12, height: size.height + 4)
                (close ? NSColor.systemOrange : NSColor.black.withAlphaComponent(0.55)).setFill()
                NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
                label.draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + 2))
            }
        }
    }

    /// A column per colour: the colour above, what the palette's press gives below, and the difference.
    private func drawPrint() {
        let each = bounds.width / CGFloat(keys.count), channel = PrintCondition.current
        for (i, key) in keys.enumerated() {
            let column = NSRect(x: (CGFloat(i) * each).rounded(), y: 0, width: each.rounded(.up) + 1, height: bounds.height)
            fill(key).setFill()
            NSRect(x: column.minX, y: 0, width: column.width, height: bounds.height / 2).fill()
            let lower = NSRect(x: column.minX, y: bounds.height / 2, width: column.width, height: bounds.height / 2)
            guard let colour = ColourKeys.definition(of: key) ?? ColourDefinition.of(hex: key) else { continue }
            let printed = Rendering.of(colour, in: channel)
            guard let shown = printed.shown, let difference = printed.difference else {
                Theme.grey(0.08).setFill(); lower.fill()
                if each > 40 { centred(text("No Press", .secondaryLabelColor), in: lower) }
                continue
            }
            shown.display.setFill()
            lower.fill()
            guard each > 34 else { continue }
            let far = difference > Rendering.visible
            let label = text(String(format: "\u{0394}E %.1f", difference), far ? .black : .white, size: 10, weight: .semibold)
            let size = label.size(), pill = NSRect(x: lower.midX - size.width / 2 - 6, y: lower.maxY - size.height - 12, width: size.width + 12, height: size.height + 4)
            (far ? NSColor.systemOrange : NSColor.black.withAlphaComponent(0.55)).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            label.draw(at: NSPoint(x: pill.minX + 6, y: pill.minY + 2))
        }
    }

    /// Bands, one per colour, top to bottom.
    private func drawList() {
        let each = bounds.height / CGFloat(keys.count)
        for (i, key) in keys.enumerated() {
            fill(key).setFill()
            NSRect(x: 0, y: (CGFloat(i) * each).rounded(), width: bounds.width, height: each.rounded(.up) + 1).fill()
        }
    }

    /// The hue circle with a dot for each colour just outside it; a colour too grey to have a hue sits in the middle.
    private func drawHue() {
        let c = NSPoint(x: bounds.midX, y: bounds.midY), radius = (min(bounds.width, bounds.height) / 2 - 30) * 0.8, width: CGFloat = max(10, radius * 0.16)
        // The dots grow with the circle, so they are not lost when the panel fills the page.
        let dotRadius = max(9, radius * 0.045)
        // Red at the top, running clockwise through yellow, green, cyan, blue and magenta.
        func point(_ degrees: Double, _ r: CGFloat) -> NSPoint {
            let a = CGFloat(degrees * .pi / 180)
            return NSPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
        }
        for degree in stride(from: 0.0, to: 360, by: 1) {
            let wedge = NSBezierPath()
            wedge.move(to: point(degree - 0.3, radius - width / 2))
            wedge.line(to: point(degree - 0.3, radius + width / 2))
            wedge.line(to: point(degree + 1.3, radius + width / 2))
            wedge.line(to: point(degree + 1.3, radius - width / 2))
            wedge.close()
            NSColor(hue: CGFloat(degree / 360), saturation: 0.9, brightness: 1, alpha: 1).setFill()
            wedge.fill()
        }
        var grey = 0
        for key in keys {
            guard let v = ColourValues(key)?.hslUnit else { continue }
            let dot: NSPoint
            if v.s < 0.05 || v.l < 0.03 || v.l > 0.99 {
                // No hue to speak of: the greys line up across the middle.
                dot = NSPoint(x: c.x + CGFloat(grey) * (dotRadius * 2 + 2) - 10 * CGFloat(max(0, keys.count - 1)).truncatingRemainder(dividingBy: 3), y: c.y)
                grey += 1
            } else {
                dot = point(v.h, radius + width / 2 + dotRadius + 4)
            }
            let shape = NSBezierPath(ovalIn: NSRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
            fill(key).setFill()
            shape.fill()
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }

    /// A column per colour: a strip of the colour itself, then the grey of its lightness, with the figure.
    private func drawLuminance() {
        let each = bounds.width / CGFloat(keys.count), strip = min(24, bounds.height * 0.15)
        for (i, key) in keys.enumerated() {
            let x = (CGFloat(i) * each).rounded(), column = NSRect(x: x, y: 0, width: each.rounded(.up) + 1, height: bounds.height)
            fill(key).setFill()
            NSRect(x: column.minX, y: 0, width: column.width, height: strip).fill()
            let l = lightness(of: key)
            // The grey of the same lightness, by way of Lab, so the two look equally light.
            (LabD50(l: l, a: 0, b: 0).xyz.display).setFill()
            let body = NSRect(x: column.minX, y: strip, width: column.width, height: bounds.height - strip)
            body.fill()
            if each > 30 { centred(text("\(Int(l.rounded()))%", l > 55 ? .black : .white, weight: .medium), in: body) }
        }
    }

    /// A row per colour; the first column as it is, then one column for each kind of colour vision.
    private func drawVision() {
        let kinds = ColourVision.allCases, head: CGFloat = 34
        let first = bounds.width * 0.14, each = (bounds.width - first) / CGFloat(kinds.count)
        Theme.grey(0.06).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: head).fill()
        centred(text("Original", .labelColor, weight: .medium), in: NSRect(x: 0, y: 0, width: first, height: head))
        for (k, kind) in kinds.enumerated() {
            let cell = NSRect(x: first + CGFloat(k) * each, y: 0, width: each, height: head)
            centred(text(kind.name, .labelColor, weight: .medium), in: NSRect(x: cell.minX, y: 3, width: cell.width, height: 15))
            if each > 110 { centred(text(kind.prevalence, .secondaryLabelColor, size: 9.5), in: NSRect(x: cell.minX, y: 17, width: cell.width, height: 14)) }
        }
        let row = (bounds.height - head) / CGFloat(keys.count)
        for (i, key) in keys.enumerated() {
            let y = head + (CGFloat(i) * row).rounded(), h = row.rounded(.up) + 1
            fill(key).setFill()
            NSRect(x: 0, y: y, width: first, height: h).fill()
            for (k, kind) in kinds.enumerated() {
                kind.colour(key).setFill()
                NSRect(x: (first + CGFloat(k) * each).rounded(), y: y, width: each.rounded(.up) + 1, height: h).fill()
            }
        }
    }

    private func drawGradient() {
        NSGradient(colors: keys.map(fill))?.draw(in: bounds, angle: 0)
    }

    /// Each colour as a ground, with the next colour set on it as a square.
    private func drawCombos() {
        let each = bounds.width / CGFloat(keys.count)
        for (i, key) in keys.enumerated() {
            let ground = NSRect(x: (CGFloat(i) * each).rounded(), y: 0, width: each.rounded(.up) + 1, height: bounds.height)
            fill(key).setFill()
            ground.fill()
            let side = min(each, bounds.height) * 0.6
            fill(keys[(i + 1) % keys.count]).setFill()
            NSRect(x: ground.minX + (each - side) / 2, y: (bounds.height - side) / 2, width: side, height: side).fill()
        }
    }

    /// The colours as squares on a light ground, and the same on a dark one.
    private func drawLightDark() {
        let half = bounds.width / 2
        let grounds: [(NSRect, NSColor)] = [(NSRect(x: 0, y: 0, width: half, height: bounds.height), NSColor.white),
                                            (NSRect(x: half, y: 0, width: half, height: bounds.height), NSColor.black)]   // pure white and the deepest black: the two extremes a colour can sit on
        for (ground, colour) in grounds {
            colour.setFill()
            ground.fill()
            // As many to a row as fit, as large as the ground allows, the whole block in the middle.
            let gap: CGFloat = 14, n = keys.count
            var best: (side: CGFloat, columns: Int) = (0, 1)
            for columns in 1...n {
                let rows = Int(ceil(Double(n) / Double(columns)))
                let side = min((ground.width - gap * CGFloat(columns + 1)) / CGFloat(columns), (ground.height - gap * CGFloat(rows + 1)) / CGFloat(rows), 72)
                if side > best.side { best = (side, columns) }
            }
            let rows = Int(ceil(Double(n) / Double(best.columns)))
            let blockW = CGFloat(best.columns) * best.side + CGFloat(best.columns - 1) * gap, blockH = CGFloat(rows) * best.side + CGFloat(rows - 1) * gap
            for (i, key) in keys.enumerated() {
                let column = i % best.columns, row = i / best.columns
                fill(key).setFill()
                NSRect(x: ground.minX + (ground.width - blockW) / 2 + CGFloat(column) * (best.side + gap),
                       y: (ground.height - blockH) / 2 + CGFloat(row) * (best.side + gap), width: best.side, height: best.side).fill()
            }
        }
    }
}

/// A panel: its title, the mark that opens it to the full page, and its picture.
private final class AnalysisPanel: NSView {
    let plot: AnalysisPlot
    var onExpand: (() -> Void)?

    init(_ kind: AnalysisKind, keys: [String], expanded: Bool) {
        plot = AnalysisPlot(kind)
        super.init(frame: .zero)
        plot.keys = keys
        let title = NSTextField(labelWithString: kind.title)
        title.font = NSFont.systemFont(ofSize: TextSize.body, weight: .bold)
        let about = caption(kind.about)
        about.textColor = .secondaryLabelColor
        about.lineBreakMode = .byTruncatingTail
        about.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let open = symbolButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                tooltip: expanded ? "Back To Every Panel" : "Open \(kind.title) To The Full Page", target: self, action: #selector(expandTapped))
        for v in [title, about, open, plot] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        translatesAutoresizingMaskIntoConstraints = false
        let height = plot.heightAnchor.constraint(equalToConstant: 230)
        height.priority = expanded ? .defaultLow : .required
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            about.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            about.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            about.trailingAnchor.constraint(lessThanOrEqualTo: open.leadingAnchor, constant: -8),
            open.trailingAnchor.constraint(equalTo: trailingAnchor),
            open.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            plot.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            plot.leadingAnchor.constraint(equalTo: leadingAnchor),
            plot.trailingAnchor.constraint(equalTo: trailingAnchor),
            plot.bottomAnchor.constraint(equalTo: bottomAnchor),
            height,
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func expandTapped() { onExpand?() }
}

private final class AnalysisPage: NSView {
    override var isFlipped: Bool { true }
}

/// The Analysis page, over the page it was opened from. Back returns to that page.
final class AnalysisViewController: NSViewController {
    private let subject: String
    private let keys: [String]
    private let onClose: () -> Void
    private let scroll = FittedScrollView()
    private let page = AnalysisPage()
    private let column = NSStackView()
    /// The one panel filling the page, when there is one.
    private var expanded: AnalysisKind?
    private lazy var back = toolButton("Back", "chevron.left", "Back (Escape)", target: self, action: #selector(backTapped))
    private let heading = NSTextField(labelWithString: "")
    private let detail = caption("")

    /// `subject` is the palette's or the swatch's name.
    init(subject: String, keys: [String], onClose: @escaping () -> Void) {
        self.subject = subject
        self.keys = keys
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        heading.font = PageStyle.titleFont
        heading.lineBreakMode = .byTruncatingTail
        detail.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, detail])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        // The titles keep their own height; the panels below take what is left.
        titles.setHuggingPriority(.required, for: .vertical)
        for label in [heading, detail] { label.setContentHuggingPriority(.required, for: .vertical) }
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        let bar = ActionBar(leading: [back])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 34
        scroll.documentView = page
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        page.addSubview(column)
        for v in [titles, bar, scroll, page, column] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in [titles, bar, scroll] as [NSView] { view.addSubview(v) }
        let side = PageStyle.side
        NSLayoutConstraint.activate([
            titles.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            titles.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -side),
            bar.topAnchor.constraint(equalTo: titles.bottomAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: side),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -side),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: page.topAnchor),
            column.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: side),
            column.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -side),
            column.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -24),
            // A panel opened to the full page is as tall as the page allows.
            page.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        fill()
    }

    /// Every panel, two to a row; or the one that has been opened, alone.
    private func fill() {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        heading.stringValue = "Analysis"
        detail.stringValue = subject + "  \u{00B7}  " + (keys.count == 1 ? "One Swatch" : plural(keys.count, "Swatch", "Swatches"))
            + "  \u{00B7}  Print: \(PrintCondition.name())" + (expanded.map { "  \u{00B7}  " + $0.title } ?? "")
        back.title = expanded == nil ? "Back" : "Every Panel"
        back.invalidateIntrinsicContentSize()
        if let kind = expanded {
            let panel = AnalysisPanel(kind, keys: keys, expanded: true)
            panel.onExpand = { [weak self] in self?.expanded = nil; self?.fill() }
            column.addArrangedSubview(panel)
            panel.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            let tall = panel.plot.heightAnchor.constraint(equalTo: scroll.heightAnchor, constant: -70)
            tall.priority = .defaultHigh
            tall.isActive = true
            return
        }
        let kinds = AnalysisKind.offered(for: keys.count)
        for start in stride(from: 0, to: kinds.count, by: 2) {
            let pair = kinds[start..<min(start + 2, kinds.count)].map { kind -> AnalysisPanel in
                let panel = AnalysisPanel(kind, keys: keys, expanded: false)
                panel.onExpand = { [weak self] in self?.expanded = kind; self?.fill() }
                return panel
            }
            // An odd one out keeps to its half of the page.
            let row = NSStackView(views: pair.count == 2 ? pair : pair + [NSView()])
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 40
            column.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
    }

    @objc private func backTapped() {
        if expanded != nil { expanded = nil; fill() } else { onClose() }
    }
    override func cancelOperation(_ sender: Any?) { backTapped() }
}
