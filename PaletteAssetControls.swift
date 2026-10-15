import AppKit

/// Small palette actions keep their hit areas independent of row selection and dragging.
final class PaletteAssetIcon:NSButton {
    var symbol="" {didSet{needsDisplay=true}}
    var ink=Design.ink {didSet{needsDisplay=true}}
    var active=true {didSet{needsDisplay=true}}
    var halo=false
    var run:(()->Void)?
    private var hovered=false
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;target=self;action=#selector(pressed)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func pressed(){run?()}
    override func draw(_ dirtyRect:NSRect){
        if hovered || isHighlighted{ink.withAlphaComponent(0.10).setFill();bounds.fill()}
        let colour=ink.withAlphaComponent(active ? 1:0.45)
        if halo{Design.haloMark(in:NSRect(x:bounds.midX-6,y:bounds.midY-6,width:12,height:12),colour:colour);return}
        let image=RowMark.image(symbol,colour:colour),size=image.size
        image.draw(in:NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

final class PaletteReviewControls:NSView,Overlay {
    static let width:CGFloat=104
    private let stars=(1...5).map{_ in PaletteAssetIcon(frame:.zero)}
    private let flag=PaletteAssetIcon(frame:.zero)
    let halo=PaletteAssetIcon(frame:.zero)
    private var menuPanel:SwissDropdown.MenuPanel?
    private var rating=0
    private var flagValue:PaletteReview.Flag?
    var onRating:((Int)->Void)?
    var onFlag:((PaletteReview.Flag?)->Void)?
    var onHalo:((NSView,NSRect)->Void)?
    var ink=Design.ink {didSet{for star in stars{star.ink=ink};halo.ink=ink;if flagValue == nil{flag.ink=ink}}}
    var overlayWindows:[NSWindow]{menuPanel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let panel=menuPanel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};menuPanel=nil;Overlays.closed(self)}
    override init(frame:NSRect){
        super.init(frame:frame)
        for (index,star) in stars.enumerated(){
            star.run={ [weak self] in guard let self else{return};self.onRating?(self.rating == index+1 ? 0:index+1)}
            addSubview(star)
        }
        flag.symbol="flag";flag.run={ [weak self] in self?.openFlags() };addSubview(flag)
        halo.halo=true;halo.run={ [weak self] in guard let self else{return};self.onHalo?(self.halo,self.halo.bounds) };addSubview(halo)
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(_ value:PaletteAssetHandler.Presentation){
        rating=value.rating;flagValue=value.flag
        for (index,star) in stars.enumerated(){
            star.symbol=index < rating ? "star.fill":"star"
            let title="Rate "+value.palette.name+" \(index+1) Of 5; Current Rating \(rating)"
            star.toolTip=title;star.setAccessibilityLabel(title)
        }
        flag.symbol=flagValue == nil ? "flag":"flag.fill";flag.ink=flagValue.map{Design.hex($0.hex)} ?? ink
        flag.toolTip="Flag: "+(flagValue?.title ?? "None");flag.setAccessibilityLabel("Flag "+value.palette.name)
        halo.toolTip="Palette Actions";halo.setAccessibilityLabel("Actions For "+value.palette.name)
    }
    override func layout(){
        super.layout()
        for (index,star) in stars.enumerated(){star.frame=NSRect(x:CGFloat(index)*12,y:0,width:12,height:bounds.height)}
        flag.frame=NSRect(x:64,y:0,width:20,height:bounds.height)
        halo.frame=NSRect(x:84,y:0,width:20,height:bounds.height)
    }
    func activate(at point:NSPoint)->Bool {
        guard let button=(stars+[flag,halo]).first(where:{$0.frame.contains(point)}) else{return false}
        button.performClick(nil);return true
    }
    private func openFlags(){
        guard let window else{return}
        if menuPanel != nil{dismissOverlay();return}
        let flags=PaletteReview.Flag.allCases,items=["No Flag"]+flags.map(\.title)
        let panel=SwissDropdown.MenuPanel(items:items,chosen:flagValue?.title ?? "No Flag",width:180){ [weak self] index in
            self?.dismissOverlay();self?.onFlag?(index == 0 ? nil:flags[index-1])
        }
        panel.setLeadingSymbols(Dictionary(uniqueKeysWithValues:flags.enumerated().map{($0.offset+1,("flag.fill",Design.hex($0.element.hex)))}))
        let anchor=window.convertToScreen(flag.convert(flag.bounds,to:nil))
        panel.place(below:NSPoint(x:anchor.maxX-180,y:anchor.minY-4));window.addChildWindow(panel,ordered:.above)
        menuPanel=panel;Overlays.opened(self)
    }
}

/// House dropdown without an extra caption row, for a section header's right-hand action.
final class PaletteOrderControl:NSView,Overlay {
    var value=PaletteAssetHandler.Order.newest {didSet{needsDisplay=true}}
    var onChange:((PaletteAssetHandler.Order)->Void)?
    private var menuPanel:SwissDropdown.MenuPanel?
    override var isFlipped:Bool{true}
    var overlayWindows:[NSWindow]{menuPanel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let panel=menuPanel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};menuPanel=nil;Overlays.closed(self)}
    override func draw(_ dirtyRect:NSRect){
        DropdownSkin.draw(in:bounds.insetBy(dx:0,dy:2),up:menuPanel != nil,flipped:true)
        Design.attributed("Order: "+value.rawValue,.body).draw(x:8,baseline:bounds.midY+5,width:max(0,bounds.width-38))
    }
    override func mouseDown(with event:NSEvent){
        guard let window else{return}
        if menuPanel != nil{dismissOverlay();return}
        let orders=PaletteAssetHandler.Order.allCases
        let panel=SwissDropdown.MenuPanel(items:orders.map(\.rawValue),chosen:value.rawValue,width:200){ [weak self] index in
            self?.dismissOverlay();self?.value=orders[index];self?.onChange?(orders[index])
        }
        let anchor=window.convertToScreen(convert(bounds,to:nil))
        panel.place(below:NSPoint(x:anchor.maxX-200,y:anchor.minY-4));window.addChildWindow(panel,ordered:.above)
        menuPanel=panel;Overlays.opened(self)
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}
