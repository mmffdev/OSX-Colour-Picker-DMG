import AppKit
import QuartzCore

// The halo: a circular popover of actions, built like an instrument dial. Actions orbit a fixed
// wedge at twelve o'clock; the ring turns, the glyphs stay upright, and the centre names whichever
// action sits under the wedge or the pointer. A port of Platform's HaloMenu, same measurements.
//
//     let halo = HaloMenu(label: "Swatch", actions: [...])
//     halo.attach(to: button)      // opens on hover and on click
//     halo.open(from: view)        // or open it yourself, under any view
//
// Whoever owns the trigger keeps the HaloMenu alive; nothing else holds on to it.

struct HaloAction {
    let id: String
    var label: String
    var icon: NSImage
    var description: String? = nil
    var disabled = false
    /// nil for a plain action; true or false for one that shows a tick dot.
    var checked: Bool? = nil
    /// Set to make the action ask for a slide across the centre before it fires.
    var confirmation: (label: String, keyboardHint: String)? = nil
    /// Leaves the dial open after `onSelect`, for an action that swaps in another ring.
    var keepsOpen = false
    /// Set to make the action open a text box in the centre; Return hands back what was typed.
    var edit: (value: String, placeholder: String, hint: String, onCommit: (String) -> Void)? = nil
    var onSelect: () -> Void = {}
    /// Set to make the action grow a ring of its own outside the one it sits on, holding these. Declared
    /// after onSelect so a trailing closure on either initialiser is the action, never the ring.
    var children: (() -> [HaloAction])? = nil
}

extension HaloAction {
    init(id: String, label: String, symbol name: String, description: String? = nil, disabled: Bool = false,
         checked: Bool? = nil, confirmation: (label: String, keyboardHint: String)? = nil, keepsOpen: Bool = false,
         edit: (value: String, placeholder: String, hint: String, onCommit: (String) -> Void)? = nil,
         onSelect: @escaping () -> Void = {}, children: (() -> [HaloAction])? = nil) {
        self.init(id: id, label: label, icon: NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage(),
                  description: description, disabled: disabled, checked: checked, confirmation: confirmation, keepsOpen: keepsOpen, edit: edit, onSelect: onSelect, children: children)
    }
}

/// One ring's colours: the band and what is drawn on it, and the cursor, which is the wedge at
/// twelve o'clock that marks the choice, and what is drawn inside it.
struct HaloRingColours {
    var band: NSColor, bandInk: NSColor, cursor: NSColor, cursorInk: NSColor
}

struct HaloPalette {
    /// The circle in the middle, where the halo says what is under the cursor.
    var centre: NSColor, centreInk: NSColor
    /// The first ring, then the rings that grow outside it. A ring past the last uses the last.
    var rings: [HaloRingColours]

    func ring(_ level: Int) -> HaloRingColours { rings[min(max(level, 0), rings.count - 1)] }

    /// Platform's own colours: a pale band around a dark centre.
    static let platform: HaloPalette = {
        let pale = NSColor(srgbRed: 0xEC / 255, green: 0xF0 / 255, blue: 0xF5 / 255, alpha: 1)
        let dark = NSColor(srgbRed: 0x22 / 255, green: 0x2A / 255, blue: 0x37 / 255, alpha: 1)
        return HaloPalette(centre: dark, centreInk: pale, rings: [HaloRingColours(band: pale, bandInk: dark, cursor: dark, cursorInk: pale)])
    }()

    /// The colours set in Settings, under Theme. Unset, the centre and the cursors are the
    /// buttons' own colours and the rings are those colours turned round.
    static var theme: HaloPalette {
        HaloPalette(centre: Theme.halo("centre.background"), centreInk: Theme.halo("centre.text"),
                    rings: (1...3).map { n in
                        HaloRingColours(band: Theme.halo("ring\(n).background"), bandInk: Theme.halo("ring\(n).text"),
                                        cursor: Theme.halo("ring\(n).cursorBackground"), cursorInk: Theme.halo("ring\(n).cursorText"))
                    })
    }
}

extension Theme {
    /// One of the halo's colours by the name Settings saves it under: "centre.background",
    /// "ring2.cursorText" and so on.
    static func halo(_ part: String) -> NSColor {
        if let set = Prefs.haloColour(part).flatMap(colorFromHex) { return set }
        return (haloDefault(part).usingColorSpace(.sRGB) ?? haloDefault(part))
    }

    static func haloDefault(_ part: String) -> NSColor { haloDefaultIsText(part) ? text : buttonRest }

    /// Whether a part's default is the buttons' text colour; otherwise it is their background.
    /// A ring is the button turned round, so its background is the text colour and its text the background.
    static func haloDefaultIsText(_ part: String) -> Bool {
        let reversed = part.hasPrefix("ring") && !part.contains("cursor")
        return part.hasSuffix("ext") != reversed
    }
}

/// The dial's arithmetic, kept apart from the drawing so the self-test can reach it.
enum HaloGeometry {
    static let fullDiameter: CGFloat = 344
    static let compactBelow: CGFloat = 290

    static func wrap(_ index: Int, _ count: Int) -> Int {
        count > 0 ? ((index % count) + count) % count : 0
    }

    /// Where the dial sits on screen: centred under the trigger, 8 points clear of it and of every
    /// screen edge, shrinking when the screen is smaller than the dial. Screen coordinates, y up.
    static func frame(below trigger: CGRect, in visible: CGRect) -> CGRect {
        let d = max(1, min(fullDiameter, visible.width - 16, visible.height - 16))
        func clamp(_ n: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(n, low), high) }
        return CGRect(x: clamp(trigger.midX - d / 2, visible.minX + 8, visible.maxX - d - 8),
                      y: clamp(trigger.minY - 8 - d, visible.minY + 8, visible.maxY - d - 8),
                      width: d, height: d)
    }

    /// The dial with its centre on `point`, moved only as far as it takes to keep it, and the
    /// `reach` of any rings that can grow outside it, 8 points inside the screen.
    static func frame(over point: CGPoint, reach: CGFloat, in visible: CGRect) -> CGRect {
        let d = max(1, min(fullDiameter, visible.width - 16, visible.height - 16))
        func place(_ c: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            let whole = d / 2 + reach + 8
            let clear = high - low >= whole * 2 ? whole : d / 2 + 8   // no room for the outer rings: keep the dial itself in
            return min(max(c, low + clear), high - clear)
        }
        return CGRect(x: place(point.x, visible.minX, visible.maxX) - d / 2, y: place(point.y, visible.minY, visible.maxY) - d / 2, width: d, height: d)
    }

    // A ring grown outside the first is a band of its own, a hair clear of the ring inside it.
    static let ringBand: CGFloat = 56
    static let ringGap: CGFloat = 2
    /// The most rings a halo makes room for outside its first.
    static let outerRings = 3

    /// How far `rings` outer rings reach past the dial's edge.
    static func reach(rings: Int) -> CGFloat { CGFloat(max(rings, 0)) * (ringBand + ringGap) }

    /// The inner and outer edge of a ring, from the dial's centre. Level 0 is the dial's own band.
    static func band(of level: Int, diameter: CGFloat) -> (near: CGFloat, far: CGFloat) {
        guard level > 0 else { return (centreRadius(diameter) + 3, diameter / 2) }
        let near = diameter / 2 + ringGap + CGFloat(level - 1) * (ringBand + ringGap)
        return (near, near + ringBand)
    }

    /// The circle a ring's glyphs ride.
    static func orbit(of level: Int, diameter: CGFloat) -> CGFloat {
        let band = band(of: level, diameter: diameter)
        return level > 0 ? (band.near + band.far) / 2 : orbitRadius(diameter)
    }

    static func target(of level: Int, diameter: CGFloat, count: Int) -> CGFloat {
        guard level > 0 else { return targetSize(diameter, count: count) }
        return max(24, min(40, 2 * .pi * orbit(of: level, diameter: diameter) / CGFloat(max(count, 1)) - 6))
    }

    /// Half the cursor wedge's angle, in radians. An outer ring's wedge is as wide as its glyph
    /// and a little more, and never wider than one place on the ring.
    static func halfWedge(of level: Int, diameter: CGFloat, count: Int) -> CGFloat {
        guard level > 0 else { return sector(count: count) * .pi / 360 }
        let wide = (target(of: level, diameter: diameter, count: count) / 2 + 8) / orbit(of: level, diameter: diameter)
        return min(wide, .pi / CGFloat(max(count, 1)))
    }

    /// Which ring a distance from the centre falls on; nil in the centre disc or in a gap.
    static func level(at radius: CGFloat, rings: Int, diameter: CGFloat) -> Int? {
        (0..<rings).first { radius > band(of: $0, diameter: diameter).near && radius <= band(of: $0, diameter: diameter).far }
    }

    /// The centre disc's radius; a 3 point ink ring sits just outside it.
    static func centreRadius(_ diameter: CGFloat) -> CGFloat { diameter * 0.32 }

    /// The circle the glyphs ride: midway across the band.
    static func orbitRadius(_ diameter: CGFloat) -> CGFloat {
        max(0, (diameter * 0.5 + centreRadius(diameter) + 3) / 2)
    }

    static func targetSize(_ diameter: CGFloat, count: Int) -> CGFloat {
        max(24, min(40, 2 * .pi * orbitRadius(diameter) / CGFloat(max(count, 1)) - 6))
    }

    /// The wedge's angle in degrees.
    static func sector(count: Int) -> CGFloat {
        max(20, min(36, 360 / CGFloat(max(count, 1))))
    }

    /// An action's offset from the dial's centre, y down, once the ring has turned by `turn` places.
    static func offset(of at: Int, count: Int, turn: CGFloat, radius: CGFloat) -> CGPoint {
        let angle = (CGFloat(at) - turn) * 2 * .pi / CGFloat(max(count, 1)) - .pi / 2
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    /// How many places to turn to reach the next action that can be chosen; nil when none can.
    static func step(from selected: Int, direction: Int, disabled: [Bool]) -> Int? {
        guard !disabled.isEmpty else { return nil }
        for step in 1...disabled.count where !disabled[wrap(selected + direction * step, disabled.count)] {
            return direction * step
        }
        return nil
    }

    /// How far the wheel has to travel, in points, to turn a ring one place. At the standard
    /// speed it is 44; a faster setting needs less travel and a slower one more.
    static func wheelStep(speed: CGFloat) -> CGFloat { 44 / max(speed, 0.1) }

    /// The action the dial opens on.
    static func opening(disabled: [Bool], checked: [Bool?], showPositions: Bool) -> Int {
        if showPositions, let at = disabled.indices.first(where: { checked[$0] == true && !disabled[$0] }) { return at }
        return max(0, disabled.firstIndex(of: false) ?? 0)
    }

    /// The confirmation slider after one arrow key.
    static func nudge(_ progress: CGFloat, by tenths: CGFloat) -> CGFloat {
        max(0, min(1, ((progress + tenths / 10) * 10).rounded() / 10))
    }
}

/// One ring of actions and how far it has turned.
fileprivate struct HaloRing {
    var actions: [HaloAction]
    /// Counts every place the ring has turned, so it never unwinds the long way round.
    var index = 0
    var turnFrom: CGFloat = 0
    var turnStart: CFTimeInterval = 0
    /// When the ring began to grow; 0 for one that is simply there.
    var grown: CFTimeInterval = 0
}

final class HaloMenu: NSResponder {
    /// The first ring's actions. An action with `children` grows a ring of its own outside.
    var actions: [HaloAction] {
        get { rings[0].actions }
        set {
            if rings.count == 1, newValue.map({ $0.id }) == rings[0].actions.map({ $0.id }) {
                rings[0].actions = newValue
            } else {   // a different ring: start it from its own opening place
                rings = [ring(of: newValue)]
                leaving = nil
            }
            if confirmationID != nil && confirming == nil { confirmationID = nil }
            hovered = nil
            refresh()
        }
    }
    /// The first ring, then each ring grown outside it. The last is the one being worked.
    fileprivate var rings: [HaloRing]
    /// A ring that has been stepped back from, while it shrinks away.
    fileprivate var leaving: (ring: HaloRing, start: CFTimeInterval)?
    /// How many rings these actions can grow, which is how much room the panel leaves.
    private var room = 0
    /// Names the menu, and fills the centre when there are no actions.
    var label: String
    var caption: String?
    var hint: String?
    var closeLabel: String
    var typeBadge: (icon: NSImage, label: String, name: String?)?
    var metadata: [(label: String, value: String)] = []
    /// Shows a row of initials in the centre, and opens on the ticked action.
    var showPositions = false
    /// Colours of its own; nil follows Settings, Theme, Halo.
    var palette: HaloPalette?
    fileprivate var colours: HaloPalette { palette ?? .theme }
    var onOpenChange: ((Bool) -> Void)?
    var isOpen: Bool { phase == .opening || phase == .open }

    fileprivate enum Phase { case closed, opening, open, closing }
    fileprivate var phase = Phase.closed
    private var phaseStart: CFTimeInterval = 0
    fileprivate var hovered: String?
    fileprivate var confirmationID: String?
    /// The action whose text box is open in the centre.
    fileprivate var editingID: String?
    /// A confirmation or a text box has the centre; the ring waits.
    fileprivate var busy: Bool { confirmationID != nil || editingID != nil }
    fileprivate var confirmStart: CFTimeInterval = 0
    fileprivate var progress: CGFloat = 0
    fileprivate var keyboardFocus = false
    fileprivate var closeFocused = false

    private weak static var current: HaloMenu?
    private weak var trigger: NSView?
    private weak var anchor: NSView?
    private var anchorRect: NSRect?
    /// Opened in the middle of a view by a press: the wheel turns the ring wherever the pointer
    /// is, and the pointer wandering off does not close it.
    private var sticky = false
    private var hoverArea: NSTrackingArea?
    private var exitTimer: Timer?
    private var ticker: Timer?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var wheelDistance: CGFloat = 0
    private var wheelAt: CFTimeInterval = 0
    private let panel = HaloPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let dial = HaloDialView()

    init(label: String, caption: String? = nil, hint: String? = nil, closeLabel: String = "Close", actions: [HaloAction]) {
        self.label = label
        self.caption = caption
        self.hint = hint
        self.closeLabel = closeLabel
        rings = [HaloRing(actions: actions)]
        super.init()
        dial.halo = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = dial
    }

    required init?(coder: NSCoder) { fatalError("HaloMenu is built in code") }

    deinit {
        detach()
        exitTimer?.invalidate()
        ticker?.invalidate()
        removeWatchers()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    // ---------- Attaching ----------

    /// Makes `view` the trigger: the halo opens when the pointer rests on it and, for a button or
    /// any other control, when it is pressed. Takes over the control's target and action.
    func attach(to view: NSView, opensOnHover: Bool = true) {
        detach()
        trigger = view
        if opensOnHover {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            view.addTrackingArea(area)
            hoverArea = area
        }
        if let control = view as? NSControl {
            control.target = self
            control.action = #selector(triggerPressed)
        }
    }

    func detach() {
        if let area = hoverArea { trigger?.removeTrackingArea(area) }
        hoverArea = nil
        if let control = trigger as? NSControl, control.target === self { control.target = nil; control.action = nil }
        trigger = nil
    }

    @objc private func triggerPressed() { open(focus: true) }

    override func mouseEntered(with event: NSEvent) {
        guard (trigger as? NSControl)?.isEnabled != false else { return }
        clearExit()
        open(focus: false)
    }

    override func mouseExited(with event: NSEvent) { leave() }

    // ---------- Opening and closing ----------

    /// Opens under `view` (or the attached trigger), or under `rect` within it. `focus` hands the
    /// dial the keyboard; without it the dial follows the pointer and leaves the keyboard alone.
    func open(from view: NSView? = nil, rect: NSRect? = nil, focus: Bool = true) {
        guard let view = view ?? trigger, let host = view.window else { return }
        if isOpen {
            if focus { takeKeyboard() }
            return
        }
        let onScreen = host.convertToScreen(view.convert(rect ?? view.bounds, to: nil))
        let visible = (host.screen ?? NSScreen.main)?.visibleFrame ?? onScreen
        present(HaloGeometry.frame(below: onScreen, in: visible), over: host, anchor: view, rect: rect, sticky: false, focus: focus)
    }

    /// Opens with its centre on `trigger`, holding the keyboard and the scroll wheel until
    /// something is chosen, Escape is pressed at the first ring, or a click lands anywhere else.
    func open(over trigger: NSView) {
        guard let host = trigger.window else { return }
        if isOpen { close() }
        let onScreen = host.convertToScreen(trigger.convert(trigger.bounds, to: nil))
        let visible = (host.screen ?? NSScreen.main)?.visibleFrame ?? onScreen
        let reach = HaloGeometry.reach(rings: depth(of: actions, limit: HaloGeometry.outerRings))
        present(HaloGeometry.frame(over: CGPoint(x: onScreen.midX, y: onScreen.midY), reach: reach, in: visible),
                over: host, anchor: trigger, rect: nil, sticky: true, focus: true)
    }

    /// Opens with its centre on a rect of a view, the icon or the tile that was pressed, so the pointer starts inside the dial:
    /// placed anywhere else, the dial sees the pointer outside it and closes itself at once.
    func open(centredOn rect: NSRect, in view: NSView) {
        guard let host = view.window else { return }
        if isOpen { close() }
        let onScreen = host.convertToScreen(view.convert(rect, to: nil))
        let visible = (host.screen ?? NSScreen.main)?.visibleFrame ?? onScreen
        let reach = HaloGeometry.reach(rings: depth(of: actions, limit: HaloGeometry.outerRings))
        present(HaloGeometry.frame(over: CGPoint(x: onScreen.midX, y: onScreen.midY), reach: reach, in: visible),
                over: host, anchor: view, rect: rect, sticky: true, focus: true)
    }

    /// How many rings deep these actions go beyond their own.
    private func depth(of actions: [HaloAction], limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        return actions.compactMap { $0.children }.map { 1 + depth(of: $0(), limit: limit - 1) }.max() ?? 0
    }

    private func present(_ frame: CGRect, over host: NSWindow, anchor view: NSView?, rect: NSRect?, sticky: Bool, focus: Bool) {
        if let other = HaloMenu.current, other !== self { other.close() }
        HaloMenu.current = self
        anchor = view
        anchorRect = rect
        self.sticky = sticky
        confirmationID = nil
        hovered = nil
        progress = 0
        closeFocused = false
        keyboardFocus = false
        rings = [ring(of: actions)]
        leaving = nil
        wheelDistance = 0

        room = depth(of: actions, limit: HaloGeometry.outerRings)
        dial.pad = HaloDialView.margin + HaloGeometry.reach(rings: room)
        panel.setFrame(frame.insetBy(dx: -dial.pad, dy: -dial.pad), display: false)
        panel.ignoresMouseEvents = false
        host.addChildWindow(panel, ordered: .above)
        addWatchers()

        phase = reduceMotion ? .open : .opening
        phaseStart = CACurrentMediaTime()
        if focus { takeKeyboard() }
        refresh()
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        clearExit()
        removeWatchers()
        dial.endDrag()
        dial.endEditing()
        editingID = nil
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow { panel.parent?.makeKey() }
        if reduceMotion {
            finishClose()
        } else {
            phase = .closing
            phaseStart = CACurrentMediaTime()
            refresh()
        }
        onOpenChange?(false)
    }

    private func finishClose() {
        phase = .closed
        confirmationID = nil
        rings = [rings[0]]
        leaving = nil
        ticker?.invalidate()
        ticker = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if HaloMenu.current === self { HaloMenu.current = nil }
    }

    private func takeKeyboard() {
        keyboardFocus = true
        panel.makeKey()
        panel.makeFirstResponder(dial)
        dial.needsDisplay = true
    }

    /// Closes shortly after the pointer leaves, unless it comes back or a confirmation is waiting.
    fileprivate func leave() {
        guard isOpen, !sticky, exitTimer == nil, !busy else { return }
        let timer = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.exitTimer = nil
            self?.close()
        }
        RunLoop.main.add(timer, forMode: .common)
        exitTimer = timer
    }

    fileprivate func clearExit() {
        exitTimer?.invalidate()
        exitTimer = nil
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // ---------- Watching the rest of the app ----------

    private func addWatchers() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            return self.watch(event)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.close()
        }
    }

    private func removeWatchers() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
        resignObserver = nil
    }

    private func isOverAnchor(_ event: NSEvent) -> Bool {
        guard let view = anchor, event.window === view.window else { return false }
        return (anchorRect ?? view.bounds).contains(view.convert(event.locationInWindow, from: nil))
    }

    private func watch(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            guard event.keyCode == 53 else { return event }
            // Escape steps back one level: out of a text box or a confirmation, then from an outer
            // ring to the ring inside it, and from the first ring out of the halo altogether.
            if !stepBack() { close() }
            return nil
        case .scrollWheel:
            let overDial = event.window === panel && dial.isInside(dial.convert(event.locationInWindow, from: nil))
            if sticky || overDial || isOverAnchor(event) { wheel(event); return nil }
            if event.momentumPhase.isEmpty { close() }
            return event
        default:
            guard event.window !== panel && !isOverAnchor(event) else { return event }
            close()
            return sticky ? nil : event   // a press that dismisses a centred halo does nothing else
        }
    }

    // ---------- Turning and choosing ----------

    fileprivate var ready: Bool { phase == .open }
    /// The outermost ring: the one the pointer, the wheel and the keys work.
    fileprivate var top: Int { rings.count - 1 }
    fileprivate var live: [HaloAction] { rings[top].actions }
    fileprivate var selected: Int { selected(in: rings[top]) }
    fileprivate func selected(in ring: HaloRing) -> Int { HaloGeometry.wrap(ring.index, ring.actions.count) }
    fileprivate var confirming: HaloAction? {
        guard let id = confirmationID else { return nil }
        return live.first { $0.id == id && !$0.disabled && $0.confirmation != nil }
    }
    fileprivate var editing: HaloAction? {
        guard let id = editingID else { return nil }
        return live.first { $0.id == id && $0.edit != nil }
    }
    /// The action the centre is describing.
    fileprivate var active: HaloAction? {
        confirming ?? editing ?? live.first { $0.id == hovered } ?? (live.isEmpty ? nil : live[selected])
    }

    /// A ring of these actions, turned to its opening place.
    private func ring(of actions: [HaloAction], grown: CFTimeInterval = 0) -> HaloRing {
        let at = HaloGeometry.opening(disabled: actions.map { $0.disabled }, checked: actions.map { $0.checked }, showPositions: showPositions)
        return HaloRing(actions: actions, index: at, turnFrom: CGFloat(at), turnStart: 0, grown: grown)
    }

    /// How far a ring has turned right now, part-way between places while it is moving.
    fileprivate func turn(of ring: HaloRing) -> CGFloat {
        let t = min(max(CGFloat(CACurrentMediaTime() - ring.turnStart) / 0.14, 0), 1)
        return ring.turnFrom + (CGFloat(ring.index) - ring.turnFrom) * (1 - (1 - t) * (1 - t))
    }

    private func turnTo(_ next: Int) {
        rings[top].turnFrom = reduceMotion ? CGFloat(next) : turn(of: rings[top])
        rings[top].turnStart = CACurrentMediaTime()
        rings[top].index = next
        hovered = nil
        refresh()
    }

    /// Brings the action at `place` on the working ring under the cursor.
    private func turn(toPlace place: Int) { turnTo(rings[top].index + place - selected) }

    fileprivate func rotate(_ direction: Int) {
        guard ready, !busy,
              let step = HaloGeometry.step(from: selected, direction: direction, disabled: live.map({ $0.disabled })) else { return }
        turnTo(rings[top].index + step)
        announce()
    }

    // MARK: Rings outside the first

    /// How much of an outer ring's width is showing, 0 to 1, while it grows.
    fileprivate func growth(of level: Int) -> CGFloat {
        guard level > 0, rings.indices.contains(level) else { return 1 }
        let t = min(max(CGFloat(CACurrentMediaTime() - rings[level].grown) / 0.18, 0), 1)
        return 1 - (1 - t) * (1 - t)
    }

    /// The same for the ring that is shrinking away.
    fileprivate var leavingSize: CGFloat {
        guard let leaving = leaving else { return 0 }
        let t = min(max(CGFloat(CACurrentMediaTime() - leaving.start) / 0.14, 0), 1)
        return 1 - t * t
    }

    /// How far a ring's glyphs are faded because a ring outside it has the work, 0 to 0.7.
    /// The action that grew the outer ring is never faded.
    fileprivate func dim(of level: Int) -> CGFloat {
        if level < top { return 0.7 * (level + 1 == top ? growth(of: top) : 1) }
        return level == top && leaving != nil ? 0.7 * leavingSize : 0
    }

    /// Grows a ring of `actions` outside the working ring and hands it the pointer, wheel and keys.
    private func grow(_ actions: [HaloAction]) {
        guard !actions.isEmpty else { return }
        let ring = ring(of: HaloMenu.withBack(actions), grown: reduceMotion ? 0 : CACurrentMediaTime())
        leaving = nil
        if top > 0, top >= room { rings[top] = ring } else { rings.append(ring) }   // no room further out: swap in place
        hovered = nil
        refresh()
        announce()
    }

    static let backID = "halo.back"

    /// An outer ring's actions with a way back to the ring inside added at the end: a back
    /// arrow, so the pointer alone can step back without Escape.
    static func withBack(_ actions: [HaloAction]) -> [HaloAction] {
        guard !actions.contains(where: { $0.id == backID }) else { return actions }
        return actions + [HaloAction(id: backID, label: "Back", symbol: "arrow.uturn.backward", description: "To the ring inside", keepsOpen: true)]
    }

    /// One step back: out of a text box or a confirmation, else off the outermost ring, which
    /// shrinks away. False when there is nothing to step back from but the halo itself.
    @discardableResult fileprivate func stepBack() -> Bool {
        if editingID != nil {
            dial.endEditing()
            editingID = nil
            takeKeyboard()
            refresh()
            return true
        }
        if confirmationID != nil {
            confirmationID = nil
            progress = 0
            dial.endDrag()
            refresh()
            return true
        }
        guard rings.count > 1 else { return false }
        let ring = rings.removeLast()
        leaving = reduceMotion ? nil : (ring, CACurrentMediaTime())
        hovered = nil
        refresh()
        announce()
        return true
    }

    /// Steps back until `level` is the working ring.
    fileprivate func stepBack(to level: Int) {
        while top > max(level, 0) { stepBack() }
    }

    /// The actions on a ring, for a press that lands on a ring inside the working one.
    fileprivate func actions(on level: Int) -> [HaloAction] { rings.indices.contains(level) ? rings[level].actions : [] }

    fileprivate func choose(_ action: HaloAction?) {
        guard ready, !busy, let action = action, !action.disabled else { return }
        if action.edit != nil {
            clearExit()
            if let at = live.firstIndex(where: { $0.id == action.id }) { turn(toPlace: at) }
            editingID = action.id
            closeFocused = false
            panel.makeKey()
            dial.beginEditing(action)
            refresh()
            return
        }
        if action.confirmation != nil {
            clearExit()
            if let at = live.firstIndex(where: { $0.id == action.id }) { turn(toPlace: at) }
            confirmationID = action.id
            confirmStart = CACurrentMediaTime()
            progress = 0
            closeFocused = false
            takeKeyboard()
            refresh()
            return
        }
        if let children = action.children {
            clearExit()
            if let at = live.firstIndex(where: { $0.id == action.id }) { turn(toPlace: at) }
            grow(children())
            return
        }
        if action.id == HaloMenu.backID { stepBack(); return }
        if action.keepsOpen { action.onSelect(); return }
        close()
        action.onSelect()
    }

    /// One step back, as Escape: off the outermost ring, or closed when only the first is showing.
    func back() { if !stepBack() { close() } }

    /// Chooses whichever action is under the cursor, as a click on the dial would.
    func chooseSelected() { choose(active(at: selected)) }

    /// Chooses an action on the working ring by its id, as a click on it would.
    func choose(id: String) { choose(live.first { $0.id == id }) }

    fileprivate func confirm() {
        guard ready, let action = confirming else { return }
        close()
        action.onSelect()
    }

    private func announce() {
        guard let text = active?.label else { return }
        NSAccessibility.post(element: dial, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func wheel(_ event: NSEvent) {
        let now = CACurrentMediaTime()
        if now - wheelAt > 0.18 { wheelDistance = 0 }
        wheelAt = now
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        // Scrolling down or right turns the ring on; a mouse wheel reports lines, a trackpad points.
        wheelDistance -= (abs(dx) > abs(dy) ? dx : dy) * (event.hasPreciseScrollingDeltas ? 1 : 16)
        if abs(wheelDistance) >= HaloGeometry.wheelStep(speed: CGFloat(Prefs.haloWheelSpeed)) {
            rotate(wheelDistance > 0 ? 1 : -1)
            wheelDistance = 0
        }
    }

    /// Return in the centre's text box: hands back the text and closes.
    fileprivate func commitEdit(_ text: String) {
        guard let action = editing, let edit = action.edit else { return }
        close()
        edit.onCommit(text)
    }

    fileprivate func key(_ event: NSEvent) -> Bool {
        if editingID != nil { return false }
        let code = event.keyCode
        let left = code == 123, right = code == 124, down = code == 125, up = code == 126
        let press = code == 36 || code == 76 || code == 49, home = code == 115, end = code == 119
        guard left || right || down || up || press || home || end || code == 48 else { return false }
        keyboardFocus = true
        defer { refresh() }
        if code == 48 {   // Tab moves between the dial and its close button
            closeFocused.toggle()
            return true
        }
        if closeFocused {
            if press { close() }
            return true
        }
        if confirming != nil {
            guard !dial.isDragging else { return true }
            if press { if progress == 1 { confirm() } }
            else if home { progress = 0 }
            else if end { progress = 1 }
            else { progress = HaloGeometry.nudge(progress, by: right || up ? 1 : -1) }
            return true
        }
        if press { choose(active(at: selected)) }
        else if home || end {
            let open = live.indices.filter { !live[$0].disabled }
            if let at = home ? open.first : open.last { turn(toPlace: at); announce() }
        }
        else { rotate(right || down ? 1 : -1) }
        return true
    }

    fileprivate func active(at position: Int) -> HaloAction? {
        live.indices.contains(position) ? live[position] : nil
    }

    // ---------- Animation ----------

    /// How much of the band, the centre disc and the contents to show, each from 0 to 1. The band
    /// opens first, then the centre, then what is written on them; closing runs it backwards.
    fileprivate func stage() -> (band: CGFloat, fill: CGFloat, content: CGFloat) {
        let ms = CGFloat(CACurrentMediaTime() - phaseStart) * 1000
        func unit(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        func out(_ t: CGFloat) -> CGFloat { 1 - (1 - t) * (1 - t) }
        switch phase {
        case .closed: return (0, 0, 0)
        case .open: return (1, 1, 1)
        case .opening: return (out(unit(ms / 120)), out(unit((ms - 120) / 80)), unit((ms - 140) / 60))
        case .closing:
            let band = unit((ms - 80) / 120), fill = unit(ms / 80)
            return (1 - band * band, 1 - fill * fill, 1 - unit(ms / 60))
        }
    }

    /// Redraws, moves the open and close along, and keeps a timer running only while something moves.
    fileprivate func refresh() {
        let now = CACurrentMediaTime()
        if phase == .opening, now - phaseStart >= 0.2 { phase = .open }
        if phase == .closing, now - phaseStart >= 0.2 { finishClose(); return }
        if let leaving = leaving, now - leaving.start >= 0.14 { self.leaving = nil }
        dial.needsDisplay = true
        let moving = phase == .opening || phase == .closing || leaving != nil || (confirming != nil && !reduceMotion)
            || rings.contains { now - $0.turnStart < 0.14 || now - $0.grown < 0.2 }
        if moving && ticker == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !moving {
            ticker?.invalidate()
            ticker = nil
        }
    }
}

private final class HaloPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Stands for one action, the close button or the slider to VoiceOver.
private final class HaloAccessibilityElement: NSAccessibilityElement {
    var press: (() -> Void)?
    var slide: ((CGFloat) -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
    override func accessibilityPerformIncrement() -> Bool { slide?(1); return slide != nil }
    override func accessibilityPerformDecrement() -> Bool { slide?(-1); return slide != nil }
}

private final class HaloDialView: NSView, NSTextFieldDelegate {
    /// Room around the dial for its shadow.
    static let margin: CGFloat = 40
    /// Room around the dial in this panel: the margin, and any rings that can grow outside it.
    var pad: CGFloat = HaloDialView.margin
    weak var halo: HaloMenu?
    private var grab: CGFloat?
    private var pressedInside = false
    var isDragging: Bool { grab != nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // ---------- Measurements ----------

    private var circle: CGRect { bounds.insetBy(dx: pad, dy: pad) }
    private var diameter: CGFloat { circle.width }
    private var centre: CGPoint { CGPoint(x: circle.midX, y: circle.midY) }
    private var compact: Bool { diameter < HaloGeometry.compactBelow }
    private func targetSize(_ level: Int, _ ring: HaloRing) -> CGFloat {
        HaloGeometry.target(of: level, diameter: diameter, count: ring.actions.count)
    }

    private func distance(_ p: CGPoint) -> CGFloat { hypot(p.x - centre.x, p.y - centre.y) }

    /// Inside the dial, out to the edge of its outermost ring.
    func isInside(_ p: CGPoint) -> Bool {
        distance(p) <= HaloGeometry.band(of: halo?.top ?? 0, diameter: diameter).far
    }

    /// A slice of the dial given as fractions of its diameter, the way the web version lays it out.
    private func part(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: circle.minX + x * diameter, y: circle.minY + y * diameter, width: w * diameter, height: h * diameter)
    }

    private func position(of at: Int, in ring: HaloRing, level: Int) -> CGPoint {
        guard let menu = halo else { return centre }
        let o = HaloGeometry.offset(of: at, count: ring.actions.count, turn: menu.turn(of: ring), radius: HaloGeometry.orbit(of: level, diameter: diameter))
        return CGPoint(x: centre.x + o.x, y: centre.y + o.y)
    }

    /// The action under a point on one ring.
    private func action(at p: CGPoint, on level: Int) -> Int? {
        guard let menu = halo, menu.rings.indices.contains(level) else { return nil }
        let ring = menu.rings[level], size = targetSize(level, ring)
        return ring.actions.indices.first { hypot(p.x - position(of: $0, in: ring, level: level).x, p.y - position(of: $0, in: ring, level: level).y) <= size / 2 }
    }

    /// The action under a point on the working ring.
    private func action(at p: CGPoint) -> Int? { action(at: p, on: halo?.top ?? 0) }

    private var closeFrame: CGRect {
        CGRect(x: centre.x - 18, y: circle.maxY - (compact ? 0.17 : 0.19) * diameter - 36, width: 36, height: 36)
    }
    private var track: CGRect { CGRect(x: centre.x - 60, y: centre.y - 10, width: 120, height: 20) }
    private var thumb: CGRect {
        CGRect(x: track.minX + 2 + (halo?.progress ?? 0) * 96, y: track.minY, width: 20, height: 20)
    }

    // ---------- Pointer and keys ----------

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func follow(_ event: NSEvent) {
        guard let menu = halo else { return }
        let p = point(event), inside = isInside(p)
        if inside { menu.clearExit() } else { menu.leave() }
        (inside ? NSCursor.pointingHand : NSCursor.arrow).set()
        let over = inside && menu.confirmationID == nil && menu.editingID == nil ? action(at: p).map { menu.live[$0].id } : nil
        if over != menu.hovered {
            menu.hovered = over
            needsDisplay = true
        }
    }

    override func mouseEntered(with event: NSEvent) { follow(event) }
    override func mouseMoved(with event: NSEvent) { follow(event) }
    override func mouseExited(with event: NSEvent) {
        halo?.hovered = nil
        halo?.leave()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let menu = halo else { return }
        let p = point(event)
        pressedInside = isInside(p)
        if !pressedInside { menu.close(); return }
        if menu.ready, menu.confirming != nil, thumb.contains(p) {
            grab = p.x - thumb.minX
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let menu = halo, let grab = grab else { return }
        menu.progress = min(max((point(event).x - grab - track.minX - 2) / 96, 0), 1)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let menu = halo else { return }
        if grab != nil {
            grab = nil
            if menu.progress >= 1 { menu.confirm() } else { menu.progress = 0; needsDisplay = true }
            return
        }
        let p = point(event)
        guard pressedInside, isInside(p) else { return }
        if closeFrame.contains(p) { if menu.ready { menu.close() } }
        else if !menu.busy, let level = HaloGeometry.level(at: distance(p), rings: menu.top, diameter: diameter) {
            // A press on a ring inside the working one steps back to it, and chooses what was pressed.
            let pressed = action(at: p, on: level).map { menu.actions(on: level)[$0] }
            menu.stepBack(to: level)
            if let pressed = pressed, pressed.id != menu.live[menu.selected].id || pressed.children == nil { menu.choose(pressed) }
        }
        else if let at = action(at: p) { menu.choose(menu.live[at]) }
        else if !track.insetBy(dx: -8, dy: -8).contains(p) || menu.confirming == nil { menu.choose(menu.active(at: menu.selected)) }
    }

    func endDrag() { grab = nil }

    // MARK: The text box in the centre

    private var editor: NSTextField?

    /// Puts a text box in the middle of the dial for an action that edits a value.
    func beginEditing(_ action: HaloAction) {
        guard let menu = halo, let edit = action.edit else { return }
        endEditing()
        let width = diameter * 0.5
        let field = NSTextField(frame: NSRect(x: centre.x - width / 2, y: centre.y - 13, width: width, height: 26))
        field.stringValue = edit.value
        field.placeholderString = edit.placeholder
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = menu.colours.ring(0).band
        field.textColor = menu.colours.ring(0).bandInk
        field.appearance = NSAppearance(named: .aqua)   // a pale box: dark text and a light selection, whatever the app's look
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.delegate = self
        field.setAccessibilityLabel(action.label)
        addSubview(field)
        editor = field
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = menu.colours.ring(0).bandInk
    }

    func endEditing() {
        editor?.removeFromSuperview()
        editor = nil
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let field = editor else { return false }
        halo?.commitEdit(field.stringValue)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if halo?.key(event) != true { super.keyDown(with: event) }
    }

    // ---------- Drawing ----------

    override func draw(_ dirtyRect: NSRect) {
        guard let menu = halo, let ctx = NSGraphicsContext.current?.cgContext, diameter > 0 else { return }
        let stage = menu.stage(), colours = menu.colours, first = colours.ring(0)
        let outer = diameter / 2, inner = HaloGeometry.centreRadius(diameter)

        func disc(_ radius: CGFloat) -> CGRect { CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2) }
        func slice(from near: CGFloat, to far: CGFloat, half: CGFloat) -> CGPath {
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: far, startAngle: -.pi / 2 - half, endAngle: -.pi / 2 + half, clockwise: false)
            path.addArc(center: .zero, radius: near, startAngle: -.pi / 2 + half, endAngle: -.pi / 2 - half, clockwise: true)
            path.closeSubpath()
            return path
        }
        func scaled(_ scale: CGFloat, _ body: () -> Void) {
            guard scale > 0 else { return }
            ctx.saveGState()
            ctx.translateBy(x: centre.x, y: centre.y)
            ctx.scaleBy(x: scale, y: scale)
            body()
            ctx.restoreGState()
        }
        func half(_ level: Int, _ ring: HaloRing) -> CGFloat {
            HaloGeometry.halfWedge(of: level, diameter: diameter, count: ring.actions.count)
        }

        // Every ring showing, the first one first: its level, its actions and how much of its width has grown.
        var shown = menu.rings.enumerated().map { (level: $0.offset, ring: $0.element, size: menu.growth(of: $0.offset)) }
        if let leaving = menu.leaving { shown.append((level: menu.rings.count, ring: leaving.ring, size: menu.leavingSize)) }

        scaled(stage.band) {
            // Rings grown outside the first, the outermost first so each lies on the one beyond it.
            for item in shown.dropFirst().reversed() {
                let band = HaloGeometry.band(of: item.level, diameter: diameter), far = band.near + (band.far - band.near) * item.size
                guard far > band.near else { continue }
                let ring = colours.ring(item.level)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.33).cgColor)
                ctx.addEllipse(in: disc(far))
                ctx.addEllipse(in: disc(band.near))
                ctx.setFillColor(ring.band.cgColor)
                ctx.fillPath(using: .evenOdd)
                ctx.restoreGState()
                ctx.addPath(slice(from: band.near, to: far, half: half(item.level, item.ring)))
                ctx.setFillColor(ring.cursor.cgColor)
                ctx.fillPath()
            }
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.33).cgColor)
            ctx.addEllipse(in: disc(outer))
            ctx.addEllipse(in: disc(inner + 3))
            ctx.setFillColor(first.band.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
            ctx.addPath(slice(from: inner + 3, to: outer, half: half(0, menu.rings[0])))
            ctx.setFillColor(first.cursor.cgColor)
            ctx.fillPath()
        }
        scaled(stage.fill) {
            ctx.setFillColor(colours.centreInk.cgColor)
            ctx.fillEllipse(in: disc(inner + 3))
            ctx.setFillColor(colours.centre.cgColor)
            ctx.fillEllipse(in: disc(inner))
        }

        guard stage.content > 0 else { return }
        ctx.saveGState()
        ctx.setAlpha(stage.content)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // Each ring is drawn twice: band ink outside its cursor, cursor ink inside it, so a glyph
        // changes colour as it crosses the cursor's edge. A ring with another outside it fades
        // all but the action that grew that ring, so the eye goes to the ring being worked.
        for item in shown {
            let level = item.level, ring = item.ring
            let fade = level == 0 ? 1 : min(max((item.size - 0.6) / 0.4, 0), 1)   // an outer ring's glyphs arrive once it has nearly grown
            guard fade > 0 else { continue }
            let band = HaloGeometry.band(of: level, diameter: diameter), inks = colours.ring(level)
            let dim = menu.dim(of: level), chosen = menu.selected(in: ring), size = targetSize(level, ring)
            var move = CGAffineTransform(translationX: centre.x, y: centre.y)
            let cursor = slice(from: level == 0 ? 0 : band.near - 1, to: band.far + 1, half: half(level, ring)).copy(using: &move) ?? CGMutablePath()
            for inside in [false, true] {
                ctx.saveGState()
                if inside {
                    ctx.addPath(cursor)
                    ctx.clip()
                } else {
                    ctx.addRect(bounds)
                    ctx.addPath(cursor)
                    ctx.clip(using: .evenOdd)
                }
                let ink = inside ? inks.cursorInk : inks.bandInk
                for (at, action) in ring.actions.enumerated() {
                    let p = position(of: at, in: ring, level: level)
                    let alpha = (action.disabled ? 0.45 : 1) * fade * (at == chosen ? 1 : 1 - dim)
                    glyph(action.icon, in: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20), ink: ink, alpha: alpha, ctx)
                    if action.checked == true {
                        ctx.setFillColor(ink.withAlphaComponent(alpha).cgColor)
                        ctx.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y + size / 2 - 7, width: 5, height: 5))
                    }
                }
                ctx.restoreGState()
            }
        }
        let showsFocus = menu.keyboardFocus && window?.isKeyWindow == true
        if showsFocus, !menu.closeFocused, menu.confirming == nil, !menu.live.isEmpty {
            let ring = menu.rings[menu.top], p = position(of: menu.selected, in: ring, level: menu.top), size = targetSize(menu.top, ring)
            ctx.setFillColor(colours.ring(menu.top).cursorInk.cgColor)
            ctx.fill(CGRect(x: p.x - size / 4, y: p.y + size / 2 - 5, width: size / 2, height: 2))
        }

        drawCentre(menu, ctx)

        // Close: a cross under the centre.
        let close = closeFrame
        ctx.setStrokeColor(colours.centreInk.cgColor)
        ctx.setLineWidth(5.0 / 3)
        ctx.setLineCap(.round)
        ctx.strokeLineSegments(between: [CGPoint(x: close.midX - 5, y: close.midY - 5), CGPoint(x: close.midX + 5, y: close.midY + 5),
                                         CGPoint(x: close.midX + 5, y: close.midY - 5), CGPoint(x: close.midX - 5, y: close.midY + 5)])
        if showsFocus, menu.closeFocused {
            ctx.setFillColor(colours.centreInk.cgColor)
            ctx.fill(CGRect(x: close.minX + 9, y: close.maxY - 5, width: 18, height: 2))
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Draws an image scaled to fit `box`: a template in one flat colour, anything else as it is.
    private func glyph(_ image: NSImage, in box: CGRect, ink: NSColor, alpha: CGFloat, _ ctx: CGContext) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(box.width / size.width, box.height / size.height)
        let rect = CGRect(x: box.midX - size.width * scale / 2, y: box.midY - size.height * scale / 2,
                          width: size.width * scale, height: size.height * scale)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if image.isTemplate {
            ink.setFill()
            rect.insetBy(dx: -1, dy: -1).fill(using: .sourceAtop)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, colour: NSColor, opacity: CGFloat = 1,
                      align: NSTextAlignment = .center, lines: Int = 1) -> (NSAttributedString, CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let string = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: colour.withAlphaComponent(opacity), .paragraphStyle: style])
        return (string, ceil(NSLayoutManager().defaultLineHeight(for: font)) * CGFloat(lines))
    }

    private func height(_ piece: (NSAttributedString, CGFloat), width: CGFloat) -> CGFloat {
        let needed = piece.0.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
        return min(ceil(needed), piece.1)
    }

    /// Stacks pieces of text down a box, centred or from its top, never past its bottom.
    private func stack(_ pieces: [(NSAttributedString, CGFloat)], in box: CGRect, gap: CGFloat, fromTop: Bool = false, _ ctx: CGContext) {
        let heights = pieces.map { height($0, width: box.width) }
        let total = heights.reduce(0, +) + gap * CGFloat(max(pieces.count - 1, 0))
        var y = fromTop ? box.minY : max(box.minY, box.midY - total / 2)
        ctx.saveGState()
        ctx.clip(to: box)
        for (piece, h) in zip(pieces, heights) {
            piece.0.draw(with: CGRect(x: box.minX, y: y, width: box.width, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += h + gap
        }
        ctx.restoreGState()
    }

    private func drawCentre(_ menu: HaloMenu, _ ctx: CGContext) {
        let ink = menu.colours.centreInk, active = menu.active
        let gap: CGFloat = compact ? 4 : 6
        let title = text(active?.label ?? menu.label, size: compact ? 13 : 16, weight: .semibold, colour: ink, lines: 2)

        if let edit = menu.editing?.edit {
            // The text box itself is a real field laid over the dial; only its heading and hint are drawn.
            stack([title], in: part(0.28, 0.27, 0.44, 0.16), gap: gap, fromTop: true, ctx)
            stack([text(edit.hint, size: 11, colour: ink, opacity: 0.8, lines: 2)],
                  in: CGRect(x: circle.minX + 0.22 * diameter, y: centre.y + 20, width: 0.56 * diameter, height: 30), gap: 0, fromTop: true, ctx)
            return
        }
        if let confirming = menu.confirming, let ask = confirming.confirmation {
            stack([title], in: part(0.28, 0.27, 0.44, 0.16), gap: gap, fromTop: true, ctx)
            drawSlider(menu, ctx)
            stack([text(ask.label, size: 12, colour: ink, lines: 2)],
                  in: CGRect(x: circle.minX + 0.22 * diameter, y: centre.y + 20, width: 0.56 * diameter, height: 34), gap: 0, fromTop: true, ctx)
            return
        }

        let note = active?.description ?? menu.hint
        if let badge = menu.typeBadge {
            stack([title], in: part(0.28, 0.27, 0.44, 0.16), gap: 4, fromTop: true, ctx)
            let icon: CGFloat = compact ? 24 : 32, between: CGFloat = compact ? 3 : 4
            let name = text([badge.label, badge.name].compactMap { $0 }.joined(separator: " "), size: compact ? 13 : 16, weight: .semibold, colour: ink)
            let rows = metadataHeight(menu)
            let top = centre.y - (icon + between + name.1 + rows) / 2
            glyph(badge.icon, in: CGRect(x: centre.x - icon / 2, y: top, width: icon, height: icon), ink: ink, alpha: 1, ctx)
            let column = part(0.22, 0, 0.56, 0)
            stack([name], in: CGRect(x: column.minX, y: top + icon + between, width: column.width, height: name.1), gap: 0, ctx)
            drawMetadata(menu, in: CGRect(x: column.minX, y: top + icon + between + name.1, width: column.width, height: rows), ctx)
            if let note = note {
                stack([text(note, size: compact ? 10 : 11, colour: ink, opacity: 0.8, lines: 2)], in: part(0.24, compact ? 0.60 : 0.61, 0.52, 0.08), gap: 0, ctx)
            }
            return
        }

        var pieces = [title]
        if let description = active?.description {
            pieces.append(text(description, size: compact ? 10 : 12, colour: ink, opacity: 0.8, lines: compact || !menu.metadata.isEmpty ? 2 : 3))
        } else if let hint = menu.hint, !compact {
            pieces.append(text(hint, size: 11, colour: ink, opacity: 0.8, lines: 2))
        }
        let box = part(0.22, 0.27, 0.56, 0.42)
        if !menu.metadata.isEmpty {
            let upper = CGRect(x: box.minX + box.width * 0.06, y: box.minY, width: box.width * 0.88, height: box.height * 0.55 - 6)
            stack(pieces, in: upper, gap: gap, fromTop: true, ctx)
            drawMetadata(menu, in: CGRect(x: box.minX, y: box.minY + box.height * 0.55, width: box.width, height: box.height * 0.45), ctx)
            return
        }
        if let caption = menu.caption { pieces.insert(text(caption, size: compact ? 10 : 12, colour: ink, opacity: 0.8), at: 0) }
        guard menu.showPositions, !menu.live.isEmpty else {
            stack(pieces, in: box, gap: gap, ctx)
            return
        }
        // A row of initials under the text, the one under the wedge filled in.
        let perRow = max(1, Int((box.width + 4) / 28)), count = menu.live.count
        let rows = (count + perRow - 1) / perRow
        let squares = CGFloat(rows) * 24 + CGFloat(rows - 1) * 4
        let words = pieces.map { height($0, width: box.width) }.reduce(0, +) + gap * CGFloat(pieces.count - 1)
        let top = max(box.minY, box.midY - (words + gap + squares) / 2)
        stack(pieces, in: CGRect(x: box.minX, y: top, width: box.width, height: words), gap: gap, fromTop: true, ctx)
        ctx.saveGState()
        ctx.clip(to: box)
        for (at, action) in menu.live.enumerated() {
            let row = at / perRow, inRow = min(perRow, count - row * perRow)
            let x = box.midX - (CGFloat(inRow) * 28 - 4) / 2 + CGFloat(at % perRow) * 28
            let square = CGRect(x: x, y: top + words + gap + CGFloat(row) * 28, width: 24, height: 24)
            let on = at == menu.selected
            ctx.setFillColor(ink.cgColor)
            ctx.setStrokeColor(ink.cgColor)
            if on { ctx.fill(square) } else { ctx.stroke(square.insetBy(dx: 0.5, dy: 0.5), width: 1) }
            let initial = text(String(action.label.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased(), size: 12, colour: on ? menu.colours.centre : ink)
            stack([initial], in: square, gap: 0, ctx)
        }
        ctx.restoreGState()
    }

    private func metadataHeight(_ menu: HaloMenu) -> CGFloat {
        guard !menu.metadata.isEmpty else { return 0 }
        let row = text(" ", size: compact ? 10 : 11, colour: .black).1
        return (compact ? 4 : 6) + row * CGFloat(menu.metadata.count)
    }

    private func drawMetadata(_ menu: HaloMenu, in box: CGRect, _ ctx: CGContext) {
        let ink = menu.colours.centreInk, size: CGFloat = compact ? 10 : 11
        var y = box.minY + (compact ? 4 : 6)
        ctx.saveGState()
        ctx.clip(to: box)
        for item in menu.metadata {
            let name = text(item.label, size: size, colour: ink, opacity: 0.7, align: .left)
            let value = text(item.value, size: size, colour: ink, align: .left)
            name.0.draw(with: CGRect(x: box.minX, y: y, width: box.width * 0.34, height: name.1), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            value.0.draw(with: CGRect(x: box.minX + box.width * 0.34 + 6, y: y, width: box.width * 0.66 - 6, height: value.1),
                         options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += name.1
        }
        ctx.restoreGState()
    }

    /// The slide-to-confirm bar: a band-coloured track with chevrons drifting towards the far end
    /// and a black thumb. It bounces in when it appears.
    private func drawSlider(_ menu: HaloMenu, _ ctx: CGContext) {
        let colours = menu.colours, band = colours.ring(0).band, still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let elapsed = CGFloat(CACurrentMediaTime() - menu.confirmStart)
        let entered = still ? 1 : min(elapsed / 0.44, 1), eased = 1 - pow(1 - entered, 4)
        let scale = eased < 0.65 ? 0.8 + 0.24 * eased / 0.65 : 1.04 - 0.04 * (eased - 0.65) / 0.35
        ctx.saveGState()
        ctx.setAlpha(min(eased / 0.65, 1))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: track.midX, y: track.midY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -track.midX, y: -track.midY)

        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setFillColor(band.cgColor)
        ctx.fillPath()

        let inside = track.insetBy(dx: 2, dy: 2)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: inside, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.clip()
        let drift = still ? 0 : elapsed.truncatingRemainder(dividingBy: 1.3) / 1.3 * 20
        ctx.setFillColor((band.blended(withFraction: 0.5, of: .black) ?? .gray).cgColor)
        for at in 0..<8 {
            let x = inside.minX - 20 + drift + CGFloat(at) * 20, y = inside.minY
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + 10, y: y))
            ctx.addLine(to: CGPoint(x: x + 18, y: y + 8))
            ctx.addLine(to: CGPoint(x: x + 10, y: y + 16))
            ctx.addLine(to: CGPoint(x: x, y: y + 16))
            ctx.addLine(to: CGPoint(x: x + 8, y: y + 8))
            ctx.closePath()
        }
        ctx.fillPath()
        let handle = thumb
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(handle)
        ctx.setStrokeColor(colours.centreInk.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeLineSegments(between: [-3, 0, 3].flatMap { (dx: CGFloat) in
            [CGPoint(x: handle.midX + dx, y: handle.midY - 3), CGPoint(x: handle.midX + dx, y: handle.midY + 3)]
        })
        if menu.keyboardFocus, window?.isKeyWindow == true, !menu.closeFocused {
            ctx.stroke(handle.insetBy(dx: 5, dy: 5), width: 2)
        }
        ctx.restoreGState()

        ctx.addPath(CGPath(roundedRect: track.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.setStrokeColor(colours.centreInk.cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // ---------- VoiceOver ----------

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { halo?.confirming == nil ? .menu : .group }
    override func accessibilityLabel() -> String? { halo?.confirming?.label ?? halo?.label }

    override func accessibilityChildren() -> [Any]? {
        guard let menu = halo, let window = window else { return [] }
        func element(_ role: NSAccessibility.Role, _ label: String, _ rect: CGRect) -> HaloAccessibilityElement {
            let e = HaloAccessibilityElement()
            e.setAccessibilityRole(role)
            e.setAccessibilityLabel(label)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrame(window.convertToScreen(convert(rect, to: nil)))
            return e
        }
        var children: [HaloAccessibilityElement] = []
        if let confirming = menu.confirming, let ask = confirming.confirmation {
            let slider = element(.slider, "\(confirming.label): \(ask.label)", track)
            slider.setAccessibilityHelp(ask.keyboardHint)
            slider.setAccessibilityValue(Int((menu.progress * 100).rounded()))
            slider.slide = { [weak halo = menu] direction in
                guard let menu = halo else { return }
                menu.progress = HaloGeometry.nudge(menu.progress, by: direction)
                menu.refresh()
            }
            slider.press = { [weak halo = menu] in if halo?.progress == 1 { halo?.confirm() } }
            children.append(slider)
        } else {
            let ring = menu.rings[menu.top], size = targetSize(menu.top, ring)
            for (at, action) in ring.actions.enumerated() {
                let p = position(of: at, in: ring, level: menu.top)
                let item = element(.menuItem, action.label, CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
                item.setAccessibilityHelp(action.description)
                item.setAccessibilityEnabled(!action.disabled)
                item.setAccessibilitySelected(at == menu.selected)
                let id = action.id
                item.press = { [weak halo = menu] in halo?.choose(id: id) }
                children.append(item)
            }
        }
        let close = element(.button, menu.closeLabel, closeFrame)
        close.press = { [weak halo = menu] in halo?.close() }
        children.append(close)
        return children
    }
}

/// A small picture of the dial, for a button that opens one: a ring, a wedge at twelve o'clock
/// and a centre dot, drawn in whatever ink suits the surface behind it.
final class HaloTriggerView: NSView {
    var ink = NSColor.labelColor { didSet { needsDisplay = true } }
    var onPress: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            ink.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let c = NSPoint(x: bounds.midX, y: bounds.midY), outer = min(bounds.width, bounds.height) / 2 - 3
        let band = NSBezierPath(ovalIn: NSRect(x: c.x - outer + 1.5, y: c.y - outer + 1.5, width: outer * 2 - 3, height: outer * 2 - 3))
        band.lineWidth = 3
        ink.withAlphaComponent(0.4).setStroke()
        band.stroke()
        let wedge = NSBezierPath()
        wedge.appendArc(withCenter: c, radius: outer, startAngle: 52, endAngle: 128)
        wedge.appendArc(withCenter: c, radius: outer - 3, startAngle: 128, endAngle: 52, clockwise: true)
        wedge.close()
        ink.setFill()
        wedge.fill()
        NSBezierPath(ovalIn: NSRect(x: c.x - outer * 0.3, y: c.y - outer * 0.3, width: outer * 0.6, height: outer * 0.6)).fill()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}   // keep the press from reaching whatever is underneath
    // While the halo is open its own panel has the keyboard, so the window this button is in is not
    // the key window. Without this, a press here would only bring the window forward and be lost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { toolTip }
    override func accessibilityPerformPress() -> Bool { onPress?(); return onPress != nil }
}
