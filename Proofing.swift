import AppKit
import CryptoKit

/// Reference values stay in D50/2° Lab. Nothing passes through an RGB preview for comparison.
struct ProofPatch: Codable, Equatable {
    var id: String
    var name: String
    var l: Double
    var a: Double
    var b: Double
    var cmyk: [Double]? = nil // Percentage values, preserved from the file.
    var lab: LabD50 { LabD50(l: l, a: a, b: b) }
    var valid: Bool { !id.isEmpty && [l,a,b].allSatisfy(\.isFinite) && (0...100).contains(l) && abs(a) <= 200 && abs(b) <= 200 && (cmyk == nil || (cmyk!.count == 4 && cmyk!.allSatisfy { $0.isFinite && (0...100).contains($0) })) }
}
struct ProofDataset: Codable, Equatable {
    var name: String
    var source: String
    var sha256: String
    var metadata: [String: String]
    var patches: [ProofPatch]
    var conditions: String {
        [metadata["ILLUMINATION_NAME"] ?? "Illuminant unspecified", metadata["OBSERVER_ANGLE"].map { $0 + "°" } ?? "Observer unspecified", metadata["FILTER"] ?? metadata["MEASUREMENT_CONDITION"] ?? "Measurement mode unspecified", metadata["MEASUREMENT_BACKING"].map { $0 + " backing" } ?? "Backing unspecified"].joined(separator: " · ")
    }
    var hasD50: Bool { metadata["ILLUMINATION_NAME"]?.uppercased() == "D50" && ["2", "2.0"].contains(metadata["OBSERVER_ANGLE"] ?? "") }
    func validate() throws {
        guard !patches.isEmpty, patches.count <= 10000, patches.allSatisfy(\.valid) else { throw ProofError.invalid("Expected 1–10,000 patches with finite Lab values (L 0–100).") }
        guard Set(patches.map(\.id)).count == patches.count else { throw ProofError.invalid("Duplicate patch IDs. Each patch must have a unique ID.") }
    }
}
/// One gate shared by measured workflows. Confirmations supply missing facts only; they never
/// replace an explicit declaration. Original metadata and file hashes remain untouched.
struct ProofConditionReview {
    var conflicts: [String] = []
    var missing: [String] = []
    var assumptions: [String] = []
    var canEvaluate: Bool { conflicts.isEmpty && missing.isEmpty }
    var needsConfirmation: Bool { conflicts.isEmpty && !missing.isEmpty }
    var status: String {
        if !conflicts.isEmpty { return "Incompatible Conditions" }
        if !missing.isEmpty { return "Needs Confirmation" }
        return assumptions.isEmpty ? "Conditions Match" : "Confirmed By User"
    }
    var detail: String { (conflicts.isEmpty ? (missing.isEmpty ? assumptions : missing) : conflicts).joined(separator: "; ") }
    var record: String { status + (detail.isEmpty ? "" : " · " + detail) }
}
enum ProofConditions {
    static let labels = ["ILLUMINATION_NAME":"Illuminant", "OBSERVER_ANGLE":"Observer", "FILTER":"Measurement mode", "MEASUREMENT_BACKING":"Backing"]
    static func canonical(_ value: String, key: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch key {
        case "OBSERVER_ANGLE": return Double(clean.replacingOccurrences(of:"°",with:"")).map { String($0) } ?? clean
        case "MEASUREMENT_BACKING": return clean.replacingOccurrences(of:" BACKING",with:"")
        default: return clean
        }
    }
    static func review(reference: ProofDataset, measurement: ProofDataset? = nil,
                       confirmed: Bool = false, requireMeasurementDetails: Bool = true) -> ProofConditionReview {
        var review = ProofConditionReview()
        let keys = ["ILLUMINATION_NAME", "OBSERVER_ANGLE"] + (requireMeasurementDetails ? ["FILTER", "MEASUREMENT_BACKING"] : [])
        func values(_ dataset: ProofDataset, _ key: String) -> [String] {
            let aliases = key == "FILTER" ? ["FILTER", "MEASUREMENT_CONDITION"] : [key]
            return aliases.compactMap { dataset.metadata[$0] }.map { canonical($0,key:key) }.filter { !$0.isEmpty }
        }
        // Always detect explicit conflicts, even when legacy callers require only D50/2°.
        for key in ["ILLUMINATION_NAME", "OBSERVER_ANGLE", "FILTER", "MEASUREMENT_BACKING"] {
            let expected = key == "ILLUMINATION_NAME" ? "D50" : key == "OBSERVER_ANGLE" ? "2.0" : nil
            let ref = values(reference,key), measured = measurement.map { values($0,key) } ?? []
            for (name, entries) in [(reference.name,ref), (measurement?.name ?? "Measurement",measured)] {
                if Set(entries).count > 1 { review.conflicts.append(name + ": conflicting " + (labels[key] ?? key) + " declarations") }
                if let expected, let actual = entries.first, actual != expected {
                    review.conflicts.append(name + ": " + (labels[key] ?? key) + " " + actual + "; requires " + expected)
                }
            }
            if let a = ref.first, let b = measured.first, a != b, expected == nil {
                review.conflicts.append((labels[key] ?? key) + " differs: reference " + a + ", measurement " + b)
            }
            guard keys.contains(key) else { continue }
            let expectedValue = expected ?? ref.first
            if ref.isEmpty {
                let fact = "Reference " + (labels[key] ?? key) + (expectedValue.map { " = " + $0 } ?? " not declared")
                if confirmed && expectedValue != nil { review.assumptions.append(fact) } else { review.missing.append(fact) }
            }
            if measurement != nil && measured.isEmpty {
                let fact = (labels[key] ?? key) + (expectedValue.map { " = " + $0 } ?? " not declared in reference")
                if confirmed && expectedValue != nil { review.assumptions.append(fact) } else { review.missing.append(fact) }
            }
        }
        return review
    }
}
/// App bundles own reference resources; no SwiftPM accessor may fall back to a developer's build tree.
enum ProofReferences {
    static let names = ["FOGRA51", "FOGRA52", "FOGRA39"]
    static func read(_ name: String, directory: URL? = nil) throws -> ProofDataset {
        guard names.contains(name), let base = directory ?? Bundle.main.resourceURL else {
            throw ProofError.invalid("Unknown bundled proof reference: " + name)
        }
        let filename = name + "_MW3_Subset.txt"
        let candidates = [base.appendingPathComponent("ProofingResources").appendingPathComponent(filename), base.appendingPathComponent(filename)]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ProofError.invalid("Bundled proof reference is missing: " + filename)
        }
        var result = try ProofImport.read(Data(contentsOf: url), name: name + " · 72 patches")
        result.source = "Fogra · MediaWedge CMYK V3 reference subset · " + filename
        // FOGRA39's original file supplies D50/2° in INSTRUMENTATION, rather than these structured keys.
        // The pre-M1 FOGRA39 condition is M0. Enrich only the known bundled target, never arbitrary imports.
        if name == "FOGRA39" {
            result.metadata["ILLUMINATION_NAME"] = "D50"
            result.metadata["OBSERVER_ANGLE"] = "2"
            result.metadata["FILTER"] = "M0"
            result.metadata["CONDITIONS_SOURCE"] = "Bundled Fogra FOGRA39 reference; D50/2° from original INSTRUMENTATION; M0 legacy condition"
        }
        // These known bundled references explicitly describe white backing in INSTRUMENTATION.
        if (result.metadata["INSTRUMENTATION"] ?? "").localizedCaseInsensitiveContains("white backing") {
            result.metadata["MEASUREMENT_BACKING"] = "White"
        }
        return result
    }
}
enum ProofError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
/// Bounded CGATS and CSV reader. Rejects partial files rather than quietly dropping bad rows.
enum ProofImport {
    static func tokens(_ line: String, separator: Character? = nil) throws -> [String] {
        var out: [String] = [], value = "", quoted = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i+1] == "\"" { value.append(c); i += 1 }
                else { quoted.toggle() }
            } else if !quoted && c == "#" && separator == nil { break }
            else if !quoted && (separator.map { c == $0 } ?? c.isWhitespace) {
                if separator != nil || !value.isEmpty { out.append(value.trimmingCharacters(in: .whitespaces)); value = "" }
            } else { value.append(c) }
            i += 1
        }
        guard !quoted else { throw ProofError.invalid("Unclosed quote in data file.") }
        if separator != nil || !value.isEmpty { out.append(value.trimmingCharacters(in: .whitespaces)) }
        return out
    }
    static func read(_ data: Data, name: String) throws -> ProofDataset {
        guard data.count <= 12_000_000, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ProofError.invalid("Use a text CGATS or CSV file under 12 MB.") }
        var fields: [String] = [], records: [[String]] = [], metadata: [String:String] = [:]
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let cgats = text.uppercased().contains("BEGIN_DATA_FORMAT")
        if cgats {
            var format = false, rows = false, ended = false
            for line in lines {
                let values = try tokens(line)
                guard let first = values.first else { continue }
                let key = first.uppercased()
                if key == "BEGIN_DATA_FORMAT" { guard fields.isEmpty else { throw ProofError.invalid("Multiple data tables are not supported. Export one table per file.") }; format = true; continue }
                if key == "END_DATA_FORMAT" { format = false; continue }
                if key == "BEGIN_DATA" { rows = true; continue }
                if key == "END_DATA" { rows = false; ended = true; continue }
                if format { fields += values.map { $0.uppercased() } }
                else if rows { records.append(values) }
                else if values.count > 1 {
                    let value = values.dropFirst().joined(separator:" ")
                    if ProofConditions.labels[key] != nil || key == "MEASUREMENT_CONDITION", let prior = metadata[key],
                       ProofConditions.canonical(prior,key:key) != ProofConditions.canonical(value,key:key) {
                        throw ProofError.invalid("Conflicting " + key + " declarations. Export one consistent measurement condition.")
                    }
                    metadata[key] = value
                }
            }
            guard ended else { throw ProofError.invalid("Incomplete CGATS table: END_DATA is missing.") }
            if let n = metadata["NUMBER_OF_SETS"].flatMap(Int.init), n != records.count { throw ProofError.invalid("Declared patch count does not match the data.") }
            if let n = metadata["NUMBER_OF_FIELDS"].flatMap(Int.init), n != fields.count { throw ProofError.invalid("Declared field count does not match the columns.") }
        } else {
            let nonempty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let first = nonempty.first else { throw ProofError.invalid("The file is empty.") }
            let separator: Character = first.contains("\t") ? "\t" : (first.contains(";") ? ";" : ",")
            fields = try tokens(first, separator: separator).map { $0.uppercased().replacingOccurrences(of: "\u{feff}", with: "") }
            records = try nonempty.dropFirst().map { try tokens($0, separator: separator) }
        }
        guard Set(fields).count == fields.count else { throw ProofError.invalid("Duplicate column names.") }
        func column(_ aliases: [String]) -> Int? { aliases.lazy.compactMap { fields.firstIndex(of: $0) }.first }
        guard let li = column(["LAB_L","L","L*"]), let ai = column(["LAB_A","A","A*"]), let bi = column(["LAB_B","B","B*"]), let idi = column(["SAMPLE_ID","ID","SAMPLE_NAME","NAME"]) else { throw ProofError.invalid("Required columns: SAMPLE_ID (or NAME), LAB_L, LAB_A, LAB_B. Spectral-only files need Lab values before import.") }
        let ni = column(["SAMPLE_NAME","NAME"])
        let ink = ["CMYK_C","CMYK_M","CMYK_Y","CMYK_K"].compactMap { column([$0]) }
        guard ink.isEmpty || ink.count == 4 else { throw ProofError.invalid("CMYK requires all four channels.") }
        var patches: [ProofPatch] = []
        for (n, row) in records.enumerated() {
            guard row.count == fields.count else { throw ProofError.invalid("Row \(n+1) has the wrong number of fields.") }
            func number(_ i: Int) throws -> Double {
                guard let d = Double(row[i].replacingOccurrences(of: ",", with: ".")), d.isFinite else { throw ProofError.invalid("Invalid number in row \(n+1), \(fields[i]).") }; return d
            }
            patches.append(ProofPatch(id: row[idi], name: ni.map { row[$0] } ?? "Patch \(row[idi])", l: try number(li), a: try number(ai), b: try number(bi), cmyk: ink.isEmpty ? nil : try ink.map(number)))
            guard patches.count <= 10000 else { throw ProofError.invalid("Maximum 10,000 patches per file.") }
        }
        let result = ProofDataset(name: name, source: name, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), metadata: metadata, patches: patches)
        try result.validate(); return result
    }
}
struct ProofOptions: Codable {
    var mode = "Prediction"
    var profile = PressProfiles.generic
    var intent = RenderingIntent.absolute.rawValue
    var method = DifferenceMethod.ciede2000.rawValue
    var tolerance = 2.0
    var inkLimit = 300.0 // Explicit user review limit, not inferred from the profile.
    var confirmD50 = false
    var recipe = false
}
struct ProofSession: Codable {
    var version = 1
    var reference: ProofDataset
    var measurement: ProofDataset?
    var options: ProofOptions
    var notes = ""
    var embeddedProfile: Data?
    func validate() throws {
        guard version == 1 else { throw ProofError.invalid("Unsupported proof session version.") }
        try reference.validate(); try measurement?.validate()
        if let data = embeddedProfile {
            guard data.count <= 16_000_000, let space = CGColorSpace(iccData: data as CFData), space.model == .cmyk else { throw ProofError.invalid("Invalid embedded CMYK profile.") }
        }
        guard ["Prediction","Measurement"].contains(options.mode), DifferenceMethod(rawValue: options.method) != nil, RenderingIntent(rawValue: options.intent) != nil,
              options.tolerance.isFinite, (0.01...100).contains(options.tolerance), options.inkLimit.isFinite, (1...400).contains(options.inkLimit) else { throw ProofError.invalid("Invalid proof settings.") }
    }
}
enum ProofStatus: String {
    case notEvaluated = "Not evaluated"
    case outsideTolerance = "Outside tolerance"
    case inkLimitExceeded = "Ink limit exceeded"
    case withinTolerance = "Within tolerance"
}
struct ProofResult {
    var reference: ProofPatch
    var sample: LabD50?
    var inks: [Double]?
    var difference: Double?
    var issue: String?
    var conversion: PCSConversion.Provenance?
    func status(_ options: ProofOptions) -> ProofStatus {
        guard let d = difference else { return .notEvaluated }
        if d > options.tolerance { return .outsideTolerance }
        if let inks, inks.reduce(0,+) > options.inkLimit { return .inkLimitExceeded }
        return .withinTolerance
    }
}
enum ProofEngine {
    static func conditionsIssue(_ session: ProofSession) -> String? {
        let review = ProofConditions.review(reference: session.reference,
            measurement: session.options.mode == "Measurement" ? session.measurement : nil,
            confirmed: session.options.confirmD50, requireMeasurementDetails: false)
        return review.canEvaluate ? nil : review.record
    }

    static func evaluate(_ session: ProofSession) -> [ProofResult] {
        let options = session.options, method = DifferenceMethod(rawValue: options.method) ?? .ciede2000
        if (try? session.validate()) == nil { return session.reference.patches.map { ProofResult(reference:$0,issue:"Invalid proof data or settings") } }
        let measured = Dictionary(uniqueKeysWithValues: (session.measurement?.patches ?? []).map { ($0.id, $0) })
        let profile = session.embeddedProfile.map { PressProfiles.registerProofProfile($0) } ?? options.profile
        let condition = conditionsIssue(session)
        return session.reference.patches.map { patch in
            var result = ProofResult(reference: patch, issue: condition)
            guard condition == nil else { return result }
            if options.mode == "Measurement" {
                guard let m = measured[patch.id] else { result.issue = "No measurement with ID \(patch.id)"; return result }
                result.sample = m.lab; result.inks = m.cmyk
            } else if options.recipe {
                guard [RenderingIntent.absolute.rawValue, RenderingIntent.relative.rawValue].contains(options.intent) else { result.issue = "Fixed CMYK recipes support absolute or relative colorimetric evaluation only"; return result }
                guard let inks = patch.cmyk else { result.issue = "No source CMYK recipe"; return result }
                guard let master = PrintBuild.master(ofInks: inks.map { $0 / 100 }, press: profile, intent: RenderingIntent(rawValue: options.intent) ?? .absolute) else { result.issue = "Profile conversion unavailable"; return result }
                result.sample = master.lab
                result.inks = inks
                result.conversion = PressProfiles.space(named: profile).flatMap { PCSConversion.provenance(for: $0) }
            } else {
                guard let build = PrintBuild.of(patch.lab.xyz, press: profile, intent: RenderingIntent(rawValue: options.intent) ?? .absolute, blackPoint: false) else { result.issue = "Profile conversion unavailable"; return result }
                result.sample = build.printed.lab; result.inks = build.inks.map { $0 * 100 }; result.conversion = build.provenance
            }
            if let sample = result.sample { result.difference = method.difference(patch.lab, sample) }
            return result
        }
    }
    struct Summary {
        var count: Int; var evaluated: Int; var passed: Int; var mean: Double?; var maximum: Double?; var p95: Double?
        var completePass: Bool { count > 0 && evaluated == count && passed == count }
    }
    static func summary(_ results: [ProofResult], options: ProofOptions) -> Summary {
        let values = results.compactMap(\.difference).sorted()
        return Summary(count: results.count, evaluated: values.count, passed: results.filter { $0.status(options) == .withinTolerance }.count,
                       mean: values.isEmpty ? nil : values.reduce(0,+) / Double(values.count), maximum: values.last,
                       p95: values.isEmpty ? nil : values[max(0, Int(ceil(Double(values.count)*0.95))-1)])
    }
    static func csv(_ results: [ProofResult], session: ProofSession) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func n(_ d: Double?) -> String { d.map { String(format: "%.6f", $0) } ?? "" }
        let conversions = results.compactMap(\.conversion)
        let profileHash = Array(Set(conversions.map(\.profileSHA256))).sorted().joined(separator:"; ")
        let engine = conversions.first
        let header: [[String]] = [["Colorgain Proof Report", "Generated", ISO8601DateFormatter().string(from: Date())],
                     ["Mode",session.options.mode,"Reference",session.reference.name,"SHA256",session.reference.sha256],
                     ["Measurement",session.measurement?.name ?? "None","SHA256",session.measurement?.sha256 ?? ""],
                     ["Profile",session.options.profile,"Intent",session.options.intent,"Black Point Compensation","Off"],
                     ["Profile SHA256",profileHash.isEmpty ? "Not evaluated":profileHash,"Preserve CMYK recipe",String(session.options.recipe)],
                     ["Conversion engine",engine?.engine ?? "Not used", "PCS pipeline version",engine.map { String($0.pipelineVersion) } ?? ""],
                     ["Engine platform",engine?.operatingSystem ?? "", "Connection space",engine?.connectionSpace ?? ""],
                     ["Measurement conditions",session.measurement?.conditions ?? "None"],
                     ["Method",session.options.method,"Tolerance",n(session.options.tolerance),"Ink review limit (%)",n(session.options.inkLimit)],
                     ["Conditions",session.reference.conditions,"Missing conditions confirmed D50/2°",String(session.options.confirmD50)],
                     ["Notes",session.notes], ["Scope","User tolerance review; not a certified contract proof. Screen colours are previews."],
                     ["ID","Name","Reference L","Reference a","Reference b","Sample L","Sample a","Sample b","Delta L","Delta a","Delta b","Delta E","C %","M %","Y %","K %","Total ink %","Status","Issue"]]
        var lines = header.map { $0.map(q).joined(separator: ",") }
        // Keep the complete instrument/file metadata alongside the numeric report.
        let metadataRows = session.reference.metadata.sorted { $0.key < $1.key }.map { ["Reference metadata",$0.key,$0.value] }
            + (session.measurement?.metadata ?? [:]).sorted { $0.key < $1.key }.map { ["Measurement metadata",$0.key,$0.value] }
        lines.insert(contentsOf:metadataRows.map { $0.map(q).joined(separator:",") },at:lines.count-1)
        lines += results.map { r in
            let a = r.reference.lab, b = r.sample
            return [r.reference.id,r.reference.name,n(a.l),n(a.a),n(a.b),n(b?.l),n(b?.a),n(b?.b),n(b.map { $0.l-a.l }),n(b.map { $0.a-a.a }),n(b.map { $0.b-a.b }),n(r.difference)] .appending(contentsOf: (0..<4).map { n(r.inks?[$0]) } + [n(r.inks?.reduce(0,+)),r.status(session.options).rawValue,r.issue ?? ""]).map(q).joined(separator: ",")
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
private extension Array { func appending(contentsOf other: [Element]) -> [Element] { self + other } }

/// Catalogue-owned proof configurations; display calibration remains machine-local.
struct ProofConfiguration: Codable {
    var version = 1
    var id = UUID()
    var name: String
    var created = Date()
    var session: ProofSession
    var densitySimulation: [Double]?
    /// Absent in legacy configurations: their conversion engine is unknown.
    var conversion: PCSConversion.Provenance?
    init(version: Int = 1, id: UUID = UUID(), name: String, created: Date = Date(), session: ProofSession, densitySimulation: [Double]? = nil) {
        self.version = version; self.id = id; self.name = name; self.created = created
        self.session = session; self.densitySimulation = densitySimulation
        if session.options.mode == "Prediction" {
            let profile = session.embeddedProfile.map { PressProfiles.registerProofProfile($0) } ?? session.options.profile
            conversion = PressProfiles.space(named: profile).flatMap { PCSConversion.provenance(for: $0) }
        }
    }
    func validate() throws {
        guard version == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 160, created.timeIntervalSince1970.isFinite else { throw ProofError.invalid("Invalid proof configuration.") }
        try session.validate()
        if let v = densitySimulation {
            guard v.count == 5, v.allSatisfy({ $0.isFinite }), (0...3).contains(v[0]), (0...3).contains(v[1]), (0...10).contains(v[2]), (1...500).contains(v[3]), (0...10).contains(v[4]) else { throw ProofError.invalid("Invalid density simulation settings.") }
        }
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 40_000_000 else { throw ProofError.invalid("Configuration exceeds 40 MB.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
}
enum ProofConfigurationStore {
    static let folder = "Library/Calibrations"
    static func entries(root: URL) throws -> [Zip.Entry] {
        let dir = root.appendingPathComponent(folder), fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        guard dir.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().appendingPathComponent(folder).path else { throw ProofError.invalid("Calibration folders cannot be symbolic links.") }
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey]).filter { $0.pathExtension.lowercased() == "colcal" }
        var entries: [Zip.Entry] = [], total = 0, ids = Set<UUID>()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try file.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 40_000_000 else { throw ProofError.invalid("Invalid calibration file: " + file.lastPathComponent) }
            total += values.fileSize ?? 0
            guard total <= 200_000_000 else { throw ProofError.invalid("Calibration collection exceeds 200 MB.") }
            let data = try Handler_File_Manager.shared.read(file), config = try ProofConfiguration.decode(data)
            guard ids.insert(config.id).inserted else { throw ProofError.invalid("Duplicate calibration identifier.") }
            entries.append(Zip.Entry(path: folder + "/" + config.id.uuidString + ".colcal", data: data))
        }
        return entries
    }
    static func list(root: URL) throws -> [ProofConfiguration] {
        try entries(root: root).map { try ProofConfiguration.decode($0.data) }.sorted { $0.created > $1.created }
    }
    @discardableResult static func save(_ config: ProofConfiguration, root: URL) throws -> ProofConfiguration {
        var copy = config
        let existing = try list(root: root)
        if existing.contains(where: { $0.id == copy.id }) { copy.id = UUID() }
        try copy.validate()
        let dir = root.appendingPathComponent(folder)
        try Handler_File_Manager.shared.createDirectory(dir)
        guard dir.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().appendingPathComponent(folder).path else { throw ProofError.invalid("Calibration folders cannot be symbolic links.") }
        let data = try JSONEncoder().encode(copy)
        _ = try ProofConfiguration.decode(data)
        guard try entries(root: root).reduce(data.count, { $0 + $1.data.count }) <= 200_000_000 else { throw ProofError.invalid("Calibration collection exceeds 200 MB.") }
        try Handler_File_Manager.shared.write(data, to: dir.appendingPathComponent(copy.id.uuidString + ".colcal"), createOnly: true)
        return copy
    }
}

/// Sort the complete filtered register before taking a page. Missing values always sort last.
enum ProofRegister {
    /// Only controls intersecting the viewport, plus one row on each side, need native hit targets.
    static func viewportRows(count: Int, top: CGFloat, rowHeight: CGFloat, visible: NSRect) -> Range<Int> {
        guard count > 0, rowHeight > 0, visible.height > 0 else { return 0..<0 }
        let first = min(count, max(0, Int(floor((visible.minY-top)/rowHeight))-1))
        let last = min(count, max(first, Int(ceil((visible.maxY-top)/rowHeight))+1))
        return first..<last
    }

    static func sorted(_ indices: [Int], results: [ProofResult], options: ProofOptions, column: Int, ascending: Bool) -> [Int] {
        indices.sorted { i, j in
            let a = results[i], b = results[j]
            func numeric(_ r: ProofResult) -> Double? {
                switch column {
                case 2: return r.difference
                case 3: return r.sample.map { $0.l - r.reference.l }
                case 4: return r.sample.map { $0.a - r.reference.a }
                case 5: return r.sample.map { $0.b - r.reference.b }
                default: return nil
                }
            }
            if (2...5).contains(column) {
                let x = numeric(a), y = numeric(b)
                if x == nil || y == nil { return x == nil ? (y == nil && i < j) : true }
                if x == y { return i < j }
                return ascending ? x! < y! : x! > y!
            }
            let x = column == 0 ? a.reference.id : column == 1 ? a.reference.name : a.status(options).rawValue
            let y = column == 0 ? b.reference.id : column == 1 ? b.reference.name : b.status(options).rawValue
            let order = x.compare(y, options: [.numeric,.caseInsensitive])
            return order == .orderedSame ? i < j : ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}
