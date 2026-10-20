import AppKit

/// Each mode owns its tools and viewport regions; switching never reparents another mode's contents.
final class DesignerWorkspace:NSView {
    enum Mode:String,CaseIterable {
        case web="Web & Screen",print="Print",branding="Branding",node="cNode"
    }
    private let tabs=DesignerTabs()
    private let pages=Mode.allCases.map{DesignerModeWorkspace(mode:$0)}
    private(set) var selectedMode:Mode
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        selectedMode=AppPreferences.shared.string(forKey:"designer.mode").flatMap(Mode.init(rawValue:)) ?? .web
        super.init(frame:frame)
        setAccessibilityLabel("Designer")
        for page in pages {addSubview(page)}
        addSubview(tabs)
        tabs.onSelect={ [weak self] mode in self?.select(mode) }
        select(selectedMode)
    }
    required init?(coder:NSCoder){fatalError()}
    private func select(_ mode:Mode){
        selectedMode=mode;tabs.selected=mode
        for page in pages {page.isHidden=page.mode != mode}
        AppPreferences.shared.set(mode.rawValue,forKey:"designer.mode")
        needsLayout=true
    }
    override func layout(){
        super.layout()
        let viewportWidth=max(0,bounds.width-Design.App.railWidth-1)
        tabs.frame=NSRect(x:0,y:0,width:viewportWidth,height:52)
        for page in pages {page.frame=bounds;page.headerHeight=tabs.frame.height}
    }
}

/// Intentionally empty tool and canvas containers for future palette-design tools.
final class DesignerModeWorkspace:NSView {
    let mode:DesignerWorkspace.Mode
    let actionbar=DesignerRegion()
    let viewport=DesignerRegion()
    let footer=DesignerRegion()
    let tools=WorkspaceRail(scrollbarOnLeft:false)
    var headerHeight:CGFloat=52 {didSet{if headerHeight != oldValue{needsLayout=true}}}
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
    override func layout(){
        super.layout()
        let width=max(0,bounds.width-Design.App.railWidth-1)
        tools.frame=NSRect(x:width+1,y:0,width:Design.App.railWidth,height:bounds.height)
        actionbar.frame=NSRect(x:0,y:headerHeight,width:width,height:WorkspaceViewportBar.actionbarHeight)
        footer.frame=NSRect(x:0,y:max(actionbar.frame.maxY,bounds.height-WorkspaceViewportBar.footerHeight),width:width,height:WorkspaceViewportBar.footerHeight)
        viewport.frame=NSRect(x:0,y:actionbar.frame.maxY,width:width,height:max(0,footer.frame.minY-actionbar.frame.maxY))
    }
}

final class DesignerRegion:NSView {
    var topRule=false,bottomRule=false
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        if topRule{hairline(x:0,y:0,width:bounds.width,Design.rule)}
        if bottomRule{hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)}
    }
}

private final class DesignerTabs:NSView {
    var selected=DesignerWorkspace.Mode.web {didSet{for button in buttons{button.active=button.mode == selected}}}
    var onSelect:((DesignerWorkspace.Mode)->Void)?
    private let buttons=DesignerWorkspace.Mode.allCases.map{DesignerTabButton(mode:$0)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for button in buttons {button.run={ [weak self] mode in self?.onSelect?(mode)};addSubview(button)}
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        var x:CGFloat=16
        for button in buttons {
            let width=ceil(Design.attributed(button.title,.bodyStrong).size().width)+16
            button.frame=NSRect(x:x,y:10,width:width,height:32);x+=width+16
        }
    }
    override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill();hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)}
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
