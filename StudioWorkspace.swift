import AppKit

/// The full-app shell uses the existing catalogue model; these views own presentation only.
final class WorkspaceCatalogues: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, WorkspaceRailAwareContent {
    var scrollbarOnLeft=false {didSet{if oldValue != scrollbarOnLeft {scroll.onLeft=scrollbarOnLeft;catalogueScroll.onLeft=scrollbarOnLeft;needsLayout=true}}}
    final class Cell: NSTableCellView {
        override func layout() {
            super.layout()
            imageView?.frame=NSRect(x:0,y:(bounds.height-16)/2,width:16,height:16)
            let height = textField?.intrinsicContentSize.height ?? 17
            textField?.frame=NSRect(x:24,y:(bounds.height-height)/2,width:max(20,bounds.width-24),height:height)
        }
    }
    final class Node: NSObject {
        let key: String, title: String, count: Int, place: StudioFrame.Place?, catalogue: String?, symbol: String
        var children: [Node] = []
        init(_ key: String, _ title: String, count: Int = 0, place: StudioFrame.Place? = nil, catalogue: String? = nil, symbol: String = "folder") {
            self.key=key; self.title=title; self.count=count; self.place=place; self.catalogue=catalogue; self.symbol=symbol
        }
    }
    private let outline = WorkspaceOutline(), scroll = WorkspacePanelScroll()
    private let catalogueList = WorkspaceOutline(), catalogueScroll = WorkspacePanelScroll()
    private var catalogueRoots: [Node] = []
    private var dividerY: CGFloat = 0
    private var roots: [Node] = [], expanded = Set<String>(), rebuilding = false
    private var current = ""
    var onPick: ((StudioFrame.Place)->Void)?
    var onCatalogue: ((String)->Void)?
    var onFilter: ((String)->Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer=true; layer?.backgroundColor=Design.card.cgColor
        for (tree, container, name) in [(catalogueList, catalogueScroll, "Catalogue List"), (outline, scroll, "Catalogue Library Tree")] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name))
            tree.addTableColumn(column); tree.outlineTableColumn=column; tree.headerView=nil
            tree.rowHeight=28; tree.indentationPerLevel=16; tree.intercellSpacing=NSSize(width:0,height:0)
            tree.backgroundColor=Design.card; tree.appearance=Theme.appearance; tree.style = .plain
            tree.dataSource=self; tree.delegate=self; tree.focusRingType = .none
            tree.setAccessibilityLabel(name)
            container.drawsBackground=false; container.hasVerticalScroller=true; container.autohidesScrollers=true; container.documentView=tree
            addSubview(container)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout() {
        super.layout()
        let topHeight=min(CGFloat(catalogueRoots.count)*28+8,max(32,min(176,bounds.height*0.35)))
        catalogueScroll.frame=NSRect(x:0,y:4,width:bounds.width,height:max(0,topHeight-8))
        dividerY=topHeight
        scroll.frame=NSRect(x:0,y:topHeight+5,width:bounds.width,height:max(0,bounds.height-topHeight-9))
        // Do not leave an empty scrollbar lane beside full-width selected rows.
        catalogueScroll.hasVerticalScroller=CGFloat(catalogueList.numberOfRows)*catalogueList.rowHeight > catalogueScroll.bounds.height
        scroll.hasVerticalScroller=CGFloat(outline.numberOfRows)*outline.rowHeight > scroll.bounds.height
        catalogueScroll.tile();scroll.tile()
        catalogueList.tableColumns.first?.width=catalogueScroll.contentSize.width
        outline.tableColumns.first?.width=scroll.contentSize.width
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) { hairline(x:0,y:dividerY,width:bounds.width) }
    func update(names:[String], active:String, rows:[LibraryRail.Row], selected:StudioFrame.Place, selectedKey:String? = nil) {
        rebuilding=true
        defer{rebuilding=false}
        current=active
        catalogueRoots=names.map { Node("catalogue:"+$0,$0,catalogue:$0,symbol:"books.vertical") }
        if !names.contains(active){catalogueRoots.insert(Node("catalogue:"+active,active,catalogue:active,symbol:"books.vertical"),at:0)}
        let root=Node("content",active)
        do {
            var stack:[(Int,Node)]=[(-1,root)]
            for row in rows {
                let node:Node, level:Int
                switch row {
                case .palette(let palette):
                    // A leaf belongs under its real schema bucket. Selecting it opens the
                    // palette in the centre canvas; it never introduces another palette rail.
                    node=Node("palette:" + palette.id.uuidString,palette.name,count:palette.count,place:.palette(palette.id),symbol:"square.grid.2x2");level=palette.indent+1
                case .group(let title,let key):
                    let target:StudioFrame.Place? = key?.hasPrefix("collection:") == true ? UUID(uuidString:String(key!.dropFirst(11))).map{.collection($0)} : (key == "palettes" ? .palettes : nil)
                    node=Node(key ?? title,title,place:target);level=0
                case .row(let title,let count,let place,let indent):node=Node(String(describing:place),title,count:count,place:place,symbol:place == .catalogue ? "square.grid.2x2" : "folder");level=indent+1
                case .node(let title,let count,let project,let indent,_,let id):node=Node(id.uuidString,title,count:count,place:.group(project,id));level=indent+1
                case .tag:continue
                }
                while let last=stack.last,last.0 >= level{stack.removeLast()}
                stack.last?.1.children.append(node);stack.append((level,node))
            }
        }
        roots=root.children
        catalogueList.reloadData()
        if let index=catalogueRoots.firstIndex(where:{$0.catalogue==active}) { catalogueList.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false) }
        outline.reloadData()
        needsLayout=true
        func restore(_ nodes:[Node]){for node in nodes {if expanded.contains(node.key) || node.catalogue==active || node.key=="catalogue"{outline.expandItem(node)};restore(node.children)}}
        restore(roots)
        for i in 0..<outline.numberOfRows {if let n=outline.item(atRow:i) as? Node,(selectedKey.map{n.key == $0} ?? (n.place==selected)){outline.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);break}}
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{(item as? Node)?.children.count ?? (outlineView === catalogueList ? catalogueRoots.count : roots.count)}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{(item as? Node)?.children[index] ?? (outlineView === catalogueList ? catalogueRoots[index] : roots[index])}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!(item as! Node).children.isEmpty}
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView? { WorkspacePanelRow() }
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node
        let cell=Cell(frame:NSRect(x:0,y:0,width:outlineView.tableColumns[0].width,height:28))
        let image=NSImageView(frame:NSRect(x:0,y:6,width:16,height:16));image.image=NSImage(systemSymbolName:node.symbol,accessibilityDescription:nil);image.contentTintColor=Design.quiet
        let label=NSTextField(labelWithString:node.title+(node.count>0 ? "   \(node.count)" : ""));label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        label.frame=NSRect(x:24,y:5,width:max(30,outlineView.frame.width-80),height:20);label.autoresizingMask=[.width]
        cell.addSubview(image);cell.addSubview(label);cell.textField=label;cell.imageView=image
        cell.toolTip=node.title;return cell
    }
    func outlineViewSelectionDidChange(_ notification:Notification){guard !rebuilding,let tree=notification.object as? NSOutlineView,let node=tree.item(atRow:tree.selectedRow) as? Node else{return};if let cat=node.catalogue{if cat != current{onCatalogue?(cat)}else{onPick?(.catalogue)}}else if ["favourites","claimed","palettes"].contains(node.key){onFilter?(node.key)}else if let place=node.place{onPick?(place)}}
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.insert(node.key);needsLayout=true}}
    func outlineViewItemDidCollapse(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.remove(node.key);needsLayout=true}}
}

final class WorkspaceInspector:NSView {
    var palette:Swatch? {didSet{needsDisplay=true;open.isEnabled=palette != nil;target.isEnabled=palette != nil}}
    var catalogue="" {didSet{needsDisplay=true}}
    var displayColours: [String:NSColor] = [:] {didSet{needsDisplay=true}}
    var total=0 {didSet{needsDisplay=true}}
    var onOpen:(()->Void)?,onTarget:(()->Void)?
    private let open=SwissButton("Open Swatches",.primary),target=SwissButton("Set Picker Target",.secondary)
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        open.target=self;open.action=#selector(openPalette);target.target=self;target.action=#selector(targetPalette)
        [open,target].forEach{addSubview($0)}
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func openPalette(){onOpen?()}
    @objc private func targetPalette(){onTarget?()}
    override func layout(){super.layout();open.frame=NSRect(x:16,y:196,width:bounds.width-32,height:32);target.frame=NSRect(x:16,y:236,width:bounds.width-32,height:32)}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed("Selection",.bodyStrong).draw(x:16,baseline:28)
        Design.attributed(palette?.name ?? "Select A Palette",.bodyStrong).draw(x:16,baseline:60,width:bounds.width-32)
        let colours=palette?.entries.map{displayColours[$0.hex] ?? Design.hex($0.hex)} ?? []
        let box=NSRect(x:16,y:76,width:bounds.width-32,height:64)
        if colours.isEmpty{fill(box,Design.mist)}else{for (i,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(i)*box.width/CGFloat(colours.count),y:box.minY,width:box.width/CGFloat(colours.count)+0.5,height:box.height),c)}}
        Design.attributed(palette.map{"\($0.entries.count) Colours"} ?? "\(total) Palettes In Catalogue",.body,colour:Design.quiet).draw(x:16,baseline:168,width:bounds.width-32)
        hairline(x:0,y:292,width:bounds.width)
        Design.attributed(catalogue,.body,colour:Design.quiet).draw(x:16,baseline:320,width:bounds.width-32)
        hairline(x:0,y:344,width:bounds.width)
    }
}

final class WorkspaceFilmstrip:NSView {
    private final class CarouselScroll:NSScrollView {
        override func scrollWheel(with event:NSEvent) {
            guard let documentView else{return}
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let step = delta * (event.hasPreciseScrollingDeltas ? 1 : 16)
            let limit = max(0,documentView.bounds.width-contentSize.width)
            let next = max(0,min(limit,contentView.bounds.origin.x-step))
            contentView.scroll(to:NSPoint(x:next,y:0))
            reflectScrolledClipView(contentView)
        }
    }
    final class Strip:NSView {
        var palettes:[Swatch]=[] {didSet{needsDisplay=true}}
        var selected:UUID? {didSet{needsDisplay=true}}
        var displayColours: [String:NSColor] = [:]
        var onPick:((UUID)->Void)?
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){for (i,palette) in palettes.enumerated(){let box=NSRect(x:CGFloat(i)*112+8,y:8,width:96,height:48);guard box.insetBy(dx:-8,dy:-8).intersects(dirtyRect) else{continue};let colours=palette.entries;for (j,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(j)*box.width/CGFloat(max(1,colours.count)),y:box.minY,width:box.width/CGFloat(max(1,colours.count))+0.5,height:box.height),displayColours[c.hex] ?? Design.hex(c.hex))};if selected==palette.id{Design.ink.setStroke();let path=NSBezierPath(rect:box.insetBy(dx:-3,dy:-3));path.lineWidth=2;path.stroke()};Design.attributed(palette.name,.body).draw(x:box.minX,baseline:76,width:96)}}
        override func mouseDown(with event:NSEvent){let point=convert(event.locationInWindow,from:nil);let index=Int(point.x/112);if palettes.indices.contains(index){onPick?(palettes[index].id)}}
    }
    private let scroll=CarouselScroll(),strip=Strip()
    var onPick:((UUID)->Void)?
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor;scroll.drawsBackground=false;scroll.hasHorizontalScroller=true;scroll.horizontalScrollElasticity = .none;scroll.verticalScrollElasticity = .none;scroll.autohidesScrollers=true;scroll.documentView=strip;addSubview(scroll);strip.onPick={[weak self] in self?.onPick?($0)};setAccessibilityLabel("Footer palette carousel")}
    required init?(coder:NSCoder){fatalError()}
    func update(_ palettes:[Swatch],selected:UUID?, colours:[String:NSColor] = [:]){strip.displayColours=colours;strip.palettes=palettes;strip.selected=selected;needsLayout=true}
    override func layout(){super.layout();scroll.frame=NSRect(x:8,y:24,width:bounds.width-16,height:bounds.height-24);strip.frame=NSRect(x:0,y:0,width:max(scroll.contentSize.width,CGFloat(strip.palettes.count)*112+8),height:84)}
    override func draw(_ dirtyRect:NSRect){hairline(x:0,y:0,width:bounds.width);Design.attributed("All Palettes · \(strip.palettes.count)",.body,colour:Design.quiet).draw(x:16,baseline:19);Design.attributed(ContentViewController.releaseLine,.body,colour:Design.quiet).draw(right:bounds.width-16,baseline:19)}
}

/// The Page's fixed tool rows stay independent of rail panels and the global carousel.
final class WorkspaceViewportBar:NSView {
    private let isFooter:Bool
    private let gridButton=NSButton(),listButton=NSButton()
    private let appearancePresets=AppearancePresetControl()
    let channels=WorkspaceChannelControls(frame:.zero)
    var onMode:((Bool)->Void)?
    var listMode=false { didSet{updateButtons()} }
    override var isFlipped:Bool{true}
    init(footer:Bool) {
        isFooter=footer;super.init(frame:.zero)
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAppearance),name:.themeDidChange,object:nil)
        if footer {
            for (button,symbol,label) in [(gridButton,"square.grid.2x2","Grid View"),(listButton,"list.bullet","List View")] {
                button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)
                button.appearance=NSAppearance(named:.aqua)
                button.imagePosition = .imageOnly;button.isBordered=false;button.setButtonType(.toggle)
                button.target=self;button.action=#selector(choose(_:));button.toolTip=label;button.setAccessibilityLabel(label)
                addSubview(button)
            }
            updateButtons()
        } else {
            addSubview(appearancePresets);addSubview(channels)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refreshAppearance(){updateButtons()}
    private func updateButtons(){gridButton.state=listMode ? .off:.on;listButton.state=listMode ? .on:.off;gridButton.contentTintColor=listMode ? Design.quiet:Design.ink;listButton.contentTintColor=listMode ? Design.ink:Design.quiet;needsDisplay=true}
    @objc private func choose(_ sender:NSButton){listMode=sender === listButton;onMode?(listMode)}
    /// The right-hand controls, left to right, each with its width, its height and the gap before it; the bar steps them left from `rightInset`, so their last edge is the swatches' at any width.
    var rightControls:[(view:NSView,width:CGFloat,height:CGFloat,gap:CGFloat)]=[] { didSet{needsLayout=true} }
    var leftInset:CGFloat=16 { didSet{needsLayout=true;needsDisplay=true} }
    var rightInset:CGFloat=16 { didSet{needsLayout=true} }
    override func layout(){
        super.layout();gridButton.frame=NSRect(x:leftInset,y:4,width:28,height:24);listButton.frame=NSRect(x:leftInset+32,y:4,width:28,height:24)
        channels.frame=NSRect(x:12,y:2,width:min(440,max(80,bounds.width-184)),height:28)
        appearancePresets.frame=NSRect(x:bounds.width-156,y:2,width:140,height:28)
        var right=bounds.width-rightInset
        for c in rightControls.reversed() {
            let width = (c.view as? PrintProfileSelector).map { min(c.width, $0.preferredControlWidth) } ?? c.width
            c.view.frame=NSRect(x:right-width,y:((bounds.height-c.height)/2).rounded(),width:width,height:c.height)
            right-=width+c.gap
        }
    }
    override func draw(_ dirtyRect:NSRect){
        hairline(x:0,y:isFooter ? 0:bounds.height-1,width:bounds.width)
        if isFooter {
            fill(NSRect(x:leftInset+(listMode ? 32:0),y:bounds.height-3,width:28,height:2),Design.ink)
        } else {
            Design.rule.setStroke()
            let border=NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke()

        }
    }
}
