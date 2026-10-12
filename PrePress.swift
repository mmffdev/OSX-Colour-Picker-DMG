import AppKit
import UniformTypeIdentifiers

// ---------- PrePress: the four print workflows, each a route with a start, steps and an artefact ----------
//
// A page section on Master Inner, laid out like Settings ▸ Shortcuts: the title, an introduction on the
// content column, numbered sections with a thick rule, rows on hairlines, the one primary action per
// step. The menu asks which job is in hand and sends the user down one route; a route is one page whose
// sections are its steps, so the page's anchor strip is the step navigation. Verify A Proof runs the
// real engine: a bundled Fogra reference, an imported measurement matched by patch ID, and the seven
// checks of ISO 12647-7:2016 (4.3.2, 4.3.3, Table 2) with the clause beside each. Will It Print? runs the
// press profile. Check A Colour compares a measured sample to a catalogue master. Press Check is drawn
// for a later release so the data model keeps room for it. Numbers never come from memory: the
// tolerances are the standard's, verified against its text on 2026-10-12.

final class PrePressPage: NSView, PageSection, NSTextFieldDelegate {
    enum Flow: Int, CaseIterable { case menu = 0, verify, check, print, press }
    var flow: Flow = .menu { didSet { if flow != oldValue { enter() } } }
    /// Asked to show another flow: the window moves the place, so the rails follow.
    var onNavigate: ((Int) -> Void)?
    var onResize: (() -> Void)?
    private let library: LibraryController
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private var u: CGFloat { Self.u }
    private var firstGuide: CGFloat { SettingsSheet.headerGuide + 4 * u }
    /// The content column is the page's own split, where the area gutter falls: the words on the left, the controls and tables on the right.
    private var contentX: CGFloat {
        let grid = Design.App.pageColumns(width: bounds.width, in: window?.frame.width ?? Design.App.size.width)
        return grid.x.indices.contains(grid.split) ? grid.x[grid.split] : SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width)
    }
    private var columns: [CGFloat] { SettingsSheet.columns(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    /// The first page column at or past a fraction of the content area: values and numerals sit on columns, never at arbitrary x.
    private func column(at fraction: CGFloat) -> CGFloat {
        let x = contentX, w = bounds.width, want = x + (w - x) * fraction
        return columns.first(where: { $0 >= want }) ?? want
    }
    private var problem = ""

    // MARK: The routes

    struct Route { let flow: Flow; let title: String; let who: String; let need: [String]; let get: String; let steps: [String]; let later: Bool }
    static let routes: [Route] = [
        Route(flow: .verify, title: "Verify A Proof", who: "Prepress · ISO 12647-7", need: ["The proof, with its MediaWedge", "A spectrophotometer, M1", "The condition it simulates"], get: "A proof label, pass or fail, every figure on it", steps: ["Condition", "Measure", "Result", "Label"], later: false),
        Route(flow: .check, title: "Check A Colour", who: "Brand owner · Agency · Printer", need: ["The master colour in the catalogue", "The brand book's tolerance", "The printed sample, measured"], get: "An approval record, copied for the swatch", steps: ["Master", "Measure", "Decide"], later: false),
        Route(flow: .print, title: "Will It Print?", who: "Designer · Before anything is printed", need: ["The palette", "The condition it is going to", "Nothing printed yet"], get: "Which colours hold, and a note to keep with the palette", steps: ["Palette", "Result", "Note"], later: false),
        Route(flow: .press, title: "Press Check", who: "Press operator · ISO 12647-2 · Later release", need: ["The colour bar on the sheet", "A spectrodensitometer", "The printing condition"], get: "The OK sheet, signed, with its densities kept", steps: ["Condition", "Measure", "OK Sheet"], later: true),
    ]
    static func route(_ flow: Flow) -> Route? { routes.first { $0.flow == flow } }

    // MARK: Verify A Proof

    struct Condition { let file: String; let name: String; let short: String; let strip: String }
    static let conditions = [Condition(file: "FOGRA51", name: "FOGRA51 · PSO Coated v3 · Premium coated", short: "FOGRA51 · PSO Coated v3", strip: "M1, white backing"),
                             Condition(file: "FOGRA52", name: "FOGRA52 · PSO Uncoated v3 · Woodfree uncoated", short: "FOGRA52 · PSO Uncoated v3", strip: "M1, white backing"),
                             Condition(file: "FOGRA39", name: "FOGRA39 · ISO Coated v2 · Coated, 2008", short: "FOGRA39 · ISO Coated v2", strip: "M0, white backing")]
    private var condition = conditions[0]
    private var reference: ProofDataset?
    private var measurement: ProofDataset?
    /// One of the standard's checks: what it is, the clause it comes from, its limit, and what was measured; nil before a measurement.
    struct Check { let name: String; let clause: String; let limit: Double; let value: Double?; let unit: String
        var within: Bool? { value.map { $0 <= limit } } }
    private var checks: [Check] = []
    private var matched = 0, missing = 0
    private var verdict: Verdict = .waiting
    enum Verdict { case waiting, passed, failed(String) }
    private let label = ProofLabelView()
    private let importMeasurement = SwissButton("Import Measurement…", .primary)
    private let exportReport = SwissButton("Export Report…", .secondary)
    private let saveLabel = SwissButton("Save Label As PDF…", .primary)
    private let backToMenu = SwissButton("All Workflows", .quiet)
    private var conditionMenu: SwissDropdown?

    /// The bundled Fogra subset by name, its conditions stamped from the file's own words: the 2008 file says D50, 2 degree only in prose.
    static func bundled(_ name: String) -> ProofDataset? {
        let file = name + "_MW3_Subset.txt"
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("ProofingResources").appendingPathComponent(file), Bundle.main.resourceURL?.appendingPathComponent(file)].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }), let data = try? Data(contentsOf: url), var set = try? ProofImport.read(data, name: name) else { return nil }
        if set.metadata["ILLUMINATION_NAME"] == nil, (set.metadata["INSTRUMENTATION"] ?? "").localizedCaseInsensitiveContains("D50") { set.metadata["ILLUMINATION_NAME"] = "D50" }
        if set.metadata["OBSERVER_ANGLE"] == nil, (set.metadata["INSTRUMENTATION"] ?? "").localizedCaseInsensitiveContains("2 degree") { set.metadata["OBSERVER_ANGLE"] = "2" }
        if set.metadata["FILTER"] == nil, (set.metadata["INSTRUMENTATION"] ?? "").localizedCaseInsensitiveContains("no polarisation") { set.metadata["FILTER"] = "M0" }
        set.source = "Fogra characterisation data, unmodified · " + file
        return set
    }

    /// The seven checks of ISO 12647-7:2016 for a control strip, from the reference and a measurement matched by ID.
    /// Patch roles come from the reference's own CMYK recipes: paper is 0/0/0/0, a solid is one ink at 100, the neutral
    /// scale is the CMY overprints with M and Y equal under a larger C. A patch with no measurement is never a pass.
    static func evaluate(reference: ProofDataset, measurement: ProofDataset) -> (checks: [Check], matched: Int, missing: Int) {
        let measured = Dictionary(measurement.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pairs = reference.patches.compactMap { r in measured[r.id].map { (r, $0) } }
        func inks(_ p: ProofPatch) -> [Double] { p.cmyk ?? [-1, -1, -1, -1] }
        func recipe(_ p: ProofPatch, _ c: Double, _ m: Double, _ y: Double, _ k: Double) -> Bool { inks(p) == [c, m, y, k] }
        func de(_ pair: (ProofPatch, ProofPatch)) -> Double { deltaE2000(pair.0.lab, pair.1.lab) }
        func hue(_ pair: (ProofPatch, ProofPatch)) -> Double {
            let a = pair.0.lab, b = pair.1.lab
            let dL = b.l - a.l, da = b.a - a.a, db = b.b - a.b, dC = hypot(b.a, b.b) - hypot(a.a, a.b)
            return sqrt(max(0, dL * dL + da * da + db * db - dL * dL - dC * dC))
        }
        func ch(_ pair: (ProofPatch, ProofPatch)) -> Double { hypot(pair.1.a - pair.0.a, pair.1.b - pair.0.b) }
        let all = pairs.map(de)
        let paper = pairs.first { recipe($0.0, 0, 0, 0, 0) }.map(de)
        let solids = [pairs.first { recipe($0.0, 100, 0, 0, 0) }, pairs.first { recipe($0.0, 0, 100, 0, 0) }, pairs.first { recipe($0.0, 0, 0, 100, 0) }, pairs.first { recipe($0.0, 0, 0, 0, 100) }]
        let solidValues = solids.compactMap { $0 }.map(de)
        let hues = solids.prefix(3).compactMap { $0 }.map(hue)
        let neutral = pairs.filter { pair in
            let i = inks(pair.0); return i[3] == 0 && i[0] > 0 && i[1] > 0 && i[2] > 0 && abs(i[1] - i[2]) < 0.5 && i[1] < i[0]
        }.map(ch)
        func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        let checks = [
            Check(name: "Paper white", clause: "4.3.2", limit: 3.0, value: paper, unit: "ΔE00"),
            Check(name: "Solids C, M, Y, K", clause: "4.3.3", limit: 3.0, value: solidValues.count == 4 ? solidValues.max() : nil, unit: "ΔE00"),
            Check(name: "C, M, Y hue", clause: "4.3.3", limit: 2.5, value: hues.count == 3 ? hues.max() : nil, unit: "ΔH"),
            Check(name: "All patches, average", clause: "Table 2", limit: 2.5, value: mean(all), unit: "ΔE00"),
            Check(name: "All patches, maximum", clause: "Table 2", limit: 5.0, value: all.max(), unit: "ΔE00"),
            Check(name: "Neutral scale, maximum", clause: "Table 2", limit: 3.5, value: neutral.count >= 5 ? neutral.max() : nil, unit: "ΔCh"),
            Check(name: "Neutral scale, average", clause: "Table 2", limit: 2.0, value: neutral.count >= 5 ? mean(neutral) : nil, unit: "ΔCh"),
        ]
        return (checks, pairs.count, reference.patches.count - pairs.count)
    }

    // MARK: Check A Colour

    private var checkPalette: Swatch?
    private var checkHex: String?
    private var checkTolerance = 2.0
    private var checkCondition = PressProfiles.generic
    private var checkMode = "M1 · White backing"
    private let sampleL = NSTextField(string: ""), sampleA = NSTextField(string: ""), sampleB = NSTextField(string: "")
    private var sample: LabD50?
    private var decision: String?
    private let approve = SwissButton("Approve And Copy Record", .primary)
    private let reject = SwissButton("Reject", .secondary)
    private let importReading = SwissButton("Import Reading…", .secondary)
    private var checkMenus: [SwissDropdown] = []

    // MARK: Will It Print?

    private var printPalette: Swatch?
    private var printPress = PressProfiles.generic
    private var printIntent = RenderingIntent.relative
    private var printFlag = 2.0
    struct Held { let name: String; let master: LabD50; let printed: LabD50?; let ink: Double?; let difference: Double? }
    private var held: [Held] = []
    private let copyNote = SwissButton("Copy Note", .primary)
    private var printMenus: [SwissDropdown] = []

    // MARK: Layout model

    /// A section of the page that is showing: its name, how many rows it holds, and its thick rule's guide.
    private struct Section { let name: String; let rows: Int; var guide: CGFloat = 0 }
    private var sections: [Section] {
        var list: [Section]
        switch flow {
        case .menu: list = Self.routes.map { Section(name: $0.title, rows: $0.need.count + 4) }
        case .verify: list = [Section(name: "Condition", rows: 6), Section(name: "Measure", rows: 8), Section(name: "Result", rows: 12), Section(name: "Label", rows: 15)]
        case .check: list = [Section(name: "Master", rows: 9), Section(name: "Measure", rows: 9), Section(name: "Decide", rows: 10)]
        case .print: list = [Section(name: "Palette", rows: 9), Section(name: "Result", rows: max(4, held.count + 3)), Section(name: "Note", rows: 7)]
        case .press: list = [Section(name: "Condition", rows: 5), Section(name: "Measure", rows: 6), Section(name: "OK Sheet", rows: 5)]
        }
        var guide = firstGuide
        for i in list.indices { list[i].guide = guide; guide += max(5 * u, CGFloat(list[i].rows + 3) * u) }
        return list
    }
    private var endGuide: CGFloat { sections.last.map { $0.guide + max(5 * u, CGFloat($0.rows + 3) * u) } ?? firstGuide }
    var sectionAnchors: [(String, CGFloat)] { sections.map { ($0.name, $0.guide + 1) } }
    func height(forWidth width: CGFloat) -> CGFloat { endGuide + 5 * u }
    /// The baseline of the n-th row under a section's rule: the first two units in, as Shortcuts lays its rows.
    private func rowBaseline(_ section: Int, _ row: Int) -> CGFloat { sections[section].guide + 2 * u + CGFloat(row) * u }

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        for (b, a) in [(importMeasurement, #selector(importMeasurementTapped)), (exportReport, #selector(exportReportTapped)), (saveLabel, #selector(saveLabelTapped)), (backToMenu, #selector(backTapped)),
                       (approve, #selector(approveTapped)), (reject, #selector(rejectTapped)), (importReading, #selector(importReadingTapped)), (copyNote, #selector(copyNoteTapped))] {
            b.target = self; b.action = a; addSubview(b)
        }
        backToMenu.leadingArrow = true
        for f in [sampleL, sampleA, sampleB] {
            f.font = Design.font(17, .regular); f.textColor = Design.ink
            f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
            f.delegate = self; addSubview(f)
        }
        sampleL.placeholderAttributedString = Design.attributed("L*", .body, colour: Design.soft)
        sampleA.placeholderAttributedString = Design.attributed("a*", .body, colour: Design.soft)
        sampleB.placeholderAttributedString = Design.attributed("b*", .body, colour: Design.soft)
        addSubview(label)
        reference = Self.bundled(condition.file)
        enter()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() { refreshChoices(); needsLayout = true; needsDisplay = true; onResize?() }
    /// Arriving at a flow: the choices are rebuilt for it, the rest put away.
    private func enter() { problem = ""; refreshChoices(); recompute(); needsLayout = true; needsDisplay = true; onResize?() }

    // MARK: Controls

    private var menuSignature = ""
    /// The dropdowns of the flow showing, remade when the flow or the catalogue's palettes change.
    private func refreshChoices() {
        let palettes = library.library.listedPalettes.filter { !$0.isTypography }
        let signature = "\(flow.rawValue)|\(palettes.map { $0.id.uuidString + $0.name + "\($0.entries.count)" }.joined())|\(checkPalette?.id.uuidString ?? "")|\(printPalette?.id.uuidString ?? "")"
        guard signature != menuSignature else { return }
        menuSignature = signature
        for m in [conditionMenu].compactMap({ $0 }) + checkMenus + printMenus { m.removeFromSuperview() }
        conditionMenu = nil; checkMenus = []; printMenus = []
        let width = max(220, bounds.width - contentX)
        func menu(_ caption: String, value: String, options: [String], _ change: @escaping (String) -> Void) -> SwissDropdown {
            let m = SwissDropdown(caption, value: value, options: options, allowsOwn: false, width: width)
            m.onChange = change; addSubview(m); return m
        }
        let paletteNames = palettes.map { $0.name }
        switch flow {
        case .verify:
            conditionMenu = menu("Printing condition the proof simulates", value: condition.name, options: Self.conditions.map { $0.name }) { [weak self] value in
                guard let self, let c = Self.conditions.first(where: { $0.name == value }) else { return }
                self.condition = c; self.reference = Self.bundled(c.file); self.recompute(); self.needsDisplay = true
            }
        case .check:
            if checkPalette == nil { checkPalette = palettes.first }
            if checkHex == nil || !(checkPalette?.entries.contains { $0.hex == checkHex } ?? false) { checkHex = checkPalette?.entries.first?.hex }
            let colours = checkPalette?.entries.map { library.library.name(of: $0.hex, in: checkPalette?.id) } ?? []
            checkMenus = [
                menu("Palette", value: checkPalette?.name ?? "No palettes yet", options: paletteNames) { [weak self] value in
                    guard let self else { return }; self.checkPalette = palettes.first { $0.name == value }; self.checkHex = nil; self.menuSignature = ""; self.reload()
                },
                menu("Master colour", value: checkHex.map { library.library.name(of: $0, in: checkPalette?.id) } ?? "No colours yet", options: colours) { [weak self] value in
                    guard let self, let p = self.checkPalette, let i = colours.firstIndex(of: value) else { return }; self.checkHex = p.entries[i].hex; self.recompute(); self.needsDisplay = true
                },
                menu("Tolerance", value: Self.toleranceName(checkTolerance), options: Self.tolerances.map { Self.toleranceName($0) }) { [weak self] value in
                    guard let self, let t = Self.tolerances.first(where: { Self.toleranceName($0) == value }) else { return }; self.checkTolerance = t; self.recompute(); self.needsDisplay = true
                },
                menu("Printing condition of the sample", value: checkCondition, options: PressProfiles.all.map(\.name)) { [weak self] value in self?.checkCondition = value; self?.needsDisplay = true },
                menu("Measurement mode · Backing", value: checkMode, options: ["M0 · White backing", "M1 · White backing", "M2 · White backing", "M1 · Black backing"]) { [weak self] value in self?.checkMode = value; self?.needsDisplay = true },
            ]
        case .print:
            if printPalette == nil { printPalette = palettes.first }
            printMenus = [
                menu("Palette", value: printPalette?.name ?? "No palettes yet", options: paletteNames) { [weak self] value in
                    guard let self else { return }; self.printPalette = palettes.first { $0.name == value }; self.menuSignature = ""; self.recompute(); self.reload()
                },
                menu("Printing condition", value: printPress, options: PressProfiles.all.map(\.name)) { [weak self] value in self?.printPress = value; self?.recompute(); self?.reload() },
                menu("Rendering intent · BPC off", value: printIntent.name, options: [RenderingIntent.relative, .absolute, .perceptual].map(\.name)) { [weak self] value in
                    guard let self, let i = RenderingIntent.allCases.first(where: { $0.name == value }) else { return }; self.printIntent = i; self.recompute(); self.reload()
                },
                menu("Flag a colour further than", value: Self.toleranceName(printFlag), options: Self.tolerances.map { Self.toleranceName($0) }) { [weak self] value in
                    guard let self, let t = Self.tolerances.first(where: { Self.toleranceName($0) == value }) else { return }; self.printFlag = t; self.recompute(); self.reload()
                },
            ]
        default: break
        }
    }
    static let tolerances = [1.0, 1.5, 2.0, 3.0, 5.0]
    static func toleranceName(_ t: Double) -> String {
        let word = t <= 1 ? "Critical" : t <= 2 ? "Brand" : t <= 3 ? "Commercial" : "Loose"
        return String(format: "ΔE00 %.1f · %@", t, word)
    }

    /// Everything the flow works out from its inputs, in one place, so a change anywhere redraws the whole truth.
    private func recompute() {
        switch flow {
        case .verify:
            if let reference, let measurement {
                let r = Self.evaluate(reference: reference, measurement: measurement)
                checks = r.checks; matched = r.matched; missing = r.missing
                if missing > 0 { verdict = .failed("\(missing) of \(reference.patches.count) patches have no measurement") }
                else if let bad = checks.first(where: { $0.within == false }) { verdict = .failed(bad.name + " is outside " + String(format: "%.1f", bad.limit)) }
                else if checks.contains(where: { $0.value == nil }) { verdict = .failed("A check could not be made from this strip") }
                else { verdict = .passed }
            } else { checks = Self.evaluate(reference: reference ?? ProofDataset(name: "", source: "", sha256: "", metadata: [:], patches: []), measurement: ProofDataset(name: "", source: "", sha256: "", metadata: [:], patches: [])).checks; matched = 0; missing = reference?.patches.count ?? 0; verdict = .waiting }
            label.condition = condition.short
            label.job = measurement.map { ($0.name as NSString).deletingPathExtension } ?? "No measurement yet"
            label.checks = checks; label.verdict = verdict; label.measurement = measurement; label.needsDisplay = true
        case .check:
            sample = [sampleL, sampleA, sampleB].map { Double($0.stringValue.replacingOccurrences(of: ",", with: ".")) }.reduce(into: [Double]()) { if let d = $1 { $0.append(d) } }.count == 3
                ? LabD50(l: Double(sampleL.stringValue)!, a: Double(sampleA.stringValue.replacingOccurrences(of: ",", with: "."))!, b: Double(sampleB.stringValue.replacingOccurrences(of: ",", with: "."))!) : nil
        case .print:
            held = []
            guard let p = printPalette else { return }
            for e in p.entries {
                guard let d = ColourKeys.definition(of: e.hex) ?? ColourDefinition.of(hex: e.hex) else { continue }
                let master = d.master.lab
                let build = PrintBuild.of(d.master, press: printPress, intent: printIntent, blackPoint: false)
                let printed = build?.printed.lab
                held.append(Held(name: library.library.name(of: e.hex, in: p.id), master: master, printed: printed, ink: build?.totalInk, difference: printed.map { deltaE2000(master, $0) }))
            }
        default: break
        }
    }
    private var masterLab: LabD50? { checkHex.flatMap { ColourKeys.definition(of: $0) ?? ColourDefinition.of(hex: $0) }?.master.lab }

    // MARK: Layout

    override func layout() {
        super.layout()
        let x = contentX, w = bounds.width, available = max(220, w - x)
        for m in [conditionMenu].compactMap({ $0 }) + checkMenus + printMenus {
            for c in m.constraints where c.firstAttribute == .width { c.constant = available }
        }
        for b in [importMeasurement, exportReport, saveLabel, backToMenu, approve, reject, importReading, copyNote] { b.isHidden = true }
        for f in [sampleL, sampleA, sampleB] { f.isHidden = true }
        for m in checkMenus + printMenus { m.isHidden = true }
        conditionMenu?.isHidden = true
        label.isHidden = true
        let s = sections
        func place(_ b: SwissButton, x bx: CGFloat, baseline: CGFloat) { b.isHidden = false; b.frame = NSRect(x: bx, y: SettingsSheet.buttonTop(baseline: baseline), width: b.intrinsicContentSize.width, height: SwissButton.height) }
        func dropdown(_ m: SwissDropdown, baseline: CGFloat) { m.isHidden = false; m.frame = NSRect(x: x, y: baseline - 11, width: available, height: 56) }
        switch flow {
        case .menu:
            break
        case .verify:
            if let m = conditionMenu { dropdown(m, baseline: rowBaseline(0, 0)) }
            place(importMeasurement, x: x, baseline: rowBaseline(1, 0))
            place(exportReport, x: x, baseline: rowBaseline(2, 11))
            label.isHidden = false
            label.frame = NSRect(x: x, y: rowBaseline(3, 0) - Self.line, width: min(available, 520), height: 12 * u)
            place(saveLabel, x: x, baseline: rowBaseline(3, 13))
            place(backToMenu, x: saveLabel.frame.maxX + 24, baseline: rowBaseline(3, 13))
        case .check:
            for (i, m) in checkMenus.enumerated() where i < 3 { dropdown(m, baseline: rowBaseline(0, i * 2)) }
            if checkMenus.count >= 5 { dropdown(checkMenus[3], baseline: rowBaseline(1, 0)); dropdown(checkMenus[4], baseline: rowBaseline(1, 2)) }
            let third = (available - 32) / 3
            for (i, f) in [sampleL, sampleA, sampleB].enumerated() { f.isHidden = false; f.frame = NSRect(x: x + CGFloat(i) * (third + 16), y: rowBaseline(1, 5) - 17, width: third, height: 24) }
            place(importReading, x: x, baseline: rowBaseline(1, 7))
            place(approve, x: x, baseline: rowBaseline(2, 7))
            place(reject, x: approve.frame.maxX + 16, baseline: rowBaseline(2, 7))
            place(backToMenu, x: x, baseline: rowBaseline(2, 9))
        case .print:
            for (i, m) in printMenus.enumerated() { dropdown(m, baseline: rowBaseline(0, i * 2)) }
            place(copyNote, x: x, baseline: rowBaseline(2, 5))
            place(backToMenu, x: copyNote.frame.maxX + 24, baseline: rowBaseline(2, 5))
        case .press:
            place(backToMenu, x: x, baseline: rowBaseline(2, 3))
        }
        _ = s
    }

    // MARK: Drawing

    private func text(_ s: String, x: CGFloat, baseline: CGFloat, style: Design.Text = .body, colour: NSColor = Design.ink, width: CGFloat? = nil) {
        Design.attributed(s, style, colour: colour).draw(x: x, baseline: baseline, width: width ?? bounds.width - x)
    }
    /// A numeral or a short value flush to the right edge of its block, as the alignment law asks.
    private func right(_ s: String, edge: CGFloat, baseline: CGFloat, style: Design.Text = .body, colour: NSColor = Design.ink) {
        let a = Design.attributed(s, style, colour: colour)
        a.draw(x: edge - a.size().width, baseline: baseline)
    }
    /// A row as Shortcuts draws one: the name on the content column, the value on the first column past the middle, a hairline under.
    private func row(_ title: String, _ value: String, baseline b: CGFloat, quiet: Bool = false, strong: Bool = false, valueAt: CGFloat = 0.5) {
        let x = contentX, w = bounds.width, valueX = column(at: valueAt)
        text(title, x: x, baseline: b, width: valueX - x - 16)
        text(value, x: valueX, baseline: b, style: strong ? .bodyStrong : .body, colour: quiet ? Design.quiet : Design.ink, width: w - valueX)
        hairline(x: x, y: b + u - Self.line - 1, width: w - x, Design.rule)
    }
    private func number(_ d: Double?, _ places: Int = 1) -> String { d.map { String(format: "%.\(places)f", $0) } ?? "—" }
    private func lead(_ words: String, section i: Int) {
        // The step's words on the left, under its number, in a box of four lines that never grows.
        SettingsSheet.paragraph(words, x: 0, firstBaseline: rowBaseline(i, 2), width: max(0, min(contentX - Design.App.areaGutter, 400)), height: 4 * u, colour: Design.quiet)
    }

    override func draw(_ dirtyRect: NSRect) {
        let x = contentX, w = bounds.width
        let s = sections
        switch flow {
        case .menu:
            SettingsSheet.title("PrePress.")
            SettingsSheet.introduction("Which job is it?", "Four workflows, one artefact each. Pick the job in hand.", x: x, width: w)
            for (i, route) in Self.routes.enumerated() {
                SettingsSheet.section(i + 1, route.title, guide: s[i].guide, contentX: x, width: w)
                var r = 0
                row("Who", route.who, baseline: rowBaseline(i, r), quiet: true, valueAt: 0.3); r += 1
                for (n, need) in route.need.enumerated() { row(n == 0 ? "In your hand" : "", need, baseline: rowBaseline(i, r), valueAt: 0.3); r += 1 }
                row("You get", route.get, baseline: rowBaseline(i, r), strong: true, valueAt: 0.3); r += 1
                drawStart(route, baseline: rowBaseline(i, r + 1))
            }
        case .verify: drawVerify(s)
        case .check: drawCheck(s)
        case .print: drawPrint(s)
        case .press: drawPress(s)
        }
        SettingsSheet.divider(above: endGuide, width: w)
        if !problem.isEmpty { text(problem, x: x, baseline: endGuide + u, style: .caption, colour: Design.ink) }
        else if flow != .menu { text("Every figure on this page is measured or worked out from the catalogue.", x: x, baseline: endGuide + u, style: .caption, colour: Design.quiet) }
    }

    // The menu's Start is a drawn primary button per route: one view each would be four buttons for one job, so the page draws
    // them from the house button's own numbers and keeps the hit rects.
    private var startRects: [(NSRect, Flow)] = []
    private func drawStart(_ route: Route, baseline b: CGFloat) {
        let title = Design.attributed(route.steps.joined(separator: " · "), .caption, colour: Design.quiet)
        title.draw(x: column(at: 0.5), baseline: b, width: bounds.width - column(at: 0.5))
        let action = Design.attributed(route.title, .action, colour: Design.card)
        let width = ceil(action.size().width) + 28 + 32
        let rect = NSRect(x: contentX, y: SettingsSheet.buttonTop(baseline: b), width: width, height: SwissButton.height)
        fill(rect, Design.ink)
        action.draw(x: rect.minX + 14, baseline: b)
        fill(NSRect(x: rect.maxX - 32, y: rect.minY, width: 1, height: rect.height), Design.card.withAlphaComponent(0.18))
        Design.arrow(14, colour: Design.card).draw(in: NSRect(x: rect.maxX - 23, y: rect.midY - 7, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        startRects.append((rect, route.flow))
    }

    private func drawVerify(_ s: [Section]) {
        let x = contentX, w = bounds.width
        SettingsSheet.title("Verify A Proof.")
        SettingsSheet.introduction("Prepress · ISO 12647-7:2016", "Condition, measure, result, label. The standard sets the tolerances.", x: x, width: w)
        // 01 Condition: the dropdown takes rows 0 and 1; the strip's facts follow.
        SettingsSheet.section(1, "Condition", guide: s[0].guide, contentX: x, width: w)
        lead("Every proof simulates one printing condition. Pick the one the job was made for; the reference values and the tolerances follow from it. Nothing here is a user's opinion.", section: 0)
        row("Control strip", "MediaWedge CMYK V3 · \(reference?.patches.count ?? 0) patches", baseline: rowBaseline(0, 3))
        row("Reference measured", reference?.conditions ?? "Reference not found in the app bundle", baseline: rowBaseline(0, 4), quiet: reference == nil)
        row("Tolerances", "ISO 12647-7:2016 · CIEDE2000", baseline: rowBaseline(0, 5))
        // 02 Measure
        SettingsSheet.section(2, "Measure", guide: s[1].guide, contentX: x, width: w)
        lead("Measure the wedge, \(condition.strip), and bring the file in. Each patch matches the reference by its ID, never by position. A patch that is missing is never counted as a pass.", section: 1)
        let m = measurement
        row("Measurement file", m?.name ?? "None imported", baseline: rowBaseline(1, 2), quiet: m == nil)
        row("Patches matched by ID", m == nil ? "—" : "\(matched) of \(reference?.patches.count ?? 0)" + (missing > 0 ? " · \(missing) missing" : " · Complete"), baseline: rowBaseline(1, 3), strong: missing > 0)
        row("Illuminant · Observer", m.map { ($0.metadata["ILLUMINATION_NAME"] ?? "Not declared") + " · " + ($0.metadata["OBSERVER_ANGLE"].map { $0 + "°" } ?? "Not declared") } ?? "—", baseline: rowBaseline(1, 4))
        row("Measurement mode", m.map { $0.metadata["FILTER"] ?? $0.metadata["MEASUREMENT_CONDITION"] ?? "Not declared" } ?? "—", baseline: rowBaseline(1, 5))
        row("Backing", m.map { $0.metadata["MEASUREMENT_BACKING"] ?? "Not declared" } ?? "—", baseline: rowBaseline(1, 6))
        row("Instrument", m.map { $0.metadata["INSTRUMENTATION"] ?? $0.metadata["ORIGINATOR"] ?? "Not declared" } ?? "—", baseline: rowBaseline(1, 7))
        // 03 Result: the verdict in a one-line box, two figures, then the seven checks with their clauses.
        SettingsSheet.section(3, "Result", guide: s[2].guide, contentX: x, width: w)
        let verdictWords: String, verdictColour: NSColor
        switch verdict {
        case .waiting: verdictWords = "Waiting for a measurement"; verdictColour = Design.quiet
        case .passed: verdictWords = "Passes ISO 12647-7"; verdictColour = Design.ink
        case .failed: verdictWords = "Does not pass ISO 12647-7"; verdictColour = Design.ink
        }
        text(verdictWords, x: x, baseline: rowBaseline(2, 0), style: .headline, colour: verdictColour)
        if case .failed(let why) = verdict { text(why, x: x, baseline: rowBaseline(2, 1), style: .caption, colour: Design.quiet) }
        else { text(m == nil ? "Import the measurement under 02 to see the seven checks." : "All seven checks are within the standard's tolerances; the label carries the figures as they stand.", x: x, baseline: rowBaseline(2, 1), style: .caption, colour: Design.quiet) }
        // The check over two columns, the tolerance with its clause on the third, the measured figure and its verdict on the fourth.
        let tolX = column(at: 0.5), measX = column(at: 0.75)
        let head = rowBaseline(2, 2)
        text("Check", x: x, baseline: head, style: .caption, colour: Design.quiet)
        text("Tolerance · Clause", x: tolX, baseline: head, style: .caption, colour: Design.quiet)
        text("Measured", x: measX, baseline: head, style: .caption, colour: Design.quiet)
        hairline(x: x, y: head + u - Self.line - 1, width: w - x, Design.rule)
        for (i, c) in checks.enumerated() {
            let b = rowBaseline(2, 3 + i)
            text(c.name + " · " + c.unit, x: x, baseline: b, width: tolX - x - 16)
            text("≤ " + number(c.limit) + " · " + c.clause, x: tolX, baseline: b, width: measX - tolX - 16)
            let verdictWord = c.within.map { $0 ? "Within" : "Outside" } ?? (m == nil ? "" : "Not in strip")
            text(number(c.value, 2) + (verdictWord.isEmpty ? "" : " · " + verdictWord), x: measX, baseline: b, style: c.within == false ? .bodyStrong : .body, colour: c.value == nil ? Design.quiet : Design.ink, width: w - measX)
            hairline(x: x, y: b + u - Self.line - 1, width: w - x, Design.rule)
        }
        text("Clauses of ISO 12647-7:2016, verified against its text on 12 Oct 2026.", x: x, baseline: rowBaseline(2, 10), style: .caption, colour: Design.quiet)
        // 04 Label
        SettingsSheet.section(4, "Label", guide: s[3].guide, contentX: x, width: w)
        lead("The label is the artefact. It names the standard, the condition, the figures, the instrument and the file, and it is stuck to the proof. The same record goes in the report.", section: 3)
    }

    private func drawCheck(_ s: [Section]) {
        let x = contentX, w = bounds.width
        SettingsSheet.title("Check A Colour.")
        SettingsSheet.introduction("Brand owner · Agency · Printer", "The master never moves. A sample is measured against it and a person decides.", x: x, width: w)
        SettingsSheet.section(1, "Master", guide: s[0].guide, contentX: x, width: w)
        lead("Pick the swatch. Its master is the colour as the brand defined it, in Lab D50; the brand book says how far a print may stray from it.", section: 0)
        if let lab = masterLab, let hex = checkHex {
            let box = NSRect(x: x, y: rowBaseline(0, 6) - Self.line, width: 2 * u, height: 2 * u)
            fill(box, Design.hex(hex)); Design.ink.setStroke(); NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
            text("Master · L* a* b*", x: box.maxX + 16, baseline: rowBaseline(0, 6), style: .caption, colour: Design.quiet)
            text(String(format: "%.2f · %.2f · %.2f", lab.l, lab.a, lab.b), x: box.maxX + 16, baseline: rowBaseline(0, 7), style: .bodyStrong)
        } else { text("No colour chosen. The catalogue needs a palette with at least one colour.", x: x, baseline: rowBaseline(0, 6), style: .caption, colour: Design.quiet) }
        SettingsSheet.section(2, "Measure", guide: s[1].guide, contentX: x, width: w)
        lead("Measure the printed sample, or bring in the supplier's reading. The mode and backing are recorded with the value, so an M0 reading is never compared to an M1 master without saying so.", section: 1)
        text("Sample · L* a* b* · type the reading, or import a one-patch CGATS file", x: x, baseline: rowBaseline(1, 4), style: .caption, colour: Design.quiet)
        hairline(x: x, y: rowBaseline(1, 5) + 6, width: w - x, Design.rule)
        if let m = masterLab {
            // The master and the sample side by side, as previews only, beside the typed reading.
            let a = NSRect(x: column(at: 0.5), y: rowBaseline(1, 6) - Self.line, width: 3 * u, height: 2 * u), b = a.offsetBy(dx: 3 * u + 16, dy: 0)
            fill(a, m.xyz.display); fill(b, sample?.xyz.display ?? Design.mist)
            Design.ink.setStroke(); NSBezierPath(rect: a.insetBy(dx: 0.5, dy: 0.5)).stroke(); NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)).stroke()
            text("Master", x: a.minX, baseline: rowBaseline(1, 8), style: .caption, colour: Design.quiet)
            text("Sample", x: b.minX, baseline: rowBaseline(1, 8), style: .caption, colour: Design.quiet)
        }
        SettingsSheet.section(3, "Decide", guide: s[2].guide, contentX: x, width: w)
        lead("The difference is the standard's CIEDE2000, master first. The decision is a person's; the page records it, it does not make it.", section: 2)
        if let m = masterLab, let sm = sample {
            let d = deltaE2000(m, sm), dl = sm.l - m.l, da = sm.a - m.a, db = sm.b - m.b
            text(d <= checkTolerance ? "Within the brand tolerance" : "Outside the brand tolerance", x: x, baseline: rowBaseline(2, 0), style: .headline)
            text(String(format: "ΔE00 %.2f · tolerance %.1f", d, checkTolerance), x: x, baseline: rowBaseline(2, 1), style: .bodyStrong)
            func direction(_ v: Double, _ up: String, _ down: String, _ same: String) -> String { abs(v) < 0.05 ? same : v > 0 ? up : down }
            text([direction(dl, "lighter", "darker", "same lightness"), direction(da, "redder", "greener", "same a*"), direction(db, "yellower", "bluer", "same b*")].joined(separator: " · ") + String(format: "   ΔL %.2f · Δa %.2f · Δb %.2f", dl, da, db), x: x, baseline: rowBaseline(2, 2), style: .caption, colour: Design.quiet)
        } else { text("Type or import a sample under 02 to see the difference.", x: x, baseline: rowBaseline(2, 0), style: .caption, colour: Design.quiet) }
        row("Condition", checkCondition, baseline: rowBaseline(2, 4))
        row("Mode · Backing", checkMode, baseline: rowBaseline(2, 5))
        row("Decision", decision ?? "Not yet decided", baseline: rowBaseline(2, 6), quiet: decision == nil, strong: decision != nil)
        text("Approve copies the record; the swatch keeps it once the approvals model is built.", x: x, baseline: rowBaseline(2, 8), style: .caption, colour: Design.quiet)
    }

    private func drawPrint(_ s: [Section]) {
        let x = contentX, w = bounds.width
        SettingsSheet.title("Will It Print?")
        SettingsSheet.introduction("Designer · Before anything is printed", "A prediction through the press profile, not a proof. For the start of a job.", x: x, width: w)
        SettingsSheet.section(1, "Palette", guide: s[0].guide, contentX: x, width: w)
        lead("Choose the palette and the press it is going to. The check says which colours that condition can hold and how far the rest will fall.", section: 0)
        SettingsSheet.section(2, "Result", guide: s[1].guide, contentX: x, width: w)
        let outside = held.filter { ($0.difference ?? .infinity) > printFlag }.count
        if held.isEmpty { text("No palette chosen, or the press profile is not on this Mac.", x: x, baseline: rowBaseline(1, 0), style: .caption, colour: Design.quiet) }
        else { text(outside == 0 ? "All \(held.count) hold" : "\(outside) of \(held.count) outside", x: x, baseline: rowBaseline(1, 0), style: .headline) }
        let inkX = column(at: 0.5), deX = column(at: 0.75)
        let head = rowBaseline(1, 1)
        text("Colour · master, then printed", x: x, baseline: head, style: .caption, colour: Design.quiet)
        text("Total ink", x: inkX, baseline: head, style: .caption, colour: Design.quiet)
        text("ΔE00 · Holds", x: deX, baseline: head, style: .caption, colour: Design.quiet)
        hairline(x: x, y: head + u - Self.line - 1, width: w - x, Design.rule)
        for (i, h) in held.enumerated() {
            let b = rowBaseline(1, 2 + i)
            let a = NSRect(x: x, y: b - 14, width: 14, height: 18), p = a.offsetBy(dx: 16, dy: 0)
            fill(a, h.master.xyz.display); fill(p, h.printed?.xyz.display ?? Design.mist)
            text(h.name, x: x + 40, baseline: b, width: inkX - x - 56)
            text(h.ink.map { String(format: "%.0f%%", $0) } ?? "—", x: inkX, baseline: b)
            let holds = h.difference.map { $0 <= printFlag }
            text(number(h.difference, 1) + " · " + (holds.map { $0 ? "Yes" : "No" } ?? "No profile"), x: deX, baseline: b, style: holds == false ? .bodyStrong : .body, colour: holds == nil ? Design.quiet : Design.ink, width: w - deX)
            hairline(x: x, y: b + u - Self.line - 1, width: w - x, Design.rule)
        }
        SettingsSheet.section(3, "Note", guide: s[2].guide, contentX: x, width: w)
        lead("The palette carries the check: the condition, the date, which colours were flagged and by how much. The decision travels with the colours, not in an email.", section: 2)
        for (i, line) in noteLines.prefix(4).enumerated() { text(line, x: x, baseline: rowBaseline(2, i), style: i == 0 ? .bodyStrong : .body, colour: Design.ink) }
    }
    private var noteLines: [String] {
        guard let p = printPalette else { return ["No palette chosen"] }
        let flagged = held.filter { ($0.difference ?? .infinity) > printFlag }
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        var lines = ["Gamut check · " + p.name + " · " + date, printPress + " · " + printIntent.name + String(format: " · flagged past ΔE00 %.1f", printFlag),
                     flagged.isEmpty ? "Every colour holds" : flagged.map { String(format: "%@ %.1f", $0.name, $0.difference ?? 0) }.joined(separator: " · ")]
        if flagged.count > 3 { lines.append("\(flagged.count) colours flagged in all") }
        return lines
    }

    private func drawPress(_ s: [Section]) {
        let x = contentX, w = bounds.width
        SettingsSheet.title("Press Check.")
        SettingsSheet.introduction("Press operator · ISO 12647-2 · Later release", "The pressroom's workflow in its own words: density, dot gain, grey.", x: x, width: w)
        SettingsSheet.section(1, "Condition", guide: s[0].guide, contentX: x, width: w)
        lead("Pick the printing condition and the colour bar on the sheet. ISO 12647-2 sets the solids, the tone value increase and the grey balance the press has to hold.", section: 0)
        row("Printing condition", "The condition's aims, e.g. FOGRA51", baseline: rowBaseline(0, 0), quiet: true, valueAt: 0.3)
        row("Colour bar", "Solids, 50% tints, grey, overprints", baseline: rowBaseline(0, 1), quiet: true, valueAt: 0.3)
        row("Instrument", "A spectrodensitometer the app reads", baseline: rowBaseline(0, 2), quiet: true, valueAt: 0.3)
        SettingsSheet.section(2, "Measure", guide: s[1].guide, contentX: x, width: w)
        lead("Solids by ΔE00, tone value increase by the deviation from the curve, grey balance by ΔCh. Density is read from the same pass and kept for the operator, measured, never modelled.", section: 1)
        row("Solids", "ΔE00 from the condition's aims", baseline: rowBaseline(1, 0), quiet: true, valueAt: 0.3)
        row("Tone value increase", "Deviation from the curve at 50%, per ink", baseline: rowBaseline(1, 1), quiet: true, valueAt: 0.3)
        row("Grey balance", "ΔCh of the three-colour grey", baseline: rowBaseline(1, 2), quiet: true, valueAt: 0.3)
        row("Density", "C · M · Y · K as the operator ran them", baseline: rowBaseline(1, 3), quiet: true, valueAt: 0.3)
        SettingsSheet.section(3, "OK Sheet", guide: s[2].guide, contentX: x, width: w)
        lead("The OK sheet says the run was started within the condition, by whom, and at what densities, so the run can be held there. A later sheet is checked against it, not against memory.", section: 2)
        row("Needs", "An instrument the app reads", baseline: rowBaseline(2, 0), quiet: true, valueAt: 0.3)
        row("Gets", "Every reading, the densities, who signed", baseline: rowBaseline(2, 1), quiet: true, valueAt: 0.3)
    }

    // MARK: Actions

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if flow == .menu, let hit = startRects.first(where: { $0.0.contains(p) }) { onNavigate?(hit.1.rawValue); return }
        super.mouseDown(with: event)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        for (r, _) in startRects { addCursorRect(r, cursor: .pointingHand) }
    }
    override func viewWillDraw() { super.viewWillDraw(); startRects = []; window?.invalidateCursorRects(for: self) }
    @objc private func backTapped() { onNavigate?(0) }

    private func open(_ title: String, _ message: String) -> URL? {
        let panel = NSOpenPanel(); panel.title = title; panel.message = message; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    private func read(_ url: URL) throws -> ProofDataset {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 12_000_000 else { throw ProofError.invalid("Maximum file size is 12 MB.") }
        return try ProofImport.read(try Data(contentsOf: url), name: url.lastPathComponent)
    }
    @objc private func importMeasurementTapped() {
        guard let url = open("Import The Measured Wedge", "CGATS or CSV: SAMPLE_ID, LAB_L, LAB_A, LAB_B. Patches match the reference by ID.") else { return }
        do {
            let set = try read(url)
            if let i = set.metadata["ILLUMINATION_NAME"], i.uppercased() != "D50" { throw ProofError.invalid("\(set.name) declares \(i). The reference is D50 / 2°; measure again or convert before import.") }
            if let o = set.metadata["OBSERVER_ANGLE"], !["2", "2.0"].contains(o) { throw ProofError.invalid("\(set.name) declares a \(o)° observer. The reference is D50 / 2°.") }
            measurement = set; problem = ""
        } catch { problem = error.localizedDescription }
        recompute(); needsDisplay = true; needsLayout = true; onResize?()
    }
    @objc private func exportReportTapped() {
        guard let reference, let measurement else { problem = "Import a measurement first."; needsDisplay = true; return }
        var lines = [["Colorgain proof report", DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)],
                     ["Standard", "ISO 12647-7:2016", "All differences CIEDE2000 (4.1)"],
                     ["Condition", condition.name], ["Reference", reference.source, "SHA-256", reference.sha256],
                     ["Measurement", measurement.name, "SHA-256", measurement.sha256], ["Measurement conditions", measurement.conditions],
                     ["Verdict", { switch verdict { case .passed: return "Passed"; case .failed(let why): return "Failed · " + why; case .waiting: return "Waiting" } }()],
                     ["Check", "Clause", "Unit", "Tolerance", "Measured", "Result"]]
        lines += checks.map { [$0.name, $0.clause, $0.unit, number($0.limit), number($0.value, 3), $0.within.map { $0 ? "Within" : "Outside" } ?? "Not in strip"] }
        lines.append(["ID", "Name", "Reference L", "a", "b", "Measured L", "a", "b", "ΔE00"])
        let measured = Dictionary(measurement.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in reference.patches {
            let m = measured[r.id]
            lines.append([r.id, r.name, number(r.l, 2), number(r.a, 2), number(r.b, 2), number(m?.l, 2), number(m?.a, 2), number(m?.b, 2), number(m.map { deltaE2000(r.lab, $0.lab) }, 3)])
        }
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let csv = lines.map { $0.map(q).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        save(Data(csv.utf8), name: "Proof Report.csv", type: .commaSeparatedText)
    }
    @objc private func saveLabelTapped() {
        guard measurement != nil else { problem = "Import a measurement first; the label carries its figures."; needsDisplay = true; return }
        label.layoutSubtreeIfNeeded()
        save(label.dataWithPDF(inside: label.bounds), name: "Proof Label.pdf", type: .pdf)
    }
    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { try data.write(to: url, options: .atomic); problem = "Saved " + url.lastPathComponent } catch { problem = error.localizedDescription }
        needsDisplay = true
    }
    func controlTextDidEndEditing(_ obj: Notification) { recompute(); needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { recompute(); needsDisplay = true }
    @objc private func importReadingTapped() {
        guard let url = open("Import A Reading", "A CGATS or CSV file; the first patch is the sample.") else { return }
        do {
            let set = try read(url)
            guard let first = set.patches.first else { throw ProofError.invalid("The file holds no patch.") }
            sampleL.stringValue = String(format: "%.2f", first.l); sampleA.stringValue = String(format: "%.2f", first.a); sampleB.stringValue = String(format: "%.2f", first.b)
            if let f = set.metadata["FILTER"] { checkMode = f + " · " + (set.metadata["MEASUREMENT_BACKING"].map { $0.capitalized + " backing" } ?? "Backing not declared"); checkMenus.last?.displayValue(checkMode) }
            problem = ""
        } catch { problem = error.localizedDescription }
        recompute(); needsDisplay = true
    }
    private var checkRecord: String? {
        guard let p = checkPalette, let hex = checkHex, let m = masterLab, let sm = sample else { return nil }
        let d = deltaE2000(m, sm)
        return [decision ?? "Undecided", library.library.name(of: hex, in: p.id) + " · " + p.name,
                String(format: "Master L %.2f a %.2f b %.2f · Sample L %.2f a %.2f b %.2f · ΔE00 %.2f · tolerance %.1f", m.l, m.a, m.b, sm.l, sm.a, sm.b, d, checkTolerance),
                checkCondition + " · " + checkMode, DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)].joined(separator: "\n")
    }
    @objc private func approveTapped() { decide("Approved") }
    @objc private func rejectTapped() { decide("Rejected") }
    private func decide(_ word: String) {
        guard sample != nil, masterLab != nil else { problem = "Type or import a sample first."; needsDisplay = true; return }
        decision = word
        if let record = checkRecord { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record, forType: .string); library.flash(word + " · record copied") }
        needsDisplay = true
    }
    @objc private func copyNoteTapped() {
        let note = noteLines.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note, forType: .string)
        library.flash("Note copied")
    }
}

/// The proof label: what is stuck to the proof. Drawn on the page and written as the PDF, from the same view.
final class ProofLabelView: NSView {
    var condition = "", job = "", checks: [PrePressPage.Check] = [], verdict: PrePressPage.Verdict = .waiting
    var measurement: ProofDataset?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds, Design.card)
        Design.ink.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let x: CGFloat = 20, w = bounds.width - 40
        let passed: Bool? = { switch verdict { case .passed: return true; case .failed: return false; case .waiting: return nil } }()
        Design.attributed(passed == true ? "Proof verified" : passed == false ? "Proof not verified" : "Proof label", .label).draw(x: x, baseline: 30)
        let std = Design.attributed("ISO 12647-7:2016", .caption, colour: Design.quiet)
        std.draw(x: x + w - std.size().width, baseline: 30)
        hairline(x: x, y: 40, width: w, Design.ink)
        Design.attributed(job, .headline).draw(x: x, baseline: 78, width: w)
        func value(_ name: String) -> String { checks.first { $0.name == name }.flatMap { $0.value }.map { String(format: "%.1f", $0) } ?? "—" }
        let cells: [(String, String)] = [
            ("Simulates", condition),
            ("Result", passed == true ? "Passed · 7 of 7 checks" : passed == false ? "Failed" : "No measurement"),
            ("Average · Maximum ΔE00", value("All patches, average") + " · " + value("All patches, maximum")),
            ("Paper · Solids · CMY hue ΔH", value("Paper white") + " · " + value("Solids C, M, Y, K") + " · " + value("C, M, Y hue")),
            ("Grey ΔCh max · avg", value("Neutral scale, maximum") + " · " + value("Neutral scale, average")),
            ("Measured", measurement?.conditions ?? "—"),
            ("Measurement file", measurement?.name ?? "—"),
            ("Software", "Colorgain 3.0 · Fogra data, unmodified"),
        ]
        let colW = (w - 16) / 2
        for (i, cell) in cells.enumerated() {
            let cx = x + CGFloat(i % 2) * (colW + 16), top: CGFloat = 104 + CGFloat(i / 2) * 44
            Design.attributed(cell.0, .caption, colour: Design.quiet).draw(x: cx, baseline: top, width: colW)
            Design.attributed(cell.1, .bodyStrong).draw(x: cx, baseline: top + 18, width: colW)
        }
        let bar = NSRect(x: x, y: bounds.height - 30, width: w, height: 10)
        hairline(x: x, y: bar.minY - 10, width: w, Design.rule)
        let inks = [Design.hex("#00A0E3"), Design.hex("#E5007E"), Design.hex("#FFEF00"), Design.ink, Design.hex("#7C7C7C"), Design.card]
        let cw = (bar.width - CGFloat(inks.count - 1) * 2) / CGFloat(inks.count)
        for (i, c) in inks.enumerated() {
            let r = NSRect(x: bar.minX + CGFloat(i) * (cw + 2), y: bar.minY, width: cw, height: bar.height)
            fill(r, c); if i == inks.count - 1 { Design.rule.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke() }
        }
    }
}
