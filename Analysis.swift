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

enum AnalysisKind: CaseIterable {
    case list, hue, luminance, vision, gradient, combos, lightDark

    var title: String {
        switch self {
        case .list: return "Colours List"
        case .hue: return "Hue Distribution"
        case .luminance: return "Luminance Map"
        case .vision: return "Colour Blind Simulation"
        case .gradient: return "View As Gradient"
        case .combos: return "Colour Combos"
        case .lightDark: return "Light And Dark"
        }
    }

    var about: String {
        switch self {
        case .list: return "Every colour, top to bottom, with nothing between them"
        case .hue: return "Where each colour sits round the hue circle; greys gather in the middle"
        case .luminance: return "Each colour with its hue taken away: how light it is, as a percentage"
        case .vision: return "Each colour as people with the commonest colour vision deficiencies see it"
        case .gradient: return "The colours run into one another, in order"
        case .combos: return "Each colour as a ground with the next colour set on it"
        case .lightDark: return "Each colour on a light ground and on a dark one"
        }
    }

    /// Whether the panel needs more than one colour to say anything.
    var needsSeveral: Bool { self == .gradient || self == .combos }

    /// The panels for these colours: all seven for a palette, five for one swatch.
    static func offered(for count: Int) -> [AnalysisKind] { allCases.filter { count > 1 || !$0.needsSeveral } }
}

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
        case .hue: drawHue()
        case .luminance: drawLuminance()
        case .vision: drawVision()
        case .gradient: drawGradient()
        case .combos: drawCombos()
        case .lightDark: drawLightDark()
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
        let c = NSPoint(x: bounds.midX, y: bounds.midY), radius = min(bounds.width, bounds.height) / 2 - 30, width: CGFloat = max(10, radius * 0.16)
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
                dot = NSPoint(x: c.x + CGFloat(grey) * 20 - 10 * CGFloat(max(0, keys.count - 1)).truncatingRemainder(dividingBy: 3), y: c.y)
                grey += 1
            } else {
                dot = point(v.h, radius + width / 2 + 12)
            }
            let shape = NSBezierPath(ovalIn: NSRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18))
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
        let grounds: [(NSRect, NSColor)] = [(NSRect(x: 0, y: 0, width: half, height: bounds.height), NSColor(white: 0.98, alpha: 1)),
                                            (NSRect(x: half, y: 0, width: half, height: bounds.height), NSColor(white: 0.19, alpha: 1))]
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
    private let scroll = NSScrollView()
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
        detail.stringValue = subject + "  \u{00B7}  " + (keys.count == 1 ? "One Swatch" : plural(keys.count, "Swatch", "Swatches")) + (expanded.map { "  \u{00B7}  " + $0.title } ?? "")
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
