import AppKit

/// Full-window settings colour chooser. Draft colours never touch preferences until Select.
final class StudioColourPicker: NSView, Overlay {
    struct Target {
        let group: String, name: String, key: String
        let read: () -> NSColor
        let write: (String) -> Void
    }
    static var targets: [Target] {
        var result: [Target] = []
        for (group, prefix) in [("Halo · Information", "centre"), ("Halo · Primary Ring", "ring1"), ("Halo · Secondary Ring", "ring2"), ("Halo · Tertiary Ring", "ring3")] {
            for (name, suffix) in [("Background", "background"), ("Text", "text")] + (prefix == "centre" ? [] : [("Cursor Background", "cursorBackground"), ("Cursor Text", "cursorText")]) {
                let key = prefix + "." + suffix
                result.append(Target(group: group, name: name, key: key, read: { Theme.halo(key) }, write: { Prefs.setHaloColour($0, key) }))
            }
        }
        result += [
            Target(group: "Sidebar · Selection", name: "Background", key: "sidebar.background", read: { Theme.sidebarSelectionBackground }, write: { Prefs.sidebarSelectionBackground = $0 }),
            Target(group: "Sidebar · Selection", name: "Text", key: "sidebar.text", read: { Theme.sidebarSelectionText }, write: { Prefs.sidebarSelectionText = $0 }),
            Target(group: "Buttons · Hover", name: "Background", key: "hover.background", read: { Theme.buttonHoverBackground }, write: { Prefs.buttonHoverBackground = $0 }),
            Target(group: "Buttons · Hover", name: "Text", key: "hover.text", read: { Theme.buttonHoverText }, write: { Prefs.buttonHoverText = $0 }),
            Target(group: "Buttons · Active", name: "Background", key: "active.background", read: { Theme.buttonActiveBackground }, write: { Prefs.buttonActiveBackground = $0 }),
            Target(group: "Buttons · Active", name: "Text", key: "active.text", read: { Theme.buttonActiveText }, write: { Prefs.buttonActiveText = $0 })
        ]
        return result
    }
    private let items: [Target]
    private var selected: Int
    private var proposed: String
    private let scroll = FittedScrollView()
    private let list = FlippedView()
    private var targetButtons: [TargetButton] = []
    private var dots: [Dot] = []
    private let select = SwissButton("Select", .primary)
    private let cancel = SwissButton("Cancel", .secondary)
    private let reset = SwissButton("Clear Colour", .secondary)
    private var resetAction:(()->Void)?
    private let commitOnPick:Bool
    private weak var previous: NSResponder?
    var onDismiss: (() -> Void)?
    var overlayWindows: [NSWindow] { window.map { [$0] } ?? [] }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var railEdge: CGFloat { LibraryRail.collapsedWidth + Design.App.column(5, in: bounds.width) - Design.App.column(3, in: bounds.width) }
    init(target: String, targets: [Target]? = nil,onReset:(()->Void)? = nil,commitOnPick:Bool=false) {
        let choices=targets ?? Self.targets
        items=choices
        resetAction=onReset
        self.commitOnPick=commitOnPick
        let index = choices.firstIndex { $0.key == target } ?? 0
        selected = index; proposed = hexOf(choices[index].read()) ?? "#000000"
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Design.card.cgColor
        setAccessibilityRole(.group); setAccessibilityLabel(targets == nil ? "Settings Colour Picker":(choices.first?.group ?? "Asset")+" Colour Picker")
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = list; addSubview(scroll)
        var y: CGFloat = 0, previousGroup = ""
        for (i, item) in items.enumerated() {
            if item.group != previousGroup {
                let label = Design.text(item.group, .caption, colour: Design.quiet)
                label.frame = NSRect(x: 16, y: y + 6, width: 240, height: 22)
                label.autoresizingMask = [.width]; list.addSubview(label); y += 28; previousGroup = item.group
            }
            let button = TargetButton(frame: NSRect(x: 16, y: y, width: 240, height: 28))
            button.title = item.name; button.colour = item.read(); button.tag = i
            button.target = self; button.action = #selector(targetPicked(_:)); button.isBordered = false
            button.setAccessibilityLabel(item.group + " " + item.name)
            targetButtons.append(button); list.addSubview(button); y += 28
        }
        list.frame.size.height = y + 16
        for (i, sample) in Self.samples.enumerated() {
            let dot = Dot(frame: .zero); dot.hex = sample.3; dot.tag = i
            dot.target = self; dot.action = #selector(picked(_:))
            dot.onDouble = { [weak self] in self?.commit() }
            dot.setAccessibilityLabel("Choose " + sample.3); dot.toolTip = sample.3
            dots.append(dot); addSubview(dot)
        }
        select.target = self; select.action = #selector(commit)
        cancel.target = self; cancel.action = #selector(cancelled)
        addSubview(select); addSubview(cancel)
        reset.target=self;reset.action=#selector(resetColour);reset.isHidden=onReset == nil;addSubview(reset)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    private final class FlippedView: NSView { override var isFlipped: Bool { true } }
    func present(over root: NSView) {
        previous = root.window?.firstResponder
        frame = root.bounds; autoresizingMask = [.width, .height]
        root.addSubview(self); root.window?.makeFirstResponder(self); Overlays.opened(self)
    }
    func dismissOverlay() {
        let win = window
        removeFromSuperview(); Overlays.closed(self)
        win?.makeFirstResponder(previous); onDismiss?()
    }
    @objc private func cancelled() { dismissOverlay() }
    @objc private func commit() { items[selected].write(proposed); dismissOverlay() }
    @objc private func resetColour() {resetAction?();dismissOverlay()}
    @objc private func targetPicked(_ sender: NSButton) {
        selected = sender.tag; proposed = hexOf(items[selected].read()) ?? "#000000"; refresh()
    }
    @objc private func picked(_ sender: NSButton) { proposed = Self.samples[sender.tag].3; refresh();if commitOnPick {commit()} }
    private func refresh() {
        for (i, button) in targetButtons.enumerated() { button.chosen = i == selected; button.needsDisplay = true }
        for dot in dots { dot.chosen = dot.hex == proposed; dot.needsDisplay = true }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismissOverlay() }
        else if event.keyCode == 36 { commit() }
        else { super.keyDown(with: event) }
    }
    override func layout() {
        super.layout()
        let edge = railEdge, top = Design.App.header + AreaHeader.height
        scroll.frame = NSRect(x: LibraryRail.collapsedWidth, y: top, width: edge - LibraryRail.collapsedWidth, height: max(0, bounds.height - top - Design.App.footer))
        list.frame.size.width = scroll.contentSize.width
        for view in list.subviews { view.frame.size.width = max(1, list.bounds.width - 32) }
        let available = NSRect(x: edge + 32, y: top + 28, width: max(1, bounds.width - edge - 64), height: max(1, bounds.height - top - 124))
        let scale = min(available.width / 1422, available.height / 1620)
        let origin = NSPoint(x: available.midX - 711 * scale, y: available.midY - 810 * scale)
        for (index, pair) in zip(dots, Self.samples).enumerated() {
            let (dot, sample) = pair
            if index >= 242 {
                dot.frame = NSRect(x: available.midX - 174 + CGFloat(index - 242) * 30, y: available.maxY + 12, width: 24, height: 24)
                continue
            }
            let radius = sample.2 * scale
            dot.frame = NSRect(x: origin.x + (sample.0 - 29) * scale - radius, y: origin.y + sample.1 * scale - radius, width: radius * 2, height: radius * 2)
        }
        cancel.frame = NSRect(x: railEdge + 16, y: bounds.height - 64, width: cancel.intrinsicContentSize.width, height: 32)
        select.frame = NSRect(x: cancel.frame.maxX + 24, y: cancel.frame.minY, width: select.intrinsicContentSize.width, height: 32)
        reset.frame=NSRect(x:select.frame.maxX+24,y:cancel.frame.minY,width:reset.intrinsicContentSize.width,height:32)
    }
    override func draw(_ dirtyRect: NSRect) {
        let edge = railEdge, top = Design.App.header
        fill(bounds, Design.card)
        fill(NSRect(x: 0, y: top, width: LibraryRail.collapsedWidth, height: bounds.height - top), Design.mist)
        hairline(x: 0, y: top, width: bounds.width)
        fill(NSRect(x: edge, y: top, width: 1, height: bounds.height - top), Design.rule)
        Design.attributed("Colour Picker", .heading).draw(x: Design.App.margin, baseline: 39)
        Design.attributed(items.count == 1 ? items[0].group+" Colours":"Settings Colours", .heading).draw(x: LibraryRail.collapsedWidth + 16, baseline: top + AreaHeader.headingBaseline)
        Design.attributed("Spiral Spectrum", .heading).draw(x: edge + 16, baseline: top + AreaHeader.headingBaseline)
        Design.attributed(items[selected].group + " / " + items[selected].name, .label, colour: Design.quiet).draw(x: edge + 16, baseline: top + AreaHeader.rule - 10, width: bounds.width - edge - 32)
        hairline(x: LibraryRail.collapsedWidth + 16, y: top + AreaHeader.rule, width: bounds.width - LibraryRail.collapsedWidth - 40)
        let preview = NSRect(x: edge + 16, y: bounds.height - 65, width: 32, height: 32)
        Design.hex(proposed).setFill(); NSBezierPath(ovalIn: preview).fill()
        Design.attributed(proposed, .bodyStrong).draw(x: preview.maxX + 12, baseline: preview.midY + 5)
    }
    private final class Dot: ClickCursorButton {
        var hex = "#000000", chosen = false
        var onDouble: (() -> Void)?
        private var hover = false
        override func updateTrackingAreas() {
            super.updateTrackingAreas(); trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self))
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
        override func mouseDown(with event: NSEvent) {
            sendAction(action, to: target)
            if event.clickCount == 2 { onDouble?() }
        }
        override func draw(_ dirtyRect: NSRect) {
            Design.hex(hex).setFill(); NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
            if chosen || hover {
                Design.ink.setStroke(); let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)); ring.lineWidth = chosen ? 1.5 : 0.75; ring.stroke()
            }
        }
    }
    private final class TargetButton: ClickCursorButton {
        var colour = NSColor.black, chosen = false
        override var isFlipped: Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func draw(_ dirtyRect: NSRect) {
            if chosen { Design.ink.setStroke(); let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5); p.lineWidth = 1; p.stroke() }
            colour.setFill(); NSBezierPath(ovalIn: NSRect(x: 8, y: 6, width: 16, height: 16)).fill()
            Design.attributed(title, .body).draw(x: 32, baseline: Design.App.textBaseline, width: bounds.width - 40)
        }
    }
    private static let samples: [(CGFloat, CGFloat, CGFloat, String)] = [
        (740.5, 73.9, 32.2, "#FF0000"),
        (740.5, 144.0, 32.0, "#CC433C"),
        (810.5, 147.3, 32.0, "#EB3F25"),
        (879.8, 157.3, 32.0, "#EE7F35"),
        (947.8, 173.8, 32.0, "#E29D41"),
        (1014.1, 196.7, 32.2, "#D18C31"),
        (390.1, 214.2, 32.0, "#EA37C7"),
        (460.1, 214.0, 32.0, "#CB3067"),
        (530.3, 214.1, 32.0, "#CB3057"),
        (600.3, 214.1, 32.0, "#CB3049"),
        (670.5, 214.2, 32.0, "#BB2721"),
        (740.5, 214.1, 32.0, "#ED706B"),
        (810.1, 217.7, 32.0, "#CC503D"),
        (1077.7, 225.8, 32.0, "#D39C39"),
        (878.9, 228.6, 32.2, "#ED7050"),
        (946.3, 246.6, 32.0, "#EE7F5F"),
        (1138.4, 260.8, 32.0, "#F3AE3D"),
        (1011.3, 271.6, 32.0, "#AF5B21"),
        (249.8, 284.2, 32.0, "#EC54C7"),
        (320.0, 284.2, 31.8, "#EC54A7"),
        (390.1, 284.2, 32.0, "#DC5269"),
        (460.1, 284.1, 32.0, "#AC232A"),
        (530.2, 284.1, 32.0, "#BB2C39"),
        (600.3, 284.2, 32.0, "#DB4659"),
        (670.4, 284.2, 32.0, "#BC353A"),
        (740.5, 284.2, 32.0, "#7D160D"),
        (809.6, 288.2, 32.0, "#BE5D4B"),
        (877.9, 300.1, 32.0, "#8F4919"),
        (1195.4, 301.5, 32.0, "#F5BE41"),
        (1073.4, 303.3, 32.0, "#C17B37"),
        (944.3, 320.1, 32.0, "#C17B42"),
        (1131.8, 341.3, 32.0, "#A16923"),
        (1007.9, 347.5, 32.0, "#D39C54"),
        (1248.4, 347.3, 32.0, "#F7CE55"),
        (320.0, 354.3, 31.8, "#ED70C8"),
        (390.0, 354.3, 32.0, "#ED70B8"),
        (460.2, 354.3, 32.0, "#BD4E86"),
        (530.2, 354.2, 32.0, "#7D1625"),
        (600.3, 354.2, 32.0, "#8C1A1A"),
        (670.5, 354.2, 32.0, "#BC4149"),
        (740.5, 354.1, 32.0, "#6F3735"),
        (809.1, 358.7, 32.2, "#BF6C5A"),
        (876.5, 372.1, 32.0, "#7E391C"),
        (1067.9, 382.2, 32.0, "#D5AC63"),
        (1186.1, 385.1, 31.8, "#FADE6D"),
        (941.5, 394.2, 32.0, "#704715"),
        (1296.7, 398.0, 32.0, "#D8BC3E"),
        (1123.5, 423.6, 32.0, "#C49B48"),
        (530.3, 424.3, 32.0, "#CE6D98"),
        (600.3, 424.4, 32.0, "#F19EAB"),
        (670.3, 424.2, 32.0, "#8D2D36"),
        (740.5, 424.3, 32.0, "#B48A89"),
        (1003.4, 424.6, 32.0, "#926827"),
        (808.4, 429.3, 32.0, "#8F4938"),
        (1235.3, 434.4, 32.0, "#DACD46"),
        (874.8, 444.4, 32.0, "#7F482A"),
        (1340.0, 453.1, 31.5, "#FADE4B"),
        (1060.5, 462.9, 32.0, "#D8BC73"),
        (938.2, 469.5, 32.0, "#F7CEAF"),
        (1173.9, 471.1, 31.5, "#FCEF70"),
        (1279.2, 488.6, 32.0, "#FCEF5D"),
        (740.5, 494.2, 32.0, "#815856"),
        (673.6, 500.3, 32.0, "#5D0E15"),
        (807.5, 500.2, 32.0, "#6F3727"),
        (997.2, 503.4, 32.2, "#70471D"),
        (1112.2, 508.2, 32.0, "#EBDE93"),
        (1377.8, 512.0, 31.8, "#FFFF00"),
        (608.6, 517.6, 32.0, "#6D1C34"),
        (872.4, 517.7, 32.0, "#A3795B"),
        (1218.4, 524.2, 32.0, "#EBDE58"),
        (547.7, 546.1, 31.8, "#F3AECB"),
        (933.3, 546.1, 31.8, "#E9CDAE"),
        (1050.4, 546.0, 31.8, "#D8BC8F"),
        (1317.2, 547.0, 32.0, "#FFFF61"),
        (1157.6, 559.9, 32.0, "#DACD75"),
        (740.5, 564.4, 32.0, "#635656"),
        (675.0, 571.3, 32.0, "#5E1924"),
        (806.1, 571.4, 32.0, "#3E1505"),
        (224.5, 582.0, 32.2, "#FF00FF"),
        (1256.5, 582.0, 32.2, "#888829"),
        (492.7, 584.5, 32.0, "#5D0E42"),
        (988.3, 584.6, 32.0, "#B69B6D"),
        (868.8, 591.8, 32.0, "#C7AC9C"),
        (612.2, 591.8, 31.8, "#F5BECC"),
        (1096.7, 595.8, 32.0, "#968942"),
        (285.3, 617.1, 32.0, "#BE5DC7"),
        (1195.8, 617.1, 31.5, "#FFFFD1"),
        (555.1, 624.7, 32.0, "#C28B99"),
        (925.9, 624.8, 31.5, "#FCEFD0"),
        (445.3, 632.0, 32.0, "#7E3974"),
        (1035.8, 632.1, 31.5, "#FCEFB2"),
        (193.5, 643.8, 32.0, "#BB27C6"),
        (1287.5, 643.9, 32.0, "#E4FE52"),
        (345.9, 652.1, 31.8, "#E08DE9"),
        (1135.1, 652.1, 31.5, "#FFFFE1"),
        (506.2, 668.8, 32.0, "#6E2963"),
        (974.9, 668.9, 31.5, "#FCEFC1"),
        (254.7, 678.6, 32.0, "#7D1684"),
        (1226.2, 678.7, 32.0, "#E0EE5B"),
        (406.6, 687.1, 32.0, "#D8BCDB"),
        (169.7, 709.0, 31.8, "#CB2BF6"),
        (1311.3, 709.0, 31.8, "#CAFD51"),
        (316.4, 713.5, 32.0, "#D07CD8"),
        (1164.6, 713.5, 32.0, "#CFDD84"),
        (467.4, 722.2, 32.2, "#2F1332"),
        (1013.7, 722.2, 31.5, "#EEEEDF"),
        (740.5, 739.5, 32.0, "#666666"),
        (232.7, 743.9, 32.0, "#D07CF8"),
        (1248.3, 743.8, 32.0, "#8FA937"),
        (378.3, 748.1, 31.8, "#C7ACCA"),
        (1102.7, 748.0, 31.8, "#596622"),
        (679.8, 774.6, 32.0, "#555555"),
        (801.2, 774.8, 32.0, "#AAAAAA"),
        (1327.2, 776.5, 32.0, "#97CA3E"),
        (296.3, 778.5, 32.0, "#B27AD7"),
        (1184.7, 778.5, 32.0, "#719838"),
        (440.6, 782.3, 32.0, "#9059A6"),
        (1040.4, 782.4, 32.0, "#4C652C"),
        (740.5, 809.8, 32.0, "#777777"),
        (219.3, 811.2, 32.0, "#AC23F6"),
        (1261.7, 811.3, 32.0, "#93BA39"),
        (1120.2, 812.9, 32.0, "#8B995D"),
        (360.9, 813.0, 31.5, "#D5ACFA"),
        (679.8, 844.7, 32.2, "#444444"),
        (801.2, 844.8, 32.0, "#BBBBBB"),
        (286.2, 845.8, 32.0, "#9268C6"),
        (1194.7, 845.7, 32.0, "#40651A"),
        (1335.3, 845.3, 32.0, "#80CA3D"),
        (1054.2, 846.9, 32.0, "#8B997A"),
        (426.8, 846.9, 31.8, "#C7ACDA"),
        (214.8, 879.8, 32.0, "#7D16C5"),
        (355.0, 879.8, 32.0, "#603694"),
        (619.1, 879.8, 32.2, "#000000"),
        (740.5, 879.9, 32.0, "#888888"),
        (1126.0, 879.9, 32.0, "#8FA96E"),
        (1266.2, 879.8, 32.0, "#93BA3C"),
        (426.8, 912.7, 32.0, "#836896"),
        (286.2, 913.7, 32.0, "#3E0683"),
        (1054.1, 912.9, 31.5, "#E4FED1"),
        (1194.8, 913.9, 32.0, "#A4CB81"),
        (679.8, 914.8, 32.2, "#333333"),
        (1335.3, 914.5, 32.0, "#B1FD5D"),
        (801.2, 914.9, 31.5, "#CCCCCC"),
        (360.8, 946.7, 32.0, "#7257A5"),
        (1120.2, 946.7, 32.2, "#406521"),
        (219.3, 948.3, 32.0, "#7D16F5"),
        (1261.7, 948.5, 32.0, "#618726"),
        (619.1, 950.0, 32.5, "#111111"),
        (740.5, 950.0, 31.8, "#999999"),
        (861.8, 950.0, 31.5, "#EEEEEE"),
        (440.5, 977.3, 32.0, "#000031"),
        (1040.5, 977.3, 32.0, "#82A97C"),
        (296.4, 981.1, 32.0, "#6036A4"),
        (1184.7, 981.2, 32.0, "#285413"),
        (1327.2, 983.4, 32.0, "#9CFC4E"),
        (679.7, 984.9, 32.2, "#222222"),
        (801.1, 985.0, 31.5, "#DDDDDD"),
        (1102.7, 1011.7, 32.0, "#7BB96F"),
        (378.2, 1011.8, 31.8, "#CCCCFB"),
        (232.6, 1015.8, 32.0, "#4E17F5"),
        (1248.3, 1015.9, 32.0, "#67B93A"),
        (467.4, 1037.5, 31.0, "#EEEEFE"),
        (316.3, 1046.2, 32.0, "#7467C6"),
        (1164.6, 1046.3, 32.0, "#87B970"),
        (1311.3, 1050.8, 32.0, "#83FC4D"),
        (406.6, 1072.6, 32.0, "#AAAAD9"),
        (1074.4, 1072.6, 32.0, "#B5DCAF"),
        (254.8, 1080.9, 32.2, "#5345C5"),
        (1226.2, 1081.0, 32.2, "#3E8624"),
        (506.1, 1090.9, 32.2, "#263363"),
        (974.9, 1090.9, 32.2, "#87B98C"),
        (345.9, 1107.6, 32.2, "#111172"),
        (1135.1, 1107.6, 32.0, "#448633"),
        (1287.5, 1115.8, 32.0, "#7DFC4F"),
        (445.2, 1127.7, 32.0, "#8FA9F9"),
        (1035.8, 1127.6, 32.0, "#52974E"),
        (555.1, 1135.1, 32.0, "#113253"),
        (925.9, 1135.0, 31.5, "#BDFDD0"),
        (285.2, 1142.6, 32.0, "#4444A4"),
        (1195.8, 1142.7, 32.0, "#A1EC93"),
        (384.3, 1164.0, 32.2, "#031093"),
        (1096.7, 1163.9, 31.8, "#76CA80"),
        (868.8, 1168.0, 32.2, "#558769"),
        (612.2, 1168.0, 31.8, "#B5DCEC"),
        (988.3, 1175.0, 32.2, "#337549"),
        (492.7, 1175.2, 32.0, "#5C76B6"),
        (224.5, 1177.7, 32.0, "#111183"),
        (1256.5, 1177.7, 32.0, "#44972A"),
        (674.9, 1188.3, 32.0, "#1A4353"),
        (806.1, 1188.3, 32.0, "#2B6556"),
        (740.5, 1195.3, 32.0, "#719899"),
        (323.5, 1199.8, 32.0, "#4C65D6"),
        (1157.5, 1199.9, 31.8, "#7DFC7A"),
        (163.8, 1212.7, 32.0, "#4444F6"),
        (1317.2, 1212.8, 32.0, "#00FF00"),
        (430.6, 1213.9, 32.0, "#1A32A4"),
        (547.7, 1213.7, 32.0, "#5C76A6"),
        (933.3, 1213.7, 32.0, "#71B99B"),
        (1050.4, 1213.8, 32.0, "#67B98C"),
        (262.6, 1235.5, 32.0, "#3744D5"),
        (608.6, 1242.1, 32.0, "#6187A7"),
        (872.4, 1242.1, 32.0, "#59A88A"),
        (103.2, 1247.7, 32.0, "#0000FF"),
        (368.8, 1251.5, 32.0, "#1132A4"),
        (1112.2, 1251.6, 32.0, "#54B849"),
        (483.9, 1256.2, 32.2, "#4C65C6"),
        (997.2, 1256.3, 32.2, "#4CA86C"),
        (673.5, 1259.5, 32.0, "#97CAEB"),
        (807.4, 1259.3, 32.0, "#337567"),
        (740.5, 1265.3, 31.8, "#D7FEFE"),
        (201.8, 1271.2, 32.0, "#1A43F5"),
        (307.1, 1288.7, 32.0, "#3665C5"),
        (542.8, 1290.4, 32.0, "#87B9EA"),
        (938.2, 1290.3, 32.0, "#9CFCDF"),
        (420.5, 1296.9, 32.0, "#7198E8"),
        (1060.5, 1296.9, 32.0, "#75FB63"),
        (606.2, 1315.3, 32.0, "#5B97C8"),
        (874.8, 1315.2, 32.0, "#7CEBCE"),
        (245.7, 1325.4, 32.0, "#3B86F7"),
        (672.6, 1330.4, 32.0, "#9CDBFC"),
        (808.4, 1330.4, 32.0, "#67B9AA"),
        (477.6, 1335.1, 32.0, "#87B9FA"),
        (740.5, 1335.4, 32.0, "#467676"),
        (1003.4, 1335.1, 32.0, "#66DA67"),
        (357.5, 1336.2, 32.0, "#1A43A4"),
        (539.4, 1365.4, 32.0, "#2B65A5"),
        (941.7, 1365.5, 32.0, "#75FB87"),
        (413.1, 1377.5, 32.0, "#4C86E7"),
        (604.5, 1387.5, 32.0, "#2B6595"),
        (876.6, 1387.7, 32.0, "#5CC99D"),
        (671.9, 1400.9, 32.5, "#3375A6"),
        (809.1, 1401.0, 32.5, "#3B8687"),
        (740.5, 1405.5, 32.0, "#BDFDFE"),
        (473.1, 1412.1, 32.0, "#3D76B6"),
        (536.6, 1439.6, 32.0, "#3375B6"),
        (603.1, 1459.5, 32.0, "#4497D7"),
        (671.3, 1471.6, 32.0, "#75DAEB"),
        (809.7, 1471.6, 32.0, "#5CC9CB"),
        (740.5, 1475.6, 32.0, "#9CFCFE"),
        (602.1, 1531.2, 32.2, "#4CA8F8"),
        (670.9, 1542.1, 32.0, "#54B8F9"),
        (740.5, 1545.7, 32.0, "#00FFFF")
    ] + (0..<12).map { index in
        let value = Int((Double(index) / 11 * 255).rounded())
        return (CGFloat(0), CGFloat(0), CGFloat(32), String(format: "#%02X%02X%02X", value, value, value))
    }
}
