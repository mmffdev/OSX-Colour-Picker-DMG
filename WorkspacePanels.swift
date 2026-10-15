import AppKit

/// Shared disclosure glyph for outline rows and dockable panel headers.
final class WorkspaceDisclosure: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        if state == .on {
            path.move(to: NSPoint(x: centre.x-5, y: centre.y-3))
            path.line(to: NSPoint(x: centre.x+5, y: centre.y-3))
            path.line(to: NSPoint(x: centre.x, y: centre.y+4))
        } else {
            path.move(to: NSPoint(x: centre.x-3, y: centre.y+5))
            path.line(to: NSPoint(x: centre.x-3, y: centre.y-5))
            path.line(to: NSPoint(x: centre.x+4, y: centre.y))
        }
        path.close(); (isHighlighted ? Design.ink : Design.quiet).setFill(); path.fill()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// Shared restrained surface treatment for all docked panels and tree selections.
enum WorkspacePanelSurface {
    static func draw(in rect: NSRect, selected: Bool) {
        let top: CGFloat = selected ? 0.16 : 0.045
        let bottom: CGFloat = selected ? 0.10 : 0.015
        let from = Design.card.blended(withFraction:top,of:Design.ink) ?? Design.card
        let to = Design.card.blended(withFraction:bottom,of:Design.ink) ?? Design.card
        NSGradient(starting:from,ending:to)?.draw(in:rect,angle:90)
    }
}

final class WorkspacePanelRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        WorkspacePanelSurface.draw(in:bounds,selected:true)
    }
}

final class WorkspaceOutline: NSOutlineView {
    // Inset the disclosure and cell contents, never the full-width selection surface.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var rect = super.frameOfOutlineCell(atRow:row); rect.origin.x += 8; return rect
    }
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var rect = super.frameOfCell(atColumn:column,row:row); rect.origin.x += 8; rect.size.width=max(0,rect.width-8); return rect
    }

    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        if identifier.rawValue == "NSOutlineViewDisclosureButtonKey" {
            let button = WorkspaceDisclosure(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            button.identifier = identifier; button.setButtonType(.onOff); button.isBordered = false
            button.target = self; button.action = #selector(toggleDisclosure(_:))
            return button
        }
        return super.makeView(withIdentifier: identifier, owner: owner)
    }
    @objc private func toggleDisclosure(_ sender: NSButton) {
        let index = row(for: sender)
        guard index >= 0, let item = item(atRow: index), isExpandable(item) else { return }
        if isItemExpanded(item) { collapseItem(item) } else { expandItem(item) }
        sender.state = isItemExpanded(item) ? .on : .off
    }
}

/// Inner scrolling consumes a bordered lane only when content actually overflows.
/// The outer side follows the owning rail, including after a panel is moved.
protocol WorkspaceRailAwareContent:AnyObject {var scrollbarOnLeft:Bool {get set}}
/// Content extent excludes the breathing room owned by the panel container.
protocol WorkspacePanelContentMetrics {
    var minimumContentHeight:CGFloat {get}
    var panelContentPadding:CGFloat {get}
}
extension WorkspacePanelContentMetrics {
    var panelContentPadding:CGFloat {WorkspacePanel.contentPadding}
}
protocol WorkspaceScrollableContent:WorkspacePanelContentMetrics {}

final class WorkspacePanelScroll:FittedScrollView {
    var onLeft=false {didSet{if oldValue != onLeft {needsLayout=true;needsDisplay=true}}}
    var reservesScrollerLane=true {didSet{needsLayout=true;needsDisplay=true}}
    override func tile(){
        super.tile()
        let lane=hasVerticalScroller || reservesScrollerLane ? QuietScroller.lane:0
        let border:CGFloat=lane > 0 ? 1:0
        contentView.frame=NSRect(x:onLeft ? lane+border:0,y:0,width:max(0,bounds.width-lane-border),height:bounds.height)
        verticalScroller?.frame=NSRect(x:onLeft ? 0:bounds.width-lane,y:0,width:lane,height:bounds.height)
        if let document=documentView,abs(document.frame.width-contentView.bounds.width)>0.5 {document.setFrameSize(NSSize(width:contentView.bounds.width,height:document.frame.height))}
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        if hasVerticalScroller || reservesScrollerLane {Design.rule.setFill();NSRect(x:onLeft ? QuietScroller.lane:bounds.width-QuietScroller.lane-1,y:0,width:1,height:bounds.height).fill()}
    }
}

/// Optional fixed controls beneath the header of a sole, full-rail panel.
protocol WorkspacePinnedPanelContent:AnyObject {
    var pinnedControls:NSView {get}
    var pinnedControlsHeight:CGFloat {get}
    var controlsArePinned:Bool {get set}
}

private final class WorkspacePanelHeader:NSView {
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect){
        fill(bounds,Design.card)
        WorkspacePanelSurface.draw(in:bounds,selected:false)
        hairline(x:0,y:bounds.height-1,width:bounds.width)
    }
}

final class WorkspacePanel: NSView {
    static let headerHeight: CGFloat = 34
    static let footerHeight: CGFloat = 18
    static let contentPadding: CGFloat = 16
    let panelID: String
    let content: NSView
    var preferredHeight: CGFloat
    /// Content-sized panels ignore remembered drag heights and have no resize footer.
    var resizable:Bool {didSet{needsLayout=true;needsDisplay=true;rail?.arrange()}}
    var draggable:Bool {didSet{needsLayout=true}}
    /// A sole panel fills the dock, then grows with its contents into the rail's outer scroll.
    var fillsRail=false {didSet{needsLayout=true;rail?.arrange()}}
    var pinsHeader=false {didSet{rail?.arrange()}}
    var headerIsPinned=false {didSet{needsLayout=true}}
    fileprivate let headerSurface:NSView=WorkspacePanelHeader()
    var collapsed = false { didSet { disclosure.state = collapsed ? .off : .on; needsLayout = true; rail?.arrange() } }
    weak var rail: WorkspaceRail? {didSet{needsLayout=true}}
    private let contentScroll: WorkspacePanelScroll?
    private let disclosure = WorkspaceDisclosure()
    private let titleButton: NSButton
    private let filledTitle: NSTextField
    private let grip = PanelDragGrip()
    private let help: Help_HexButton
    private let resizeGrip = PanelResizeGrip()
    private let headerActionButton = NSButton()
    private var headerAction: (() -> Void)?
    private var contentHeight:CGFloat {(content as? WorkspacePanelContentMetrics)?.minimumContentHeight ?? max(72,content.fittingSize.height)}
    private var bottomPadding:CGFloat {(content as? WorkspacePanelContentMetrics)?.panelContentPadding ?? Self.contentPadding}
    private var resizeFooterHeight:CGFloat {resizable && !fillsRail ? Self.footerHeight:0}
    var minimumHeight:CGFloat {Self.headerHeight+contentHeight+bottomPadding+resizeFooterHeight}
    var panelHeight: CGFloat { fillsRail ? max((headerIsPinned ? 0:Self.headerHeight)+contentHeight+bottomPadding,rail?.panelViewportHeight ?? minimumHeight):(collapsed ? Self.headerHeight:(resizable ? max(minimumHeight,preferredHeight):minimumHeight)) }
    override var isFlipped: Bool { true }
    init(id: String, title: String, content: NSView, height: CGFloat? = nil, resizable:Bool = true, draggable:Bool = true) {
        panelID = id; self.content = content; preferredHeight = height ?? 0
        help=Help_HexButton(page:id,title:title)
        self.resizable=resizable;self.draggable=draggable
        contentScroll = content is WorkspaceInspector || content is WorkspaceScrollableContent ? WorkspacePanelScroll() : nil
        titleButton = NSButton(title: title, target: nil, action: nil)
        filledTitle = NSTextField(labelWithString:title)
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Design.card.cgColor
        disclosure.setButtonType(.onOff); disclosure.state = .on; disclosure.isBordered = false
        disclosure.target = self; disclosure.action = #selector(toggle)
        disclosure.setAccessibilityLabel("Collapse or expand \(title)")
        titleButton.isBordered = false; titleButton.alignment = .left
        titleButton.font = Design.Text.bodyStrong.font(); titleButton.contentTintColor = Design.ink
        titleButton.target = self; titleButton.action = #selector(toggle)
        filledTitle.font=Design.Text.bodyStrong.font();filledTitle.textColor=Design.ink;filledTitle.isHidden=true
        grip.panel = self; grip.setAccessibilityLabel("Move \(title) panel")
        grip.toolTip = "Drag to Rail1 or Rail2, above or below another panel"
        resizeGrip.panel = self; resizeGrip.toolTip = "Drag to resize \(title)"
        if let contentScroll {
            contentScroll.drawsBackground=false;contentScroll.hasVerticalScroller=true;contentScroll.autohidesScrollers=true
            contentScroll.reservesScrollerLane = !(content is WorkspaceRailAwareContent)
            contentScroll.documentView=content;addSubview(contentScroll)
        } else { addSubview(content) }
        headerActionButton.isHidden=true
        headerActionButton.isBordered=false
        headerActionButton.imagePosition = .imageOnly
        headerActionButton.appearance=NSAppearance(named:.aqua)
        headerActionButton.contentTintColor=Design.quiet
        headerActionButton.target=self; headerActionButton.action=#selector(runHeaderAction)
        addSubview(headerSurface)
        [disclosure,titleButton,filledTitle,headerActionButton,grip,help].forEach{headerSurface.addSubview($0)}
        addSubview(resizeGrip)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setHeaderAction(symbol: String, title: String, action: @escaping () -> Void) {
        headerAction=action
        headerActionButton.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
        headerActionButton.toolTip=title
        headerActionButton.setAccessibilityLabel(title)
        headerActionButton.isHidden=false
        needsLayout=true
    }
    @objc private func runHeaderAction() { headerAction?() }
    @objc private func toggle() { collapsed.toggle() }
    override func layout() {
        super.layout()
        if !headerIsPinned {headerSurface.frame=NSRect(x:0,y:0,width:bounds.width,height:Self.headerHeight)}
        disclosure.frame = NSRect(x: 8, y: 9, width: 16, height: 16)
        let dragSpace:CGFloat=draggable ? 28:0
        help.frame=Help_HexButton.frame(width:bounds.width,height:Self.headerHeight)
        titleButton.frame = NSRect(x: 30, y: 0, width: max(20,bounds.width-70-dragSpace-(headerAction == nil ? 0:28)), height: Self.headerHeight)
        headerActionButton.frame=NSRect(x:bounds.width-64-dragSpace,y:5,width:24,height:24)
        grip.frame = NSRect(x: bounds.width-64, y: 0, width: 28, height: Self.headerHeight)
        disclosure.isHidden=fillsRail;grip.isHidden=fillsRail || !draggable;titleButton.isHidden=fillsRail;filledTitle.isHidden = !fillsRail
        if fillsRail {
            titleButton.frame=NSRect(x:16,y:0,width:max(20,bounds.width-64),height:Self.headerHeight)
            let labelHeight=filledTitle.intrinsicContentSize.height
            filledTitle.frame=NSRect(x:16,y:(Self.headerHeight-labelHeight)/2,width:max(20,bounds.width-92),height:labelHeight)
            filledTitle.textColor=Design.ink
            headerActionButton.frame=NSRect(x:bounds.width-64,y:5,width:24,height:24)
        }
        let closed=collapsed && !fillsRail
        content.isHidden = closed; contentScroll?.isHidden=closed; resizeGrip.isHidden = closed || resizeFooterHeight == 0
        let top:CGFloat=headerIsPinned ? 0:Self.headerHeight
        let viewport=NSRect(x:0,y:top,width:bounds.width,height:max(0,bounds.height-top-resizeFooterHeight-bottomPadding))
        if let contentScroll {
            let height=fillsRail ? viewport.height:contentHeight
            contentScroll.onLeft=false
            contentScroll.reservesScrollerLane=resizable && !fillsRail && !(content is WorkspaceRailAwareContent)
            contentScroll.hasVerticalScroller=resizable && !fillsRail && height > viewport.height+0.5
            contentScroll.frame=viewport;contentScroll.tile()
            content.frame=NSRect(x:0,y:0,width:contentScroll.contentSize.width,height:max(height,contentScroll.contentSize.height))
        } else { content.frame=viewport }
        (content as? WorkspaceRailAwareContent)?.scrollbarOnLeft=false
        resizeGrip.frame = NSRect(x: 0, y: bounds.height-Self.footerHeight, width: bounds.width, height: Self.footerHeight)
    }
    override func draw(_ dirtyRect: NSRect) {
        if !collapsed && !fillsRail {
            if resizeFooterHeight > 0 {hairline(x:0,y:bounds.height-resizeFooterHeight,width:bounds.width)}
            hairline(x:0,y:bounds.height-1,width:bounds.width)
        }
    }
}

private final class PanelDragGrip: NSView {
    weak var panel: WorkspacePanel?
    private var dragging = false
    private weak var destination: WorkspaceRail?
    private var activeRails:[WorkspaceRail]=[]
    private var escapeMonitor:Any?
    private var scrollTimer:Timer?
    private var lastLocation=NSPoint.zero
    private var cancelled=false
    private func endDrag() {
        scrollTimer?.invalidate();scrollTimer=nil
        panel?.alphaValue=1
        activeRails.forEach{$0.setDragging(false)}
        activeRails=[];destination=nil;dragging=false
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) };escapeMonitor=nil
        NSCursor.openHand.set()
    }
    override func draw(_ dirtyRect: NSRect) {
        Design.quiet.setFill()
        for x:CGFloat in [10,16] { for y in [bounds.midY-7,bounds.midY-1,bounds.midY+5] { NSBezierPath(ovalIn: NSRect(x:x,y:y,width:2,height:2)).fill() } }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.openHand) }
    override func mouseDown(with event:NSEvent) { dragging=false;cancelled=false }
    override func mouseDragged(with event:NSEvent) {
        guard !cancelled,let panel,panel.draggable, let root=window?.contentView else{return}
        lastLocation=event.locationInWindow
        func rails(_ view:NSView)->[WorkspaceRail] {
            if let rail=view as? WorkspaceRail { return rail.isHidden ? [] : [rail] }
            return view.subviews.flatMap{rails($0)}
        }
        if !dragging {
            dragging=true;activeRails=rails(root)
            activeRails.forEach{$0.setDragging(true)}
            escapeMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                if event.keyCode == 53 { self?.cancelled=true;self?.endDrag();return nil };return event
            }
        }
        if scrollTimer == nil {
            let timer=Timer(timeInterval:1.0/30,repeats:true){[weak self] _ in
                guard let self,self.dragging else{return}
                self.destination?.previewDrop(at:self.lastLocation)
            }
            scrollTimer=timer;RunLoop.main.add(timer,forMode:.common)
        }
        let target=activeRails.first{$0.bounds.contains($0.convert(event.locationInWindow,from:nil))}
        if destination !== target { destination?.clearDrop() }
        destination=target
        target?.previewDrop(at:event.locationInWindow)
        panel.alphaValue=0.55
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event:NSEvent) {
        defer { endDrag() }
        guard dragging,let panel,panel.draggable else{return}
        destination?.finishDrop(panel)
    }
}

private final class PanelResizeGrip: NSView {
    weak var panel: WorkspacePanel?
    private var startY: CGFloat = 0, startHeight: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        Design.quiet.setFill()
        for x in [bounds.midX-7,bounds.midX-1,bounds.midX+5] {
            for y in [bounds.midY-4,bounds.midY+2] { NSBezierPath(ovalIn:NSRect(x:x,y:y,width:2,height:2)).fill() }
        }
    }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.resizeUpDown) }
    override func mouseDown(with event:NSEvent) { startY=event.locationInWindow.y; startHeight=panel?.panelHeight ?? 0 }
    override func mouseDragged(with event:NSEvent) {
        guard let panel,panel.resizable,!panel.fillsRail else { return }
        panel.preferredHeight=max(panel.minimumHeight,min(max(panel.minimumHeight,panel.rail?.bounds.height ?? 1000),startHeight+startY-event.locationInWindow.y))
        panel.rail?.arrange()
    }
}

/// Keeps the stack scrollbar outside the panel border, on the outer edge of its rail.
private final class WorkspaceRailScroll:FittedScrollView {
    var onLeft=false {didSet{needsLayout=true}}
    override func tile() {
        super.tile()
        let gutter=QuietScroller.lane
        contentView.frame=NSRect(x:onLeft ? gutter+1:0,y:0,width:max(0,bounds.width-gutter-1),height:bounds.height)
        verticalScroller?.frame=NSRect(x:onLeft ? 0:bounds.width-gutter,y:0,width:gutter,height:bounds.height)
        if let document=documentView {document.setFrameSize(NSSize(width:contentView.bounds.width,height:document.frame.height))}
    }
}

/// Each rail independently scrolls its stack; drops use the same ordering in either rail.
final class WorkspaceRail: NSView {
    private final class Stack:NSView { override var isFlipped:Bool { true } }
    private let scroll=WorkspaceRailScroll(), stack=Stack()
    var scrollbarOnLeft:Bool{scroll.onLeft}
    var panelViewportHeight:CGFloat {scroll.contentSize.height}
    private(set) var panels:[WorkspacePanel]=[]
    private var insertion:Int? { didSet { for (i,target) in targets.enumerated(){target.active=i == insertion} } }
    private var targets:[PanelDropTarget]=[]
    private var dragging=false
    private var targetRects:[NSRect]=[]
    var onDragging:((Bool)->Void)?
    func setDragging(_ value:Bool) {
        dragging=value;insertion=nil
        targets.forEach{$0.removeFromSuperview()};targets=[]
        if value { for _ in 0...panels.count { let target=PanelDropTarget();targets.append(target);addSubview(target) } }
        arrange();onDragging?(value)
    }
    override var isFlipped:Bool { true }
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true; layer?.backgroundColor=Design.card.cgColor
        scroll.drawsBackground=false; scroll.hasVerticalScroller=true;scroll.autohidesScrollers=false;scroll.documentView=stack
        scroll.verticalScrollElasticity = .none;QuietScroller.install(in:scroll)
        addSubview(scroll)
    }
    convenience init(scrollbarOnLeft:Bool) {self.init(frame:.zero);scroll.onLeft=scrollbarOnLeft}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect) {
        Design.rule.setFill()
        NSRect(x:scroll.onLeft ? bounds.width-1:0,y:0,width:1,height:bounds.height).fill()
        NSRect(x:scroll.onLeft ? QuietScroller.lane:bounds.width-QuietScroller.lane-1,y:0,width:1,height:bounds.height).fill()
    }
    func add(_ panel:WorkspacePanel,at index:Int? = nil) {
        if let old=panel.rail { old.panels.removeAll{$0 === panel};old.arrange() }
        panel.removeFromSuperview();panels.insert(panel,at:min(index ?? panels.count,panels.count));panel.rail=self;stack.addSubview(panel);arrange()
    }
    override func layout(){super.layout();arrange()}
    func arrange() {
        let pinned=panels.count == 1 && panels[0].fillsRail && panels[0].pinsHeader ? panels[0]:nil
        let controls=pinned?.content as? WorkspacePinnedPanelContent
        let fixedHeight:CGFloat=pinned == nil ? 0:WorkspacePanel.headerHeight+(controls?.pinnedControlsHeight ?? 0)
        scroll.frame=NSRect(x:scroll.onLeft ? 0:1,y:fixedHeight,width:max(0,bounds.width-1),height:max(0,bounds.height-fixedHeight))
        scroll.tile()
        for panel in panels {
            panel.headerIsPinned=panel === pinned
            if panel === pinned {
                if panel.headerSurface.superview !== self {addSubview(panel.headerSurface)}
                panel.headerSurface.frame=NSRect(x:scroll.frame.minX+scroll.contentView.frame.minX,y:0,width:scroll.contentSize.width,height:WorkspacePanel.headerHeight)
                if let controls {
                    controls.controlsArePinned=true
                    if controls.pinnedControls.superview !== self {addSubview(controls.pinnedControls)}
                    controls.pinnedControls.frame=NSRect(x:panel.headerSurface.frame.minX,y:WorkspacePanel.headerHeight,width:scroll.contentSize.width,height:controls.pinnedControlsHeight)
                }
            } else if panel.headerSurface.superview !== panel {panel.addSubview(panel.headerSurface)}
        }
        var y:CGFloat=0
        targetRects=[]
        let width=scroll.contentSize.width
        for (i,panel) in panels.enumerated() {
            if dragging,targets.indices.contains(i) { targetRects.append(NSRect(x:0,y:y,width:width,height:22));y += 22 }
            panel.frame=NSRect(x:0,y:y,width:width,height:panel.panelHeight);panel.needsLayout=true
            // Headers meet the preceding footer directly; only active drop slots add space.
            y += panel.panelHeight
        }
        if dragging { targetRects.append(NSRect(x:0,y:y,width:width,height:22));y += 22 }
        stack.frame=NSRect(x:0,y:0,width:width,height:max(scroll.contentSize.height,y))
        updateDropPresentation()
        needsDisplay=true
    }
    private func updateDropPresentation() {
        // One view per insertion slot. Edge slots are repositioned, never duplicated.
        for (index,target) in targets.enumerated() {
            guard targetRects.indices.contains(index) else {target.isHidden=true;continue}
            var rect=convert(targetRects[index],from:stack)
            if index == 0 { rect.origin.y=0;target.edge = .top }
            else if index == targets.count-1 {
                rect.origin.y=min(max(0,bounds.height-22),max(0,rect.minY))
                target.edge = .bottom
            } else {target.edge = .middle}
            target.frame=rect
            target.isHidden = !dragging || !bounds.intersects(rect)
        }
        // Edge targets own their entire band, including while the stack scrolls behind them.
        if let first=targets.first,let last=targets.last {
            for target in targets.dropFirst().dropLast() {
                if target.frame.intersects(first.frame) || target.frame.intersects(last.frame) {target.isHidden=true}
            }
        }
    }
    func previewDrop(at location:NSPoint) {
        // Explicit top and bottom slots make every insertion position reachable.
        let railPoint=convert(location,from:nil)
        if railPoint.y < 30 { scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,scroll.contentView.bounds.minY-14))) }
        else if railPoint.y > bounds.height-30 { scroll.contentView.scroll(to:NSPoint(x:0,y:min(max(0,stack.bounds.height-scroll.contentSize.height),scroll.contentView.bounds.minY+14))) }
        scroll.reflectScrolledClipView(scroll.contentView)
        updateDropPresentation()
        insertion=targets.indices.filter{!targets[$0].isHidden}.min{
            abs(targets[$0].frame.midY-railPoint.y)<abs(targets[$1].frame.midY-railPoint.y)
        }
    }
    func clearDrop(){insertion=nil;updateDropPresentation()}
    func finishDrop(_ panel:WorkspacePanel) {
        guard var index=insertion else{return}
        if panel.rail === self,let old=panels.firstIndex(where:{$0 === panel}),old < index { index -= 1 }
        add(panel,at:index);insertion=nil
    }
 }

/// A 22-point insertion slot: a four-point rule flows into a symmetrical curved tab.
private final class PanelDropTarget:NSView {
    enum Edge { case top,middle,bottom }
    var edge=Edge.middle { didSet { needsDisplay=true } }
    var active=false { didSet { needsDisplay=true } }
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect) {
        let c=bounds.midX,y=bounds.midY,path=NSBezierPath()
        if edge != .middle {
            // Mirrored, border-flush tabs keep the full label readable without an outer lobe.
            let transform=NSAffineTransform()
            if edge == .bottom { transform.translateX(by:0,yBy:bounds.height);transform.scaleX(by:1,yBy:-1) }
            path.move(to:NSPoint(x:0,y:0));path.line(to:NSPoint(x:bounds.width,y:0))
            path.line(to:NSPoint(x:bounds.width,y:4));path.line(to:NSPoint(x:c+66,y:4))
            path.curve(to:NSPoint(x:c+40,y:21),controlPoint1:NSPoint(x:c+50,y:4),controlPoint2:NSPoint(x:c+54,y:21))
            path.line(to:NSPoint(x:c-40,y:21))
            path.curve(to:NSPoint(x:c-66,y:4),controlPoint1:NSPoint(x:c-54,y:21),controlPoint2:NSPoint(x:c-50,y:4))
            path.line(to:NSPoint(x:0,y:4));path.close();path.transform(using:transform as AffineTransform)
            (active ? Design.houseYellow:Design.ink).setFill();path.fill()
            let text=Design.attributed("Drop Here",.body,colour:active ? Design.ink:Design.card)
            text.draw(x:c-text.size().width/2,baseline:16)
            return
        }
        path.move(to:NSPoint(x:8,y:y-2));path.line(to:NSPoint(x:c-66,y:y-2))
        path.curve(to:NSPoint(x:c-40,y:1),controlPoint1:NSPoint(x:c-50,y:y-2),controlPoint2:NSPoint(x:c-54,y:1))
        path.line(to:NSPoint(x:c+40,y:1))
        path.curve(to:NSPoint(x:c+66,y:y-2),controlPoint1:NSPoint(x:c+54,y:1),controlPoint2:NSPoint(x:c+50,y:y-2))
        path.line(to:NSPoint(x:bounds.width-8,y:y-2));path.line(to:NSPoint(x:bounds.width-8,y:y+2))
        path.line(to:NSPoint(x:c+66,y:y+2))
        path.curve(to:NSPoint(x:c+40,y:bounds.height-1),controlPoint1:NSPoint(x:c+50,y:y+2),controlPoint2:NSPoint(x:c+54,y:bounds.height-1))
        path.line(to:NSPoint(x:c-40,y:bounds.height-1))
        path.curve(to:NSPoint(x:c-66,y:y+2),controlPoint1:NSPoint(x:c-54,y:bounds.height-1),controlPoint2:NSPoint(x:c-50,y:y+2))
        path.line(to:NSPoint(x:8,y:y+2));path.close()
        (active ? Design.houseYellow:Design.ink).setFill();path.fill()
        let text=Design.attributed("Drop Here",.body,colour:active ? Design.ink:Design.card)
        text.draw(x:c-text.size().width/2,baseline:16)
    }
}

final class WorkspaceDragShade:NSView {
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect){NSColor.black.withAlphaComponent(0.18).setFill();bounds.fill()}
}
