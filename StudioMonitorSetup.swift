import AppKit
import CoreGraphics

// THESIS: a guided visual check on the user's actual display, with honest unmeasured results.
// OWN-WORLD: shared Swiss controls, square patterns, neutral surroundings, measured grid spacing.
// STORY: choose a display, inspect each pattern, adjust physical controls, retain notes and progress.
// FIRST VIEWPORT: pattern left; display, instructions and actions right; persistent step navigation.
// FORM: sequential console-style setup as requested; focused full-screen patterns extend the guide.

enum MonitorCheck: Int, CaseIterable, Codable {
    case prepare, shadows, highlights, neutral, channels, gradients, review
    var title: String { ["Prepare your display", "Shadow detail", "Highlight detail", "Neutral greys", "Colour channels", "Smooth gradients", "Review your setup"][rawValue] }
    var instruction: String {
        switch self {
        case .prepare: return "Use your normal working light and let the display warm up. Select its Standard or sRGB preset if available. Use native resolution. Temporarily turn off Night Shift, True Tone, automatic brightness and dynamic contrast. Note your original settings before changing them."
        case .shadows: return "Look for separation between the numbered dark patches and the black surround. The very darkest steps may be difficult to see. Adjust black level only if your monitor provides it; backlight brightness controls light output and is not the same thing. Do not wash out black to reveal every step."
        case .highlights: return "Look for separation between the near-white patches and the white surround. If several merge into white, reduce contrast if available. Keep white comfortable in your working light. This check cannot measure brightness in cd/m²."
        case .neutral: return "The grey steps should look neutral, without an obvious red, green or blue cast. Try the monitor's sRGB or 6500 K preset where available. Your eyes adapt to colour casts: this is a visual check, not confirmation of D65 accuracy."
        case .channels: return "Check the red, green and blue rows for distinct steps at both ends. Avoid settings that flatten several steps into one colour. Use the monitor's standard preset rather than boosting saturation. These patches cannot prove colour accuracy or gamut coverage."
        case .gradients: return "Inspect the grey and RGB ramps for abrupt jumps, tint and banding. Compare from your normal viewing position. Some banding can come from the display, graphics pipeline or the finite steps of this test; do not adjust colour controls simply to hide it."
        case .review: return "Record the monitor settings you chose and your room lighting below. Checked steps mean you inspected them, not that the display passed a measured test. Recheck shadow and highlight detail after any final adjustment. An instrument is needed for measured calibration and profiling."
        }
    }
    var levels: [Int] {
        switch self {
        case .shadows: return [0, 2, 4, 8, 12, 16, 24, 32]
        case .highlights: return [223, 231, 239, 243, 247, 251, 253, 255]
        default: return [0, 32, 64, 96, 128, 160, 192, 224, 255]
        }
    }
}

struct MonitorSetupRecord: Codable {
    var step = 0
    var checked: Set<Int> = []
    var notes = ""
    var updated = Date()
    var complete: Bool { (0..<6).allSatisfy { checked.contains($0) } }
    var safeStep: Int { min(6, max(0, step)) }
}

/// Machine-local records: never sync monitor identity or pretend these are calibration profiles.
enum MonitorSetupStore {
    static let prefix = "MonitorVisualSetup.v1."
    static func key(_ screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() { return CFUUIDCreateString(nil, uuid) as String }
        return "Display-\(id)"
    }
    static func read(_ key: String) -> MonitorSetupRecord {
        guard let data = UserDefaults.standard.data(forKey: prefix + key), let record = try? JSONDecoder().decode(MonitorSetupRecord.self, from: data) else { return MonitorSetupRecord() }
        return record
    }
    static func save(_ record: MonitorSetupRecord, key: String) {
        if let data = try? JSONEncoder().encode(record) { UserDefaults.standard.set(data, forKey: prefix + key) }
    }
}

final class MonitorSetupView: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    private var screens = NSScreen.screens
    private var selectedID = ""
    private var record = MonitorSetupRecord()
    private let pattern = MonitorPatternView()
    private let close = ProofChartArrow("Close monitor setup", contracts: true)
    private let back = SwissButton("Previous", .secondary)
    private let next = SwissButton("Next", .secondary)
    private let checked = SwissButton("Mark Checked", .secondary)
    private let fullscreen = SwissButton("Full Screen", .primary)
    private let notes = NSTextField(string: "")
    private var displayMenu: SwissDropdown?
    private var observer: NSObjectProtocol?
    private var fullscreenWindow: MonitorPatternWindow?
    private var status = ""
    private var rightX: CGFloat { max(280, bounds.width * 0.60) }
    private var rightWidth: CGFloat { bounds.width-rightX }
    private var step: MonitorCheck { MonitorCheck(rawValue: record.safeStep)! }
    init() {
        super.init(frame: .zero)
        for b in [back,next,checked,fullscreen] { addSubview(b); b.target=self }
        back.action=#selector(previous); next.action=#selector(advance); checked.action=#selector(mark); fullscreen.action=#selector(openFullscreen)
        close.target=self; close.action=#selector(finish); addSubview(close); addSubview(pattern)
        notes.font=Design.Text.body.font(); notes.textColor=Design.ink; notes.backgroundColor=Design.card
        notes.isBordered=false; notes.focusRingType = .none; notes.delegate=self
        notes.cell?.wraps=true; notes.cell?.isScrollable=false
        notes.placeholderAttributedString=Design.attributed("Preset, brightness, contrast, RGB gains, room light…",.body,colour:Design.quiet)
        notes.setAccessibilityLabel("Monitor settings and room lighting notes"); addSubview(notes)
        selectedID=screens.first.map(MonitorSetupStore.key) ?? ""
        loadRecord(); rebuildDisplayMenu()
        observer=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.screensChanged() }
        setAccessibilityLabel("Visual monitor setup. Unmeasured. Seven guided steps.")
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) }; fullscreenWindow?.close() }
    override var isFlipped: Bool { true }
    private func persist() { record.updated=Date(); MonitorSetupStore.save(record,key:selectedID) }
    private func loadRecord() { record=MonitorSetupStore.read(selectedID); notes.stringValue=record.notes; refresh() }
    private func screensChanged() {
        closeFullscreen(); screens=NSScreen.screens
        if !screens.contains(where: { MonitorSetupStore.key($0)==selectedID }) {
            selectedID=screens.first.map(MonitorSetupStore.key) ?? ""; loadRecord()
            status="Display configuration changed. Check the selected display."
        }
        rebuildDisplayMenu(); refresh()
    }
    private func rebuildDisplayMenu() {
        displayMenu?.removeFromSuperview()
        let options=screens.enumerated().map { "\($0.offset+1). \($0.element.localizedName)" }
        let index=screens.firstIndex { MonitorSetupStore.key($0)==selectedID } ?? 0
        let menu=SwissDropdown("Display to adjust",value:options.indices.contains(index) ? options[index] : "No display",options:options,allowsOwn:false,width:max(240,rightWidth))
        menu.onChange={ [weak self] name in
            guard let self, let i=options.firstIndex(of:name), self.screens.indices.contains(i) else { return }
            self.closeFullscreen(); self.selectedID=MonitorSetupStore.key(self.screens[i]); self.loadRecord()
        }
        displayMenu=menu; addSubview(menu); needsLayout=true
    }
    private func refresh() {
        pattern.step=step; pattern.needsDisplay=true
        back.isEnabled=record.safeStep>0; next.isEnabled=record.safeStep<6
        checked.title=record.checked.contains(record.safeStep) ? "Undo Check" : "Mark Checked"
        checked.isHidden=step == .review; fullscreen.isEnabled = !screens.isEmpty
        needsDisplay=true; needsLayout=true
        fullscreenWindow?.surface.update(step:step)
    }
    @objc private func previous() { record.step=max(0,record.safeStep-1); persist(); refresh() }
    @objc private func advance() { record.step=min(6,record.safeStep+1); persist(); refresh() }
    @objc private func mark() {
        if record.checked.contains(record.safeStep) { record.checked.remove(record.safeStep) } else { record.checked.insert(record.safeStep) }
        persist(); refresh()
    }
    @objc private func finish() { window?.makeFirstResponder(self); persist(); closeFullscreen(); onClose?() }
    func controlTextDidChange(_ obj: Notification) { record.notes=String(notes.stringValue.prefix(2000)); persist() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { closeFullscreen() } }
    override func layout() {
        super.layout()
        close.frame=NSRect(x:bounds.width-32,y:0,width:32,height:32)
        displayMenu?.constraints.first(where: { $0.firstAttribute == .width })?.constant=rightWidth
        displayMenu?.frame=NSRect(x:rightX,y:56,width:rightWidth,height:64)
        pattern.frame=NSRect(x:0,y:112,width:rightX-32,height:max(120,bounds.height-224))
        notes.frame=NSRect(x:rightX,y:bounds.height-156,width:rightWidth,height:48)
        fullscreen.frame=NSRect(x:rightX,y:bounds.height-88,width:fullscreen.intrinsicContentSize.width,height:32)
        checked.frame=NSRect(x:rightX,y:bounds.height-44,width:checked.intrinsicContentSize.width,height:32)
        back.frame=NSRect(x:0,y:bounds.height-44,width:back.intrinsicContentSize.width,height:32)
        next.frame=NSRect(x:back.frame.maxX+16,y:bounds.height-44,width:next.intrinsicContentSize.width,height:32)
    }
    override func draw(_ dirtyRect:NSRect) {
        Design.attributed("Monitor Setup",.heading).draw(x:0,baseline:17)
        hairline(x:0,y:40,width:bounds.width,Design.rule)
        Design.attributed(String(format:"%02d",record.safeStep+1) + " / 07",.lead).draw(x:0,baseline:84)
        Design.attributed(step.title,.heading).draw(x:100,baseline:84,width:rightX-140)
        SettingsSheet.paragraph(step.instruction,x:rightX,firstBaseline:157,width:rightWidth,height:max(84,bounds.height-390))
        let complete = record.complete ? "Visually adjusted · Unmeasured" : "Visual setup in progress · Unmeasured"
        SettingsSheet.paragraph(complete + "\n\(record.checked.intersection(Set(0..<6)).count) of 6 checks recorded. Saved on this Mac.",x:rightX,firstBaseline:bounds.height-244,width:rightWidth,height:56,colour:Design.quiet)
        Design.attributed("Monitor settings & room light · Saved automatically",.caption,colour:Design.quiet).draw(x:rightX,baseline:bounds.height-176,width:rightWidth)
        hairline(x:rightX,y:bounds.height-108,width:rightWidth,Design.rule)
        SettingsSheet.paragraph(status.isEmpty ? "sRGB patterns through ColorSync · Existing display profile retained. Full Screen opens on the selected display." : status,x:0,firstBaseline:bounds.height-88,width:rightX-32,height:40,colour:Design.quiet)
    }
    @objc private func openFullscreen() {
        guard let screen=screens.first(where:{MonitorSetupStore.key($0)==selectedID}) else { return }
        closeFullscreen()
        let win=MonitorPatternWindow(screen:screen,step:step)
        win.surface.onExit={ [weak self] in self?.closeFullscreen() }
        win.surface.onStep={ [weak self] forward in if forward { self?.advance() } else { self?.previous() } }
        fullscreenWindow=win; win.makeKeyAndOrderFront(nil); win.makeFirstResponder(win.surface)
    }
    private func closeFullscreen() { fullscreenWindow?.close(); fullscreenWindow=nil; window?.makeKeyAndOrderFront(nil) }
}

/// Tagged sRGB patches, transformed by the existing display profile. No device-RGB or profile writes.
final class MonitorPatternView: NSView {
    var step: MonitorCheck = .prepare
    override var isFlipped:Bool { true }
    private func rgb(_ r:Int,_ g:Int,_ b:Int)->NSColor { NSColor(srgbRed:CGFloat(r)/255,green:CGFloat(g)/255,blue:CGFloat(b)/255,alpha:1) }
    override func draw(_ dirtyRect:NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Adjacent source-level bands must not acquire anti-aliased seams against the surround.
        NSGraphicsContext.current?.shouldAntialias=false
        let dark = step == .shadows
        fill(bounds, dark ? rgb(0,0,0) : step == .highlights ? rgb(255,255,255) : rgb(128,128,128))
        let pad:CGFloat=24, area=bounds.insetBy(dx:pad,dy:pad)
        switch step {
        case .shadows,.highlights,.neutral:
            let values=step.levels, gap:CGFloat=4
            let w=(area.width-CGFloat(values.count-1)*gap)/CGFloat(values.count)
            for (i,v) in values.enumerated() {
                let x=area.minX+CGFloat(i)*(w+gap)
                fill(NSRect(x:x,y:area.minY+area.height*0.22,width:w,height:area.height*0.50),rgb(v,v,v))
                Design.attributed("\(v)",.caption,colour:dark ? .white : .black).draw(x:x,baseline:area.minY+area.height*0.72+24,width:w)
            }
        case .channels:
            let values=[0,8,16,32,64,96,128,160,192,224,239,247,255]
            let h=area.height/3
            for channel in 0..<3 { for (i,v) in values.enumerated() {
                let w=area.width/CGFloat(values.count)
                fill(NSRect(x:area.minX+CGFloat(i)*w,y:area.minY+CGFloat(channel)*h,width:w+0.1,height:h-8),rgb(channel==0 ? v:0,channel==1 ? v:0,channel==2 ? v:0))
            } }
        case .prepare,.gradients,.review:
            // 256 exact source levels; device scale can add quantisation. This is an appearance check.
            for channel in 0..<4 { for i in 0..<256 {
                let w=area.width/256, h=area.height/4
                fill(NSRect(x:area.minX+CGFloat(i)*w,y:area.minY+CGFloat(channel)*h,width:w+0.1,height:h-8),rgb(channel==0 || channel==1 ? i:0,channel==0 || channel==2 ? i:0,channel==0 || channel==3 ? i:0))
            } }
        }
    }
}

final class MonitorPatternWindow:NSWindow {
    let surface:MonitorFullscreenView
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
    init(screen:NSScreen,step:MonitorCheck) {
        surface=MonitorFullscreenView(step:step)
        super.init(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        setFrame(screen.frame,display:true); isReleasedWhenClosed=false
        level = .statusBar; collectionBehavior=[.fullScreenAuxiliary,.moveToActiveSpace]
        colorSpace = screen.colorSpace; contentView=surface
    }
}

final class MonitorFullscreenView:NSView {
    var onExit:(()->Void)?
    var onStep:((Bool)->Void)?
    private let pattern=MonitorPatternView()
    private let exit=SwissButton("Return To Setup",.secondary)
    private let previous=SwissButton("Previous",.secondary), next=SwissButton("Next",.secondary)
    private let hide=SwissButton("Hide Controls · Space",.secondary)
    private var hiddenControls=false
    private var step:MonitorCheck
    init(step:MonitorCheck) {
        self.step=step; super.init(frame:.zero); addSubview(pattern)
        for b in [exit,previous,next,hide] { addSubview(b); b.target=self }
        exit.action=#selector(close); previous.action=#selector(back); next.action=#selector(forward); hide.action=#selector(toggle)
        update(step:step)
    }
    required init?(coder:NSCoder) { fatalError() }
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    func update(step:MonitorCheck) {
        self.step=step; pattern.step=step; pattern.needsDisplay=true
        previous.isEnabled=step.rawValue>0; next.isEnabled=step.rawValue<6
        setAccessibilityLabel(step.title + ". " + step.instruction + " Escape returns to setup. Space hides or shows controls.")
        needsDisplay=true
    }
    @objc private func close() { onExit?() }
    @objc private func back() { onStep?(false) }
    @objc private func forward() { onStep?(true) }
    @objc private func toggle() { hiddenControls.toggle(); needsLayout=true; needsDisplay=true }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode { case 53:close(); case 49:toggle(); case 123:back(); case 124:forward(); default:super.keyDown(with:event) }
    }
    override func layout() {
        super.layout(); pattern.frame=NSRect(x:0,y:0,width:bounds.width,height:hiddenControls ? bounds.height : max(100,bounds.height-224))
        for b in [exit,previous,next,hide] { b.isHidden=hiddenControls }
        previous.frame=NSRect(x:24,y:bounds.height-56,width:previous.intrinsicContentSize.width,height:32)
        next.frame=NSRect(x:previous.frame.maxX+16,y:bounds.height-56,width:next.intrinsicContentSize.width,height:32)
        hide.frame=NSRect(x:next.frame.maxX+32,y:bounds.height-56,width:hide.intrinsicContentSize.width,height:32)
        exit.frame=NSRect(x:hide.frame.maxX+32,y:bounds.height-56,width:exit.intrinsicContentSize.width,height:32)
    }
    override func draw(_ dirtyRect:NSRect) {
        guard !hiddenControls else { return }; fill(bounds,Design.card)
        let y=bounds.height-224
        Design.attributed("\(step.rawValue+1) / 7 · " + step.title,.heading).draw(x:24,baseline:y+36)
        SettingsSheet.paragraph(step.instruction,x:24,firstBaseline:y+64,width:min(900,bounds.width-48),height:80)
        Design.attributed("Unmeasured · Space: hide controls · ← / →: change pattern · Esc: return",.caption,colour:Design.quiet).draw(x:24,baseline:bounds.height-80)
    }
}
