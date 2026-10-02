import Foundation

// ---------- Exporting palettes ----------
//
// Text and binary formats other tools read. Everything here is pure: colours in, bytes out.
// Two formats need AppKit (.clr colour lists and PNG sheets); those live with the UI code.

struct ExportColour: Equatable {
    let name: String
    let hex: String
}

struct ExportPalette {
    let name: String
    let colours: [ExportColour]
}

struct ExportOptions {
    enum Naming: Int { case names, numbers }
    /// "swatch" gives --swatch-steel-blue.
    var prefix = "swatch"
    var naming = Naming.names
    var lowercaseHex = true
}

enum ExportFormat: String, CaseIterable {
    case css, scss, tailwind4, tailwind3, tokens, tokensLegacy, swift, android, ase, aco, acb, act, afterEffects, procreate, sketch, clr, gpl,
         paintNet, jasc, hexFile, png, text

    var title: String {
        switch self {
        case .css: return "CSS variables (tokens.css)"
        case .scss: return "SCSS variables"
        case .tailwind4: return "Tailwind v4 @theme"
        case .tailwind3: return "Tailwind v3 config"
        case .tokens: return "Design tokens JSON \u{2014} W3C 2025.10, Figma"
        case .tokensLegacy: return "Design tokens JSON \u{2014} older tools (hex values)"
        case .swift: return "Swift \u{2014} SwiftUI colours"
        case .android: return "Android colors.xml"
        case .ase: return "Adobe Swatch Exchange \u{2014} Photoshop, Illustrator, InDesign, Affinity"
        case .aco: return "Adobe Color swatches \u{2014} Photoshop, Clip Studio"
        case .acb: return "Adobe Color Book \u{2014} Photoshop colour libraries"
        case .act: return "Adobe Color Table \u{2014} Photoshop, Illustrator Save for Web"
        case .afterEffects: return "After Effects script \u{2014} palette comp with colour controls"
        case .procreate: return "Procreate swatches \u{2014} iPad"
        case .sketch: return "Sketch palette \u{2014} Sketch Palettes plugin"
        case .clr: return "macOS colour list \u{2014} every Mac colour panel"
        case .gpl: return "GIMP palette \u{2014} also Inkscape, Krita"
        case .paintNet: return "Paint.NET palette"
        case .jasc: return "JASC palette \u{2014} PaintShop Pro, pixel art tools"
        case .hexFile: return "Hex file \u{2014} Aseprite, Lospec"
        case .png: return "PNG swatch sheet"
        case .text: return "Plain text hex list"
        }
    }

    var fileExtension: String {
        switch self {
        case .css, .tailwind4: return "css"
        case .scss: return "scss"
        case .tailwind3: return "js"
        case .tokens, .tokensLegacy: return "json"
        case .swift: return "swift"
        case .android: return "xml"
        case .gpl: return "gpl"
        case .ase: return "ase"
        case .aco: return "aco"
        case .acb: return "acb"
        case .act: return "act"
        case .afterEffects: return "jsx"
        case .procreate: return "swatches"
        case .sketch: return "sketchpalette"
        case .clr: return "clr"
        case .paintNet: return "txt"
        case .jasc: return "pal"
        case .hexFile: return "hex"
        case .png: return "png"
        case .text: return "txt"
        }
    }

    /// A sensible file name for one palette, or for the whole library.
    func fileName(for palettes: [ExportPalette]) -> String {
        let base = palettes.count == 1 ? slug(palettes[0].name) : "palettes"
        switch self {
        case .css: return palettes.count == 1 ? "\(base)-tokens.css" : "tokens.css"
        case .tailwind4: return "\(base)-theme.css"
        case .tailwind3: return "\(base).tailwind.js"
        case .tokens, .tokensLegacy: return "\(base).tokens.json"
        case .android: return "colors.xml"
        case .paintNet: return "\(base)-paint-net.txt"
        case .afterEffects: return "\(base)-after-effects.jsx"
        case .swift: return "\(base.split(separator: "-").map { $0.capitalized }.joined())Colours.swift"
        default: return "\(base).\(fileExtension)"
        }
    }

    /// The file's contents. nil for the formats drawn with AppKit.
    func data(_ palettes: [ExportPalette], options: ExportOptions = ExportOptions()) -> Data? {
        switch self {
        case .clr, .png: return nil
        case .ase: return aseData(palettes)
        case .aco: return acoData(palettes)
        case .acb: return acbData(palettes)
        case .act: return actData(palettes)
        case .procreate: return procreateData(palettes)
        default: return render(palettes, options).data(using: .utf8)
        }
    }

    // MARK: Text formats

    private func render(_ palettes: [ExportPalette], _ o: ExportOptions) -> String {
        let named = palettes.map { ($0, tokenNames(for: $0, among: palettes, o)) }
        func hex(_ c: ExportColour) -> String { o.lowercaseHex ? c.hex.lowercased() : c.hex.uppercased() }
        let banner = "Exported from MMFFDev Colour 3"
        var out: [String] = []

        switch self {
        case .css, .tailwind4:
            let prefix = self == .css ? o.prefix : "color"
            out.append("/* \(banner) */")
            out.append(self == .css ? ":root {" : "@theme {")
            for (i, (p, names)) in named.enumerated() {
                if i > 0 { out.append("") }
                out.append("  /* \(p.name) */")
                for (c, n) in zip(p.colours, names) { out.append("  --\(prefix)-\(n): \(hex(c));") }
            }
            out.append("}")

        case .scss:
            out.append("// \(banner)")
            for (p, names) in named {
                out.append("")
                out.append("// \(p.name)")
                for (c, n) in zip(p.colours, names) { out.append("$\(o.prefix)-\(n): \(hex(c));") }
            }

        case .tailwind3:
            out.append("// \(banner)")
            out.append("module.exports = {")
            out.append("  theme: {")
            out.append("    extend: {")
            out.append("      colors: {")
            for p in palettes {
                out.append("        '\(slug(p.name))': {")
                for (c, n) in zip(p.colours, localNames(p, o)) { out.append("          '\(n)': '\(hex(c))',") }
                out.append("        },")
            }
            out.append("      },")
            out.append("    },")
            out.append("  },")
            out.append("}")

        case .tokens, .tokensLegacy:
            // W3C Design Tokens format: a group per palette, a colour token per swatch.
            // Since the 2025.10 version a colour's value is an object; older tools expect the hex string.
            var groups: [String] = []
            for p in palettes {
                let tokens = zip(p.colours, localNames(p, o)).compactMap { c, n -> String? in
                    guard let u = ColourValues(c.hex)?.unit else { return nil }
                    func n4(_ v: Double) -> String { String(format: "%g", (v * 10000).rounded() / 10000) }
                    let value = self == .tokensLegacy ? json(hex(c))
                        : "{ \"colorSpace\": \"srgb\", \"components\": [\(n4(u.r)), \(n4(u.g)), \(n4(u.b))], \"alpha\": 1, \"hex\": \(json(c.hex.lowercased())) }"
                    return "    \(json(n)): { \"$type\": \"color\", \"$value\": \(value), \"$description\": \(json(c.name)) }"
                }
                groups.append("  \(json(slug(p.name))): {\n" + tokens.joined(separator: ",\n") + "\n  }")
            }
            out.append("{\n" + groups.joined(separator: ",\n") + "\n}")

        case .swift:
            out.append("// \(banner)")
            out.append("import SwiftUI")
            for p in palettes {
                out.append("")
                out.append("/// \(p.name)")
                out.append("enum \(typeName(p.name)) {")
                for (c, n) in zip(p.colours, localNames(p, o)) {
                    guard let v = ColourValues(c.hex) else { continue }
                    let u = v.unit
                    out.append(String(format: "    static let %@ = Color(red: %.3f, green: %.3f, blue: %.3f) // %@",
                                      camel(n), u.r, u.g, u.b, hex(c)))
                }
                out.append("}")
            }

        case .android:
            out.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
            out.append("<!-- \(banner) -->")
            out.append("<resources>")
            for (p, names) in named {
                out.append("    <!-- \(xml(p.name)) -->")
                for (c, n) in zip(p.colours, names) {
                    out.append("    <color name=\"\(o.prefix)_\(n.replacingOccurrences(of: "-", with: "_"))\">\(hex(c))</color>")
                }
            }
            out.append("</resources>")

        case .gpl:
            out.append("GIMP Palette")
            out.append("Name: \(palettes.map { $0.name }.joined(separator: ", "))")
            out.append("Columns: 0")
            out.append("# \(banner)")
            for p in palettes {
                for c in p.colours {
                    guard let v = ColourValues(c.hex) else { continue }
                    out.append(String(format: "%3d %3d %3d\t%@", v.r, v.g, v.b, c.name))
                }
            }

        case .afterEffects:
            // After Effects has no swatch file, so this is a script: run it and each palette becomes a comp
            // of colour tiles to pick from, with a "Colours" layer of named colour controls to link to.
            out.append("// \(banner)")
            out.append("// After Effects: File \u{25B8} Scripts \u{25B8} Run Script File\u{2026}")
            out.append("(function () {")
            out.append("    var palettes = [")
            for p in palettes {
                var taken: [String] = []
                let colours = p.colours.compactMap { c -> String? in
                    guard let u = ColourValues(c.hex)?.unit else { return nil }
                    let name = uniqueName(c.name, among: taken); taken.append(name)
                    return String(format: "            [%@, %.4f, %.4f, %.4f]", json(name), u.r, u.g, u.b)
                }
                out.append("        { name: \(json(p.name)), colours: [")
                out.append(colours.joined(separator: ",\n"))
                out.append("        ] },")
            }
            out.append("""
                    ];
                    var tile = 240;
                    app.beginUndoGroup("Import Palettes");
                    for (var p = 0; p < palettes.length; p++) {
                        var palette = palettes[p], count = palette.colours.length;
                        if (count === 0) continue;
                        var perRow = Math.min(count, 8), rows = Math.ceil(count / perRow);
                        var comp = app.project.items.addComp(palette.name, perRow * tile, rows * tile, 1, 10, 25);
                        var controls = comp.layers.addNull();
                        controls.name = "Colours";
                        for (var i = 0; i < count; i++) {
                            var c = palette.colours[i];
                            var solid = comp.layers.addSolid([c[1], c[2], c[3]], c[0], tile, tile, 1);
                            solid.property("ADBE Transform Group").property("ADBE Position")
                                .setValue([(i % perRow + 0.5) * tile, (Math.floor(i / perRow) + 0.5) * tile]);
                            var control = controls.property("ADBE Effect Parade").addProperty("ADBE Color Control");
                            control.name = c[0];
                            control.property("ADBE Color Control-0001").setValue([c[1], c[2], c[3], 1]);
                        }
                        controls.moveToBeginning();
                        comp.openInViewer();
                    }
                    app.endUndoGroup();
                })();
                """)

        case .sketch:
            // The Sketch Palettes plugin's file: document colours as 0–1 components.
            let colours = palettes.flatMap { $0.colours }.compactMap { c -> String? in
                guard let u = ColourValues(c.hex)?.unit else { return nil }
                return String(format: "    { \"name\": %@, \"red\": %.6f, \"green\": %.6f, \"blue\": %.6f, \"alpha\": 1 }",
                              json(c.name), u.r, u.g, u.b)
            }
            out.append("{\n  \"compatibleVersion\": \"2.0\",\n  \"pluginVersion\": \"2.22\",\n  \"colors\": [")
            out.append(colours.joined(separator: ",\n"))
            out.append("  ],\n  \"gradients\": [],\n  \"images\": []\n}")

        case .paintNet:
            // One AARRGGBB per line. Paint.NET's palette holds 96 colours and ignores the rest.
            out.append("; \(banner)")
            out.append("; \(palettes.map { $0.name }.joined(separator: ", "))")
            for c in palettes.flatMap({ $0.colours }).prefix(96) {
                guard let v = ColourValues(c.hex) else { continue }
                out.append("FF" + v.hex.dropFirst())
            }

        case .jasc:
            // Windows line endings, as PaintShop Pro writes them.
            let values = palettes.flatMap { $0.colours }.compactMap { ColourValues($0.hex) }
            return (["JASC-PAL", "0100", "\(values.count)"] + values.map { "\($0.r) \($0.g) \($0.b)" }).joined(separator: "\r\n") + "\r\n"

        case .hexFile:
            for c in palettes.flatMap({ $0.colours }) {
                guard let v = ColourValues(c.hex) else { continue }
                out.append(v.hex.dropFirst().lowercased())
            }

        case .text:
            for p in palettes {
                if palettes.count > 1 { out.append("\(p.name): " + p.colours.map(hex).joined(separator: ", ")) }
                else { out.append(p.colours.map(hex).joined(separator: ", ")) }
            }

        case .ase, .aco, .acb, .act, .procreate, .clr, .png:
            break
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Names

    /// Names unique within one palette: "steel-blue", "steel-blue-2", or "1", "2" …
    private func localNames(_ p: ExportPalette, _ o: ExportOptions) -> [String] {
        var taken: [String] = []
        return p.colours.enumerated().map { i, c in
            if o.naming == .numbers { return "\(i + 1)" }
            var name = slug(c.name), n = 2
            while taken.contains(name) { name = "\(slug(c.name))-\(n)"; n += 1 }
            taken.append(name)
            return name
        }
    }

    /// As `localNames`, with the palette in front when several palettes share one file.
    private func tokenNames(for p: ExportPalette, among all: [ExportPalette], _ o: ExportOptions) -> [String] {
        let names = localNames(p, o)
        return all.count > 1 ? names.map { "\(slug(p.name))-\($0)" } : names
    }

    private func camel(_ s: String) -> String {
        let parts = s.split(separator: "-").map(String.init)
        let joined = (parts.first ?? "colour") + parts.dropFirst().map { $0.capitalized }.joined()
        return joined.first?.isNumber == true ? "c" + joined : joined
    }

    private func typeName(_ s: String) -> String {
        let t = slug(s).split(separator: "-").map { $0.capitalized }.joined()
        return (t.first?.isNumber == true ? "P" + t : t) + "Colours"
    }

    private func json(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func xml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "--", with: "\u{2013}")
    }

    // MARK: Adobe Swatch Exchange

    /// Big-endian throughout. "ASEF", version 1.0, a block count, then blocks:
    /// group start (0xC001), colour entries (0x0001), group end (0xC002).
    private func aseData(_ palettes: [ExportPalette]) -> Data {
        var d = Data("ASEF".utf8)
        func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).bigEndian) { Data($0) } }
        func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).bigEndian) { Data($0) } }
        func f32(_ v: Double) -> Data { withUnsafeBytes(of: Float(v).bitPattern.bigEndian) { Data($0) } }
        /// Length in UTF-16 units including the terminating zero, then the units.
        func text(_ s: String) -> Data {
            let units = Array(s.utf16) + [0]
            return u16(units.count) + units.reduce(Data()) { $0 + u16(Int($1)) }
        }
        func block(_ type: Int, _ body: Data) -> Data { u16(type) + u32(body.count) + body }

        let valid = palettes.map { p in (p.name, p.colours.filter { ColourValues($0.hex) != nil }) }
        d += u16(1) + u16(0)
        d += u32(valid.reduce(0) { $0 + $1.1.count + 2 })
        for (name, colours) in valid {
            d += block(0xC001, text(name))
            for c in colours {
                let u = ColourValues(c.hex)!.unit
                d += block(0x0001, text(c.name) + Data("RGB ".utf8) + f32(u.r) + f32(u.g) + f32(u.b) + u16(2))
            }
            d += block(0xC002, Data())
        }
        return d
    }
}

extension ExportFormat {
    /// Adobe Color swatches. Big-endian. A version 1 section (no names) then a version 2 section
    /// (with names), which is how Photoshop writes them so that old and new readers both cope.
    fileprivate func acoData(_ palettes: [ExportPalette]) -> Data {
        func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).bigEndian) { Data($0) } }
        let colours = palettes.flatMap { $0.colours }.compactMap { c in ColourValues(c.hex).map { (c.name, $0) } }
        func record(_ v: ColourValues) -> Data { u16(0) + u16(v.r * 257) + u16(v.g * 257) + u16(v.b * 257) + u16(0) }
        var d = u16(1) + u16(colours.count)
        for (_, v) in colours { d += record(v) }
        d += u16(2) + u16(colours.count)
        for (name, v) in colours {
            let units = Array(name.utf16)
            d += record(v) + u16(0) + u16(units.count + 1)
            d += units.reduce(Data()) { $0 + u16(Int($1)) } + u16(0)
        }
        return d
    }
}

extension ExportFormat {
    /// Adobe Color Table: 256 RGB triples, then how many are in use and the transparent index (none).
    /// The table holds 256 colours; any beyond that are left out.
    fileprivate func actData(_ palettes: [ExportPalette]) -> Data {
        let values = palettes.flatMap { $0.colours }.compactMap { ColourValues($0.hex) }.prefix(256)
        var d = Data()
        for v in values { d += Data([UInt8(v.r), UInt8(v.g), UInt8(v.b)]) }
        d += Data(count: (256 - values.count) * 3)
        return d + Data([UInt8(values.count >> 8), UInt8(values.count & 0xFF), 0xFF, 0xFF])
    }

    /// Adobe Color Book, the format of Photoshop's colour libraries. Big-endian. "8BCB", version 1,
    /// a book id, four strings (title, prefix, suffix, description), the colour count, colours per
    /// page, the page key, the colour space (0 is RGB), then each colour: name, a six-character code,
    /// and its components. Photoshop finds books in its Presets ▸ Color Books folder.
    fileprivate func acbData(_ palettes: [ExportPalette]) -> Data {
        func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).bigEndian) { Data($0) } }
        func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).bigEndian) { Data($0) } }
        func text(_ s: String) -> Data {
            let units = Array(s.utf16)
            return u32(units.count) + units.reduce(Data()) { $0 + u16(Int($1)) }
        }
        let title = palettes.count == 1 ? palettes[0].name : "Palettes"
        let colours = Array(palettes.flatMap { $0.colours }.compactMap { c in ColourValues(c.hex).map { (c.name, $0) } }.prefix(0xFFFF))
        // Adobe's own books use ids below 3000. Ours come from the title, so two books rarely share one.
        let id = 3000 + Int(crc32(Data(title.utf8)) % 60000)
        var d = Data("8BCB".utf8) + u16(1) + u16(id)
        d += text(title) + text("") + text("") + text("Exported from MMFFDev Colour 3")
        d += u16(colours.count) + u16(min(9, max(1, colours.count))) + u16(0) + u16(0)
        for (i, (name, v)) in colours.enumerated() {
            let code = String(i + 1).padding(toLength: 6, withPad: " ", startingAt: 0)
            d += text(name) + Data(code.utf8) + Data([UInt8(v.r), UInt8(v.g), UInt8(v.b)])
        }
        // Photoshop's own books end by saying whether they hold spot or process colours.
        return d + Data("spflproc".utf8)
    }

    /// Procreate swatches: a zip holding Swatches.json, an array of palettes whose colours are
    /// hue, saturation and brightness from 0 to 1. A Procreate palette holds 30 colours, so a
    /// longer one carries on in "Name 2", "Name 3" …
    fileprivate func procreateData(_ palettes: [ExportPalette]) -> Data {
        var entries: [String] = []
        for p in palettes {
            let colours = p.colours.compactMap { ColourValues($0.hex)?.hsvUnit }
            for (i, start) in stride(from: 0, to: colours.count, by: 30).enumerated() {
                let swatches = colours[start..<min(start + 30, colours.count)].map {
                    String(format: "{\"hue\":%.6f,\"saturation\":%.6f,\"brightness\":%.6f,\"alpha\":1,\"colorSpace\":0}",
                           $0.h / 360, $0.s, $0.v)
                }
                entries.append("{\"name\":\(json(i == 0 ? p.name : "\(p.name) \(i + 1)")),\"swatches\":[\(swatches.joined(separator: ","))]}")
            }
        }
        return zipArchive([("Swatches.json", Data("[\(entries.joined(separator: ","))]".utf8))])
    }
}

/// A zip archive with its files stored uncompressed. Little-endian; every reader copes with stored entries.
func zipArchive(_ files: [(name: String, data: Data)]) -> Data {
    func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
    func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
    var out = Data(), directory = Data()
    for f in files {
        let name = Data(f.name.utf8)
        // Version 2.0, UTF-8 names, stored, midnight on 1 January 1980, then checksum and both sizes.
        var common = Data()
        for v in [20, 0x0800, 0, 0, 0x21] { common += u16(v) }
        for v in [Int(crc32(f.data)), f.data.count, f.data.count] { common += u32(v) }
        common += u16(name.count)
        common += u16(0)
        let offset = out.count
        out += u32(0x04034B50)
        out += common
        out += name
        out += f.data
        // The directory repeats the header, then: comment length, disk, two sets of attributes, where the file starts.
        directory += u32(0x02014B50)
        directory += u16(20)
        directory += common
        for v in [0, 0, 0] { directory += u16(v) }
        directory += u32(0)
        directory += u32(offset)
        directory += name
    }
    let start = out.count
    out += directory
    out += u32(0x06054B50)
    for v in [0, 0, files.count, files.count] { out += u16(v) }
    out += u32(directory.count)
    out += u32(start)
    out += u16(0)
    return out
}

/// The checksum zip files carry.
func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    return ~crc
}

// ---------- Adobe's library folders ----------

/// A folder where an installed Adobe app keeps the swatch libraries it lists in its own menus,
/// and the kind of file it expects there. These folders belong to the system, not the user.
struct AdobeDestination: Equatable {
    /// "Photoshop 2026 — Colour Book"
    let title: String
    /// "Photoshop 2026"
    let app: String
    let folder: URL
    let format: ExportFormat

    /// The destinations on offer, for the newest year of each app found in `applications`.
    /// Adobe names each app's folder for its year, so nothing here can be remembered between launches.
    static func installed(in applications: URL = URL(fileURLWithPath: "/Applications")) -> [AdobeDestination] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: applications.path)) ?? []
        func isFolder(_ url: URL) -> Bool {
            var dir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
        }
        /// "Adobe Photoshop 2026" → its folder and "Photoshop 2026", newest year first.
        func newest(_ product: String) -> (home: URL, name: String)? {
            let prefix = "Adobe \(product) "
            let years = names.compactMap { n -> Int? in n.hasPrefix(prefix) ? Int(n.dropFirst(prefix.count)) : nil }
            return years.max().map { (applications.appendingPathComponent("\(prefix)\($0)"), "\(product) \($0)") }
        }
        var out: [AdobeDestination] = []
        func offer(_ app: (home: URL, name: String), _ kind: String, _ path: String, _ format: ExportFormat) {
            let folder = app.home.appendingPathComponent(path)
            if isFolder(folder) { out.append(AdobeDestination(title: "\(app.name) \u{2014} \(kind)", app: app.name, folder: folder, format: format)) }
        }
        if let ps = newest("Photoshop") {
            offer(ps, "Colour Book", "Presets/Color Books", .acb)
            offer(ps, "Swatches", "Presets/Color Swatches", .aco)
        }
        if let ai = newest("Illustrator") {
            // Illustrator keeps its presets under a folder named for the language it was installed in.
            let presets = ai.home.appendingPathComponent("Presets.localized")
            let languages = ((try? fm.contentsOfDirectory(atPath: presets.path)) ?? []).sorted()
            if let language = languages.first(where: { isFolder(presets.appendingPathComponent("\($0)/Swatches")) }) {
                offer(ai, "Swatch Library", "Presets.localized/\(language)/Swatches", .ase)
            }
        }
        if let id = newest("InDesign") { offer(id, "Colour Book", "Presets/Swatch Libraries", .acb) }
        return out
    }

    /// The file a palette becomes in this folder.
    func fileName(for palette: ExportPalette) -> String { filesystemName(palette.name) + "." + format.fileExtension }
}

extension Library {
    /// A palette ready to export, colours in the order given, each with its nearest name.
    func exportPalette(_ id: UUID, by order: SortOrder) -> ExportPalette? {
        guard let s = swatch(id) else { return nil }
        return ExportPalette(name: s.name, colours: hexes(inSwatch: id, by: order).map { ExportColour(name: name(of: $0, in: id), hex: $0) })
    }

    /// Every colour in the library as one palette.
    func exportEverything(named name: String, by order: SortOrder) -> ExportPalette {
        ExportPalette(name: name, colours: catalogueHexes(by: order).map { ExportColour(name: colourName($0), hex: $0) })
    }
}

// ---------- Design Pack ----------
//
// One folder that carries palettes to any team: our JSON, a PNG per swatch, a proof sheet, a CSS file
// per palette, and the licence. Everything here is pure text; the PNGs are drawn by the app.

struct PackSwatch {
    let name: String, hex: String, tags: [String]
    /// Path of the PNG within the pack.
    let file: String
}

struct PackPalette {
    let name: String, tags: [String]
    /// Folder within the pack.
    let folder: String
    let swatches: [PackSwatch]
    var css: String { "\(folder)/\(slug(name)).css" }
    var sheet: String { "\(folder)/\(slug(name)).png" }
    var export: ExportPalette { ExportPalette(name: name, colours: swatches.map { ExportColour(name: $0.name, hex: $0.hex) }) }
}

struct PackProject {
    let name: String
    let palettes: [PackPalette]
}

struct DesignPack {
    let name: String
    let projects: [PackProject]
    let licenceOwner: String
    let licenceText: String
    let exportedAt: Date

    var folderName: String { filesystemName(name) + " Design Pack" }
    var palettes: [PackPalette] { projects.flatMap { $0.palettes } }

    /// The files to write, path → contents, apart from the PNGs.
    func textFiles(options: ExportOptions) -> [(path: String, text: String)] {
        var out: [(String, String)] = [("README.md", readme()), ("pack.json", json()), ("LICENSE.md", licence())]
        for p in palettes {
            let css = ExportFormat.css.data([p.export], options: options).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            out.append((p.css, css))
        }
        return out
    }

    private var stamp: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: exportedAt)
    }

    private var year: String { String(Calendar.current.component(.year, from: exportedAt)) }

    func licence() -> String {
        licenceText.replacingOccurrences(of: "{owner}", with: licenceOwner.isEmpty ? "the author" : licenceOwner)
            .replacingOccurrences(of: "{year}", with: year)
            .replacingOccurrences(of: "{pack}", with: name) + "\n"
    }

    func readme() -> String {
        var l = ["# \(name) \u{2014} Design Pack", "",
                 "Exported from MMFFDev Colour 3 on \(stamp.prefix(10)). See LICENSE.md for terms.", "",
                 "## What is inside", "",
                 "- `pack.json` \u{2014} every project, palette and swatch, with all colour formats and tags",
                 "- `proof-sheet.png` \u{2014} contact sheet of every palette",
                 "- one folder per palette holding its `.css` (drop it into any codebase), its sheet, and a PNG per swatch", ""]
        for pr in projects {
            if projects.count > 1 || pr.name != "Palettes" { l += ["## \(pr.name)", ""] }
            for p in pr.palettes {
                l.append("### \(p.name)" + (p.tags.isEmpty ? "" : "  \u{2014}  " + p.tags.map { "#" + $0 }.joined(separator: " ")))
                l += ["", "Tokens: `\(p.css)` \u{00B7} Sheet: `\(p.sheet)`", "",
                      "| # | Swatch | Hex | RGB | HSL | CMYK | Tags |", "|---|---|---|---|---|---|---|"]
                for (i, s) in p.swatches.enumerated() {
                    l.append("| \(i + 1) | \(s.name) | \(s.hex) | \(ColourFormat.rgb.text(s.hex)) | \(ColourFormat.hsl.text(s.hex)) | \(ColourFormat.cmyk.text(s.hex)) | \(s.tags.joined(separator: ", ")) |")
                }
                l.append("")
            }
        }
        return l.joined(separator: "\n")
    }

    func json() -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        func list(_ a: [String]) -> String { "[" + a.map(q).joined(separator: ", ") + "]" }
        func nums(_ s: String) -> String { "[" + s.replacingOccurrences(of: "%", with: "") + "]" }
        var l = ["{", "  \"format\": \"mmffdev-colour-pack\",", "  \"version\": 1,",
                 "  \"generator\": \"MMFFDev Colour 3\",", "  \"exportedAt\": \(q(stamp)),", "  \"name\": \(q(name)),",
                 "  \"licence\": { \"owner\": \(q(licenceOwner)), \"file\": \"LICENSE.md\" },", "  \"projects\": ["]
        for (pi, pr) in projects.enumerated() {
            l.append("    { \"name\": \(q(pr.name)), \"palettes\": [")
            for (i, p) in pr.palettes.enumerated() {
                l.append("      { \"name\": \(q(p.name)), \"tags\": \(list(p.tags)), \"css\": \(q(p.css)), \"sheet\": \(q(p.sheet)), \"swatches\": [")
                for (j, s) in p.swatches.enumerated() {
                    guard let v = ColourValues(s.hex) else { continue }
                    let u = v.unit, lin = v.linear
                    l.append("        { \"name\": \(q(s.name)), \"hex\": \(q(s.hex.lowercased())), \"rgb\": [\(v.r), \(v.g), \(v.b)], "
                             + "\"hsl\": \(nums(ColourFormat.hsl.text(s.hex))), \"hsv\": \(nums(ColourFormat.hsv.text(s.hex))), "
                             + "\"cmyk\": \(nums(ColourFormat.cmyk.text(s.hex))), "
                             + String(format: "\"float\": [%.4f, %.4f, %.4f], \"linear\": [%.4f, %.4f, %.4f], ", u.r, u.g, u.b, lin.r, lin.g, lin.b)
                             + "\"tags\": \(list(s.tags)), \"file\": \(q(s.file)) }" + (j == p.swatches.count - 1 ? "" : ","))
                }
                l.append("      ] }" + (i == pr.palettes.count - 1 ? "" : ","))
            }
            l.append("    ] }" + (pi == projects.count - 1 ? "" : ","))
        }
        l += ["  ]", "}", ""]
        return l.joined(separator: "\n")
    }

    /// The default licence, with placeholders the export fills in.
    static let defaultLicence = """
    # Licence

    \u{00A9} {year} {owner}. All rights reserved.

    This design pack ("{pack}") and the colours, names and files in it are provided for use in the \
    recipient's own products and materials. It may be copied within the recipient's organisation and \
    passed to contractors working on those products. It may not be sold or published as a colour \
    collection in its own right.

    Colour names are approximate and provided for convenience. CMYK values are unprofiled conversions \
    and should be checked against a print profile before use in print.
    """
}

extension Library {
    /// Builds the pack for one palette, one project, or everything, laying out folders and file names.
    func designPack(named name: String, palettes chosen: [UUID]? = nil, projects only: [UUID]? = nil,
                    owner: String, licence: String, order: SortOrder = .oldest, at date: Date = Date()) -> DesignPack {
        let nested = chosen == nil && only == nil
        var groups: [(name: String, folder: String, palettes: [Swatch])] = []
        var usedFolders: [String] = []
        for p in orderedProjects where only == nil || only!.contains(p.id) {
            let list = palettes(in: p.id).filter { chosen == nil || chosen!.contains($0.id) }
            guard !list.isEmpty else { continue }
            let folder = uniqueName(slug(p.name), among: usedFolders); usedFolders.append(folder)
            groups.append((p.name, nested ? folder : "", list))
        }
        let loose = palettes(in: nil).filter { chosen == nil || chosen!.contains($0.id) }
        if only == nil, !loose.isEmpty {
            let folder = uniqueName("palettes", among: usedFolders); usedFolders.append(folder)
            groups.append(("Palettes", nested ? folder : "", loose))
        }
        var usedPalettes: [String] = []
        let projects = groups.map { g -> PackProject in
            PackProject(name: g.name, palettes: g.palettes.map { s -> PackPalette in
                let base = uniqueName(slug(s.name), among: usedPalettes); usedPalettes.append(base)
                let folder = g.folder.isEmpty ? base : "\(g.folder)/\(base)"
                var usedFiles: [String] = []
                // A Typography palette is exported pairing by pairing: each one's text colour and
                // background, named for the pairing and its part, so the files that belong together sort together.
                if let styles = s.styles {
                    let swatches = styles.enumerated().flatMap { i, style -> [PackSwatch] in
                        [("Text", "text", style.ink), ("Background", "bg", style.paper)].map { part, short, hex in
                            let file = uniqueName(String(format: "%02d-%@-%@-%@-%@", i + 1, slug(style.name), short, slug(colourName(hex)),
                                                         String(hex.dropFirst()).lowercased()), among: usedFiles)
                            usedFiles.append(file)
                            return PackSwatch(name: "\(style.name) \(part)", hex: hex, tags: colours.first { $0.hex == hex }?.tags ?? [],
                                              file: "\(folder)/swatches/\(file).png")
                        }
                    }
                    return PackPalette(name: s.name, tags: s.tagList, folder: folder, swatches: swatches)
                }
                let swatches = hexes(inSwatch: s.id, by: order).enumerated().map { i, hex -> PackSwatch in
                    let n = self.name(of: hex, in: s.id)
                    let file = uniqueName(String(format: "%02d-%@-%@", i + 1, slug(n), String(hex.dropFirst()).lowercased()), among: usedFiles)
                    usedFiles.append(file)
                    return PackSwatch(name: n, hex: hex, tags: colours.first { $0.hex == hex }?.tags ?? [],
                                      file: "\(folder)/swatches/\(file).png")
                }
                return PackPalette(name: s.name, tags: s.tagList, folder: folder, swatches: swatches)
            })
        }
        return DesignPack(name: name, projects: projects, licenceOwner: owner, licenceText: licence, exportedAt: date)
    }
}
