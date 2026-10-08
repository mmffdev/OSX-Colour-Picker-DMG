import AppKit

// ---------- A colour's identity ----------
//
// Every colour in a library is handled by a KEY, a short piece of text. Two kinds of key:
//
//   "#RRGGBB"   a colour that IS a plain sRGB value. Its key is that value, as it always was, so
//               nothing about an existing library changes.
//   "c:<id>"    any other colour: a pick from a wide screen, a CMYK build typed for a press, a Lab
//               value. It has an id of its own and carries its source, its master and its kind.
//
// So two colours that look the same on an sRGB screen can both exist, and a colour sRGB cannot
// show can be kept whole. The field is still called `hex` in the code and in the files, for the
// sake of every library written so far; read it as "key".
//
// Code written before this, some 280 places, hands keys to functions that expect a hex: to draw a
// colour, to name it, to format it. Those functions ask here what a key that is not a hex means.
// Every colour record that is read from a file or made in the app registers itself, so the answer
// is there whichever library, history step or sync copy the key came from.

enum ColourKeys {
    static let prefix = "c:"
    private static var known: [String: ColourDefinition] = [:]
    private static let lock = NSLock()

    static func isKey(_ text: String) -> Bool { text.hasPrefix(prefix) }
    static func make() -> String { prefix + UUID().uuidString }

    static func register(_ key: String, _ definition: ColourDefinition) {
        lock.lock(); defer { lock.unlock() }
        known[key] = definition
    }

    /// The definition behind a key with an id of its own; nil for a hex, which defines itself.
    static func definition(of key: String) -> ColourDefinition? {
        guard isKey(key) else { return nil }
        lock.lock(); defer { lock.unlock() }
        return known[key]
    }

    /// The colour as sRGB can show it: what a card, a name or an export that only knows sRGB works from.
    static func displayHex(_ key: String) -> String? {
        definition(of: key).map { RGBSpace.srgb.text(RGBSpace.srgb.values(of: $0.master)) }
    }

    /// The colour in its own terms, short: its hex, or its source for one that is not a hex.
    static func label(_ key: String) -> String { definition(of: key)?.shortSource ?? key }
}

/// A key as the library stores it: a tidied hex, or a known key of the other kind. nil for anything else.
func colourKey(_ raw: String) -> String? {
    normaliseHex(raw) ?? (ColourKeys.definition(of: raw) != nil ? raw : nil)
}

/// The sRGB hex a colour is shown and exported as, where only sRGB will do.
func displayHex(_ key: String) -> String {
    normaliseHex(key) ?? ColourKeys.displayHex(key) ?? key
}

extension ColourDefinition {
    /// The source without its space spelled out at length: "P3 0.917, 0.200, 0.139", "C 0  M 90  Y 85  K 0", "Lab 52.1, 68.3, 47.9".
    var shortSource: String {
        let v = source.values
        switch source.space {
        case RGBSpace.srgb.rawValue: return RGBSpace.srgb.text(v)
        case RGBSpace.displayP3.rawValue: return "P3 " + RGBSpace.displayP3.text(v)
        case RGBSpace.prophoto.rawValue: return "ProPhoto " + RGBSpace.prophoto.text(v)
        case "cmyk": return PrintBuild(inks: v, printed: master).text
        case "lab": return "Lab " + v.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        default: return sourceText
        }
    }

    /// A colour given in Display P3, each value 0 to 1.
    static func displayP3(_ values: [Double]) -> ColourDefinition {
        ColourDefinition(source: ColourSource(space: RGBSpace.displayP3.rawValue, values: values), master: RGBSpace.displayP3.master(of: values), kind: .surface)
    }

    /// A colour given in ProPhoto RGB, each value 0 to 1.
    static func prophoto(_ values: [Double]) -> ColourDefinition {
        ColourDefinition(source: ColourSource(space: RGBSpace.prophoto.rawValue, values: values), master: RGBSpace.prophoto.master(of: values), kind: .surface)
    }

    /// A colour given as Lab (D50).
    static func lab(_ l: Double, _ a: Double, _ b: Double) -> ColourDefinition {
        ColourDefinition(source: ColourSource(space: "lab", values: [l, a, b]), master: LabD50(l: l, a: a, b: b).xyz, kind: .surface)
    }

    /// A build of the four inks, each 0 to 1, for a press. nil when the press profile is not on this Mac.
    static func cmyk(_ inks: [Double], press: String) -> ColourDefinition? {
        PrintBuild.master(ofInks: inks, press: press).map {
            ColourDefinition(source: ColourSource(space: "cmyk", values: inks, press: press), master: $0, kind: .surface)
        }
    }

    /// Whether sRGB can show the colour as it is.
    var fitsSRGB: Bool { master.fits(.srgb) }

    /// What a picked colour is kept as: a plain hex when sRGB holds it, as it always was; otherwise
    /// the Display P3 values the screen showed, so a vivid colour is not flattened by being picked.
    static func picked(_ colour: NSColor) -> ColourDefinition? {
        guard let wide = colour.usingColorSpace(.displayP3) else { return hexOf(colour).flatMap { ColourDefinition.of(hex: $0) } }
        // The exact Display P3 values the screen showed, always: the key may be a hex when sRGB holds the colour, but the
        // colour itself is kept whole, so nothing is flattened to eight bits by being picked.
        return ColourDefinition.displayP3([Double(wide.redComponent), Double(wide.greenComponent), Double(wide.blueComponent)])
    }
}

extension Library {
    /// The key of a colour with this definition, adding it if the library does not have it. A
    /// colour that is a plain sRGB value is kept under its hex; any other gets a key of its own.
    /// The same definition twice is the same colour.
    @discardableResult
    mutating func addColour(_ definition: ColourDefinition, at date: Date = Date()) -> String? {
        if definition.source.space == RGBSpace.srgb.rawValue, definition.source.values.count == 3, definition.source.values.allSatisfy({ $0 >= 0 && $0 <= 1 }) {
            return addToCatalogue(RGBSpace.srgb.text(definition.source.values), at: date)
        }
        // A screen pick sRGB can show keeps its hex as its key, as every library so far expects, and its exact source
        // and master on the record beside it, so what was captured is never only the eight-bit hex. A build typed for a
        // press or given as Lab is a colour in its own right whatever sRGB makes of it, and keeps a key of its own.
        if definition.source.space == RGBSpace.displayP3.rawValue, definition.fitsSRGB {
            let hex = RGBSpace.srgb.text(RGBSpace.srgb.values(of: definition.master))
            guard let key = addToCatalogue(hex, at: date) else { return nil }
            if let i = colours.firstIndex(where: { $0.hex == key }), colours[i].source == nil {
                colours[i].source = definition.source; colours[i].master = definition.master; colours[i].kind = definition.kind
            }
            return key
        }
        if let have = colours.first(where: { $0.source == definition.source }) { return have.hex }
        let key = ColourKeys.make()
        colours.append(Colour(hex: key, pickedAt: date, source: definition.source, master: definition.master, kind: definition.kind))
        return key
    }

    /// A fresh pick by its definition: into the catalogue, and into the active swatch if there is one.
    @discardableResult
    mutating func addPick(_ definition: ColourDefinition, at date: Date = Date()) -> String? {
        guard let key = addColour(definition, at: date) else { return nil }
        if let id = activeSwatchID {
            if swatch(id) != nil { add([key], toSwatch: id, at: date) } else { activeSwatchID = nil }
        }
        return key
    }
}

// ---------- The print condition in force ----------
//
// The CMYK a card shows and a copy gives is the build for a real press: the print channel of the
// profile the palette on screen uses, or the house default's, or the system's Generic CMYK when
// neither names one. The controller keeps `current` up to date as the page, the library and the
// Settings change. An export works out each palette's own condition instead.

enum PrintCondition {
    static let fallback = ProfileChannel(space: ProfileChannel.print, press: PressProfiles.generic, intent: .relative)
    static var current = fallback { didSet { if current != oldValue { lock.lock(); cache = [:]; lock.unlock() } } }

    private static var cache: [String: [Int]] = [:]
    private static let lock = NSLock()

    /// "Coated FOGRA39 (ISO 12647-2:2004), Relative Colorimetric".
    static func name(_ channel: ProfileChannel = current) -> String {
        (channel.press ?? PressProfiles.generic) + ", " + (channel.intent ?? .relative).name + (channel.blackPoint == true ? ", Black Point Compensation" : "")
    }

    /// The four ink percentages for a colour under a condition; nil when the press profile is not on this Mac.
    static func inks(of key: String, in channel: ProfileChannel = current) -> [Int]? {
        let isCurrent = channel == current
        if isCurrent { lock.lock(); let have = cache[key]; lock.unlock(); if let have = have { return have } }
        guard let definition = ColourKeys.definition(of: key) ?? ColourDefinition.of(hex: key) else { return nil }
        let press = channel.press ?? PressProfiles.generic
        let build: PrintBuild?
        // A colour typed as a build for this very press is given back as typed.
        if definition.source.space == "cmyk", definition.source.press == press, definition.source.values.count == 4 {
            build = PrintBuild(inks: definition.source.values, printed: definition.master)
        } else {
            build = PrintBuild.of(definition.master, press: press, intent: channel.intent ?? .relative, blackPoint: channel.blackPoint ?? false)
        }
        guard let inks = build?.inks.map({ Int(($0 * 100).rounded()) }) else { return nil }
        if isCurrent { lock.lock(); cache[key] = inks; lock.unlock() }
        return inks
    }
}

extension ColourProfile {
    /// The condition CMYK values are worked out for under this profile.
    var printCondition: ProfileChannel { print ?? PrintCondition.fallback }
}

extension Library {
    /// The key a colour would have if added to a copy of this library; for checks.
    func addingColour(_ definition: ColourDefinition) -> String {
        var copy = self
        return copy.addColour(definition) ?? ""
    }
}

extension Library {
    /// Fills in the record of every colour known only by its hex: its sRGB source and the linear XYZ master made from it,
    /// so no colour in a catalogue is only eight bits. A record that already has a source is left as it is.
    mutating func completeColourRecords() {
        for i in colours.indices where colours[i].source == nil {
            guard let def = ColourDefinition.of(hex: colours[i].hex) else { continue }
            colours[i].source = def.source; colours[i].master = def.master; colours[i].kind = def.kind
        }
    }
    /// The colour to draw for a key: from its master, through Display P3, so a colour is shown as it was captured and
    /// not as its eight-bit hex; the hex itself for a colour with no record here.
    func displayTable() -> [String: NSColor] {
        var out: [String: NSColor] = [:]
        for c in colours {
            guard let m = c.master else { continue }
            let v = RGBSpace.displayP3.values(of: m).map { min(max($0, 0), 1) }
            guard v.count == 3 else { continue }
            out[c.hex] = NSColor(displayP3Red: CGFloat(v[0]), green: CGFloat(v[1]), blue: CGFloat(v[2]), alpha: 1)
        }
        return out
    }
}
