import AppKit

/// Scrolling moves content under a stationary pointer; only a real pointer move may reopen a halo.
struct HoverScrollGate {
    private var pointer:NSPoint?
    mutating func suppress(at point:NSPoint){pointer=point}
    mutating func allows(at point:NSPoint)->Bool {
        guard let pointer else{return true}
        guard abs(point.x-pointer.x)>0.5 || abs(point.y-pointer.y)>0.5 else{return false}
        self.pointer=nil;return true
    }
}

/// A named destination retains its real palette spectrum and the existing controller operation.
struct HaloGalleryItem {
    let id:String, name:String, path:String, colours:[NSColor], count:Int, favourite:Bool
    let run:()->Void
}
struct HaloGalleryRequest {
    let title:String, source:String, commit:String, items:[HaloGalleryItem]
    var sourceColours:[NSColor]=[]
    var create:(label:String,run:()->Void)? = nil
}

/// The destination browser replaces the dial at the same screen centre, never beside it.
final class HaloDestinationGallery: NSObject, NSSearchFieldDelegate {
    static let pageSize=100
    private final class GalleryPanel:NSPanel {
        override var canBecomeKey:Bool{true}
        var escape:(()->Void)?
        override func cancelOperation(_ sender:Any?){escape?()}
    }
    private final class Ground:NSView {
        override var isFlipped:Bool{true}
        override func draw(_ rect:NSRect){Design.card.setFill();bounds.fill();Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()}
    }
    private final class SourceSpectrum:NSView {
        var colours:[NSColor]=[]
        override func draw(_ rect:NSRect){SwissDropdown.drawSpectrum(colours,in:bounds)}
    }
    private final class Tile:NSButton {
        let item:HaloGalleryItem
        var run:(()->Void)?
        var picked=false {didSet{needsDisplay=true}}
        private var hovered=false
        init(_ item:HaloGalleryItem){self.item=item;super.init(frame:.zero);isBordered=false;target=self;action=#selector(choose);setAccessibilityLabel(item.name+", "+item.path+", \(item.count) Colours");toolTip=item.name+"\n"+item.path}
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool{true}
        @objc private func choose(){run?()}
        override func accessibilityValue()->Any?{picked ? "Selected":"Not Selected"}
        override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.inVisibleRect,.mouseEnteredAndExited,.activeInKeyWindow],owner:self))}
        override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
        override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
        override func draw(_ rect:NSRect){
            (hovered || picked ? Design.mist:Design.card).setFill();bounds.fill()
            SwissDropdown.drawSpectrum(item.colours,in:NSRect(x:0,y:0,width:bounds.width,height:52))
            Design.attributed(item.name,.bodyStrong).draw(x:8,baseline:72,width:bounds.width-16)
            Design.attributed(item.path,.caption).draw(x:8,baseline:94,width:bounds.width-16)
            Design.attributed("\(item.count) Colours"+(item.favourite ? " · Favourite":""),.caption).draw(x:8,baseline:114,width:bounds.width-16)
            (picked ? Design.houseYellow:Design.rule).setStroke();let edge=NSBezierPath(rect:bounds.insetBy(dx:picked ? 1.5:0.5,dy:picked ? 1.5:0.5));edge.lineWidth=picked ? 3:1;edge.stroke()
            if window?.firstResponder === self{Design.ink.setStroke();NSBezierPath(rect:bounds.insetBy(dx:5,dy:5)).stroke()}
        }
    }
    private let panel=GalleryPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private let ground=Ground(),document=Ground(),scroll=FittedScrollView()
    private let title=Design.text("",.heading),source=Design.text("",.body),status=Design.text("Choose A Destination",.caption),range=Design.text("",.caption)
    private let sourceSpectrum=SourceSpectrum()
    private let search=NSSearchField()
    private let filter=SwissDropdown("",value:"All Destinations",options:["All Destinations","Favourites","Recent"],allowsOwn:false,width:180)
    private let back=SwissButton("Halo",.quiet),commit=SwissButton("Copy Here",.primary),previous=SwissButton("Previous",.quiet),next=SwissButton("Next",.quiet),create=SwissButton("New Palette…",.quiet)
    private let recentKey="halo.destinationGallery.recent"
    private var recent:[String]{UserDefaults.standard.stringArray(forKey:recentKey) ?? []}
    private let request:HaloGalleryRequest
    private var tiles:[Tile]=[],page=0,selected:String?,monitor:Any?,resign:NSObjectProtocol?
    var onBack:(()->Void)?,onCancel:(()->Void)?,onCommit:((()->Void)->Void)?
    init(_ request:HaloGalleryRequest){
        self.request=request;super.init()
        panel.contentView=ground;panel.isReleasedWhenClosed=false;panel.backgroundColor=Design.card;panel.hasShadow=true
        panel.escape={ [weak self] in self?.onBack?() }
        title.stringValue=request.title;source.stringValue=request.source;source.toolTip=request.source;sourceSpectrum.colours=request.sourceColours;sourceSpectrum.setAccessibilityElement(true);sourceSpectrum.setAccessibilityRole(.image);sourceSpectrum.setAccessibilityLabel("Source Spectrum: "+request.source);commit.title=request.commit;commit.isEnabled=false
        search.placeholderString="Search All Destinations";search.font=Design.Text.body.font();search.delegate=self;search.setAccessibilityLabel("Search All Destinations")
        for view in [title,source,sourceSpectrum,status,range,search,filter,back,commit,previous,next,create,scroll] as [NSView]{ground.addSubview(view)}
        scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.drawsBackground=false;scroll.documentView=document
        back.target=self;back.action=#selector(goBack);commit.target=self;commit.action=#selector(accept)
        previous.target=self;previous.action=#selector(prev);next.target=self;next.action=#selector(nextPage)
        create.target=self;create.action=#selector(makeNew);create.isHidden=request.create == nil;create.title=request.create?.label ?? "New Palette…"
        filter.onChange={ [weak self] _ in self?.page=0;self?.rebuild() }
        rebuild()
    }
    deinit{dismiss()}
    func open(over frame:NSRect,in host:NSWindow){
        let screen=host.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let width=min(640,max(280,screen.width-32)),height=min(600,max(300,screen.height-48))
        let x=min(max(screen.minX+16,frame.midX-width/2),screen.maxX-width-16),y=min(max(screen.minY+24,frame.midY-height/2),screen.maxY-height-24)
        panel.setFrame(NSRect(x:x,y:y,width:width,height:height),display:false);layout();host.addChildWindow(panel,ordered:.above);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(search)
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]){ [weak self] event in
            guard let self else{return event}
            if event.type == .keyDown,event.keyCode == 53 {
                if !self.filter.overlayWindows.isEmpty {self.filter.dismissOverlay();return nil}
                self.onBack?();return nil
            }
            if event.type != .keyDown,event.window !== self.panel,!self.filter.overlayWindows.contains(where:{$0 === event.window}){self.onCancel?()}
            return event
        }
        resign=NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main){ [weak self] _ in self?.onCancel?() }
    }
    func dismiss(){filter.dismissOverlay();if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil;if let resign{NotificationCenter.default.removeObserver(resign)};resign=nil;panel.parent?.removeChildWindow(panel);panel.orderOut(nil)}
    private var filtered:[HaloGalleryItem]{
        let q=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),recent=self.recent
        var list=request.items.filter{(filter.text != "Favourites" || $0.favourite) && (filter.text != "Recent" || recent.contains($0.path+"|"+$0.id)) && (q.isEmpty || ($0.name+" "+$0.path).localizedCaseInsensitiveContains(q))}
        if filter.text == "Recent" {list.sort{(recent.firstIndex(of:$0.path+"|"+$0.id) ?? Int.max)<(recent.firstIndex(of:$1.path+"|"+$1.id) ?? Int.max)}}
        return list
    }
    private func rebuild(){
        let list=filtered;page=min(page,max(0,(list.count-1)/Self.pageSize));let first=page*Self.pageSize,last=min(first+Self.pageSize,list.count)
        tiles.forEach{$0.removeFromSuperview()};tiles=list[first..<last].map{item in let tile=Tile(item);tile.picked=item.id==selected;tile.run={ [weak self] in self?.select(item.id) };document.addSubview(tile);return tile}
        range.stringValue=list.isEmpty ? "No Matching Destinations":"\(first+1)–\(last) Of \(list.count)"
        previous.isEnabled=page>0;next.isEnabled=last<list.count
        if !list.contains(where:{$0.id==selected}){selected=nil;commit.isEnabled=false;status.stringValue="Choose A Destination"}
        layout();scroll.contentView.scroll(to:.zero);scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func select(_ id:String){selected=id;tiles.forEach{$0.picked=$0.item.id==id};commit.isEnabled=true;if let item=request.items.first(where:{$0.id==id}){status.stringValue=item.path+" / "+item.name;status.toolTip=status.stringValue}}
    private func layout(){
        let w=ground.bounds.width,h=ground.bounds.height
        title.frame=NSRect(x:16,y:14,width:max(1,w-130),height:24);source.frame=NSRect(x:16,y:42,width:max(1,w-32),height:22);back.frame=NSRect(x:w-90,y:14,width:74,height:32)
        let filterWidth=min(180,w*0.36)
        sourceSpectrum.frame=NSRect(x:16,y:72,width:w-32,height:18)
        search.frame=NSRect(x:16,y:112,width:max(1,w-filterWidth-44),height:28);filter.frame=NSRect(x:w-filterWidth-16,y:97,width:filterWidth,height:52)
        scroll.frame=NSRect(x:1,y:152,width:w-2,height:max(20,h-252));scroll.tile()
        previous.frame=NSRect(x:12,y:h-96,width:100,height:32);next.frame=NSRect(x:w-100,y:h-96,width:88,height:32);range.frame=NSRect(x:116,y:h-87,width:max(1,w-224),height:20)
        status.frame=NSRect(x:16,y:h-60,width:w-32,height:20);create.frame=NSRect(x:16,y:h-36,width:140,height:32);commit.frame=NSRect(x:w-140,y:h-36,width:124,height:32)
        let available=scroll.contentView.bounds.width,columns=max(1,Int((available-24)/180)),gap:CGFloat=12,tileWidth=max(1,(available-24-CGFloat(columns-1)*gap)/CGFloat(columns))
        for (i,tile) in tiles.enumerated(){tile.frame=NSRect(x:12+CGFloat(i%columns)*(tileWidth+gap),y:12+CGFloat(i/columns)*140,width:tileWidth,height:128)}
        document.frame=NSRect(x:0,y:0,width:available,height:max(scroll.contentView.bounds.height,24+CGFloat((tiles.count+columns-1)/columns)*140))
    }
    func controlTextDidChange(_ notification:Notification){page=0;rebuild()}
    @objc private func goBack(){onBack?()}
    @objc private func prev(){page=max(0,page-1);rebuild()}
    @objc private func nextPage(){page+=1;rebuild()}
    @objc private func makeNew(){if let create=request.create{onCommit?(create.run)}}
    @objc private func accept(){guard let id=selected,let item=filtered.first(where:{$0.id==id}) else{return};let key=item.path+"|"+item.id;UserDefaults.standard.set(Array(([key]+recent.filter{$0 != key}).prefix(30)),forKey:recentKey);onCommit?(item.run)}
}

extension HaloGalleryRequest {
    /// Resolve destinations from the existing action tree, preserving its controller callbacks.
    static func destinations(_ actions:[HaloAction],title:String,source:String,commit:String,library:LibraryController,sourceColours:[NSColor]=[])->HaloGalleryRequest {
        let lib=library.library
        var items:[HaloGalleryItem]=[],create:(label:String,run:()->Void)?
        func visit(_ actions:[HaloAction],path:String){
            for action in actions where !action.disabled {
                if let children=action.children {visit(children(),path:path.isEmpty ? action.label:path+" / "+action.label);continue}
                guard let id=UUID(uuidString:action.id) else {
                    if action.id == "new" {create=(action.label,action.onSelect)}
                    else if action.id == "loose" {items.append(.init(id:action.id,name:action.label,path:library.catalogue,colours:[],count:0,favourite:false,run:action.onSelect))}
                    continue
                }
                let palette=lib.swatch(id),project=lib.project(id)
                guard palette != nil || project != nil else{continue}
                let palettes=palette.map{[$0]} ?? lib.palettes(in:id)
                let entries=palettes.flatMap{$0.entries}
                let colours=entries.map{lib.definition(of:$0.hex)?.master.display ?? Design.hex($0.hex)}
                var parent=palette?.projectID.flatMap{lib.project($0)?.name} ?? (palette != nil ? "Library":path)
                if let palette,let projectID=palette.projectID,let bucket=palette.bucketID,let node=SchemaTrial.rows(of:SchemaTrial.schema(for:projectID)).first(where:{$0.node.id==bucket})?.node {parent+=" / "+node.name}
                items.append(.init(id:action.id,name:palette?.name ?? project!.name,path:[library.catalogue,parent].filter{!$0.isEmpty}.joined(separator:" / "),colours:colours,count:entries.count,favourite:palettes.contains{$0.favourite},run:action.onSelect))
            }
        }
        visit(actions,path:"")
        return .init(title:title,source:source,commit:commit,items:items,sourceColours:sourceColours,create:create)
    }
}
