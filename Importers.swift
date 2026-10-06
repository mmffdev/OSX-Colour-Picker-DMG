import Foundation

// ---------- Importing palettes ----------
//
// Files other tools write, read back into palettes: our own .colpalette, CSS or SCSS variables
// (the tokens.css the app exports, and anything shaped like it), and W3C Design Tokens JSON.
// Everything here is pure: bytes in, named colours out. Merging into a library is `Library.merge`.

/// One palette as read from a file, before it is merged: a name and its named colours, in file order.
struct ImportedPalette: Equatable {
    var name: String
    var colours: [ExportColour]
}

/// What a merge did, for the footer.
struct ImportOutcome: Equatable {
    var palettesMade = 0
    var added = 0
    /// Already in the palette, same colour: left alone.
    var skipped = 0
    /// Same name as a colour already there but a different colour: taken in under a numbered name.
    var renamed = 0

    var summary: String {
        var parts: [String] = []
        if palettesMade > 0 { parts.append(plural(palettesMade, "new palette", "new palettes")) }
        parts.append(plural(added, "colour added", "colours added"))
        if skipped > 0 { parts.append(plural(skipped, "duplicate skipped", "duplicates skipped")) }
        if renamed > 0 { parts.append(plural(renamed, "name clash numbered", "name clashes numbered")) }
        return parts.joined(separator: ", ")
    }
}

enum PaletteImport {
    /// Reads whatever the file is by its contents, not its extension: a .colpalette, a tokens JSON,
    /// or CSS/SCSS text. `fallback` names a palette when the file does not (the file's own name).
    static func read(_ data: Data, fallback: String) -> [ImportedPalette] {
        if let own = paletteDocument(data) { return [own] }
        if let tokens = designTokens(data) { return tokens }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return variables(in: text, fallback: fallback)
    }

    /// A .colpalette: the palette and the colours it uses, each named as it was there.
    static func paletteDocument(_ data: Data) -> ImportedPalette? {
        guard let doc = try? ColourFiles.decoder().decode(PaletteDocument.self, from: data), doc.format == "colour-palette" else { return nil }
        let colours = doc.palette.entries.map { ExportColour(name: $0.name ?? colourName($0.hex), hex: $0.hex) }
        return ImportedPalette(name: doc.palette.name, colours: colours)
    }

    /// W3C Design Tokens: a colour token is any object with "$type": "color", or a "$value" that reads as a colour.
    /// A group becomes a palette named for its key; tokens at the top level make a palette named "Tokens".
    static func designTokens(_ data: Data) -> [ImportedPalette]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [ImportedPalette] = []
        var loose: [ExportColour] = []
        func colour(_ value: Any) -> String? {
            if let s = value as? String { return parseColour(s) }
            if let o = value as? [String: Any] {
                if let h = o["hex"] as? String, let hex = normaliseHex(h) { return hex }
                if let c = o["components"] as? [Any], c.count >= 3 {
                    let v = c.prefix(3).compactMap { ($0 as? NSNumber)?.doubleValue }
                    guard v.count == 3 else { return nil }
                    return hex(v[0], v[1], v[2])
                }
            }
            return nil
        }
        func walk(_ node: [String: Any], into palette: inout [ExportColour], path: [String]) {
            for key in node.keys.sorted() {
                guard !key.hasPrefix("$"), let child = node[key] as? [String: Any] else { continue }
                if let value = child["$value"], let hex = colour(value) {
                    let name = (child["$description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title(key)
                    palette.append(ExportColour(name: name, hex: hex))
                } else if child["$value"] == nil {
                    // A group. At the top it is a palette; deeper groups fold into the palette above them.
                    if path.isEmpty {
                        var inner: [ExportColour] = []
                        walk(child, into: &inner, path: [key])
                        if !inner.isEmpty { out.append(ImportedPalette(name: title(key), colours: inner)) }
                    } else {
                        walk(child, into: &palette, path: path + [key])
                    }
                }
            }
        }
        walk(root, into: &loose, path: [])
        if !loose.isEmpty { out.insert(ImportedPalette(name: "Tokens", colours: loose), at: 0) }
        return out.isEmpty ? nil : out
    }

    /// CSS custom properties (--name: value) and SCSS variables ($name: value). A comment on a line of its
    /// own starts a new palette named by the comment, as the app's own export writes them; anything before
    /// the first such comment is a palette named for the file.
    static func variables(in text: String, fallback: String) -> [ImportedPalette] {
        var out: [ImportedPalette] = []
        var current = ImportedPalette(name: fallback, colours: [])
        func close() { if !current.colours.isEmpty { out.append(current) } }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let heading = commentHeading(line) {
                close()
                current = ImportedPalette(name: heading, colours: [])
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard key.hasPrefix("--") || key.hasPrefix("$") else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let semi = value.firstIndex(of: ";") { value = String(value[..<semi]) }
            if let comment = value.range(of: "//") { value = String(value[..<comment.lowerBound]) }
            if let comment = value.range(of: "/*") { value = String(value[..<comment.lowerBound]) }
            guard let hex = parseColour(value.trimmingCharacters(in: .whitespaces)) else { continue }
            current.colours.append(ExportColour(name: variableName(key, within: current.name), hex: hex))
        }
        close()
        return out
    }

    /// "/* Brand */" or "// Brand" alone on a line, but not the banner the export writes.
    private static func commentHeading(_ line: String) -> String? {
        var inner: Substring?
        if line.hasPrefix("/*"), line.hasSuffix("*/") { inner = line.dropFirst(2).dropLast(2) }
        else if line.hasPrefix("//") { inner = line.dropFirst(2) }
        guard let found = inner?.trimmingCharacters(in: .whitespaces), !found.isEmpty, !found.hasPrefix("Exported from") else { return nil }
        return found
    }

    /// "--swatch-steel-blue" gives "Steel Blue": the marker and a leading swatch, color or colour prefix go, and so
    /// does the palette's own name when the file put it in front, as the app does when several palettes share a file.
    static func variableName(_ key: String, within palette: String? = nil) -> String {
        var name = key
        if name.hasPrefix("--") { name.removeFirst(2) } else if name.hasPrefix("$") { name.removeFirst() }
        for prefix in ["swatch-", "colour-", "color-"] where name.lowercased().hasPrefix(prefix) && name.count > prefix.count {
            name.removeFirst(prefix.count)
            break
        }
        if let own = palette.map(slug), !own.isEmpty, name.lowercased().hasPrefix(own + "-"), name.count > own.count + 1 {
            name.removeFirst(own.count + 1)
        }
        return title(name)
    }

    /// "Steel Blue!" gives "steel-blue", as the export names its variables.
    static func slug(_ s: String) -> String {
        var out = "", gap = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber { if gap, !out.isEmpty { out.append("-") }; out.append(ch); gap = false }
            else { gap = true }
        }
        return out
    }

    /// "steel-blue" or "steel_blue" gives "Steel Blue". A number stays a number.
    static func title(_ slug: String) -> String {
        slug.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// "#RRGGBB", "#RGB", "rgb(r g b)", "rgb(r, g, b)" and their rgba forms, as a "#RRGGBB" key. Anything else is nil.
    static func parseColour(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = normaliseHex(s) { return hex }
        if s.hasPrefix("#"), s.count == 4, s.dropFirst().allSatisfy({ $0.isHexDigit }) {
            return normaliseHex("#" + s.dropFirst().map { "\($0)\($0)" }.joined())
        }
        let lower = s.lowercased()
        guard lower.hasPrefix("rgb"), let open = lower.firstIndex(of: "("), let close = lower.lastIndex(of: ")") else { return nil }
        let inside = lower[lower.index(after: open)..<close].replacingOccurrences(of: "/", with: " ")
        let parts = inside.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        guard parts.count >= 3 else { return nil }
        func channel(_ p: String) -> Double? {
            if p.hasSuffix("%"), let v = Double(p.dropLast()) { return v / 100 }
            guard let v = Double(p) else { return nil }
            return v / 255
        }
        let v = parts.prefix(3).compactMap(channel)
        guard v.count == 3 else { return nil }
        return hex(v[0], v[1], v[2])
    }

    private static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

extension Library {
    /// Takes imported palettes into one place: `project` for a member's palettes, nil for the stock list. A palette
    /// with the name of one already there merges into it; otherwise it is made. Within a palette a colour that is
    /// already there is skipped, and one whose name is taken by a different colour comes in under a numbered name.
    @discardableResult
    mutating func merge(_ imported: [ImportedPalette], into project: UUID?, at date: Date = Date()) -> ImportOutcome {
        var outcome = ImportOutcome()
        for incoming in imported where !incoming.colours.isEmpty {
            let wanted = incoming.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let id: UUID
            if let there = palettes(in: project).first(where: { !$0.isTypography && $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) {
                id = there.id
            } else {
                let keep = activeSwatchID
                id = createSwatch(named: wanted, hexes: [], at: date)
                if let project = project { move(id, to: project, index: Int.max, at: date) }
                activeSwatchID = keep   // an import does not redirect picks
                outcome.palettesMade += 1
            }
            for colour in incoming.colours {
                guard let entries = swatch(id)?.entries else { break }
                if entries.contains(where: { $0.hex == colour.hex }) { outcome.skipped += 1; continue }
                guard add([colour.hex], toSwatch: id, at: date) == 1 else { outcome.skipped += 1; continue }
                let taken = entries.map { name(of: $0.hex, in: id) }
                var given = colour.name
                if taken.contains(where: { $0.caseInsensitiveCompare(given) == .orderedSame }) {
                    given = uniqueName(given, among: taken)
                    outcome.renamed += 1
                }
                setName(given, of: colour.hex, in: id, at: date)
                outcome.added += 1
            }
        }
        return outcome
    }
}
