#if APPSTORE
import AppKit

/// One status item keeps the swatches, shared copy format and app icon together as a single movable cluster.
final class AppleMenubar: NSObject {
    static let shared = AppleMenubar()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let content = NSView()
    private let format = NSButton(title: "", target: nil, action: nil)
    private let icon = NSButton(title: "", target: nil, action: nil)
    private var swatches: [MenubarSwatchButton] = []
    private var observers: [NSObjectProtocol] = []
    private weak var library: LibraryController?
    private var showApp: (() -> Void)?
    private var nameBar: MenubarPaletteNameBar?
    override init() {
        super.init()
        item.autosaveName = "Colorgain Apple Menubar"
        guard let button = item.button else { return }
        button.addSubview(content)
        for control in [format, icon] { control.isBordered = false; content.addSubview(control); control.target = self }
        format.font = Design.Text.body.font(); format.action = #selector(chooseFormat)
        format.setAccessibilityLabel("Colour Copy Format")
        icon.image = NSImage(named: NSImage.applicationIconName); icon.imageScaling = .scaleProportionallyDown
        icon.action = #selector(openMenu); icon.toolTip = "Colorgain · Picker And Rectangle Picker"
        icon.setAccessibilityLabel("Colorgain Menu")
        for name in [ColourCopies.changed, .prefsDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }
    func bind(to library: LibraryController, showApp: @escaping () -> Void) {
        self.library = library; self.showApp = showApp; refresh()
    }
    private func refresh() {
        let history = Array(ColourCopies.recent.suffix(Prefs.appleMenubarCount))
        swatches.forEach { $0.removeFromSuperview() }; swatches = []
        var x: CGFloat = 4
        if Prefs.appleMenubarSwatches {
            for slot in 0..<Prefs.appleMenubarCount {
                let entry = slot < history.count ? history[slot] : nil
                let button = MenubarSwatchButton(frame: NSRect(x: x, y: 3, width: 18, height: 18))
                button.entry = entry; button.target = self; button.action = #selector(copySwatch(_:))
                button.isEnabled = entry != nil
                button.setAccessibilityLabel(entry.map { "Copy " + Prefs.copyText($0.key) } ?? "Empty Swatch Slot")
                button.toolTip = entry.map { Prefs.copyText($0.key) } ?? "Pick A Colour To Fill This Slot"
                content.addSubview(button); swatches.append(button); x += 21
            }
            x += 6
        }
        format.title = Prefs.copyFormat.label + " ▾"
        let width = max(48, format.intrinsicContentSize.width + 4)
        format.frame = NSRect(x: x, y: 0, width: width, height: 24); x += width + 6
        icon.frame = NSRect(x: x, y: 1, width: 24, height: 22); x += 28
        item.length = x; content.frame = NSRect(x: 0, y: 0, width: x, height: 24)
        item.button?.setAccessibilityLabel("Colorgain Colour Tools")
    }
    @objc private func copySwatch(_ sender: MenubarSwatchButton) {
        guard let entry = sender.entry else { return }
        ColourCopies.copy(entry.key, sourceCMYK: entry.sourceCMYK, record: false, sound: Prefs.appleMenubarSound)
    }
    @objc private func chooseFormat() {
        let menu = NSMenu(title: "Colour Copy Format")
        for value in StudioPage.models {
            let row = NSMenuItem(title: value.label, action: #selector(setFormat(_:)), keyEquivalent: "")
            row.target = self; row.representedObject = value.rawValue; row.state = Prefs.copyFormat == value ? .on : .off
            menu.addItem(row)
        }
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: 0, y: 0), in: format)
    }
    @objc private func setFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = ColourFormat(rawValue: raw) else { return }
        Prefs.copyFormat = value
        StudioWindowController.shared?.frame.needsDisplay = true
        StudioWindowController.shared?.frame.reload()
    }
    @objc private func openMenu() {
        let menu = NSMenu(title: "Colorgain")
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let row = NSMenuItem(title: title, action: action, keyEquivalent: ""); row.target = self; row.isEnabled = enabled; menu.addItem(row)
        }
        add("New Palette", #selector(newPalette), enabled: library != nil)
        menu.addItem(.separator())
        add(library?.picking == true ? "Stop Picker" : "Picker", #selector(pick), enabled: library != nil)
        add("Rectangle Picker", #selector(rectangle), enabled: library != nil)
        menu.addItem(.separator())
        add("Open Colorgain", #selector(openApp)); add("Apple Menubar Settings", #selector(settings))
        menu.addItem(.separator()); add("Quit Colorgain", #selector(quit))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: icon)
    }
    @objc private func newPalette() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let library = self.library, let id = library.createMenubarPalette() else { return }
            let bar = MenubarPaletteNameBar(library: library, palette: id)
            bar.onClose = { [weak self] in self?.nameBar = nil }
            self.nameBar = bar
            if let button = self.item.button { bar.show(below: button) }
        }
    }
    @objc private func pick() { library?.startMenubarPicking(sound: Prefs.appleMenubarSound) }
    @objc private func rectangle() { library?.sampleAreaFromMenubar(sound: Prefs.appleMenubarSound) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openApp() { showApp?() }
    @objc private func settings() { showApp?(); StudioWindowController.shared?.frame.go(.appleMenubar) }
}

private final class MenubarSwatchButton: NSButton {
    var entry: ColourCopies.Entry?
    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        (entry.map { colorFromHex($0.key) ?? NSColor.controlBackgroundColor } ?? NSColor.quaternaryLabelColor).setFill()
        NSBezierPath(rect: box).fill()
        NSColor.labelColor.withAlphaComponent(0.3).setStroke(); let border = NSBezierPath(rect: box); border.lineWidth = 0.5; border.stroke()
        if isHighlighted { NSColor.labelColor.setStroke(); let pressed = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); pressed.lineWidth = 1; pressed.stroke() }
    }
}

private final class MenubarCountSlider: NSSlider {
    override func draw(_ dirtyRect: NSRect) {
        let fraction = CGFloat((doubleValue - minValue) / max(1, maxValue - minValue))
        let x = 4 + (bounds.width - 8) * fraction, y = bounds.midY
        fill(NSRect(x: 4, y: y, width: bounds.width - 8, height: 1), Design.rule)
        fill(NSRect(x: 4, y: y, width: max(0, x - 4), height: 1), Design.ink)
        for tick in 0..<20 {
            fill(NSRect(x: 4 + CGFloat(tick) * (bounds.width - 8) / 19, y: y + 5, width: 1, height: 3), Design.rule)
        }
        fill(NSRect(x: x - 4, y: y - 4, width: 8, height: 8), Design.ink)
    }
}

final class AppleMenubarSettings: NSView, PageSection {
    var onResize: (() -> Void)?
    var sectionAnchors: [(String, CGFloat)] { [("Settings", SettingsSheet.headerGuide + 1)] }
    private let descriptions = ["Show your recent swatches beside the shared copy-format selector and Colorgain icon. Click a swatch to copy it. The format stays synchronized with the app header.","The most recent samples fill these slots. Empty slots remain available until you pick more colours.","Use the Copy Swatch and Colour Pick effects selected in Settings → Sounds. Its master and event switches still apply; turning this off mutes only menubar actions."]
    private let visible = SwissButton("", .secondary)
    private let sound = SwissButton("", .secondary)
    private let count = MenubarCountSlider(value: 10, minValue: 1, maxValue: 20, target: nil, action: nil)
    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    init() {
        super.init(frame: .zero)
        visible.target = self; visible.action = #selector(toggleVisible)
        sound.target = self; sound.action = #selector(toggleSound)
        count.target = self; count.action = #selector(changeCount); count.isContinuous = true
        count.numberOfTickMarks = 20; count.allowsTickMarkValuesOnly = true
        count.setAccessibilityLabel("Number Of Menubar Swatches")
        for view in [visible, sound, count] { addSubview(view) }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    func reload() {
        visible.title = "Show Swatches In Menubar: " + (Prefs.appleMenubarSwatches ? "On" : "Off")
        sound.title = "Menubar Sound: " + (Prefs.appleMenubarSound ? "On" : "Off")
        count.integerValue = Prefs.appleMenubarCount; count.isHidden = !Prefs.appleMenubarSwatches
        needsLayout = true; needsDisplay = true; onResize?()
    }
    private func geometry(_ width: CGFloat) -> (count: CGFloat, sound: CGFloat, end: CGFloat) {
        let x = SettingsSheet.contentColumn(width: width, window: window?.frame.width ?? Design.App.size.width), textWidth = max(140, width - x)
        let countRow = 5 + SettingsSheet.settingAdvance(descriptions[0], width: textWidth)
        let soundRow = Prefs.appleMenubarSwatches ? countRow + SettingsSheet.settingAdvance(descriptions[1], width: textWidth, paragraphOffset: 3) : countRow
        return (countRow, soundRow, soundRow + SettingsSheet.settingAdvance(descriptions[2], width: textWidth))
    }
    func height(forWidth width: CGFloat) -> CGFloat { SettingsSheet.baseline(geometry(width).end + 2) }
    override func layout() {
        super.layout()
        let width = max(140, bounds.width - contentX)
        visible.frame = NSRect(x: contentX, y: SettingsSheet.buttonTop(baseline: SettingsSheet.baseline(5)), width: min(width, visible.intrinsicContentSize.width), height: SwissButton.height)
        count.frame = NSRect(x: contentX, y: SettingsSheet.baseline(geometry(bounds.width).count + 1) - 17, width: min(380, width), height: 28)
        sound.frame = NSRect(x: contentX, y: SettingsSheet.buttonTop(baseline: SettingsSheet.baseline(geometry(bounds.width).sound)), width: min(width, sound.intrinsicContentSize.width), height: SwissButton.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        SettingsSheet.title("Apple Menubar.")
        SettingsSheet.introduction("Colour tools everywhere", "Pick, sample and copy without bringing the workspace forward.", x: contentX, width: bounds.width)
        SettingsSheet.section(1, "Settings", guide: SettingsSheet.headerGuide, contentX: contentX, width: bounds.width)
        SettingsSheet.paragraph(descriptions[0], x: contentX, firstBaseline: SettingsSheet.baseline(7), width: bounds.width - contentX, height: SettingsSheet.settingAdvance(descriptions[0], width: max(140, bounds.width - contentX)) * Design.App.unit)
        if Prefs.appleMenubarSwatches {
            Design.attributed("\(Prefs.appleMenubarCount) Swatches · Choose From 1–20", .bodyStrong).draw(x: contentX, baseline: SettingsSheet.baseline(geometry(bounds.width).count), width: bounds.width - contentX)
            SettingsSheet.paragraph(descriptions[1], x: contentX, firstBaseline: SettingsSheet.baseline(geometry(bounds.width).count + 3), width: bounds.width - contentX, height: SettingsSheet.settingAdvance(descriptions[1], width: max(140, bounds.width - contentX)) * Design.App.unit)
        }
        SettingsSheet.paragraph(descriptions[2], x: contentX, firstBaseline: SettingsSheet.baseline(geometry(bounds.width).sound + 2), width: bounds.width - contentX, height: SettingsSheet.settingAdvance(descriptions[2], width: max(140, bounds.width - contentX)) * Design.App.unit)
        SettingsSheet.divider(above: SettingsSheet.baseline(geometry(bounds.width).end), width: bounds.width)
    }
    @objc private func toggleVisible() { Prefs.appleMenubarSwatches.toggle(); reload() }
    @objc private func toggleSound() { Prefs.appleMenubarSound.toggle(); reload() }
    @objc private func changeCount() { Prefs.appleMenubarCount = count.integerValue; needsDisplay = true }
}
#endif
