import AppKit

/// The full-app shell uses the existing catalogue model; these views own presentation only.
final class WorkspaceCatalogues: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
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
    private let outline = WorkspaceOutline(), scroll = FittedScrollView()
    private var roots: [Node] = [], expanded = Set<String>(), rebuilding = false
    private var current = ""
    var onPick: ((StudioFrame.Place)->Void)?
    var onCatalogue: ((String)->Void)?
    var onFilter: ((String)->Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer=true; layer?.backgroundColor=Design.card.cgColor
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("catalogue"))
        outline.addTableColumn(column); outline.outlineTableColumn=column; outline.headerView=nil
        outline.rowHeight=28; outline.indentationPerLevel=16; outline.intercellSpacing=NSSize(width:0,height:0)
        outline.backgroundColor=Design.card; outline.appearance=NSAppearance(named: .aqua); outline.style = .plain
        outline.dataSource=self; outline.delegate=self; outline.focusRingType = .none
        outline.setAccessibilityLabel("Catalogues library tree")
        scroll.drawsBackground=false; scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true; scroll.documentView=outline
        addSubview(scroll)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();scroll.frame=NSRect(x:8,y:4,width:bounds.width-16,height:max(0,bounds.height-8));outline.tableColumns.first?.width=scroll.contentSize.width}
    func update(names:[String], active:String, rows:[LibraryRail.Row], selected:StudioFrame.Place, selectedKey:String? = nil) {
        rebuilding=true
        defer{rebuilding=false}
        if current != active {current=active;expanded.insert("catalogue:"+active)}
        roots=names.map { Node("catalogue:"+$0,$0,catalogue:$0,symbol:"books.vertical") }
        if !names.contains(active){roots.insert(Node("catalogue:"+active,active,catalogue:active,symbol:"books.vertical"),at:0)}
        if let root=roots.first(where:{$0.catalogue==active}) {
            var stack:[(Int,Node)]=[(-1,root)]
            for row in rows {
                let node:Node, level:Int
                switch row {
                case .palette: continue // Palettes belong to Page and Footer.
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
        outline.reloadData()
        func restore(_ nodes:[Node]){for node in nodes {if expanded.contains(node.key) || node.catalogue==active || node.key=="catalogue"{outline.expandItem(node)};restore(node.children)}}
        restore(roots)
        for i in 0..<outline.numberOfRows {if let n=outline.item(atRow:i) as? Node,(selectedKey.map{n.key == $0} ?? (n.place==selected)){outline.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);break}}
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{(item as? Node)?.children.count ?? roots.count}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{(item as? Node)?.children[index] ?? roots[index]}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!(item as! Node).children.isEmpty}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node
        let cell=Cell(frame:NSRect(x:0,y:0,width:outlineView.tableColumns[0].width,height:28))
        let image=NSImageView(frame:NSRect(x:0,y:6,width:16,height:16));image.image=NSImage(systemSymbolName:node.symbol,accessibilityDescription:nil);image.contentTintColor=Design.quiet
        let label=NSTextField(labelWithString:node.title+(node.count>0 ? "   \(node.count)" : ""));label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        label.frame=NSRect(x:24,y:5,width:max(30,outlineView.frame.width-80),height:20);label.autoresizingMask=[.width]
        cell.addSubview(image);cell.addSubview(label);cell.textField=label;cell.imageView=image
        cell.toolTip=node.title;return cell
    }
    func outlineViewSelectionDidChange(_ notification:Notification){guard !rebuilding,let node=outline.item(atRow:outline.selectedRow) as? Node else{return};if let cat=node.catalogue{if cat != current{onCatalogue?(cat)}else{onPick?(.catalogue)}}else if ["favourites","claimed","palettes"].contains(node.key){onFilter?(node.key)}else if let place=node.place{onPick?(place)}}
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.insert(node.key)}}
    func outlineViewItemDidCollapse(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.remove(node.key)}}
}

final class WorkspaceInspector:NSView {
    var palette:Swatch? {didSet{needsDisplay=true;open.isEnabled=palette != nil;target.isEnabled=palette != nil}}
    var catalogue="" {didSet{needsDisplay=true}}
    var displayColours: [String:NSColor] = [:] {didSet{needsDisplay=true}}
    var total=0 {didSet{needsDisplay=true}}
    var onOpen:(()->Void)?,onTarget:(()->Void)?,onBackground:((NSColor)->Void)?
    private let open=SwissButton("Open Swatches",.primary),target=SwissButton("Set Picker Target",.secondary)
    private let background=NSColorWell()
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        open.target=self;open.action=#selector(openPalette);target.target=self;target.action=#selector(targetPalette)
        background.color=Design.card;background.target=self;background.action=#selector(changeBackground);background.setAccessibilityLabel("Canvas background colour")
        [open,target,background].forEach{addSubview($0)}
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func openPalette(){onOpen?()}
    @objc private func targetPalette(){onTarget?()}
    @objc private func changeBackground(){onBackground?(background.color)}
    override func layout(){super.layout();open.frame=NSRect(x:16,y:196,width:bounds.width-32,height:32);target.frame=NSRect(x:16,y:236,width:bounds.width-32,height:32);background.frame=NSRect(x:16,y:336,width:44,height:28)}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed("Selection",.bodyStrong).draw(x:16,baseline:28)
        Design.attributed(palette?.name ?? "Select A Palette",.bodyStrong).draw(x:16,baseline:60,width:bounds.width-32)
        let colours=palette?.entries.map{displayColours[$0.hex] ?? Design.hex($0.hex)} ?? []
        let box=NSRect(x:16,y:76,width:bounds.width-32,height:64)
        if colours.isEmpty{fill(box,Design.mist)}else{for (i,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(i)*box.width/CGFloat(colours.count),y:box.minY,width:box.width/CGFloat(colours.count)+0.5,height:box.height),c)}}
        Design.attributed(palette.map{"\($0.entries.count) Colours"} ?? "\(total) Palettes In Catalogue",.body,colour:Design.quiet).draw(x:16,baseline:168,width:bounds.width-32)
        hairline(x:0,y:292,width:bounds.width)
        Design.attributed("Canvas",.bodyStrong).draw(x:16,baseline:320)
        Design.attributed("Background",.body).draw(x:72,baseline:355)
        Design.attributed(catalogue,.body,colour:Design.quiet).draw(x:16,baseline:408,width:bounds.width-32)
        hairline(x:0,y:432,width:bounds.width)
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
    var onMode:((Bool)->Void)?
    var listMode=false { didSet{updateButtons()} }
    override var isFlipped:Bool{true}
    init(footer:Bool) {
        isFooter=footer;super.init(frame:.zero)
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        if footer {
            for (button,symbol,label) in [(gridButton,"square.grid.2x2","Grid View"),(listButton,"list.bullet","List View")] {
                button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)
                button.appearance=NSAppearance(named:.aqua)
                button.imagePosition = .imageOnly;button.isBordered=false;button.setButtonType(.toggle)
                button.target=self;button.action=#selector(choose(_:));button.toolTip=label;button.setAccessibilityLabel(label)
                addSubview(button)
            }
            updateButtons()
        }
    }
    required init?(coder:NSCoder){fatalError()}
    private func updateButtons(){gridButton.state=listMode ? .off:.on;listButton.state=listMode ? .on:.off;gridButton.contentTintColor=listMode ? Design.quiet:Design.ink;listButton.contentTintColor=listMode ? Design.ink:Design.quiet;needsDisplay=true}
    @objc private func choose(_ sender:NSButton){listMode=sender === listButton;onMode?(listMode)}
    override func layout(){super.layout();gridButton.frame=NSRect(x:12,y:4,width:28,height:24);listButton.frame=NSRect(x:44,y:4,width:28,height:24)}
    override func draw(_ dirtyRect:NSRect){
        hairline(x:0,y:isFooter ? 0:bounds.height-1,width:bounds.width)
        if isFooter {
            fill(NSRect(x:listMode ? 44:12,y:bounds.height-3,width:28,height:2),Design.ink)
        } else { Design.attributed("Library Filter",.body,colour:Design.quiet).draw(x:16,baseline:17) }
    }
}
