import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Portable favourite records include their display colour, rather than a separate colour map.
private enum WorkspaceFavourites {
    static func records(_ key:String)->[[String:String]] {AppPreferences.shared.object(forKey:key) as? [[String:String]] ?? []}
    static func sync(_ key:String,entries:[(String,String)]) {
        let old=records(key)
        let next=entries.map { id,title -> [String:String] in
            var record=["id":id,"title":title]
            if let colour=old.first(where:{$0["id"] == id})?["colour"] {record["colour"]=colour}
            return record
        }
        if next != old {AppPreferences.shared.set(next,forKey:key)}
    }
    static func colour(_ key:String,id:String)->NSColor? {
        records(key).first{$0["id"] == id}?["colour"].map{Design.hex($0)}
    }
    static func pick(key:String,id:String,title:String,over view:NSView,changed:@escaping()->Void) {
        guard let root=view.window?.contentView else{return}
        let target=StudioColourPicker.Target(group:"Favourite",name:title,key:id,
            read:{colour(key,id:id) ?? Design.card},write:{hex in
                var all=records(key)
                guard let index=all.firstIndex(where:{$0["id"] == id}) else{return}
                all[index]["colour"]=hex;AppPreferences.shared.set(all,forKey:key);changed()
            })
        StudioColourPicker(target:id,targets:[target],onReset:{
            var all=records(key)
            guard let index=all.firstIndex(where:{$0["id"] == id}) else{return}
            all[index].removeValue(forKey:"colour");AppPreferences.shared.set(all,forKey:key);changed()
        }).present(over:root)
    }
}

/// A full-width internal section header; disclosure state travels with the app data.
private final class WorkspaceSectionHeader:NSButton {
    private let preferenceKey:String
    private let help:Help_HexButton
    private let actionButton=NSButton()
    var trailingControl:NSView? {didSet{oldValue?.removeFromSuperview();if let trailingControl{addSubview(trailingControl)};needsLayout=true}}
    private var headerAction:(()->Void)?
    var changed:(()->Void)?
    var expanded:Bool {state == .on}
    func restoreLayoutPreference(){state=AppPreferences.shared.bool(forKey:preferenceKey) ? .off:.on;changed?()}
    override var isFlipped:Bool {true}
    init(_ title:String,key:String){
        preferenceKey=key
        let anchor=key.contains("Catalogues") ? "catalogues":key.contains("Favs") ? "favourites":key.contains("Folders") ? "folders":"my-palettes"
        help=Help_HexButton(page:"catalogues",section:anchor,title:title)
        super.init(frame:.zero)
        self.title=title;isBordered=false;setButtonType(.onOff)
        state=AppPreferences.shared.bool(forKey:key) ? .off:.on
        target=self;action=#selector(toggled);setAccessibilityLabel(title+" section")
        actionButton.isBordered=false;actionButton.imagePosition = .imageOnly
        actionButton.target=self;actionButton.action=#selector(runHeaderAction);actionButton.isHidden=true
        addSubview(actionButton);addSubview(help)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name:"Help: "+title,handler:{ [weak self] in self?.help.performClick(nil);return true })])
    }
    required init?(coder:NSCoder){fatalError()}
    override func mouseDown(with event:NSEvent){
        let point=convert(event.locationInWindow,from:nil)
        if help.frame.contains(point){help.performClick(nil);return}
        if let control=trailingControl,control.frame.contains(point){control.mouseDown(with:event);return}
        if !actionButton.isHidden,actionButton.frame.contains(point){actionButton.performClick(nil);return}
        super.mouseDown(with:event)
    }
    @objc private func toggled(){AppPreferences.shared.set(!expanded,forKey:preferenceKey);changed?()}
    func setAction(symbol:String,title:String,run:@escaping()->Void){
        headerAction=run;actionButton.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
        actionButton.setAccessibilityLabel(title);actionButton.toolTip=title;actionButton.isHidden=false;needsLayout=true
    }
    @objc private func runHeaderAction(){headerAction?()}
    override func layout(){
        super.layout();help.frame=Help_HexButton.frame(width:bounds.width,height:28)
        actionButton.frame=NSRect(x:bounds.width-60,y:2+Help_HexButton.opticalOffset,width:24,height:24);actionButton.contentTintColor=Design.ink
        trailingControl?.frame=NSRect(x:max(150,bounds.width-188),y:0,width:min(152,max(0,bounds.width-178)),height:28)
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect){
        if isHighlighted {fill(bounds,Design.mist)}
        let path=NSBezierPath()
        if expanded {
            path.move(to:NSPoint(x:14,y:13));path.line(to:NSPoint(x:22,y:13));path.line(to:NSPoint(x:18,y:19))
        } else {
            path.move(to:NSPoint(x:15,y:12));path.line(to:NSPoint(x:21,y:16));path.line(to:NSPoint(x:15,y:20))
        }
        path.close();Design.ink.setFill();path.fill()
        Design.attributed(title,.bodyStrong).draw(x:30,baseline:19,width:max(0,(trailingControl?.frame.minX ?? (bounds.width-(actionButton.isHidden ? 44:68)))-38))
    }
}

/// The full-app shell uses the existing catalogue model; these views own presentation only.
final class WorkspaceCatalogues: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, WorkspaceRailAwareContent, WorkspacePanelContentMetrics {
    func restoreLayoutPreferences(){expanded=Set(AppPreferences.shared.stringArray(forKey:expandedKey) ?? []);for heading in [cataloguesHeading,favsHeading,foldersHeading,myPalettesHeading]{heading.restoreLayoutPreference()}}
    var scrollbarOnLeft=false
    var panelContentPadding:CGFloat {myPalettesHeading.expanded ? 16:0}
    private func contentHeight(_ tree:NSOutlineView)->CGFloat {tree.numberOfRows == 0 ? 0:tree.rect(ofRow:tree.numberOfRows-1).maxY}
    private var favouritesHeight:CGFloat {favouriteRoots.isEmpty ? 28:contentHeight(favourites)}
    private var sections:[(WorkspaceSectionHeader,WorkspaceBranchTree,CGFloat)] {
        [(cataloguesHeading,catalogueList,contentHeight(catalogueList)),(favsHeading,favourites,favouritesHeight),(foldersHeading,outline,contentHeight(outline)),(myPalettesHeading,myPalettes,myPaletteRoots.isEmpty ? 28:contentHeight(myPalettes))]
    }
    var minimumContentHeight:CGFloat {sections.reduce(0){total,section in
        let filterHeight:CGFloat=section.1 === myPalettes && hasMyPalettes ? 96:0
        return total+28+(section.0.expanded ? section.2+filterHeight+(section.1 === myPalettes ? 0:WorkspacePanel.contentPadding):0)
    }}
    final class Node:NSObject {
        let key:String,title:String,count:Int,place:StudioFrame.Place?,catalogue:String?,symbol:String
        var children:[Node]=[]
        var colours:[NSColor]=[]
        var destination:LibraryRail.DropDestination?
        init(_ key:String,_ title:String,count:Int=0,place:StudioFrame.Place?=nil,catalogue:String?=nil,symbol:String="folder"){
            self.key=key;self.title=title;self.count=count;self.place=place;self.catalogue=catalogue;self.symbol=symbol
        }
        func resolveDestination(){
            children.forEach{$0.resolveDestination()}
            if destination != nil {return}
            let choices=children.compactMap(\.destination)
            if case .project(let project)=place,let first=choices.first(where:{$0.project == project}) {
                destination=first
            } else if let first=choices.first,choices.allSatisfy({$0 == first}) {destination=first}
        }
    }
    private let outline=WorkspaceBranchTree(),catalogueList=WorkspaceBranchTree(),favourites=WorkspaceBranchTree()
    private let myPalettes=WorkspaceBranchTree()
    private let favsHeading=WorkspaceSectionHeader("Favs",key:"Workspace.Library.Sections.Favs.Collapsed")
    private let cataloguesHeading=WorkspaceSectionHeader("Catalogues",key:"Workspace.Library.Sections.Catalogues.Collapsed")
    private let foldersHeading=WorkspaceSectionHeader("Folders",key:"Workspace.Library.Sections.Folders.Collapsed")
    private let myPalettesHeading=WorkspaceSectionHeader("My Palette's",key:"Workspace.Library.Sections.MyPalettes.Collapsed")
    private let emptyFavourites=NSTextField(labelWithString:"No favourites listed")
    private let emptyMyPalettes=NSTextField(labelWithString:"You have no palettes.")
    private var hasMyPalettes=false
    private var catalogueRoots:[Node]=[],favouriteRoots:[Node]=[],roots:[Node]=[],myPaletteRoots:[Node]=[]
    private var dividerYs:[CGFloat]=[]
    private var expanded=Set<String>(),rebuilding=false,current=""
    private var expandedKey:String {"Workspace.CatalogueTree.Expanded.\(current)"}
    private var favouritesKey:String {"Workspace.Library.Favourites."+(AppPreferences.shared.string(forKey:"currentCatalogueID") ?? current)}
    var onPick:((StudioFrame.Place)->Void)?
    var onCatalogue:((String)->Void)?
    var onCatalogueAction:((String,CatalogueRowAction)->Void)?
    private let catalogueMenu=SwissContextMenu()
    var onFilter:((String)->Void)?
    var onFavourite:((UUID)->Void)?
    var onDrop:((UUID,LibraryRail.DropDestination)->Void)?
    var onRename:((UUID,String)->Void)?
    var onTarget:((UUID)->Void)?
    var onRating:((UUID,Int)->Void)?
    var onFlag:((UUID,PaletteReview.Flag?)->Void)?
    private var assets=Library()
    private let paletteFilters=PaletteFilterControls(frame:.zero)
    var filter=PaletteAssetHandler.Filter() {didSet{paletteFilters.value=filter}}
    var onPaletteFilter:((PaletteAssetHandler.Filter)->Void)?
    private var order:PaletteAssetHandler.Order {filter.order}
    func configureAssets(_ library:Library){assets=library}

    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        for panel in [paletteFilters] {
            addSubview(panel);panel.onChange={ [weak self] value in self?.onPaletteFilter?(value) }
        }
        myPalettes.showsConnectors=false;favourites.showsConnectors=false;catalogueList.showsConnectors=false
        for (tree,name) in [(favourites,"Library Favourites"),(catalogueList,"Catalogue List"),(outline,"Catalogue Library Tree"),(myPalettes,"My Palettes")] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name))
            tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
            tree.rowHeight=34;tree.indentationPerLevel=0;tree.intercellSpacing=NSSize(width:0,height:0)
            tree.backgroundColor=Design.card;tree.appearance=Theme.appearance;tree.style = .plain
            tree.dataSource=self;tree.delegate=self;tree.focusRingType = .none;tree.setAccessibilityLabel(name)
            tree.setDraggingSourceOperationMask(.copy,forLocal:true)
            tree.rowColour={ [weak self] item in
                guard let self,let node=item as? Node else{return nil}
                return WorkspaceFavourites.colour(self.favouritesKey,id:node.key)
            }
            addSubview(tree);tree.installConnectors(in:self)
        }
        outline.registerForDraggedTypes([PaletteDrag.type])
        outline.isDropTarget={($0 as? Node)?.destination != nil}
        for heading in [favsHeading,cataloguesHeading,foldersHeading,myPalettesHeading] {
            heading.changed={ [weak self] in self?.refreshExtent() };addSubview(heading)
        }
        for label in [emptyFavourites,emptyMyPalettes] {label.font=Design.Text.body.font();label.textColor=Design.quiet;addSubview(label)}
    }
    required init?(coder:NSCoder){fatalError()}
    func setCatalogueAction(_ action:@escaping()->Void){cataloguesHeading.setAction(symbol:"plus",title:"Open Catalogue…",run:action)}
    override func layout(){
        super.layout();dividerYs=[]
        var y:CGFloat=0
        for (heading,tree,height) in sections {
            dividerYs.append(y)
            heading.frame=NSRect(x:0,y:y,width:bounds.width,height:28)
            y+=28
            if tree === myPalettes {
                let panel=paletteFilters
                panel.isHidden = !heading.expanded || !hasMyPalettes
                if heading.expanded && hasMyPalettes {panel.frame=NSRect(x:16,y:y+12,width:max(0,bounds.width-32),height:PaletteFilterControls.height(for:bounds.width-32));y+=96}
                else {panel.dismissOverlay()}
            }
            tree.isHidden = !heading.expanded || (tree === favourites && favouriteRoots.isEmpty)
            tree.frame=NSRect(x:0,y:y,width:bounds.width,height:tree.isHidden ? 0:height)
            tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()
            if tree === myPalettes {emptyMyPalettes.frame=NSRect(x:16,y:y+4,width:max(0,bounds.width-32),height:20)}
            if tree === favourites {emptyFavourites.frame=NSRect(x:16,y:y+4,width:max(0,bounds.width-32),height:20)}
            if heading.expanded {y+=height+(tree === myPalettes ? 0:WorkspacePanel.contentPadding)}
        }
        emptyFavourites.isHidden = !favouriteRoots.isEmpty || !favsHeading.expanded
        emptyMyPalettes.isHidden = !myPaletteRoots.isEmpty || !myPalettesHeading.expanded
        emptyMyPalettes.stringValue=hasMyPalettes ? "No palettes match your filters.":"You have no palettes."
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){for y in dividerYs {hairline(x:0,y:y,width:bounds.width)}}
    private func refreshExtent(){
        needsLayout=true
        for tree in [favourites,catalogueList,outline,myPalettes] {tree.refreshSurfaces()}
        var ancestor=superview
        while let view=ancestor {
            if let panel=view as? WorkspacePanel {panel.rail?.arrange();break}
            ancestor=view.superview
        }
    }
    func update(names:[String],active:String,rows:[LibraryRail.Row],selected:StudioFrame.Place,selectedKey:String?=nil,allFavourites:[Swatch]){
        rebuilding=true
        defer{rebuilding=false;refreshExtent()}
        if current != active {
            if !current.isEmpty {AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey)}
            current=active;expanded=Set(AppPreferences.shared.stringArray(forKey:expandedKey) ?? [])
        }
        catalogueRoots=names.map{Node("catalogue:"+$0,$0,catalogue:$0,symbol:"books.vertical")}
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
                    node=Node("palette:" + palette.id.uuidString,palette.name,count:palette.count,place:.palette(palette.id),symbol:"swatchpalette");level=palette.indent+1
                    node.colours=palette.colours
                    if let project=palette.project {node.destination=LibraryRail.DropDestination(project:project,bucket:palette.bucket)}
                case .group(let title,let key):
                    let target:StudioFrame.Place? = key?.hasPrefix("collection:") == true ? UUID(uuidString:String(key!.dropFirst(11))).map{.collection($0)} : (key == "palettes" ? .palettes : nil)
                    node=Node(key ?? title,title,place:target);level=0
                case .row(let title,let count,let place,let indent):node=Node(String(describing:place),title,count:count,place:place,symbol:place == .catalogue ? "square.grid.2x2" : "folder");level=indent+1
                case .node(let title,let count,let project,let indent,let acceptsPalette,let id):
                    let role=SchemaTrial.role(of:SchemaNode(name:title))
                    let symbol=role == .palettes ? "swatchpalette" : role == .information ? "info.circle" : role == .typography ? "textformat" : role == .tags ? "tag" : title.lowercased() == "photography" ? "camera" : title.lowercased() == "assets" ? "shippingbox" : "square.dashed"
                    node=Node(id.uuidString,title,count:count,place:.group(project,id),symbol:symbol);level=indent+1
                    if acceptsPalette {node.destination=LibraryRail.DropDestination(project:project,bucket:id)}
                case .tag:continue
                }
                while let last=stack.last,last.0 >= level{stack.removeLast()}
                stack.last?.1.children.append(node);stack.append((level,node))
            }
        }

        // Closed ancestors remain valid targets when their descendants identify one project.
        root.children.forEach{$0.resolveDestination()}

        favouriteRoots=root.children.first{$0.key == "favourites"}?.children ?? []
        WorkspaceFavourites.sync(favouritesKey,entries:allFavourites.map{("palette:"+$0.id.uuidString,$0.name)})
        myPaletteRoots=root.children.filter{["palettes","claimed"].contains($0.key)}.flatMap(\.children).filter{
            if case .palette=$0.place {return true};return false
        }
        roots=root.children.filter{!["favourites","palettes","claimed"].contains($0.key)}
        hasMyPalettes = !myPaletteRoots.isEmpty
        sortPalettes()
        for tree in [catalogueList,favourites,outline,myPalettes] {tree.reloadData()}
        if let index=catalogueRoots.firstIndex(where:{$0.catalogue == active}) {
            catalogueList.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
        }
        func restore(_ nodes:[Node]){for node in nodes {
            if expanded.contains(node.key) || node.key == "catalogue" {outline.expandItem(node)}
            restore(node.children)
        }}
        restore(roots)
        for tree in [outline,favourites,myPalettes] {
            for i in 0..<tree.numberOfRows {
                if let node=tree.item(atRow:i) as? Node,(selectedKey.map{node.key == $0} ?? (node.place == selected)) {
                    tree.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);break
                }
            }
        }
    }
    private func sortPalettes(){
        func sorted(_ nodes:[Node])->[Node]{
            let visibleNodes=nodes.filter{node in if case .palette(let id)=node.place,let palette=assets.swatch(id){return filter.matches(palette)};return true}
            let palettes=visibleNodes.compactMap{node->Swatch? in if case .palette(let id)=node.place{return assets.swatch(id)};return nil}
            let ranks=Dictionary(uniqueKeysWithValues:PaletteAssetHandler.ordered(palettes,by:order,in:assets).enumerated().map{($0.element.id,$0.offset)})
            let ordered=visibleNodes.filter{if case .palette=$0.place{return true};return false}.sorted{a,b in
                guard case .palette(let x)=a.place,case .palette(let y)=b.place else{return false};return (ranks[x] ?? 0) < (ranks[y] ?? 0)
            }
            var index=0
            return visibleNodes.map{node in
                node.children=sorted(node.children)
                if case .palette=node.place{defer{index+=1};return ordered[index]};return node
            }
        }
        myPaletteRoots=sorted(myPaletteRoots);favouriteRoots=sorted(favouriteRoots)
    }
    private func roots(for tree:NSOutlineView)->[Node]{tree === catalogueList ? catalogueRoots:(tree === favourites ? favouriteRoots:(tree === myPalettes ? myPaletteRoots:roots))}
    func outlineView(_ tree:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int {(item as? Node)?.children.count ?? roots(for:tree).count}
    func outlineView(_ tree:NSOutlineView,child index:Int,ofItem item:Any?)->Any {(item as? Node)?.children[index] ?? roots(for:tree)[index]}
    func outlineView(_ tree:NSOutlineView,isItemExpandable item:Any)->Bool {!(item as! Node).children.isEmpty}
    func outlineView(_ tree:NSOutlineView,rowViewForItem item:Any)->NSTableRowView? {
        let row=WorkspaceBranchTree.Row();row.accordion=tree as? WorkspaceBranchTree;return row
    }
    func outlineView(_ tree:NSOutlineView,heightOfRowByItem item:Any)->CGFloat {
        if let node=item as? Node,case .palette=node.place,tree !== favourites {return 56}
        return 34
    }
    func outlineView(_ tree:NSOutlineView,viewFor column:NSTableColumn?,item:Any)->NSView? {
        let node=item as! Node
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:tree.tableColumns[0].width,height:34))
        cell.symbol=node.symbol
        let isPalette:Bool={if case .palette=node.place{return true};return false}()
        let label=NSTextField(labelWithString:node.title)
        cell.countLabel.stringValue=String(node.count);cell.countLabel.isHidden = !isPalette && node.count == 0
        label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.title
        if tree === catalogueList, let name=node.catalogue {
            cell.catalogueAction.isHidden=false
            cell.catalogueAction.symbol="slider.horizontal.3"
            cell.catalogueAction.setAccessibilityLabel("Catalogue Actions: "+name)
            cell.catalogueAction.toolTip="Catalogue Actions: "+name
            cell.catalogueAction.run={ [weak self,weak cell] in
                guard let self,let cell else{return}
                let actions=CatalogueRowAction.allCases.map { action in
                    HaloAction(id:action.rawValue,label:action.rawValue,icon:RowMark.image(action.symbol,colour:Design.ink),onSelect:{ [weak self] in self?.onCatalogueAction?(name,action) })
                }
                self.catalogueMenu.open(actions,at:NSPoint(x:cell.catalogueAction.frame.minX,y:cell.catalogueAction.frame.maxY),in:cell)
            }
        }
        if case .palette(let id)=node.place {
            cell.isPalette=true
            cell.twoLines=tree !== favourites
            cell.renamePalette={ [weak self] name in self?.onRename?(id,name) }
            if let palette=assets.swatch(id){
                let value=PaletteAssetHandler.presentation(palette,in:assets)
                cell.review.configure(value)
                cell.target.active=value.isTarget
                cell.target.symbol="scope"
                cell.target.setAccessibilityLabel((value.isTarget ? "Stop Targeting ":"Target New Picks To ")+palette.name)
                cell.target.toolTip=value.isTarget ? "New Picks Go Here":"Target For New Picks"
                cell.target.run={ [weak self] in self?.onTarget?(id) }
                cell.review.onRating={ [weak self] rating in self?.onRating?(id,rating) }
                cell.review.onFlag={ [weak self] flag in self?.onFlag?(id,flag) }
            }
            cell.paletteDrag=(id,node.title,node.colours)
            cell.selectPalette={ [weak tree] in
                guard let tree else{return};tree.window?.makeFirstResponder(tree);let row=tree.row(forItem:node)
                if row >= 0 {tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            }
            cell.dragChanged={ [weak self] active in self?.outline.paletteDragActive=active }
            cell.star.favourite=favouriteRoots.contains{$0.place == .palette(id)}
            cell.star.setAccessibilityLabel((cell.star.favourite ? "Remove Favourite: ":"Add Favourite: ")+node.title)
            cell.star.run={ [weak self] in self?.onFavourite?(id) }
            if tree === favourites {
                cell.colourButton.isHidden=false
                cell.colourButton.colour=WorkspaceFavourites.colour(favouritesKey,id:node.key) ?? Design.card
                cell.colourButton.setAccessibilityLabel("Favourite Colour: "+node.title)
                cell.colourButton.run={ [weak self] in
                    guard let self else{return}
                    WorkspaceFavourites.pick(key:self.favouritesKey,id:node.key,title:node.title,over:self){ [weak self] in
                        guard let self else{return}
                        for tree in [self.favourites,self.outline,self.myPalettes] {tree.refreshSurfaces()}
                        self.refreshExtent()
                    }
                }
            }
        } else {cell.star.isHidden=true}
        return cell
    }
    func outlineView(_ tree:NSOutlineView,pasteboardWriterForItem item:Any)->NSPasteboardWriting? {
        guard let node=item as? Node,case .palette(let id)=node.place else{return nil}
        let writer=NSPasteboardItem();writer.setString(id.uuidString,forType:PaletteDrag.type);return writer
    }
    func outlineView(_ tree:NSOutlineView,draggingSession session:NSDraggingSession,willBeginAt screenPoint:NSPoint,forItems draggedItems:[Any]) {
        outline.paletteDragActive=true
    }
    func outlineView(_ tree:NSOutlineView,draggingSession session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        outline.paletteDragActive=false
    }
    func outlineView(_ tree:NSOutlineView,validateDrop info:NSDraggingInfo,proposedItem item:Any?,proposedChildIndex index:Int)->NSDragOperation {
        guard tree === outline,PaletteDrag.palette(on:info.draggingPasteboard) != nil else{return []}
        outline.paletteDragActive=true
        let row=tree.row(at:tree.convert(info.draggingLocation,from:nil))
        guard row >= 0,let node=tree.item(atRow:row) as? Node,node.destination != nil else{return []}
        tree.setDropItem(node,dropChildIndex:NSOutlineViewDropOnItemIndex)
        return .copy
    }
    func outlineView(_ tree:NSOutlineView,acceptDrop info:NSDraggingInfo,item:Any?,childIndex:Int)->Bool {
        defer{outline.paletteDragActive=false}
        guard tree === outline,let node=item as? Node,let destination=node.destination,let id=PaletteDrag.palette(on:info.draggingPasteboard) else{return false}
        onDrop?(id,destination);return true
    }
    func outlineViewSelectionDidChange(_ notification:Notification){
        guard !rebuilding,let tree=notification.object as? NSOutlineView,let node=tree.item(atRow:tree.selectedRow) as? Node else{return}
        // Finish the row's expand/collapse gesture before navigation rebuilds its node model.
        DispatchQueue.main.async { [weak self,weak tree] in
            guard let self,let tree,let selected=tree.item(atRow:tree.selectedRow) as? Node,selected.key == node.key else{return}
            if let catalogue=node.catalogue {if catalogue != self.current {self.onCatalogue?(catalogue)}else{self.onPick?(.catalogue)}}
            else if ["favourites","claimed","palettes"].contains(node.key){self.onFilter?(node.key)}
            else if let place=node.place {self.onPick?(place)}
        }
    }
    func outlineViewItemDidExpand(_ notification:Notification){
        guard !rebuilding,let node=notification.userInfo?["NSObject"] as? Node else{return}
        expanded.insert(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey);refreshExtent()
    }
    func outlineViewItemDidCollapse(_ notification:Notification){
        guard !rebuilding,let node=notification.userInfo?["NSObject"] as? Node else{return}
        expanded.remove(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey);refreshExtent()
    }
}

final class WorkspaceInspector:NSView,WorkspaceScrollableContent {
    var minimumContentHeight:CGFloat {345}
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
    final class Strip:NSView,NSDraggingSource {
        private var pressedPalette:Swatch?
        private var press:(NSPoint,TimeInterval)=(.zero,0)
        var palettes:[Swatch]=[] {didSet{needsDisplay=true}}
        var selected:UUID? {didSet{needsDisplay=true}}
        var displayColours: [String:NSColor] = [:]
        var onPick:((UUID)->Void)?
        override var isFlipped:Bool{true}
        override func draw(_ dirtyRect:NSRect){for (i,palette) in palettes.enumerated(){let box=NSRect(x:CGFloat(i)*112+8,y:8,width:96,height:48);guard box.insetBy(dx:-8,dy:-8).intersects(dirtyRect) else{continue};let colours=palette.entries;for (j,c) in colours.enumerated(){fill(NSRect(x:box.minX+CGFloat(j)*box.width/CGFloat(max(1,colours.count)),y:box.minY,width:box.width/CGFloat(max(1,colours.count))+0.5,height:box.height),displayColours[c.hex] ?? Design.hex(c.hex))};if selected==palette.id{Design.ink.setStroke();let path=NSBezierPath(rect:box.insetBy(dx:-3,dy:-3));path.lineWidth=2;path.stroke()};Design.attributed(palette.name,.body).draw(x:box.minX,baseline:76,width:96)}}
        private func palette(at point:NSPoint)->Swatch? {
            guard bounds.contains(point) else{return nil}
            let index=Int(point.x/112)
            return palettes.indices.contains(index) ? palettes[index]:nil
        }
        override func mouseDown(with event:NSEvent){
            pressedPalette=palette(at:convert(event.locationInWindow,from:nil))
            press=(event.locationInWindow,event.timestamp)
        }
        override func mouseDragged(with event:NSEvent){
            guard let palette=pressedPalette,PaletteDrag.counts(event,from:press) else{return}
            pressedPalette=nil
            PaletteDrag.begin(palette.id,name:palette.name,colours:palette.entries.map{displayColours[$0.hex] ?? Design.hex($0.hex)},event:event,in:self)
        }
        override func mouseUp(with event:NSEvent){
            defer{pressedPalette=nil}
            guard let pressedPalette,!PaletteDrag.counts(event,from:press),
                  palette(at:convert(event.locationInWindow,from:nil))?.id == pressedPalette.id else{return}
            onPick?(pressedPalette.id)
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
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

/// Mutually exclusive choices using the shared filled-square checkbox treatment.
final class WorkspaceToggleChoiceControl: NSView {
    private let buttons: [SwissCheckbox]
    var selectedSegment = 0 { didSet { updateSelection() } }
    var onChange: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    init(labels: [String]) {
        buttons = labels.map { SwissCheckbox($0) }
        super.init(frame: .zero)
        for (index, button) in buttons.enumerated() {
            button.tag = index; button.target = self; button.action = #selector(choose(_:))
            addSubview(button)
        }
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateSelection() {
        for (index, button) in buttons.enumerated() { button.state = index == selectedSegment ? .on : .off; button.needsDisplay = true }
    }
    @objc private func choose(_ sender: SwissCheckbox) {
        let changed = selectedSegment != sender.tag
        selectedSegment = sender.tag
        if changed { onChange?(selectedSegment) }
    }
    override func layout() {
        super.layout()
        let width = bounds.width / CGFloat(max(1, buttons.count))
        for (index, button) in buttons.enumerated() { button.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height) }
    }
}

final class WorkspaceMenuControl:NSView {
    var title="Sort: Off"{didSet{needsDisplay=true}}
    var onPress:(()->Void)?
    private var hovering=false
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        Design.attributed(title,.bodyStrong,colour:Design.ink).draw(x:8,baseline:bounds.midY+5,width:max(0,bounds.width-24))
        let x=bounds.width-9,y=bounds.midY-1
        let path=NSBezierPath();path.lineWidth=hovering ? 2:1.5;path.move(to:NSPoint(x:x-3,y:y-2));path.line(to:NSPoint(x:x,y:y+1));path.line(to:NSPoint(x:x+3,y:y-2));Design.ink.setStroke();path.stroke()
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
    static let actionbarHeight:CGFloat=52
    var preferredHeight:CGFloat=WorkspaceViewportBar.actionbarHeight
    static let footerHeight:CGFloat=42
    private let isFooter:Bool
    private let gridButton=NSButton(),listButton=NSButton()
    private let appearancePresets=AppearancePresetControl()
    let channels=WorkspaceChannelControls(frame:.zero)
    private let importButton=SwissButton("Import", .secondary)
    private let cancelButton=SwissButton("Cancel", .quiet)
    private let allImages=SwissCheckbox("All Images")
    private let imageCount=NSTextField(labelWithString:"0 Images")
    private let intakeView=WorkspaceChoiceControl(labels:["Grid","Full"])
    private let sortButton=WorkspaceMenuControl()
    private let imageFilter=WorkspaceToggleChoiceControl(labels:["All Images","New Images"])
    private let metadataFilterButton=WorkspaceMenuControl()
    private let importLinkChoice=WorkspaceToggleChoiceControl(labels:["Import","Link"])
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
            [importButton,appearancePresets,allImages,imageFilter,imageCount,metadataFilterButton,importLinkChoice].forEach(addSubview)
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
        appearancePresets.isHidden=active
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
    var leadingControls:[(view:NSView,width:CGFloat,height:CGFloat,gap:CGFloat)]=[] {didSet{needsLayout=true}}
    var leftInset:CGFloat=16 { didSet{needsLayout=true;needsDisplay=true} }
    var rightInset:CGFloat=16 { didSet{needsLayout=true} }
    /// Leading actions claim their actual width before filters are positioned.
    var leadingContentInset:CGFloat {leftInset+(!isFooter && !importButton.isHidden ? importButton.intrinsicContentSize.width+16:0)}
    override func layout(){
        super.layout();gridButton.frame=NSRect(x:leftInset,y:4,width:28,height:24);listButton.frame=NSRect(x:leftInset+32,y:4,width:28,height:24)
        intakeView.frame=NSRect(x:leftInset,y:2,width:128,height:28)
        sortButton.frame=NSRect(x:leftInset+148,y:2,width:128,height:28)
        allImages.frame=NSRect(x:leftInset,y:3,width:136,height:26)
        imageFilter.frame=NSRect(x:leftInset+148,y:2,width:226,height:28)
        imageCount.frame=NSRect(x:bounds.width-rightInset-300,y:6,width:284,height:20)
        importButton.frame=NSRect(x:leftInset,y:2,width:importButton.intrinsicContentSize.width,height:32)
        importLinkChoice.frame=NSRect(x:leftInset+550,y:2,width:160,height:28)
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
        var left=leadingContentInset
        for c in leadingControls {
            c.view.frame=NSRect(x:left,y:((bounds.height-c.height)/2).rounded(),width:c.width,height:c.height)
            left+=c.width+c.gap
        }
        let filter=leadingControls.first(where:{$0.view is PaletteFilterControls})?.view
        for view in subviews {
            var frame=view.frame
            if let filter,bounds.height > Self.actionbarHeight {
                frame.origin.y=view === filter ? 12:bounds.height-12-frame.height
            } else {frame.origin.y=((bounds.height-frame.height)/2).rounded()}
            view.frame=frame
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

/// Shared rail tree: compact branching lanes, greyscale depth headers and node rings.
/// Native outline semantics retain independent expansion and keyboard/multiple selection.
final class WorkspaceBranchTree: NSOutlineView {
    var showsConnectors=true
    var isDropTarget:((Any)->Bool)?
    var paletteDragActive=false {didSet{enumerateAvailableRowViews{row,_ in row.needsDisplay=true}}}
    var onContext:((Any,NSPoint,NSView)->Void)?
    var rowColour:((Any)->NSColor?)?
    private var hoverRow = -1
    private var tracking: NSTrackingArea?
    private var ancestors:[[Int]]=[]
    private var branchEnds:[Int:Int]=[:]
    private var previousSiblings:[Int:Int]=[:]
    private lazy var connectorOverlay=Connectors(tree:self)
    private static let laneStep:CGFloat=14 // Nine-point nodes, five-point horizontal gap.
    private static func lane(_ depth:Int)->CGFloat {13 + CGFloat(depth)*laneStep}
    private static let depthTints = ["#414141", "#707070", "#B2B2B2", "#D0D0D0"]
    static func tint(_ depth:Int)->NSColor {
        let base=Design.hex(depthTints[min(max(0,depth),depthTints.count-1)])
        return depth < depthTints.count ? base:Design.mix(base,.white,min(0.65,CGFloat(depth-depthTints.count+1)*0.10))
    }
    static var accent:NSColor {
        Theme.takesLightText(on:hexOf(Design.card) ?? "#FFFFFF") ? Design.hex("#C7C7C7"):Design.hex("#6D6D6D")
    }
    static func textColour(_ depth:Int)->NSColor {
        depth < 2 ? .white:Design.hex("#161616")
    }
    private static let trailingActionCentreInset:CGFloat=18
    private static var paletteCellTrailingInset:CGFloat {trailingActionCentreInset-10}
    override func frameOfOutlineCell(atRow row:Int)->NSRect {
        let box=rect(ofRow:row)
        return NSRect(x:max(0,bounds.width-Self.trailingActionCentreInset-10),y:box.midY-10,width:20,height:20)
    }
    override func frameOfCell(atColumn column:Int,row:Int)->NSRect {
        let box=rect(ofRow:row)
        let start:CGFloat=showsConnectors ? Self.lane(level(forRow:row))+21:16
        let isPalette:Bool={if let node=item(atRow:row) as? WorkspaceCatalogues.Node,case .palette=node.place{return true};return false}()
        let isCatalogue=(item(atRow:row) as? WorkspaceCatalogues.Node)?.catalogue != nil
        let trailing=isCatalogue ? 6:(isPalette ? Self.paletteCellTrailingInset:34)
        return NSRect(x:start,y:box.minY,width:max(0,bounds.width-start-trailing),height:box.height)
    }
    private final class Disclosure:NSButton {
        weak var tree:WorkspaceBranchTree?
        override func draw(_ dirtyRect:NSRect) {
            guard let tree else{return}
            let row=tree.row(for:self)
            let colour:NSColor
            if row >= 0,let item=tree.item(atRow:row),let background=tree.rowColour?(item) {
                colour=Theme.takesLightText(on:hexOf(background) ?? "#FFFFFF") ? .white:.black
            } else {colour=state == .on ? WorkspaceBranchTree.textColour(tree.level(forRow:max(0,row))):WorkspaceBranchTree.accent}
            let path=NSBezierPath();path.lineWidth=1.3
            path.move(to:NSPoint(x:bounds.midX-3,y:bounds.midY));path.line(to:NSPoint(x:bounds.midX+3,y:bounds.midY))
            if state != .on {path.move(to:NSPoint(x:bounds.midX,y:bounds.midY-3));path.line(to:NSPoint(x:bounds.midX,y:bounds.midY+3))}
            colour.withAlphaComponent(isHighlighted ? 1:0.75).setStroke();path.stroke()
        }
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
    final class Star:NSButton {
        var favourite=false
        var run:(()->Void)?
        init(){super.init(frame:.zero);isBordered=false;target=self;action=#selector(pressed)}
        required init?(coder:NSCoder){fatalError()}
        @objc private func pressed(){run?()}
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
        override func draw(_ dirtyRect:NSRect){
            let ink=contentTintColor ?? Design.ink
            let mark=Design.attributed(favourite ? "★":"☆",.body,colour:ink)
            mark.draw(at:NSPoint(x:(bounds.width-mark.size().width)/2,y:(bounds.height-mark.size().height)/2))
        }
    }
    final class Cell:NSTableCellView,NSDraggingSource {
        let star=Star()
        let catalogueAction=PaletteAssetIcon(frame:.zero)
        let target=PaletteAssetIcon(frame:.zero)
        let review=PaletteReviewControls(frame:.zero)
        var twoLines=false {didSet{needsLayout=true;needsDisplay=true}}
        var isPalette=false {didSet{target.isHidden = !isPalette;review.isHidden = !isPalette;needsLayout=true}}
        var renamePalette:((String)->Void)?
        private var editingName=false
        override var isFlipped:Bool{true}
        var paletteDrag:(UUID,String,[NSColor])?
        var selectPalette:(()->Void)?
        var dragChanged:((Bool)->Void)?
        private var press:(NSPoint,TimeInterval)?
        override func hitTest(_ point:NSPoint)->NSView? {
            let hit=super.hitTest(point)
            guard paletteDrag != nil,let hit else{return hit}
            if hit === star || hit === colourButton || hit === target || hit.isDescendant(of:review) || hit is InlineName {return hit}
            return self
        }
        override func mouseDown(with event:NSEvent){
            if activate(at:convert(event.locationInWindow,from:nil)){press=nil;return}
            guard paletteDrag != nil else{super.mouseDown(with:event);return}
            if event.clickCount == 2,beginRenaming(with:event){return}
            press=(event.locationInWindow,event.timestamp)
        }
        override func mouseDragged(with event:NSEvent){
            guard let press,let (id,name,colours)=paletteDrag,PaletteDrag.counts(event,from:press) else{return}
            self.press=nil;dragChanged?(true)
            PaletteDrag.begin(id,name:name,colours:colours,event:event,in:self)
        }
        override func mouseUp(with event:NSEvent){
            defer{press=nil}
            if press != nil,bounds.contains(convert(event.locationInWindow,from:nil)) {selectPalette?()}
        }
        func activate(at point:NSPoint)->Bool {
            for button in [star,colourButton,target,catalogueAction] as [NSButton] where !button.isHidden && button.frame.contains(point){button.performClick(nil);return true}
            if isPalette,review.frame.contains(point){return review.activate(at:convert(point,to:review))}
            return false
        }
        @discardableResult func beginRenaming(with event:NSEvent)->Bool {
            let point=convert(event.locationInWindow,from:nil)
            guard isPalette,let field=textField,field.frame.contains(point),!editingName else{return false}
            editingName=true;field.isHidden=true;press=nil
            InlineName.edit(field.stringValue,style:.body,in:self,x:field.frame.minX,baseline:twoLines ? 19:bounds.midY+5,width:field.frame.width,at:point,colour:field.textColor ?? Design.ink){ [weak self,weak field] value in
                self?.editingName=false;field?.isHidden=false
                if let value {self?.renamePalette?(value)}
            };return true
        }
        func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation {.copy}
        func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation){dragChanged?(false)}
        let countLabel=NSTextField(labelWithString:"")
        final class ColourButton:NSButton {
            var colour=Design.card {didSet{needsDisplay=true}}
            var run:(()->Void)?
            init(){super.init(frame:.zero);isBordered=false;target=self;action=#selector(pressed)}
            required init?(coder:NSCoder){fatalError()}
            @objc private func pressed(){run?()}
            override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
            override func draw(_ dirtyRect:NSRect){
                let box=NSRect(x:(bounds.width-12)/2,y:(bounds.height-12)/2,width:12,height:12)
                colour.setFill();box.fill()
                (Theme.takesLightText(on:hexOf(colour) ?? "#FFFFFF") ? NSColor.white:NSColor.black).setStroke()
                NSBezierPath(rect:box.insetBy(dx:0.5,dy:0.5)).stroke()
            }
        }
        let colourButton=ColourButton()
        var compactMetadata=false
        var warning=false
        var symbol:String? {didSet{needsLayout=true;needsDisplay=true}}
        override init(frame:NSRect){
            super.init(frame:frame);addSubview(star);addSubview(colourButton);colourButton.isHidden=true
            addSubview(target);addSubview(review);target.isHidden=true;review.isHidden=true
            addSubview(catalogueAction);catalogueAction.isHidden=true
            countLabel.font=Design.Text.body.font();countLabel.alignment = .right;countLabel.isHidden=true;addSubview(countLabel)
        }
        required init?(coder:NSCoder){fatalError()}
        override func layout() {
            super.layout()
            let height=textField?.intrinsicContentSize.height ?? 18
            let inset:CGFloat=symbol == nil ? 0:24
            let countWidth:CGFloat=countLabel.isHidden ? 0:max(24,countLabel.intrinsicContentSize.width+8)
            let reviewWidth=PaletteReviewControls.width
            if !catalogueAction.isHidden {
                catalogueAction.frame=NSRect(x:max(0,bounds.width-28),y:0,width:28,height:bounds.height)
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,catalogueAction.frame.minX-inset-8),height:height)
                return
            }
            if compactMetadata {
                textField?.frame=NSRect(x:inset,y:(bounds.height-height)/2,width:max(0,bounds.width-inset-countWidth-8),height:height)
                countLabel.frame=NSRect(x:bounds.width-countWidth,y:(bounds.height-height)/2,width:countWidth,height:height)
                return
            }
            if twoLines {
                textField?.frame=NSRect(x:inset,y:(28-height)/2,width:max(0,bounds.width-inset-countWidth-8),height:height)
                countLabel.frame=NSRect(x:bounds.width-countWidth,y:(28-height)/2,width:max(0,countWidth-4),height:height)
                star.frame=NSRect(x:0,y:28,width:24,height:28)
                target.frame=NSRect(x:24,y:28,width:24,height:28)
                review.frame=NSRect(x:bounds.width-reviewWidth,y:28,width:reviewWidth,height:28)
                return
            }
            // Parent cells reserve their disclosure lane; counts share the palette count column.
            let parentCorrection:CGFloat=isPalette ? 0:34-WorkspaceBranchTree.paletteCellTrailingInset
            let nameStart:CGFloat=isPalette ? inset+44+(colourButton.isHidden ? 0:22):inset
            let trailing:CGFloat=countLabel.isHidden ? 0:reviewWidth+countWidth+4-parentCorrection
            textField?.frame=NSRect(x:nameStart,y:(bounds.height-height)/2,width:max(0,bounds.width-nameStart-trailing),height:height)
            star.frame=NSRect(x:isPalette ? inset+(colourButton.isHidden ? 0:22):bounds.width-22,y:0,width:22,height:bounds.height)
            target.frame=NSRect(x:star.frame.maxX,y:0,width:22,height:bounds.height)
            review.frame=NSRect(x:bounds.width-reviewWidth+parentCorrection,y:0,width:reviewWidth,height:bounds.height)
            countLabel.frame=NSRect(x:review.frame.minX-countWidth-4,y:(bounds.height-height)/2,width:max(0,countWidth-4),height:height)
            colourButton.frame=NSRect(x:inset,y:0,width:22,height:bounds.height)
        }
        override func draw(_ dirtyRect:NSRect){
            super.draw(dirtyRect)
            guard let symbol,let label=textField else{return}
            if warning {ResultGlyph.warning.draw(in:NSRect(x:0,y:((twoLines ? 28:bounds.height)-16)/2,width:16,height:16));return}
            let image=RowMark.image(symbol,colour:label.textColor ?? Design.ink),size=image.size
            image.draw(in:NSRect(x:(14-size.width)/2,y:((twoLines ? 28:bounds.height)-size.height)/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
    }
    override func makeView(withIdentifier identifier:NSUserInterfaceItemIdentifier,owner:Any?)->NSView? {
        if identifier == NSOutlineView.disclosureButtonIdentifier {
            let button=Disclosure(frame:NSRect(x:0,y:0,width:20,height:20))
            button.tree=self;button.identifier=identifier;button.setButtonType(.onOff);button.isBordered=false
            button.target=self;button.action=#selector(toggleFolder(_:));return button
        }
        return super.makeView(withIdentifier:identifier,owner:owner)
    }
    @objc private func toggleFolder(_ sender:NSButton) {
        let index=row(for:sender)
        guard index >= 0,let item=item(atRow:index) else{return}
        if isItemExpanded(item){collapseItem(item)}else{expandItem(item)}
        sender.state=isItemExpanded(item) ? .on:.off;refreshSurfaces()
    }
    override func keyDown(with event:NSEvent){
        if (event.keyCode == 125 || event.keyCode == 126),event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,numberOfRows > 0 {
            let next=min(numberOfRows-1,max(0,selectedRow+(event.keyCode == 125 ? 1:-1)))
            selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false)
            scrollRowToVisible(next);return
        }
        super.keyDown(with:event)
    }
    override func mouseDown(with event:NSEvent) {
        let point=convert(event.locationInWindow,from:nil),index=row(at:point)
        if index >= 0,let cell=view(atColumn:0,row:index,makeIfNecessary:false) as? Cell {
            let local=cell.convert(event.locationInWindow,from:nil)
            if cell.activate(at:local){return}
            if event.clickCount == 2,cell.beginRenaming(with:event){return}
        }
        window?.makeFirstResponder(self)
        let node=index >= 0 ? item(atRow:index):nil
        let expanded=node.map{isItemExpanded($0)} ?? false
        let disclosure=index >= 0 && (frameOfOutlineCell(atRow:index).contains(point) || point.x >= bounds.width-56)
        super.mouseDown(with:event)
        guard let node,isExpandable(node),!disclosure,event.clickCount == 1,
              event.modifierFlags.intersection([.shift,.command,.control,.option]).isEmpty else{return}
        if expanded{collapseItem(node)}else{expandItem(node)}
        refreshSurfaces()
    }
    override func rightMouseDown(with event:NSEvent){
        let point=convert(event.locationInWindow,from:nil),index=row(at:point)
        guard index >= 0,let node=item(atRow:index) else{return}
        onContext?(node,point,self)
    }
    override func draggingExited(_ sender:NSDraggingInfo?){super.draggingExited(sender);paletteDragActive=false}
    override func draggingEnded(_ sender:NSDraggingInfo){super.draggingEnded(sender);paletteDragActive=false}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking{removeTrackingArea(tracking)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);tracking=area
    }
    private func setHover(_ index:Int) {
        guard hoverRow != index else{return}
        let old=hoverRow;hoverRow=index
        connectorOverlay.needsDisplay=true
        for row in [old,index] where row >= 0 && row < numberOfRows {rowView(atRow:row,makeIfNecessary:false)?.needsDisplay=true}
    }
    override func mouseMoved(with event:NSEvent){setHover(row(at:convert(event.locationInWindow,from:nil)))}
    override func mouseExited(with event:NSEvent){setHover(-1)}
    override func resetCursorRects(){addCursorRect(visibleRect,cursor:.pointingHand)}
    func refreshCell(_ index:Int) {
        guard index >= 0,let item=item(atRow:index),let cell=view(atColumn:0,row:index,makeIfNecessary:false) as? Cell else{return}
        let expanded=isItemExpanded(item)
        cell.textField?.font=(expanded ? Design.Text.bodyStrong:Design.Text.body).font()
        if let colour=rowColour?(item) {
            cell.textField?.textColor=Theme.takesLightText(on:hexOf(colour) ?? "#FFFFFF") ? .white:.black
            cell.colourButton.colour=colour
        } else {
            cell.textField?.textColor=expanded ? Self.textColour(level(forRow:index)):Design.ink
            cell.colourButton.colour=Design.card
        }
        cell.star.contentTintColor=cell.textField?.textColor;cell.star.needsDisplay=true
        cell.target.ink=cell.textField?.textColor ?? Design.ink;cell.review.ink=cell.textField?.textColor ?? Design.ink
        cell.catalogueAction.ink=cell.textField?.textColor ?? Design.ink
        cell.countLabel.font=cell.textField?.font
        cell.countLabel.textColor=cell.textField?.textColor
        cell.needsDisplay=true
    }
    func refreshSurfaces() {
        // Cache visible ancestry once per expansion; drawing never scans the folder list.
        ancestors=[];branchEnds=[:];previousSiblings=[:]
        var stack:[Int]=[]
        for index in 0..<numberOfRows {
            let depth=level(forRow:index)
            if stack.count > depth {stack.removeLast(stack.count-depth)}
            ancestors.append(stack)
            let parent=stack.last ?? -1 // The root folders share their own trunk.
            previousSiblings[index]=branchEnds[parent]
            branchEnds[parent]=index
            stack.append(index)
        }
        enumerateAvailableRowViews { [weak self] row,index in row.needsDisplay=true;self?.refreshCell(index) }
        needsDisplay=true;connectorOverlay.needsDisplay=true
    }
    func installConnectors(in host:NSView){host.addSubview(connectorOverlay);connectorOverlay.isHidden = !showsConnectors}
    func layoutConnectors(){connectorOverlay.frame=frame;connectorOverlay.isHidden = !showsConnectors || isHidden;connectorOverlay.needsDisplay=true}
    private func terminal(_ index:Int)->Bool {
        guard index < ancestors.count else{return false}
        return branchEnds[ancestors[index].last ?? -1] == index
    }
    private func active(_ index:Int)->Bool {
        isRowSelected(index) || hoverRow == index || item(atRow:index).map{isItemExpanded($0)} == true
    }
    private func nodeRadius(_ index:Int)->CGFloat {active(index) || terminal(index) ? 8:4.5}
    /// One transparent canvas spans every row, so a curve is never split at a cell seam.
    private final class Connectors:NSView {
        weak var tree:WorkspaceBranchTree?
        init(tree:WorkspaceBranchTree){self.tree=tree;super.init(frame:.zero)}
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool {true}
        override func hitTest(_ point:NSPoint)->NSView? {nil}
        override func draw(_ dirtyRect:NSRect){
            guard let tree else{return}
            let ink=WorkspaceBranchTree.accent
            let lines=NSBezierPath();lines.lineWidth=1.2
            for index in 0..<min(tree.numberOfRows,tree.ancestors.count) {
                let parent=tree.ancestors[index].last ?? -1
                let x=WorkspaceBranchTree.lane(tree.level(forRow:index))
                let y=tree.rect(ofRow:index).midY-tree.nodeRadius(index)
                if let previous=tree.previousSiblings[index] {
                    let start=tree.rect(ofRow:previous).midY+tree.nodeRadius(previous)
                    guard NSRect(x:x-1,y:start,width:2,height:max(1,y-start)).intersects(dirtyRect) else{continue}
                    lines.move(to:NSPoint(x:x,y:start));lines.line(to:NSPoint(x:x,y:y))
                } else if parent >= 0 {
                    let px=WorkspaceBranchTree.lane(tree.level(forRow:parent))
                    let start=tree.rect(ofRow:parent).midY+tree.nodeRadius(parent)
                    guard NSRect(x:px-1,y:start,width:x-px+2,height:max(1,y-start)).intersects(dirtyRect) else{continue}
                    let reach=(y-start)*0.65
                    lines.move(to:NSPoint(x:px,y:start))
                    lines.curve(to:NSPoint(x:x,y:y),
                        controlPoint1:NSPoint(x:px,y:start+reach),
                        controlPoint2:NSPoint(x:x,y:y-reach))
                }
            }
            ink.withAlphaComponent(0.65).setStroke();lines.stroke()
            for index in 0..<tree.numberOfRows {
                let row=tree.rect(ofRow:index)
                guard row.intersects(dirtyRect) else{continue}
                let x=WorkspaceBranchTree.lane(tree.level(forRow:index)),y=row.midY
                let depth=tree.level(forRow:index)
                let ground=depth > 0 ? Design.mix(Design.card,WorkspaceBranchTree.tint(depth-1),0.045):Design.card
                let ring=tree.active(index) || tree.terminal(index)
                if ring {
                    let outer=NSBezierPath(ovalIn:NSRect(x:x-8,y:y-8,width:16,height:16))
                    ground.setFill();outer.fill();ink.withAlphaComponent(0.65).setStroke();outer.lineWidth=1;outer.stroke()
                }
                let dot=NSBezierPath(ovalIn:NSRect(x:x-4.5,y:y-4.5,width:9,height:9))
                (tree.active(index) ? ink:ground).setFill();dot.fill()
                ink.setStroke();dot.lineWidth=1;dot.stroke()
            }
        }
    }
    final class Row:NSTableRowView {
        weak var accordion:WorkspaceBranchTree?
        override func drawBackground(in dirtyRect:NSRect) {
            guard let tree=accordion else{return}
            let index=tree.row(for:self)
            guard index >= 0,let item=tree.item(atRow:index) else{return}
            let depth=tree.level(forRow:index),expanded=tree.isItemExpanded(item)
            let accent=WorkspaceBranchTree.accent
            let lane=WorkspaceBranchTree.lane(depth)
            if depth > 0 {
                fill(bounds,Design.mix(Design.card,WorkspaceBranchTree.tint(depth-1),0.045))
            }
            if expanded || isSelected || tree.hoverRow == index || tree.rowColour?(item) != nil {
                let inset:CGFloat=tree.showsConnectors ? lane+13:8
                let box=NSRect(x:inset,y:3,width:max(0,bounds.width-inset-4),height:bounds.height-6)
                let colour=tree.rowColour?(item) ?? (expanded ? WorkspaceBranchTree.tint(depth):Design.mix(Design.card,accent,isSelected ? 0.17:0.09))
                colour.setFill();NSBezierPath(roundedRect:box,xRadius:7,yRadius:7).fill()
            }
            if tree.paletteDragActive,tree.isDropTarget?(item) == true {
                Design.houseYellow.setStroke()
                let box=NSRect(x:lane+13,y:2,width:max(0,bounds.width-lane-18),height:bounds.height-4)
                let path=NSBezierPath(roundedRect:box,xRadius:7,yRadius:7);path.lineWidth=2;path.stroke()
            }
            tree.refreshCell(index)
        }
        override func drawSelection(in dirtyRect:NSRect) {} // Selection belongs to the timeline surface.
    }
}

enum WorkspaceImageScanEvent { case began, batch, completed }

final class WorkspaceImageIntakePane:NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, WorkspacePanelContentMetrics, WorkspaceRailAwareContent, WorkspacePinnedPanelContent {
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
    var scrollbarOnLeft=false
    var onImageFiles:((URL?,[URL],WorkspaceImageScanEvent)->Void)?
    private static let favouritesKey="Workspace.Import.FavouriteFolders"
    private static let favouriteRecordsKey="Workspace.Import.Favourites"
    private var favouritePaths:[String]=[]
    private var favouriteRoots:[Node]=[]
    private let favouriteOutline=WorkspaceBranchTree()
    private let favouritesHeading=NSTextField(labelWithString:"Favourites")
    private let systemHeading=NSTextField(labelWithString:"System")
    private let noFavourites=NSTextField(labelWithString:"No favourites listed")
    private let folderMenu=SwissContextMenu()
    private var selectedTree:WorkspaceBranchTree?
    private var favouritesHeight:CGFloat {favouriteRoots.isEmpty ? 28:CGFloat(favouriteOutline.numberOfRows)*34}
    private final class ControlsHeader:NSView {
        override var isFlipped:Bool {true}
        override func draw(_ dirtyRect:NSRect){fill(bounds,Design.card);hairline(x:0,y:bounds.height-1,width:bounds.width)}
    }
    private let controlsHeader=ControlsHeader()
    var pinnedControls:NSView {controlsHeader}
    var pinnedControlsHeight:CGFloat {32}
    var controlsArePinned=false {didSet{needsLayout=true}}
    var minimumContentHeight:CGFloat {(controlsArePinned ? 0:32)+28+favouritesHeight+28+CGFloat(outline.numberOfRows)*outline.rowHeight}
    private var roots:[Node]=[]
    private var systemRootPaths=Set<String>()
    private var volumeObservers:[NSObjectProtocol]=[]
    private var activationObserver:NSObjectProtocol?
    private var selectedFolder:Node?
    private var rebuilding=false
    private var scanGeneration=0
    private var scanCancellation:ScanCancellation?
    private var includeNested=false
    private let outline=WorkspaceBranchTree()
    private let nestedFolders=SwissCheckbox("Include Nested Folders")
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
        favouritePaths=AppPreferences.shared.stringArray(forKey:Self.favouritesKey) ?? []
        if AppPreferences.shared.object(forKey:Self.favouriteRecordsKey) != nil {
            favouritePaths=WorkspaceFavourites.records(Self.favouriteRecordsKey).compactMap{$0["id"]}
        }
        favouriteRoots=favouritePaths.map{Node(url:URL(fileURLWithPath:$0,isDirectory:true),isDirectory:true,isRoot:true)}
        WorkspaceFavourites.sync(Self.favouriteRecordsKey,entries:favouriteRoots.map{($0.url.standardizedFileURL.path,$0.title)})
        for tree in [favouriteOutline,outline] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("Image Folder Tree"))
            tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
            tree.rowHeight=34;tree.indentationPerLevel=0;tree.intercellSpacing=NSSize(width:0,height:0)
            tree.backgroundColor=Design.card;tree.appearance=Theme.appearance;tree.style = .plain
            tree.dataSource=self;tree.delegate=self;tree.focusRingType = .none;tree.allowsMultipleSelection=true
            tree.onContext={ [weak self] item,point,view in if let node=item as? Node {self?.showFolderMenu(node,at:point,in:view)} }
            tree.rowColour={ item in
                guard let node=item as? Node else{return nil}
                return WorkspaceFavourites.colour(Self.favouriteRecordsKey,id:node.url.standardizedFileURL.path)
            }
        }
        outline.setAccessibilityLabel("System folder tree")
        favouriteOutline.setAccessibilityLabel("Favourite folder tree")
        for heading in [favouritesHeading,systemHeading] {heading.font=Design.Text.bodyStrong.font();heading.textColor=Design.ink;addSubview(heading)}
        noFavourites.font=Design.Text.body.font();noFavourites.textColor=Design.quiet;addSubview(noFavourites)
        nestedFolders.font=Design.Text.body.font();nestedFolders.contentTintColor=Design.ink
        nestedFolders.target=self;nestedFolders.action=#selector(nestedFoldersChanged)
        nestedFolders.setAccessibilityLabel("Include Nested Folders")
        controlsHeader.addSubview(nestedFolders);addSubview(controlsHeader)
        for tree in [favouriteOutline,outline] {addSubview(tree);tree.installConnectors(in:self)}
        favouriteOutline.reloadData();favouriteOutline.refreshSurfaces()
        reloadRoots()
        let workspace=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification,NSWorkspace.didUnmountNotification,NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(workspace.addObserver(forName:name,object:nil,queue:.main){ [weak self] _ in self?.reloadRoots() })
        }
        activationObserver=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){ [weak self] _ in self?.reloadRoots() }
    }
    deinit {
        for observer in volumeObservers {NSWorkspace.shared.notificationCenter.removeObserver(observer)}
        if let activationObserver {NotificationCenter.default.removeObserver(activationObserver)}
        scanCancellation?.cancel()
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        if !controlsArePinned {controlsHeader.frame=NSRect(x:0,y:0,width:bounds.width,height:32)}
        nestedFolders.frame=NSRect(x:16,y:0,width:max(0,bounds.width-32),height:32)
        let offset:CGFloat=controlsArePinned ? 32:0
        favouritesHeading.frame=NSRect(x:16,y:38-offset,width:max(0,bounds.width-32),height:20)
        noFavourites.frame=NSRect(x:16,y:64-offset,width:max(0,bounds.width-32),height:22)
        noFavourites.isHidden = !favouriteRoots.isEmpty
        favouriteOutline.isHidden=favouriteRoots.isEmpty
        favouriteOutline.frame=NSRect(x:0,y:60-offset,width:bounds.width,height:favouriteRoots.isEmpty ? 0:favouritesHeight)
        let systemY=60-offset+favouritesHeight
        systemHeading.frame=NSRect(x:16,y:systemY+6,width:max(0,bounds.width-32),height:20)
        outline.frame=NSRect(x:0,y:systemY+28,width:bounds.width,height:max(0,bounds.height-systemY-28))
        for tree in [favouriteOutline,outline] {tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()}
    }
    override func draw(_ dirtyRect:NSRect){
        if !controlsArePinned {hairline(x:0,y:32,width:bounds.width,Design.rule)}
        hairline(x:0,y:(controlsArePinned ? 28:60)+favouritesHeight,width:bounds.width,Design.rule)
    }
    private func isFavourite(_ node:Node)->Bool {favouritePaths.contains(node.url.standardizedFileURL.path)}
    private func tree(for node:Node)->WorkspaceBranchTree {favouriteOutline.row(forItem:node) >= 0 ? favouriteOutline:outline}
    private func toggleFavourite(_ node:Node){
        let path=node.url.standardizedFileURL.path
        if let index=favouritePaths.firstIndex(of:path) {
            favouritePaths.remove(at:index);favouriteRoots.removeAll{$0.url.standardizedFileURL.path == path}
        } else {favouritePaths.append(path);favouriteRoots.append(Node(url:node.url,isDirectory:true,isRoot:true))}
        AppPreferences.shared.set(favouritePaths,forKey:Self.favouritesKey)
        WorkspaceFavourites.sync(Self.favouriteRecordsKey,entries:favouriteRoots.map{($0.url.standardizedFileURL.path,$0.title)})
        rebuilding=true
        favouriteOutline.reloadData();favouriteOutline.refreshSurfaces()
        rebuilding=false
        for tree in [outline,favouriteOutline] {
            tree.enumerateAvailableRowViews { [weak self] _,index in
                guard let self,let node=tree.item(atRow:index) as? Node,
                      let cell=tree.view(atColumn:0,row:index,makeIfNecessary:false) as? WorkspaceBranchTree.Cell else{return}
                self.configureStar(cell,node:node,in:tree)
            }
            tree.refreshSurfaces()
        }
        refreshExtent();needsDisplay=true
    }
    private func configureStar(_ cell:WorkspaceBranchTree.Cell,node:Node,in tree:NSOutlineView){
        cell.star.favourite=isFavourite(node)
        cell.star.setAccessibilityLabel((cell.star.favourite ? "Remove Favourite: ":"Add Favourite: ")+node.title)
        cell.star.toolTip=cell.star.favourite ? "Remove From Favourites":"Add To Favourites"
        cell.star.run={ [weak self,weak node] in if let node {self?.toggleFavourite(node)} }
        cell.star.needsDisplay=true
        cell.colourButton.isHidden = tree !== favouriteOutline || !isFavourite(node)
        if !cell.colourButton.isHidden {
            let path=node.url.standardizedFileURL.path
            cell.colourButton.colour=WorkspaceFavourites.colour(Self.favouriteRecordsKey,id:path) ?? Design.card
            cell.colourButton.setAccessibilityLabel("Favourite Colour: "+node.title)
            cell.colourButton.run={ [weak self] in
                guard let self else{return}
                WorkspaceFavourites.pick(key:Self.favouriteRecordsKey,id:path,title:node.title,over:self){ [weak self] in
                    self?.outline.refreshSurfaces();self?.favouriteOutline.refreshSurfaces()
                }
            }
        }
        cell.needsLayout=true
    }
    private func showFolderMenu(_ node:Node,at point:NSPoint,in view:NSView){
        folderMenu.open([
            HaloAction(id:"finder",label:"Show in Finder",symbol:"folder",onSelect:{NSWorkspace.shared.activateFileViewerSelecting([node.url])}),
            HaloAction(id:"favourite",label:isFavourite(node) ? "Remove From Favourites":"Add To Favourites",symbol:"star",onSelect:{[weak self] in self?.toggleFavourite(node)})
        ],at:point,in:view)
    }
    private func refreshExtent(){
        needsLayout=true
        var ancestor=superview
        while let view=ancestor {
            if let panel=view as? WorkspacePanel {panel.rail?.arrange();break}
            ancestor=view.superview
        }
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
        guard let volumes=FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:[.volumeNameKey],options:[.skipHiddenVolumes]) else{return}
        let path:(URL)->String={$0.standardizedFileURL.path}
        var seen=Set<String>()
        let system=([Self.userHome,disk]+volumes).filter{seen.insert(path($0)).inserted}
        let newPaths=Set(system.map(path)),removed=systemRootPaths.subtracting(newPaths)
        // Reuse objects so loaded children, independent expansion and selection survive hot-plugging.
        let existing=Dictionary(roots.map{(path($0.url),$0)},uniquingKeysWith:{first,_ in first})
        let extras=roots.filter{!systemRootPaths.contains(path($0.url)) && !newPaths.contains(path($0.url))}
        let expanded=(0..<outline.numberOfRows).compactMap{index -> Node? in
            guard let node=outline.item(atRow:index) as? Node,outline.isItemExpanded(node) else{return nil}
            return node
        }
        let selected=outline.selectedRowIndexes.compactMap{outline.item(atRow:$0) as? Node}
        roots=system.map{existing[path($0)] ?? Node(url:$0,isDirectory:true,isRoot:true)}+extras
        systemRootPaths=newPaths
        func disconnected(_ url:URL)->Bool {
            let value=path(url)
            return removed.contains{value == $0 || value.hasPrefix($0+"/")}
        }
        rebuilding=true
        outline.reloadData()
        for node in expanded where outline.row(forItem:node) >= 0 {outline.expandItem(node)}
        let indexes=IndexSet(selected.compactMap{node -> Int? in
            let index=outline.row(forItem:node);return index >= 0 ? index:nil
        })
        outline.selectRowIndexes(indexes,byExtendingSelection:false)
        // Keep saved favourites, but discard stale descendants from a disk that has gone away.
        for node in favouriteRoots where disconnected(node.url) {
            favouriteOutline.collapseItem(node,collapseChildren:true);node.children=nil
            favouriteOutline.reloadItem(node,reloadChildren:true)
        }
        if let folder=selectedFolder,disconnected(folder.url) {
            selectedFolder=nil;selectedTree=nil
            outline.deselectAll(nil);favouriteOutline.deselectAll(nil)
            scanGeneration+=1;scanCancellation?.cancel()
            onImageFiles?(nil,[],.began);onImageFiles?(nil,[],.completed)
        }
        rebuilding=false
        outline.refreshSurfaces();favouriteOutline.refreshSurfaces();refreshExtent()
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
            let tree=self.tree(for:chosen),row=tree.row(forItem:chosen)
            if row>=0 {tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            tree.expandItem(chosen)
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
                guard values.isDirectory == true else{return nil}
                return Node(url:child,isDirectory:true)
            }.sorted{
                if $0.isDirectory != $1.isDirectory{return $0.isDirectory}
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            DispatchQueue.main.async { [weak self,weak node] in
                guard let self,let node else{return};node.children=found;node.loading=false
                let tree=self.tree(for:node),expanded=tree.isItemExpanded(node)
                if tree.row(forItem:node) >= 0 {
                    tree.reloadItem(node,reloadChildren:true)
                    if expanded{tree.expandItem(node)}
                }
                tree.refreshSurfaces();self.refreshExtent()
                if self.selectedFolder === node {
                    self.publishSelection()
                }
            }
        }
    }
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{
        guard let node=item as? Node else{return outlineView === favouriteOutline ? favouriteRoots.count:roots.count};return node.children?.count ?? 0
    }
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{
        guard let node=item as? Node else{return outlineView === favouriteOutline ? favouriteRoots[index]:roots[index]};return node.children![index]
    }
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{
        let node=item as! Node
        return node.isDirectory && node.children?.isEmpty != true
    }
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{
        let row=WorkspaceBranchTree.Row();row.accordion=outlineView as? WorkspaceBranchTree;return row
    }
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:outlineView.tableColumns[0].width,height:34))
        let label=NSTextField(labelWithString:node.title)
        label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel(node.isDirectory ? "Folder: \(node.title)":"Image: \(node.title)")
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.url.path;configureStar(cell,node:node,in:outlineView)
        return cell
    }
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node {load(node)};(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    func outlineViewItemDidCollapse(_ notification:Notification){(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    func outlineViewSelectionDidChange(_ notification:Notification){
        guard !rebuilding,let tree=notification.object as? WorkspaceBranchTree else{return}
        selectedTree=tree
        rebuilding=true;(tree === outline ? favouriteOutline:outline).deselectAll(nil);rebuilding=false
        outline.refreshSurfaces();favouriteOutline.refreshSurfaces();publishSelection()
    }
    private func publishSelection(){
        let tree=selectedTree ?? outline
        let nodes=tree.selectedRowIndexes.compactMap{tree.item(atRow:$0) as? Node}
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
    var minimumContentHeight:CGFloat {170}
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
        override func tile(){super.tile();documentView?.setFrameSize(NSSize(width:max(tabWidth,contentView.bounds.width),height:32))}
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
            let top:CGFloat=0.5,bottom=bounds.height-0.5
            let trigger=pane.moreButton.isHidden ? pane.newButton:pane.moreButton
            let foot=max(0,trigger.frame.minX-28),crest=max(0,trigger.frame.minX-4)
            let end=min(pane.strip.frame.maxX,max(0,pane.strip.tabWidth-pane.strip.contentView.bounds.minX))
            let controls=NSBezierPath();controls.move(to:NSPoint(x:foot,y:bottom))
            controls.curve(to:NSPoint(x:crest,y:top),controlPoint1:NSPoint(x:foot+12,y:bottom),controlPoint2:NSPoint(x:crest-12,y:top))
            controls.line(to:NSPoint(x:bounds.width,y:top))
            let ground=controls.copy() as! NSBezierPath;ground.line(to:NSPoint(x:bounds.width,y:bottom));ground.close();Design.card.setFill();ground.fill()
            let border=NSBezierPath()
            border.move(to:NSPoint(x:min(end,foot),y:bottom));border.line(to:NSPoint(x:foot,y:bottom));border.append(controls)
            border.lineWidth=1;Design.rule.setStroke();border.stroke()
        }
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
            let buttons=owner?.root is Pane ? [newButton,splitButton,belowButton]:[newButton,splitButton,belowButton,closeButton]
            let menu=SwissDropdown.MenuPanel(items:buttons.map{$0.toolTip ?? "Panel Action"},chosen:"",width:44,literalItems:true){ [weak self] index in
                self?.dismissOverlay();guard buttons.indices.contains(index) else{return};buttons[index].run?()
            }
            menu.setLeadingSymbols(Dictionary(uniqueKeysWithValues:buttons.enumerated().map{($0.offset,($0.element.symbol,Design.ink))}));menu.setIconsOnly()
            menu.place(anchoredTo:window.convertToScreen(moreButton.convert(moreButton.bounds,to:nil)),within:window)
            window.addChildWindow(menu,ordered:.above);toolMenu=menu;Overlays.opened(self)
        }
        fileprivate let strip=TabScroll(),document=Content(frame:.zero)
        fileprivate let contour=HeaderContour(frame:.zero)
        private var revealSelection=true,lastStripWidth:CGFloat = -1
        fileprivate var labels:[TabButton]=[]
        fileprivate let shade=DropShade(frame:.zero)
        fileprivate var zone=Zone.centre
        override init(frame:NSRect){
            super.init(frame:frame)
            strip.drawsBackground=false;strip.contentView.drawsBackground=false;document.paintsGround=false;strip.hasVerticalScroller=false;strip.hasHorizontalScroller=false;strip.documentView=document
            contour.pane=self;addSubview(contour);addSubview(strip);for b in [newButton,splitButton,belowButton,closeButton,moreButton]{addSubview(b)}
            moreButton.symbol="chevron.down";moreButton.toolTip="Panel Actions";moreButton.setAccessibilityLabel("Panel Actions");moreButton.run={ [weak self] in self?.openTools() }
            registerForDraggedTypes([LibraryPageLayout.tabDragType]);setAccessibilityIdentifier("library-pane-"+id.uuidString)
        }
        required init?(coder:NSCoder){fatalError()}
        override var isFlipped:Bool{true}
        fileprivate func render(){
            dismissOverlay()
            for view in subviews where view !== strip && view !== newButton && view !== splitButton && view !== belowButton && view !== closeButton && view !== moreButton && view !== shade && view !== contour{view.removeFromSuperview()}
            if let tab=selectedTab {tab.content.removeFromSuperview();addSubview(tab.content,positioned:.below,relativeTo:contour)}
            labels.forEach{$0.removeFromSuperview()};labels=[]
            for tab in tabs {let label=TabButton(tab:tab,pane:self);document.addSubview(label);labels.append(label)}
            revealSelection=true;needsLayout=true
        }
        override func layout(){
            super.layout();selectedTab?.content.frame=bounds
            let compact=bounds.width < Self.compactControlsWidth
            if moreButton.isHidden == compact{dismissOverlay()}
            moreButton.isHidden = !compact
            for button in [newButton,splitButton,belowButton]{button.isHidden=compact}
            closeButton.isHidden=compact || owner?.root is Pane
            let buttons=compact ? [moreButton]:(closeButton.isHidden ? [newButton,splitButton,belowButton]:[newButton,splitButton,belowButton,closeButton])
            let controlsWidth=CGFloat(buttons.count)*36
            strip.frame=NSRect(x:0,y:AreaHeader.headingBaseline-21,width:max(0,bounds.width-20-controlsWidth-28),height:32)
            contour.frame=NSRect(x:0,y:strip.frame.minY,width:bounds.width,height:32)
            var x:CGFloat=0
            for label in labels {label.updateTitle();let width=min(480,max(72,Design.attributed(label.name,.bodyStrong).size().width+36+8+TabButton.curve));label.frame=NSRect(x:x,y:0,width:width,height:32);x+=width;label.needsDisplay=true}
            strip.tabWidth=x;document.frame=NSRect(x:0,y:0,width:max(x,strip.contentSize.width),height:32)
            if lastStripWidth != strip.frame.width{lastStripWidth=strip.frame.width;revealSelection=true}
            if revealSelection,let label=labels.first(where:{$0.tab.id == selected}){label.scrollToVisible(label.bounds);revealSelection=false}
            for (i,b) in buttons.enumerated(){b.ink=Design.ink;b.frame=NSRect(x:bounds.width-16-controlsWidth+CGFloat(i)*36,y:AreaHeader.headingBaseline-21,width:32,height:32)}
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
        static let curve:CGFloat=28
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
            let edge=NSBezierPath(),h=bounds.height-0.5,w=bounds.width-0.5,c=Self.curve
            edge.move(to:NSPoint(x:0,y:0.5));edge.line(to:NSPoint(x:w-c,y:0.5))
            edge.curve(to:NSPoint(x:w,y:h),controlPoint1:NSPoint(x:w-c/2,y:0.5),controlPoint2:NSPoint(x:w-c/2,y:h))
            let ground=edge.copy() as! NSBezierPath;ground.line(to:NSPoint(x:0,y:h));ground.close();(selected ? Design.card:Design.mist).setFill();ground.fill()
            edge.lineWidth=1;Design.rule.setStroke();edge.stroke()
            let symbol:String
            switch tab.controller?.place ?? tab.route {
            case .some(.palette),.some(.palettes):symbol="swatchpalette"
            case nil:symbol="plus"
            default:symbol="folder"
            }
            RowMark.image(symbol,colour:Design.quiet).draw(in:NSRect(x:16,y:9,width:14,height:14),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            Design.attributed(name,selected ? .bodyStrong:.body).draw(x:36,baseline:21,width:max(0,bounds.width-36-Self.curve-8))
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
    var currentPlace:(()->StudioFrame.Place)?
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
    fileprivate func name(of tab:Tab)->String{guard let place=tab.controller?.place ?? tab.route else{return "New Panel"};return titleForPlace?(place) ?? "Library"}
    private func activateAncestor(of hit:NSView?){var view=hit;while let candidate=view{if let pane=candidate as? Pane{activate(pane);return};view=candidate.superview}}
    private func activate(_ pane:Pane){active.layer?.borderWidth=0;active=pane;pane.wantsLayer=true;pane.layer?.borderWidth=1;pane.layer?.borderColor=Design.houseYellow.cgColor;onActivate?(pane.controller)}
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
    /// Page templates carry the currently focused tab into the first slot; other slots start empty.
    func restore(_ saved:WorkspaceLayoutTemplate.Node,activePane:UUID,pageOnly:Bool)throws {
        guard saved.paneCount > 0,saved.paneCount <= 32,saved.tabCount > 0,saved.tabCount <= 128 else{throw failure("This layout has too many panels or tabs.")}
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
        if let target=target ?? panes().first{activate(target)};needsLayout=true;layoutSubtreeIfNeeded();viewRestores.forEach{$0()}
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
    private func load(_ pane:Pane,place:StudioFrame.Place){
        guard let tab=pane.selectedTab else{return};tab.route=place
        if let controller=tab.controller{controller.go(place);pane.needsLayout=true;return}
        guard let controller=makePage?(place) else{return};choices.removeValue(forKey:tab.id);tab.controller=controller;tab.content=controller;pane.render();activate(pane)
    }
    private func newTab(in pane:Pane,source:StudioFrame.Place){let tab=Tab();tab.source=source;pane.tabs.append(tab);pane.selected=tab.id;chooser(tab,in:pane);pane.render();activate(pane)}
    @discardableResult private func split(_ old:Pane,vertical:Bool,before:Bool)->Pane{
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
        content.arrange={ [weak content,weak pane] in guard let content else{return};scroll.frame=NSRect(x:0,y:AreaHeader.rule+1,width:content.bounds.width,height:max(0,content.bounds.height-AreaHeader.rule-1));document.frame=NSRect(x:0,y:0,width:scroll.contentSize.width,height:max(288,scroll.contentSize.height));for (i,b) in buttons.enumerated(){b.isHidden = i == buttons.count-1 && (pane?.owner?.root is Pane);b.frame=NSRect(x:16,y:16+CGFloat(i)*44,width:max(0,min(b.intrinsicContentSize.width,content.bounds.width-48)),height:32)} }
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
        if let next=panes(survivor).first{activate(next)};needsLayout=true
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
        if point.x < edge{return .left};if point.x > pane.bounds.width-edge{return .right}
        if point.y < AreaHeader.rule+60{return .top};if point.y > pane.bounds.height-min(80,pane.bounds.height*0.2){return .bottom};return .centre
    }
    private func draggedTab(_ pasteboard:NSPasteboard)->(Pane,Tab)?{
        guard let text=pasteboard.string(forType:Self.tabDragType) else{return nil};let parts=text.split(separator:"|");guard parts.count == 2,parts[0] == id.uuidString,let tabID=UUID(uuidString:String(parts[1])) else{return nil}
        for pane in panes(){if let tab=pane.tabs.first(where:{$0.id == tabID}){return (pane,tab)}};return nil
    }
    private func move(_ tab:Tab,from source:Pane,to target:Pane,zone:Zone,index:Int)->Bool{
        if source === target,source.tabs.count == 1,zone != .centre{return false}
        let destination:Pane
        if zone == .centre{destination=target}else{destination=split(target,vertical:zone == .left || zone == .right,before:zone == .left || zone == .top);destination.tabs.forEach{choices.removeValue(forKey:$0.id)};destination.tabs=[]}
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
