import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Shared title contour for split library tabs and single-subject pages.
enum WorkspaceTabContour {
    static let curve:CGFloat=28
    // The page tab extends below the rail header without changing the rail's height.
    static let height:CGFloat=WorkspacePanel.headerHeight+4
    /// Extend one point under the actionbar rule; the visible lower edge stays put.
    static let topOverlap:CGFloat=1
    /// The same concave action tab used below Library cards and canvas nodes.
    static func drawCardActionTab(_ tab:NSRect) {
        let notch=NSBezierPath(),halfCurve=curve/2
        notch.move(to:NSPoint(x:tab.minX-curve,y:tab.minY))
        notch.curve(to:NSPoint(x:tab.minX,y:tab.maxY-1),controlPoint1:NSPoint(x:tab.minX-halfCurve,y:tab.minY),controlPoint2:NSPoint(x:tab.minX-halfCurve,y:tab.maxY-1))
        notch.line(to:NSPoint(x:tab.maxX,y:tab.maxY-1))
        notch.curve(to:NSPoint(x:tab.maxX+curve,y:tab.minY),controlPoint1:NSPoint(x:tab.maxX+halfCurve,y:tab.maxY-1),controlPoint2:NSPoint(x:tab.maxX+halfCurve,y:tab.minY))
        let ground=notch.copy() as! NSBezierPath
        ground.close();Design.card.setFill();ground.fill()
        notch.lineWidth=1;Design.rule.setStroke();notch.stroke()
    }
    /// One selection band follows both the card and its concave control tab.
    static func drawSelectedCardContour(card:NSRect,tab:NSRect) {
        func outline(_ inset:CGFloat)->NSBezierPath {
            let body=card.insetBy(dx:-inset,dy:-inset)
            let radius:CGFloat=max(0,8+inset),bend=curve
            let leftFoot=tab.minX-bend-inset,rightFoot=tab.maxX+bend+inset
            let leftTab=tab.minX-inset,rightTab=tab.maxX+inset
            let tabBottom=tab.maxY-1+inset
            let path=NSBezierPath()
            path.move(to:NSPoint(x:body.minX+radius,y:body.minY))
            path.line(to:NSPoint(x:body.maxX-radius,y:body.minY))
            path.curve(to:NSPoint(x:body.maxX,y:body.minY+radius),
                       controlPoint1:NSPoint(x:body.maxX-radius/2,y:body.minY),
                       controlPoint2:NSPoint(x:body.maxX,y:body.minY+radius/2))
            path.line(to:NSPoint(x:body.maxX,y:body.maxY-radius))
            path.curve(to:NSPoint(x:body.maxX-radius,y:body.maxY),
                       controlPoint1:NSPoint(x:body.maxX,y:body.maxY-radius/2),
                       controlPoint2:NSPoint(x:body.maxX-radius/2,y:body.maxY))
            path.line(to:NSPoint(x:rightFoot,y:body.maxY))
            path.curve(to:NSPoint(x:rightTab,y:tabBottom),
                       controlPoint1:NSPoint(x:rightFoot-bend/2,y:body.maxY),
                       controlPoint2:NSPoint(x:rightTab+bend/2,y:tabBottom))
            path.line(to:NSPoint(x:leftTab,y:tabBottom))
            path.curve(to:NSPoint(x:leftFoot,y:body.maxY),
                       controlPoint1:NSPoint(x:leftTab-bend/2,y:tabBottom),
                       controlPoint2:NSPoint(x:leftFoot+bend/2,y:body.maxY))
            path.line(to:NSPoint(x:body.minX+radius,y:body.maxY))
            path.curve(to:NSPoint(x:body.minX,y:body.maxY-radius),
                       controlPoint1:NSPoint(x:body.minX+radius/2,y:body.maxY),
                       controlPoint2:NSPoint(x:body.minX,y:body.maxY-radius/2))
            path.line(to:NSPoint(x:body.minX,y:body.minY+radius))
            path.curve(to:NSPoint(x:body.minX+radius,y:body.minY),
                       controlPoint1:NSPoint(x:body.minX,y:body.minY+radius/2),
                       controlPoint2:NSPoint(x:body.minX+radius/2,y:body.minY))
            path.close()
            return path
        }
        let outer=outline(4),inner=outline(0)
        let band=NSBezierPath();band.windingRule = .evenOdd;band.append(outer);band.append(inner)
        let bounds=outer.bounds
        NSGraphicsContext.saveGraphicsState();band.addClip()
        NSColor.white.setFill();bounds.fill()
        NSColor.black.setFill()
        let stripe:CGFloat=6,period:CGFloat=12
        var x=bounds.minX-bounds.height-period
        while x<bounds.maxX+bounds.height+period {
            let mark=NSBezierPath()
            mark.move(to:NSPoint(x:x,y:bounds.minY));mark.line(to:NSPoint(x:x+stripe,y:bounds.minY))
            mark.line(to:NSPoint(x:x+stripe-bounds.height,y:bounds.maxY))
            mark.line(to:NSPoint(x:x-bounds.height,y:bounds.maxY))
            mark.close();mark.fill();x+=period
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func edge(width:CGFloat,height:CGFloat)->NSBezierPath{
        let path=NSBezierPath(),h=height-0.5,w=max(curve,width-0.5)
        path.move(to:NSPoint(x:0,y:0.5));path.line(to:NSPoint(x:w-curve,y:0.5))
        path.curve(to:NSPoint(x:w,y:h),controlPoint1:NSPoint(x:w-curve/2,y:0.5),controlPoint2:NSPoint(x:w-curve/2,y:h));return path
    }
    static func drawBarberPole(in bounds:NSRect,colour:NSColor){
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:bounds).addClip()
        Design.mix(colour,.white,0.20).setFill()
        let stripe=20*sqrt(2.0),step=30*sqrt(2.0),height=bounds.height
        var x = -height-step
        while x < bounds.width+height {
            let path=NSBezierPath();path.move(to:NSPoint(x:x,y:0));path.line(to:NSPoint(x:x+stripe,y:0));path.line(to:NSPoint(x:x+stripe-height,y:height));path.line(to:NSPoint(x:x-height,y:height));path.close();path.fill();x+=step
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Shared tab face used by both the pane layout and a single-page tab header.
    static func drawTab(in bounds:NSRect,title:String,symbol:String,selected:Bool){
        let edge=edge(width:bounds.width,height:bounds.height),h=bounds.height-0.5
        let ground=edge.copy() as! NSBezierPath
        ground.line(to:NSPoint(x:0,y:h));ground.close()
        (selected ? Design.card:Design.mist).setFill();ground.fill()
        // The Actionbar owns the straight top rule. Only the descending tab
        // contour is stroked, so the two rows meet on a single clean line.
        let w=max(curve,bounds.width-0.5)
        let outline=NSBezierPath()
        outline.move(to:NSPoint(x:w-curve,y:0.5))
        outline.curve(to:NSPoint(x:w,y:h),controlPoint1:NSPoint(x:w-curve/2,y:0.5),controlPoint2:NSPoint(x:w-curve/2,y:h))
        outline.lineWidth=1;Design.rule.setStroke();outline.stroke()
        RowMark.image(symbol,colour:Design.quiet).draw(in:NSRect(x:16,y:(bounds.height-14)/2+topOverlap,width:14,height:14),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        Design.attributed(title,selected ? .bodyStrong:.body).draw(x:36,baseline:bounds.midY+5+topOverlap,width:max(0,bounds.width-36-curve-8))
    }
    /// The mirrored S-curve over the action cap. A page may omit the cap entirely.
    static func drawActionCap(in bounds:NSRect,triggerX:CGFloat,tabEnd:CGFloat){
        let top:CGFloat=0.5,bottom=bounds.height-0.5
        let foot=max(0,triggerX-28),crest=max(0,triggerX-4)
        let controls=NSBezierPath();controls.move(to:NSPoint(x:foot,y:bottom))
        controls.curve(to:NSPoint(x:crest,y:top),controlPoint1:NSPoint(x:foot+12,y:bottom),controlPoint2:NSPoint(x:crest-12,y:top))
        controls.line(to:NSPoint(x:bounds.width,y:top))
        let ground=controls.copy() as! NSBezierPath
        ground.line(to:NSPoint(x:bounds.width,y:bottom));ground.close();Design.card.setFill();ground.fill()
        let border=NSBezierPath();border.move(to:NSPoint(x:min(tabEnd,foot),y:bottom))
        border.line(to:NSPoint(x:foot,y:bottom))
        border.curve(to:NSPoint(x:crest,y:top),controlPoint1:NSPoint(x:foot+12,y:bottom),controlPoint2:NSPoint(x:crest-12,y:top))
        border.lineWidth=1;Design.rule.setStroke();border.stroke()
    }
    static func canSplit(paneCount:Int,maxPanes:Int,isRoot:Bool,parentIsRoot:Bool,rootVertical:Bool?,vertical:Bool)->Bool{
        guard paneCount<maxPanes else{return false}
        if isRoot{return true}
        return parentIsRoot && rootVertical != vertical
    }
}
/// One-page host for the shared tab primitive. Its action props obey layout capacity.
final class WorkspacePageTabHeader:NSView{
    var title=""{didSet{needsDisplay=true;setAccessibilityLabel(title)}}
    var symbol="photo.on.rectangle"{didSet{needsDisplay=true}}
    var stripeColour=Design.houseYellow{didSet{needsDisplay=true}}
    var showsLeadingBorder=false{didSet{needsDisplay=true}}
    struct Actions {
        var paneCount=1,maxPanes=1
        var newTab:(()->Void)?
        var splitSide:(()->Void)?
        var splitBelow:(()->Void)?
        var close:(()->Void)?
    }
    var actions=Actions(){didSet{needsLayout=true;needsDisplay=true}}
    private let newButton=PaletteAssetIcon(frame:.zero),sideButton=PaletteAssetIcon(frame:.zero),belowButton=PaletteAssetIcon(frame:.zero),closeButton=PaletteAssetIcon(frame:.zero)
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{
        let local=convert(point,from:superview)
        return [newButton,sideButton,belowButton,closeButton].first{!$0.isHidden && $0.frame.contains(local)}?.hitTest(local)
    }
    override init(frame:NSRect){
        super.init(frame:frame)
        for (button,symbol,label) in [(newButton,"plus","New Tab"),(sideButton,"rectangle.split.2x1","Split Side By Side"),(belowButton,"rectangle.split.1x2","Split Top And Bottom"),(closeButton,"xmark","Close Panel")]{
            button.symbol=symbol;button.toolTip=label;button.setAccessibilityLabel(label);button.ink=Design.ink;addSubview(button)
        }
        newButton.run={ [weak self] in self?.actions.newTab?() }
        sideButton.run={ [weak self] in self?.actions.splitSide?() }
        belowButton.run={ [weak self] in self?.actions.splitBelow?() }
        closeButton.run={ [weak self] in self?.actions.close?() }
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        let available=[(newButton,actions.newTab != nil),
            (sideButton,actions.paneCount<actions.maxPanes && actions.splitSide != nil),
            (belowButton,actions.paneCount<actions.maxPanes && actions.splitBelow != nil),
            (closeButton,actions.paneCount>1 && actions.close != nil)]
        let shown=available.filter{$0.1}.map(\.0)
        for (button,visible) in available{button.isHidden = !visible}
        for (index,button) in shown.enumerated(){button.frame=NSRect(x:bounds.width-12-CGFloat(shown.count-index)*36,y:(bounds.height-32)/2+WorkspaceTabContour.topOverlap,width:32,height:32)}
    }
    override func draw(_ dirtyRect:NSRect){
        fill(bounds,Design.card)
        WorkspaceTabContour.drawBarberPole(in:bounds,colour:stripeColour)
        let shown=[newButton,sideButton,belowButton,closeButton].filter{!$0.isHidden}
        let capStart=shown.first?.frame.minX ?? bounds.width
        let tabWidth=min(max(72,Design.attributed(title,.bodyStrong).size().width+44+WorkspaceTabContour.curve),max(72,capStart-WorkspaceTabContour.curve-12))
        WorkspaceTabContour.drawTab(in:NSRect(x:0,y:0,width:tabWidth,height:bounds.height),title:title,symbol:symbol,selected:true)
        if let first=shown.first{WorkspaceTabContour.drawActionCap(in:bounds,triggerX:first.frame.minX,tabEnd:tabWidth)}
        else{hairline(x:tabWidth,y:bounds.height-1,width:max(0,bounds.width-tabWidth))}
        // The tab row owns this final pixel; the barber pole cannot leak below it.
        hairline(x:0,y:bounds.height-1,width:bounds.width)
        if showsLeadingBorder {fill(NSRect(x:0,y:0,width:1,height:bounds.height),Design.rule)}
    }
}

/// Stable pane/tab identities address views independently of the catalogue assets they display.
final class LibraryPageLayout:NSView {
    static let tabDragType=NSPasteboard.PasteboardType("com.colorgain.workspace-tab")
    let id=UUID()
    final class Content:NSView {
        var paintsGround=true
        var arrange:(()->Void)?
        override var isFlipped:Bool{true}
        override func layout(){super.layout();arrange?()}
        override func draw(_ dirtyRect:NSRect){if paintsGround{Design.card.setFill();bounds.fill()}}
    }
    final class Tab {
        var id=UUID()
        var route:StudioFrame.Place?
        var source:StudioFrame.Place = .catalogue
        var controller:StudioFrame?
        var content:NSView
        init(content:NSView=Content(frame:.zero)){self.content=content}
    }
    private final class Divider:NSSplitView,NSSplitViewDelegate {
        override var isFlipped:Bool{true}
        override init(frame:NSRect){super.init(frame:frame);delegate=self;autoresizingMask=[.width,.height]}
        required init?(coder:NSCoder){fatalError()}
        func splitView(_ splitView:NSSplitView,constrainMinCoordinate p:CGFloat,ofSubviewAt index:Int)->CGFloat {p+min(160,max(0,(isVertical ? bounds.width:bounds.height)/2-1))}
        func splitView(_ splitView:NSSplitView,constrainMaxCoordinate p:CGFloat,ofSubviewAt index:Int)->CGFloat {p-min(160,max(0,(isVertical ? bounds.width:bounds.height)/2-1))}
    }
    fileprivate enum Zone {case centre,left,right,top,bottom}
    fileprivate final class DropShade:NSView {
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func draw(_ dirtyRect:NSRect){Design.houseYellow.withAlphaComponent(0.2).setFill();bounds.fill();Design.houseYellow.setStroke();NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke()}
    }
    fileprivate final class TabScroll:FittedScrollView {
        var tabWidth:CGFloat=0
        override func tile(){super.tile();documentView?.setFrameSize(NSSize(width:max(tabWidth,contentView.bounds.width),height:WorkspaceTabContour.height))}
        override func scrollWheel(with event:NSEvent){
            let delta=event.scrollingDeltaX == 0 ? event.scrollingDeltaY:event.scrollingDeltaX
            let x=max(0,min(max(0,tabWidth-contentSize.width),contentView.bounds.minX-delta))
            contentView.scroll(to:NSPoint(x:x,y:0));reflectScrolledClipView(contentView)
        }
    }
    /// One contour follows the raised title tabs, the low middle span and the mirrored control tab.
    fileprivate final class HeaderContour:NSView {
        weak var pane:Pane?
        override var isFlipped:Bool{true}
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func draw(_ dirtyRect:NSRect){
            guard let pane else{return}
            if pane.owner?.hidePageControls?() == true{return}
            let trigger=pane.moreButton.isHidden ? pane.newButton:pane.moreButton
            let end=min(pane.strip.frame.maxX,max(0,pane.strip.tabWidth-pane.strip.contentView.bounds.minX))
            let tabHeight=WorkspaceTabContour.height
            // Carry the control face across the content's top rule, as the title tab does.
            let foot=max(0,trigger.frame.minX-WorkspaceTabContour.curve)
            fill(NSRect(x:foot,y:tabHeight-1,width:max(0,bounds.width-foot),height:2),Design.card)
            WorkspaceTabContour.drawActionCap(in:NSRect(x:0,y:0,width:bounds.width,height:tabHeight),triggerX:trigger.frame.minX,tabEnd:end)
        }
    }
    fileprivate final class TargetBand:NSView {
        weak var pane:Pane?
        override var isFlipped:Bool{true}
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func draw(_ dirtyRect:NSRect){
            NSGraphicsContext.saveGraphicsState()
            let clip=NSBezierPath(rect:bounds);clip.windingRule = .evenOdd
            if let pane {
                // Exclude the full tab grounds, including the bottom pixel beneath their contour.
                for label in pane.labels {
                    let rect=convert(label.bounds,from:label),shape=WorkspaceTabContour.edge(width:rect.width,height:rect.height)
                    shape.line(to:NSPoint(x:rect.width,y:rect.height));shape.line(to:NSPoint(x:0,y:rect.height));shape.close()
                    let transform=AffineTransform(translationByX:rect.minX,byY:rect.minY);shape.transform(using:transform);clip.append(shape)
                }
            }
            clip.addClip()
            WorkspaceTabContour.drawBarberPole(in:bounds,colour:Design.rule)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    fileprivate final class TargetPill:ClickCursorButton {
        var symbol: String?
        private var hovered=false
        override init(frame:NSRect){super.init(frame:frame);isBordered=false;setButtonType(.momentaryPushIn)}
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){
            let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:bounds.height/2,yRadius:bounds.height/2)
            (hovered ? Design.mist:Design.card).setFill();shape.fill();Design.rule.setStroke();shape.stroke()
            let text=Design.attributed(title,.caption,colour:Design.ink)
            let iconWidth:CGFloat = symbol == nil ? 0:22
            let start=(bounds.width-text.size().width-iconWidth)/2
            if let symbol { RowMark.image(symbol,colour:Design.ink).draw(in:NSRect(x:start,y:bounds.midY-8,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            text.draw(x:start+iconWidth,baseline:bounds.midY+4,width:bounds.width-iconWidth-12)
        }
        override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
        override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
        override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
    final class Pane:NSView,Overlay {
        static let compactControlsWidth:CGFloat=420
        var id=UUID()
        fileprivate weak var owner:LibraryPageLayout?
        fileprivate var tabs:[Tab]=[]
        fileprivate var selected:UUID?
        fileprivate var selectedTab:Tab?{tabs.first{$0.id == selected}}
        var controller:StudioFrame?{selectedTab?.controller}
        var route:StudioFrame.Place{selectedTab?.controller?.place ?? selectedTab?.route ?? selectedTab?.source ?? .catalogue}
        let newButton=PaletteAssetIcon(frame:.zero),splitButton=PaletteAssetIcon(frame:.zero),belowButton=PaletteAssetIcon(frame:.zero),closeButton=PaletteAssetIcon(frame:.zero)
        fileprivate let moreButton=PaletteAssetIcon(frame:.zero)
        private var toolMenu:SwissDropdown.MenuPanel?
        var overlayWindows:[NSWindow]{toolMenu.map{[$0]} ?? []}
        var dismissOnOutsideClick:Bool{true}
        func dismissOverlay(){if let menu=toolMenu{menu.parent?.removeChildWindow(menu);menu.orderOut(nil)};toolMenu=nil;Overlays.closed(self)}
        override func viewDidMoveToWindow(){super.viewDidMoveToWindow();if window == nil{dismissOverlay()}}
        private func openTools(){
            if toolMenu != nil{dismissOverlay();return}
            guard let window else{return}
            let buttons=[newButton]+(owner?.canSplit(self,vertical:true) == true ? [splitButton]:[])+(owner?.canSplit(self,vertical:false) == true ? [belowButton]:[])+(owner?.root is Pane ? []:[closeButton])
            let menu=SwissDropdown.MenuPanel(items:buttons.map{$0.toolTip ?? "Panel Action"},chosen:"",width:44,literalItems:true){ [weak self] index in
                self?.dismissOverlay();guard buttons.indices.contains(index) else{return};buttons[index].run?()
            }
            menu.setLeadingSymbols(Dictionary(uniqueKeysWithValues:buttons.enumerated().map{($0.offset,($0.element.symbol,Design.ink))}));menu.setIconsOnly()
            menu.place(anchoredTo:window.convertToScreen(moreButton.convert(moreButton.bounds,to:nil)),within:window)
            window.addChildWindow(menu,ordered:.above);toolMenu=menu;Overlays.opened(self)
        }
        fileprivate let strip=TabScroll(),document=Content(frame:.zero)
        fileprivate let contour=HeaderContour(frame:.zero)
        private let targetBand=TargetBand(frame:.zero),targetPill=TargetPill(frame:.zero),referencePill=TargetPill(frame:.zero)
        private var revealSelection=true,lastStripWidth:CGFloat = -1
        fileprivate var labels:[TabButton]=[]
        fileprivate let shade=DropShade(frame:.zero)
        fileprivate var zone=Zone.centre
        override init(frame:NSRect){
            super.init(frame:frame)
            strip.drawsBackground=false;strip.contentView.drawsBackground=false;document.paintsGround=false;strip.hasVerticalScroller=false;strip.hasHorizontalScroller=false;strip.documentView=document
            contour.pane=self;targetBand.pane=self;addSubview(targetBand);addSubview(contour);addSubview(targetPill);targetPill.target=self;targetPill.action=#selector(setTarget);addSubview(referencePill);referencePill.target=self;referencePill.action=#selector(toggleReferenceEditing);addSubview(strip);for b in [newButton,splitButton,belowButton,closeButton,moreButton]{addSubview(b)};addSubview(targetPill,positioned:.above,relativeTo:nil)
            moreButton.symbol="chevron.down";moreButton.toolTip="Panel Actions";moreButton.setAccessibilityLabel("Panel Actions");moreButton.run={ [weak self] in self?.openTools() }
            registerForDraggedTypes([LibraryPageLayout.tabDragType]);setAccessibilityIdentifier("library-pane-"+id.uuidString)
            NotificationCenter.default.addObserver(self,selector:#selector(refreshHeaderAppearance),name:.themeDidChange,object:nil)
        }
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool{true}
        deinit{NotificationCenter.default.removeObserver(self)}
        @objc private func refreshHeaderAppearance(){
            for button in [newButton,splitButton,belowButton,closeButton,moreButton]{button.ink=Design.ink;button.needsDisplay=true}
            labels.forEach{$0.needsDisplay=true};contour.needsDisplay=true;targetBand.needsDisplay=true;targetPill.needsDisplay=true;needsDisplay=true
        }
        private var referenceID: UUID? {
            let place = controller?.place ?? (selectedTab === owner?.initialTab ? owner?.currentPlace?():nil) ?? route
            if case .palette(let id) = place, controller?.isLinkedPalette(id) ?? owner?.isLinkedPalette?(id) ?? false { return id }
            return nil
        }
        @objc private func toggleReferenceEditing() {
            guard let id = referenceID else { return }
            if let controller { controller.toggleLinkedPaletteEditing(id) } else { owner?.toggleLinkedPaletteEditing?(id) }
            needsLayout=true
        }
        @objc private func setTarget(){_ = owner?.setTargetPane(id)}
        fileprivate func render(){
            dismissOverlay()
            for view in subviews where view !== strip && view !== newButton && view !== splitButton && view !== belowButton && view !== closeButton && view !== moreButton && view !== shade && view !== contour && view !== targetBand && view !== targetPill && view !== referencePill{view.removeFromSuperview()}
            if let tab=selectedTab {tab.content.removeFromSuperview();addSubview(tab.content,positioned:.below,relativeTo:targetBand)}
            labels.forEach{$0.removeFromSuperview()};labels=[]
            for tab in tabs {let label=TabButton(tab:tab,pane:self);document.addSubview(label);labels.append(label)}
            revealSelection=true;needsLayout=true
        }
        override func layout(){
            super.layout();selectedTab?.content.frame=NSRect(x:0,y:WorkspaceTabContour.topOverlap,width:bounds.width,height:max(0,bounds.height-WorkspaceTabContour.topOverlap))
            let compact=bounds.width < Self.compactControlsWidth
            if moreButton.isHidden == compact{dismissOverlay()}
            moreButton.isHidden = !compact
            newButton.isHidden=compact
            splitButton.isHidden=compact || owner?.canSplit(self,vertical:true) != true
            belowButton.isHidden=compact || owner?.canSplit(self,vertical:false) != true
            closeButton.isHidden=compact || owner?.root is Pane
            let hideControls=owner?.hidePageControls?() == true
            if hideControls {[moreButton,newButton,splitButton,belowButton,closeButton].forEach{$0.isHidden=true}}
            let buttons=hideControls ? []:compact ? [moreButton]:[newButton,splitButton,belowButton,closeButton].filter{!$0.isHidden}
            let controlsWidth=CGFloat(buttons.count)*36
            strip.frame=NSRect(x:0,y:0,width:max(0,bounds.width-20-controlsWidth-28),height:WorkspaceTabContour.height)
            contour.frame=NSRect(x:0,y:strip.frame.minY,width:bounds.width,height:WorkspaceTabContour.height+1)
            var x:CGFloat=0
            for label in labels {label.updateTitle();let width=min(480,max(72,Design.attributed(label.name,.bodyStrong).size().width+36+8+TabButton.curve));label.frame=NSRect(x:x,y:0,width:width,height:WorkspaceTabContour.height);x+=width;label.needsDisplay=true}
            strip.tabWidth=x;document.frame=NSRect(x:0,y:0,width:max(x,strip.contentSize.width),height:WorkspaceTabContour.height)
            if lastStripWidth != strip.frame.width{lastStripWidth=strip.frame.width;revealSelection=true}
            if revealSelection,let label=labels.first(where:{$0.tab.id == selected}){label.scrollToVisible(label.bounds);revealSelection=false}
            for (i,b) in buttons.enumerated(){b.ink=Design.ink;b.frame=NSRect(x:bounds.width-12-controlsWidth+CGFloat(i)*36,y:(WorkspaceTabContour.height-32)/2+WorkspaceTabContour.topOverlap,width:32,height:32)}
            targetBand.frame=NSRect(x:0,y:strip.frame.minY,width:bounds.width,height:WorkspaceTabContour.height)
            targetBand.isHidden=owner?.targetPaneID != id && referenceID == nil
            targetBand.needsDisplay=true
            targetPill.isHidden=owner?.root is Pane
            targetPill.title=owner?.targetPaneID == id ? "Target":"Set Target"
            targetPill.setAccessibilityLabel(targetPill.title+" Pane")
            targetPill.toolTip="Make This Pane The Target For Future Actions"
            targetPill.frame=NSRect(x:max(0,(bounds.width-88)/2),y:strip.frame.minY+4+WorkspaceTabContour.topOverlap,width:88,height:24)
            referencePill.isHidden = referenceID == nil
            if let id = referenceID {
                let unlocked = controller?.canEditLinkedPalette(id) ?? owner?.canEditLinkedPalette?(id) ?? false
                referencePill.symbol = unlocked ? "lock.open":"lock"
                referencePill.title = unlocked ? "Lock Editing":"Unlock Editing"
                referencePill.setAccessibilityLabel(referencePill.title + " Linked Palette")
                referencePill.toolTip = unlocked ? "Edits Save To The Original Linked File":"Unlock To Edit The Original Linked File"
                let right = targetPill.isHidden ? bounds.midX+76 : bounds.midX+124
                referencePill.frame=NSRect(x:max(8,right-152),y:strip.frame.minY+4+WorkspaceTabContour.topOverlap,width:152,height:24)
                if !targetPill.isHidden { targetPill.frame.origin.x=max(8,referencePill.frame.minX-96) }
                addSubview(referencePill,positioned:.above,relativeTo:nil)
                referencePill.needsDisplay=true
            }
            targetPill.needsDisplay=true
            contour.needsDisplay=true
        }
        override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill()}
        override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{draggingUpdated(sender)}
        override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation{
            guard let owner,let (source,_)=owner.draggedTab(sender.draggingPasteboard) else{return []}
            let p=convert(sender.draggingLocation,from:nil)
            zone=owner.dropZone(p,in:self)
            if source === self,tabs.count == 1,zone != .centre{shade.removeFromSuperview();return []}
            let r:NSRect
            switch zone {
            case .centre:r=NSRect(x:0,y:0,width:bounds.width,height:p.y < AreaHeader.rule ? AreaHeader.rule:bounds.height)
            case .left:r=NSRect(x:0,y:0,width:bounds.width/2,height:bounds.height)
            case .right:r=NSRect(x:bounds.width/2,y:0,width:bounds.width/2,height:bounds.height)
            case .top:r=NSRect(x:0,y:0,width:bounds.width,height:bounds.height/2)
            case .bottom:r=NSRect(x:0,y:bounds.height/2,width:bounds.width,height:bounds.height/2)
            }
            shade.frame=r;if shade.superview == nil{addSubview(shade)};return .move
        }
        override func draggingExited(_ sender:NSDraggingInfo?){shade.removeFromSuperview()}
        override func performDragOperation(_ sender:NSDraggingInfo)->Bool{
            shade.removeFromSuperview();guard let owner,let (source,tab)=owner.draggedTab(sender.draggingPasteboard) else{return false}
            let p=convert(sender.draggingLocation,from:nil)
            return owner.move(tab,from:source,to:self,zone:zone,index:p.y < AreaHeader.rule ? insertionIndex(p.x):tabs.count)
        }
        fileprivate func insertionIndex(_ x:CGFloat)->Int{let local=x+strip.contentView.bounds.minX;return labels.firstIndex{local < $0.frame.midX} ?? tabs.count}
    }
    fileprivate final class TabButton:NSView,NSDraggingSource {
        static let curve:CGFloat=WorkspaceTabContour.curve
        let tab:Tab
        weak var pane:Pane?
        private var start:NSPoint?,dragged=false,hovered=false
        private var announcedName=""
        private var announcedClosable:Bool?
        var name:String{pane?.owner?.name(of:tab) ?? "New Panel"}
        init(tab:Tab,pane:Pane){self.tab=tab;self.pane=pane;super.init(frame:.zero);setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityIdentifier("library-tab-"+tab.id.uuidString);setAccessibilityLabel("Tab: "+name);toolTip=name
            setAccessibilityCustomActions([NSAccessibilityCustomAction(name:"Close Tab",handler:{ [weak self] in guard let self,let pane=self.pane,let owner=pane.owner,owner.canCloseTab(in:pane) else{return false};owner.close(self.tab,in:pane);return true })])
        }
        func updateTitle(){
            if announcedName != name{announcedName=name;setAccessibilityLabel("Tab: "+name);toolTip=name}
            let canClose=pane.map{$0.owner?.canCloseTab(in:$0) == true} ?? false
            if announcedClosable != canClose{announcedClosable=canClose;setAccessibilityCustomActions(canClose ? [NSAccessibilityCustomAction(name:"Close Tab",handler:{ [weak self] in guard let self,let pane=self.pane,let owner=pane.owner,owner.canCloseTab(in:pane) else{return false};owner.close(self.tab,in:pane);return true })]:[])}
        }
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool{true}
        override var acceptsFirstResponder:Bool{true}
        override func accessibilityPerformPress()->Bool{guard let pane else{return false};pane.owner?.select(tab,in:pane);return true}
        override func draw(_ dirtyRect:NSRect){
            let selected=pane?.selected == tab.id
            let symbol:String
            switch tab.controller?.place ?? tab.route {
            case .some(.palette),.some(.palettes):symbol="swatchpalette"
            case nil:symbol="plus"
            default:symbol="folder"
            }
            WorkspaceTabContour.drawTab(in:bounds,title:name,symbol:symbol,selected:selected)
        }
        override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
        override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
        override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
        override func mouseDown(with event:NSEvent){start=convert(event.locationInWindow,from:nil);dragged=false;window?.makeFirstResponder(self)}
        override func mouseUp(with event:NSEvent){
            defer{start=nil};guard !dragged,let pane,let owner=pane.owner else{return}
            owner.select(tab,in:pane);if event.clickCount == 2{owner.rename(tab,from:self)}
        }
        override func keyDown(with event:NSEvent){if event.keyCode == 36 || event.keyCode == 49{_ = accessibilityPerformPress()}else{super.keyDown(with:event)}}
        override func mouseDragged(with event:NSEvent){
            guard !dragged,let start,let pane,let owner=pane.owner else{return}
            let p=convert(event.locationInWindow,from:nil);guard hypot(p.x-start.x,p.y-start.y)>=8 else{return}
            dragged=true
            let payload=NSPasteboardItem();payload.setString(owner.id.uuidString+"|"+tab.id.uuidString,forType:LibraryPageLayout.tabDragType)
            let item=NSDraggingItem(pasteboardWriter:payload),image=NSImage(size:bounds.size)
            image.lockFocus();draw(bounds);image.unlockFocus();item.setDraggingFrame(bounds,contents:image)
            beginDraggingSession(with:[item],event:event,source:self)
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation{context == .withinApplication ? .move:[]}
    }
    let primary=Pane(frame:.zero)
    let primaryContent=Content(frame:.zero)
    private let initialTab:Tab
    private(set) var active:Pane
    private var root:NSView
    private var monitor:Any?
    var makePage:((StudioFrame.Place)->StudioFrame)?
    var isLinkedPalette:((UUID)->Bool)?
    var canEditLinkedPalette:((UUID)->Bool)?
    var toggleLinkedPaletteEditing:((UUID)->Void)?
    var currentPlace:(()->StudioFrame.Place)?
    var hidePageControls:(()->Bool)?
    var pickerTitleOverride:String? {didSet{refreshTabTitles()}}
    var titleForPlace:((StudioFrame.Place)->String)?
    var navigatePrimary:((StudioFrame.Place)->Void)?
    var renamePrimary:((String)->Void)?
    var onActivate:((StudioFrame?)->Void)?
    var capturePrimary:(()->WorkspaceLayoutTemplate.Page)?
    var restorePrimary:((WorkspaceLayoutTemplate.Page)->Void)?
    var resolveRoute:((StudioFrame.Place)->StudioFrame.Place)?
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        initialTab=Tab(content:primaryContent);initialTab.route = .catalogue
        active=primary;root=primary
        super.init(frame:frame);primary.tabs=[initialTab];primary.selected=initialTab.id;configure(primary);addSubview(root);primary.render()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{if let monitor{NSEvent.removeMonitor(monitor)}}
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow();if let monitor{NSEvent.removeMonitor(monitor);self.monitor=nil};guard window != nil else{return}
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.keyDown]){ [weak self] event in
            guard let self,event.window === self.window,!self.isHidden else{return event}
            if event.type == .keyDown {DispatchQueue.main.async { [weak self] in guard let self else{return};var view=self.window?.firstResponder as? NSView;if let editor=view as? NSTextView,let field=editor.delegate as? NSView{view=field};self.activateAncestor(of:view)}}
            else{self.activateAncestor(of:self.hitTest(self.convert(event.locationInWindow,from:nil)))}
            return event
        }
    }
    private func configure(_ pane:Pane){
        pane.owner=self
        for (b,s,label) in [(pane.newButton,"plus","New Tab"),(pane.splitButton,"rectangle.split.2x1","Split Side By Side"),(pane.belowButton,"rectangle.split.1x2","Split Top And Bottom"),(pane.closeButton,"xmark","Close Panel")] {b.symbol=s;b.toolTip=label;b.setAccessibilityLabel(label)}
        pane.newButton.run={ [weak self,weak pane] in guard let self,let pane else{return};self.newTab(in:pane,source:pane.route) }
        pane.splitButton.run={ [weak self,weak pane] in guard let self,let pane else{return};self.activate(pane);_ = self.split(pane,vertical:true,before:false) }
        pane.belowButton.run={ [weak self,weak pane] in guard let self,let pane else{return};self.activate(pane);_ = self.split(pane,vertical:false,before:false) }
        pane.closeButton.run={ [weak self,weak pane] in guard let self,let pane else{return};self.remove(pane) }
    }
    private func panes(_ view:NSView?=nil)->[Pane]{let view=view ?? root;if let pane=view as? Pane{return [pane]};return view.subviews.flatMap{panes($0)}}
    private var targetID:UUID?
    var targetPaneID:UUID{targetID ?? primary.id}
    func restoreSessionTarget(_ id:UUID) {
        guard paneIDs.contains(id) else{return}
        targetID=id;panes().forEach{$0.needsLayout=true}
    }
    @discardableResult func setTargetPane(_ id:UUID)->Bool{
        guard let pane=panes().first(where:{$0.id == id}) else{return false}
        targetID=id;activate(pane);window?.makeFirstResponder(pane.controller?.page ?? pane)
        panes().forEach{$0.needsLayout=true};needsLayout=true
        return true
    }
    var paneIDs:[UUID]{panes().map{$0.id}}
    var activeTabID:UUID?{active.selected}
    func selectedTabID(in paneID:UUID)->UUID?{panes().first(where:{$0.id == paneID})?.selected}
    func tabIDs(in paneID:UUID)->[UUID]{panes().first(where:{$0.id == paneID})?.tabs.map{$0.id} ?? []}
    @discardableResult func closeTab(_ tabID:UUID,in paneID:UUID)->Bool{
        guard let pane=panes().first(where:{$0.id == paneID}),canCloseTab(in:pane),let tab=pane.tabs.first(where:{$0.id == tabID}) else{return false};close(tab,in:pane);return true
    }
    @discardableResult func moveTab(_ tabID:UUID,to paneID:UUID,at index:Int?=nil)->Bool{
        guard let destination=panes().first(where:{$0.id == paneID}),let source=panes().first(where:{$0.tabs.contains(where:{$0.id == tabID})}),let tab=source.tabs.first(where:{$0.id == tabID}) else{return false}
        return move(tab,from:source,to:destination,zone:.centre,index:index ?? destination.tabs.count)
    }
    func refreshTabTitles(){for pane in panes(){pane.needsLayout=true;for label in pane.labels{label.updateTitle();label.needsDisplay=true}}}
    func updatePrimary(_ place:StudioFrame.Place){initialTab.route=place;refreshTabTitles()}
    fileprivate func name(of tab:Tab)->String{if tab === initialTab,let pickerTitleOverride{return pickerTitleOverride};guard let place=tab.controller?.place ?? tab.route else{return "New Panel"};return titleForPlace?(place) ?? "Library"}
    private func activateAncestor(of hit:NSView?){var view=hit;while let candidate=view{if let pane=candidate as? Pane{activate(pane);return};view=candidate.superview}}
    private func activate(_ pane:Pane){active.layer?.borderWidth=0;active=pane;pane.wantsLayer=true;pane.layer?.borderWidth=0;onActivate?(pane.controller)}
    fileprivate func select(_ tab:Tab,in pane:Pane){pane.selected=tab.id;pane.render();activate(pane);needsLayout=true}
    func refreshPages(){for pane in panes(){for tab in pane.tabs{tab.controller?.reload()};pane.needsLayout=true}}
    func snapshot()->WorkspaceLayoutTemplate.Node {
        func node(_ view:NSView)->WorkspaceLayoutTemplate.Node {
            if let pane=view as? Pane {
                let tabs=pane.tabs.map{tab in WorkspaceLayoutTemplate.Tab(id:tab.id,primary:tab === initialTab,route:tab === initialTab ? currentPlace?():tab.controller?.place ?? tab.route,source:tab.source,view:tab === initialTab ? capturePrimary?():tab.controller?.captureLayoutPage())}
                return .pane(id:pane.id,primary:pane === primary,selected:pane.selected,tabs:tabs)
            }
            let split=view as! NSSplitView,children=split.arrangedSubviews
            let length=split.isVertical ? split.bounds.width:split.bounds.height
            let first=split.isVertical ? children[0].frame.width:children[0].frame.height
            return .split(vertical:split.isVertical,ratio:Double(first/max(1,length-split.dividerThickness)),first:node(children[0]),second:node(children[1]))
        }
        return node(root)
    }
    /// Apply scroll positions once the restored window and rail widths have settled.
    func restoreSessionViews(_ saved:WorkspaceLayoutTemplate.Node,includePrimary:Bool,primaryView:(WorkspaceLayoutTemplate.Page)->Void) {
        func visit(_ node:WorkspaceLayoutTemplate.Node) {
            switch node {
            case .split(_,_,let a,let b):visit(a);visit(b)
            case .pane(let id,_,_,let records):
                guard let pane=panes().first(where:{$0.id == id}) else{return}
                for record in records {
                    guard let view=record.view,let tab=pane.tabs.first(where:{$0.id == record.id}) else{continue}
                    if tab === initialTab {if includePrimary{primaryView(view)}}
                    else {tab.controller?.page.restoreLayoutView(view)}
                }
            }
        }
        visit(saved)
    }
    /// Page templates carry the currently focused tab into the first slot; other slots start empty.
    func restore(_ saved:WorkspaceLayoutTemplate.Node,activePane:UUID,pageOnly:Bool)throws {
        guard Layout_Handler.supportsSplitTree(saved),saved.tabCount > 0,saved.tabCount <= 128 else{throw failure("This layout has too many panels or tabs.")}
        let carried=active.selectedTab ?? initialTab
        var seenPanes=Set<UUID>(),seenTabs=Set<UUID>(),primaryPanes=0,primaryTabs=0
        func validate(_ node:WorkspaceLayoutTemplate.Node,depth:Int)throws {
            guard depth < 16 else{throw failure("This layout is nested too deeply.")}
            switch node {
            case .pane(let id,let isPrimary,let selected,let tabs):
                guard seenPanes.insert(id).inserted,!tabs.isEmpty,tabs.contains(where:{$0.id == selected}) else{throw failure("This layout has an invalid panel.")}
                if isPrimary{primaryPanes+=1};for tab in tabs{guard seenTabs.insert(tab.id).inserted else{throw failure("This layout has repeated tabs.")};if tab.primary{primaryTabs+=1}}
            case .split(_,let ratio,let a,let b):guard ratio.isFinite,ratio > 0,ratio < 1 else{throw failure("This layout has an invalid split.")};try validate(a,depth:depth+1);try validate(b,depth:depth+1)
            }
        }
        try validate(saved,depth:0);guard primaryPanes <= 1,primaryTabs <= 1 else{throw failure("This layout is missing its main view.")}
        for pane in panes(){pane.dismissOverlay();pane.tabs.forEach{$0.content.removeFromSuperview()};pane.tabs=[]}
        choices=[:];root.removeFromSuperview();var ratios:[(Divider,Double)]=[],firstSlot=true,viewRestores:[()->Void]=[]
        func build(_ node:WorkspaceLayoutTemplate.Node)->NSView {
            switch node {
            case .split(let vertical,let ratio,let a,let b):
                let split=Divider(frame:bounds);split.isVertical=vertical;split.dividerStyle = .thin;split.addArrangedSubview(build(a));split.addArrangedSubview(build(b));ratios.append((split,ratio));return split
            case .pane(let id,let isPrimary,let selected,let records):
                let pane=isPrimary ? primary:Pane(frame:.zero);pane.id=id;configure(pane)
                for record in records {
                    let tab:Tab
                    if pageOnly && firstSlot{tab=carried;firstSlot=false}
                    else if !pageOnly && record.primary{tab=initialTab}
                    else{tab=Tab()}
                    if !pageOnly{tab.id=record.id};tab.source=resolveRoute?(record.source) ?? record.source
                    pane.tabs.append(tab)
                    if pageOnly && tab === carried {continue}
                    if !pageOnly,let route=record.route {
                        let route=resolveRoute?(route) ?? route;tab.route=route
                        if tab === initialTab{navigatePrimary?(route);if let view=record.view{viewRestores.append{[weak self] in self?.restorePrimary?(view)}}}
                        else{tab.controller=makePage?(route);if let controller=tab.controller{tab.content=controller;if let view=record.view{viewRestores.append{[weak controller] in controller?.restoreLayoutPage(view)}}}}
                    }else{tab.route=nil;chooser(tab,in:pane)}
                }
                pane.selected=pageOnly ? pane.tabs.first?.id:selected;pane.render();return pane
            }
        }
        root=build(saved);addSubview(root);root.frame=bounds
        func position(_ view:NSView){guard let split=view as? Divider else{return};split.adjustSubviews();if let ratio=ratios.first(where:{$0.0 === split})?.1{split.setPosition((split.isVertical ? split.bounds.width-split.dividerThickness:split.bounds.height-split.dividerThickness)*ratio,ofDividerAt:0)};split.arrangedSubviews.forEach(position)}
        position(root)
        let target=pageOnly ? panes().first:panes().first{$0.id == activePane}
        if let target=target ?? panes().first{activate(target);targetID=target.id};needsLayout=true;layoutSubtreeIfNeeded();viewRestores.forEach{$0()}
    }
    /// Explicit destinations let tree navigation, tools and future integrations address a stable pane.
    @discardableResult func show(_ place:StudioFrame.Place,in paneID:UUID,newTab:Bool=false)->Bool{
        guard Self.supports(place),let pane=panes().first(where:{$0.id == paneID}) else{return false};activate(pane)
        if newTab{self.newTab(in:pane,source:place)}
        if pane.selectedTab === initialTab{navigatePrimary?(place);return true}
        load(pane,place:place);return true
    }
    private static func supports(_ place:StudioFrame.Place)->Bool {
        switch place{case .catalogue,.palettes,.palette,.collection,.folder,.project,.overview,.group:return true;default:return false}
    }
    func navigate(_ place:StudioFrame.Place)->Bool{guard active.selectedTab !== initialTab else{return false};load(active,place:place);return true}
    func selectPrimary(){select(initialTab,in:primary)}
    private func load(_ pane:Pane,place:StudioFrame.Place){
        guard let tab=pane.selectedTab else{return};tab.route=place
        if let controller=tab.controller{controller.go(place);pane.needsLayout=true;return}
        guard let controller=makePage?(place) else{return};choices.removeValue(forKey:tab.id);tab.controller=controller;tab.content=controller;pane.render();activate(pane)
    }
    private func newTab(in pane:Pane,source:StudioFrame.Place){let tab=Tab();tab.source=source;pane.tabs.append(tab);pane.selected=tab.id;chooser(tab,in:pane);pane.render();activate(pane)}
    fileprivate func canSplit(_ pane:Pane,vertical:Bool)->Bool{
        let split=root as? NSSplitView
        return WorkspaceTabContour.canSplit(paneCount:panes().count,maxPanes:4,isRoot:root === pane,
            parentIsRoot:pane.superview === root,rootVertical:split?.isVertical,vertical:vertical)
    }
    @discardableResult private func split(_ old:Pane,vertical:Bool,before:Bool)->Pane{
        guard canSplit(old,vertical:vertical) else{return old}
        let new=Pane(frame:.zero),divider=Divider(frame:old.frame),parent=old.superview
        configure(new);divider.isVertical=vertical;divider.dividerStyle = .thin
        if root === old{old.removeFromSuperview();root=divider;addSubview(divider)}
        else if let parent=parent as? NSSplitView,let index=parent.arrangedSubviews.firstIndex(where:{$0 === old}){parent.removeArrangedSubview(old);old.removeFromSuperview();parent.insertArrangedSubview(divider,at:index)}
        divider.addArrangedSubview(before ? new:old);divider.addArrangedSubview(before ? old:new)
        newTab(in:new,source:old.controller?.place ?? (old.selectedTab === initialTab ? currentPlace?() ?? old.route:old.route))
        needsLayout=true;layoutSubtreeIfNeeded();divider.adjustSubviews();divider.setPosition((vertical ? divider.bounds.width:divider.bounds.height)/2,ofDividerAt:0);return new
    }
    private final class Choice:NSObject {let run:()->Void;init(_ run:@escaping()->Void){self.run=run};@objc func press(){run()}}
    private var choices:[UUID:[Choice]]=[:]
    private func chooser(_ tab:Tab,in pane:Pane){
        guard let content=tab.content as? Content else{return}
        let scroll=FittedScrollView(),document=Content(frame:.zero);scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.documentView=document;content.addSubview(scroll)
        let actions:[(String,()->Void)]=[
            ("Library Palettes",{ [weak self,weak pane] in guard let pane else{return};self?.load(pane,place:.palettes) }),
            ("Open Current View Here",{ [weak self,weak pane,weak tab] in guard let pane,let tab else{return};self?.load(pane,place:tab.source) }),
            ("Browse Library…",{ [weak self,weak pane] in guard let pane else{return};self?.load(pane,place:.catalogue) }),
            ("Split Side By Side",{ [weak self,weak pane] in guard let self,let pane else{return};_ = self.split(pane,vertical:true,before:false) }),
            ("Split Top And Bottom",{ [weak self,weak pane] in guard let self,let pane else{return};_ = self.split(pane,vertical:false,before:false) }),
            ("Close Panel",{ [weak self,weak pane] in guard let pane else{return};self?.remove(pane) })]
        var targets:[Choice]=[]
        let buttons=actions.map{title,run -> SwissButton in let b=SwissButton(title,.secondary),target=Choice(run);targets.append(target);b.target=target;b.action=#selector(Choice.press);document.addSubview(b);return b}
        choices[tab.id]=targets
        content.arrange={ [weak content,weak pane] in guard let content else{return};scroll.frame=NSRect(x:0,y:AreaHeader.rule+1,width:content.bounds.width,height:max(0,content.bounds.height-AreaHeader.rule-1));document.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(288,scroll.contentSize.height));for (i,b) in buttons.enumerated(){b.isHidden = (i == buttons.count-1 && (pane?.owner?.root is Pane)) || (i == 3 && pane.map{$0.owner?.canSplit($0,vertical:true) != true} == true) || (i == 4 && pane.map{$0.owner?.canSplit($0,vertical:false) != true} == true);b.frame=NSRect(x:16,y:16+CGFloat(i)*44,width:max(0,min(b.intrinsicContentSize.width,content.bounds.width-48)),height:32)} }
    }
    fileprivate func canCloseTab(in pane:Pane)->Bool{pane.tabs.count > 1 || !(root is Pane)}
    fileprivate func close(_ tab:Tab,in pane:Pane){
        guard canCloseTab(in:pane) else{return}
        let oldIndex=pane.tabs.firstIndex(where:{$0 === tab}) ?? 0
        pane.tabs.removeAll{$0 === tab};choices.removeValue(forKey:tab.id);tab.content.removeFromSuperview()
        if pane.tabs.isEmpty{remove(pane)}else{select(pane.selectedTab ?? pane.tabs[min(oldIndex,pane.tabs.count-1)],in:pane)}
    }
    private func remove(_ pane:Pane){
        guard let split=pane.superview as? NSSplitView else{return}
        guard let survivor=split.arrangedSubviews.first(where:{$0 !== pane}) else{return}
        pane.tabs.forEach{choices.removeValue(forKey:$0.id);$0.content.removeFromSuperview()};pane.tabs=[];pane.selected=nil
        pane.labels.forEach{$0.removeFromSuperview()};pane.labels=[]
        pane.removeFromSuperview();survivor.removeFromSuperview()
        if root === split{split.removeFromSuperview();root=survivor;addSubview(survivor)}
        else if let parent=split.superview as? NSSplitView,let index=parent.arrangedSubviews.firstIndex(where:{$0 === split}){let rect=split.frame;parent.removeArrangedSubview(split);split.removeFromSuperview();parent.insertArrangedSubview(survivor,at:index);survivor.frame=rect;survivor.autoresizingMask=[.width,.height]}
        if let next=panes(survivor).first{activate(next);if !paneIDs.contains(targetPaneID){targetID=next.id}};needsLayout=true
    }
    fileprivate func rename(_ tab:Tab,from view:TabButton){
        let save=tab.controller?.page.onRenamePalette ?? (tab === initialTab ? renamePrimary:nil)
        guard let save else{return}
        let closeWidth:CGFloat=0
        InlineName.edit(name(of:tab),style:.bodyStrong,in:view,x:36,baseline:21,width:max(0,view.bounds.width-36-TabButton.curve-8-closeWidth),at:NSPoint(x:36,y:16)){ [weak self,weak view] value in if let value{save(value)};view?.needsDisplay=true;self?.needsLayout=true }
    }
    private func dropZone(_ point:NSPoint,in pane:Pane)->Zone{
        if point.y < AreaHeader.rule{return .centre}
        let edge=min(80,pane.bounds.width*0.2)
        if canSplit(pane,vertical:true){if point.x < edge{return .left};if point.x > pane.bounds.width-edge{return .right}}
        if canSplit(pane,vertical:false){if point.y < AreaHeader.rule+60{return .top};if point.y > pane.bounds.height-min(80,pane.bounds.height*0.2){return .bottom}};return .centre
    }
    private func draggedTab(_ pasteboard:NSPasteboard)->(Pane,Tab)?{
        guard let text=pasteboard.string(forType:Self.tabDragType) else{return nil};let parts=text.split(separator:"|");guard parts.count == 2,parts[0] == id.uuidString,let tabID=UUID(uuidString:String(parts[1])) else{return nil}
        for pane in panes(){if let tab=pane.tabs.first(where:{$0.id == tabID}){return (pane,tab)}};return nil
    }
    private func move(_ tab:Tab,from source:Pane,to target:Pane,zone:Zone,index:Int)->Bool{
        if source === target,source.tabs.count == 1,zone != .centre{return false}
        let destination:Pane
        if zone == .centre{destination=target}else{guard canSplit(target,vertical:zone == .left || zone == .right) else{return false};destination=split(target,vertical:zone == .left || zone == .right,before:zone == .left || zone == .top);destination.tabs.forEach{choices.removeValue(forKey:$0.id)};destination.tabs=[]}
        let originalIndex=source.tabs.firstIndex(where:{$0 === tab}) ?? 0
        source.tabs.removeAll{$0 === tab};tab.content.removeFromSuperview()
        let insertion=min(destination.tabs.count,max(0,index-(source === destination && originalIndex < index ? 1:0)));destination.tabs.insert(tab,at:insertion)
        if tab.route == nil{tab.content=Content(frame:.zero);chooser(tab,in:destination)}
        select(tab,in:destination)
        if source !== destination {if source.tabs.isEmpty{remove(source);activate(destination)}else{if source.selectedTab == nil{source.selected=source.tabs[min(originalIndex,source.tabs.count-1)].id};source.render()}}
        return true
    }
    override func layout(){super.layout();root.frame=bounds;if let split=root as? NSSplitView{split.adjustSubviews()};for pane in panes(){pane.needsLayout=true}}
    override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill()}
}
