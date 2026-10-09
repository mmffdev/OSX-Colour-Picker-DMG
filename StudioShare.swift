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

final class SharePage: NSView, PageSection, Overlay {
    enum Mode { case export, bringIn }
    struct Level { let level: ShareLevel; let subject: URL; let name: String }

    private let library: LibraryController
    var onResize: (() -> Void)?
    /// The page is done with: back to where the user came from.
    var onLeave: (() -> Void)?
    var leading: CGFloat = 0 { didSet { needsLayout = true; needsDisplay = true } }

    private var mode = Mode.export
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

    private var steps: [String] { mode == .export ? ["Level", "Contents", "Options", "Check", "Save"] : ["Choose", "Contents", "Check", "Twins", "Placement", "Confirm", "Done"] }
    private var level: ShareLevel { mode == .export ? (levels.indices.contains(levelIndex) ? levels[levelIndex].level : .palette) : (inspection?.manifest.level ?? .palette) }

    // MARK: The views

    private let scroll = NSScrollView()
    private let canvas = Canvas()
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
        enum Act { case none, level(Int), tick(String), option(Int), placement(Int), answer(UUID?) }
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
        addSubview(back); addSubview(next)
        canvas.onDraw = { [weak self] in self?.drawRows() }
        canvas.onDown = { [weak self] p in self?.down(at: p) }
        canvas.onMove = { [weak self] p in
            guard let self = self else { return }
            self.rollover.moved(p.flatMap { pt in self.rowRects.firstIndex { $0.contains(pt) } })
        }
        rollover.keys = { [weak self] in Array((self?.rows.indices) ?? 0..<0) }
        rollover.locked = { _ in false }
        rollover.redraw = { [weak self] in self?.canvas.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func height(forWidth width: CGFloat) -> CGFloat { 0 }
    func reload() { refresh() }
    private func refresh() { needsLayout = true; needsDisplay = true; canvas.needsDisplay = true; onResize?() }

    // MARK: Starting

    /// Export from a place: the level pressed, and every level above it, up to the whole catalogue.
    func beginExport(level: ShareLevel, subject: URL, name: String) {
        clear()
        mode = .export
        var chain: [Level] = [Level(level: level, subject: subject, name: name)]
        let root = library.store.root
        func upward(_ l: Level) -> Level? {
            switch l.level {
            case .palette:
                let folder = l.subject.deletingLastPathComponent()
                // The palette's member, found by walking up to the folder with a work group file; a palette in the Library has only the catalogue above it.
                var dir = folder
                while dir.path.count > root.path.count {
                    if let file = CatalogueTree.document(in: dir, extension: TreeFiles.workGroup), let doc = CatalogueTree.read(WorkGroupDocument.self, at: file), doc.kind == .member {
                        return Level(level: .workGroup, subject: dir, name: doc.name)
                    }
                    dir = dir.deletingLastPathComponent()
                }
                return Level(level: .catalogue, subject: root, name: library.catalogue)
            case .workGroup:
                var dir = l.subject.deletingLastPathComponent()
                while dir.path.count > root.path.count {
                    if let file = CatalogueTree.document(in: dir, extension: TreeFiles.collection), let doc = CatalogueTree.read(CollectionDocument.self, at: file) { return Level(level: .collection, subject: dir, name: doc.name) }
                    if let file = CatalogueTree.document(in: dir, extension: TreeFiles.workGroup), let doc = CatalogueTree.read(WorkGroupDocument.self, at: file) { return Level(level: .workGroup, subject: dir, name: doc.name) }
                    dir = dir.deletingLastPathComponent()
                }
                return Level(level: .catalogue, subject: root, name: library.catalogue)
            case .collection: return Level(level: .catalogue, subject: root, name: library.catalogue)
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
    func beginImport() {
        clear()
        mode = .bringIn
        refresh()
    }

    private func clear() {
        if let s = staging { Sharing.discard(s) }
        levels = []; levelIndex = 0; tree = nil; ticked = []; step = 0; carryTags = true; carryNotes = true
        chosenFile = nil; inspection = nil; staging = nil; staged = nil; placements = []; placementIndex = 0
        twins = []; resolutions = [:]; otherwise = .keepBoth; outcome = nil; savedTo = nil; problem = nil
        closeMenu()
    }

    private func buildTree() {
        switch mode {
        case .export:
            guard levels.indices.contains(levelIndex) else { tree = nil; return }
            let l = levels[levelIndex]
            tree = Sharing.tree(level: l.level, subject: l.subject, root: library.store.root)
        case .bringIn:
            tree = inspection?.tree
        }
        ticked = Set(tree?.flattened.map { $0.node.id } ?? [])
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
            return Row(text: node.name, caption: nil, level: level, node: node, strong: level == 0, square: st != .none, partial: st == .some, mark: mark(for: node.kind), trailing: count, act: .tick(node.id))
        }
    }
    private func fileRows(_ files: [ShareManifest.File]) -> [Row] {
        files.map { Row(text: $0.path, caption: nil, level: 0, strong: false, square: nil, mark: "doc", trailing: bytes($0.bytes)) }
    }
    private func bytes(_ n: Int) -> String { n < 1024 ? "\(n) B" : n < 1_048_576 ? String(format: "%.1f KB", Double(n) / 1024) : String(format: "%.1f MB", Double(n) / 1_048_576) }

    private func build() -> [Row] {
        let name = steps[step]
        switch (mode, name) {
        case (.export, "Level"):
            return levels.enumerated().map { i, l in Row(text: l.level.title, caption: nil, strong: i == levelIndex, square: i == levelIndex, mark: nil, trailing: l.name, act: .level(i)) }
        case (_, "Contents"):
            return treeRows()
        case (.export, "Options"):
            return [Row(text: "Carry the tags", strong: carryTags, square: carryTags, trailing: "On each palette and colour", act: .option(0)),
                    Row(text: "Carry the notes", strong: carryNotes, square: carryNotes, trailing: "The words written on each colour", act: .option(1))]
        case (.export, "Check"):
            guard let t = tree else { return [] }
            let files = Sharing.files(ticked: ticked, in: t).filter { !$0.hasSuffix("." + ColourFiles.history) }
            let base = levels[levelIndex].level == .catalogue ? library.store.root : levels[levelIndex].subject.deletingLastPathComponent()
            let sizes = files.map { ((try? FileManager.default.attributesOfItem(atPath: base.appendingPathComponent($0).path)[.size]) as? Int) ?? 0 }
            var out = [Row(text: "\(plural(files.count, "file")), \(bytes(sizes.reduce(0, +))), \(plural(t.flattened.filter { ticked.contains($0.node.id) && $0.node.kind == .palette }.count, "palette"))", strong: true, square: nil)]
            out += zip(files, sizes).map { Row(text: $0.0, square: nil, mark: "doc", trailing: bytes($0.1)) }
            return out
        case (.export, "Save"):
            if let url = savedTo { return [Row(text: url.lastPathComponent, caption: nil, strong: true, square: nil, mark: "checkmark", trailing: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)] }
            return [Row(text: problem ?? "Nothing saved yet", square: nil, warning: problem != nil)]
        case (.bringIn, "Choose"):
            guard let i = inspection, let f = chosenFile else { return [Row(text: problem ?? "No file chosen yet", square: nil, warning: problem != nil)] }
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
            var out = [Row(text: "For every twin", strong: true, square: nil, trailing: otherwise.title, act: .answer(nil))]
            out += twins.map { d in
                let why = d.why == .sameID ? "The same \(kindWord(d.kind)), by id" : d.why == .sameColours ? "The same colours as \(d.existing)" : "The same name as \(d.existing)"
                return Row(text: d.name, caption: why, strong: false, square: nil, mark: d.kind == .palette ? "swatchpalette" : "folder", trailing: (resolutions[d.id] ?? otherwise).title, act: .answer(d.id))
            }
            return out
        case (.bringIn, "Placement"):
            return placements.enumerated().map { i, p in Row(text: p.1, strong: i == placementIndex, square: i == placementIndex, act: .placement(i)) }
        case (.bringIn, "Confirm"):
            guard let s = staged else { return [] }
            var lib = library.library, schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
            let o = Sharing.commit(s, choices: choices(), into: &lib, schema: &schema)
            return sums(o, heading: "What Bring It In will do")
        case (.bringIn, "Done"):
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
        case (.export, "Options"): return "Tags and the notes written on colours are yours; leave them out when the share is for someone outside the work."
        case (.export, "Check"): return "Every file that will go, with its size. Nothing is written until Save."
        case (.export, "Save"): return savedTo == nil ? "Choose where the file goes. It is one .colshare file: a zip anyone can open, with its manifest inside." : "Saved. Send it as it is; the manifest lets the other end check it arrived whole."
        case (.bringIn, "Choose"): return chosenFile == nil ? "Choose a .colshare file. It is opened into a staging folder and read there; nothing reaches the catalogue until Confirm." : "What the share says it is. Next reads its contents."
        case (.bringIn, "Contents"): return "Tick what comes in, down to a single palette. Anything left unticked stays in the file."
        case (.bringIn, "Check"): return inspection?.ok == true ? "The manifest, every file's digest and the shape its level calls for all hold." : "The share failed its check. Nothing has been written; ask for it to be sent again."
        case (.bringIn, "Twins"): return "What is already here, found by id, by the colours themselves, or by name in the same place. Replace puts the share's version in its place; Skip leaves it out; Rename brings it in under the next free name; Keep Both brings it in as it is, under a new id."
        case (.bringIn, "Placement"): return "Where it lands: only places that fit its level are offered."
        case (.bringIn, "Confirm"): return "The sums of what Bring It In will do. It goes in as one step in the history, so it can be undone whole."
        case (.bringIn, "Done"): return "Done. The rails show what came in."
        default: return ""
        }
    }
    private var nextTitle: String {
        switch (mode, steps[step]) {
        case (.export, "Check"): return "Save As\u{2026}"
        case (.export, "Save"): return savedTo == nil ? "Save As\u{2026}" : "Done"
        case (.bringIn, "Choose"): return chosenFile == nil ? "Choose File\u{2026}" : "Next"
        case (.bringIn, "Confirm"): return "Bring It In"
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
        let u = Self.u, gut = Design.App.gutter
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
        scroll.frame = NSRect(x: 0, y: g.top, width: leading + g.lw + Design.App.gutter / 2, height: max(0, bounds.height - g.top))
        let h = CGFloat(rows.count) * u + u
        canvas.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: max(scroll.frame.height, h))
        scroll.verticalScrollElasticity = h > scroll.frame.height ? .allowed : .none
        rowRects = rows.indices.map { NSRect(x: leading, y: CGFloat($0) * u, width: g.lw, height: u) }
        stepRects = steps.indices.map { NSRect(x: g.rx, y: g.stepsTop + CGFloat($0) * u, width: g.rw, height: u) }
        next.title = nextTitle; next.invalidateIntrinsicContentSize()
        next.isEnabled = canGoOn
        back.isHidden = step == 0 || steps[step] == "Done"
        let nw = next.intrinsicContentSize.width, bw = back.intrinsicContentSize.width
        next.frame = NSRect(x: g.rx + g.rw - nw, y: g.buttonsTop + u - 32, width: nw, height: 32)
        back.frame = NSRect(x: next.frame.minX - 12 - bw, y: next.frame.minY, width: bw, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry(width: bounds.width - leading), u = Self.u, line = Self.line, l = leading
        let title = mode == .export ? "Export" : "Import"
        let help = mode == .export ? "Any level goes out as one checked file: the whole catalogue, a collection, a work group, or a palette, with everything beneath it that is ticked."
                                   : "A share comes in through the same steps in reverse: checked before anything is written, its twins answered one by one, and placed where its level fits."
        Design.attributed(title, .header).draw(x: l, baseline: line)
        Design.attributed(help, .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: l, y: u, width: g.lw, height: Self.helpUnits * u))
        Design.attributed(steps[step], .header).draw(x: l, baseline: 4 * u + line)
        hairline(x: l, y: g.top - 1, width: g.lw, Design.rule)
        let rx = g.rx
        Design.attributed(mode == .export ? "Five Steps" : "Seven Steps", .header).draw(x: rx, baseline: line)
        Design.attributed(levels.indices.contains(levelIndex) && mode == .export ? "\(levels[levelIndex].level.title): \(levels[levelIndex].name)" : (inspection.map { "\($0.manifest.level.title): \($0.manifest.subject.name)" } ?? "Choose a file to begin"), .caption, colour: Design.quiet, lineHeight: true).draw(in: NSRect(x: rx, y: u, width: g.rw, height: Self.helpUnits * u))
        Design.attributed("Steps", .header).draw(x: rx, baseline: 4 * u + line)
        hairline(x: rx, y: g.stepsTop - 1, width: g.rw, Design.rule)
        for (i, name) in steps.enumerated() {
            let r = stepRects[i], b = r.minY + line
            if i == step { fill(NSRect(x: r.minX - Design.App.gutter / 2, y: r.minY - 1, width: r.width + Design.App.gutter / 2, height: r.height + 1), Design.mist) }
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
            rollover.pane(i, box: box, reach: x + 40 + name.size().width + Self.step)
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
            if let m = r.mark { RowMark.draw(m, x: x, baseline: b, colour: r.warning ? Design.orange : Design.soft); x += 20 }
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
        case .level(let k): levelIndex = k; buildTree(); refresh()
        case .tick(let id): toggle(id); rows = build(); canvas.needsDisplay = true
        case .option(let k): if k == 0 { carryTags.toggle() } else { carryNotes.toggle() }; refresh()
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
                if let s = staging { Sharing.discard(s) }
                let dir = try Sharing.stage(i)
                staging = dir
                let s = try Sharing.read(staging: dir, level: i.manifest.level)
                staged = s
                let lib = library.library, schema = SchemaTrial.schema(for: library.store.root) ?? library.store.schema
                placements = Sharing.placements(for: i.manifest.level, in: lib, schema: schema)
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
            outcome = library.bringIn(s, choices: choices())
            if let dir = staging { Sharing.discard(dir); staging = nil }
        case (.bringIn, "Done"):
            onLeave?(); return
        default: break
        }
        if step + 1 < steps.count { step += 1 }
        refresh()
    }

    private func save() {
        guard levels.indices.contains(levelIndex) else { return }
        let l = levels[levelIndex]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filesystemName(l.name) + ".colshare"
        panel.allowedContentTypes = [UTType(exportedAs: "com.mmffdev.colorgain.colshare", conformingTo: .zip)]
        panel.canCreateDirectories = true
        panel.prompt = "Save Share"
        panel.message = "One zip with its manifest inside, for anyone to open"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                let index = CatalogueTree.index(in: self.library.store.root)
                let named = ShareManifest.Named(id: index?.id ?? UUID(), name: self.library.catalogue)
                _ = try Sharing.export(level: l.level, subject: l.subject, root: self.library.store.root, catalogue: named, ticked: self.ticked, strip: (!self.carryTags, !self.carryNotes), to: url)
                self.savedTo = url
                self.library.flash("Exported \(l.name) to \(url.lastPathComponent)")
                if self.steps[self.step] != "Save" { self.step = self.steps.firstIndex(of: "Save") ?? self.step }
            } catch { self.problem = error.localizedDescription; Diagnostics.log("share", error: error) }
            self.refresh()
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(exportedAs: "com.mmffdev.colorgain.colshare", conformingTo: .zip), .zip]
        panel.prompt = "Open Share"
        panel.message = "Choose a .colshare file to bring into \(library.catalogue)"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                let i = try Sharing.inspect(url)
                self.inspection = i
                self.chosenFile = url
                self.buildTree()
            } catch { self.problem = error.localizedDescription; self.inspection = nil; self.chosenFile = nil }
            self.refresh()
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }
}

extension LibraryController {
    /// Brings a staged share in as the choices say: the schema first, then the library as one step in the history.
    func bringIn(_ staged: Sharing.Staged, choices: Sharing.Choices) -> Sharing.Outcome {
        var lib = library
        var schema = SchemaTrial.schema(for: store.root) ?? store.schema
        let outcome = Sharing.commit(staged, choices: choices, into: &lib, schema: &schema)
        SchemaTrial.replace(schema)
        let made = lib
        apply("Import \(staged.level.title)") { $0 = made }
        flash("Brought in \(plural(outcome.palettes, "palette"))" + (outcome.members > 0 ? " and \(plural(outcome.members, "member"))" : ""))
        return outcome
    }
}
