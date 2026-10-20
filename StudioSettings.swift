import AppKit

// ---------- Settings ▸ Shortcuts and Settings ▸ Halo, and the old pages hosted on the Studio page ----------
//
// Each is a page section: a view the page scrolls as one piece, laid out on Master Inner, that says how
// tall it is at a width. Shortcuts: the quick keys, single keys that work anywhere in the window while
// no words are being typed, then every menu command with its shortcut, each a value on a hairline that a
// click turns into "Type the key". Halo: how far the wheel moves a ring, and a halo of letters to try it
// on. The Lab and Contrast pages are the old window's, held in a section until they are redrawn.

protocol PageSection: NSView {
    var onResize: (() -> Void)? { get set }
    func reload()
    func height(forWidth width: CGFloat) -> CGFloat
    var sectionAnchors: [(String, CGFloat)] { get }
}
extension PageSection { var sectionAnchors: [(String, CGFloat)] { [] } }

/// The single keys that work anywhere in the window: what they do, and the key each is on.
enum QuickKeys {
    struct Command { let id: String; let title: String; let fallback: String }
    static let commands = [Command(id: "newPalette", title: "New Palette", fallback: "1"),
                           Command(id: "pick", title: "Picker", fallback: "2"),
                           Command(id: "sample", title: "Rectangle Picker", fallback: "3"),
                           Command(id: "outputProof", title: "Output Proof On/Off", fallback: "P"),
                           Command(id: "rail1", title: "Rail 1 Open/Close", fallback: ","),
                           Command(id: "rail2", title: "Rail 2 Open/Close", fallback: ".")]
    static func key(for id: String) -> String { Prefs.quickKeys[id] ?? commands.first { $0.id == id }?.fallback ?? "" }
    static func set(_ key: String?, for id: String) { var all = Prefs.quickKeys; all[id] = key; Prefs.quickKeys = all }
    /// The key a press is, as it is written here: a shift arrow before the character when Shift was down.
    static func pressed(_ e: NSEvent) -> String? {
        guard let c = e.charactersIgnoringModifiers, c.count == 1, !e.modifierFlags.contains(.command), !e.modifierFlags.contains(.control), !e.modifierFlags.contains(.option) else { return nil }
        return (e.modifierFlags.contains(.shift) ? "\u{21E7}" : "") + c.uppercased()
    }
    /// The command a press belongs to, if any.
    static func command(for e: NSEvent) -> String? {
        guard let k = pressed(e) else { return nil }
        return commands.first { key(for: $0.id) == k }?.id
    }
}

final class ShortcutsSettings: ClickCursorView, PageSection {
    override var handCursorRects:[NSRect]{hits.map{$0.0}+clearHits.map{$0.0}}

    var onResize: (() -> Void)?
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    /// Which row is taking a key: a quick key by id, or a menu command by id.
    private enum Recording: Equatable { case quick(String), menu(String) }
    private var recording: Recording?
    var isRecordingShortcut: Bool { recording != nil }
    private var problem = ""
    private var hits: [(NSRect, Recording)] = []
    private var clearHits: [(NSRect, Recording)] = []
    private let restore = SwissButton("Restore Defaults", .secondary)
    private let importKeys = SwissButton("↓ Import", .secondary)
    private let exportKeys = SwissButton("↑ Export", .secondary)
    private let shareKeys = SwissButton("↗ Share", .secondary)
    private var profilePicker: SwissDropdown?
    private let profileNote = Design.text("", .caption)
    private var profiles: [(URL, KeyProfile)] = []
    private var firstGuide: CGFloat { SettingsSheet.headerGuide + 4 * Self.u }


    init() {
        super.init(frame: .zero)
        restore.target = self; restore.action = #selector(restoreDefaults)
        importKeys.target = self; importKeys.action = #selector(importProfile)
        exportKeys.target = self; exportKeys.action = #selector(exportProfile)
        shareKeys.target = self; shareKeys.action = #selector(shareProfile)
        for button in [importKeys, exportKeys, shareKeys, restore] { addSubview(button) }
        profileNote.maximumNumberOfLines = 2; profileNote.lineBreakMode = .byWordWrapping
        addSubview(profileNote)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func reload() {
        recording = nil
        do { profiles = try KeyProfiles.list(); problem = "" } catch { problem = error.localizedDescription }
        rebuildPicker()
        needsLayout = true; needsDisplay = true; onResize?()
    }
    private func rebuildPicker() {
        profilePicker?.removeFromSuperview()
        let labels = profiles.map { entry in
            profiles.filter { $0.1.name == entry.1.name }.count > 1 ? entry.1.name + " (" + entry.0.lastPathComponent + ")" : entry.1.name
        }
        let selected = profiles.firstIndex { $0.0 == KeyProfiles.activeURL }
        let picker = SwissDropdown("Key Profile", value: selected.map { labels[$0] } ?? "Choose Profile", options: labels, allowsOwn: false, width: max(220, bounds.width - contentX))
        picker.onChange = { [weak self] label in
            guard let self, let index = labels.firstIndex(of: label) else { return }
            do { try KeyProfiles.activate(self.profiles[index].0); self.reload() }
            catch { self.reload(); self.showError(error) }
        }
        profileNote.stringValue = selected.map { profiles[$0].1.description } ?? ""
        profilePicker = picker; addSubview(picker)
    }

    private var menuCommands: [Shortcuts.Command] { Shortcuts.commands }

    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    private var groups: [(String, [(String, String, Recording)])] {
        var result: [(String, [(String, String, Recording)])] = [("Quick Keys", QuickKeys.commands.map { ($0.title, QuickKeys.key(for: $0.id), .quick($0.id)) })]
        for command in menuCommands {
            if result.last?.0 != command.menu { result.append((command.menu, [])) }
            result[result.count - 1].1.append((command.title, command.shortcut?.display ?? "", .menu(command.id)))
        }
        return result
    }
    var sectionAnchors: [(String, CGFloat)] {
        var y = firstGuide
        var anchors: [(String,CGFloat)] = [("Profile",SettingsSheet.headerGuide+1)]
        for group in groups { anchors.append((group.0,y+1)); y += max(5*Self.u,CGFloat(group.1.count+3)*Self.u) }
        anchors.append(("Manage",endGuide+1)); return anchors
    }
    private var endGuide: CGFloat {
        firstGuide + groups.reduce(CGFloat(0)) { $0 + max(5 * Self.u, CGFloat($1.1.count + 3) * Self.u) }
    }
    func height(forWidth width: CGFloat) -> CGFloat { endGuide + 5 * Self.u }
    override func layout() {
        super.layout()
        let x = contentX, available = bounds.width - x
        if let picker = profilePicker { for constraint in picker.constraints where constraint.firstAttribute == .width { constraint.constant = max(220, available) } }
        profilePicker?.frame = NSRect(x: x, y: SettingsSheet.headerGuide + 11, width: available, height: 56)
        profileNote.frame = NSRect(x: x, y: SettingsSheet.headerGuide + 73, width: available, height: 28)
        var bx = x, by = SettingsSheet.buttonTop(baseline: endGuide + 2 * Self.u)
        for button in [importKeys, exportKeys, shareKeys, restore] {
            let width = button.intrinsicContentSize.width
            if bx > x && bx + width > bounds.width { bx = x; by += 2 * Self.u }
            button.frame = NSRect(x: bx, y: by, width: width, height: 32); bx += width + 16
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let u = Self.u, x = contentX, w = bounds.width
        hits = []; clearHits = []
        SettingsSheet.title("Shortcuts.")
        SettingsSheet.introduction("Keyboard controls", "Click a key to change it. Delete clears; Escape cancels.", x: x, width: w)
        var guide = firstGuide
        for (index, group) in groups.enumerated() {
            SettingsSheet.section(index + 1, group.0, guide: guide, contentX: x, width: w)
            var y = guide + 2 * u - Self.line
            let valueX = SettingsSheet.columns(width: w, window: window?.frame.width ?? Design.App.size.width).first(where: { $0 >= x + (w - x) / 2 }) ?? (x + (w - x) / 2)
            for (title, value, id) in group.1 {
                let b = y + Self.line, on = recording == id
                Design.attributed(title, .body).draw(x: x, baseline: b, width: valueX - x - 16)
                Design.attributed(on ? "Type the key…" : (value.isEmpty ? "None" : value), .body,
                                  colour: value.isEmpty && !on ? Design.quiet : Design.ink).draw(x: valueX, baseline: b, width: w - valueX - 32)
                hairline(x: x, y: y + u - 1, width: w - x, on ? Design.ink : Design.rule)
                hits.append((NSRect(x: valueX, y: y, width: w - valueX - 32, height: u), id))
                if !value.isEmpty && !on {
                    let r = NSRect(x: w - 16, y: b - 10, width: 10, height: 10)
                    Design.quiet.setStroke()
                    let path = NSBezierPath(); path.lineWidth = 1
                    path.move(to: r.origin); path.line(to: NSPoint(x: r.maxX, y: r.maxY))
                    path.move(to: NSPoint(x: r.maxX, y: r.minY)); path.line(to: NSPoint(x: r.minX, y: r.maxY)); path.stroke()
                    clearHits.append((r.insetBy(dx: -6, dy: -6), id))
                }
                y += u
            }
            guide += max(5 * u, CGFloat(group.1.count + 3) * u)
        }
        SettingsSheet.divider(above: guide, width: w)
        if !problem.isEmpty { Design.attributed(problem, .caption, colour: Design.ink).draw(x: x, baseline: guide + 28, width: w - x) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let c = clearHits.first(where: { $0.0.contains(p) }) { clear(c.1); return }
        if let h = hits.first(where: { $0.0.contains(p) }) {
            recording = h.1; problem = ""
            window?.makeFirstResponder(self)
            needsDisplay = true
            return
        }
        recording = nil; needsDisplay = true
    }
    private func clear(_ r: Recording) {
        switch r {
        case .quick(let id): QuickKeys.set("", for: id)
        case .menu(let id): _ = Shortcuts.set(nil, for: id)
        }
        reload()
    }
    override func keyDown(with event: NSEvent) {
        guard let r = recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = nil; needsDisplay = true; return }
        if event.keyCode == 51 || event.keyCode == 117 { clear(r); return }
        switch r {
        case .quick(let id):
            guard let k = QuickKeys.pressed(event) else { problem = "A quick key is a single key, with Shift at most."; needsDisplay = true; return }
            if let taken = QuickKeys.commands.first(where: { $0.id != id && QuickKeys.key(for: $0.id) == k }) { problem = "\(k) is \(taken.title)'s."; needsDisplay = true; return }
            QuickKeys.set(k, for: id)
        case .menu(let id):
            guard let key = event.characters(byApplyingModifiers: []), !key.isEmpty else { return }
            let s = Shortcut(key: key, modifiers: ShortcutModifiers(event.modifierFlags))
            if let why = Shortcuts.set(s, keyCode: Int(event.keyCode), for: id) { problem = why.message(for: s); needsDisplay = true; return }
        }
        reload()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording != nil else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    @objc private func restoreDefaults() { Shortcuts.restoreDefaults(); Prefs.quickKeys = [:]; reload() }
}

/// Keeps the native colour-panel interaction, with the Studio's square swatch treatment.
private final class HaloColourWell: ClickCursorColorWell {
    var part = "centre.background"
    override func mouseDown(with event: NSEvent) { openPicker() }
    override func accessibilityPerformPress() -> Bool { openPicker(); return true }
    override func activate(_ exclusive: Bool) { openPicker() }
    private func openPicker() {
        guard let frame = window?.contentView as? StudioFrame else { return }
        let picker = StudioColourPicker(target: part)
        picker.onDismiss = { [weak frame] in frame?.reload() }
        picker.present(over: frame)
    }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill(); bounds.fill()
        Design.ink.setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1; outline.stroke()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

private final class HaloResetButton: ClickCursorButton {
    var symbol = "arrow.counterclockwise"
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted { Design.rule.setFill(); bounds.fill() }
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip ?? "Reset Colour")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [Design.ink]))
        icon?.draw(in: NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16))
    }
}

/// Shared settings geometry: labels span two app columns; compact controls occupy the next two.
enum SettingsSheet {
    static let ground = Design.card
    static let row: CGFloat = 32
    static let dividerWeight: CGFloat = 3
    static let gutter = Design.App.gutter
    static let titleStyle = Design.Text.title
    static let indexStyle = Design.Text.headline
    static let indexSize: CGFloat = 80
    static let headerGuide = 2 * Design.App.unit + Design.App.textBaseline
    static let contentStart = 4 * Design.App.unit
    // Rule 1: the overlay and Rail 1 own the coordinates. No page-specific lift.
    static func baseline(_ row: CGFloat) -> CGFloat { row * Design.App.unit + Design.App.textBaseline }
    static func glyphBounds(_ text: NSAttributedString) -> CGRect {
        CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(text), .useGlyphPathBounds)
    }
    static var titleBaseline: CGFloat { baseline(1) }
    static var sectionTop: CGFloat { baseline(3) - glyphBounds(Design.attributed("// Motion", .bodyStrong)).maxY }
    static var sectionInset: CGFloat { sectionTop - headerGuide }
    static var schemaContentStart: CGFloat { 3 * Design.App.unit }
    static func buttonTop(baseline: CGFloat) -> CGFloat {
        let text = Design.attributed("Test Halo", .action)
        return baseline - ((SwissButton.height - text.size().height) / 2 + text.baselineFont.ascender)
    }
    /// The first paragraph baseline sits on its strong guide; subsequent lines use normal leading.
    static func paragraph(_ value: String, x: CGFloat, firstBaseline: CGFloat, width: CGFloat, height: CGFloat, colour: NSColor = Design.ink) {
        let storage = NSTextStorage(attributedString: Design.attributed(value, .caption, colour: colour, lineHeight: true))
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: height))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let range = layout.glyphRange(for: container)
        guard range.length > 0 else { return }
        let first = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY + layout.location(forGlyphAt: 0).y
        layout.drawGlyphs(forGlyphRange: range, at: NSPoint(x: x, y: firstBaseline - first))
    }
    /// Snap wrapped descriptions to the grid, retaining one clear row before the next setting.
    static func settingAdvance(_ text: String, width: CGFloat, paragraphOffset: CGFloat = 2) -> CGFloat {
        let storage = NSTextStorage(attributedString: Design.attributed(text, .caption, lineHeight: true))
        let layout = NSLayoutManager(), container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container)
        let range = layout.glyphRange(for: container)
        guard range.length > 0 else { return paragraphOffset + 1 }
        func baseline(_ glyph: Int) -> CGFloat { layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + layout.location(forGlyphAt: glyph).y }
        return paragraphOffset + ceil(max(0, baseline(range.length - 1) - baseline(0)) / Design.App.unit) + 1
    }
    static func settingGroups(_ descriptions: [String], width: CGFloat) -> (rows: [CGFloat], end: CGFloat) {
        var cursor: CGFloat = 5, rows: [CGFloat] = []
        for text in descriptions { rows.append(cursor); cursor += settingAdvance(text, width: width) }
        return (rows, cursor)
    }
    static func columns(width: CGFloat, window: CGFloat) -> [CGFloat] {
        Design.App.pageColumns(width: width, in: window).x
    }
    static func contentColumn(width: CGFloat, window: CGFloat) -> CGFloat {
        let grid = columns(width: width, window: window)
        return max(grid.first(where: { $0 >= 128 }) ?? 128,
                   grid.last(where: { $0 <= width - 360 }) ?? 0)
    }
    static func introduction(_ heading: String, _ detail: String, x: CGFloat, width: CGFloat, leading: CGFloat = 0) {
        if x - leading < 260 {
            Design.attributed(detail, .caption).draw(x: leading, baseline: baseline(2), width: width - leading)
        } else {
            Design.attributed(heading, .heading).draw(x: x, baseline: baseline(0))
            Design.attributed(detail, .caption).draw(x: x, baseline: titleBaseline, width: width - x)
        }
    }
    static func title(_ title: String, x: CGFloat = 0) {
        Design.attributed(title, titleStyle).draw(x: x, baseline: titleBaseline)
    }
    /// Thick rules grow upward from their grid guide, never below it.
    static func divider(above guide: CGFloat, x: CGFloat = 0, width: CGFloat) {
        fill(NSRect(x: x, y: guide - dividerWeight, width: width, height: dividerWeight), Design.ink)
    }
    static func index(_ value: Int, x: CGFloat = 0, top: CGFloat) {
        let label = Design.attributed(String(format: "%02d", value), indexStyle, size: indexSize)
        let glyph = glyphBounds(label)
        label.draw(x: x - glyph.minX, baseline: top + glyph.maxY)
    }
    static func section(_ value: Int, _ heading: String, guide: CGFloat, x: CGFloat = 0, contentX: CGFloat, width: CGFloat) {
        divider(above: guide, x: x, width: width)
        let top = guide + sectionInset
        index(value, x: x, top: top)
        let label = Design.attributed("// " + heading, .bodyStrong)
        label.draw(x: contentX, baseline: top + glyphBounds(label).maxY)
    }
}

final class HaloSettings: NSView, PageSection {
    var sectionAnchors: [(String,CGFloat)] { [("Motion",SettingsSheet.headerGuide+1),("Colours",SettingsSheet.baseline(7)+1)] }
    var onResize: (() -> Void)?
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private let speed = MiniSlider()
    private let test = SwissButton("Test Halo", .secondary)
    private var tester: HaloMenu?
    private let colourRows: [(title: String, prefix: String, cursor: Bool, layer: Int)] = [
        ("Information", "centre", false, 0),
        ("Primary Ring", "ring1", false, 1), ("Highlight Cursor", "ring1", true, 1),
        ("Secondary Ring", "ring2", false, 2), ("Highlight Cursor", "ring2", true, 2),
        ("Tertiary Ring", "ring3", false, 3), ("Highlight Cursor", "ring3", true, 3)
    ]
    private var wells: [(well: NSColorWell, part: String)] = []
    private var resets: [HaloResetButton] = []
    private let resetAll = SwissButton("Reset All Colours", .secondary)
    private var finalGuide: CGFloat { SettingsSheet.baseline(20) }
    private var colourStart: CGFloat { 9 * Self.u }
    private let colourRowHeight = Design.App.unit
    private var columns: [CGFloat] { SettingsSheet.columns(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    private var contentColumn: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    private var colourColumn: CGFloat { columns.dropLast().last ?? max(160, bounds.width - 176) }
    private var textColumn: CGFloat { columns.last ?? bounds.width - 80 }
    private var tableRight: CGFloat { bounds.width }
    private func rowY(_ i: Int) -> CGFloat { colourStart + CGFloat(i) * Self.u + CGFloat([1, 3, 5].filter { $0 <= i }.count) * Self.u }


    init() {
        super.init(frame: .zero)
        speed.onChange = { v in
            let r = Prefs.haloWheelSpeedRange
            Prefs.haloWheelSpeed = r.lowerBound + Double(v) * (r.upperBound - r.lowerBound)
        }
        test.target = self; test.action = #selector(testHalo)
        addSubview(speed); addSubview(test)
        for row in colourRows {
            for suffix in row.cursor ? ["cursorBackground", "cursorText"] : ["background", "text"] {
                let part = row.prefix + "." + suffix
                let well = HaloColourWell()
                well.part = part
                well.isBordered = false
                well.color = Theme.halo(part)
                well.target = self; well.action = #selector(colourChanged(_:))
                well.setAccessibilityLabel(row.title + " " + (suffix.lowercased().contains("background") ? "Background" : "Text") + " " + row.prefix)
                let reset = HaloResetButton(frame: .zero)
                reset.isBordered = false; reset.title = ""
                reset.tag = wells.count; reset.target = self; reset.action = #selector(resetColour(_:))
                let name = "Reset " + row.title + " " + (suffix.lowercased().contains("background") ? "Background" : "Text") + " " + row.prefix
                reset.toolTip = name; reset.setAccessibilityLabel(name)
                resets.append(reset); addSubview(reset)
                wells.append((well, part)); addSubview(well)
            }
        }
        resetAll.trailing = .none
        resetAll.target = self; resetAll.action = #selector(resetAllColours)
        addSubview(resetAll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        let r = Prefs.haloWheelSpeedRange
        speed.value = CGFloat((Prefs.haloWheelSpeed - r.lowerBound) / (r.upperBound - r.lowerBound))
        for item in wells { item.well.color = Theme.halo(item.part) }
        needsLayout = true; needsDisplay = true; onResize?()
    }
    func height(forWidth width: CGFloat) -> CGFloat { 24 * Self.u }

    override func layout() {
        super.layout()
        speed.frame = NSRect(x: colourColumn, y: SettingsSheet.baseline(4) - 13, width: max(96, tableRight - colourColumn), height: 16)
        test.frame = NSRect(x: contentColumn, y: SettingsSheet.buttonTop(baseline: SettingsSheet.baseline(6)), width: test.intrinsicContentSize.width, height: 32)
        for i in colourRows.indices {
            let y = rowY(i)
            wells[i * 2].well.frame = NSRect(x: colourColumn + 32, y: y + Self.line - 5 - 9, width: 32, height: 18)
            wells[i * 2 + 1].well.frame = NSRect(x: textColumn + 32, y: y + Self.line - 5 - 9, width: 32, height: 18)
            resets[i * 2].frame = NSRect(x: colourColumn, y: y + Self.line - 5 - 15, width: 24, height: 30)
            resets[i * 2 + 1].frame = NSRect(x: textColumn, y: y + Self.line - 5 - 15, width: 24, height: 30)
        }
        resetAll.frame = NSRect(x: contentColumn, y: SettingsSheet.buttonTop(baseline: finalGuide + 2 * Self.u), width: resetAll.intrinsicContentSize.width, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.ground.setFill(); bounds.fill()
        let ink = Design.ink
        func text(_ value: String, _ style: Design.Text, _ x: CGFloat, _ baseline: CGFloat, width: CGFloat? = nil) {
            Design.attributed(value, style, colour: ink).draw(x: x, baseline: baseline, width: width ?? bounds.width - x)
        }
        func rule(_ y: CGFloat, _ weight: CGFloat = 0.5, from x: CGFloat = 0) {
            ink.withAlphaComponent(weight > 1 ? 1 : 0.35).setFill()
            NSRect(x: x, y: y, width: tableRight - x, height: weight).fill()
        }
        SettingsSheet.title("Halo.")
        SettingsSheet.introduction("Behaviour & colour", "Four layers. One continuous gesture.", x: contentColumn, width: bounds.width)
        SettingsSheet.section(1, "Motion", guide: SettingsSheet.headerGuide, contentX: contentColumn, width: bounds.width)
        text("Mouse Sensitivity", .body, contentColumn, SettingsSheet.baseline(4), width: colourColumn - contentColumn - 16)
        text("Slower", .caption, colourColumn, SettingsSheet.baseline(5))
        Design.attributed("Faster", .caption, colour: ink).draw(right: tableRight, baseline: SettingsSheet.baseline(5))
        SettingsSheet.section(2, "Colours", guide: SettingsSheet.baseline(7), contentX: contentColumn, width: bounds.width)
        text("Background", .caption, colourColumn, SettingsSheet.baseline(8))
        text("Text", .caption, textColumn, SettingsSheet.baseline(8))
        for (i, row) in colourRows.enumerated() {
            let y = rowY(i)
            if !row.cursor && i > 0 { rule(y - Self.u + Self.line, from: contentColumn) }
            text(row.cursor ? "↳ Highlight Cursor" : row.title, row.cursor ? .caption : .body,
                 contentColumn, y + Self.line, width: colourColumn - contentColumn - 12)
        }
        SettingsSheet.divider(above: finalGuide, width: bounds.width)

    }

    @objc private func colourChanged(_ sender: NSColorWell) {
        guard let item = wells.first(where: { $0.well === sender }) else { return }
        Prefs.setHaloColour(hexOf(sender.color), item.part)
    }

    @objc private func resetColour(_ sender: NSButton) {
        guard wells.indices.contains(sender.tag) else { return }
        Prefs.setHaloColour(nil, wells[sender.tag].part)
        reload()
    }

    @objc private func resetAllColours() {
        for item in wells { Prefs.setHaloColour(nil, item.part) }
        reload()
    }

    @objc private func testHalo() {
        let halo = tester ?? HaloMenu(label: "Test Halo", hint: "Scroll to turn, click to choose", actions: [])
        tester = halo
        halo.actions = HaloSettingsPanel.letters { [weak halo] in halo?.back() }
        halo.open(over: test)
    }
}

/// One of the old window's pages held on the Studio page until it is redrawn: the controller's view, the page's full height at least.
final class EmbeddedSection: NSView, PageSection {
    var onResize: (() -> Void)?
    private let controller: NSViewController
    private let least: CGFloat
    init(_ controller: NSViewController, least: CGFloat = 720) {
        self.controller = controller
        self.least = least
        super.init(frame: .zero)
        // The old page's words are set for the old window's ground, so it keeps that ground until it is redrawn.
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        addSubview(controller.view)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func reload() { layer?.backgroundColor = Theme.background.cgColor; needsLayout = true }
    func height(forWidth width: CGFloat) -> CGFloat { least }
    override func layout() { super.layout(); controller.view.frame = bounds }
}

extension ShortcutsSettings {
    private func showError(_ error: Error) { NSApp.presentError(error) }
    private func currentProfile() throws -> KeyProfile { try KeyProfiles.ensure(); try KeyProfiles.saveCurrent(); return try KeyProfiles.read(KeyProfiles.activeURL) }

    @objc private func exportProfile() { exportForm() }
    private func exportForm(after: (() -> Void)? = nil) {
        do {
            let current = try currentProfile()
            let modal = SwissFocusModal(title: "Export Key Profile", message: "Name this set of shortcuts. A copy stays in Keys so you can select it again.")
            let name = modal.field("Heading", value: current.name)
            let detail = modal.field("Description", value: current.description)
            modal.button("Export", primary: true) { [weak self, weak modal] in
                guard let self, let modal, let win = self.window else { return }
                let heading = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !heading.isEmpty else { self.showError(failure("Enter a heading for this profile.")); return }
                let profile = KeyProfile(name: heading, description: detail.stringValue, shortcuts: current.shortcuts, quickKeys: current.quickKeys)
                let save = NSSavePanel(); save.allowedFileTypes = ["colkeys"]; save.nameFieldStringValue = filesystemName(heading) + ".colkeys"
                save.beginSheetModal(for: win) { result in
                    guard result == .OK, let url = save.url else { return }
                    do {
                        try KeyProfiles.write(profile, to: url)
                        if url.deletingLastPathComponent().standardizedFileURL != KeyProfiles.folder.standardizedFileURL { _ = try KeyProfiles.copyIn(profile) }
                        modal.dismissOverlay(); self.reload(); after?()
                    } catch { self.showError(error) }
                }
            }
            modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }
            modal.present(over: self)
        } catch { showError(error) }
    }
    @objc private func importProfile() {
        let modal = SwissFocusModal(title: "Import Key Profile", message: "Your current profile is saved in Keys. Would you also like to export a backup before importing another configuration?")
        modal.button("Save A Copy First", primary: true) { [weak self, weak modal] in
            modal?.dismissOverlay(); self?.exportForm { [weak self] in self?.chooseImport() }
        }
        modal.button("Import Without Exporting") { [weak self, weak modal] in modal?.dismissOverlay(); self?.chooseImport() }
        modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }
        modal.present(over: self)
    }
    private func chooseImport() {
        guard let win = window else { return }
        let open = NSOpenPanel(); open.allowedFileTypes = ["colkeys"]; open.allowsMultipleSelection = false
        open.beginSheetModal(for: win) { [weak self] result in
            guard let self, result == .OK, let url = open.url else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let profile = try KeyProfiles.read(url); try KeyProfiles.validate(profile)
                let local = try KeyProfiles.copyIn(profile)
                try KeyProfiles.activate(local); self.reload()
            } catch { self.showError(error) }
        }
    }
    @objc private func shareProfile() {
        do {
            let profile = try currentProfile()
            let modal = SwissFocusModal(title: "Share Key Profile", message: "Share “\(profile.name)” as a .colkeys attachment or copy its complete configuration.")
            modal.button("Mail", primary: true) { [weak self, weak modal] in
                do {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(filesystemName(profile.name) + ".colkeys")
                    try KeyProfiles.write(profile, to: url)
                    guard let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [url]) else { throw failure("Mail sharing is unavailable. Export the profile and attach it in your mail app.") }
                    mail.subject = profile.name; modal?.dismissOverlay(); mail.perform(withItems: [profile.description, url])
                } catch { self?.showError(error) }
            }
            modal.button("Direct Schema Copy") { [weak self, weak modal] in
                do {
                    let data = try ColourFiles.encoder().encode(profile)
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                    modal?.dismissOverlay()
                } catch { self?.showError(error) }
            }
            modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }
            modal.present(over: self)
        } catch { showError(error) }
    }
}

final class SoundsSettings: NSView, PageSection {
    var sectionAnchors: [(String,CGFloat)] { [("All Sounds",SettingsSheet.headerGuide+1),("Copy Swatch",SettingsSheet.baseline(6)+1),("Colour Pick",SettingsSheet.baseline(14)+1)] }
    var onResize: (() -> Void)?
    private let all = SwissButton("All Sounds: On", .secondary)
    private let copyToggle = SwissButton("Copy Swatch: On", .secondary)
    private let pickToggle = SwissButton("Colour Pick: On", .secondary)
    private let copyTest = HaloResetButton(frame: .zero)
    private let pickTest = HaloResetButton(frame: .zero)
    private var selectors: [SwissDropdown] = []
    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    init() {
        super.init(frame: .zero)
        for button in [copyTest, pickTest] { button.symbol = "speaker.wave.2"; button.title = ""; button.isBordered = false; button.toolTip = "Test Sound"; button.setAccessibilityLabel("Test Sound") }
        for (i, button) in ([all, copyToggle, pickToggle, copyTest, pickTest] as [NSButton]).enumerated() {
            button.tag = i; button.target = self; button.action = #selector(pressed(_:)); addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func reload() {
        all.title = "All Sounds: " + (Prefs.sounds ? "On" : "Off")
        copyToggle.title = "Copy Swatch: " + (AppSounds.enabled(.copy) ? "On" : "Off")
        pickToggle.title = "Colour Pick: " + (AppSounds.enabled(.pick) ? "On" : "Off")
        selectors.forEach { $0.removeFromSuperview() }; selectors = []
        for event in [AppSounds.Event.copy, .pick] {
            let selector = SwissDropdown("Sound", value: AppSounds.selection(event), options: AppSounds.choices, allowsOwn: false, width: 200)
            selector.onPreview = { AppSounds.preview($0) }
            selector.onChange = { name in AppPreferences.shared.set(name, forKey: "sound." + event.rawValue) }
            selectors.append(selector); addSubview(selector)
        }
        needsLayout = true; needsDisplay = true; onResize?()
    }
    @objc private func pressed(_ sender: NSButton) {
        switch sender.tag {
        case 0: Prefs.sounds.toggle()
        case 1, 2:
            let event: AppSounds.Event = sender.tag == 1 ? .copy : .pick
            AppPreferences.shared.set(!AppSounds.enabled(event), forKey: "sound." + event.rawValue + ".enabled")
        case 3: AppSounds.play(.copy, test: true)
        default: AppSounds.play(.pick, test: true)
        }
        reload()
    }
    func height(forWidth width: CGFloat) -> CGFloat { SettingsSheet.baseline(24) }
    override func layout() {
        super.layout()
        let x = contentX, width = max(140, bounds.width - x)
        for (button, row) in [(all, CGFloat(4)), (copyToggle, 9), (pickToggle, 17)] {
            button.frame = NSRect(x: x, y: SettingsSheet.buttonTop(baseline: SettingsSheet.baseline(row)), width: min(width, max(200, button.intrinsicContentSize.width)), height: 32)
        }
        for (i, selector) in selectors.enumerated() {
            let toggle = i == 0 ? copyToggle : pickToggle
            selector.frame = NSRect(x: x, y: SettingsSheet.baseline(i == 0 ? 10 : 18), width: toggle.frame.width, height: 56)
            let test = i == 0 ? copyTest : pickTest
            test.frame = NSRect(x: selector.frame.maxX + Design.App.gutter, y: selector.frame.maxY - 44, width: 32, height: 32)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title("Sounds.")
        SettingsSheet.introduction("Audio feedback", "Choose a sound for copying and picking colours.", x: contentX, width: bounds.width)
        SettingsSheet.section(1, "All Sounds", guide: SettingsSheet.headerGuide, contentX: contentX, width: bounds.width)
        SettingsSheet.section(2, "Copy Swatch", guide: SettingsSheet.baseline(6), contentX: contentX, width: bounds.width)
        SettingsSheet.section(3, "Colour Pick", guide: SettingsSheet.baseline(14), contentX: contentX, width: bounds.width)
        SettingsSheet.divider(above: SettingsSheet.baseline(23), width: bounds.width)
    }
}

/// Tabs share a leading direction glyph and a marker below their owning divider.
final class SectionAnchorButton: ClickCursorButton {
    var active = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let hover = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil)) } ?? false
        if hover { Design.mist.setFill(); bounds.fill() }
        RowMark.draw("arrow.down.right", x:0, baseline:17, colour: active ? Design.ink : Design.quiet)
        attributedTitle.draw(x:20,baseline:17,width:bounds.width-32)
        if active { Design.ink.setFill(); NSRect(x:20,y:28,width:min(attributedTitle.size().width,max(0,bounds.width-32)),height:2).fill() }
        if window?.firstResponder === self { Design.ink.setStroke(); NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke() }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.pointingHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))
    }
    override func mouseEntered(with event:NSEvent) { needsDisplay=true }
    override func mouseExited(with event:NSEvent) { needsDisplay=true }
}

/// Portable Library policies use the same numbered sheet and controls as Halo.
final class LibrarySettings: NSView, PageSection {
    var onResize: (() -> Void)?
    var sectionAnchors: [(String, CGFloat)] { [("Palette Settings", SettingsSheet.headerGuide + 1)] }
    private let toggles = [SwissButton("", .secondary), SwissButton("", .secondary), SwissButton("", .secondary), SwissButton("", .secondary)]
    private let names = ["Copy To Every Palette Bucket", "Retain Original In Library", "Create Claimed Library Copies", "Remove Associated Claimed Copies"]
    private let descriptions = [
        "Off: copy into the selected project bucket only. On: create a separate copy in every palette bucket of that project. Each copy can be edited independently.",
        "On: keep the original palette in the main Library. Off: remove the Library original after the project copy is saved. Palettes copied from another project remain in their original project.",
        "Keep an additional independent copy in Claimed Palettes, labelled with its project and bucket. Editing a claimed copy does not change the project copy. Available only while retaining the original.",
        "On: deleting a project palette also removes its associated copies from Claimed Palettes. Off: retain those independent Library copies. Other projects and unrelated Library palettes are unaffected."
    ]
    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    init() {
        super.init(frame: .zero)
        for (i, toggle) in toggles.enumerated() {
            toggle.tag = i; toggle.target = self; toggle.action = #selector(changed(_:))
            toggle.setAccessibilityLabel(names[i]); toggle.toolTip = descriptions[i]; addSubview(toggle)
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func reload() {
        let states = [Prefs.libraryCopyAllBuckets, Prefs.libraryKeepOriginal, Prefs.libraryKeepClaimed, Prefs.libraryRemoveClaimed]
        for i in toggles.indices { toggles[i].title = names[i] + ": " + (states[i] ? "On" : "Off") }
        toggles[2].isHidden = !Prefs.libraryKeepOriginal
        needsLayout = true; needsDisplay = true; onResize?()
    }
    @objc private func changed(_ sender: NSButton) {
        switch sender.tag {
        case 0: Prefs.libraryCopyAllBuckets.toggle()
        case 1: Prefs.libraryKeepOriginal.toggle()
        case 2: Prefs.libraryKeepClaimed.toggle()
        default: Prefs.libraryRemoveClaimed.toggle()
        }
        reload()
    }
    private var visibleIndices: [Int] { toggles.indices.filter { $0 != 2 || Prefs.libraryKeepOriginal } }
    private func geometry(_ width: CGFloat) -> (rows: [CGFloat], end: CGFloat) {
        let x = SettingsSheet.contentColumn(width: width, window: window?.frame.width ?? Design.App.size.width)
        return SettingsSheet.settingGroups(visibleIndices.map { descriptions[$0] }, width: max(140, width - x))
    }
    private func row(_ index: Int) -> CGFloat { visibleIndices.firstIndex(of: index).map { geometry(bounds.width).rows[$0] } ?? 5 }
    func height(forWidth width: CGFloat) -> CGFloat { SettingsSheet.baseline(geometry(width).end + 2) }
    override func layout() {
        super.layout()
        let width = max(140, bounds.width - contentX)
        for i in toggles.indices {
            let baseline = SettingsSheet.baseline(CGFloat(row(i)))
            toggles[i].frame = NSRect(x: contentX, y: SettingsSheet.buttonTop(baseline: baseline),
                width: min(width, max(200, toggles[i].intrinsicContentSize.width)), height: SwissButton.height)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title("Library.")
        SettingsSheet.introduction("Project palette copies", "Choose how Library palettes are assigned to project buckets.", x: contentX, width: bounds.width)
        SettingsSheet.section(1, "Palette Settings", guide: SettingsSheet.headerGuide, contentX: contentX, width: bounds.width)
        for i in toggles.indices where !toggles[i].isHidden {
            SettingsSheet.paragraph(descriptions[i], x: contentX,
                firstBaseline: SettingsSheet.baseline(CGFloat(row(i) + 2)), width: max(140, bounds.width - contentX), height: SettingsSheet.settingAdvance(descriptions[i], width: max(140, bounds.width - contentX)) * Design.App.unit)
        }
        SettingsSheet.divider(above: SettingsSheet.baseline(geometry(bounds.width).end), width: bounds.width)
    }
}

final class GeneralSettings: NSView, PageSection {
    var onResize: (() -> Void)?
    var onWizard: (() -> Void)?
    var onReset: (() -> Void)?
    var sectionAnchors: [(String, CGFloat)] { [("Setup & Preferences", SettingsSheet.headerGuide + 1)] }
    private let descriptions = ["Restore default app preferences. Your catalogues, palettes, colours, saved key profiles and folder access remain available. Completed setup stays complete.","Reopen the workspace setup wizard to review your catalogue structure. The wizard opens only when you request it; a completed workspace opens directly into the app."]
    private let reset = SwissButton("Reset App Preferences", .secondary)
    private let wizard = SwissButton("Open Setup Wizard", .secondary)
    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    init() {
        super.init(frame: .zero)
        reset.target = self; reset.action = #selector(resetPreferences)
        wizard.target = self; wizard.action = #selector(openWizard)
        for button in [reset, wizard] { addSubview(button) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func reload() { needsLayout = true; needsDisplay = true }
    private func geometry(_ width: CGFloat) -> (rows: [CGFloat], end: CGFloat) {
        let x = SettingsSheet.contentColumn(width: width, window: window?.frame.width ?? Design.App.size.width)
        return SettingsSheet.settingGroups(descriptions, width: max(140, width - x))
    }
    func height(forWidth width: CGFloat) -> CGFloat { SettingsSheet.baseline(geometry(width).end + 2) }
    override func layout() {
        super.layout()
        for (button, row) in zip([reset, wizard], geometry(bounds.width).rows) {
            button.frame = NSRect(x: contentX, y: SettingsSheet.buttonTop(baseline: SettingsSheet.baseline(CGFloat(row))), width: min(bounds.width - contentX, button.intrinsicContentSize.width), height: SwissButton.height)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title("General.")
        SettingsSheet.introduction("Your workspace", "Manage app preferences and revisit the setup wizard.", x: contentX, width: bounds.width)
        SettingsSheet.section(1, "Setup & Preferences", guide: SettingsSheet.headerGuide, contentX: contentX, width: bounds.width)
        SettingsSheet.paragraph(descriptions[0], x: contentX, firstBaseline: SettingsSheet.baseline(geometry(bounds.width).rows[0] + 2), width: bounds.width - contentX, height: SettingsSheet.settingAdvance(descriptions[0], width: max(140, bounds.width - contentX)) * Design.App.unit)
        SettingsSheet.paragraph(descriptions[1], x: contentX, firstBaseline: SettingsSheet.baseline(geometry(bounds.width).rows[1] + 2), width: bounds.width - contentX, height: SettingsSheet.settingAdvance(descriptions[1], width: max(140, bounds.width - contentX)) * Design.App.unit)
        SettingsSheet.divider(above: SettingsSheet.baseline(geometry(bounds.width).end), width: bounds.width)
    }
    @objc private func resetPreferences() {
        SwissConfirm.ask(over: window, title: "Reset App Preferences", note: "Restore default app preferences while keeping your catalogues, assets and completed setup. Slide across to reset.", commit: "Reset") { [weak self] in
            do { try AppPreferences.shared.resetUserPreferences(); self?.reload(); self?.onReset?() }
            catch { NSApp.presentError(error) }
        }
    }
    @objc private func openWizard() { onWizard?() }
}

/// Settings groups share the existing routes, so bookmarks and Escape keep their meaning.
enum SettingsNavigation {
    struct Group {
        let title: String
        let tabs: [(String, StudioFrame.Place)]
    }
    static var groups: [Group] {
        var app: [(String, StudioFrame.Place)] = [("General", .general), ("Shortcuts", .shortcuts), ("Halo", .halo), ("Sounds", .sounds)]
        app.append(("Apple Menubar", .appleMenubar))
        return [Group(title: "App & Interaction", tabs: app),
                Group(title: "Library & Data", tabs: [("Library", .librarySettings), ("Catalogues", .settings), ("Tags", .tags), ("Schema", .schema)]),
                Group(title: "Colour Management", tabs: [("Profiles & Proofing", .colourManagement(0)), ("Measurements & Spectral Viewing", .colourManagement(1)), ("Display & Viewing Environment", .colourManagement(2))]),
                Group(title: "Connections & Sharing", tabs: [("Appbridge", .appbridgeSettings), ("Sharing", .sharingSettings)])]
    }
    static func group(for place: StudioFrame.Place) -> Group? {
        groups.first { $0.tabs.contains { $0.1 == place } }
    }
}

/// Capability setup only: no imported measurements or calculated relighting are claimed.
final class ColourManagementSettings: NSView, PageSection {
    var onResize: (() -> Void)?
    var onProfiles: (() -> Void)?
    private let index: Int
    private let action = SwissButton("Open Viewing Profiles…", .secondary)
    private let output = SwissButton("Output Proof: Off", .secondary)
    private var x: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    private var descriptions: [String] {
        switch index {
        case 0: return ["Manage saved viewing profiles, output targets, rendering intent and difference tolerances in the shared Preset editor. Opens your palette workspace and its Preset dropdown.", "Output Proof compares the stored colour preview with the selected output target. This global choice also applies to palette and swatch views; it is a prediction, not a measured approval."]
        case 1: return ["Import measured reflectance spectra, link each sample to its actual swatch and enable Spectral Viewing in the shared Settings window. Choose the observer there and D50, D65 or A in the palette actionbar.", "Supported input: CxF3 reflectance fractions, 1–10 nm intervals, covering at least 380–730 nm. Confirm opaque, non-fluorescent material before linking. The original CxF and declared conditions are retained; RGB or Lab values alone are insufficient."]
        default: return ["An on-screen preview depends on your display profile and viewing environment. Colorgain does not currently measure or calibrate your display. Manage display calibration and the display profile in macOS or your calibration software.", "D50 and D65 describe standard daylight illuminants; A describes a different standard illuminant. Selecting one does not change the monitor calibration or prove how an unmeasured material will look under that light."]
        }
    }
    private var headings: [String] {
        index == 0 ? ["Viewing Profiles", "Output Proof"] : index == 1 ? ["Spectral Viewing", "Measurement Files"] : ["Display", "Viewing Conditions"]
    }
    var sectionAnchors: [(String, CGFloat)] { headings.enumerated().map { ($0.element, guide($0.offset) + 1) } }
    private func advance(_ i: Int, width: CGFloat) -> CGFloat { max(6, SettingsSheet.settingAdvance(descriptions[i], width: max(140, width), paragraphOffset: 2) + 3) }
    private func guide(_ i: Int) -> CGFloat { SettingsSheet.headerGuide + (i == 0 ? 0 : advance(0, width: bounds.width - x) * Design.App.unit) }
    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        action.target = self; action.action = #selector(openProfiles)
        output.target = self; output.action = #selector(toggleOutput)
        if index == 1 { action.title="Open Spectral Measurements…" }
        action.isHidden = index > 1; output.isHidden = index != 0
        addSubview(action); addSubview(output)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .prefsDidChange, object: nil)
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    override var isFlipped: Bool { true }
    func reload() { refresh() }
    @objc private func refresh() {
        output.title = "Output Proof: " + (Prefs.deltaWarningsEnabled ? "On" : "Off")
        output.invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true
    }
    func height(forWidth width: CGFloat) -> CGFloat {
        let cx = SettingsSheet.contentColumn(width: width, window: window?.frame.width ?? Design.App.size.width)
        return SettingsSheet.headerGuide + (advance(0, width: width - cx) + advance(1, width: width - cx)) * Design.App.unit
    }
    override func layout() {
        super.layout()
        for (i, button) in [action, output].enumerated() {
            button.frame = NSRect(x: x, y: SettingsSheet.buttonTop(baseline: guide(i) + 2 * Design.App.unit), width: min(max(0, bounds.width - x), button.intrinsicContentSize.width), height: SwissButton.height)
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title(index == 0 ? "Proofing." : index == 1 ? "Spectral." : "Viewing.")
        SettingsSheet.introduction("Colour Management", index == 0 ? "Profiles and output comparison." : index == 1 ? "Measured materials and lighting." : "Display and environment.", x: x, width: bounds.width)
        for i in 0..<2 {
            let g = guide(i)
            SettingsSheet.section(i + 1, headings[i], guide: g, contentX: x, width: bounds.width)
            SettingsSheet.paragraph(descriptions[i], x: x, firstBaseline: g + (index == 0 ? 4 : 3) * Design.App.unit, width: bounds.width - x, height: (advance(i, width: bounds.width - x) - 3) * Design.App.unit)
        }
        SettingsSheet.divider(above: height(forWidth: bounds.width) - Design.App.unit, width: bounds.width)
    }
    @objc private func openProfiles() {
        if index == 1,let delegate=NSApp.delegate as? AppDelegate { delegate.showSettings();delegate.settings?.showSpectralViewing() }
        else { onProfiles?() }
    }
    @objc private func toggleOutput() { Prefs.deltaWarningsEnabled.toggle() }
}
