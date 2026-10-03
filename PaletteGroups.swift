import AppKit

// ---------- Grouping and filtering a palette's colours ----------
//
// The bar under a palette's spectrum splits the page into titled groups and narrows what it
// shows. Both are ways of LOOKING at the palette: nothing about the palette changes, and the
// order inside a group is the order the page already had. The choice is the user's for every
// palette, like the grid and vertical views.

enum PaletteGrouping: String, CaseIterable {
    case none, source, hue, lightness, range, tag

    var title: String {
        switch self {
        case .none: return "None"
        case .source: return "Captured As"
        case .hue: return "Hue"
        case .lightness: return "Lightness"
        case .range: return "Range"
        case .tag: return "Tag"
        }
    }
}

enum PaletteFilter: String, CaseIterable {
    case all, withinSRGB, beyondSRGB, outOfRange

    var title: String {
        switch self {
        case .all: return "All"
        case .withinSRGB: return "Within sRGB"
        case .beyondSRGB: return "Beyond sRGB"
        case .outOfRange: return "Out Of Range"
        }
    }
}

/// How New Colour opens: on which kind of colour, and for a build, which press.
struct NewColourStart: Equatable {
    var kind: Int
    var press: String? = nil
}

struct PaletteGroup: Equatable {
    let title: String
    let keys: [String]
    /// For a group of colours captured one way: how a new colour of that kind is started. A group
    /// like this has a blank swatch of its own. nil for groups a colour cannot simply be added to.
    var start: NewColourStart? = nil
}

/// One place on a palette's page: a colour, or a blank swatch that adds one.
enum PaletteSlot: Equatable {
    case colour(String)
    case add(NewColourStart?)

    var key: String? { if case .colour(let key) = self { return key } else { return nil } }

    /// The page in order, group by group. Grouped by how colours were captured, every group ends
    /// with a blank swatch of its own kind; otherwise one blank swatch ends the page.
    static func page(_ keys: [String], groups: [PaletteGroup], offersNew: Bool) -> (slots: [PaletteSlot], counts: [Int]) {
        guard !groups.isEmpty else { return (keys.map { .colour($0) } + (offersNew ? [.add(nil)] : []), []) }
        let own = offersNew && groups.contains { $0.start != nil }
        var slots: [PaletteSlot] = [], counts: [Int] = []
        for (i, group) in groups.enumerated() {
            var run = group.keys.map { PaletteSlot.colour($0) }
            if own, let start = group.start { run.append(.add(start)) }
            if offersNew, !own, i == groups.count - 1 { run.append(.add(nil)) }
            slots += run
            counts.append(run.count)
        }
        return (slots, counts)
    }
}

extension Prefs {
    static var paletteGrouping: PaletteGrouping {
        get { preferences.string(forKey: "paletteGrouping").flatMap(PaletteGrouping.init(rawValue:)) ?? .none }
        set { preferences.set(newValue.rawValue, forKey: "paletteGrouping") }
    }
    static var paletteFilter: PaletteFilter {
        get { preferences.string(forKey: "paletteFilter").flatMap(PaletteFilter.init(rawValue:)) ?? .all }
        set { preferences.set(newValue.rawValue, forKey: "paletteFilter") }
    }
}

extension Library {
    /// Whether every channel of the profile can hold the colour as it is.
    func inRange(_ key: String, for profile: ColourProfile) -> Bool {
        guard let colour = definition(of: key) else { return true }
        return profile.channels.allSatisfy { Rendering.of(colour, in: $0).inRange }
    }

    /// The colours a filter lets through, in the order given.
    func shown(_ keys: [String], filter: PaletteFilter, profile: ColourProfile) -> [String] {
        switch filter {
        case .all: return keys
        case .withinSRGB: return keys.filter { definition(of: $0)?.fitsSRGB ?? true }
        case .beyondSRGB: return keys.filter { !(definition(of: $0)?.fitsSRGB ?? true) }
        case .outOfRange: return keys.filter { !inRange($0, for: profile) }
        }
    }

    /// The colours split into titled groups. Groups come in a fixed, sensible order; a group with
    /// no colours is left out; inside a group the colours keep the order they were given in.
    /// Grouping by nothing gives no groups at all: the page is then one run, as it always was.
    func groups(of keys: [String], by grouping: PaletteGrouping, profile: ColourProfile) -> [PaletteGroup] {
        guard grouping != .none, !keys.isEmpty else { return [] }
        var order: [String] = []
        var held: [String: [String]] = [:]
        func put(_ key: String, in title: String) {
            if held[title] == nil { order.append(title) }
            held[title, default: []].append(key)
        }
        // The order groups are shown in, where it is not simply the order they turn up.
        var ranked: [String] = []
        switch grouping {
        case .none: break
        case .source:
            ranked = ["Hex (sRGB)", "Display P3"]
            for key in keys {
                let source = definition(of: key)?.source
                switch source?.space {
                case RGBSpace.displayP3.rawValue: put(key, in: "Display P3")
                case "cmyk": put(key, in: "CMYK: " + (source?.press ?? PressProfiles.generic))
                case "lab": put(key, in: "Lab")
                case RGBSpace.srgb.rawValue, nil: put(key, in: "Hex (sRGB)")
                default: put(key, in: source.flatMap { RGBSpace(rawValue: $0.space)?.name } ?? "Other")
                }
            }
            ranked += order.filter { $0.hasPrefix("CMYK") }.sorted() + ["Lab"]
        case .hue:
            ranked = ["Reds", "Oranges", "Yellows", "Greens", "Cyans", "Blues", "Purples", "Pinks", "Neutrals"]
            for key in keys {
                guard let v = ColourValues(key)?.hslUnit else { put(key, in: "Neutrals"); continue }
                // Too grey, too dark or too pale to have a hue worth sorting by.
                if v.s < 0.12 || v.l < 0.06 || v.l > 0.96 { put(key, in: "Neutrals"); continue }
                switch v.h {
                case ..<15, 345...: put(key, in: "Reds")
                case ..<45: put(key, in: "Oranges")
                case ..<70: put(key, in: "Yellows")
                case ..<165: put(key, in: "Greens")
                case ..<200: put(key, in: "Cyans")
                case ..<260: put(key, in: "Blues")
                case ..<300: put(key, in: "Purples")
                default: put(key, in: "Pinks")
                }
            }
        case .lightness:
            ranked = ["Light", "Mid", "Dark"]
            for key in keys {
                let l = definition(of: key)?.master.lab.l ?? 50
                put(key, in: l >= 67 ? "Light" : l >= 34 ? "Mid" : "Dark")
            }
        case .range:
            ranked = ["In Range In Every Channel", "Out Of Range In At Least One Channel"]
            for key in keys { put(key, in: inRange(key, for: profile) ? ranked[0] : ranked[1]) }
        case .tag:
            for key in keys {
                let tags = (colours.first { $0.hex == key }?.tags ?? []).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                put(key, in: tags.first.map { "#" + $0 } ?? "Untagged")
            }
            ranked = order.filter { $0 != "Untagged" }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } + ["Untagged"]
        }
        let titles = ranked.filter { held[$0] != nil } + order.filter { !ranked.contains($0) }
        return titles.map { title in
            var start: NewColourStart?
            if grouping == .source {
                if title == "Hex (sRGB)" { start = NewColourStart(kind: NewColourSheet.Kind.hex.rawValue) }
                else if title == "Display P3" { start = NewColourStart(kind: NewColourSheet.Kind.p3.rawValue) }
                else if title == "Lab" { start = NewColourStart(kind: NewColourSheet.Kind.lab.rawValue) }
                else if title.hasPrefix("CMYK: ") { start = NewColourStart(kind: NewColourSheet.Kind.cmyk.rawValue, press: String(title.dropFirst(6))) }
            }
            return PaletteGroup(title: title, keys: held[title] ?? [], start: start)
        }
    }
}

// ---------- The bar ----------

/// The bar under the spectrum: how the page is grouped, and what it shows.
final class PaletteViewBar: NSView {
    var onChange: (() -> Void)?
    private lazy var grouping = ToggleBar(labels: PaletteGrouping.allCases.map { $0.title }, target: self, action: #selector(groupingChanged))
    // What every swatch shows beside its values, in the vertical view.
    private lazy var channels = toolButton("Channels", "dial.medium", "Show Every Swatch's Value And Fidelity In Each Channel Of The Palette's Profile", target: self, action: #selector(panelTapped(_:)))
    private lazy var history = toolButton("History", "clock.arrow.circlepath", "Show What Happened To Every Swatch In This Palette", target: self, action: #selector(panelTapped(_:)))
    private lazy var histogram = toolButton("Histogram", "chart.bar.xaxis", "Show Every Swatch's Histogram", target: self, action: #selector(panelTapped(_:)))
    private lazy var filter = ToggleBar(labels: PaletteFilter.allCases.map { $0.title }, target: self, action: #selector(filterChanged))

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        grouping.toolTip = "Split The Page Into Groups. Captured As: By How Each Colour Was Given. Range: By Whether Every Channel Of The Profile Can Hold It."
        filter.toolTip = "Show Only Some Colours. Out Of Range: Those A Channel Of The Profile Cannot Hold."
        let groupLabel = caption("Group By"), showLabel = caption("Show")
        for l in [groupLabel, showLabel] { l.textColor = .secondaryLabelColor }
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        // Left: what every swatch shows. Right: how the page is grouped, then what it shows.
        let row = NSStackView(views: [channels, history, histogram, spacer, groupLabel, grouping, showLabel, filter])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PageStyle.barSpacing
        row.setCustomSpacing(16, after: grouping)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PageStyle.barHeight),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            grouping.heightAnchor.constraint(equalToConstant: ButtonStyle.height),
            filter.heightAnchor.constraint(equalToConstant: ButtonStyle.height),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        grouping.selectedSegment = PaletteGrouping.allCases.firstIndex(of: Prefs.paletteGrouping) ?? 0
        filter.selectedSegment = PaletteFilter.allCases.firstIndex(of: Prefs.paletteFilter) ?? 0
        for (button, on) in [(channels, Prefs.paletteChannels), (history, Prefs.paletteHistory), (histogram, Prefs.histograms)] {
            button.state = on ? .on : .off
            button.needsDisplay = true
        }
    }

    @objc private func panelTapped(_ sender: NSButton) {
        if sender === channels { Prefs.paletteChannels.toggle() }
        else if sender === history { Prefs.paletteHistory.toggle() }
        else { Prefs.histograms.toggle() }
        // These sit beside each swatch's values, which only the vertical view has.
        if Prefs.paletteChannels || Prefs.paletteHistory || Prefs.histograms { Prefs.paletteListView = true }
        onChange?()
    }

    @objc private func groupingChanged() {
        Prefs.paletteGrouping = PaletteGrouping.allCases[min(max(grouping.selectedSegment, 0), PaletteGrouping.allCases.count - 1)]
        onChange?()
    }
    @objc private func filterChanged() {
        Prefs.paletteFilter = PaletteFilter.allCases[min(max(filter.selectedSegment, 0), PaletteFilter.allCases.count - 1)]
        onChange?()
    }
}

/// A group's title over its colours, in the grid.
final class GroupHeaderView: NSView, NSCollectionViewElement {
    static let kind = "groupHeader"
    static let identifier = NSUserInterfaceItemIdentifier("groupHeader")
    static let height: CGFloat = 30
    let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// "CMYK: Generic CMYK  ·  3"
    static func text(_ group: PaletteGroup) -> String { "\(group.title)  \u{00B7}  \(group.keys.count)" }
}
