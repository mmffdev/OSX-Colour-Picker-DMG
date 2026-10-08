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
}

/// The single keys that work anywhere in the window: what they do, and the key each is on.
enum QuickKeys {
    struct Command { let id: String; let title: String; let fallback: String }
    static let commands = [Command(id: "newPalette", title: "New Palette", fallback: "1"),
                           Command(id: "pick", title: "Picker", fallback: "2"),
                           Command(id: "sample", title: "Rectangle Picker", fallback: "\u{21E7}2")]
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

final class ShortcutsSettings: NSView, PageSection {
    var onResize: (() -> Void)?
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    /// Which row is taking a key: a quick key by id, or a menu command by id.
    private enum Recording: Equatable { case quick(String), menu(String) }
    private var recording: Recording?
    private var problem = ""
    private var hits: [(NSRect, Recording)] = []
    private var clearHits: [(NSRect, Recording)] = []
    private let restore = SwissButton("Restore Defaults", .secondary)

    init() {
        super.init(frame: .zero)
        restore.target = self; restore.action = #selector(restoreDefaults)
        addSubview(restore)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func reload() { recording = nil; needsLayout = true; needsDisplay = true; onResize?() }

    private var menuCommands: [Shortcuts.Command] { Shortcuts.commands }

    func height(forWidth width: CGFloat) -> CGFloat {
        let u = Self.u
        var rows: CGFloat = 1 + 3 + 1 + CGFloat(QuickKeys.commands.count) + 2   // header, words, label, keys, air
        var menu = ""
        for c in menuCommands { if c.menu != menu { menu = c.menu; rows += 2 }; rows += 1 }
        return rows * u + 3 * u + 3 * u
    }

    override func layout() {
        super.layout()
        let h = height(forWidth: bounds.width)
        restore.frame = NSRect(x: 0, y: h - 3 * Self.u - 32 - 4, width: restore.intrinsicContentSize.width, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let u = Self.u, line = Self.line, w = bounds.width
        hits = []; clearHits = []
        Design.attributed("Shortcuts", .body).draw(x: 0, baseline: line)
        Design.attributed("Quick keys are single keys that work anywhere in the window while nothing is being typed. Menu commands keep the shortcuts in the menu bar; those need \u{2318} or \u{2303}. Click a key to change it, then type the new one; Delete takes it off, Escape leaves it.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: u, width: min(w, 560), height: 3 * u))
        var y = 4 * u
        func row(_ title: String, _ value: String, _ id: Recording) {
            let b = y + line
            Design.attributed(title, .body).draw(x: Self.u / 2 + 4, baseline: b, width: w / 2)
            let on = recording == id
            let t = Design.attributed(on ? "Type the key\u{2026}" : (value.isEmpty ? "None" : value), .body, colour: on ? Design.ink : value.isEmpty ? Design.soft : Design.ink)
            let vx = (w / 2).rounded()
            t.draw(x: vx, baseline: b)
            hairline(x: vx, y: y + u - 1, width: w / 2 - 40, on ? Design.ink : Design.rule)
            hits.append((NSRect(x: vx, y: y, width: w / 2 - 40, height: u), id))
            if !value.isEmpty && !on {
                // The cross at the right takes the key off.
                let g = NSRect(x: w - 16, y: b - 12, width: 10, height: 10)
                Design.quiet.setStroke()
                let p = NSBezierPath(); p.lineWidth = 1.1
                p.move(to: NSPoint(x: g.minX, y: g.minY)); p.line(to: NSPoint(x: g.maxX, y: g.maxY)); p.move(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.minX, y: g.maxY))
                p.stroke()
                clearHits.append((g.insetBy(dx: -6, dy: -6), id))
            }
            y += u
        }
        Design.attributed("Quick Keys", .label, colour: Design.quiet).draw(x: 0, baseline: y + line); y += u
        for c in QuickKeys.commands { row(c.title, QuickKeys.key(for: c.id), .quick(c.id)) }
        y += u
        var menu = ""
        for c in menuCommands {
            if c.menu != menu {
                menu = c.menu
                y += u
                Design.attributed(menu, .label, colour: Design.quiet).draw(x: 0, baseline: y + line); y += u
            }
            row(c.title, c.shortcut?.display ?? "", .menu(c.id))
        }
        if !problem.isEmpty { Design.attributed(problem, .caption, colour: Design.orange).draw(x: 0, baseline: y + u + line) }
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

final class HaloSettings: NSView, PageSection {
    var onResize: (() -> Void)?
    private static var u: CGFloat { Design.App.unit }
    private static var line: CGFloat { Design.App.textBaseline }
    private let speed = MiniSlider()
    private let test = SwissButton("Test Halo", .secondary)
    private var tester: HaloMenu?

    init() {
        super.init(frame: .zero)
        speed.onChange = { v in
            let r = Prefs.haloWheelSpeedRange
            Prefs.haloWheelSpeed = r.lowerBound + Double(v) * (r.upperBound - r.lowerBound)
        }
        test.target = self; test.action = #selector(testHalo)
        addSubview(speed); addSubview(test)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func reload() {
        let r = Prefs.haloWheelSpeedRange
        speed.value = CGFloat((Prefs.haloWheelSpeed - r.lowerBound) / (r.upperBound - r.lowerBound))
        needsLayout = true; needsDisplay = true; onResize?()
    }
    func height(forWidth width: CGFloat) -> CGFloat { 12 * Self.u }

    override func layout() {
        super.layout()
        let u = Self.u, line = Self.line
        let column = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        speed.frame = NSRect(x: (bounds.width / 2).rounded(), y: 5 * u + line - 12, width: column * 2, height: 16)
        test.frame = NSRect(x: (bounds.width / 2).rounded(), y: 7 * u + line - 22, width: test.intrinsicContentSize.width, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        let u = Self.u, line = Self.line, w = bounds.width
        Design.attributed("Halo", .body).draw(x: 0, baseline: line)
        Design.attributed("The halo is the ring menu over a gear or a swatch. Scrolling turns it; this sets how far the wheel or trackpad has to move to turn a ring by one place. Test Halo opens a halo of letters three rings deep: Up grows the next ring, the back arrow steps back one, and X closes it.", .caption, colour: Design.quiet, lineHeight: true)
            .draw(in: NSRect(x: 0, y: u, width: min(w, 560), height: 3 * u))
        Design.attributed("Scrolling", .label, colour: Design.quiet).draw(x: 0, baseline: 4 * u + line)
        Design.attributed("Mouse Sensitivity", .body).draw(x: u / 2 + 4, baseline: 5 * u + line)
        let vx = (w / 2).rounded(), column = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        Design.attributed("Slower", .caption, colour: Design.quiet).draw(x: vx, baseline: 6 * u + line)
        Design.attributed("Faster", .caption, colour: Design.quiet).draw(right: vx + column * 2, baseline: 6 * u + line)
        Design.attributed("Try It", .body).draw(x: u / 2 + 4, baseline: 7 * u + line)
        Design.attributed("Colours", .label, colour: Design.quiet).draw(x: 0, baseline: 9 * u + line)
        Design.attributed("The halo's own colours come with the redesign; until then it wears the old window's.", .caption, colour: Design.quiet).draw(x: u / 2 + 4, baseline: 10 * u + line)
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
