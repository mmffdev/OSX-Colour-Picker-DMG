import Foundation

// ---------- Preferences (per Mac) ----------

extension Notification.Name {
    /// Posted when a preference that changes how colours are shown or copied is edited.
    static let prefsDidChange = Notification.Name("prefsDidChange")
}

enum TileSize: Int, CaseIterable {
    case small, medium, large
    var title: String { ["Small", "Medium", "Large"][rawValue] }
    var points: Double { [84, 108, 140][rawValue] }
}

enum Arrange: Int, CaseIterable {
    case palette, group, hue, lightness, saturation, newest, oldest, name

    var title: String {
        switch self {
        case .palette: return "Palette"
        case .group: return "Colour Group"
        case .hue: return "Hue"
        case .lightness: return "Lightness"
        case .saturation: return "Saturation"
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .name: return "Name"
        }
    }
}

enum Prefs {
    private static let d = preferences

    private static func changed() { NotificationCenter.default.post(name: .prefsDidChange, object: nil) }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
    private static func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: key) as? Int ?? fallback }

    /// What a click on a swatch puts on the clipboard.
    static var copyFormat: ColourFormat {
        get { ColourFormat(rawValue: d.string(forKey: "copyFormat") ?? "") ?? .hex }
        set { d.set(newValue.rawValue, forKey: "copyFormat"); changed() }
    }

    static var lowercaseHex: Bool {
        get { bool("lowercaseHex", false) }
        set { d.set(newValue, forKey: "lowercaseHex"); changed() }
    }

    // MARK: Theme

    /// The sidebar's selected row: background and text as "#RRGGBB"; nil is the system's own.
    static var sidebarSelectionBackground: String? {
        get { d.string(forKey: "theme.sidebar.selectionBackground") }
        set { d.set(newValue, forKey: "theme.sidebar.selectionBackground"); changed() }
    }
    static var sidebarSelectionText: String? {
        get { d.string(forKey: "theme.sidebar.selectionText") }
        set { d.set(newValue, forKey: "theme.sidebar.selectionText"); changed() }
    }

    /// The main buttons and toggles under the pointer and when pressed or on, as "#RRGGBB"; nil is the theme's grey.
    private static func colour(_ key: String) -> String? { d.string(forKey: key) }
    private static func setColour(_ value: String?, _ key: String) { d.set(value, forKey: key); changed() }
    static var buttonHoverBackground: String? { get { colour("theme.button.hoverBackground") } set { setColour(newValue, "theme.button.hoverBackground") } }
    static var buttonHoverText: String? { get { colour("theme.button.hoverText") } set { setColour(newValue, "theme.button.hoverText") } }
    static var buttonActiveBackground: String? { get { colour("theme.button.activeBackground") } set { setColour(newValue, "theme.button.activeBackground") } }
    static var buttonActiveText: String? { get { colour("theme.button.activeText") } set { setColour(newValue, "theme.button.activeText") } }

    /// One of the halo's colours as "#RRGGBB"; nil is the theme's own. `part` is "centre.background",
    /// "centre.text", or for ring 1, 2 or 3: "ring1.background", "ring1.text", "ring1.cursorBackground", "ring1.cursorText".
    static func haloColour(_ part: String) -> String? { colour("theme.halo." + part) }
    /// How readily the mouse wheel turns a halo's ring: 1 is the standard, less is slower, more is faster.
    static let haloWheelSpeedRange = 0.4...2.0
    static var haloWheelSpeed: Double {
        get { (d.object(forKey: "halo.wheelSpeed") as? Double).map { min(max($0, haloWheelSpeedRange.lowerBound), haloWheelSpeedRange.upperBound) } ?? 1 }
        set { d.set(newValue, forKey: "halo.wheelSpeed"); changed() }
    }
    static func setHaloColour(_ value: String?, _ part: String) { setColour(value, "theme.halo." + part) }

    // MARK: Organisation

    /// The organisation using the app, as the project form's Studio fields: field key to value.
    /// A new project's Studio section starts as this.
    static var organisation: [String: String] {
        get { d.dictionary(forKey: "organisation") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "organisation") }
    }

    // MARK: History

    /// History is kept per library (catalogue): on unless turned off for that one.
    static func historyEnabled(for catalogue: String) -> Bool { bool("history.\(catalogue)", true) }
    static func setHistoryEnabled(_ on: Bool, for catalogue: String) { d.set(on, forKey: "history.\(catalogue)") }
    /// How palettes are laid out: cards in a grid, or one colour to a row with its notes. One
    /// choice for every palette, so it holds as the user goes from one palette to the next.
    static var paletteListView: Bool {
        get { bool("paletteListView", false) }
        set { d.set(newValue, forKey: "paletteListView") }
    }
    static var historyRailShown: Bool {
        get { bool("historyRail", false) }
        set { d.set(newValue, forKey: "historyRail") }
    }
    /// Steps kept; 0 is unlimited.
    static var historySteps: Int {
        get { int("historySteps", 50) }
        set { d.set(newValue, forKey: "historySteps") }
    }
    /// Steps that touch one project are also written into that project's file.
    static var projectHistory: Bool {
        get { bool("projectHistory", true) }
        set { d.set(newValue, forKey: "projectHistory") }
    }

    /// The first-open setup has been shown and dismissed.
    static var setupDone: Bool {
        get { bool("setupDone", false) }
        set { d.set(newValue, forKey: "setupDone") }
    }

    static var sounds: Bool {
        get { bool("sounds", true) }
        set { d.set(newValue, forKey: "sounds") }
    }

    /// Keep the loupe up after each pick until Esc.
    static var keepPicking: Bool {
        get { bool("keepPicking", true) }
        set { d.set(newValue, forKey: "keepPicking") }
    }

    static var imagePaletteSize: Int {
        get { int("imagePaletteSize", 8) }
        set { d.set(newValue, forKey: "imagePaletteSize") }
    }

    static var showNames: Bool {
        get { bool("showNames", true) }
        set { d.set(newValue, forKey: "showNames"); changed() }
    }

    static var showContrast: Bool {
        get { bool("showContrast", true) }
        set { d.set(newValue, forKey: "showContrast"); changed() }
    }

    static var showPaletteBars: Bool {
        get { bool("showPaletteBars", true) }
        set { d.set(newValue, forKey: "showPaletteBars"); changed() }
    }

    /// Scrolling past the end of a palette moves to the next one. Off until chosen: it moves the selection in rail1 and refills rail2, which reads as the rails scrolling by themselves.
    static var wheelChangesPalette: Bool {
        get { bool("wheelChangesPalette", false) }
        set { d.set(newValue, forKey: "wheelChangesPalette") }
    }

    static var tileSize: TileSize {
        get { TileSize(rawValue: int("tileSize", 1)) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "tileSize"); changed() }
    }

    static var arrange: Arrange {
        get { Arrange(rawValue: int("arrange", 0)) ?? .palette }
        set { d.set(newValue.rawValue, forKey: "arrange") }
    }

    /// What is written under each tile in All Swatches, in order: "name" and ColourFormat raw values.
    static var tileLabels: [String] {
        get { d.stringArray(forKey: "tileLabels") ?? (showNames ? ["name", "hex"] : ["hex"]) }
        set { d.set(newValue, forKey: "tileLabels"); changed() }
    }

    /// Which rows a colour card shows.
    static var houseCardRows: [ColourFormat] {
        get {
            guard let saved = d.stringArray(forKey: "cardRows") else { return ColourFormat.defaultCardRows }
            return ColourFormat.cardRows.filter { saved.contains($0.rawValue) }
        }
        set { d.set(newValue.map { $0.rawValue }, forKey: "cardRows"); changed() }
    }

    /// The purpose a new palette is turned to, and the one a palette with none is shown as.
    static var defaultPurpose: Purpose {
        get { d.string(forKey: "defaultPurpose").flatMap(Purpose.init(rawValue:)) ?? .web }
        set { d.set(newValue.rawValue, forKey: "defaultPurpose"); changed() }
    }

    /// The rows the palette page is showing for the purpose on show; nil while no purpose is,
    /// when the cards show the rows chosen in Settings. Set by the palette page, kept nowhere.
    static var purposeCardRows: [ColourFormat]?

    /// Which rows a colour card shows now: the purpose's on a purpose's tab, else those chosen in Settings.
    static var cardRows: [ColourFormat] {
        get { purposeCardRows ?? houseCardRows }
        set { houseCardRows = newValue }
    }

    static var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: d.string(forKey: "exportFormat") ?? "") ?? .css }
        set { d.set(newValue.rawValue, forKey: "exportFormat") }
    }

    static var exportOptions: ExportOptions {
        get {
            var o = ExportOptions()
            let prefix = slug(d.string(forKey: "exportPrefix") ?? "swatch")
            o.prefix = prefix
            o.naming = ExportOptions.Naming(rawValue: int("exportNaming", 0)) ?? .names
            o.lowercaseHex = bool("exportLowercase", true)
            return o
        }
        set {
            d.set(newValue.prefix, forKey: "exportPrefix")
            d.set(newValue.naming.rawValue, forKey: "exportNaming")
            d.set(newValue.lowercaseHex, forKey: "exportLowercase")
        }
    }

    /// Who the design pack licence names.
    static var licenceOwner: String {
        get { d.string(forKey: "licenceOwner") ?? "" }
        set { d.set(newValue, forKey: "licenceOwner") }
    }

    /// The licence text, with {owner}, {year} and {pack} filled in at export.
    static var licenceText: String {
        get { d.string(forKey: "licenceText") ?? DesignPack.defaultLicence }
        set { d.set(newValue, forKey: "licenceText") }
    }

    /// Saved project templates, encoded; see ProjectTemplates.
    static var projectTemplates: Data? {
        get { d.data(forKey: "projectTemplates") }
        set { d.set(newValue, forKey: "projectTemplates") }
    }

    /// Shortcuts the user has changed, by command; an empty string is one taken off altogether.
    static var shortcuts: [String: String] {
        get { d.dictionary(forKey: "shortcuts") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "shortcuts") }
    }

    /// The text for a click on a swatch, in the chosen copy format.
    static func copyText(_ hex: String) -> String { copyFormat.text(hex, lowercase: lowercaseHex) }
}
