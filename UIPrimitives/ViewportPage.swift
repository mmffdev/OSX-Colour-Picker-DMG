import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

struct AssetPageProps {
    enum Renderer { case palette, image }
    enum Pagination { case continuous, imageByImage }
    enum Menu: Hashable { case colourFormat, sort, imageView }
    enum Filter: Hashable { case paletteReview, metadata }
    var renderer: Renderer = .palette
    var pagination: Pagination = .continuous
    var menus: Set<Menu> = [.colourFormat, .sort]
    var filters: Set<Filter> = [.metadata, .paletteReview]
    static let photographs = AssetPageProps(renderer: .image, pagination: .imageByImage, menus: [.sort, .imageView], filters: [.metadata])
}

/// The page: 34 clear, then a Split header on its own six columns, a hairline, 22 clear, and the grid of tiles.
final class StudioPage: ClickCursorView, Overlay {
    override var handCursorRects:[NSRect]{
        var regions:[NSRect]=[]
        if !compactWorkspace {regions.append(AreaHeader.arrowRect(in:bounds,insetRight:insetRight).insetBy(dx:-8,dy:-8));if showsFormat && !slider.isHidden{regions.append(formatRect)}}
        if !paneHeaderControls,onRenamePalette != nil,!renamingTitle {
            let trailing:CGFloat=paletteSwatchCount.map{Design.attributed("Swatch Count \($0)",.body).size().width+24} ?? 0
            let width=min(Design.attributed(title,.heading).size().width,max(0,bounds.width-inset-insetRight-24-trailing))
            regions.append(NSRect(x:inset,y:AreaHeader.headingBaseline-Design.Text.heading.font().ascender,width:width,height:28))
        }
        return regions
    }

    func captureLayoutView()->WorkspaceLayoutTemplate.Page {
        var state=WorkspaceLayoutTemplate.Page();state.assetOrder=assetOrder.rawValue;state.columns=grid.across;state.list=grid.listView;state.format=format.rawValue;state.selectedColour=grid.chosenHex;state.metadataOpen=metadataFilterExpanded;state.metadata=metadataFilterPanel.layoutColumns
        state.scrollX=scroll.contentView.bounds.minX;state.scrollY=scroll.contentView.bounds.minY;state.delta=grid.deltaEnabled;return state
    }
    func restoreLayoutView(_ state:WorkspaceLayoutTemplate.Page){
        assetOrder=state.assetOrder.flatMap(GridAssetOrder.init(rawValue:)) ?? .name
        grid.across=max(1,min(30,state.columns));grid.listView=state.list;format=ColourFormat(rawValue:state.format) ?? .hex;grid.chosenHex=state.selectedColour
        metadataFilterPanel.layoutColumns=state.metadata;metadataFilterExpanded=state.metadataOpen;metadataFilterPanel.isHidden = !state.metadataOpen;applyDeltaState(Prefs.deltaWarningsEnabled)
        needsLayout=true;layoutSubtreeIfNeeded()
        let extent=scroll.documentView?.bounds.size ?? .zero
        let y=max(0,min(state.scrollY,extent.height-scroll.contentSize.height)),x=max(0,min(state.scrollX,extent.width-scroll.contentSize.width))
        scroll.contentView.scroll(to:NSPoint(x:x,y:y));scroll.reflectScrolledClipView(scroll.contentView)
    }
    var compactWorkspace = false
    private let subjectTabHeader=WorkspacePageTabHeader(frame:.zero)
    var paneHeaderControls=false
    var colourPickerHeader:(instruction:String,selection:String)? {didSet{needsDisplay=true}}
    weak var workspaceToolbar: WorkspaceViewportBar?
    weak var workspaceActionbar: WorkspaceViewportBar?
    let paletteActions=PalettePageControls(frame:.zero)
    let paletteFilters=PaletteFilterControls(frame:.zero)
    var assetProps=AssetPageProps() {didSet{
        showsFormat=assetProps.menus.contains(.colourFormat)
        let image=assetProps.renderer == .image
        if grid.imageLibrary != image {grid.imageLibrary=image}
        needsLayout=true
    }}
    var showsPaletteFilters=false {didSet{if oldValue != showsPaletteFilters{window?.contentView?.needsLayout=true}}}
    var paletteSwatchCount:Int? {didSet{needsLayout=true;needsDisplay=true}}
    var imageIntakeMode=false {didSet{subjectTabHeader.isHidden = !imageIntakeMode;grid.imageIntake=imageIntakeMode;if imageIntakeMode{grid.listView=false};needsLayout=true;needsDisplay=true}}
    private var intakeGridColumns=6
    private var metadataFilterExpanded=false
    private let metadataFilterPanel=MetadataFilterPanel(frame:.zero)
    private var basePageItems:[TileGrid.Item]=[]
    private var filteredPageItems:[TileGrid.Item]=[]
    private var sourceGridSections:[TileGrid.Section]=[]
    var assetOrder=GridAssetOrder.name { didSet { applyAssetOrder() } }
    @discardableResult private func applyAssetOrder(reuseGridIfSame:Bool=false)->Bool {
        var ordered:[TileGrid.Item]=[]
        var visibleSections:[TileGrid.Section]=[]
        if sourceGridSections.isEmpty {
            ordered=assetProps.renderer == .image ? filteredPageItems:assetOrder.sorted(filteredPageItems)
        } else {
            for (sectionIndex,section) in sourceGridSections.enumerated() {
                let members=filteredPageItems.filter{$0.sectionIndex == sectionIndex}
                guard !members.isEmpty else{continue}
                visibleSections.append(TileGrid.Section(title:section.title,start:ordered.count))
                ordered += assetOrder.sorted(members)
            }
        }
        let reused=reuseGridIfSame && grid.hasSameIdentities(as:ordered)
        if !reused{grid.items=ordered}
        grid.sections=visibleSections
        workspaceActionbar?.setAssetOrder(assetOrder)
        needsLayout=true
        return reused
    }

    var metadataFilterIsExpanded:Bool { metadataFilterExpanded }
    func toggleMetadataFilter(){metadataFilterExpanded.toggle();metadataFilterPanel.isHidden = !metadataFilterExpanded;if metadataFilterExpanded{metadataFilterPanel.refreshIfNeeded()};needsLayout=true}
    func configureMetadataFilters(store:MetadataFilterStore?,catalogueID:UUID){metadataFilterPanel.configure(records:basePageItems,store:store,catalogueID:catalogueID)}
    var importImageControls=true
    func configureImageIntake(_ active:Bool,kind:String,linking:Bool,gridColumns:Int,fullView:Bool){
        imageIntakeMode=active;intakeGridColumns=gridColumns;grid.imageFullView=active && fullView
        grid.showsHalo = !active
        grid.importPaletteCards=active && kind == "Palettes"
        subjectTabHeader.symbol = kind == "Palettes" || kind == "ASE" ? "swatchpalette" : "photo.on.rectangle"
        subjectTabHeader.stripeColour = Design.houseYellow
    }
    var layoutFrozen = false
    /// Palette content heading shares the first rail-row baseline.
    var paletteCount: String? { didSet { needsLayout = true; needsDisplay = true } }
    var inset: CGFloat = 8 { didSet { if inset != oldValue { needsLayout = true } } }
    var insetRight: CGFloat = 8 { didSet { if insetRight != oldValue { needsLayout = true } } }
    private func viewingNeedsRow(for width:CGFloat)->Bool{showsDeltaTools && !imageIntakeMode && width < (showsPaletteFilters ? 620:max(460,paletteActions.controlWidth+viewingControls.controlWidth+64))}
    private func needsFilterRow(for width:CGFloat)->Bool{section == .tiles && !imageIntakeMode && paletteSwatchCount == nil && assetProps.filters.contains(.metadata) && width < 1140}
    func actionbarHeight(for width:CGFloat)->CGFloat{
        if imageIntakeMode{return WorkspacePanel.headerHeight}
        let base=showsPaletteFilters ? PaletteFilterControls.actionbarHeight(for:width):WorkspaceViewportBar.actionbarHeight
        return base+(viewingNeedsRow(for:width) ? 40:0)+(needsFilterRow(for:width) ? 40:0)
    }
    let importPanel=WorkspaceImportPanel(frame:.zero)
    private var importDestination:String?
    func configureImportPanel(_ destination:String?){importDestination=destination;importPanel.destination=destination ?? "Photography";importPanel.isHidden=destination == nil;grid.suppressesEmptyMessage=destination != nil;needsLayout=true}
    private let viewingControls=PaletteViewingControls(frame:.zero)
    private let profileSelector=PrintProfileSelector(compact:true)
    var onDeltaToggle:(()->Void)?
    var showsDeltaTools=false {didSet{viewingControls.isHidden = !showsDeltaTools;profileSelector.isHidden = !showsDeltaTools;needsLayout=true;needsDisplay=true;if oldValue != showsDeltaTools{window?.contentView?.needsLayout=true}}}
    func applyDeltaState(_ enabled:Bool){viewingControls.showsIlluminant=paletteSwatchCount != nil;grid.showsIlluminant=paletteSwatchCount != nil;grid.deltaEnabled=Prefs.deltaWarningsEnabled;grid.needsDisplay=true;grid.setAccessibilityLabel(grid.showsIlluminant ? "Palette And Swatch Comparison. "+PaletteViewing.accessibilitySummary:"Palette Output Proof "+(Prefs.deltaWarningsEnabled ? "On":"Off"));needsLayout=true;needsDisplay=true}
    func refreshPrintProfiles(){profileSelector.reload();needsDisplay=true}
    @objc private func toggleDelta(){onDeltaToggle?()}
    let grid = TileGrid()
    let settings = CatalogueSettings()
    let schema = SchemaSettings()
    private let scroll = FittedScrollView()
    /// Visible palette canvas, excluding its header, actionbar and footer, in page coordinates.
    var previewViewport: NSRect { convert(scroll.contentView.bounds, from: scroll.contentView) }
    /// The settings scroll as one piece, the open accordion and all, when they outgrow the page.
    private let settingsScroll = FittedScrollView(), schemaScroll = FittedScrollView()
    /// The way to make a member, under the header when the page lists members.
    private let newButton = SwissButton("New Project", .primary)
    var onNew: (() -> Void)?
    /// Export beside New, where a page shows a level that can go out as one file.
    private let exportButton = SwissButton("Export\u{2026}", .secondary)
    var onExport: (() -> Void)?
    /// How many tiles sit across: the slider in the page's header, right-aligned before the arrow and centred on it, shown with the tiles.
    private let slider = MiniSlider()
    var onAcross: ((Int) -> Void)?
    /// The colour model the tiles' captions are in, chosen on the menu before the slider.
    var format: ColourFormat = .hex {didSet{needsDisplay=true}}
    private var valueFormatHelp:String {format == .cmyk ? "Colour Values · CMYK · "+PrintCondition.name():"Master Colour Values · "+Self.valueFormatTitle(format)}
    static func valueFormatTitle(_ format:ColourFormat)->String {
        switch format {
        case .cmyk:return "CMYK · "+(PrintCondition.current.press ?? PressProfiles.generic)
        case .lab:return "Lab (D50)"
        case .xyz:return "XYZ (D50)"
        case .linear:return "Linear RGB (sRGB)"
        case .rgb:return "RGB (sRGB)"
        case .float:return "Float RGB (sRGB)"
        default:return format.label
        }
    }
    var onFormat: (() -> Void)?
    var showsFormat = true
    private var formatRect = NSRect.zero
    private var dropped: SwissDropdown.MenuPanel?
    static let models: [ColourFormat] = [.hex, .rgb, .hsl, .hsv, .cmyk, .p3, .adobeRGB, .rec2020, .lab, .lch, .luv, .oklch, .oklab, .xyz, .float, .linear]
    var overlayWindows: [NSWindow] { dropped.map { [$0] } ?? [] }
    func dismissOverlay() { closeFormats() }
    private func closeFormats() {
        if let m = dropped { m.parent?.removeChildWindow(m); m.orderOut(nil) }
        dropped = nil
        Overlays.closed(self)
    }
    @objc private func openFormats() {
        guard let win = window else { return }
        closeFormats()
        let items = Self.models.map { Self.valueFormatTitle($0) }
        let panel = SwissDropdown.MenuPanel(items: items, chosen: Self.valueFormatTitle(format), width: 320) { [weak self] i in
            guard let self = self else { return }
            self.closeFormats()
            self.format = Self.models[i]
            self.onFormat?()
        }
        let anchor = convert(formatRect,to:nil)
        let s = win.convertToScreen(anchor)
        panel.place(anchoredTo:NSRect(x:s.maxX-160,y:s.minY,width:160,height:s.height))
        win.addChildWindow(panel, ordered: .above)
        dropped = panel
        Overlays.opened(self)
    }
    var acceptsPaletteDrop = false
    var onPaletteDrop: ((UUID) -> Bool)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsPaletteDrop && PaletteDrag.palette(on: sender.draggingPasteboard) != nil ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard acceptsPaletteDrop, let id = PaletteDrag.palette(on: sender.draggingPasteboard) else { return false }
        return onPaletteDrop?(id) ?? false
    }
    enum Section: Hashable { case tiles, welcome, catalogues, schema, shortcuts, halo, sounds, general, colourManagement(Int), appleMenubar, sharingSettings, qrImport, help, librarySettings, tags, lab, prepress, contrast, share, appbridge }
    var settingsDestination: StudioFrame.Place? { didSet { needsLayout = true; needsDisplay = true } }
    var onSettingsTab: ((StudioFrame.Place) -> Void)?
    private var navigationTabs: [(String, StudioFrame.Place)] { settingsDestination.flatMap { SettingsNavigation.group(for: $0)?.tabs } ?? [] }
    var journey:CatalogueJourneyView?
    var onboardingDismissed=false
    private var section = Section.tiles
    private let sectionTabs = NSScrollView()
    private let tabBody = NSView()
    private var tabButtons: [NSButton] = []
    private var tabSignature = ""
    private var tabObserver: NSObjectProtocol?
    private var anchoredScroll: NSScrollView? {
        section == .catalogues ? settingsScroll : section == .schema ? schemaScroll : extras[section]?.scroll
    }
    private var anchors: [(String,CGFloat)] {
        if section == .catalogues { return settings.sectionAnchors }
        if section == .schema { return schema.sectionAnchors }
        return extras[section]?.view.sectionAnchors ?? []
    }
    private func updateTabs() {
        let items = navigationTabs.isEmpty ? anchors : navigationTabs.map { ($0.0, CGFloat(0)) }
        sectionTabs.isHidden = items.isEmpty
        let signature = items.map { $0.0 }.joined(separator:"|")
        if signature != tabSignature {
            tabSignature = signature; tabButtons.forEach { $0.removeFromSuperview() }; tabButtons = []
            var x: CGFloat = 0
            for (i,item) in items.enumerated() {
                let b = SectionAnchorButton(title:item.0,target:self,action:#selector(jumpSection(_:)))
                b.tag=i; b.isBordered=false; b.alignment = .left; b.toolTip="Go to " + item.0
                let width = Design.attributed(item.0,.body).size().width + 44
                b.frame=NSRect(x:x,y:0,width:width,height:32); x += width
                tabBody.addSubview(b); tabButtons.append(b)
            }
            tabBody.frame=NSRect(x:0,y:0,width:x,height:32)
        }
        sectionTabs.frame=NSRect(x:inset,y:AreaHeader.labelBaseline-17,width:max(0,bounds.width-inset-insetRight),height:32)
        updateActiveTab()
        if let selected = navigationTabs.firstIndex(where: { $0.1 == settingsDestination }), tabButtons.indices.contains(selected) {
            tabBody.scrollToVisible(tabButtons[selected].frame)
        }
    }
    private func updateActiveTab() {
        guard let scroll = anchoredScroll else { return }
        let y = scroll.contentView.bounds.minY
        let items = navigationTabs.isEmpty ? anchors : navigationTabs.map { ($0.0, CGFloat(0)) }
        let active = navigationTabs.isEmpty ? (anchors.lastIndex { $0.1 <= y+1 } ?? 0) : (navigationTabs.firstIndex { $0.1 == settingsDestination } ?? 0)
        for (i,b) in tabButtons.enumerated() where items.indices.contains(i) {
            b.attributedTitle=Design.attributed(items[i].0,i == active ? .bodyStrong : .body,colour:i == active ? Design.ink : Design.quiet)
            (b as? SectionAnchorButton)?.active = i == active
            b.state = i == active ? .on : .off
            b.needsDisplay=true
        }
    }
    @objc private func jumpSection(_ sender: NSButton) {
        if navigationTabs.indices.contains(sender.tag) { onSettingsTab?(navigationTabs[sender.tag].1); return }
        guard let scroll = anchoredScroll, anchors.indices.contains(sender.tag) else { return }
        layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to:NSPoint(x:0,y:anchors[sender.tag].1))
        scroll.reflectScrolledClipView(scroll.contentView); updateActiveTab()
    }
    deinit { if let tabObserver { NotificationCenter.default.removeObserver(tabObserver) } }
    /// The sections beyond the tiles, the catalogues and the schema, each in a scroll of its own, laid out like the catalogues.
    private var extras: [Section: (view: PageSection, scroll: NSScrollView)] = [:]
    func add(_ view: PageSection, as s: Section) {
        let scroll = FittedScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = view
        scroll.isHidden = true
        addSubview(scroll)
        view.onResize = { [weak self] in self?.needsLayout = true }
        extras[s] = (view, scroll)
    }
    /// Taking the whole width: the arrow turns to "close", and a press on it gives the rails back.
    var expanded = false { didSet { needsDisplay = true } }
    var onArrow: (() -> Void)?
    var onRenamePalette:((String)->Void)?
    private var renamingTitle=false
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let trailingWidth:CGFloat=paneHeaderControls ? 144:(paletteSwatchCount.map{Design.attributed("Swatch Count \($0)",.body).size().width+24} ?? 0)
        let availableTitleWidth=max(0,bounds.width-inset-insetRight-24-trailingWidth)
        let titleWidth=min(Design.attributed(title,.heading).size().width,availableTitleWidth)
        let titleRect=NSRect(x:inset,y:AreaHeader.headingBaseline-Design.Text.heading.font().ascender,width:titleWidth,height:28)
        if event.clickCount == 2,!paneHeaderControls,onRenamePalette != nil,titleRect.contains(p),!renamingTitle {
            renamingTitle=true
            InlineName.edit(title,style:.heading,in:self,x:inset,baseline:AreaHeader.headingBaseline,width:min(availableTitleWidth,max(120,titleWidth)),at:p){ [weak self] name in
                self?.renamingTitle=false;self?.needsDisplay=true
                if let name {self?.onRenamePalette?(name)}
            };needsDisplay=true;return
        }
        if !compactWorkspace, AreaHeader.arrowRect(in: bounds, insetRight: insetRight).insetBy(dx: -8, dy: -8).contains(p) { onArrow?(); return }
        if !compactWorkspace, showsFormat, !slider.isHidden, formatRect.contains(p) { openFormats(); return }
        super.mouseDown(with: event)
    }
    private var aseName: ASENameEditor?
    func cancelASEName() {
        if let editor = aseName, window?.firstResponder === editor { window?.makeFirstResponder(nil) }
        aseName?.removeFromSuperview(); aseName = nil; needsDisplay = true
    }
    func beginASEName(save: @escaping (String) -> Bool) {
        aseName?.removeFromSuperview()
        title = ""; grid.note = "Name your ASE file, then press Enter to choose its folder."
        let editor = ASENameEditor(frame: NSRect(x: inset, y: AreaHeader.headingBaseline - Design.Text.heading.font().ascender, width: max(120, bounds.width - inset - insetRight - 180), height: 28))
        editor.font = Design.Text.heading.font(); editor.textColor = Design.ink
        editor.drawsBackground = false; editor.isRichText = false
        editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel("New ASE filename")
        editor.onSave = { [weak self, weak editor] value in
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\n") else { NSSound.beep(); return }
            let stem = name.lowercased().hasSuffix(".ase") ? String(name.dropLast(4)) : name
            guard !stem.isEmpty else { NSSound.beep(); return }
            if save(stem) { editor?.removeFromSuperview(); self?.aseName = nil }
            else { self?.window?.makeFirstResponder(editor) }
        }
        editor.onCancel = { [weak self, weak editor] in editor?.removeFromSuperview(); self?.aseName = nil; self?.title = "Appbridge"; self?.needsDisplay = true }
        aseName = editor; addSubview(editor); window?.makeFirstResponder(editor); needsDisplay = true
        DispatchQueue.main.async { [weak self, weak editor] in
            guard let self, let editor, self.aseName === editor else { return }
            self.window?.makeFirstResponder(editor)
        }
    }
    var expandedPanelTitle:String? {didSet{needsDisplay=true}}
    private var title = ""
    private var meta: (String, String) = ("", "")
    /// The area header, then 16 clear before the tiles.
    static var headerHeight: CGFloat { AreaHeader.height }

    init() {
        super.init(frame: .zero)
        addSubview(viewingControls);addSubview(profileSelector)
        viewingControls.onChange={ [weak self] in self?.applyDeltaState(Prefs.deltaWarningsEnabled) }
        viewingControls.isHidden=true;profileSelector.isHidden=true

        registerForDraggedTypes([PaletteDrag.type])
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = grid
        addSubview(scroll)
        metadataFilterPanel.isHidden=true
        metadataFilterPanel.onFiltered = { [weak self] filtered in self?.filteredPageItems=filtered;self?.applyAssetOrder() }
        addSubview(metadataFilterPanel)
        settingsScroll.drawsBackground = false
        settingsScroll.hasVerticalScroller = true
        settingsScroll.autohidesScrollers = true
        settingsScroll.scrollerStyle = .overlay
        settingsScroll.documentView = settings
        settingsScroll.isHidden = true
        addSubview(settingsScroll)
        schemaScroll.drawsBackground = false
        schemaScroll.hasVerticalScroller = true
        schemaScroll.autohidesScrollers = true
        schemaScroll.scrollerStyle = .overlay
        schemaScroll.documentView = schema
        schemaScroll.isHidden = true
        addSubview(schemaScroll)
        newButton.isHidden = true
        newButton.target = self; newButton.action = #selector(makeNew)
        addSubview(newButton)
        exportButton.isHidden = true
        exportButton.target = self; exportButton.action = #selector(exportPressed)
        addSubview(exportButton)
        slider.onChange = { [weak self] v in self?.onAcross?(4 + Int((v * 4).rounded())) }
        addSubview(slider)
        grid.onResize = { [weak self] in self?.needsLayout = true }
        settings.onResize = { [weak self] in self?.needsLayout = true }
        schema.onResize = { [weak self] in self?.needsLayout = true }
        sectionTabs.drawsBackground=false; sectionTabs.hasHorizontalScroller=false; sectionTabs.hasVerticalScroller=false
        sectionTabs.documentView=tabBody; addSubview(sectionTabs)
        tabObserver=NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:nil,queue:.main) { [weak self] note in
            guard let self, let clip=note.object as? NSClipView, clip === self.anchoredScroll?.contentView else { return }
            self.updateActiveTab()
        }
    }

    /// What the page shows: the tiles, the Catalogues settings or the Schema settings, one in place of the others.
    func show(_ s: Section) {
        if s == .schema && section != .schema { schema.enterPage() }
        section = s
        layer?.backgroundColor = (s == .halo ? SettingsSheet.ground : Design.card).cgColor
        journey?.isHidden = s != .welcome
        scroll.isHidden = s != .tiles
        settingsScroll.isHidden = s != .catalogues
        schemaScroll.isHidden = s != .schema
        for (k, e) in extras { e.scroll.isHidden = k != s; if k == s { e.view.reload() } }
        if s == .catalogues { settings.reload() }
        if s == .schema { schema.reload() }
        newButton.isHidden = true
        exportButton.isHidden = true
        needsLayout = true
    }
    /// The page that is showing, whole, at the screen's scale: what --snap writes.
    func snapshot() -> NSBitmapImageRep? {
        let v: NSView
        switch section {
        case .tiles: v = grid
        case .catalogues: v = settings
        case .schema: v = schema
        default: guard let e = extras[section], let view = e.view as? NSView else { return nil }; v = view
        }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep
    }
    /// The Export button beside New; nil takes it away.
    func showExport(_ title: String?) {
        exportButton.isHidden = title == nil
        if let t = title { exportButton.title = t; exportButton.invalidateIntrinsicContentSize() }
        needsLayout = true
    }
    @objc private func exportPressed() { onExport?() }
    /// The New button under the header, with its word; nil takes it away.
    func showNew(_ title: String?) {
        newButton.isHidden = title == nil
        if let t = title { newButton.title = t; newButton.invalidateIntrinsicContentSize() }
        needsLayout = true
    }
    @objc private func makeNew() { onNew?() }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func canShowDelta(_ item:TileGrid.Item)->Bool { grid.canHover?(item) ?? (item.hex != nil || item.id != nil) }
    func set(title: String, meta: (String, String), items: [TileGrid.Item],reuseGridIfSame:Bool=false,sections:[TileGrid.Section]=[]) {
        self.title = title; self.meta = meta;subjectTabHeader.title=title
        showsDeltaTools = (showsPaletteFilters || paletteSwatchCount != nil || items.contains{canShowDelta($0)})
        applyDeltaState(Prefs.deltaWarningsEnabled)
        basePageItems=items
        filteredPageItems=items
        sourceGridSections=sections
        let reused=applyAssetOrder(reuseGridIfSame:reuseGridIfSame)
        if !reused{metadataFilterPanel.update(records:items)}
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        guard !layoutFrozen else { return }
        let profileWidth=min(240,max(120,(bounds.width-inset-insetRight)*0.32))
        profileSelector.frame=NSRect(x:bounds.width-insetRight-profileWidth,y:AreaHeader.labelBaseline-17,width:profileWidth,height:28)
        viewingControls.frame=NSRect(x:profileSelector.frame.minX-viewingControls.controlWidth-16,y:AreaHeader.labelBaseline-17,width:viewingControls.controlWidth,height:28)

        super.layout()
        if subjectTabHeader.superview == nil{addSubview(subjectTabHeader)}
        subjectTabHeader.isHidden = !imageIntakeMode
        subjectTabHeader.frame=NSRect(x:0,y:(imageIntakeMode ? 0:AreaHeader.headingBaseline-21)-WorkspaceTabContour.topOverlap,width:bounds.width,height:WorkspaceTabContour.height)
        var top = Self.headerHeight
        let u = Design.App.unit
        // The slider: one column wide, its track through the arrow's centre, ending a step before the arrow.
        slider.isHidden = section != .tiles || (imageIntakeMode && grid.imageFullView)
        let arrowCentre = AreaHeader.headingBaseline - 5
        let column = Design.App.columnWidth(in: window?.frame.width ?? Design.App.size.width)
        slider.frame = NSRect(x: bounds.width - insetRight - 16 - 24 - column, y: arrowCentre - 8, width: column, height: 16)
        if imageIntakeMode {slider.value=CGFloat(max(0,min(4,intakeGridColumns-4)))/4}
        if !newButton.isHidden || !exportButton.isHidden {
            // The buttons stand on the second unit's foot, clear of the rule above it; the tiles a unit below.
            var x = inset
            if !newButton.isHidden { newButton.frame = NSRect(x: x, y: top + 2 * u - 32, width: newButton.intrinsicContentSize.width, height: 32); x += newButton.frame.width + 12 }
            if !exportButton.isHidden { exportButton.frame = NSRect(x: x, y: top + 2 * u - 32, width: exportButton.intrinsicContentSize.width, height: 32) }
            top += 2 * u
        }
        let baseTilesTop = imageIntakeMode ? WorkspaceTabContour.height+u : compactWorkspace && section == .tiles ? top - Design.App.unit + (workspaceActionbar?.preferredHeight ?? WorkspaceViewportBar.actionbarHeight) + 12 : top + (section == .tiles ? (paletteCount == nil ? u : 2 * u) : 0)
        let filterHeight:CGFloat=metadataFilterExpanded && section == .tiles ? 236:0
        let promptHeight:CGFloat=importDestination == nil || imageIntakeMode ? 0:112
        let tilesTop=baseTilesTop+filterHeight+promptHeight
        let canvasWidth = bounds.width - inset - insetRight
        if importPanel.superview == nil{addSubview(importPanel)}
        importPanel.isHidden=promptHeight == 0
        importPanel.frame=NSRect(x:inset,y:baseTilesTop+filterHeight,width:canvasWidth,height:100)
        metadataFilterPanel.frame=NSRect(x:inset,y:baseTilesTop,width:canvasWidth,height:filterHeight)
        metadataFilterPanel.isHidden = filterHeight == 0
        scroll.frame = NSRect(x: inset, y: tilesTop, width: canvasWidth + min(insetRight, QuietScroller.lane), height: max(0,bounds.height - tilesTop))
        settingsScroll.frame = NSRect(x: inset, y: top, width: scroll.frame.width, height: max(0,bounds.height - top))
        journey?.frame = section == .welcome ? NSRect(x:0,y:32,width:bounds.width,height:max(0,bounds.height-32)):settingsScroll.frame
        let sh = settings.height(forWidth: canvasWidth)
        settings.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: max(scroll.frame.height, sh))
        settingsScroll.verticalScrollElasticity = sh > scroll.frame.height ? .allowed : .none
        // The schema's scroll starts at the page's edge, so a row's ground can reach the rail's divider; its words start a column in.
        schemaScroll.frame = NSRect(x: 0, y: top, width: inset + scroll.frame.width, height: max(0,bounds.height - top))
        schema.leading = inset
        let kh = schema.height(forWidth: inset + canvasWidth)
        schema.frame = NSRect(x: 0, y: 0, width: inset + canvasWidth, height: max(schemaScroll.frame.height, kh))
        schemaScroll.verticalScrollElasticity = kh > scroll.frame.height ? .allowed : .none
        for (_, e) in extras {
            e.scroll.frame = settingsScroll.frame
            let eh = e.view.height(forWidth: canvasWidth)
            e.view.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: max(e.scroll.frame.height, eh))
            // Tags is laid out as the schema is: from the page's edge, its words a column in.
            if let t = e.view as? TagsSettings {
                e.scroll.frame = schemaScroll.frame
                t.leading = inset
                t.frame = NSRect(x: 0, y: 0, width: inset + canvasWidth, height: max(e.scroll.frame.height, eh))
            } else if let sp = e.view as? SharePage {
                e.scroll.frame = schemaScroll.frame
                sp.leading = inset
                sp.frame = NSRect(x: 0, y: 0, width: inset + canvasWidth, height: max(e.scroll.frame.height, eh))
            }
            e.scroll.verticalScrollElasticity = eh > e.scroll.frame.height ? .allowed : .none
        }
        if paletteSwatchCount == nil {workspaceActionbar?.leadingControls=[];paletteActions.isHidden=true}
        if showsPaletteFilters,compactWorkspace,let actionbar=workspaceActionbar {
            if paletteFilters.superview !== actionbar {actionbar.addSubview(paletteFilters)}
            actionbar.leftInset=inset
            let width=paletteFilters.preferredWidth
            actionbar.leadingControls=[(paletteFilters,width,PaletteFilterControls.height(for:width),0)]
        }
        let controlParent: NSView = compactWorkspace ? (workspaceToolbar ?? self) : self
        for control in (compactWorkspace ? [slider] : [slider,profileSelector]) where control.superview !== controlParent { controlParent.addSubview(control) }
        let viewingParent: NSView = compactWorkspace ? (workspaceActionbar ?? self):self
        if viewingControls.superview !== viewingParent{viewingParent.addSubview(viewingControls)}
        if compactWorkspace,let actionbar=workspaceActionbar{
            actionbar.filtersNewRow = needsFilterRow(for:actionbar.bounds.width)
            actionbar.trailingControlsNewRow=viewingNeedsRow(for:actionbar.bounds.width)
            actionbar.rightControls=showsDeltaTools && !imageIntakeMode ? [(viewingControls,viewingControls.controlWidth,28,0)]:[]
        }
        if compactWorkspace{profileSelector.removeFromSuperview()}
        profileSelector.opensUpward = compactWorkspace
        if compactWorkspace,let toolbar=workspaceToolbar {
            toolbar.leftInset=inset
            toolbar.rightInset=insetRight
            if imageIntakeMode {
                toolbar.rightControls=grid.imageFullView ? [] : [(slider,120,16,0)]
            } else {
                if paletteSwatchCount != nil,let actionbar=workspaceActionbar {
                    actionbar.leftInset=inset
                    if paletteActions.superview !== actionbar {actionbar.addSubview(paletteActions)}
                    actionbar.leadingControls=[(paletteActions,paletteActions.controlWidth,32,0)]
                    toolbar.rightControls=[(slider,96,16,0)]
                } else {
                    if !showsPaletteFilters {workspaceActionbar?.leadingControls=[]}
                    toolbar.rightControls=[(slider,96,16,0)]
                }
            }
            slider.alphaValue = grid.listView ? 0.4 : 1
        } else { slider.alphaValue=1 }
        grid.contentInset = 0
        grid.width = canvasWidth
        grid.fullImageViewportHeight=scroll.frame.height
        grid.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: max(scroll.frame.height, grid.height))
        scroll.verticalScrollElasticity = grid.height > scroll.frame.height ? .allowed : .none
        if let scroll = anchoredScroll, let last = anchors.last, let document = scroll.documentView {
            document.frame.size.height = max(document.frame.height,last.1 + scroll.contentView.bounds.height)
            scroll.contentView.postsBoundsChangedNotifications = true
        }
        updateTabs()
        grid.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if section == .welcome || imageIntakeMode {return}
        if let picker=colourPickerHeader {
            AreaHeader.draw(heading:"",left:"CHOOSE NODE COLOURS · "+picker.instruction,right:picker.selection,in:bounds,inset:inset,insetRight:insetRight,arrow:.none,centreTabRowLabels:paneHeaderControls)
            return
        }
        // The same header as the rails: the name as the Heading, its two facts as the Labels, the Rule under.
        let paneCount=paletteSwatchCount.map{"Swatch Count \($0)"} ?? meta.0
        let paneContext=paletteSwatchCount == nil ? meta.1:meta.0
        AreaHeader.draw(heading: aseName == nil && !renamingTitle && !paneHeaderControls && !imageIntakeMode ? (expandedPanelTitle ?? title) : "", left:paneHeaderControls ? paneContext:(anchors.isEmpty && navigationTabs.isEmpty && !showsDeltaTools ? meta.0:""), right:paneHeaderControls ? paneCount:(anchors.isEmpty && navigationTabs.isEmpty && !showsDeltaTools ? meta.1:""), in: bounds, inset: inset, insetRight: insetRight, arrow: compactWorkspace ? .none : (expanded ? .close : .open),headingRight:paneHeaderControls ? "":(paletteSwatchCount.map{"Swatch Count \($0)"} ?? ""),headingTrailingInset:paneHeaderControls ? 144:0,centreTabRowLabels:paneHeaderControls)
        if showsDeltaTools && !paneHeaderControls {Design.attributed(meta.0,.label,colour:Design.quiet).draw(x:inset,baseline:AreaHeader.labelBaseline,width:compactWorkspace ? bounds.width-inset-insetRight : max(0,viewingControls.frame.minX-inset-16))}
        if let paletteCount, !compactWorkspace {
            Design.attributed(paletteCount, .bodyStrong).draw(x: inset, baseline: Self.headerHeight + Design.App.textBaseline, width: bounds.width - inset - insetRight)
        }
        // The colour model before the slider, a quiet word with its chevron, on the heading's line.
        formatRect = .zero
        if showsFormat, !slider.isHidden, !compactWorkspace {
            let b = AreaHeader.headingBaseline
            let t = Design.attributed(format.label, .caption, colour: Design.quiet)
            let right = slider.frame.minX - 24
            t.draw(right: right - 14, baseline: b)
            Design.quiet.setStroke()
            let c = NSBezierPath(); c.lineWidth = 1
            c.move(to: NSPoint(x: right - 9, y: b - 6)); c.line(to: NSPoint(x: right - 5, y: b - 2)); c.line(to: NSPoint(x: right - 1, y: b - 6))
            c.stroke()
            formatRect = NSRect(x: right - 14 - t.size().width - 8, y: b - 20, width: t.size().width + 24, height: 28)
        }
    }
}
