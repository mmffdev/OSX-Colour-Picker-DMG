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

final class WorkspaceOutline: NSOutlineView {
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        if identifier.rawValue == "NSOutlineViewDisclosureButtonKey" {
            let button = WorkspaceDisclosure(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            button.identifier = identifier; button.setButtonType(.onOff); button.isBordered = false
            return button
        }
        return super.makeView(withIdentifier: identifier, owner: owner)
    }
}

final class WorkspacePanel: NSView {
    static let headerHeight: CGFloat = 34
    static let footerHeight: CGFloat = 18
    let panelID: String
    let content: NSView
    var preferredHeight: CGFloat
    var collapsed = false { didSet { disclosure.state = collapsed ? .off : .on; needsLayout = true; rail?.arrange() } }
    weak var rail: WorkspaceRail?
    private let contentScroll: NSScrollView?
    private let disclosure = WorkspaceDisclosure()
    private let titleButton: NSButton
    private let grip = PanelDragGrip()
    private let resizeGrip = PanelResizeGrip()
    var panelHeight: CGFloat { collapsed ? Self.headerHeight : preferredHeight }
    override var isFlipped: Bool { true }
    init(id: String, title: String, content: NSView, height: CGFloat) {
        panelID = id; self.content = content; preferredHeight = height
        contentScroll = content is WorkspaceInspector ? NSScrollView() : nil
        titleButton = NSButton(title: title, target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = Design.card.cgColor
        disclosure.setButtonType(.onOff); disclosure.state = .on; disclosure.isBordered = false
        disclosure.target = self; disclosure.action = #selector(toggle)
        disclosure.setAccessibilityLabel("Collapse or expand \(title)")
        titleButton.isBordered = false; titleButton.alignment = .left
        titleButton.font = Design.Text.bodyStrong.font(); titleButton.contentTintColor = Design.ink
        titleButton.target = self; titleButton.action = #selector(toggle)
        grip.panel = self; grip.setAccessibilityLabel("Move \(title) panel")
        grip.toolTip = "Drag to Rail1 or Rail2, above or below another panel"
        resizeGrip.panel = self; resizeGrip.toolTip = "Drag to resize \(title)"
        if let contentScroll {
            contentScroll.drawsBackground=false;contentScroll.hasVerticalScroller=true;contentScroll.autohidesScrollers=true
            contentScroll.documentView=content;addSubview(contentScroll)
        } else { addSubview(content) }
        [disclosure, titleButton, grip, resizeGrip].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func toggle() { collapsed.toggle() }
    override func layout() {
        super.layout()
        disclosure.frame = NSRect(x: 8, y: 9, width: 16, height: 16)
        titleButton.frame = NSRect(x: 30, y: 0, width: max(20,bounds.width-70), height: Self.headerHeight)
        grip.frame = NSRect(x: bounds.width-36, y: 0, width: 28, height: Self.headerHeight)
        content.isHidden = collapsed; contentScroll?.isHidden=collapsed; resizeGrip.isHidden = collapsed
        let viewport=NSRect(x:0,y:Self.headerHeight,width:bounds.width,height:max(0,bounds.height-Self.headerHeight-Self.footerHeight))
        if let contentScroll {
            contentScroll.frame=viewport
            content.frame=NSRect(x:0,y:0,width:contentScroll.contentSize.width,height:max(440,contentScroll.contentSize.height))
        } else { content.frame=viewport }
        resizeGrip.frame = NSRect(x: 0, y: bounds.height-Self.footerHeight, width: bounds.width, height: Self.footerHeight)
    }
    override func draw(_ dirtyRect: NSRect) {
        hairline(x: 0, y: Self.headerHeight-1, width: bounds.width)
        if !collapsed { hairline(x: 0, y: bounds.height-Self.footerHeight, width: bounds.width);hairline(x: 0, y: bounds.height-1, width: bounds.width) }
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
        guard !cancelled,let panel, let root=window?.contentView else{return}
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
        guard dragging,let panel else{return}
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
    override func mouseDown(with event:NSEvent) { startY=event.locationInWindow.y; startHeight=panel?.preferredHeight ?? 0 }
    override func mouseDragged(with event:NSEvent) {
        guard let panel else { return }
        panel.preferredHeight=max(140,min(max(140,panel.rail?.bounds.height ?? 1000),startHeight+startY-event.locationInWindow.y))
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
        NSRect(x:scroll.onLeft ? QuietScroller.lane:bounds.width-QuietScroller.lane-1,y:0,width:1,height:bounds.height).fill()
    }
    func add(_ panel:WorkspacePanel,at index:Int? = nil) {
        if let old=panel.rail { old.panels.removeAll{$0 === panel};old.arrange() }
        panel.removeFromSuperview();panels.insert(panel,at:min(index ?? panels.count,panels.count));panel.rail=self;stack.addSubview(panel);arrange()
    }
    override func layout(){super.layout();scroll.frame=bounds;arrange()}
    func arrange() {
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
