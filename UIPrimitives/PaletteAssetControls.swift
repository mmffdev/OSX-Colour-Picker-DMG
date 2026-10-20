import AppKit

/// Small palette actions keep their hit areas independent of row selection and dragging.
final class PaletteAssetIcon:ClickCursorButton {
    var symbol="" {didSet{if symbol != oldValue{needsDisplay=true}}}
    var ink=Design.ink {didSet{if !ink.isEqual(oldValue){needsDisplay=true}}}
    var active=true {didSet{if active != oldValue{needsDisplay=true}}}
    var run:(()->Void)?
    private var hovered=false
    private var themeInk=Design.ink
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;target=self;action=#selector(pressed);NotificationCenter.default.addObserver(self,selector:#selector(refreshThemeInk),name:.themeDidChange,object:nil)}
    deinit{NotificationCenter.default.removeObserver(self)}
    @objc private func refreshThemeInk(){if ink == themeInk{ink=Design.ink};themeInk=Design.ink;needsDisplay=true}
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
    override func resetCursorRects(){if isEnabled{ClickCursor.register([bounds],in:self)}}
}

final class PaletteReviewControls:NSView,Overlay {
    var isReadOnly = false { didSet { guard isReadOnly != oldValue else{return};for control in subviews.compactMap({ $0 as? NSControl }) { control.isEnabled = !isReadOnly }; if isReadOnly { dismissOverlay() } } }
    static let width:CGFloat=124
    private let stars=(1...5).map{_ in PaletteAssetIcon(frame:.zero)}
    private let flag=PaletteAssetIcon(frame:.zero)
    /// Visible symbol edges, excluding the wider star-button hit areas.
    var ratingGlyphSpan:ClosedRange<CGFloat> {
        func edges(_ symbol:String)->ClosedRange<CGFloat> {
            let image=RowMark.image(symbol,colour:ink),alignment=image.alignmentRect
            let rect=alignment.width > 0 ? alignment:NSRect(origin:.zero,size:image.size)
            let left=(20-image.size.width)/2+rect.minX
            return left...(left+rect.width)
        }
        let first=edges(stars.first?.symbol ?? "star"),last=edges(stars.last?.symbol ?? "star")
        return first.lowerBound...(80+last.upperBound)
    }

    private var menuPanel:SwissDropdown.MenuPanel?
    private var rating=0
    private var flagValue:PaletteReview.Flag?
    private var shownName:String?
    private var shownReview:PaletteReview?
    var onRating:((Int)->Void)?
    var onFlag:((PaletteReview.Flag?)->Void)?
    var ink=Design.ink {didSet{guard !ink.isEqual(oldValue) else{return};for star in stars{star.ink=ink};if flagValue == nil{flag.ink=ink}}}
    var overlayWindows:[NSWindow]{menuPanel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let panel=menuPanel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};menuPanel=nil;Overlays.closed(self)}
    override init(frame:NSRect){
        super.init(frame:frame)
        for (index,star) in stars.enumerated(){
            star.run={ [weak self] in guard let self else{return};let next=self.rating == index+1 ? 0:index+1;self.rating=next;for (i,glyph) in self.stars.enumerated(){glyph.symbol=i < next ? "star.fill":"star"};let update=self.onRating;DispatchQueue.main.async { update?(next) } }
            addSubview(star)
        }
        flag.symbol="flag";flag.run={ [weak self] in self?.openFlags() };addSubview(flag)
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(_ value:PaletteAssetHandler.Presentation){configure(name:value.palette.name,review:value.palette.review)}
    func configure(name:String,review:PaletteReview?){
        guard shownName != name || shownReview != review else{return}
        shownName=name;shownReview=review
        rating=review?.rating ?? 0;flagValue=review?.flag
        for (index,star) in stars.enumerated(){
            star.symbol=index < rating ? "star.fill":"star"
            let title="Rate "+name+" \(index+1) Of 5; Current Rating \(rating)"
            star.toolTip=title;star.setAccessibilityLabel(title)
        }
        flag.symbol=flagValue == nil ? "flag":"flag.fill";flag.ink=flagValue.map{Design.hex($0.hex)} ?? ink
        flag.toolTip="Flag: "+(flagValue?.title ?? "None");flag.setAccessibilityLabel("Flag "+name)
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
        guard !isReadOnly, let window else{return}
        if menuPanel != nil{dismissOverlay();return}
        let flags=PaletteReview.Flag.allCases,items=["No Flag"]+flags.map(\.title)
        let panel=SwissDropdown.MenuPanel(items:items,chosen:flagValue?.title ?? "No Flag",width:180){ [weak self] index in
            guard let self else{return}
            let next:PaletteReview.Flag?=index == 0 ? nil:flags[index-1]
            self.flagValue=next;self.flag.symbol=next == nil ? "flag":"flag.fill";self.flag.ink=next.map{Design.hex($0.hex)} ?? self.ink
            let update=self.onFlag
            self.dismissOverlay();DispatchQueue.main.async { update?(next) }
        }
        panel.setLeadingSymbols(Dictionary(uniqueKeysWithValues:flags.enumerated().map{($0.offset+1,("flag.fill",Design.hex($0.element.hex)))}))
        let anchor=window.convertToScreen(flag.convert(flag.bounds,to:nil))
        panel.place(anchoredTo:NSRect(x:anchor.maxX-180,y:anchor.minY,width:anchor.width,height:anchor.height));window.addChildWindow(panel,ordered:.above)
        menuPanel=panel;panel.orderFront(nil);Overlays.opened(self)
    }
}

/// The palette page edits the same asset metadata as the library rows.
final class PalettePageControls:NSView {
    static let width:CGFloat=184
    let back=SwissButton("Back to Palettes",.quiet)
    var controlWidth:CGFloat {Self.width+(back.isHidden ? 0:back.intrinsicContentSize.width+16)}
    let favourite=PaletteAssetIcon(frame:.zero)
    let target=PaletteAssetIcon(frame:.zero)
    let review=PaletteReviewControls(frame:.zero)
    override init(frame:NSRect){
        super.init(frame:frame);back.actionSymbol="arrow.left";back.isHidden=true;addSubview(back);addSubview(favourite);addSubview(target);addSubview(review)
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
        let offset:CGFloat=back.isHidden ? 0:back.intrinsicContentSize.width+16
        back.frame=NSRect(x:0,y:0,width:max(0,offset-16),height:bounds.height)
        favourite.frame=NSRect(x:offset,y:0,width:24,height:bounds.height)
        target.frame=NSRect(x:offset+28,y:0,width:24,height:bounds.height)
        review.frame=NSRect(x:offset+60,y:0,width:PaletteReviewControls.width,height:bounds.height)
    }
}

/// A single filter surface for library buckets and palette listing actionbars.
final class PaletteFilterControls:NSView,Overlay {
    static func height(for width:CGFloat)->CGFloat{32}
    static func actionbarHeight(for width:CGFloat)->CGFloat{52}
    var value=PaletteAssetHandler.Filter(){didSet{refresh()}}
    var onChange:((PaletteAssetHandler.Filter)->Void)?
    private let stars=(1...5).map{_ in PaletteAssetIcon(frame:.zero)}
    private let flags=PaletteAssetIcon(frame:.zero),orderIcon=PaletteAssetIcon(frame:.zero)
    private let order=DropdownButton()
    var showsOrder=true {didSet{needsLayout=true}}
    private var orderSelected=false
    private var menuPanel:SwissDropdown.MenuPanel?
    var preferredWidth:CGFloat{showsOrder ? 148+(orderSelected || value.order != .newest ? order.fittedWidth:24):132}
    override var isFlipped:Bool{true}
    var overlayWindows:[NSWindow]{menuPanel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let panel=menuPanel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};menuPanel=nil;Overlays.closed(self)}
    override init(frame:NSRect){
        super.init(frame:frame)
        for (i,star) in stars.enumerated(){addSubview(star);star.run={ [weak self] in guard let self else{return};self.value.rating=self.value.rating == i+1 ? nil:i+1;self.onChange?(self.value)}}
        flags.symbol="flag";flags.run={ [weak self] in self?.openFlags() };flags.setAccessibilityLabel("Filter Palette Flags");addSubview(flags)
        orderIcon.symbol="line.3.horizontal.decrease";orderIcon.run={ [weak self] in self?.openOrder() };orderIcon.setAccessibilityLabel("Order Palettes");orderIcon.toolTip="Order Palettes";addSubview(orderIcon)
        order.borderless=true;order.target=self;order.action=#selector(openOrder);order.setAccessibilityLabel("Order Palettes");addSubview(order);refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    private func refresh(){
        for (i,star) in stars.enumerated(){star.symbol=i < (value.rating ?? 0) ? "star.fill":"star";star.ink=Design.ink;star.toolTip="Filter Exact Rating: \(i+1) · Click Again For All Ratings";star.setAccessibilityLabel("Filter Rating \(i+1) Of 5")}
        flags.symbol=value.flag == nil ? "flag":"flag.fill";flags.ink=Design.ink;flags.toolTip=value.flag == nil ? "All Flags":"Filter Flags: "+value.selectedFlags.sorted().map{PaletteReview.Flag(rawValue:$0)?.title ?? "No Flag"}.joined(separator:", ")
        order.title=value.order.rawValue;order.toolTip="Order By: "+value.order.rawValue;needsLayout=true;needsDisplay=true;superview?.needsLayout=true
    }
    private func checkedFlags()->Set<Int>{
        if value.flag == nil{return [0]}
        let flags=PaletteReview.Flag.allCases
        return Set(value.selectedFlags.compactMap{raw in raw.isEmpty ? 1:flags.firstIndex(where:{$0.rawValue == raw}).map{$0+2}})
    }
    private func openFlags(){
        guard let window else{return};dismissOverlay()
        let values=PaletteReview.Flag.allCases
        let panel=SwissDropdown.MenuPanel(items:["All Flags","No Flag"]+values.map(\.title),chosen:"",width:180){ [weak self] index in
            guard let self else{return}
            if index == 0{self.value.flag=nil}else{let raw=index == 1 ? "":values[index-2].rawValue;var selected=self.value.selectedFlags;if selected.contains(raw){selected.remove(raw)}else{selected.insert(raw)};self.value.selectedFlags=selected}
            self.menuPanel?.setCheckedIndexes(self.checkedFlags());self.onChange?(self.value)
        }
        panel.setCheckedIndexes(checkedFlags());panel.setLeadingSymbols(Dictionary(uniqueKeysWithValues:values.enumerated().map{($0.offset+2,("flag.fill",Design.hex($0.element.hex)))}))
        panel.place(anchoredTo:window.convertToScreen(flags.convert(flags.bounds,to:nil)),within:window);window.addChildWindow(panel,ordered:.above);menuPanel=panel;panel.orderFront(nil);Overlays.opened(self)
    }
    @objc private func openOrder(){
        guard let window else{return};dismissOverlay();let values=PaletteAssetHandler.Order.allCases
        let trigger=order.isHidden ? orderIcon as NSView:order
        let panel=SwissDropdown.MenuPanel(items:values.map(\.rawValue),chosen:value.order.rawValue,width:208){ [weak self] index in guard let self else{return};self.dismissOverlay();self.orderSelected=true;self.value.order=values[index];self.onChange?(self.value)}
        panel.place(anchoredTo:window.convertToScreen(trigger.convert(trigger.bounds,to:nil)),within:window);window.addChildWindow(panel,ordered:.above);menuPanel=panel;panel.orderFront(nil);Overlays.opened(self)
    }
    override func layout(){
        super.layout();for (i,star) in stars.enumerated(){star.frame=NSRect(x:CGFloat(i)*20,y:0,width:20,height:32)}
        flags.frame=NSRect(x:108,y:0,width:24,height:32)
        order.isHidden = !showsOrder || (!orderSelected && value.order == .newest);orderIcon.isHidden = !showsOrder || !order.isHidden
        orderIcon.frame=NSRect(x:148,y:0,width:24,height:32);order.frame=NSRect(x:148,y:0,width:order.fittedWidth,height:32)
    }
}
