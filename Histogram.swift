import AppKit

// ---------- Histograms ----------
//
// A swatch is one flat colour, so its own histogram is one spike per channel: where each channel's
// value sits between nothing and full. On its own that says little, so the spikes stand over a
// faint histogram of the whole palette: every colour in it, counted channel by channel. A swatch
// is then seen against the spread it belongs to. Merged, the channels share one plot, lit so that
// spikes which coincide go white, as an image editor's "Colours" histogram does. Split, each
// channel has a strip of its own, one under the other.

enum HistogramType: Int, CaseIterable {
    case rgb, cmyk

    var title: String { self == .rgb ? "RGB" : "CMYK" }
    var channels: [String] { self == .rgb ? ["Red", "Green", "Blue"] : ["Cyan", "Magenta", "Yellow", "Black"] }
    /// The top of the scale as its users write it.
    var top: Int { self == .rgb ? 255 : 100 }
    var bins: Int { top + 1 }
    var colours: [NSColor] {
        self == .rgb
            ? [NSColor(srgbRed: 1, green: 0.22, blue: 0.16, alpha: 1), NSColor(srgbRed: 0.25, green: 0.9, blue: 0.25, alpha: 1), NSColor(srgbRed: 0.2, green: 0.35, blue: 1, alpha: 1)]
            : [NSColor(srgbRed: 0, green: 0.75, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.95, green: 0.1, blue: 0.6, alpha: 1), NSColor(srgbRed: 1, green: 0.9, blue: 0.1, alpha: 1), NSColor(white: 0.72, alpha: 1)]
    }

    /// The safe range. Outside it detail is lost: on a screen or in video, values under 16 crush to
    /// black and over 235 blow out to white; on a press, a dot under 3% does not hold and the paper
    /// shows through, and over 95% the dots fill in to solid.
    var safe: ClosedRange<Int> { self == .rgb ? 16...235 : 3...95 }
    /// What the zone below and above the safe range is called.
    var zones: (low: String, high: String) { self == .rgb ? ("Black", "White Out") : ("White Out", "Black") }

    /// The channels of a colour that sit outside the safe range: "Red In White Out, Blue In Black".
    func warnings(for values: [Int]) -> [String] {
        zip(channels, values).compactMap { name, value in
            // No ink at all is not a risk: there is no dot to lose. Only a dot too small to hold is.
            if self == .cmyk, value == 0 { return nil }
            return value < safe.lowerBound ? "\(name) In \(zones.low)" : value > safe.upperBound ? "\(name) In \(zones.high)" : nil
        }
    }

    /// A colour's channel values on this scale: sRGB bytes, or the ink percentages for the press in force.
    func values(of key: String) -> [Int]? {
        switch self {
        case .rgb: return ColourValues(key).map { [$0.r, $0.g, $0.b] }
        case .cmyk: return PrintCondition.inks(of: key)
        }
    }
}

enum Histogram {
    /// How many of the colours fall at each value, for each channel: counts[channel][value].
    static func counts(of keys: [String], as type: HistogramType) -> [[Int]] {
        var out = Array(repeating: Array(repeating: 0, count: type.bins), count: type.channels.count)
        for key in keys {
            guard let values = type.values(of: key), values.count == type.channels.count else { continue }
            for (channel, value) in values.enumerated() { out[channel][min(max(value, 0), type.top)] += 1 }
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
                let low = (own?[safe: channel] ?? 0) < type.top / 2
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
        let step = inner.width / CGFloat(type.top)
        func x(_ value: Int) -> CGFloat { inner.minX + CGFloat(value) * step }
        // The zones outside the safe range, shaded at each end with a line where safe begins and ends.
        context.saveGraphicsState()
        context.compositingOperation = .sourceOver
        let low = NSRect(x: rect.minX, y: rect.minY, width: x(type.safe.lowerBound) - rect.minX, height: rect.height)
        let high = NSRect(x: x(type.safe.upperBound), y: rect.minY, width: rect.maxX - x(type.safe.upperBound), height: rect.height)
        for zone in [low, high] {
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
        NSColor(white: 1, alpha: 0.28).setFill()
        NSRect(x: low.maxX - 0.5, y: rect.minY, width: 1, height: rect.height).fill()
        NSRect(x: high.minX - 0.5, y: rect.minY, width: 1, height: rect.height).fill()
        context.restoreGraphicsState()
        let tallest = CGFloat(max(1, counts.flatMap { $0 }.max() ?? 1))
        for channel in channels {
            let colour = type.colours[channel]
            if counts.indices.contains(channel) {
                colour.withAlphaComponent(0.38).setFill()
                for (value, count) in counts[channel].enumerated() where count > 0 {
                    let h = max(3, inner.height * 0.6 * CGFloat(count) / tallest)
                    NSRect(x: x(value) - 1.5, y: inner.maxY - h, width: 3, height: h).fill()
                }
            }
            if let value = own?[safe: channel] {
                colour.setFill()
                NSRect(x: x(value) - 1.5, y: inner.minY, width: 3, height: inner.height).fill()
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
        let values = plot.own.map { zip(type.channels, $0).map { "\($0.prefix(1)) \($1)" }.joined(separator: "   ") } ?? ""
        about.stringValue = plot.own == nil ? "Not Worked Out: The Press Profile Is Not On This Mac" : unsafe.isEmpty ? values : values + "   \u{00B7}   " + unsafe.joined(separator: ", ")
        plot.toolTip = type == .rgb
            ? "Bright: This Colour. Faint: Every Colour On The Page. The Shaded Ends Are Outside The Safe Range: Under 16 Crushes To Black, Over 235 Blows Out To White."
            : "Bright: This Colour. Faint: Every Colour On The Page. The Shaded Ends Are Outside The Safe Range: Under 3% The Dot Does Not Hold, Over 95% It Fills In To Solid."
    }
}

/// The second bar, shown while Histogram is on: the choices every swatch's histogram follows.
final class HistogramBar: NSView {
    var onChange: (() -> Void)?
    private lazy var types = ToggleBar(labels: HistogramType.allCases.map { $0.title }, target: self, action: #selector(changed))
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
        let label = caption("Histogram")
        label.textColor = .secondaryLabelColor
        let row = NSStackView(views: [label, types, layouts, about])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PageStyle.barSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            types.heightAnchor.constraint(equalToConstant: ButtonStyle.height),
            layouts.heightAnchor.constraint(equalToConstant: ButtonStyle.height),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let type = Prefs.histogramType
        types.selectedSegment = type.rawValue
        layouts.selectedSegment = Prefs.histogramSplit ? 1 : 0
        let scale = type == .rgb ? "0 To 255" : "0 To 100, For \(PrintCondition.current.press ?? PressProfiles.generic)"
        about.stringValue = "\(scale)  \u{00B7}  Safe \(type.safe.lowerBound) To \(type.safe.upperBound)  \u{00B7}  Bright: The Swatch. Faint: Every Colour On The Page."
    }

    @objc private func changed() {
        Prefs.histogramType = HistogramType(rawValue: types.selectedSegment) ?? .rgb
        Prefs.histogramSplit = layouts.selectedSegment == 1
        refresh()
        onChange?()
    }
}

extension Prefs {
    /// Histograms on every swatch of a palette's vertical view.
    static var histogramType: HistogramType {
        get { HistogramType(rawValue: preferences.integer(forKey: "histogramType")) ?? .rgb }
        set { preferences.set(newValue.rawValue, forKey: "histogramType") }
    }
    static var histogramSplit: Bool {
        get { preferences.bool(forKey: "histogramSplit") }
        set { preferences.set(newValue, forKey: "histogramSplit") }
    }
    /// Every swatch's channels, and every swatch's history, in a palette's vertical view.
    static var paletteChannels: Bool {
        get { preferences.bool(forKey: "paletteChannels") }
        set { preferences.set(newValue, forKey: "paletteChannels") }
    }
    static var paletteHistory: Bool {
        get { preferences.bool(forKey: "paletteHistory") }
        set { preferences.set(newValue, forKey: "paletteHistory") }
    }
    /// Notes are shown until switched off.
    static var paletteNotes: Bool {
        get { preferences.object(forKey: "paletteNotes") == nil ? true : preferences.bool(forKey: "paletteNotes") }
        set { preferences.set(newValue, forKey: "paletteNotes") }
    }
    static var histograms: Bool {
        get { preferences.bool(forKey: "paletteHistograms") }
        set { preferences.set(newValue, forKey: "paletteHistograms") }
    }
}
