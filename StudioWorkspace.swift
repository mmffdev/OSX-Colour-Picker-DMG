import AppKit
import UniformTypeIdentifiers
import ImageIO

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
    private var expandedKey: String { "Workspace.CatalogueTree.Expanded.\(current)" }
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
        if current != active {
            if !current.isEmpty { AppPreferences.shared.set(expanded.sorted(), forKey: expandedKey) }
            current=active
            expanded=Set(AppPreferences.shared.stringArray(forKey: expandedKey) ?? [])
        }
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
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.insert(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey);needsLayout=true}}
    func outlineViewItemDidCollapse(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node{expanded.remove(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey);needsLayout=true}}
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
    override func draw(_ dirtyRect:NSRect){hairline(x:0,y:0,width:bounds.width);Design.attributed("All Palettes · \(strip.palettes.count)",.body,colour:Design.quiet).draw(x:16,baseline:19)}
}

enum WorkspaceImageSort: String, CaseIterable {
    case captureTime = "Capture Time", checkedState = "Checked State", fileName = "File Name"
    case fileType = "File Type", mediaType = "Media Type", off = "Off"
}

/// A text-first, underline-selected control shared by intake and footer view modes.
final class WorkspaceChoiceControl:NSView {
    let labels:[String]
    var selectedSegment=0 {didSet{needsDisplay=true}}
    var onChange:((Int)->Void)?
    private var hovered:Int?
    override var isFlipped:Bool{true}
    init(labels:[String]){self.labels=labels;super.init(frame:.zero);setAccessibilityRole(.radioGroup)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let width=bounds.width/CGFloat(max(1,labels.count))
        for (i,label) in labels.enumerated(){
            let box=NSRect(x:CGFloat(i)*width,y:0,width:width,height:bounds.height)
            let on=i == selectedSegment
            Design.attributed(label,on ? .bodyStrong:.body,colour:on ? Design.ink:Design.quiet).draw(x:box.minX+8,baseline:bounds.midY+5,width:box.width-16)
            if on {fill(NSRect(x:box.minX+8,y:bounds.maxY-2,width:max(0,box.width-16),height:2),Design.ink)}
            else if hovered == i {hairline(x:box.minX+8,y:bounds.maxY-1,width:max(0,box.width-16),Design.rule)}
        }
    }
    private func segment(_ event:NSEvent)->Int{min(labels.count-1,max(0,Int(convert(event.locationInWindow,from:nil).x/max(1,bounds.width)*CGFloat(labels.count))))}
    override func mouseDown(with event:NSEvent){let next=segment(event);guard next != selectedSegment else{return};selectedSegment=next;onChange?(next)}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseMoved(with event:NSEvent){let next=segment(event);if hovered != next{hovered=next;needsDisplay=true}}
    override func mouseExited(with event:NSEvent){hovered=nil;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

final class WorkspaceMenuControl:NSView {
    var title="Sort: Off"{didSet{needsDisplay=true}}
    var onPress:(()->Void)?
    private var hovering=false
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed(title,.bodyStrong,colour:Design.ink).draw(x:8,baseline:bounds.midY+5,width:max(0,bounds.width-24))
        let x=bounds.width-9,y=bounds.midY-1
        let path=NSBezierPath();path.lineWidth=1.5;path.move(to:NSPoint(x:x-3,y:y-2));path.line(to:NSPoint(x:x,y:y+1));path.line(to:NSPoint(x:x+3,y:y-2));Design.ink.setStroke();path.stroke()
        if hovering{hairline(x:8,y:bounds.maxY-1,width:max(0,bounds.width-20),Design.rule)}
    }
    override func mouseDown(with event:NSEvent){onPress?()}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovering=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovering=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

final class WorkspaceTextActionControl:NSView {
    var title:String {didSet{needsDisplay=true}}
    var onPress:(()->Void)?
    private var hovering=false
    override var isFlipped:Bool{true}
    init(_ title:String){self.title=title;super.init(frame:.zero);setAccessibilityRole(.button);setAccessibilityLabel(title)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let text=Design.attributed(title,.bodyStrong,colour:Design.ink)
        text.draw(x:0,baseline:bounds.midY+5,width:bounds.width)
        if hovering{hairline(x:0,y:bounds.maxY-1,width:min(bounds.width,text.size().width),Design.ink)}
    }
    override func mouseDown(with event:NSEvent){onPress?()}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovering=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovering=false;needsDisplay=true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}

/// The Page's fixed tool rows stay independent of rail panels and the global carousel.
final class WorkspaceViewportBar:NSView {
    private let isFooter:Bool
    private let gridButton=NSButton(),listButton=NSButton()
    private let appearancePresets=AppearancePresetControl()
    let channels=WorkspaceChannelControls(frame:.zero)
    private let importButton=SwissButton("Import", .secondary)
    private let cancelButton=SwissButton("Cancel", .quiet)
    private let allImages=NSButton(checkboxWithTitle:"All Images",target:nil,action:nil)
    private let imageCount=NSTextField(labelWithString:"0 Images")
    private let intakeView=WorkspaceChoiceControl(labels:["Grid","Full"])
    private let sortButton=WorkspaceMenuControl()
    private let imageFilter=WorkspaceChoiceControl(labels:["All Images","New Images"])
    private let metadataFilterButton=WorkspaceMenuControl()
    private let importLinkChoice=WorkspaceChoiceControl(labels:["Import","Link"])
    private var intakeSort=WorkspaceImageSort.off
    var onImport:(()->Void)?
    var onIntakeMode:((Bool)->Void)?
    var onCancel:(()->Void)?
    var onSelectAllImages:((Bool)->Void)?
    var onImageFilter:((Bool)->Void)?
    var onImageSort:((WorkspaceImageSort)->Void)?
    var onImageView:((Bool)->Void)?
    var onMetadataFilter:(()->Void)?
    var onImportLinking:((Bool)->Void)?
    private var offersImport=false
    private var intake=false
    private var linking=false
    private var imageIntake=false
    var onMode:((Bool)->Void)?
    var listMode=false { didSet{updateButtons()} }
    override var isFlipped:Bool{true}
    init(footer:Bool) {
        isFooter=footer;super.init(frame:.zero)
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAppearance),name:.themeDidChange,object:nil)
        metadataFilterButton.title="Filter by Meta"
        metadataFilterButton.onPress={[weak self] in self?.onMetadataFilter?()}
        if footer {
            for (button,symbol,label) in [(gridButton,"square.grid.2x2","Grid View"),(listButton,"list.bullet","List View")] {
                button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)
                button.appearance=NSAppearance(named:.aqua)
                button.imagePosition = .imageOnly;button.isBordered=false;button.setButtonType(.toggle)
                button.target=self;button.action=#selector(choose(_:));button.toolTip=label;button.setAccessibilityLabel(label)
                addSubview(button)
            }
            intakeView.onChange={[weak self] segment in self?.onImageView?(segment == 1)}
            sortButton.onPress={[weak self] in self?.openSortMenu()}
            [intakeView,sortButton,metadataFilterButton].forEach(addSubview)
            intakeView.isHidden=true;sortButton.isHidden=true;metadataFilterButton.isHidden=true
            updateButtons()
        } else {
            importButton.target=self;importButton.action=#selector(beginImport)
            allImages.target=self;allImages.action=#selector(selectAllChanged)
            allImages.state = .on
            imageFilter.onChange={[weak self] segment in self?.onImageFilter?(segment == 1)}
            importLinkChoice.onChange={[weak self] segment in self?.onImportLinking?(segment == 1)}
            imageCount.font=Design.Text.body.font();imageCount.textColor=Design.quiet;imageCount.alignment = .right
            [importButton,appearancePresets,channels,allImages,imageFilter,imageCount,metadataFilterButton,importLinkChoice].forEach(addSubview)
            setIntakeMode(false)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func refreshAppearance(){updateButtons()}
    private func updateButtons(){gridButton.state=listMode ? .off:.on;listButton.state=listMode ? .on:.off;gridButton.contentTintColor=listMode ? Design.quiet:Design.ink;listButton.contentTintColor=listMode ? Design.ink:Design.quiet;needsDisplay=true}
    @objc private func choose(_ sender:NSButton){listMode=sender === listButton;onMode?(listMode)}
    func offerPhotographyImport(_ offered:Bool){offersImport=offered;importButton.isHidden = !offered || intake;needsLayout=true}
    func setIntakeMode(_ active:Bool,linking:Bool=false){
        intake=active;self.linking=linking
        channels.isHidden=active;appearancePresets.isHidden=active
        importLinkChoice.isHidden = !active
        importButton.isHidden = !offersImport || active
        allImages.isHidden = !active;imageFilter.isHidden = !active;imageCount.isHidden = !active
        if active && !imageIntake {imageFilter.selectedSegment=0}
        needsLayout=true
    }
    func configureImageIntake(_ active:Bool,linking:Bool=false,selectAll:Bool,newOnly:Bool,fullView:Bool,sort:WorkspaceImageSort,imageCount:Int,selectedCount:Int,columns:Int){
        imageIntake=active
        if !isFooter {
            setIntakeMode(active,linking:linking)
            importLinkChoice.selectedSegment=linking ? 1:0
            allImages.state=selectAll ? .on:.off
            imageFilter.selectedSegment=newOnly ? 1:0
            self.imageCount.stringValue="\(imageCount) Images · \(selectedCount) Selected"
        } else {
            for control in [intakeView,sortButton] {control.isHidden = !active}
            gridButton.isHidden=active;listButton.isHidden=active
            intakeView.selectedSegment=fullView ? 1:0
            intakeSort=sort;sortButton.title="Sort: \(sort.rawValue)"
        }
        needsLayout=true;needsDisplay=true
    }
    @objc private func selectAllChanged(){onSelectAllImages?(allImages.state == .on)}
    @objc private func beginImport(){onImport?()}
    func configureMetadataFilter(visible:Bool,active:Bool){guard !isFooter else{return};metadataFilterButton.isHidden = !visible;metadataFilterButton.title=active ? "Metadata Filter: On" : "Filter by Meta";needsLayout=true}
    @objc private func openSortMenu(){
        guard let win=window else{return}
        if let old=droppedSort {old.parent?.removeChildWindow(old);old.orderOut(nil);droppedSort=nil;return}
        let items=WorkspaceImageSort.allCases.map(\.rawValue)
        let panel=SwissDropdown.MenuPanel(items:items,chosen:intakeSort.rawValue,width:196){[weak self] index in
            guard let self,WorkspaceImageSort.allCases.indices.contains(index) else{return}
            self.intakeSort=WorkspaceImageSort.allCases[index];self.sortButton.title="Sort: \(self.intakeSort.rawValue)"
            self.onImageSort?(self.intakeSort);self.droppedSort?.parent?.removeChildWindow(self.droppedSort!);self.droppedSort?.orderOut(nil);self.droppedSort=nil
        }
        let rect=win.convertToScreen(sortButton.convert(sortButton.bounds,to:nil));panel.place(above:NSPoint(x:rect.minX,y:rect.maxY+4));win.addChildWindow(panel,ordered:.above);droppedSort=panel
    }
    private var droppedSort:SwissDropdown.MenuPanel?
    /// The right-hand controls, left to right, each with its width, its height and the gap before it; the bar steps them left from `rightInset`, so their last edge is the swatches' at any width.
    var rightControls:[(view:NSView,width:CGFloat,height:CGFloat,gap:CGFloat)]=[] { didSet{needsLayout=true} }
    var leftInset:CGFloat=16 { didSet{needsLayout=true;needsDisplay=true} }
    var rightInset:CGFloat=16 { didSet{needsLayout=true} }
    override func layout(){
        super.layout();gridButton.frame=NSRect(x:leftInset,y:4,width:28,height:24);listButton.frame=NSRect(x:leftInset+32,y:4,width:28,height:24)
        intakeView.frame=NSRect(x:leftInset,y:2,width:128,height:28)
        sortButton.frame=NSRect(x:leftInset+148,y:2,width:128,height:28)
        allImages.frame=NSRect(x:leftInset,y:3,width:136,height:26)
        imageFilter.frame=NSRect(x:leftInset+148,y:2,width:226,height:28)
        imageCount.frame=NSRect(x:bounds.width-rightInset-300,y:6,width:284,height:20)
        importButton.frame=NSRect(x:12,y:2,width:78,height:28)
        importLinkChoice.frame=NSRect(x:leftInset+550,y:2,width:128,height:28)
        channels.frame=NSRect(x:100,y:2,width:min(440,max(80,bounds.width-272)),height:28)
        appearancePresets.frame=NSRect(x:bounds.width-156,y:2,width:140,height:28)
        if isFooter {
            metadataFilterButton.isHidden=true;metadataFilterButton.frame = .zero
            intakeView.frame=NSRect(x:leftInset,y:2,width:128,height:28)
            sortButton.frame=NSRect(x:leftInset+148,y:2,width:160,height:28)
        } else if intake {
            metadataFilterButton.frame=NSRect(x:leftInset+384,y:2,width:156,height:28)
        } else {
            metadataFilterButton.frame=NSRect(x:max(12,bounds.width-rightInset-156-148),y:2,width:156,height:28)
        }
        var right=bounds.width-rightInset
        for c in rightControls.reversed() {
            let width = (c.view as? PrintProfileSelector).map { min(c.width, $0.preferredControlWidth) } ?? c.width
            c.view.frame=NSRect(x:right-width,y:((bounds.height-c.height)/2).rounded(),width:width,height:c.height)
            right-=width+c.gap
        }
    }
    override func draw(_ dirtyRect:NSRect){
        hairline(x:0,y:isFooter ? 0:bounds.height-1,width:bounds.width)
        if !isFooter && intake {hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)}
        if isFooter {
            fill(NSRect(x:leftInset+(listMode ? 32:0),y:bounds.height-3,width:28,height:2),Design.ink)
        } else {
            Design.rule.setStroke()
            let border=NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5));border.lineWidth=1;border.stroke()

        }
    }
}

/// Lazy Finder-style source tree. Folder browsing and selection are active; import/link actions
/// remain separate from browsing and are added in a later phase.
enum WorkspaceImageScanEvent { case began, batch, completed }

final class WorkspaceImageIntakePane:NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, WorkspaceScrollableContent, WorkspaceRailAwareContent {
    private final class ScanCancellation {
        private let lock=NSLock();private var cancelled=false
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
        var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
    }
    final class Node:NSObject {
        let url:URL
        let isDirectory:Bool
        let isRoot:Bool
        var children:[Node]?
        var loading=false
        init(url:URL,isDirectory:Bool,isRoot:Bool=false){self.url=url;self.isDirectory=isDirectory;self.isRoot=isRoot}
        var title:String {
            if isRoot && url == WorkspaceImageIntakePane.userHome { return "Home — \(url.lastPathComponent)" }
            if isRoot, let name = try? url.resourceValues(forKeys:[.volumeNameKey]).volumeName,
               url.path == "/" || url.deletingLastPathComponent().path == "/Volumes" { return name }
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
    }
    var scrollbarOnLeft=false {didSet{scroll.onLeft=scrollbarOnLeft}}
    var onImageFiles:((URL?,[URL],WorkspaceImageScanEvent)->Void)?
    var minimumContentHeight:CGFloat {380}
    private var roots:[Node]=[]
    private var selectedFolder:Node?
    private var rebuilding=false
    private var scanGeneration=0
    private var scanCancellation:ScanCancellation?
    private var includeNested=false
    private let outline=WorkspaceOutline(),scroll=WorkspacePanelScroll()
    private let nestedFolders=NSButton(checkboxWithTitle:"Include Nested Folders",target:nil,action:nil)
    private static let supportedImageExtensions:Set<String> = {
        let identifiers=CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
        let extensions=identifiers.flatMap{identifier -> [String] in
            guard let type=UTType(identifier),type.conforms(to:.image) else{return []}
            return type.tags[.filenameExtension] ?? []
        }
        return Set(extensions.map{$0.lowercased()})
    }()
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("Image File Tree"))
        outline.addTableColumn(column);outline.outlineTableColumn=column;outline.headerView=nil
        outline.rowHeight=28;outline.indentationPerLevel=16;outline.intercellSpacing=NSSize(width:0,height:0)
        outline.backgroundColor=Design.card;outline.appearance=Theme.appearance;outline.style = .plain
        outline.dataSource=self;outline.delegate=self;outline.focusRingType = .none;outline.allowsMultipleSelection=true
        outline.setAccessibilityLabel("Source folders and images")
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.documentView=outline
        nestedFolders.font=Design.Text.body.font();nestedFolders.contentTintColor=Design.ink
        nestedFolders.target=self;nestedFolders.action=#selector(nestedFoldersChanged)
        nestedFolders.setAccessibilityLabel("Include Nested Folders")
        addSubview(nestedFolders);addSubview(scroll)
        reloadRoots()
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout();nestedFolders.frame=NSRect(x:16,y:0,width:max(0,bounds.width-32),height:32)
        scroll.frame=NSRect(x:0,y:32,width:bounds.width,height:max(0,bounds.height-32))
        scroll.hasVerticalScroller=CGFloat(outline.numberOfRows)*outline.rowHeight > scroll.bounds.height
        scroll.tile();outline.tableColumns.first?.width=scroll.contentSize.width
    }
    static var userHome: URL {
        // NSHomeDirectory is the app container in a sandboxed process.
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            return URL(fileURLWithPath:String(cString:path),isDirectory:true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    private var requestingAccess=false
    private func reloadRoots(){
        let disk=URL(fileURLWithPath:"/",isDirectory:true)
        let volumes=FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:[.volumeNameKey],options:[.skipHiddenVolumes]) ?? []
        var seen=Set<String>()
        roots=([Self.userHome,disk]+volumes).filter{seen.insert($0.standardizedFileURL.path).inserted}
            .map{Node(url:$0,isDirectory:true,isRoot:true)}
        outline.reloadData();needsLayout=true
    }
    func chooseFolder(){ requestAccess(nil) }
    private func requestAccess(_ node:Node?){
        guard !requestingAccess,let window else{return}
        requestingAccess=true
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.allowsMultipleSelection=false;panel.directoryURL=node?.url ?? Self.userHome
        panel.prompt="Allow Access";panel.message="Choose the folder or disk to browse. Colorgain remembers access to the location you select."
        panel.beginSheetModal(for:window){[weak self] response in
            guard let self else{return};self.requestingAccess=false
            guard response == .OK,let url=panel.url else{return}
            do {try FolderAccess.authorize(url,renew:true)}
            catch {NSApp.presentError(error);return}
            let chosen:Node
            let requested=node?.url.standardizedFileURL.path ?? ""
            let granted=url.standardizedFileURL.path
            if let node,requested == granted || granted == "/" || requested.hasPrefix(granted+"/") {chosen=node}
            else if let existing=self.roots.first(where:{$0.url.standardizedFileURL.path == granted}) {chosen=existing}
            else {chosen=Node(url:url,isDirectory:true,isRoot:true);self.roots.append(chosen);self.outline.reloadData()}
            chosen.children=nil;self.selectedFolder=chosen
            self.load(chosen)
            let row=self.outline.row(forItem:chosen)
            if row>=0 {self.outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            self.outline.expandItem(chosen)
        }
    }
    private func imageFile(_ url:URL)->Bool {
        let ext=url.pathExtension.lowercased()
        if let type=UTType(filenameExtension:ext),type.conforms(to:.image) {return true}
        return Self.supportedImageExtensions.contains(ext)
    }
    private func load(_ node:Node){
        guard node.isDirectory,node.children == nil,!node.loading else{return}
        #if APPSTORE
        guard FolderAccess.covers(node.url) else {requestAccess(node);return}
        #endif
        node.loading=true
        let url=node.url
        DispatchQueue.global(qos:.userInitiated).async { [weak self,weak node] in
            let urls:[URL]
            do {urls=try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])}
            catch {
                DispatchQueue.main.async { [weak node] in node?.loading=false;NSApp.presentError(error) }
                return
            }
            let found=urls.compactMap{child -> Node? in
                guard let values=try? child.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),values.isSymbolicLink != true else{return nil}
                if values.isDirectory == true {return Node(url:child,isDirectory:true)}
                return self?.imageFile(child) == true ? Node(url:child,isDirectory:false):nil
            }.sorted{
                if $0.isDirectory != $1.isDirectory{return $0.isDirectory}
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            DispatchQueue.main.async { [weak self,weak node] in
                guard let self,let node else{return};node.children=found;node.loading=false
                self.outline.reloadItem(node,reloadChildren:true);self.outline.expandItem(node);self.needsLayout=true
                if self.selectedFolder === node {
                    self.publishSelection()
                }
            }
        }
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{
        guard let node=item as? Node else{return roots.count};return node.children?.count ?? 0
    }
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{
        guard let node=item as? Node else{return roots[index]};return node.children![index]
    }
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{(item as! Node).isDirectory}
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{WorkspacePanelRow()}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node
        let cell=WorkspaceCatalogues.Cell(frame:NSRect(x:0,y:0,width:outlineView.tableColumns[0].width,height:28))
        let icon=NSImageView(frame:NSRect(x:0,y:6,width:16,height:16))
        icon.image=NSImage(systemSymbolName:node.isDirectory ? "folder":"photo",accessibilityDescription:node.isDirectory ? "Folder":"Image")
        icon.contentTintColor=Design.quiet
        let label=NSTextField(labelWithString:node.title);label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        label.frame=NSRect(x:24,y:5,width:max(30,outlineView.frame.width-40),height:20);label.autoresizingMask=[.width]
        cell.addSubview(icon);cell.addSubview(label);cell.textField=label;cell.imageView=icon;cell.toolTip=node.url.path
        return cell
    }
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node {load(node)}}
    func outlineViewSelectionDidChange(_ notification:Notification){guard !rebuilding else{return};publishSelection()}
    private func publishSelection(){
        let nodes=outline.selectedRowIndexes.compactMap{outline.item(atRow:$0) as? Node}
        if let folder=nodes.last(where:\.isDirectory){
            selectedFolder=folder;load(folder)
            // Permission and enumeration must finish before scanning the selection.
            guard folder.children != nil,!folder.loading else{return}
        }
        let files=nodes.filter{ !$0.isDirectory }.map(\.url)
        if !files.isEmpty {scanGeneration+=1;scanCancellation?.cancel();onImageFiles?(selectedFolder?.url,[],.began);onImageFiles?(selectedFolder?.url,files,.batch);onImageFiles?(selectedFolder?.url,[],.completed)}
        else if let folder=selectedFolder {scan(folder.url)}
        else {scanGeneration+=1;scanCancellation?.cancel();onImageFiles?(nil,[],.began);onImageFiles?(nil,[],.completed)}
    }
    @objc private func nestedFoldersChanged(){includeNested=nestedFolders.state == .on;if let folder=selectedFolder,folder.children != nil{scan(folder.url)}}
    private func scan(_ folder:URL){
        scanGeneration+=1;let generation=scanGeneration,recursive=includeNested
        scanCancellation?.cancel();let cancellation=ScanCancellation();scanCancellation=cancellation
        onImageFiles?(folder,[],.began)
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            guard let self else{return}
            var batch:[URL]=[]
            func emit(){
                guard !batch.isEmpty else{return}
                let ready=batch.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending};batch=[]
                DispatchQueue.main.async{[weak self] in guard let self,self.scanGeneration==generation else{return};self.onImageFiles?(folder,ready,.batch)}
            }
            func inspect(_ url:URL,values supplied:URLResourceValues?=nil){
                guard !cancellation.isCancelled,self.imageFile(url) else{return}
                // Extension checks are cheap; avoid a metadata round-trip for every non-image
                // document in large camera folders. Only image candidates need stat data.
                let values=supplied ?? (try? url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]))
                guard let values,values.isSymbolicLink != true,values.isDirectory != true else{return}
                batch.append(url);if batch.count>=24{emit()}
            }
            if recursive {
                var pending=[folder]
                while let directory=pending.popLast(),!cancellation.isCancelled {
                    guard let urls=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else{continue}
                    for url in urls {
                        if cancellation.isCancelled{break}
                        guard let values=try? url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.isPackageKey]),values.isSymbolicLink != true else{continue}
                        if values.isDirectory == true {
                            if values.isPackage != true {pending.append(url)}
                        } else {inspect(url,values:values)}
                    }
                }
            } else if let urls=try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) {
                urls.forEach{inspect($0)}
            }
            emit()
            DispatchQueue.main.async{[weak self] in guard let self,self.scanGeneration==generation,!cancellation.isCancelled else{return};self.onImageFiles?(folder,[],.completed)}
        }
    }
}

final class WorkspaceImageDestinationPane:NSView,WorkspaceScrollableContent {
    var catalogue="" {didSet{needsDisplay=true}}
    var linking=false {didSet{needsDisplay=true}}
    var minimumContentHeight:CGFloat {220}
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect){
        let title=linking ? "Linked Files":"Destination"
        Design.attributed(title,.bodyStrong).draw(x:16,baseline:24,width:bounds.width-32)
        Design.attributed(catalogue,.bodyStrong,colour:Design.quiet).draw(x:16,baseline:58,width:bounds.width-32)
        if linking {
            Design.attributed("Images / Photography",.body).draw(x:16,baseline:94,width:bounds.width-32)
            Design.attributed("Files remain at their source locations.",.body,colour:Design.quiet).draw(x:16,baseline:132,width:bounds.width-32)
            Design.attributed("Linking is not connected yet.",.caption,colour:Design.quiet).draw(x:16,baseline:160,width:bounds.width-32)
        } else {
            Design.attributed("Images",.body).draw(x:16,baseline:94,width:bounds.width-32)
            Design.attributed("Photography",.body).draw(x:16,baseline:124,width:bounds.width-32)
            Design.attributed("This previews the catalogue destination.",.body,colour:Design.quiet).draw(x:16,baseline:166,width:bounds.width-32)
        }
    }
}
