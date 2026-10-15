import AppKit

/// Small palette actions keep their hit areas independent of row selection and dragging.
final class PaletteAssetIcon:NSButton {
    var symbol="" {didSet{needsDisplay=true}}
    var ink=Design.ink {didSet{needsDisplay=true}}
    var active=true {didSet{needsDisplay=true}}
    var run:(()->Void)?
    private var hovered=false
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;target=self;action=#selector(pressed)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func pressed(){run?()}
    override func draw(_ dirtyRect:NSRect){
        let rollover=hovered || isHighlighted
        let colour=ink.withAlphaComponent(rollover ? (active ? 0.60:1):(active ? 1:0.45))
        let image=RowMark.image(symbol,colour:colour),size=image.size
        image.draw(in:NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

final class PaletteReviewControls:NSView,Overlay {
    static let width:CGFloat=124
    private let stars=(1...5).map{_ in PaletteAssetIcon(frame:.zero)}
    private let flag=PaletteAssetIcon(frame:.zero)
    private var menuPanel:SwissDropdown.MenuPanel?
    private var rating=0
    private var flagValue:PaletteReview.Flag?
    var onRating:((Int)->Void)?
    var onFlag:((PaletteReview.Flag?)->Void)?
    var ink=Design.ink {didSet{for star in stars{star.ink=ink};if flagValue == nil{flag.ink=ink}}}
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
    }
    override func layout(){
        super.layout()
        for (index,star) in stars.enumerated(){star.frame=NSRect(x:CGFloat(index)*20,y:0,width:20,height:bounds.height)}
        flag.frame=NSRect(x:104,y:0,width:20,height:bounds.height)
    }
    func activate(at point:NSPoint)->Bool {
        guard let button=(stars+[flag]).first(where:{$0.frame.contains(point)}) else{return false}
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
        panel.place(anchoredTo:NSRect(x:anchor.maxX-180,y:anchor.minY,width:anchor.width,height:anchor.height));window.addChildWindow(panel,ordered:.above)
        menuPanel=panel;Overlays.opened(self)
    }
}

/// The palette page edits the same asset metadata as the library rows.
final class PalettePageControls:NSView {
    static let width:CGFloat=184
    let favourite=PaletteAssetIcon(frame:.zero)
    let target=PaletteAssetIcon(frame:.zero)
    let review=PaletteReviewControls(frame:.zero)
    override init(frame:NSRect){
        super.init(frame:frame);addSubview(favourite);addSubview(target);addSubview(review)
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(_ value:PaletteAssetHandler.Presentation){
        favourite.symbol=value.palette.favourite ? "star.fill":"star"
        favourite.setAccessibilityLabel((value.palette.favourite ? "Remove Favourite: ":"Add Favourite: ")+value.palette.name)
        favourite.toolTip=value.palette.favourite ? "Remove From Favourites":"Add To Favourites"
        target.symbol="scope";target.active=value.isTarget
        target.setAccessibilityLabel((value.isTarget ? "Stop Targeting ":"Target New Picks To ")+value.palette.name)
        target.toolTip=value.isTarget ? "New Picks Go Here":"Target For New Picks"
        review.configure(value)
    }
    override func layout(){
        super.layout()
        favourite.frame=NSRect(x:0,y:0,width:24,height:bounds.height)
        target.frame=NSRect(x:28,y:0,width:24,height:bounds.height)
        review.frame=NSRect(x:60,y:0,width:PaletteReviewControls.width,height:bounds.height)
    }
}

/// A single filter surface for library buckets and palette listing actionbars.
final class PaletteFilterControls:NSView,Overlay {
    static func height(for width:CGFloat)->CGFloat {width < 620 ? 72:32}
    static func actionbarHeight(for width:CGFloat)->CGFloat {width >= 1000 ? 52:height(for:min(636,max(328,width-48)))+60}
    var value=PaletteAssetHandler.Filter() {didSet{refresh()}}
    var onChange:((PaletteAssetHandler.Filter)->Void)?
    private let rating=DropdownButton(),flags=DropdownButton(),order=DropdownButton()
    private let clear=SwissButton("Clear",.quiet)
    private var menuPanel:SwissDropdown.MenuPanel?
    override var isFlipped:Bool{true}
    var overlayWindows:[NSWindow]{menuPanel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let panel=menuPanel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};menuPanel=nil;for button in [rating,flags,order]{button.opensUpward=false;button.needsDisplay=true};Overlays.closed(self)}
    override init(frame:NSRect){
        super.init(frame:frame)
        for (index,button) in [rating,flags,order].enumerated(){
            button.tag=index;button.target=self;button.action=#selector(openMenu(_:));button.font=Design.Text.body.font();button.isBordered=false;button.alignment = .left
            addSubview(button)
        }
        rating.setAccessibilityLabel("Filter Palette Rating");flags.setAccessibilityLabel("Filter Palette Flag");order.setAccessibilityLabel("Order Palettes")
        clear.target=self;clear.action=#selector(reset);addSubview(clear);refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    private func refresh(){
        rating.title=value.rating.map{$0 == 0 ? "No Rating":String(repeating:"☆",count:$0)} ?? "All Ratings"
        flags.title=value.flag.map{raw in PaletteReview.Flag(rawValue:raw)?.title ?? "No Flag"} ?? "All Flags"
        order.title="Order: "+value.order.rawValue
        clear.isHidden=value == PaletteAssetHandler.Filter()
        rating.toolTip=value.rating.map{"Exact Rating: \($0)"} ?? "All Ratings";flags.toolTip=value.flag == nil ? "All Flags":"Palette Flag";order.toolTip="Order By: "+value.order.rawValue
        needsLayout=true;needsDisplay=true
    }
    @objc private func reset(){dismissOverlay();value = .init();onChange?(value)}
    @objc private func openMenu(_ sender:NSButton){
        guard let window else{return};dismissOverlay()
        let flagValues=PaletteReview.Flag.allCases,orders=PaletteAssetHandler.Order.allCases
        let items:[String],chosen:Int
        switch sender.tag {
        case 0:items=["All Ratings","No Rating"]+(1...5).map{String(repeating:"☆",count:$0)};chosen=value.rating.map{$0+1} ?? 0
        case 1:items=["All Flags","No Flag"]+flagValues.map(\.title);chosen=value.flag.map{raw in flagValues.firstIndex(where:{$0.rawValue == raw}).map{$0+2} ?? 1} ?? 0
        default:items=orders.map(\.rawValue);chosen=orders.firstIndex(of:value.order) ?? 0
        }
        let panel=SwissDropdown.MenuPanel(items:items,chosen:items[chosen],width:208){[weak self] index in
            guard let self else{return};self.dismissOverlay()
            switch sender.tag {
            case 0:self.value.rating=index == 0 ? nil:index-1
            case 1:self.value.flag=index == 0 ? nil:(index == 1 ? "":flagValues[index-2].rawValue)
            default:self.value.order=orders[index]
            }
            self.onChange?(self.value)
        }
        panel.configure(disabled:[])
        if sender.tag == 1 {panel.setLeadingSymbols(Dictionary(uniqueKeysWithValues:flagValues.enumerated().map{($0.offset+2,("flag.fill",Design.hex($0.element.hex)))}))}
        let anchor=window.convertToScreen(sender.convert(sender.bounds,to:nil))
        panel.place(anchoredTo:anchor)
        (sender as? DropdownButton)?.opensUpward=panel.frame.minY >= anchor.maxY
        window.addChildWindow(panel,ordered:.above);menuPanel=panel;Overlays.opened(self)
    }
    override func layout(){
        super.layout()
        let clearWidth=clear.intrinsicContentSize.width
        if bounds.width < 620 {
            let column=(bounds.width-8)/2
            rating.frame=NSRect(x:0,y:0,width:column,height:32)
            flags.frame=NSRect(x:column+8,y:0,width:column,height:32)
            order.frame=NSRect(x:0,y:40,width:bounds.width-(clear.isHidden ? 0:clearWidth+12),height:32)
            clear.frame=NSRect(x:bounds.width-clearWidth,y:40,width:clearWidth,height:SwissButton.height)
        } else {
            rating.frame=NSRect(x:0,y:0,width:148,height:32)
            flags.frame=NSRect(x:160,y:0,width:148,height:32)
            order.frame=NSRect(x:332,y:0,width:max(0,bounds.width-332-(clear.isHidden ? 0:clearWidth+24)),height:32)
            clear.frame=NSRect(x:bounds.width-clearWidth,y:0,width:clearWidth,height:SwissButton.height)
        }
    }
}
