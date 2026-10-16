import AppKit

/// Versioned catalogue templates describe views, never copies of the assets being viewed.
struct WorkspaceLayoutTemplate:Codable,Equatable,Identifiable {
    var id=UUID()
    var name:String
    var notes=""
    var updatedAt=Date()
    var includes=Includes()
    var state:State
    struct Includes:Codable,Equatable {var pages=true,rails=true,settings=true,window=true}
    struct Page:Codable,Equatable {
        var columns:Int=5,list=false,format="hex",rating:Int?,flag:String?,order="Newest",filter:String?,selectedColour:String?
        var metadataOpen=false,metadata:[MetadataFilterColumn]=[]
        var scrollX:Double=0,scrollY:Double=0,delta=false
    }
    struct Tab:Codable,Equatable {var id:UUID,primary:Bool,route:StudioFrame.Place?,source:StudioFrame.Place,view:Page?}
    indirect enum Node:Codable,Equatable {
        case pane(id:UUID,primary:Bool,selected:UUID?,tabs:[Tab])
        case split(vertical:Bool,ratio:Double,first:Node,second:Node)
        var paneCount:Int {switch self{case .pane:return 1;case .split(_,_,let a,let b):return a.paneCount+b.paneCount}}
        var tabCount:Int {switch self{case .pane(_,_,_,let tabs):return tabs.count;case .split(_,_,let a,let b):return a.tabCount+b.tabCount}}
    }
    struct Panel:Codable,Equatable {var id:String,rail:Int,order:Int,closed:Bool,height:Double}
    struct Rect:Codable,Equatable {var x:Double,y:Double,width:Double,height:Double
        init(_ rect:NSRect){x=rect.minX;y=rect.minY;width=rect.width;height=rect.height}
        var rect:NSRect{NSRect(x:x,y:y,width:width,height:height)}
    }
    struct State:Codable,Equatable {
        var version=1
        var tree:Node
        var activePane:UUID
        var panels:[Panel]=[]
        var rails:[Double]=[1,1,0]
        var expanded=false,pageExpanded=false
        var settings:[String:String]=[:]
        var histogram:[Int]=[]
        var printProfile:PrintProfileSettings?
        var window:Rect?
    }
}

/// One state/persistence boundary. The native file manager preserves unknown catalogue fields.
enum Layout_Handler {
    enum Scope {case app,catalogue}
    static func pageTemplate(_ original:WorkspaceLayoutTemplate.State)->WorkspaceLayoutTemplate.State {
        func slots(_ node:WorkspaceLayoutTemplate.Node)->WorkspaceLayoutTemplate.Node {
            switch node {
            case .pane(let id,let primary,_,let tabs):
                let empty=tabs.map{WorkspaceLayoutTemplate.Tab(id:$0.id,primary:$0.primary,route:nil,source:.catalogue,view:nil)}
                return .pane(id:id,primary:primary,selected:empty.first?.id,tabs:empty)
            case .split(let vertical,let ratio,let a,let b):return .split(vertical:vertical,ratio:ratio,first:slots(a),second:slots(b))
            }
        }
        return .init(tree:slots(original.tree),activePane:original.activePane)
    }
    static func validate(_ state:WorkspaceLayoutTemplate.State)throws {
        guard state.version == 1,state.tree.paneCount > 0,state.tree.paneCount <= 32,state.tree.tabCount > 0,state.tree.tabCount <= 128 else{throw failure("This layout is unsupported or has too many panels.")}
        guard state.rails.count == 3,state.rails.allSatisfy({$0.isFinite && (0...1).contains($0)}),state.panels.allSatisfy({$0.height.isFinite && $0.height >= 0 && (0...3).contains($0.rail) && $0.order >= 0}) else{throw failure("This layout has invalid rail settings.")}
        var panes=Set<UUID>(),tabs=Set<UUID>(),primaryPanes=0,primaryTabs=0
        func visit(_ node:WorkspaceLayoutTemplate.Node,depth:Int)throws {
            guard depth < 16 else{throw failure("This layout is nested too deeply.")}
            switch node {
            case .pane(let id,let primary,let selected,let records):
                guard panes.insert(id).inserted,!records.isEmpty,records.contains(where:{$0.id == selected}) else{throw failure("This layout has an invalid panel.")}
                if primary{primaryPanes+=1}
                for tab in records{if tab.primary{primaryTabs+=1};guard tabs.insert(tab.id).inserted else{throw failure("This layout has repeated tabs.")};if let view=tab.view{guard view.scrollX.isFinite,view.scrollY.isFinite else{throw failure("This layout has invalid view settings.")}}}
            case .split(_,let ratio,let a,let b):guard ratio.isFinite,ratio > 0,ratio < 1 else{throw failure("This layout has an invalid split.")};try visit(a,depth:depth+1);try visit(b,depth:depth+1)
            }
        }
        try visit(state.tree,depth:0);guard panes.contains(state.activePane),primaryPanes <= 1,primaryTabs <= 1 else{throw failure("This layout has an invalid main panel.")}
    }
    static func read(_ url:URL,scope:Scope,appData:AppDataStore = .current)throws->[WorkspaceLayoutTemplate] {
        if scope == .app {
            let object=try appData.read()["workspaceLayouts"] ?? []
            return try ColourFiles.decoder().decode([WorkspaceLayoutTemplate].self,from:JSONSerialization.data(withJSONObject:object))
        }
        let data=try Handler_File_Manager.shared.read(url)
        guard let file=CatalogueTree.decode(data) else{throw failure("The catalogue layouts could not be read.")}
        return file.workspaceLayouts ?? []
    }
    static func write(_ layouts:[WorkspaceLayoutTemplate],to url:URL,scope:Scope,appData:AppDataStore = .current)throws {
        if scope == .app {
            let object=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(layouts))
            try appData.update{$0["workspaceLayouts"]=object};return
        }
        let data=try Handler_File_Manager.shared.read(url)
        guard var file=CatalogueTree.decode(data) else{throw failure("The catalogue layouts could not be read.")}
        file.workspaceLayouts=layouts;file.changedAt=Date()
        try Handler_File_Manager.shared.write(ColourFiles.encoder().encode(file),to:url,expected:FileRevision(digest:Sharing.sha256(data)))
    }
    static func isSetting(_ key:String)->Bool {
        let exact:Set<String>=["workspace.bloomOrder","workspace.channelProfile","workspace.previewChannel","workspace.targetPress","workspace.targetPaperWhite","workspace.targetKOnly","Workspace.Library.PaletteOrder","theme.preset","Workspace.Library.Sections.Favs.Collapsed","Workspace.Library.Sections.Catalogues.Collapsed","Workspace.Library.Sections.Folders.Collapsed","Workspace.Library.Sections.MyPalettes.Collapsed"]
        return exact.contains(key) || key.hasPrefix("Workspace.CatalogueTree.Expanded.") || key.hasPrefix("rails.shut.")
    }
    static func captureSettings()->[String:String] {
        var values=preferences.dictionaryRepresentation()
        if let manifest=try? AppDataStore.current.read(),let settings=manifest["settings"] as? [String:Any]{values.merge(settings,uniquingKeysWith:{_,new in new})}
        return values.filter{isSetting($0.key)}.reduce(into:[:]){out,pair in
            if let data=try? JSONSerialization.data(withJSONObject:pair.value,options:[.fragmentsAllowed,.sortedKeys]){out[pair.key]=String(data:data,encoding:.utf8)}
        }
    }
    static func restoreSettings(_ saved:[String:String]) {
        let keys=Set(captureSettings().keys).union(saved.keys).filter(isSetting)
        for key in keys {
            let value=saved[key].flatMap{$0.data(using:.utf8)}.flatMap{try? JSONSerialization.jsonObject(with:$0,options:[.fragmentsAllowed])}
            AppPreferences.shared.set(value is NSNull ? nil:value,forKey:key)
        }
    }
}

/// The single header trigger owns a wide house dropdown, with independent scrollable template lists.
final class WorkspaceLayoutControl:NSView,Overlay {
    private let label=Design.text("Layout",.bodyStrong)
    private let button=DropdownButton()
    private var panel:NSPanel?
    private var columns:[WorkspaceLayoutColumn]=[]
    var catalogueURL:URL?{didSet{if oldValue != catalogueURL{dismissOverlay();selectedName="Custom Layout"}}}
    var capture:(()->WorkspaceLayoutTemplate.State?)?
    var restore:((WorkspaceLayoutTemplate,Layout_Handler.Scope)throws->Void)?
    var selectedName="Custom Layout"{didSet{button.title=selectedName}}
    var overlayWindows:[NSWindow]{panel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func containsOverlayEvent(_ event:NSEvent)->Bool {
        if event.window === panel{return true}
        return event.window === window && bounds.contains(convert(event.locationInWindow,from:nil))
    }
    func dismissOverlay(){if let panel{panel.parent?.removeChildWindow(panel);panel.orderOut(nil)};panel=nil;columns=[];Overlays.closed(self)}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);addSubview(label);addSubview(button);button.title=selectedName;button.target=self;button.action=#selector(toggle);button.setAccessibilityLabel("Layout");button.toolTip="Saved App And Catalogue Layouts"}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();let width=ceil(label.intrinsicContentSize.width)+8;label.frame=NSRect(x:0,y:(bounds.height-label.intrinsicContentSize.height)/2,width:width,height:label.intrinsicContentSize.height);button.frame=NSRect(x:width+12,y:0,width:max(0,bounds.width-width-12),height:bounds.height)}
    @objc private func toggle(){if panel != nil{dismissOverlay()}else{open()}}
    func open(){openChooser()}
    private func openChooser(){
        guard let window,let url=catalogueURL else{return};dismissOverlay()
        var items:[String]=[],entries:[Int:(WorkspaceLayoutTemplate,Layout_Handler.Scope)]=[:],symbols:[Int:(String,NSColor)]=[:]
        for scope in [Layout_Handler.Scope.app,.catalogue]{
            if !items.isEmpty{items.append(SwissDropdown.MenuPanel.divider)}
            items.append(SwissDropdown.MenuPanel.heading(scope == .app ? "App Layouts":"Catalogue Layouts"))
            do{
                let records=try Layout_Handler.read(url,scope:scope)
                if records.isEmpty{items.append(SwissDropdown.MenuPanel.heading("No Saved Layouts"))}
                for record in records{let index=items.count;items.append(record.name);entries[index]=(record,scope);symbols[index]=(scope == .app ? "rectangle.3.group":"rectangle.split.2x1",Design.ink)}
            }catch{items.append(SwissDropdown.MenuPanel.heading("Layouts Unavailable"));FileIncidentCoordinator.report(error,at:scope == .app ? AppDataStore.current.url:url)}
        }
        items.append(SwissDropdown.MenuPanel.divider);let manage=items.count;items.append("Manage Layouts…")
        let menu=SwissDropdown.MenuPanel(items:items,chosen:selectedName,width:max(300,button.bounds.width)){[weak self] index in
            guard let self else{return};self.dismissOverlay()
            if index == manage{self.openManager();return}
            guard let (record,scope)=entries[index] else{return}
            do{try self.restore?(record,scope);self.selectedName=record.name}catch{FileIncidentCoordinator.report(error,at:scope == .app ? AppDataStore.current.url:url)}
        }
        menu.setLeadingSymbols(symbols)
        let trigger=window.convertToScreen(button.convert(button.bounds,to:nil))
        menu.place(anchoredTo:NSRect(x:trigger.maxX-menu.frame.width,y:trigger.minY,width:menu.frame.width,height:trigger.height),within:window)
        window.addChildWindow(menu,ordered:.above);panel=menu;Overlays.opened(self);menu.orderFront(nil)
    }
    private func openManager(){
        guard let window,let url=catalogueURL else{return};dismissOverlay()
        let width=min(760,max(360,window.frame.width-32)),height=min(540,max(300,window.frame.height-120))
        let popup=Panel(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        popup.isOpaque=false;popup.backgroundColor = .clear;popup.hasShadow=true
        let surface=Surface(frame:NSRect(x:0,y:0,width:width,height:height));popup.contentView=surface
        let trigger=window.convertToScreen(button.convert(button.bounds,to:nil))
        let anchor=NSRect(x:trigger.maxX-width,y:trigger.minY,width:width,height:trigger.height)
        let screen=window.screen?.visibleFrame ?? window.frame
        let placement=SwissDropdown.MenuPanel.placement(anchor:anchor,size:popup.frame.size,within:screen.intersection(window.frame).insetBy(dx:8,dy:8))
        popup.setContentSize(NSSize(width:width,height:placement.height));surface.frame=NSRect(x:0,y:0,width:width,height:placement.height)
        for (i,scope) in [Layout_Handler.Scope.app,.catalogue].enumerated(){
            let column=WorkspaceLayoutColumn(scope:scope,url:url)
            column.selectSavedName(selectedName)
            column.capture={ [weak self] in self?.capture?() }
            column.apply={ [weak self] record in guard let self else{return};try self.restore?(record,scope);self.selectedName=record.name }
            let scroll=FittedScrollView(frame:NSRect(x:CGFloat(i)*width/2,y:0,width:width/2,height:placement.height));scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
            column.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(360,placement.height));scroll.documentView=column;surface.addSubview(scroll);columns.append(column)
        }
        popup.setFrameOrigin(placement.origin);window.addChildWindow(popup,ordered:.above);panel=popup;Overlays.opened(self);popup.makeKeyAndOrderFront(nil)
    }
    private final class Surface:NSView {
        override func draw(_ dirtyRect:NSRect){Design.card.setFill();bounds.fill();Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke();Design.rule.setFill();NSRect(x:bounds.midX,y:0,width:1,height:bounds.height).fill()}
    }
    private final class Panel:NSPanel {override var canBecomeKey:Bool{true}}
}

private final class WorkspaceLayoutColumn:NSView,NSTableViewDataSource,NSTableViewDelegate {
    let scope:Layout_Handler.Scope,url:URL
    private var records:[WorkspaceLayoutTemplate]=[]
    private var selected:UUID?
    private var removed:WorkspaceLayoutTemplate?
    private let title: NSTextField,subtitle:NSTextField
    private let scroll=FittedScrollView(),table=NSTableView()
    private let name=LayoutField(frame:.zero)
    private let status=Design.text("",.caption,colour:Design.quiet,wraps:true)
    private let save=SwissButton("Save New",.secondary)
    private let undo=SwissButton("Undo Remove",.secondary)
    private let current=LayoutEntry(frame:.zero)
    private let currentTitle=Design.text("Selected Layout",.caption,colour:Design.quiet)
    private var renaming:UUID?
    var capture:(()->WorkspaceLayoutTemplate.State?)?
    var apply:((WorkspaceLayoutTemplate)throws->Void)?
    override var isFlipped:Bool{true}
    init(scope:Layout_Handler.Scope,url:URL){
        self.scope=scope;self.url=url
        title=Design.text(scope == .app ? "App Layouts":"Catalogue Layouts",.bodyStrong)
        subtitle=Design.text(scope == .app ? "Whole Workspace":"Page Splits",.caption,colour:Design.quiet)
        super.init(frame:.zero)
        for view in [title,subtitle,scroll,name,status,save,undo,current,currentTitle] as [NSView]{addSubview(view)}
        name.font=Design.font(Design.Text.body.size,.bold);name.textColor=Design.ink;name.drawsBackground=false;name.isBordered=false;name.focusRingType = .none
        name.placeholderAttributedString=NSAttributedString(string:"New Layout Name",attributes:[.font:Design.font(Design.Text.body.size,.bold),.foregroundColor:Design.quiet]);name.setAccessibilityLabel("Layout Name")
        name.target=self;name.action=#selector(saveName)
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("layout"));table.addTableColumn(column);table.headerView=nil;table.rowHeight=32;table.intercellSpacing = .zero;table.backgroundColor=Design.card;table.selectionHighlightStyle = .none;table.dataSource=self;table.delegate=self;table.setAccessibilityLabel(scope == .app ? "App Layout Templates":"Catalogue Layout Templates")
        scroll.documentView=table;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        save.target=self;save.action=#selector(saveName);undo.target=self;undo.action=#selector(undoRemove)
        do{records=try Layout_Handler.read(url,scope:scope);status.stringValue=records.isEmpty ? "No Saved Layouts":"Select A Layout To Apply It"}catch{status.stringValue=error.localizedDescription;save.isEnabled=false}
        table.reloadData();refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    func selectSavedName(_ value:String){selected=records.first{$0.name == value}?.id;refresh()}
    func numberOfRows(in tableView:NSTableView)->Int{records.count}
    private func configure(_ view:LayoutEntry,record:WorkspaceLayoutTemplate){
        view.label.stringValue=record.name;view.mark.stringValue=scope == .app ? "▣":"◫"
        view.onAction={ [weak self] action in self?.rowAction(action,id:record.id) }
    }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{let view=LayoutEntry(frame:.zero);configure(view,record:records[row]);return view}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView?{LayoutRow()}
    func tableViewSelectionDidChange(_ notification:Notification){
        guard records.indices.contains(table.selectedRow) else{return};let record=records[table.selectedRow];selected=record.id
        do{try apply?(record);status.stringValue="Applied · \(record.state.tree.paneCount) Panels"}catch{status.stringValue=error.localizedDescription};refresh()
    }
    private func refresh(){
        let record=records.first{$0.id == selected};current.isHidden=record == nil
        currentTitle.stringValue=record == nil ? "Select A Saved Layout":"Selected Layout"
        if let record{configure(current,record:record)}
        undo.isHidden=removed == nil;needsLayout=true;needsDisplay=true
    }
    private func persist(_ next:[WorkspaceLayoutTemplate],selection:UUID?){
        do{try Layout_Handler.write(next,to:url,scope:scope);records=next;selected=selection;table.reloadData();status.stringValue="Saved";refresh()}catch{status.stringValue=error.localizedDescription;FileIncidentCoordinator.report(error,at:scope == .app ? AppDataStore.current.url:url)}
    }
    @objc private func saveName(){
        window?.makeFirstResponder(nil)
        let title=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty else{status.stringValue="Give This Layout A Name";window?.makeFirstResponder(name);return}
        if let id=renaming,let index=records.firstIndex(where:{$0.id == id}){
            var next=records;next[index].name=title;next[index].updatedAt=Date();persist(next,selection:id);renaming=nil;save.title="Save New";name.stringValue="";return
        }
        guard let state=capture?() else{status.stringValue="Open A Library Page To Save A Layout";return}
        let record=WorkspaceLayoutTemplate(name:title,notes:"",state:scope == .catalogue ? Layout_Handler.pageTemplate(state):state)
        persist(records+[record],selection:record.id);name.stringValue=""
    }
    private func rowAction(_ action:Int,id:UUID){
        guard let index=records.firstIndex(where:{$0.id == id}) else{return}
        selected=id
        switch action{
        case 0:
            guard let state=capture?() else{return};var next=records
            next[index].state=scope == .catalogue ? Layout_Handler.pageTemplate(state):state;next[index].updatedAt=Date();persist(next,selection:id)
        case 1:
            renaming=id;name.stringValue=records[index].name;save.title="Rename";refresh();window?.makeFirstResponder(name);name.selectText(nil)
        default:
            removed=records[index];var next=records;next.remove(at:index);persist(next,selection:nil)
        }
    }
    @objc private func undoRemove(){guard let removed else{return};self.removed=nil;persist(records+[removed],selection:removed.id)}
    override func layout(){super.layout();let w=max(0,bounds.width-32)
        title.frame=NSRect(x:16,y:16,width:w,height:20);subtitle.frame=NSRect(x:16,y:40,width:w,height:20)
        currentTitle.frame=NSRect(x:16,y:80,width:w,height:20);current.frame=NSRect(x:0,y:104,width:bounds.width,height:32)
        let listHeight=max(32,bounds.height-268);scroll.frame=NSRect(x:0,y:148,width:bounds.width,height:listHeight)
        table.tableColumns.first?.width=scroll.contentSize.width;table.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(listHeight,CGFloat(records.count)*32)))
        let y=scroll.frame.maxY+12;name.frame=NSRect(x:16,y:y+1,width:w,height:34)
        save.frame=NSRect(x:16,y:y+44,width:w/2,height:32);undo.frame=NSRect(x:16+w/2,y:y+44,width:w/2,height:32)
        status.frame=NSRect(x:16,y:y+80,width:w,height:32)
    }
    override func draw(_ dirtyRect:NSRect){Design.rule.setFill();for y in [CGFloat(68),CGFloat(140),name.frame.minY-1,name.frame.maxY+1]{NSRect(x:16,y:y,width:bounds.width-32,height:1).fill()}}
    private final class LayoutEntry:NSView {
        let mark=Design.text("",.body),label=Design.text("",.body)
        private var buttons:[RowIcon]=[]
        var onAction:((Int)->Void)?
        override init(frame:NSRect){super.init(frame:frame);addSubview(mark);addSubview(label);label.lineBreakMode = .byTruncatingTail
            for (index,item) in [("arrow.clockwise","Update Layout"),("pencil","Rename Layout"),("trash","Remove Layout")].enumerated(){let button=RowIcon(symbol:item.0,label:item.1);button.tag=index;button.target=self;button.action=#selector(performAction(_:));addSubview(button);buttons.append(button)}
        }
        required init?(coder:NSCoder){fatalError()}
        @objc private func performAction(_ sender:NSButton){onAction?(sender.tag)}
        override func layout(){super.layout();let h=ceil(label.intrinsicContentSize.height),y=(bounds.height-h)/2
            mark.frame=NSRect(x:16,y:y,width:20,height:h);label.frame=NSRect(x:44,y:y,width:max(0,bounds.width-44-112),height:h)
            for (i,button) in buttons.enumerated(){button.frame=NSRect(x:bounds.width-16-96+CGFloat(i)*32,y:(bounds.height-28)/2,width:32,height:28)}
        }
    }
    private final class RowIcon:NSButton {
        private var hovered=false
        init(symbol:String,label:String){super.init(frame:.zero);isBordered=false;title="";image=NSImage(systemSymbolName:symbol,accessibilityDescription:label);imagePosition = .imageOnly;contentTintColor=Design.ink;toolTip=label;setAccessibilityLabel(label)}
        required init?(coder:NSCoder){fatalError()}
        override func draw(_ dirtyRect:NSRect){if hovered{Design.mist.setFill();bounds.fill()};super.draw(dirtyRect)}
        override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
        override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
        override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
    private final class LayoutField:NSTextField {
        override init(frame:NSRect){super.init(frame:frame);cell=Cell(textCell:"");isEditable=true;isSelectable=true;focusRingType = .none}
        required init?(coder:NSCoder){fatalError()}
        private final class Cell:NSTextFieldCell {
            private let editor=BlockEditor(frame:.zero)
            override func fieldEditor(for controlView:NSView)->NSTextView?{editor.isFieldEditor=true;editor.isRichText=false;editor.drawsBackground=false;editor.font=font;editor.textColor=Design.ink;editor.insertionPointColor = .clear;editor.focusRingType = .none;editor.selectedTextAttributes=[.backgroundColor:Design.ink,.foregroundColor:Design.card];return editor}
            override func drawingRect(forBounds rect:NSRect)->NSRect{
                var result=super.drawingRect(forBounds:rect);let font=font ?? Design.Text.bodyStrong.font(),h=min(result.height,ceil(font.ascender-font.descender+font.leading)+2)
                result.origin.y+=(result.height-h)/2;result.size.height=h;return result
            }
            override func edit(withFrame rect:NSRect,in controlView:NSView,editor textObj:NSText,delegate:Any?,event:NSEvent?){super.edit(withFrame:drawingRect(forBounds:rect),in:controlView,editor:textObj,delegate:delegate,event:event)}
            override func select(withFrame rect:NSRect,in controlView:NSView,editor textObj:NSText,delegate:Any?,start:Int,length:Int){super.select(withFrame:drawingRect(forBounds:rect),in:controlView,editor:textObj,delegate:delegate,start:start,length:length)}
        }
        private final class BlockEditor:NSTextView {
            private var pulse:Timer?,visibleCaret=true
            override func becomeFirstResponder()->Bool{let accepted=super.becomeFirstResponder();if accepted{startPulse()};return accepted}
            override func resignFirstResponder()->Bool{let accepted=super.resignFirstResponder();if accepted{pulse?.invalidate();pulse=nil;needsDisplay=true};return accepted}
            deinit{pulse?.invalidate()}
            private func startPulse(){
                pulse?.invalidate();visibleCaret=true
                let timer=Timer(timeInterval:0.5,repeats:true){[weak self] timer in
                    guard let self,self.window?.isVisible == true,self.window?.firstResponder === self else{timer.invalidate();self?.pulse=nil;return}
                    self.visibleCaret.toggle();self.needsDisplay=true
                };pulse=timer;RunLoop.main.add(timer,forMode:.common)
            }
            override func drawInsertionPoint(in rect:NSRect,color:NSColor,turnedOn flag:Bool){}
            override func draw(_ dirtyRect:NSRect){
                super.draw(dirtyRect)
                guard visibleCaret,let window,window.firstResponder === self,selectedRange().length == 0 else{return}
                let screen=firstRect(forCharacterRange:selectedRange(),actualRange:nil),caret=convert(window.convertFromScreen(screen),from:nil)
                let face=font ?? Design.Text.bodyStrong.font()
                let height=max(caret.height,ceil(face.ascender-face.descender))
                Design.ink.setFill();NSRect(x:caret.minX,y:caret.midY-height/2,width:7,height:height).fill()
            }
        }
    }
    private final class LayoutRow:NSTableRowView {
        private var hovered=false
        override func drawBackground(in dirtyRect:NSRect){if hovered && !isSelected{Design.mist.setFill();bounds.fill()}}
        override func drawSelection(in dirtyRect:NSRect){WorkspacePanelSurface.draw(in:bounds,selected:true)}
        override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
        override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
        override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
}
