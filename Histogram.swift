import AppKit

// ---------- Histograms ----------
//
// A swatch is one flat colour, so its own histogram is one spike per channel: where each channel's
// value sits between nothing and full. On its own that says little, so the spikes stand over a
// faint histogram of the whole palette: every colour in it, counted channel by channel. A swatch
// is then seen against the spread it belongs to. Merged, the channels share one plot, lit so that
// spikes which coincide go white, as an image editor's "Colours" histogram does. Split, each
// channel has a strip of its own, one under the other.

/// Every set of values a card can show has a histogram. (Hex is the RGB values written in base 16,
/// so RGB is its histogram.) The raw values are kept in preferences, so new kinds go at the end.
enum HistogramType: Int, CaseIterable {
    case rgb, cmyk, hsl, hsv, p3, adobeRGB, rec2020, lab, ycbcr

    /// The order they are offered in: the order of a card's rows, then the video signal.
    static let offered: [HistogramType] = [.rgb, .hsl, .hsv, .cmyk, .p3, .adobeRGB, .rec2020, .lab, .ycbcr]

    var title: String {
        switch self {
        case .rgb: return "RGB"
        case .cmyk: return "CMYK"
        case .hsl: return "HSL"
        case .hsv: return "HSV"
        case .p3: return "P3"
        case .adobeRGB: return "Adobe"
        case .rec2020: return "BT.2020"
        case .lab: return "L*a*b*"
        case .ycbcr: return "Y\u{2032}CbCr"
        }
    }

    var channels: [String] {
        switch self {
        case .rgb, .p3, .adobeRGB, .rec2020: return ["Red", "Green", "Blue"]
        case .cmyk: return ["Cyan", "Magenta", "Yellow", "Black"]
        case .hsl: return ["Hue", "Saturation", "Lightness"]
        case .hsv: return ["Hue", "Saturation", "Value"]
        case .lab: return ["L*", "a*", "b*"]
        case .ycbcr: return ["Y\u{2032}", "Cb", "Cr"]
        }
    }

    /// Each channel's scale as its users write it: 0 to 255, 0 to 360 degrees, 0 to 100 percent, -128 to 127.
    var ranges: [ClosedRange<Int>] {
        switch self {
        case .rgb, .p3, .adobeRGB, .rec2020: return [0...255, 0...255, 0...255]
        case .cmyk: return [0...100, 0...100, 0...100, 0...100]
        case .hsl, .hsv: return [0...360, 0...100, 0...100]
        case .lab: return [0...100, -128...127, -128...127]
        case .ycbcr: return [0...1023, 0...1023, 0...1023]
        }
    }

    /// The scales in words, for the bar.
    var scale: String {
        switch self {
        case .rgb, .p3, .adobeRGB, .rec2020: return "0 To 255"
        case .cmyk: return "0 To 100, For \(PrintCondition.current.press ?? PressProfiles.generic)"
        case .hsl, .hsv: return "Hue 0 To 360, The Rest 0 To 100"
        case .lab: return "L* 0 To 100, a* And b* \u{2212}128 To 127"
        case .ycbcr: return "Rec. 709, 10-Bit Legal Range; 512 Is No Colour"
        }
    }

    var colours: [NSColor] {
        let red = NSColor(srgbRed: 1, green: 0.22, blue: 0.16, alpha: 1), green = NSColor(srgbRed: 0.25, green: 0.9, blue: 0.25, alpha: 1), blue = NSColor(srgbRed: 0.2, green: 0.35, blue: 1, alpha: 1)
        switch self {
        case .rgb, .p3, .adobeRGB, .rec2020: return [red, green, blue]
        case .cmyk: return [NSColor(srgbRed: 0, green: 0.75, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.95, green: 0.1, blue: 0.6, alpha: 1), NSColor(srgbRed: 1, green: 0.9, blue: 0.1, alpha: 1), NSColor(white: 0.72, alpha: 1)]
        // Not colours of light, so they are simply three that tell apart: the hue, how strong, how light.
        case .hsl, .hsv: return [NSColor(srgbRed: 0.75, green: 0.35, blue: 1, alpha: 1), NSColor(srgbRed: 0.1, green: 0.8, blue: 0.75, alpha: 1), NSColor(white: 0.8, alpha: 1)]
        // Lightness, then the two opponent axes: green to red, blue to yellow.
        case .lab: return [NSColor(white: 0.8, alpha: 1), NSColor(srgbRed: 1, green: 0.35, blue: 0.5, alpha: 1), NSColor(srgbRed: 1, green: 0.75, blue: 0.15, alpha: 1)]
        // Brightness, then the blue and the red difference.
        case .ycbcr: return [NSColor(white: 0.8, alpha: 1), blue, red]
        }
    }

    /// The safe range, where there is one. Outside it detail is lost: on a screen or in video,
    /// values under 16 crush to black and over 235 blow out to white; on a press, a dot under 3%
    /// does not hold and the paper shows through, and over 95% the dots fill in to solid. Hue,
    /// saturation, lightness and Lab have no such limits: every value of theirs is a usable one.
    var safe: ClosedRange<Int>? {
        switch self {
        case .rgb, .p3, .adobeRGB, .rec2020: return 16...235
        case .cmyk: return 3...95
        case .ycbcr: return 64...940
        case .hsl, .hsv, .lab: return nil
        }
    }
    /// What the zone below and above the safe range is called.
    var zones: (low: String, high: String) { self == .cmyk ? ("White Out", "Black") : ("Black", "White Out") }

    /// The channels of a colour that sit outside the safe range: "Red In White Out, Blue In Black".
    func warnings(for values: [Int]) -> [String] {
        guard let safe = safe else { return [] }
        return zip(channels, values).compactMap { name, value in
            // No ink at all is not a risk: there is no dot to lose. Only a dot too small to hold is.
            if self == .cmyk, value == 0 { return nil }
            return value < safe.lowerBound ? "\(name) In \(zones.low)" : value > safe.upperBound ? "\(name) In \(zones.high)" : nil
        }
    }

    /// The card row these values are, where it is one.
    private var format: ColourFormat? {
        switch self {
        case .rgb: return .rgb
        case .hsl: return .hsl
        case .hsv: return .hsv
        case .p3: return .p3
        case .adobeRGB: return .adobeRGB
        case .rec2020: return .rec2020
        case .lab: return .lab
        case .cmyk, .ycbcr: return nil
        }
    }

    /// A colour's channel values on this scale: the very numbers its card shows, or the ink
    /// percentages for the press in force. Lab is rounded to whole numbers.
    func values(of key: String) -> [Int]? {
        if self == .ycbcr {
            guard let colour = ColourKeys.definition(of: key) ?? ColourDefinition.of(hex: key) else { return nil }
            return RGBSpace.rec709.yCbCr(RGBSpace.rec709.values(of: colour.master), legal: true)
        }
        guard let format = format else { return PrintCondition.inks(of: key) }
        guard ColourValues(key) != nil else { return nil }
        let numbers = format.fields(key).compactMap { Double($0) }.map { Int($0.rounded()) }
        return numbers.count == channels.count ? numbers : nil
    }

    /// Where a value sits along its channel's scale, 0 to 1.
    func place(_ value: Int, in channel: Int) -> CGFloat {
        let range = ranges[channel]
        return CGFloat(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / CGFloat(range.count - 1)
    }
}

enum Histogram {
    /// How many of the colours fall at each value, for each channel: counts[channel][value - the scale's lowest].
    static func counts(of keys: [String], as type: HistogramType) -> [[Int]] {
        var out = type.ranges.map { Array(repeating: 0, count: $0.count) }
        for key in keys {
            guard let values = type.values(of: key), values.count == type.channels.count else { continue }
            for (channel, value) in values.enumerated() {
                let range = type.ranges[channel]
                out[channel][min(max(value, range.lowerBound), range.upperBound) - range.lowerBound] += 1
            }
        }
        return out
    }
}

/// The plot itself: merged into one, or a strip per channel.
final class HistogramView: NSView {
    static let mergedHeight: CGFloat = 72
    static let stripHeight: CGFloat = 34
    static let stripGap: CGFloat = 4

    var type = HistogramType.rgb { didSet { changed() } }
    var split = false { didSet { changed() } }
    /// This swatch's value in each channel; nil when it cannot be worked out.
    var own: [Int]? { didSet { needsDisplay = true } }
    /// The palette's counts, channel by channel.
    var counts: [[Int]] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        let n = CGFloat(type.channels.count)
        return NSSize(width: NSView.noIntrinsicMetric, height: split ? n * HistogramView.stripHeight + (n - 1) * HistogramView.stripGap : HistogramView.mergedHeight)
    }
    private func changed() { invalidateIntrinsicContentSize(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let n = type.channels.count
        if split {
            for channel in 0..<n {
                let strip = NSRect(x: 0, y: CGFloat(channel) * (HistogramView.stripHeight + HistogramView.stripGap), width: bounds.width, height: HistogramView.stripHeight)
                plot([channel], in: strip, lit: false)
                let value = own.flatMap { $0.indices.contains(channel) ? "\($0[channel])" : nil } ?? "\u{2014}"
                let label = NSAttributedString(string: "\(type.channels[channel])  \(value)", attributes: [
                    .font: NSFont.systemFont(ofSize: TextSize.caption, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.7)])
                // The label keeps clear of the spike: on the right while the value is low, on the left once it is high.
                let low = type.place(own?[safe: channel] ?? type.ranges[channel].lowerBound, in: channel) < 0.5
                label.draw(at: NSPoint(x: low ? strip.maxX - label.size().width - 8 : strip.minX + 8, y: strip.minY + 4))
            }
        } else {
            plot(Array(0..<n), in: bounds, lit: true)
        }
    }

    /// One plot: the palette's spread faintly, this swatch's spikes over it. `lit` adds the channels'
    /// light together, so spikes in one place go towards white.
    private func plot(_ channels: [Int], in rect: NSRect, lit: Bool) {
        // Always dark, whatever the theme: the channel colours are read against it.
        NSColor(white: 0.13, alpha: 1).setFill()
        let frame = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        frame.fill()
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        frame.addClip()
        if lit { context.compositingOperation = .plusLighter }
        let inner = rect.insetBy(dx: 6, dy: 5)
        func x(_ value: Int, _ channel: Int) -> CGFloat { inner.minX + type.place(value, in: channel) * inner.width }
        // The zones outside the safe range, shaded at each end with a line where safe begins and ends.
        context.saveGraphicsState()
        context.compositingOperation = .sourceOver
        // Only where the values have a safe range, which is the same for every channel that does.
        let safe = type.safe ?? type.ranges[0]
        let low = NSRect(x: rect.minX, y: rect.minY, width: x(safe.lowerBound, 0) - rect.minX, height: rect.height)
        let high = NSRect(x: x(safe.upperBound, 0), y: rect.minY, width: rect.maxX - x(safe.upperBound, 0), height: rect.height)
        for zone in (type.safe == nil ? [] : [low, high]) {
            NSColor(white: 1, alpha: 0.07).setFill()
            zone.fill()
            // Fine diagonal lines, so a zone reads as "not here" without a colour of its own.
            context.saveGraphicsState()
            NSBezierPath(rect: zone).addClip()
            NSColor(white: 1, alpha: 0.10).setStroke()
            let hatch = NSBezierPath()
            var at = zone.minX - zone.height
            while at < zone.maxX { hatch.move(to: NSPoint(x: at, y: zone.maxY)); hatch.line(to: NSPoint(x: at + zone.height, y: zone.minY)); at += 5 }
            hatch.lineWidth = 1
            hatch.stroke()
            context.restoreGraphicsState()
        }
        NSColor(white: 1, alpha: type.safe == nil ? 0 : 0.28).setFill()
        NSRect(x: low.maxX - 0.5, y: rect.minY, width: 1, height: rect.height).fill()
        NSRect(x: high.minX - 0.5, y: rect.minY, width: 1, height: rect.height).fill()
        context.restoreGraphicsState()
        let tallest = CGFloat(max(1, counts.flatMap { $0 }.max() ?? 1))
        for channel in channels {
            let colour = type.colours[channel]
            if counts.indices.contains(channel) {
                colour.withAlphaComponent(0.38).setFill()
                for (offset, count) in counts[channel].enumerated() where count > 0 {
                    let h = max(3, inner.height * 0.6 * CGFloat(count) / tallest)
                    NSRect(x: x(offset + type.ranges[channel].lowerBound, channel) - 1.5, y: inner.maxY - h, width: 3, height: h).fill()
                }
            }
            if let value = own?[safe: channel] {
                colour.setFill()
                NSRect(x: x(value, channel) - 1.5, y: inner.minY, width: 3, height: inner.height).fill()
            }
        }
        context.restoreGraphicsState()
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// A swatch's histogram: the plot, and a line saying what it shows or which channels are outside the safe range.
/// Which values it counts, and whether the channels are merged, is chosen once for every swatch on the bar above.
final class HistogramPanel: NSView {
    static let width: CGFloat = 460
    let plot = HistogramView()
    private let about = caption("")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        about.lineBreakMode = .byTruncatingTail
        about.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [plot, about] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            plot.topAnchor.constraint(equalTo: topAnchor),
            plot.leadingAnchor.constraint(equalTo: leadingAnchor),
            plot.trailingAnchor.constraint(equalTo: trailingAnchor),
            about.topAnchor.constraint(equalTo: plot.bottomAnchor, constant: 4),
            about.leadingAnchor.constraint(equalTo: leadingAnchor),
            about.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            about.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows a swatch against the colours of its page.
    func show(_ key: String, among population: [String], type: HistogramType, split: Bool) {
        plot.type = type
        plot.split = split
        plot.own = type.values(of: key)
        plot.counts = Histogram.counts(of: population, as: type)
        let unsafe = plot.own.map { type.warnings(for: $0) } ?? []
        about.textColor = unsafe.isEmpty ? .tertiaryLabelColor : .systemOrange
        let values = plot.own.map { zip(type.channels, $0).map { "\($0.count > 2 ? String($0.prefix(1)) : $0) \($1)" }.joined(separator: "   ") } ?? ""
        about.stringValue = plot.own == nil ? "Not Worked Out: The Press Profile Is Not On This Mac" : unsafe.isEmpty ? values : values + "   \u{00B7}   " + unsafe.joined(separator: ", ")
        plot.toolTip = "Bright: This Colour. Faint: Every Colour On The Page." + (type.safe == nil ? ""
            : type == .cmyk ? " The Shaded Ends Are Outside The Safe Range: Under 3% The Dot Does Not Hold, Over 95% It Fills In To Solid."
            : " The Shaded Ends Are Outside The Safe Range: Under 16 Crushes To Black, Over 235 Blows Out To White.")
    }
}

/// The second bar, shown while Histogram is on: the choices every swatch's histogram follows.
final class HistogramBar: NSView {
    var onChange: (() -> Void)?
    private lazy var types = ToggleBar(labels: HistogramType.offered.map { $0.title }, target: self, action: #selector(changed))
    private lazy var layouts = ToggleBar(labels: ["Merged", "Per Channel"], target: self, action: #selector(changed))
    private let about = caption("")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        types.toolTip = "Which Values Every Histogram Counts. CMYK Is The Build For The Palette's Press."
        layouts.toolTip = "One Plot With Every Channel, Or A Strip For Each Channel"
        about.textColor = .secondaryLabelColor
        about.lineBreakMode = .byTruncatingTail
        about.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = ActionBar(leading: [ActionBar.label("Histogram"), types, layouts, about])
        addSubview(bar)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let type = Prefs.histogramType
        types.selectedSegment = HistogramType.offered.firstIndex(of: type) ?? 0
        layouts.selectedSegment = Prefs.histogramSplit ? 1 : 0
        let safe = type.safe.map { "  \u{00B7}  Safe \($0.lowerBound) To \($0.upperBound)" } ?? ""
        about.stringValue = "\(type.scale)\(safe)  \u{00B7}  Bright: The Swatch. Faint: Every Colour On The Page."
    }

    @objc private func changed() {
        Prefs.histogramType = HistogramType.offered.indices.contains(types.selectedSegment) ? HistogramType.offered[types.selectedSegment] : .rgb
        Prefs.histogramSplit = layouts.selectedSegment == 1
        refresh()
        onChange?()
    }
}

extension Prefs {
    /// Histograms on every swatch of a palette's vertical view.
    static var histogramType: HistogramType {
        get { HistogramType(rawValue: AppPreferences.shared.integer(forKey: "histogramType")) ?? .rgb }
        set { AppPreferences.shared.set(newValue.rawValue, forKey: "histogramType") }
    }
    static var histogramSplit: Bool {
        get { AppPreferences.shared.bool(forKey: "histogramSplit") }
        set { AppPreferences.shared.set(newValue, forKey: "histogramSplit") }
    }
    /// Every swatch's channels, and every swatch's history, in a palette's vertical view.
    static var paletteChannels: Bool {
        get { AppPreferences.shared.bool(forKey: "paletteChannels") }
        set { AppPreferences.shared.set(newValue, forKey: "paletteChannels") }
    }
    static var paletteHistory: Bool {
        get { AppPreferences.shared.bool(forKey: "paletteHistory") }
        set { AppPreferences.shared.set(newValue, forKey: "paletteHistory") }
    }
    /// How the contrast on a card is worked out: "wcag" or "apca".
    static var contrastMethod: String {
        get { AppPreferences.shared.string(forKey: "contrastMethod") == "apca" ? "apca" : "wcag" }
        set { AppPreferences.shared.set(newValue, forKey: "contrastMethod") }
    }
    /// The contrast lines for a colour: a title, then white and black text on it, by the method chosen.
    static func contrastLines(for hex: String) -> (title: String, line: String) {
        let shown = displayHex(hex)
        if contrastMethod == "apca" {
            let white = abs(apcaContrast(text: "#FFFFFF", background: shown)), black = abs(apcaContrast(text: "#000000", background: shown))
            return ("APCA Text Contrast", String(format: "White Lc %.0f  \u{00B7}  Black Lc %.0f", white, black))
        }
        let white = contrastRatio(shown, "#FFFFFF"), black = contrastRatio(shown, "#000000")
        return ("WCAG Text Contrast", String(format: "White %.1f %@  \u{00B7}  Black %.1f %@", white, contrastGrade(white), black, contrastGrade(black)))
    }
    /// How a contrast result stands: it fails, it passes for large text only, or it passes.
    enum ContrastVerdict { case fail, partial, pass }

    /// The contrast of white and of black text on a colour, by the method chosen: a title, then
    /// for each the number, its grade in words and how the grade stands.
    static func contrast(for hex: String) -> (title: String, rows: [(name: String, value: String, grade: String, verdict: ContrastVerdict)]) {
        let shown = displayHex(hex)
        if contrastMethod == "apca" {
            func row(_ name: String, _ text: String) -> (name: String, value: String, grade: String, verdict: ContrastVerdict) {
                let lc = abs(apcaContrast(text: text, background: shown)), grade = apcaGrade(lc)
                return (name, String(format: "Lc %.0f", lc), grade.grade, grade.verdict)
            }
            return ("APCA Text Contrast", [row("White", "#FFFFFF"), row("Black", "#000000")])
        }
        func row(_ name: String, _ text: String) -> (name: String, value: String, grade: String, verdict: ContrastVerdict) {
            let ratio = contrastRatio(shown, text)
            return (name, String(format: "%.1f", ratio), ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "AA Large" : "Fail",
                    ratio >= 4.5 ? .pass : ratio >= 3 ? .partial : .fail)
        }
        return ("WCAG Text Contrast", [row("White", "#FFFFFF"), row("Black", "#000000")])
    }

    /// APCA's lightness contrast in words: 75 and over suits body text, 60 other text, 45 large text only.
    static func apcaGrade(_ lc: Double) -> (grade: String, verdict: ContrastVerdict) {
        lc >= 75 ? ("Body", .pass) : lc >= 60 ? ("Text", .pass) : lc >= 45 ? ("Large", .partial) : ("Fail", .fail)
    }

    /// Which view the gamut map shows: the round Lab view until another is chosen.
    static var gamutView: GamutView {
        get { GamutView(rawValue: AppPreferences.shared.integer(forKey: "gamutView")) ?? .lab }
        set { AppPreferences.shared.set(newValue.rawValue, forKey: "gamutView") }
    }
    /// Notes are shown until switched off.
    static var paletteNotes: Bool {
        get { AppPreferences.shared.object(forKey: "paletteNotes") == nil ? true : AppPreferences.shared.bool(forKey: "paletteNotes") }
        set { AppPreferences.shared.set(newValue, forKey: "paletteNotes") }
    }
    static var histograms: Bool {
        get { AppPreferences.shared.bool(forKey: "paletteHistograms") }
        set { AppPreferences.shared.set(newValue, forKey: "paletteHistograms") }
    }
}
