import AppKit
import UniformTypeIdentifiers

// ---------- Export and Import, as a wizard in the page ----------
//
// Drawn as the Schema page is: two columns at 60 and 40 on Master Inner, first-order headers on the first line with
// their words in a box of three units, second-order headers on a rule, every row on the beat. The left is the step
// in hand: the levels on offer, the tree of what goes or comes with a square tick on every row down to each palette,
// the files and their check, the twins with an answer each, the places it may land, the sums, the result. The right
// is the steps, the one in hand on the pane, the words for it in a fixed box, and Back and Next.
//
// Export: Level, Contents, Options, Check, Save. Import: Choose, Contents, Check, Twins, Placement, Confirm, Done.
// Nothing is written to the catalogue before Confirm, and the import goes in as one change the history can undo.

final class SharePage: ClickCursorView, PageSection, Overlay {
    override var handCursorRects:[NSRect]{steps[step] == "Done" ? []:Array(stepRects.prefix(step))}

    enum Mode { case export, bringIn }
    struct Level { let level: ShareLevel; let subject: UUID?; let name: String }

    private let library: LibraryController
    var onResize: (() -> Void)?
    /// The page is done with: back to where the user came from.
    var onLeave: (() -> Void)?
    var leading: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    private var mode = Mode.export
    var pageTitle: String { mode == .export ? "Export" : "Import" }
    private var carryAssets = false
    private var carryAppbridge = false
    private var importedName: String?
    var didImportCatalogue: Bool { importedName != nil }
    private var standalone: Bool { mode == .bringIn && level == .catalogue }
    private var exportLibrary: Library {
        if carryAssets || level == .palette { return library.library }
        var local = GlobalAssets.split(library.library).local
        let tags = Set(local.swatches.flatMap { $0.tags ?? [] } + local.colours.flatMap { $0.tags ?? [] })
        local.tagInfo = library.library.tagInfo.filter { $0.projectID != nil || $0.groupID != nil || tags.contains($0.name) }
        return local
    }
    private var aseSelection = Set<UUID>()
    private var restoreASELocations = false
    private var aseLinks: [AppbridgeStore.Source] {
        if mode == .bringIn { return staged?.aseLinks ?? [] }
        return (try? ASERegistry.resolved(library.store.root).filter { !$0.folder }) ?? []
    }
    private func aseFiles() throws -> [Zip.Entry] {
        guard carryAppbridge && level == .catalogue else { return [] }
        return try ASERegistry.harvest(root: library.store.root, selected: aseSelection)
    }
    private func aseRows() -> [Row] {
        let links = aseLinks
        var result = [Row(text: "Select All ASE Files", act: .aseAll(true)), Row(text: "Deselect All ASE Files", act: .aseAll(false))]
        let grouped = Dictionary(grouping: links) { URL(fileURLWithPath: $0.originalPath ?? $0.path).deletingLastPathComponent().path }
        for folder in grouped.keys.sorted() {
            let children = grouped[folder]!.sorted { $0.path < $1.path }
            result.append(Row(text: folder, strong: true, square: children.allSatisfy { aseSelection.contains($0.id) }, act: .aseGroup(folder)))
            result += children.map { source in
                Row(text: URL(fileURLWithPath: source.path).lastPathComponent, level: 1, square: aseSelection.contains(source.id), mark: "colorgain.ase", act: .ase(source.id), warning: mode == .export && !FileManager.default.fileExists(atPath: source.url.path))
            }
        }
        return result
    }
    private var levels: [Level] = []
    private var levelIndex = 0
    private var tree: ShareNode?
    private var ticked = Set<String>()
    private var step = 0
    private var carryTags = true, carryNotes = true
    private var chosenFile: URL?
    private var inspection: Sharing.Inspection?
    private var staging: URL?
    private var staged: Sharing.Staged?
    private var placements: [(Sharing.Placement, String)] = []
    private var placementIndex = 0
    private var twins: [Sharing.Duplicate] = []
    private var resolutions: [UUID: Sharing.Resolution] = [:]
    private var otherwise = Sharing.Resolution.keepBoth
    private var outcome: Sharing.Outcome?
    private var savedTo: URL?
    private var problem: String?

    private var steps: [String] { mode == .export ? ["Level", "Contents", "Options", "Check", "Save"] : standalone ? ["Choose", "Contents", "Check", "Confirm", "Done"] : ["Choose", "Contents", "Check", "Twins", "Placement", "Confirm", "Done"] }
    private var level: ShareLevel { mode == .export ? (levels.indices.contains(levelIndex) ? levels[levelIndex].level : .palette) : (inspection?.manifest.level ?? .palette) }

    // MARK: The views

    private let scroll = FittedScrollView()
    private let canvas = Canvas()
    private let cancel = SwissButton("Cancel", .secondary)
    private let back = SwissButton("Back", .secondary)
    private let next = SwissButton("Next", .primary)
    private var dropped: SwissDropdown.MenuPanel?
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeMenu() }
    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }
    private func openMenu(under rect: NSRect, items: [String], chosen: String, pick: @escaping (Int) -> Void) {
        guard let win = window else { return }
        closeMenu()
        let w = max(180, rect.width)
        let panel = SwissDropdown.MenuPanel(items: items, chosen: chosen, width: w) { [weak self] i in self?.closeMenu(); pick(i) }
        let s = win.convertToScreen(canvas.convert(rect, to: nil))
        panel.place(below: NSPoint(x: s.maxX - w, y: s.minY - 4))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }

    /// A row of the left column, as the step lays it out.
    private struct Row {
        enum Act { case none, level(Int), tick(String), option(Int), placement(Int), answer(UUID?), ase(UUID), aseGroup(String), aseAll(Bool) }
        var text: String
        var caption: String?
        var level = 0
        var node: ShareNode?
        var strong = false
        var square: Bool? = nil     // nil none; true filled; false empty
        var partial = false
        var mark: String?
        var trailing: String?
        var act = Act.none
        var warning = false
        var menuRect = NSRect.zero
    }
    private var rows: [Row] = []
    private var rowRects: [NSRect] = []
    private var stepRects: [NSRect] = []
    private let rollover = Rollover<Int>()

    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private static let step: CGFloat = 16, helpUnits: CGFloat = 3, wordsUnits: CGFloat = 3

    init(library: LibraryController) {
        self.library = library
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = canvas
        addSubview(scroll)
        back.target = self; back.action = #selector(goBack)
        next.target = self; next.action = #selector(goNext)
        next.arrow = true
        cancel.target = self; cancel.action = #selector(cancelJourney)
        addSubview(cancel); addSubview(back); addSubview(next)
        canvas.onDraw = { [weak self] in self?.drawRows() }
        canvas.onDown = { [weak self] p in self?.down(at: p) }
        canvas.onMove = { [weak self] p in
            guard let self = self else { return }
            self.rollover.moved(p.flatMap { pt in self.rowRects.firstIndex { $0.contains(pt) } }.flatMap { self.actionable(self.rows[$0]) ? $0 : nil })
        }
        rollover.keys = { [weak self] in Array((self?.rows.indices) ?? 0..<0) }
        rollover.locked = { _ in false }
        rollover.redraw = { [weak self] in self?.canvas.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func height(forWidth width: CGFloat) -> CGFloat { geometry(width: width - leading).buttonsTop + 4 * Self.u }
    func reload() { refresh() }
    private func refresh() { needsLayout = true; needsDisplay = true; canvas.needsDisplay = true; onResize?() }

    // MARK: Starting

    /// The schema of the open catalogue, as it stands.
    private var schema: SchemaTrial.SchemaFile { SchemaTrial.schema(for: library.store.root) ?? library.store.schema }

    /// Export from a place: the level pressed, and every level above it, up to the whole catalogue.
    func beginExport(level: ShareLevel, subject: UUID?, name: String) {
        clear()
        mode = .export
        var chain: [Level] = [Level(level: level, subject: subject, name: name)]
        let lib = library.library, f = schema
        func upward(_ l: Level) -> Level? {
            let top = Level(level: .catalogue, subject: nil, name: library.catalogue)
            switch l.level {
            case .palette:
                // A palette's member, then on up; a palette in the Library has only the catalogue above it.
                guard let id = l.subject, let m = lib.swatch(id)?.projectID, let p = lib.project(m) else { return top }
                return Level(level: .workGroup, subject: p.id, name: p.name)
            case .workGroup:
                guard let id = l.subject else { return top }
                if lib.project(id) != nil {
                    let c = SchemaTrial.collection(of: id, among: f.collections, places: f.places)
                    if let g = SchemaTrial.folder(of: id, among: f.collections, places: f.places), let folder = c.folders.first(where: { $0.id == g }) {
                        return Level(level: .workGroup, subject: folder.id, name: folder.name)
                    }
                    return Level(level: .collection, subject: c.id, name: c.name)
                }
                if let c = f.collections.first(where: { $0.folders.contains { $0.id == id } }) { return Level(level: .collection, subject: c.id, name: c.name) }
                return top
            case .collection: return top
            case .catalogue: return nil
            }
        }
        while let up = upward(chain[chain.count - 1]) { chain.append(up) }
        levels = chain
        levelIndex = 0
        buildTree()
        refresh()
    }

    /// Import: the wizard opens on Choose; the file is asked for on Next.
    func beginImport(url: URL? = nil) {
        clear()
        mode = .bringIn
        if let url { inspectImport(url) }
        refresh()
    }

    private func clear() {
        if let s = staging { Sharing.discard(s) }
        if let inspected=inspection?.stagedRoot,inspected != staging {Sharing.discard(inspected)}
        levels = []; levelIndex = 0; tree = nil; ticked = []; step = 0; carryTags = true; carryNotes = true
        carryAssets = false; carryAppbridge = false; importedName = nil; aseSelection = []; restoreASELocations = false
        chosenFile = nil; inspection = nil; staging = nil; staged = nil; placements = []; placementIndex = 0
        twins = []; resolutions = [:]; otherwise = .keepBoth; outcome = nil; savedTo = nil; problem = nil
        closeMenu()
    }

    private func buildTree() {
        switch mode {
        case .export:
            guard levels.indices.contains(levelIndex) else { tree = nil; return }
            let l = levels[levelIndex]
            tree = Sharing.tree(level: l.level, subject: l.subject, in: exportLibrary, schema: schema, catalogueName: library.catalogue)
        case .bringIn:
            tree = inspection?.tree
        }
        ticked = Set(tree?.flattened.map { $0.node.id } ?? [])
        if mode == .bringIn, let global = tree?.node("library") {
            ticked.subtract(global.flattened.map { $0.node.id })
        }
    }

    // MARK: Ticks

    private enum TickState { case all, none, some }
    private func state(_ n: ShareNode) -> TickState {
        let ids = n.flattened.map { $0.node.id }
        let on = ids.filter { ticked.contains($0) }.count
        return on == 0 ? .none : on == ids.count ? .all : .some
    }
    private func toggle(_ id: String) {
        guard let t = tree, let n = t.node(id) else { return }
        let below = n.flattened.map { $0.node.id }
        if state(n) == .all { for i in below { ticked.remove(i) } }
        else { for i in below { ticked.insert(i) }; for a in ShareNode.ancestors(of: id, in: t) { ticked.insert(a) } }
        canvas.needsDisplay = true
        needsDisplay = true
    }

    // MARK: The rows of each step

    private func mark(for kind: ShareNode.Kind) -> String {
        switch kind {
        case .catalogue: return "square.grid.2x2"
        case .collection: return "folder"
        case .group: return "building.2"
        case .member: return "folder"
        case .bucket: return "square.dashed"
        case .library: return "books.vertical"
        case .pool: return "tray"
        case .templates: return "square.stack.3d.up"
        case .template: return "doc"
        case .palette: return "swatchpalette"
        }
    }
    private func treeRows() -> [Row] {
        guard let t = tree else { return [] }
        return t.flattened.map { node, level in
            let st = state(node)
            let count = node.kind == .palette ? nil : plural(node.palettes, "palette")
            return Row(text: node.name, caption: nil, level: level, node: node, strong: level == 0, square: level == 0 ? nil : st != .none, partial: st == .some, mark: mark(for: node.kind), trailing: count, act: level == 0 ? .none : .tick(node.id))
        }
    }
    private func fileRows(_ files: [ShareManifest.File]) -> [Row] {
        files.map { Row(text: $0.path, caption: nil, level: 0, strong: false, square: nil, mark: $0.path.hasSuffix(".ase") ? "colorgain.ase" : "doc", trailing: bytes($0.bytes)) }
    }
    private func bytes(_ n: Int) -> String { n < 1024 ? "\(n) B" : n < 1_048_576 ? String(format: "%.1f KB", Double(n) / 1024) : String(format: "%.1f MB", Double(n) / 1_048_576) }

    private func build() -> [Row] {
        let name = steps[step]
        switch (mode, name) {
        case (.export, "Level"):
            return levels.enumerated().map { i, l in Row(text: l.level.title, caption: nil, strong: i == levelIndex, square: levels.count > 1 ? i == levelIndex : nil, mark: nil, trailing: l.name, act: levels.count > 1 ? .level(i) : .none) }
        case (_, "Contents"):
            return treeRows()
        case (.export, "Options"):
            return (level == .catalogue ? [Row(text: "Include global Assets", strong: carryAssets, square: carryAssets, trailing: "Unassigned app-wide assets", act: .option(2)), Row(text: "Include Appbridge ASE files", strong: carryAppbridge, square: carryAppbridge, trailing: "Linked in this catalogue’s .colase", act: .option(3))] : []) + [Row(text: "Carry the tags", strong: carryTags, square: carryTags, trailing: "On each palette and colour", act: .option(0)),
                    Row(text: "Carry the notes", strong: carryNotes, square: carryNotes, trailing: "The words written on each colour", act: .option(1))] + (carryAppbridge && level == .catalogue ? aseRows() : [])
        case (.export, "Check"):
            guard let t = tree else { return [] }
            let l = levels[levelIndex]
            let entries: [Zip.Entry]
            do { entries = try Sharing.package(level: l.level, subject: l.subject, ticked: ticked, strip: (!carryTags, !carryNotes), from: exportLibrary, schema: schema, catalogueName: library.catalogue, appbridge: aseFiles()) }
            catch { return [Row(text: "Cannot prepare export: " + error.localizedDescription, warning: true)] }
            var out = [Row(text: "\(plural(entries.count, "file")), \(bytes(entries.reduce(0) { $0 + $1.data.count })), \(plural(t.flattened.filter { ticked.contains($0.node.id) && $0.node.kind == .palette }.count, "palette"))", strong: true, square: nil)]
            out += entries.map { Row(text: $0.path, square: nil, mark: $0.path.hasSuffix(".ase") ? "colorgain.ase" : "doc", trailing: bytes($0.data.count)) }
            return out
        case (.export, "Save"):
            if let url = savedTo { return [Row(text: url.lastPathComponent, caption: nil, strong: true, square: nil, mark: "checkmark", trailing: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)] }
            return [Row(text: problem ?? "Nothing saved yet", square: nil, warning: problem != nil)]
        case (.bringIn, "Choose"):
            guard let i = inspection, let f = chosenFile else { return problem.map { [Row(text: $0, square: nil, warning: true)] } ?? [] }
            let m = i.manifest
            let f2 = DateFormatter(); f2.dateStyle = .medium; f2.timeStyle = .short
            return [Row(text: f.lastPathComponent, strong: true, square: nil, mark: "doc"),
                    Row(text: "\(m.level.title): \(m.subject.name)", square: nil, trailing: plural(m.files.count, "file")),
                    Row(text: "From \(m.catalogue.name)", square: nil, trailing: f2.string(from: m.exportedAt))]
        case (.bringIn, "Check"):
            guard let i = inspection else { return [] }
            if i.ok { return [Row(text: "Every file matches its digest, and the share is a \(i.manifest.level.title.lowercased()) as it says", strong: true, square: nil, mark: "checkmark")] + fileRows(i.manifest.files) }
            return i.problems.map { Row(text: $0, square: nil, mark: "exclamationmark.triangle", warning: true) }
        case (.bringIn, "Twins"):
            if twins.isEmpty { return [Row(text: "Nothing in the share is already in the catalogue", strong: true, square: nil, mark: "checkmark")] }
            var out = [Row(text: "For all matching items", strong: true, square: nil, trailing: otherwise.title, act: .answer(nil))]
            out += twins.map { d in
                let why = d.why == .sameID ? "The same \(kindWord(d.kind)), by id" : d.why == .sameColours ? "Identical content: \(d.existing)" : "Same name, different content: \(d.existing)"
                return Row(text: d.name, caption: why, strong: false, square: nil, mark: d.kind == .palette ? "swatchpalette" : "folder", trailing: (resolutions[d.id] ?? otherwise).title, act: .answer(d.id))
            }
            return out
        case (.bringIn, "Placement"):
            return placements.enumerated().map { i, p in Row(text: p.1, strong: i == placementIndex, square: i == placementIndex, act: .placement(i)) }
        case (.bringIn, "Confirm"):
            if standalone {
                return [Row(text: "Create a separate catalogue", strong: true), Row(text: inspection?.manifest.subject.name ?? "Catalogue"), Row(text: "Existing catalogues stay unchanged")] + (aseLinks.isEmpty ? [] : [Row(text: "\(aseSelection.count) of \(aseLinks.count) ASE files selected", strong: true), Row(text: "Keep in Library/ASE", square: !restoreASELocations, act: .option(4)), Row(text: "Restore original locations…", square: restoreASELocations, trailing: "Choose folders after import; never overwrite", act: .option(4))] + aseRows())
            }
            guard let s = staged else { return [] }
            var lib = library.library, schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
            let o = Sharing.commit(s, choices: choices(), into: &lib, schema: &schema)
            return sums(o, heading: "What Bring It In will do")
        case (.bringIn, "Done"):
            if let name = importedName { return [Row(text: "Imported " + name, strong: true, mark: "checkmark"), Row(text: "Created as a separate catalogue")] }
            guard let o = outcome else { return [Row(text: problem ?? "Nothing brought in", square: nil, warning: problem != nil)] }
            return sums(o, heading: "Brought in")
        default: return []
        }
    }
    private func kindWord(_ k: Sharing.Duplicate.Kind) -> String {
        switch k {
        case .collection: return "collection"
        case .group: return "group"
        case .member: return "member"
        case .palette: return "palette"
        }
    }
    private func sums(_ o: Sharing.Outcome, heading: String) -> [Row] {
        [Row(text: heading, strong: true, square: nil),
         Row(text: "Members", square: nil, trailing: "\(o.members)"), Row(text: "Palettes", square: nil, trailing: "\(o.palettes)"),
         Row(text: "Added", square: nil, trailing: "\(o.added)"), Row(text: "Replaced", square: nil, trailing: "\(o.replaced)"),
         Row(text: "Renamed", square: nil, trailing: "\(o.renamed)"), Row(text: "Skipped", square: nil, trailing: "\(o.skipped)")]
    }
    private func choices() -> Sharing.Choices {
        Sharing.Choices(ticked: ticked, placement: placements.indices.contains(placementIndex) ? placements[placementIndex].0 : .catalogue, resolutions: resolutions, otherwise: otherwise)
    }

    /// The words for the step in hand.
    private var words: String {
        switch (mode, steps[step]) {
        case (.export, "Level"): return "What goes: the \(levels.first?.level.title.lowercased() ?? "palette") you pressed Export on, or anything above it up to the whole catalogue. One zip, one manifest, every file listed with its digest."
        case (.export, "Contents"): return "Tick what goes. Untick a group and everything beneath it stays home; tick one palette and the folders above it go with it, so it lands where it belongs."
        case (.export, "Options"): return "Choose whether to include global Assets and Appbridge ASE files. Select linked ASE files by directory. Copies and their .colase index travel in Library/ASE; originals stay in place."
        case (.export, "Check"): return "Every file that will go, with its size. Nothing is written until Save."
        case (.export, "Save"): return savedTo == nil ? "Choose where the file goes. It is one .colshr file: a zip anyone can open, with its manifest inside." : "Saved. Send it as it is; the manifest lets the other end check it arrived whole."
        case (.bringIn, "Choose"): return chosenFile == nil ? "Choose a .colshr file. It is opened into a staging folder and read there; nothing reaches the catalogue until Confirm." : "What the share says it is. Next reads its contents."
        case (.bringIn, "Contents"): return "Choose the work to import. If included, Global Assets are unassigned app-wide assets; leave that branch unticked to import only the catalogue."
        case (.bringIn, "Check"): return inspection?.ok == true ? "The manifest, every file's digest and the shape its level calls for all hold." : "The share failed its check. Nothing has been written; ask for it to be sent again."
        case (.bringIn, "Twins"): return "What is already here, found by id, by the colours themselves, or by name in the same place. Replace puts the share's version in its place; Skip leaves it out; Rename brings it in under the next free name; Keep Both brings it in as it is, under a new id."
        case (.bringIn, "Placement"): return "Where it lands: only places that fit its level are offered."
        case (.bringIn, "Confirm"): if standalone { return "A new catalogue will be created. Existing catalogues are not compared or changed; an available name is used if this name already exists." }; return "The sums of what Bring It In will do. It goes in as one step in the history, so it can be undone whole."
        case (.bringIn, "Done"): return "Done. The rails show what came in."
        default: return ""
        }
    }
    private var nextTitle: String {
        switch (mode, steps[step]) {
        case (.export, "Check"): return "Save As\u{2026}"
        case (.export, "Save"): return savedTo == nil ? "Save As\u{2026}" : "Done"
        case (.bringIn, "Choose"): return chosenFile == nil ? "Choose File\u{2026}" : "Next"
        case (.bringIn, "Confirm"): return standalone ? "Import Catalogue" : "Import"
        case (.bringIn, "Done"): return "Done"
        default: return "Next"
        }
    }
    private var canGoOn: Bool {
        switch (mode, steps[step]) {
        case (.export, "Contents"), (.bringIn, "Contents"): return !ticked.isEmpty
        case (.bringIn, "Check"): return inspection?.ok == true
        default: return true
        }
    }

    // MARK: Geometry

    private struct Geometry { var lw: CGFloat = 0, rx: CGFloat = 0, rw: CGFloat = 0, top: CGFloat = 0, stepsTop: CGFloat = 0, wordsTop: CGFloat = 0, buttonsTop: CGFloat = 0 }
    private func geometry(width w: CGFloat) -> Geometry {
        var g = Geometry()
        let u = Self.u, gut = Design.App.areaGutter   // the split is an area gutter
        g.lw = ((w - gut) * 0.6).rounded(); g.rx = leading + g.lw + gut; g.rw = w - g.lw - gut
        g.top = 5 * u
        g.stepsTop = 5 * u
        g.wordsTop = g.stepsTop + CGFloat(steps.count) * u + u
        g.buttonsTop = g.wordsTop + Self.wordsUnits * u + u
        return g
    }

    override func layout() {
        super.layout()
        let g = geometry(width: bounds.width - leading), u = Self.u
        rows = build()
        scroll.frame = NSRect(x: 0, y: g.top, width: leading + g.lw + Design.App.areaGutter / 2, height: max(0, bounds.height - g.top))
        let h = CGFloat(rows.count) * u + u
        canvas.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.frame.height, h))
        scroll.verticalScrollElasticity = h > scroll.frame.height ? .allowed : .none
        rowRects = rows.indices.map { NSRect(x: leading, y: CGFloat($0) * u, width: g.lw, height: u) }
        stepRects = steps.indices.map { NSRect(x: g.rx, y: g.stepsTop + CGFloat($0) * u, width: g.rw, height: u) }
        next.title = nextTitle; next.invalidateIntrinsicContentSize()
        next.isEnabled = canGoOn
        back.isHidden = step == 0 || steps[step] == "Done"
        cancel.isHidden = steps[step] == "Done"
        cancel.frame = NSRect(x: g.rx, y: g.buttonsTop + u - 32, width: 90, height: 32)
        let nw = next.intrinsicContentSize.width, bw = back.intrinsicContentSize.width
        next.frame = NSRect(x: g.rx + g.rw - nw, y: g.buttonsTop + u - 32, width: nw, height: 32)
        back.frame = NSRect(x: next.frame.minX - 12 - bw, y: next.frame.minY, width: bw, height: 32)
        if g.rw < nw + bw + 90 + 32 {
            cancel.frame.origin.y += 2 * u
            back.frame = NSRect(x: g.rx + g.rw - bw, y: cancel.frame.minY, width: bw, height: 32)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width - leading), u = Self.u, line = Self.line, l = leading
        let title = mode == .export ? "Export" : "Import"
        let help = mode == .export ? "Any level goes out as one checked file: the whole catalogue, a collection, a work group, or a palette, with everything beneath it that is ticked."
                                   : "Import a catalogue as a separate system of work. Collections and individual assets can be brought into the open catalogue."
        Design.attributed(title, .header).draw(x: l, baseline: line)
        Design.attributed(help, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: l, y: u, width: g.lw, height: Self.helpUnits * u))
        Design.attributed(steps[step], .header).draw(x: l, baseline: 4 * u + line)
        hairline(x: l, y: g.top - 1, width: g.lw, Design.rule)
        let rx = g.rx
        Design.attributed(steps.count == 5 ? "Five Steps" : "Seven Steps", .header).draw(x: rx, baseline: line)
        Design.attributed(levels.indices.contains(levelIndex) && mode == .export ? "\(levels[levelIndex].level.title): \(levels[levelIndex].name)" : (inspection.map { "\($0.manifest.level.title): \($0.manifest.subject.name)" } ?? "Choose a file to begin"), .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: u, width: g.rw, height: Self.helpUnits * u))
        Design.attributed("Steps", .header).draw(x: rx, baseline: 4 * u + line)
        hairline(x: rx, y: g.stepsTop - 1, width: g.rw, Design.rule)
        for (i, name) in steps.enumerated() {
            let r = stepRects[i], b = r.minY + line
            if i == step { fill(NSRect(x: r.minX - Design.App.areaGutter / 2, y: r.minY - 1, width: r.width + Design.App.areaGutter / 2, height: r.height + 1), Design.mist) }
            Design.attributed("\(i + 1)", .caption, colour: i < step ? Design.quiet : Design.soft).draw(x: r.minX, baseline: b)
            Design.attributed(name, i == step ? .bodyStrong : .body, colour: i == step ? Design.ink : i < step ? Design.quiet : Design.soft).draw(x: r.minX + 24, baseline: b)
            if i < step { Design.attributed("\u{2713}", .caption, colour: Design.quiet).draw(right: r.maxX, baseline: b) }
            hairline(x: r.minX, y: r.maxY - 1, width: r.width, Design.mist)
        }
        Design.attributed(words, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: g.wordsTop, width: g.rw, height: Self.wordsUnits * u))
        if let p = problem, steps[step] != "Save", steps[step] != "Choose", steps[step] != "Done" {
            Design.attributed(p, .caption, colour: Design.orange).draw(x: rx, baseline: g.buttonsTop - u + line, width: g.rw)
        }
    }

    private func drawRows() {
        let line = Self.line, l = leading
        guard rowRects.count == rows.count else { return }
        let treeRowsHere = rows.contains { $0.node != nil }
        for (i, r) in rows.enumerated() {
            let box = rowRects[i], x = l + CGFloat(r.level) * Self.step
            let name = Design.attributed(r.text, r.strong ? .bodyStrong : .body, colour: r.warning ? Design.orange : r.strong ? Design.ink : Design.quiet)
            if actionable(r) { rollover.pane(i, box: box, reach: x + 40 + name.size().width + Self.step) }
        }
        if treeRowsHere {
            TreeLines.draw(rows.enumerated().map { k, r in
                TreeLines.Row(top: rowRects[k].minY, height: rowRects[k].height, level: r.level, anchor: l + CGFloat(r.level) * Self.step + 6, markLeft: l + CGFloat(r.level) * Self.step, baseline: line)
            }, colour: Design.rule)
        }
        for i in rows.indices {
            var r = rows[i]
            let box = rowRects[i], b = box.minY + line
            var x = l + CGFloat(r.level) * Self.step
            if let on = r.square {
                let sq = NSRect(x: x, y: b - 10, width: 12, height: 12)
                fill(sq, on && !r.partial ? Design.ink : Design.card)
                Design.ink.setStroke()
                let e = NSBezierPath(rect: sq.insetBy(dx: 0.5, dy: 0.5)); e.lineWidth = 1; e.stroke()
                if r.partial { fill(sq.insetBy(dx: 3, dy: 3), Design.ink) }
                x += 20
            }
            if let m = r.mark {
                if m == "colorgain.ase" { ASEIcon.image.draw(in: NSRect(x: x, y: b - 15, width: 16, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
                else { RowMark.draw(m, x: x, baseline: b, colour: r.warning ? Design.orange : Design.soft) }; x += 24
            }
            var right = box.maxX
            if let t = r.trailing {
                let isMenu: Bool = { if case .answer = r.act { return true }; return false }()
                let tt = Design.attributed(t, .caption, colour: isMenu ? Design.ink : Design.quiet)
                if isMenu {
                    // The answer as a drawn dropdown: the word and a chevron, which opens the house menu.
                    tt.draw(right: right - 14, baseline: b)
                    Design.quiet.setStroke()
                    let c = NSBezierPath(); c.lineWidth = 1
                    c.move(to: NSPoint(x: right - 9, y: b - 6)); c.line(to: NSPoint(x: right - 5, y: b - 2)); c.line(to: NSPoint(x: right - 1, y: b - 6))
                    c.stroke()
                    r.menuRect = NSRect(x: right - 14 - tt.size().width - 8, y: box.minY, width: tt.size().width + 22, height: box.height)
                    rows[i] = r
                } else { tt.draw(right: right, baseline: b) }
                right -= tt.size().width + 24
            }
            let name = Design.attributed(r.text, r.strong ? .bodyStrong : .body, colour: r.warning ? Design.orange : r.strong ? Design.ink : Design.quiet)
            if let c = r.caption {
                let cap = Design.attributed(c, .caption, colour: Design.quiet)
                name.draw(x: x, baseline: b, width: max(40, right - x - cap.size().width - 16))
                cap.draw(x: x + min(name.size().width, max(40, right - x - cap.size().width - 16)) + 12, baseline: b)
            } else {
                name.draw(x: x, baseline: b, width: right - x)
            }
            hairline(x: l, y: box.maxY - 1, width: box.width, Design.mist)
        }
    }

    // MARK: The pointer

    private func down(at p: NSPoint) {
        window?.makeFirstResponder(self)
        guard let i = rowRects.firstIndex(where: { $0.contains(p) }) else { return }
        let r = rows[i]
        switch r.act {
        case .none: break
        case .ase(let id): if aseSelection.contains(id) { aseSelection.remove(id) } else { aseSelection.insert(id) }; refresh()
        case .aseAll(let on): aseSelection = on ? Set(aseLinks.map { $0.id }) : []; refresh()
        case .aseGroup(let folder):
            let ids = Set(aseLinks.filter { URL(fileURLWithPath: $0.originalPath ?? $0.path).deletingLastPathComponent().path == folder }.map { $0.id })
            if ids.isSubset(of: aseSelection) { aseSelection.subtract(ids) } else { aseSelection.formUnion(ids) }; refresh()
        case .level(let k): levelIndex = k; buildTree(); refresh()
        case .tick(let id): toggle(id); rows = build(); canvas.needsDisplay = true
        case .option(let k): if k == 0 { carryTags.toggle() } else if k == 1 { carryNotes.toggle() } else if k == 3 { carryAppbridge.toggle(); if carryAppbridge { aseSelection = Set(aseLinks.map { $0.id }) } } else if k == 4 { restoreASELocations.toggle() } else { let previous = ticked; let oldIDs = Set(tree?.flattened.map { $0.node.id } ?? []); carryAssets.toggle(); buildTree(); ticked = previous.intersection(ticked).union(ticked.subtracting(oldIDs)) }; refresh()
        case .placement(let k): placementIndex = k; refresh()
        case .answer(let id):
            let items = Sharing.Resolution.allCases.map { $0.title }
            let now = id.flatMap { resolutions[$0] } ?? otherwise
            openMenu(under: r.menuRect.isEmpty ? rowRects[i] : r.menuRect, items: items, chosen: now.title) { [weak self] k in
                guard let self = self else { return }
                let pick = Sharing.Resolution.allCases[k]
                if let id = id { self.resolutions[id] = pick } else { self.otherwise = pick; self.resolutions = [:] }
                self.refresh()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if let i = stepRects.firstIndex(where: { $0.contains(p) }), i < step, steps[step] != "Done" { step = i; refresh() }
    }

    private func actionable(_ row: Row) -> Bool { if case .none = row.act { return false }; return true }
    @objc private func cancelJourney() { clear(); onLeave?() }

    @objc private func goBack() {
        guard step > 0 else { return }
        step -= 1
        problem = nil
        refresh()
    }

    @objc private func goNext() {
        problem = nil
        switch (mode, steps[step]) {
        case (.export, "Check"), (.export, "Save"):
            if savedTo != nil { onLeave?(); return }
            save()
            return
        case (.bringIn, "Choose"):
            if chosenFile == nil { chooseFile(); return }
        case (.bringIn, "Check"):
            // Twins and places are worked out once the share has been staged and read.
            guard let i = inspection else { return }
            do {
                if let s = staging,s != i.stagedRoot { Sharing.discard(s) }
                let dir = try Sharing.stage(i)
                staging = dir
                let s = try Sharing.read(staging: dir, level: i.manifest.level)
                staged = s
                aseSelection = Set(s.aseLinks.map { $0.id })
                let lib = library.library, schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
                placements = Sharing.placements(for: i.manifest.level, in: lib, schema: schema, origin: i.manifest.origin)
                placementIndex = 0
                twins = Sharing.duplicates(in: s, ticked: ticked, into: lib, schema: schema, placement: placements.first?.0 ?? .catalogue)
                resolutions = [:]
            } catch { problem = error.localizedDescription; refresh(); return }
        case (.bringIn, "Placement"):
            // The twins depend on where it lands, so they are looked at again for the place chosen.
            if let s = staged {
                let lib = library.library, schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
                twins = Sharing.duplicates(in: s, ticked: ticked, into: lib, schema: schema, placement: choices().placement)
            }
        case (.bringIn, "Confirm"):
            guard let s = staged else { return }
            if standalone {
                do {
                    let name = try Sharing.importCatalogue(s, ticked: ticked, name: inspection?.manifest.subject.name ?? "Imported Catalogue", catalogues: .standard, aseSelection: aseSelection)
                    if restoreASELocations { restoreLocations(in: Catalogues.standard.directory(for: name)) }
                    importedName = name
                    outcome = Sharing.Outcome()
                    library.open(catalogue: name)
                } catch { problem = error.localizedDescription; refresh(); return }
            } else { do { outcome = try library.bringIn(s, choices: choices()) } catch { problem = error.localizedDescription; refresh(); return } }
            if let dir = staging { Sharing.discard(dir); staging = nil }
        case (.bringIn, "Done"):
            onLeave?(); return
        default: break
        }
        if step + 1 < steps.count { step += 1 }
        refresh()
    }

    private func restoreLocations(in root: URL) {
        do {
            var links = try ASERegistry.resolved(root)
            let folders = Set(links.compactMap { $0.originalPath }.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
            var notes: [String] = []
            for folder in folders.sorted() {
                let panel = NSOpenPanel(); panel.title = "Restore ASE Files"
                panel.message = "Original folder: " + folder + "\nChoose this folder or another destination. Cancel keeps these files in the catalogue."
                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                panel.directoryURL = URL(fileURLWithPath: folder)
                guard panel.runModal() == .OK, let destination = panel.url else { continue }
                try FolderAccess.authorize(destination)
                for i in links.indices where links[i].originalPath.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().path }) == folder {
                    let target = destination.appendingPathComponent(URL(fileURLWithPath: links[i].originalPath!).lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: links[i].url, to: target)
                        ASEIcon.apply(to: target); links[i].path = target.path
                    } catch { notes.append(target.lastPathComponent + ": kept in catalogue (" + error.localizedDescription + ")") }
                }
            }
            try ASERegistry.write(links, root: root)
            if !notes.isEmpty { NSApp.presentError(failure(notes.joined(separator: "\n"))) }
        } catch { NSApp.presentError(error) }
    }

    private func save() {
        guard levels.indices.contains(levelIndex) else { return }
        let l = levels[levelIndex]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filesystemName(l.name) + "." + ColourFiles.share
        panel.allowedContentTypes = [UTType(exportedAs: "com.mmffdev.colour.share", conformingTo: .zip)]
        panel.canCreateDirectories = true
        panel.prompt = "Save Share"
        panel.message = "One zip with its manifest inside, for anyone to open"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                let named = ShareManifest.Named(id: CatalogueTree.catalogue(in: self.library.store.root)?.id ?? UUID(), name: self.library.catalogue)
                _ = try Sharing.export(level: l.level, subject: l.subject, from: self.exportLibrary, schema: self.schema, catalogue: named, ticked: self.ticked,
                                       strip: (!self.carryTags, !self.carryNotes), appbridge: self.aseFiles(), calibrationRoot: self.library.store.root, to: url)
                self.savedTo = url
                self.library.flash("Exported \(l.name) to \(url.lastPathComponent)")
                if self.steps[self.step] != "Save" { self.step = self.steps.firstIndex(of: "Save") ?? self.step }
            } catch { self.problem = error.localizedDescription; Diagnostics.log("share", error: error) }
            self.refresh()
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    private func inspectImport(_ url: URL) {
        if let prior=inspection?.stagedRoot,prior != staging {Sharing.discard(prior)}
        do { inspection = try Sharing.inspect(url); chosenFile = url; buildTree() }
        catch { problem = error.localizedDescription; inspection = nil; chosenFile = nil }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(exportedAs: "com.mmffdev.colour.share", conformingTo: .zip), .zip]
        panel.prompt = "Import"
        panel.message = "Catalogues open independently. Individual collections and assets import into the current catalogue."
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            self.inspectImport(url)
            self.refresh()
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }
}

extension LibraryController {
    /// Brings a staged share in as the choices say: the schema first, then the library as one step in the history.
    func bringIn(_ staged: Sharing.Staged, choices: Sharing.Choices) throws -> Sharing.Outcome {
        var lib = library
        var schema = SchemaTrial.schema(for: store.root) ?? store.schema
        let outcome = Sharing.commit(staged, choices: choices, into: &lib, schema: &schema)
        let made = lib
        guard apply("Import \(staged.level.title)", schema: schema, { $0 = made }) else { throw failure("The import could not be saved. Your existing work was retained.") }
        flash("Brought in \(plural(outcome.palettes, "palette"))" + (outcome.members > 0 ? " and \(plural(outcome.members, "member"))" : ""))
        return outcome
    }
}
