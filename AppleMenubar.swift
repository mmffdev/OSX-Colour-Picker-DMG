import AppKit
import CoreText

/// One status item keeps the swatches, shared copy format and app icon together as a single movable cluster.
final class AppleMenubar: NSObject {
    static let shared = AppleMenubar()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var swatches:[(rect:NSRect,entry:ColourCopies.Entry?)]=[]
    private var formatRect=NSRect.zero
    private var renderKey=""
    private var observers: [NSObjectProtocol] = []
    private weak var library: LibraryController?
    private var showApp: (() -> Void)?
    private var nameBar: MenubarPaletteNameBar?
    override init() {
        super.init()
        item.autosaveName = "Colorgain Apple Menubar"
        guard let button = item.button else { return }
        // Keep the system status button flat. Nested live controls cause repeated
        // AppKit replicant snapshots on macOS 26, even while the app is idle.
        button.target=self;button.action=#selector(pressed)
        button.imagePosition = .imageOnly
        button.toolTip="Colorgain · Click A Swatch To Copy, The Format To Change It, Or The Icon For Tools"
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(appearanceChanged),name:NSNotification.Name("AppleInterfaceThemeChangedNotification"),object:nil)
        for name in [ColourCopies.changed, .prefsDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }
    func bind(to library: LibraryController, showApp: @escaping () -> Void) {
        self.library = library; self.showApp = showApp; refresh()
    }
    @objc private func appearanceChanged(){renderKey="";refresh()}
    private func refresh() {
        guard let button=item.button else{return}
        let history=Array(ColourCopies.recent.suffix(Prefs.appleMenubarCount))
        let dark=button.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        let key=([String(dark),String(Prefs.appleMenubarSwatches),String(Prefs.appleMenubarCount),Prefs.copyFormat.rawValue]+history.map{$0.key+($0.sourceCMYK ?? "")}).joined(separator:"|")
        guard key != renderKey else{return};renderKey=key
        swatches=[];var x:CGFloat=8
        if Prefs.appleMenubarSwatches {
            for slot in 0..<Prefs.appleMenubarCount {
                swatches.append((NSRect(x:x,y:3,width:18,height:18),slot<history.count ? history[slot]:nil));x+=21
            }
            x+=6
        }
        let foreground=dark ? NSColor.white:NSColor.black
        let label=NSAttributedString(string:Prefs.copyFormat.label+" ▾",attributes:[.font:Design.Text.body.font(),.foregroundColor:foreground])
        let width=max(48,label.size().width+12)
        formatRect=NSRect(x:x,y:0,width:width,height:24);x+=width+6
        let iconRect=NSRect(x:x,y:1,width:22,height:22);x+=28
        let image=NSImage(size:NSSize(width:x,height:24))
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            image.lockFocus()
            let pill=NSBezierPath(roundedRect:NSRect(x:0.5,y:0.5,width:x-1,height:23),xRadius:11.5,yRadius:11.5)
            (dark ? NSColor(calibratedWhite:0.16,alpha:1):NSColor(calibratedWhite:0.98,alpha:1)).setFill();pill.fill()
            (dark ? NSColor.white.withAlphaComponent(0.55):NSColor.black.withAlphaComponent(0.25)).setStroke()
            pill.lineWidth=1;pill.stroke()
            for slot in swatches {
                let box=slot.rect.insetBy(dx:1,dy:1)
                (slot.entry.flatMap{colorFromHex($0.key)} ?? NSColor.quaternaryLabelColor).setFill();box.fill()
                foreground.withAlphaComponent(0.3).setStroke();let border=NSBezierPath(rect:box);border.lineWidth=0.5;border.stroke()
            }
            // Centre the visible glyphs, including the arrow, rather than the font's line box.
            let line=CTLineCreateWithAttributedString(label)
            let ink=CTLineGetBoundsWithOptions(line,.useGlyphPathBounds)
            if let context=NSGraphicsContext.current?.cgContext {
                context.textPosition=CGPoint(x:formatRect.minX+4,y:formatRect.midY-ink.midY)
                CTLineDraw(line,context)
            }
            NSImage(named:NSImage.applicationIconName)?.draw(in:iconRect)
            image.unlockFocus()
        }
        image.isTemplate=false;item.length=x;button.image=image
        button.setAccessibilityLabel("Colorgain Colour Tools · "+Prefs.copyFormat.label)
        var actions=swatches.compactMap{slot->NSAccessibilityCustomAction? in
            guard let entry=slot.entry else{return nil}
            return NSAccessibilityCustomAction(name:"Copy "+Prefs.copyText(entry.key),handler:{ColourCopies.copy(entry.key,sourceCMYK:entry.sourceCMYK,record:false,sound:Prefs.appleMenubarSound);return true})
        }
        actions.append(NSAccessibilityCustomAction(name:"Colour Copy Format",handler:{ [weak self] in self?.chooseFormat();return true }))
        button.setAccessibilityCustomActions(actions)
    }
    @objc private func pressed(){
        guard let button=item.button else{return}
        // Accessibility and keyboard activation open the complete tools menu.
        guard let event=NSApp.currentEvent,event.type == .leftMouseDown || event.type == .leftMouseUp else{openMenu();return}
        let point=button.convert(event.locationInWindow,from:nil)
        if let slot=swatches.first(where:{$0.rect.contains(point)}) {
            if let entry=slot.entry{ColourCopies.copy(entry.key,sourceCMYK:entry.sourceCMYK,record:false,sound:Prefs.appleMenubarSound)}
        } else if formatRect.contains(point){chooseFormat()}else{openMenu()}
    }
    @objc private func chooseFormat() {
        let menu = NSMenu(title: "Colour Copy Format")
        for value in StudioPage.models {
            let row = NSMenuItem(title: value.label, action: #selector(setFormat(_:)), keyEquivalent: "")
            row.target = self; row.representedObject = value.rawValue; row.state = Prefs.copyFormat == value ? .on : .off
            menu.addItem(row)
        }
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: formatRect.minX, y: 0), in: item.button)
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
        menu.popUp(positioning: nil, at: NSPoint(x: formatRect.maxX+6, y: 0), in: item.button)
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

private final class MenubarCountSlider: ClickCursorSlider {
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
