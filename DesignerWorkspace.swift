import AppKit

/// Each mode owns its tools and viewport regions; switching never reparents another mode's contents.
final class DesignerWorkspace:NSView {
    enum Mode:String,CaseIterable {
        case web="Web & Screen",print="Print",branding="Branding",palette="Palette"
    }
    private let tabs=DesignerTabs()
    private let pages=Mode.allCases.map{DesignerModeWorkspace(mode:$0)}
    var onModeChange:((Mode)->Void)?
    var paletteInspector:ImagePaletteInspectorPane? {pages.first(where:{$0.mode == .palette})?.paletteEditor?.inspector}
    var paletteHasImage:Bool {pages.first(where:{$0.mode == .palette})?.paletteEditor?.hasImage == true}
    var onPaletteImageChanged:((Bool)->Void)?
    private(set) var selectedMode:Mode
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        let remembered=AppPreferences.shared.string(forKey:"designer.mode")
        selectedMode=remembered == "cNode" ? .palette:(remembered.flatMap(Mode.init(rawValue:)) ?? .web)
        super.init(frame:frame)
        registerForDraggedTypes(DesignerImageDrop.types)
        setAccessibilityLabel("Designer")
        for page in pages {addSubview(page)}
        addSubview(tabs)
        tabs.onSelect={ [weak self] mode in self?.select(mode) }
        select(selectedMode)
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(library:LibraryController){
        pages.first(where:{$0.mode == .palette})?.configurePalette(library:library)
        pages.first(where:{$0.mode == .palette})?.paletteEditor?.onImageAvailabilityChanged={ [weak self] hasImage in self?.onPaletteImageChanged?(hasImage) }
    }
    private func select(_ mode:Mode){
        selectedMode=mode;tabs.selected=mode
        for page in pages {page.isHidden=page.mode != mode}
        AppPreferences.shared.set(mode.rawValue,forKey:"designer.mode")
        needsLayout=true
        onModeChange?(mode)
    }
    func acceptDroppedImage(_ payload:DesignerImageDrop.Payload) {
        if selectedMode != .palette {select(.palette)}
        pages.first(where:{$0.mode == .palette})?.paletteEditor?.useDroppedImage(payload)
    }
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
        !isHidden && DesignerImageDrop.supports(sender.draggingPasteboard) ? .copy:[]
    }
    override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {draggingEntered(sender)}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
        guard !isHidden,let payload=DesignerImageDrop.read(sender.draggingPasteboard) else{return false}
        acceptDroppedImage(payload)
        return true
    }
    override func layout(){
        super.layout()
        let viewportWidth=max(0,bounds.width-(selectedMode == .palette ? 0:Design.App.railWidth+1))
        tabs.frame=NSRect(x:0,y:0,width:viewportWidth,height:WorkspacePanel.headerHeight)
        for page in pages {page.frame=bounds;page.headerHeight=tabs.frame.height}
    }
}

/// Each Designer mode retains its own viewport and tool rail.
final class DesignerModeWorkspace:NSView {
    let mode:DesignerWorkspace.Mode
    let actionbar=DesignerRegion()
    let viewport=DesignerRegion()
    let footer=DesignerRegion()
    let tools=WorkspaceRail(scrollbarOnLeft:false)
    fileprivate var paletteEditor:DesignerPaletteEditor?
    var headerHeight:CGFloat=WorkspacePanel.headerHeight {didSet{if headerHeight != oldValue{needsLayout=true}}}
    override var isFlipped:Bool{true}
    init(mode:DesignerWorkspace.Mode){
        self.mode=mode;super.init(frame:.zero)
        setAccessibilityLabel(mode.rawValue+" Designer")
        for (view,name) in [(actionbar,"Actionbar"),(viewport,"Viewport"),(footer,"Footer")] {
            view.setAccessibilityLabel(mode.rawValue+" "+name);addSubview(view)
        }
        actionbar.bottomRule=true;footer.topRule=true
        tools.setAccessibilityLabel(mode.rawValue+" Tools");addSubview(tools)
    }
    required init?(coder:NSCoder){fatalError()}
    func configurePalette(library:LibraryController){
        guard mode == .palette,paletteEditor == nil else{return}
        let editor=DesignerPaletteEditor(library:library,actionbar:actionbar,viewport:viewport)
        paletteEditor=editor
    }
    override func layout(){
        super.layout()
        let width=max(0,bounds.width-(mode == .palette ? 0:Design.App.railWidth+1))
        tools.isHidden=mode == .palette
        tools.frame=NSRect(x:width+1,y:0,width:Design.App.railWidth,height:bounds.height)
        actionbar.frame=NSRect(x:0,y:headerHeight,width:width,height:WorkspaceViewportBar.actionbarHeight)
        footer.isHidden=mode == .palette
        let footerTop=mode == .palette ? bounds.height:max(actionbar.frame.maxY,bounds.height-WorkspaceViewportBar.footerHeight)
        footer.frame=NSRect(x:0,y:footerTop,width:width,height:mode == .palette ? 0:WorkspaceViewportBar.footerHeight)
        let tabOverlap:CGFloat=mode == .palette ? 1:0
        viewport.frame=NSRect(x:0,y:actionbar.frame.maxY-tabOverlap,width:width,
                              height:max(0,footerTop-actionbar.frame.maxY+tabOverlap))
    }
}

final class DesignerRegion:NSView {
    var topRule=false,bottomRule=false
    var gradedSurface=false
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        if gradedSurface {WorkspacePanelSurface.draw(in:bounds,selected:false)}
        if topRule{hairline(x:0,y:0,width:bounds.width,Design.rule)}
        if bottomRule{hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)}
    }
}

private final class DesignerTabs:NSView {
    var selected=DesignerWorkspace.Mode.web {didSet{
        for button in buttons{button.active=button.mode == selected}
        help.pageID=selected == .palette ? "designer-image-palette":"designer"
        needsDisplay=true
    }}
    var onSelect:((DesignerWorkspace.Mode)->Void)?
    private let buttons=DesignerWorkspace.Mode.allCases.map{DesignerTabButton(mode:$0)}
    private let help=Help_HexButton(page:"designer",title:"Designer")
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for button in buttons {button.run={ [weak self] mode in self?.onSelect?(mode)};addSubview(button)}
        addSubview(help)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        var x:CGFloat=16
        for button in buttons {
            let width=ceil(Design.attributed(button.title,.bodyStrong).size().width)+16
            button.frame=NSRect(x:x,y:(bounds.height-32)/2,width:width,height:32);x+=width+16
        }
        help.frame=Help_HexButton.frame(width:bounds.width,height:bounds.height)
    }
    override func draw(_ dirtyRect:NSRect){
        if selected == .palette {WorkspacePanelSurface.draw(in:bounds,selected:false)}
        else {Design.card.setFill();bounds.fill()}
        hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)
    }
}

private final class DesignerTabButton:ClickCursorButton {
    let mode:DesignerWorkspace.Mode
    var active=false {didSet{state=active ? .on:.off;needsDisplay=true}}
    var run:((DesignerWorkspace.Mode)->Void)?
    private var hovered=false
    override var isFlipped:Bool{true}
    init(mode:DesignerWorkspace.Mode){
        self.mode=mode;super.init(frame:.zero);title=mode.rawValue;isBordered=false
        target=self;action=#selector(pressed);setAccessibilityLabel(title)
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func pressed(){run?(mode)}
    override func draw(_ dirtyRect:NSRect){
        if hovered || isHighlighted{Design.mist.setFill();bounds.fill()}
        Design.attributed(title,active ? .bodyStrong:.body,colour:active ? Design.ink:Design.quiet).draw(x:8,baseline:bounds.midY+5)
        if active{hairline(x:8,y:bounds.height-2,width:bounds.width-16,Design.ink)}
    }
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}
