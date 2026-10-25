import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

private final class PaletteHaloButton: ClickCursorButton {
    override init(frame: NSRect) { super.init(frame: frame); isBordered = false; title = ""; setButtonType(.momentaryChange) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        for degree in 0..<180 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: centre, radius: 8, startAngle: CGFloat(degree * 2), endAngle: CGFloat(degree * 2 + 3))
            arc.lineWidth = 4
            NSColor(calibratedHue: CGFloat(degree) / 180, saturation: 0.9, brightness: isHighlighted ? 0.75 : 0.95, alpha: 1).setStroke()
            arc.stroke()
        }
        if window?.firstResponder === self {
            NSFocusRingPlacement.only.set(); NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
        }
    }
}

/// One square drawing box and centre for every header utility glyph.
enum HeaderUtilityIcon {
    static let size: CGFloat = 18
    private static var images: [String: NSImage] = [:]
    static func rect(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
    }
    static func draw(_ name: String, in bounds: NSRect, colour: NSColor = Design.ink) {
        let opaque=colour.withAlphaComponent(1)
        let key = name + (hexOf(opaque) ?? "")
        if let image = images[key] {
            image.draw(in: rect(in: bounds), from: .zero, operation: .sourceOver, fraction: colour.alphaComponent, respectFlipped: true, hints: nil)
            return
        }
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [opaque]))),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 72, pixelsHigh: 72,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        // SF Symbols include differing optical margins. Trim once, then cache;
        // all utility glyphs occupy the same visible square at every redraw.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        symbol.draw(in: NSRect(x: 0, y: 0, width: 72, height: 72))
        NSGraphicsContext.restoreGraphicsState()
        var minX = 72, minY = 72, maxX = -1, maxY = -1
        for y in 0..<72 { for x in 0..<72 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.04 {
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY,
              let pixels = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return }
        let image = NSImage(cgImage: pixels, size: NSSize(width: size, height: size))
        images[key] = image
        image.draw(in: rect(in: bounds), from: .zero, operation: .sourceOver, fraction: colour.alphaComponent, respectFlipped: true, hints: nil)
    }
}

private final class HeaderHelpButton: ClickCursorButton {
    private var hovered = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; title = ""; setButtonType(.momentaryChange)
        toolTip = "Help"; setAccessibilityLabel("Help")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted { fill(bounds, Design.rule.withAlphaComponent(0.25)) }
        HeaderUtilityIcon.draw("questionmark.circle", in: bounds)
    }
}

private final class HeaderNavigationButton:ClickCursorButton {
    var active=false {didSet{needsDisplay=true}}
    var symbol=""
    var run:(()->Void)?
    private var hovered=false
    static func label(_ title:String,active:Bool)->NSAttributedString {
        let value=NSMutableAttributedString(attributedString:Design.attributed(title,.lead,colour:Design.ink))
        value.addAttribute(.font,value:Design.font(Design.Text.lead.size,active ? .medium:.regular),range:NSRange(location:0,length:value.length));return value
    }
    var contentWidth:CGFloat {ceil(max(Self.label(title,active:false).size().width,Self.label(title,active:true).size().width))+26}
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;target=self;action=#selector(pressed)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func pressed(){run?()}
    override var isFlipped:Bool{true}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect){
        HeaderUtilityIcon.draw(symbol,in:NSRect(x:0,y:0,width:18,height:bounds.height))
        let baseline=bounds.midY+7
        Self.label(title,active:active).draw(x:26,baseline:baseline)
        if active || hovered || isHighlighted {fill(NSRect(x:26,y:baseline+6,width:bounds.width-26,height:1),active ? Design.ink:Design.quiet)}
    }
}

private final class HeaderToolsButton:ClickCursorButton {
    override var isFlipped:Bool{true}
    var active=false {didSet{needsDisplay=true}}
    private var hovered=false
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;title="";toolTip="More Tools";setAccessibilityLabel("More Tools")}
    required init?(coder:NSCoder){fatalError()}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect){
        HeaderUtilityIcon.draw("square.grid.2x2",in:bounds)
        if active || hovered || isHighlighted {fill(NSRect(x:8,y:bounds.height-3,width:bounds.width-16,height:1),Design.ink)}
    }
}

final class StudioHeader: ClickCursorView, Overlay, NSTextFieldDelegate {
    override var handCursorRects:[NSRect]{[copyRect,searchRect,settingsRect]+markRects+pickRects}

    let layoutControl=WorkspaceLayoutControl(frame:.zero)
    var overlayWindows: [NSWindow] { (dropped.map { [$0] } ?? []) + (searchPanel.map { [$0] } ?? []) }
    func dismissOverlay() { closeMenu(); hideSearch() }
    func containsOverlayEvent(_ event: NSEvent) -> Bool {
        if overlayWindows.contains(where: { $0 === event.window }) { return true }
        guard searchExpanded, event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return field.frame.insetBy(dx: -6, dy: -10).contains(point) || searchRect.contains(point)
    }
    var grid: (x: CGFloat, column: CGFloat) = (24, 96) { didSet { if grid != oldValue { needsLayout = true; needsDisplay = true } } }
    var live: Int? = 0 { didSet { needsLayout = true; needsDisplay = true } }
    private var settingsRect = NSRect.zero, searchRect = NSRect.zero
    struct SavedSearch: Codable { var query: String; var date: Date; var favourite: Bool }
    var searchStorageKey = "Studio.Searches"
    var savedSearches: [SavedSearch] {
        guard let data = UserDefaults.standard.data(forKey: searchStorageKey) else { return [] }
        return (try? JSONDecoder().decode([SavedSearch].self, from: data)) ?? []
    }
    struct SearchResult { let title: String; let detail: String; let select: () -> Void }
    var searchResults: ((String) -> [SearchResult])?
    private var visibleResults: [SearchResult] = []
    var onSearchCommitted: (() -> Void)?
    private var searchPanel: NSPanel?
    private var searchExpanded = false
    private var searchTimer: Timer?
    private var searchProgress: CGFloat = 0
    private var commitTimer: Timer?
    private var dropdownQueries: [String] = []

    var onTab: ((Int) -> Void)?
    var onPaletteWheel: (() -> Void)?
    var proofingControl:NSView? {didSet{if let proofingControl {addSubview(proofingControl)};needsLayout=true}}
    private let paletteHalo = PaletteHaloButton(frame: .zero)
    /// The expanded Rail1 edge anchors primary navigation.
    var railEdge: CGFloat = 248 { didSet { if railEdge != oldValue { needsLayout = true; needsDisplay = true } } }
    private var navigationStart: CGFloat { max(railEdge,Design.App.railWidth)+Logo.headerSidePadding(over:Design.App.railWidth) }
    private var copyRect = NSRect.zero
    var onPick: (() -> Void)?
    var onSample: (() -> Void)?
    private var pickRects: [NSRect] = []
    /// The clock: the history slides in or out; it is drawn in ink while the history is in.
    var onHistory: (() -> Void)?
    var historyOpen = false { didSet { needsDisplay = true } }
    /// The three window marks at the top of column 1, where macOS would put its buttons: close, minimise, and arrange, which drops its menu.
    private var markRects: [NSRect] = []
    private var markHover: Int?
    private var dropped: SwissDropdown.MenuPanel?
    var onSettings: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onAcross: ((Int) -> Void)?
    var search: String { field.stringValue }
    func clearFilter() { hideSearch() }
    private let tabs = ["Library", "Palettes", "Lab", "PrePress", "Contrast", "Projects", "Appbridge", "Import", "Designer"]
    static let secondaryNavigation:[(index:Int,title:String)]=[(2,"Lab"),(4,"Contrast"),(5,"Projects"),(3,"PrePress"),(6,"Appbridge")]
    private let primaryButtons=(0..<4).map{_ in HeaderNavigationButton(frame:.zero)}
    private let primaryIndices=[0,1,8,7]
    private let toolsButton=HeaderToolsButton(frame:.zero)
    private let field = NSTextField(string: "")
    static let baseline: CGFloat = 40
    private var compactHeader:Bool { bounds.width < 1720 }
    private var headerCentre:CGFloat { compactHeader ? 28:bounds.midY }
    private var headerBaseline:CGFloat { let font=Design.Text.body.font();return headerCentre+(font.ascender+font.descender)/2 }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Design.Text.body.font()
        field.textColor = Design.ink
        field.placeholderAttributedString = Design.attributed("Search", .body, colour: Design.soft)
        field.target = self
        field.action = #selector(searched)
        field.delegate = self
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        field.isHidden = true
        addSubview(field)
        for (i,button) in primaryButtons.enumerated(){
            button.title=tabs[primaryIndices[i]];button.symbol=["books.vertical","square.stack","pencil.and.outline","square.and.arrow.down"][i]
            button.setAccessibilityLabel(button.title);button.toolTip=button.title
            button.run={ [weak self] in self?.onTab?(self?.primaryIndices[i] ?? i) };addSubview(button)
        }
        toolsButton.target=self;toolsButton.action=#selector(openTools);addSubview(toolsButton)
        paletteHalo.target = self; paletteHalo.action = #selector(openPaletteWheel)
        paletteHalo.setAccessibilityLabel("Open palette wheel")
        paletteHalo.toolTip = "Palette wheel · Tab"
        addSubview(paletteHalo)
        addSubview(layoutControl)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openPaletteWheel() { onPaletteWheel?() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let g = Design.App.gutter
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        var x=navigationStart
        for (i,button) in primaryButtons.enumerated(){
            button.active=live == primaryIndices[i]
            button.frame=NSRect(x:x,y:headerCentre-18,width:button.contentWidth,height:36)
            x=button.frame.maxX+28
        }
        toolsButton.active=live.map{$0 > 1 && $0 != 7 && $0 != 8} ?? false
        let font=Design.Text.body.font(),textCentre=headerBaseline-(font.ascender+font.descender)/2
        paletteHalo.frame=NSRect(x:x-6,y:textCentre-14,width:28,height:28)
        toolsButton.frame=NSRect(x:bounds.width-Design.App.margin-97,y:textCentre-18,width:36,height:36)
        let proofRight=bounds.width-Design.App.railWidth
        let available=max(0,proofRight-max(paletteHalo.frame.maxX+24,bounds.midX+72))
        let layoutWidth=min(280,max(136,available*0.44)),proofWidth=min(360,max(0,available-layoutWidth-20))
        layoutControl.frame=NSRect(x:proofRight-layoutWidth,y:textCentre-14,width:layoutWidth,height:28)
        proofingControl?.frame=NSRect(x:layoutControl.frame.minX-20-proofWidth,y:textCentre-14,width:proofWidth,height:28)
        if compactHeader {
            layoutControl.frame=NSRect(x:navigationStart,y:58,width:280,height:28)
            proofingControl?.frame=NSRect(x:layoutControl.frame.maxX+100,y:58,width:max(0,bounds.width-layoutControl.frame.maxX-124),height:28)
        }
        layoutControl.isHidden=live.map{!([0,1].contains($0))} ?? true
        // Law 1: the field's text on the baseline.
        let right = bounds.width - Design.App.margin
        let end = compactHeader ? right:right - 148
        let start = compactHeader ? layoutControl.frame.maxX+100:max(col(8), (proofingControl?.frame.maxX ?? paletteHalo.frame.maxX) + 24)
        let width = max(80, end-start) * searchProgress
        field.frame = NSRect(x: end - width, y: (compactHeader ? 72:textCentre) - 10, width: width, height: 20)
        positionSearchPanel()
    }

    override func draw(_ dirtyRect: NSRect) {
        hairline(x:0, y:bounds.height - 1, width:bounds.width, Design.rule)
        let g = Design.App.gutter, b = headerBaseline
        func col(_ c: Int) -> CGFloat { grid.x + CGFloat(c - 1) * (grid.column + g) }
        func span(_ n: Int) -> CGFloat { CGFloat(n) * grid.column + CGFloat(n - 1) * g }
        Logo.drawHeader(centredOver:Design.App.railWidth,centreY:bounds.midY)
        let font = Design.Text.body.font()
        let centreY = b - (font.ascender + font.descender) / 2
        // Centre the picker pair in the full header, using the utility icon renderer.
        pickRects = []
        for (k, name) in ["eyedropper", "rectangle.dashed"].enumerated() {
            let rect = NSRect(x:compactHeader ? layoutControl.frame.maxX+24+CGFloat(k)*36:bounds.midX-30+CGFloat(k)*36,y:(compactHeader ? 72:centreY)-12,width:24,height:24)
            HeaderUtilityIcon.draw(name,in:rect)
            pickRects.append(rect.insetBy(dx:-6,dy:-6))
        }
        let right = bounds.width - Design.App.margin + 5
        searchRect = NSRect(x: right - 132, y: centreY - 12, width: 24, height: 24)
        settingsRect = NSRect(x: right - 24, y: centreY - 12, width: 24, height: 24)
        copyRect = .zero
        if !searchExpanded {
            let label = Design.attributed("Copy " + Prefs.copyFormat.label + " ▾", .body, colour: Design.quiet)
            let x = searchRect.minX - Design.App.gutter - label.size().width
            label.draw(x: x, baseline: b)
            copyRect = NSRect(x: x - 4, y: centreY - 16, width: label.size().width + 8, height: 32)
        }

        for (name, rect) in [("magnifyingglass", searchRect), ("gearshape", settingsRect)] {
            HeaderUtilityIcon.draw(name, in: rect)
        }
        if searchProgress > 0 { hairline(x: field.frame.minX, y: (compactHeader ? 76:b) + 7, width: field.frame.width, Design.rule) }
        markRects = []
        let historyRect = NSRect(x:right-60,y:centreY-12,width:24,height:24)
        HeaderUtilityIcon.draw("clock", in:historyRect)
        markRects.append(historyRect.insetBy(dx:-6,dy:-6))
    }

    @objc private func openTools(){
        guard let win=window else{return}
        if dropped != nil {closeMenu();return}
        if searchExpanded {hideSearch()}
        let entries=Self.secondaryNavigation
        let panel=SwissDropdown.MenuPanel(items:entries.map(\.title),chosen:entries.first{$0.index == live}?.title ?? "",width:220){ [weak self] i in
            guard let self,entries.indices.contains(i) else{return}
            self.closeMenu();self.onTab?(entries[i].index)
        }
        let anchor=win.convertToScreen(toolsButton.convert(toolsButton.bounds,to:nil))
        panel.place(below:NSPoint(x:anchor.maxX-220,y:anchor.minY-4))
        win.addChildWindow(panel,ordered:.above);dropped=panel;Overlays.opened(self)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let over = markRects.firstIndex { $0.contains(p) }
        if over != markHover { markHover = over; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { if markHover != nil { markHover = nil; needsDisplay = true } }

    private func closeMenu() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if copyRect.contains(p), let win = window {
            if dropped != nil { closeMenu(); return }
            let formats = StudioPage.models
            let panel = SwissDropdown.MenuPanel(items: formats.map { $0.label }, chosen: Prefs.copyFormat.label, width: 200) { [weak self] index in
                Prefs.copyFormat = formats[index]
                self?.closeMenu(); self?.needsDisplay = true
            }
            let anchor = win.convertToScreen(convert(copyRect, to: nil))
            panel.place(below: NSPoint(x: anchor.minX, y: anchor.minY - 4))
            win.addChildWindow(panel, ordered: .above)
            dropped = panel; Overlays.opened(self)
            return
        }
        if searchRect.contains(p) { if searchExpanded { hideSearch() } else { showSearch(focus: true) }; return }
        if markRects.contains(where: { $0.contains(p) }) { onHistory?(); return }
        if let i = pickRects.firstIndex(where: { $0.contains(p) }) { if i == 0 { onPick?() } else { onSample?() }; return }
        if settingsRect.contains(p) { onSettings?(); return }
        // Window movement belongs to the native macOS title bar.
    }
    @objc private func searched() { if !visibleResults.isEmpty { selectResult(0) } }
    func controlTextDidChange(_ obj: Notification) { showSearchDropdown() }
    private func selectResult(_ index: Int) {
        guard visibleResults.indices.contains(index) else { return }
        let result = visibleResults[index]
        commitSearch(); hideSearch(); result.select()
    }
    private func commitSearch() {
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var entries = savedSearches
        let favourite = entries.first { $0.query == query }?.favourite ?? false
        entries.removeAll { $0.query == query }
        entries.insert(SavedSearch(query: query, date: Date(), favourite: favourite), at: 0)
        saveSearches(Array(entries.prefix(200)))
        onSearchCommitted?()
    }
    private func saveSearches(_ entries: [SavedSearch]) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: searchStorageKey) }
    }
    private func showSearch(focus: Bool) {
        if !searchExpanded { searchExpanded = true; field.isHidden = false; animateSearch(); showSearchDropdown(); Overlays.opened(self) }
        if focus { window?.makeFirstResponder(field) }
    }
    private func hideSearch() {
        commitTimer?.invalidate()
        let hadQuery = !field.stringValue.isEmpty
        field.stringValue = ""; visibleResults = []
        searchExpanded = false; animateSearch(); Overlays.closed(self)
        if hadQuery { onSearch?("") }
        searchPanel?.parent?.removeChildWindow(searchPanel!); searchPanel?.orderOut(nil); searchPanel = nil
    }
    private func animateSearch() {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let target: CGFloat = self.searchExpanded ? 1 : 0
            self.searchProgress += (target - self.searchProgress) * 0.24
            if abs(self.searchProgress - target) < 0.002 { self.searchProgress = target; timer.invalidate(); self.field.isHidden = target == 0 }
            self.needsLayout = true; self.needsDisplay = true
        }
        RunLoop.main.add(searchTimer!, forMode: .common)
    }
    private func positionSearchPanel() {
        guard let panel = searchPanel, let win = window else { return }
        let point = win.convertToScreen(convert(NSRect(x: field.frame.maxX - panel.frame.width, y: bounds.maxY + 1, width: 0, height: 0), to: nil)).origin
        panel.setFrameOrigin(NSPoint(x: point.x, y: point.y - panel.frame.height))
    }
    private func showSearchDropdown() {
        guard searchExpanded, let win = window else { return }
        searchPanel?.parent?.removeChildWindow(searchPanel!); searchPanel?.orderOut(nil); searchPanel = nil
        let end = bounds.width - Design.App.margin - 220
        let gridStart = grid.x + 7 * (grid.column + Design.App.gutter)
        let width = max(240, end - max(gridStart, paletteHalo.frame.maxX + 24))
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let list: NSView
        if !query.isEmpty {
            visibleResults = searchResults?(query) ?? []
            let results = SearchResultList(results: visibleResults, width: width)
            results.onSelect = { [weak self] in self?.selectResult($0) }
            list = results
        } else {
            visibleResults = []
            let entries = savedSearches
            guard !entries.isEmpty else { return }
            let ordered = entries.filter { $0.favourite } + entries.filter { !$0.favourite }
            dropdownQueries = ordered.map { $0.query }
            let history = SearchHistoryList(entries: ordered, width: width)
            history.onSelect = { [weak self] i in
                guard let self, self.dropdownQueries.indices.contains(i) else { return }
                self.field.stringValue = self.dropdownQueries[i]; self.showSearchDropdown(); self.window?.makeFirstResponder(self.field)
            }
            history.onStar = { [weak self] i in
                guard let self, self.dropdownQueries.indices.contains(i) else { return }
                var entries = self.savedSearches
                if let n = entries.firstIndex(where: { $0.query == self.dropdownQueries[i] }) { entries[n].favourite.toggle() }
                self.saveSearches(entries); self.showSearchDropdown()
            }
            list = history
        }
        let height = list.frame.height
        let pageHeight = (win.contentView?.bounds.height ?? 600) - Design.App.headerHeight(for:bounds.width) - Design.App.footer
        let scroll = FittedScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(height, pageHeight * 0.5)))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = true; scroll.backgroundColor = Design.card; scroll.documentView = list
        let panel = NSPanel(contentRect: scroll.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = scroll; panel.hasShadow = true; panel.backgroundColor = Design.card
        searchPanel = panel; positionSearchPanel(); win.addChildWindow(panel, ordered: .above); Overlays.opened(self)
        scroll.contentView.scroll(to: .zero)
    }
    @objc private func starSearch(_ sender: NSButton) {
        guard dropdownQueries.indices.contains(sender.tag) else { return }
        var entries = savedSearches
        if let i = entries.firstIndex(where: { $0.query == dropdownQueries[sender.tag] }) { entries[i].favourite.toggle() }
        saveSearches(entries); showSearchDropdown()
    }
    @objc private func repeatSearch(_ sender: NSButton) {
        guard dropdownQueries.indices.contains(sender.tag) else { return }
        field.stringValue = dropdownQueries[sender.tag]; showSearchDropdown(); window?.makeFirstResponder(field)
    }
    /// Escape in the search clears it and lets go, so the page is whole again and the quick keys work.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard sel == #selector(NSResponder.cancelOperation(_:)) else { return false }
        field.stringValue = ""
        onSearch?(""); hideSearch()
        window?.makeFirstResponder(window?.contentView)
        return true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: field, queue: .main) { [weak self] _ in
            (self?.field.currentEditor() as? NSTextView)?.insertionPointColor = Design.ink
            self?.needsDisplay = true
        }
        NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: field, queue: .main) { [weak self] _ in self?.needsDisplay = true }
    }
}

private final class SearchResultList: NSView {
    var onSelect: ((Int) -> Void)?
    private let empty: Bool
    override var isFlipped: Bool { true }
    init(results: [StudioHeader.SearchResult], width: CGFloat) {
        empty = results.isEmpty
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 56 + CGFloat(max(1, results.count)) * 56))
        for (i, result) in results.enumerated() {
            let button = ClickCursorButton(frame: NSRect(x: 24, y: 48 + CGFloat(i) * 56, width: width - 48, height: 48))
            button.isBordered = false; button.alignment = .left
            let title = NSMutableAttributedString(attributedString: Design.attributed(result.title, .body))
            title.append(Design.attributed("\n" + result.detail, .caption, colour: Design.quiet))
            button.attributedTitle = title; button.toolTip = result.title + " / " + result.detail
            button.setAccessibilityLabel(result.title + ", " + result.detail)
            button.target = self; button.action = #selector(selected(_:)); button.tag = i
            addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        Design.attributed("Results", .heading).draw(x: 24, baseline: 36)
        if empty { Design.attributed("No results", .body, colour: Design.quiet).draw(x: 24, baseline: 73) }
    }
    @objc private func selected(_ sender: NSButton) { onSelect?(sender.tag) }
}

private final class SearchHistoryList: NSView {
    var onSelect: ((Int) -> Void)?
    var onStar: ((Int) -> Void)?
    private var headings: [(String, CGFloat)] = []
    private var dividers: [CGFloat] = []
    override var isFlipped: Bool { true }
    init(entries: [StudioHeader.SavedSearch], width: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Design.card.cgColor
        var y = AreaHeader.headingBaseline - 16
        for (i, entry) in entries.enumerated() {
            if i == 0 || entries[i - 1].favourite != entry.favourite {
                if i > 0 { y += 12; dividers.append(y); y += 16 }
                headings.append((entry.favourite ? "Favourites" : "Recent Searches", y + 16)); y += 40
            }
            let star = ClickCursorButton(frame: NSRect(x: 20, y: y, width: 24, height: 32))
            star.isBordered = false; star.attributedTitle = Design.attributed(entry.favourite ? "★" : "☆", .body, colour: Design.ink)
            star.target = self; star.action = #selector(starred(_:)); star.tag = i; star.setAccessibilityLabel("Favourite " + entry.query)
            addSubview(star)
            let query = ClickCursorButton(frame: NSRect(x: 56, y: y, width: max(24, width - 80), height: 32))
            query.isBordered = false; query.alignment = .left; query.attributedTitle = Design.attributed(entry.query, .body, colour: Design.ink)
            query.target = self; query.action = #selector(selected(_:)); query.tag = i
            addSubview(query); y += 32
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y + 16)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        for (title, baseline) in headings { Design.attributed(title, .heading, colour: Design.ink).draw(x: 24, baseline: baseline) }
        for y in dividers { Design.rule.setFill(); NSRect(x: 24, y: y, width: bounds.width - 48, height: 1).fill() }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        for view in subviews { addCursorRect(view.frame, cursor: .pointingHand) }
    }
    @objc private func selected(_ sender: NSButton) { onSelect?(sender.tag) }
    @objc private func starred(_ sender: NSButton) { onStar?(sender.tag) }
}

/// The mini slider: a hairline track and an 8 square knob. Here it sets how many tiles sit across the page.
