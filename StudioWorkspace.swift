import AppKit
import UniformTypeIdentifiers
import ImageIO

enum WorkspaceTreeGridAsset {
    case palette(UUID), colour(String), font(UUID), imported(UUID), other(name:String,kind:String,identity:String)
}
struct WorkspaceTreeGridSection {
    let title:String
    let assets:[WorkspaceTreeGridAsset]
}
struct WorkspaceTreeGridScope {
    let key:String
    let title:String
    let sections:[WorkspaceTreeGridSection]
    var fontBucket:Bool=false
}

/// Portable favourite records include their display colour, rather than a separate colour map.
private enum WorkspaceFavourites {
    static func records(_ key:String)->[[String:String]] {AppPreferences.shared.object(forKey:key) as? [[String:String]] ?? []}
    static func sync(_ key:String,entries:[(String,String)]) {
        let old=records(key)
        let colours=Dictionary(old.compactMap{record -> (String,String)? in
            guard let id=record["id"],let colour=record["colour"] else{return nil}
            return (id,colour)
        },uniquingKeysWith:{first,_ in first})
        let next=entries.map { id,title -> [String:String] in
            var record=["id":id,"title":title]
            if let colour=colours[id] {record["colour"]=colour}
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
/// The full-app shell uses the existing catalogue model; these views own presentation only.
final class WorkspaceCatalogues: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, WorkspaceRailAwareContent, WorkspacePanelContentMetrics, Overlay {
    func restoreLayoutPreferences(){expanded=Set(AppPreferences.shared.stringArray(forKey:expandedKey) ?? []);for heading in [cataloguesHeading,favsHeading,foldersHeading,myPalettesHeading]{heading.restoreLayoutPreference()}}
    var scrollbarOnLeft=false
    var panelContentPadding:CGFloat {0}
    var panelEdgePadding:CGFloat {0}
    private func contentHeight(_ tree:NSOutlineView)->CGFloat {
        // Expansion notifications can arrive before AppKit updates its cached row rectangles.
        // Use the same visible-row metrics as the delegate, including two-line palettes.
        let rows=(0..<tree.numberOfRows).reduce(CGFloat.zero){height,row in
            guard let item=tree.item(atRow:row) else{return height}
            return height+outlineView(tree,heightOfRowByItem:item)
        }
        return rows+CGFloat(max(0,tree.numberOfRows-1))*tree.intercellSpacing.height
    }
    private var favouritesHeight:CGFloat {favouriteRoots.isEmpty ? 28:contentHeight(favourites)}
    private var sections:[(WorkspaceSectionHeader,WorkspaceBranchTree,CGFloat)] {
        [(favsHeading,favourites,favouritesHeight),(foldersHeading,outline,contentHeight(outline)),(myPalettesHeading,myPalettes,contentHeight(myPalettes))]
    }
    /// Every subsection ends the way a panel does: the 16 pt content padding plus the 5 pt edge, 21 pt under the last row before the divider.
    static let sectionFooter:CGFloat=WorkspacePanel.contentPadding+WorkspaceBranchTree.edgePadding
    private var catalogueSectionHeight:CGFloat {WorkspaceSectionHeader.height+(cataloguesHeading.expanded ? 38+Self.sectionFooter:0)}
    var minimumContentHeight:CGFloat {catalogueSectionHeight+sections.reduce(0){$0+WorkspaceSectionHeader.height+($1.0.expanded ? $1.2+WorkspaceBranchTree.edgePadding+Self.sectionFooter:0)}}
    private let catalogueSelector=DropdownButton()
    private var cataloguePopup:SwissDropdown.MenuPanel?
    private var importCatalogue:(()->Void)?
    private var myLibraryRoots:[Node]=[]
    private var iccContent:ICCProfilePanel?
    var overlayWindows:[NSWindow]{cataloguePopup.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    func dismissOverlay(){if let popup=cataloguePopup{popup.parent?.removeChildWindow(popup);popup.orderOut(nil)};cataloguePopup=nil;Overlays.closed(self)}
    override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow == nil{dismissOverlay()};super.viewWillMove(toWindow:newWindow)}
    func installICCProfiles(_ view:ICCProfilePanel){
        iccContent=view
        view.onContentHeightChange={ [weak self] in guard let self else{return};let index=self.myPalettes.row(forItem:self.myLibraryRoots.first(where:{$0.key == "mylibrary-icc"})?.children.first);if index >= 0{self.myPalettes.noteHeightOfRows(withIndexesChanged:IndexSet(integer:index))};self.refreshExtent()}
    }
    func revealICCProfiles(){
        myPalettesHeading.state = .on
        AppPreferences.shared.set(false,forKey:"Workspace.Library.Sections.MyLibrary.Collapsed")
        guard let icc=myLibraryRoots.first(where:{$0.key == "mylibrary-icc"}) else{return}
        myPalettes.expandItem(icc)
        refreshExtent();layoutSubtreeIfNeeded()
        if let child=icc.children.first{let row=myPalettes.row(forItem:child);if row >= 0{_ = myPalettes.view(atColumn:0,row:row,makeIfNecessary:true)}}
    }
    @objc private func openCatalogues(){
        guard let window else{return};dismissOverlay()
        let names=catalogueRoots.compactMap(\.catalogue),items=names+[SwissDropdown.MenuPanel.divider,"Import Catalogue…"]
        let popup=SwissDropdown.MenuPanel(items:items,chosen:current,width:min(420,max(240,catalogueSelector.fittedWidth))){ [weak self] index in guard let self else{return};self.dismissOverlay();if index < names.count{self.onCatalogue?(names[index])}else if index == names.count+1{self.importCatalogue?()} }
        popup.place(anchoredTo:window.convertToScreen(catalogueSelector.convert(catalogueSelector.bounds,to:nil)),within:window);window.addChildWindow(popup,ordered:.above);cataloguePopup=popup;popup.orderFront(nil);Overlays.opened(self)
    }
    final class Node:NSObject {
        let key:String,title:String,place:StudioFrame.Place?,catalogue:String?,symbol:String
        var count:Int
        var children:[Node]=[]
        var creationClient:UUID?
        var createClient=false
        var pulse=false
        var colours:[NSColor]=[]
        var importedAssetID:UUID?
        var fontID:UUID?
        var fontFamily:String?
        var fontDestination:LibraryRail.DropDestination?
        var assetTypeID: String?
        var isAssetContainer=false
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
    private let favsHeading=WorkspaceSectionHeader(WorkspaceSidebarStructure.favourites,key:"Workspace.Library.Sections.Favs.Collapsed")
    private let cataloguesHeading=WorkspaceSectionHeader("Catalogues",key:"Workspace.Library.Sections.Catalogues.Collapsed")
    private let foldersHeading=WorkspaceSectionHeader("Folders",key:"Workspace.Library.Sections.Folders.Collapsed")
    private let myPalettesHeading=WorkspaceSectionHeader(WorkspaceSidebarStructure.library,key:"Workspace.Library.Sections.MyLibrary.Collapsed")
    var onMultiColourSelect:((Node,WorkspaceBranchTree)->Void)?
    func isColourTargetTree(_ tree:WorkspaceBranchTree)->Bool {tree === outline || tree === myPalettes}
    func selectColourTarget(_ node:Node,in tree:WorkspaceBranchTree,mode:WorkspaceColourMode){mode.select(node,in:tree)}
    func installColourMode(_ mode:WorkspaceColourMode){
        for tree in [outline,myPalettes] {
            mode.register(tree){[weak self] item in
                guard let self,let node=item as? Node,node.key != self.backNode.key,!node.key.hasPrefix("icc-content") else{return nil}
                return WorkspaceColourMode.Target(id:"node:"+node.key,name:node.title,
                    read:{channel in
                        switch channel {
                        case .background:return WorkspaceNodeAppearance.colour(node.key)
                        case .text:return WorkspaceNodeAppearance.textColour(node.key)
                        case .border:return WorkspaceNodeAppearance.borderColour(node.key)
                        }
                    },
                    write:{[weak self] channel,hex in
                        switch channel {
                        case .background:WorkspaceNodeAppearance.set(hex,for:node.key)
                        case .text:WorkspaceNodeAppearance.setText(hex,for:node.key)
                        case .border:WorkspaceNodeAppearance.setBorder(hex,for:node.key)
                        }
                        for tree in [self?.outline,self?.myPalettes].compactMap({$0}){tree.repaintColours()}
                    })
            }
        }
        // Favourites are intentionally not colour targets, but must not navigate while the brush is open.
        mode.register(favourites){_ in nil}
    }
    private let emptyFavourites=NSTextField(labelWithString:"No favourites listed")
    private let emptyMyPalettes=NSTextField(labelWithString:"You have no palettes.")
    private var hasMyPalettes=false
    private var catalogueRoots:[Node]=[],favouriteRoots:[Node]=[],roots:[Node]=[],myPaletteRoots:[Node]=[]
    private var focusedFolderKey:String?
    var sessionFocusedFolder: String? {
        get { focusedFolderKey }
        set { focusFolder(newValue.flatMap { findFolder($0,in:roots) == nil ? nil:$0 }) }
    }
    private let backNode=Node("workspace-focus-back","Back",symbol:"arrow.left")
    private var dividerYs:[CGFloat]=[]
    private var expanded=Set<String>(),rebuilding=false,current=""
    private var expandedKey:String {"Workspace.CatalogueTree.Expanded.\(current)"}
    private var favouritesKey:String {"Workspace.Library.Favourites."+(AppPreferences.shared.string(forKey:"currentCatalogueID") ?? current)}
    var onAssetContext: ((UUID, Node, WorkspaceBranchTree, NSView, NSPoint) -> Void)?
    var onOpenImportedAsset:((UUID)->Void)?
    var importedAssets:[WorkspaceImportedAsset]=[]
    var linkedPaletteIDs=Set<UUID>()
    var lockedPaletteIDs=Set<UUID>()
    var onImportLibrary:(()->Void)?
    var onImportAsset:((String,StudioFrame.Place?)->Void)?
    var onExportLibrary:(()->Void)?
    var onRevealMyLibrary:(()->Void)?
    var locationOfNode:((Node)->URL?)?
    var onRevealNode:((Node)->Void)?
    var onCreateClient:(()->Void)?
    var onCreateWork:((UUID)->Void)?
    enum AssetReorder { case library([String]), catalogue(UUID,[UUID]) }
    var onReorderAsset:((AssetReorder)->Void)?
    private var pulseTimer:Timer?
    deinit{pulseTimer?.invalidate()}
    private var pulsePhase:CGFloat {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1:CGFloat((sin(Date.timeIntervalSinceReferenceDate*1.6)+1)/2)
    }
    func beginOnboarding(){
        for heading in [cataloguesHeading,favsHeading,myPalettesHeading]{heading.state = .off}
        foldersHeading.state = .on;refreshExtent()
    }
    var onPick:((StudioFrame.Place)->Void)?
    var onBucketPick:((WorkspaceTreeGridScope)->Void)?
    var onCatalogue:((String)->Void)?
    var onCatalogueAction:((String,CatalogueRowAction)->Void)?
    private let catalogueMenu=SwissContextMenu()
    var onFilter:((String)->Void)?
    var onFavourite:((UUID)->Void)?
    var onDrop:((UUID,LibraryRail.DropDestination)->Void)?
    var onRename:((UUID,String)->Void)?
    var onTarget:((UUID)->Void)?
    /// The tag icon on a palette row: the palette's tags, in railInfo.
    var onTags:((UUID)->Void)?
    var onRating:((UUID,Int)->Void)?
    var onFlag:((UUID,PaletteReview.Flag?)->Void)?
    var onOpenFont:((UUID)->Void)?
    var onFontContext:((UUID,Node,NSView,NSPoint)->Void)?
    var onFontUpdate:((UUID,FontAssetInfo)->Void)?
    var onFontDrop:((UUID,LibraryRail.DropDestination)->Void)?
    var fontEntries:[FontLibraryEntry]=[]
    private var assets=Library()
    private var assetsByID:[UUID:Swatch]=[:]
    private var renderedAssets:Library?
    private var favouriteColours:[String:NSColor]=[:]
    private var collectionAssetColours:[String:NSColor]=[:]
    func configureCollections(_ entries:[AssetCollectionEntry],linkedPaletteRecords:[UUID:UUID]=[:]) {
        var colours:[String:NSColor]=[:]
        // The first Collection in the user's order wins when an asset belongs to several.
        for entry in entries {for item in entry.items where colours[item.key] == nil {
            if let hex=entry.colour {colours[item.key]=Design.hex(hex)}
        }}
        for (palette,record) in linkedPaletteRecords where colours["Palette/"+palette.uuidString] == nil {
            colours["Palette/"+palette.uuidString]=colours["Palettes/"+record.uuidString]
        }
        collectionAssetColours=colours
        for tree in [outline,myPalettes,favourites] {tree.repaintColours()}
    }
    private func assetColour(_ node:Node)->NSColor? {
        if let family=node.fontFamily {return collectionAssetColours["Font/"+family]}
        if case .palette(let id)=node.place {return collectionAssetColours["Palette/"+id.uuidString]}
        if let id=node.importedAssetID,let asset=importedAssets.first(where:{$0.id == id}) {
            return collectionAssetColours[asset.type+"/"+id.uuidString]
        }
        return nil
    }
    private func isAsset(_ node:Node)->Bool {
        if case .palette=node.place{return true}
        return node.importedAssetID != nil || node.fontID != nil
    }
    private func nodeMenu(_ node:Node,at point:NSPoint,in view:NSView,tree:WorkspaceBranchTree) {
        if let id=node.fontID {
            onFontContext?(id,node,view,point)
            return
        }
        if let id=node.importedAssetID {onAssetContext?(id,node,tree,view,point);return}
        if case .palette(let id)=node.place {onAssetContext?(id,node,tree,view,point);return}
        var actions:[HaloAction]=[]
        if tree !== favourites,node.key != backNode.key {
            actions.append(HaloAction(id:"multi-colour",label:"Multi Colour Select",symbol:"square.grid.2x2",onSelect:{[weak self] in self?.onMultiColourSelect?(node,tree)}))
            actions.append(HaloAction(id:"divider-multi-colour",label:"",symbol:""))
        }
        var colour=HaloAction(id:"colour",label:"Colour",symbol:"square.fill",onSelect:{[weak self,weak view] in
            guard let self else{return}
            if tree !== self.favourites {self.onMultiColourSelect?(node,tree);return}
            guard let view,let root=view.window?.contentView else{return}
            let target=StudioColourPicker.Target(group:"Tree Node",name:node.title,key:node.key,
                read:{WorkspaceNodeAppearance.colour(node.key) ?? Design.card},
                write:{[weak self] hex in
                    WorkspaceNodeAppearance.set(hex,for:node.key)
                    guard let self else{return}
                    for tree in [self.outline,self.myPalettes,self.favourites]{tree.repaintColours()}
                })
            StudioColourPicker(target:node.key,targets:[target],commitOnPick:true).present(over:root)
        })
        colour.menuSwatch=WorkspaceNodeAppearance.colour(node.key) ?? Design.card
        actions.append(colour)
        var rest:[HaloAction]=[]
        if let kind=importKind(for:node) {
            let label=kind == "Palettes" ? "Palette" : kind == "Fonts" ? "Font" : kind == "Images" ? "Image" : kind == "Photographs" ? "Photograph" : kind == "Typography Packs" ? "Typography Pack" : kind == "ICC Profiles" ? "ICC Profile" : kind
            rest.append(HaloAction(id:"import-asset",label:"Import \(label)…",symbol:"square.and.arrow.down",disabled:!WorkspaceImport.supportedTypes.contains(kind) && kind != "Images" && kind != "Photographs",onSelect:{[weak self] in
                self?.onImportAsset?(kind,node.key.hasPrefix("mylibrary-") ? .catalogue : node.place)
            }))
        }
        if node.key != backNode.key {
            let location=locationOfNode?(node)
            rest.append(HaloAction(id:"reveal",label:"Reveal in Finder",symbol:"folder",disabled:!(location.map{FileManager.default.fileExists(atPath:$0.path)} ?? false),onSelect:{[weak self] in self?.onRevealNode?(node)}))
        }
        if node.key == "catalogue" {
            rest += [HaloAction(id:"import-library",label:"Import Library…",symbol:"square.and.arrow.down",onSelect:{[weak self] in self?.onImportLibrary?()}),
                     HaloAction(id:"export-library",label:"Export Library…",symbol:"square.and.arrow.up",onSelect:{[weak self] in self?.onExportLibrary?()})]
        }
        if node.createClient || node.creationClient != nil {
            let title=node.createClient ? (SchemaTrial.structure?.clientName ?? "Client"):(node.creationClient.flatMap{id in SchemaTrial.collections.first{$0.id == id}?.stack.name} ?? "Project")
            rest.append(HaloAction(id:"create",label:"Create New "+title,symbol:"plus",onSelect:{[weak self] in
                if node.createClient{self?.onCreateClient?()}else if let id=node.creationClient{self?.onCreateWork?(id)}
            }))
        }
        if node.key != backNode.key,findFolder(node.key,in:roots) != nil {
            rest.append(HaloAction(id:"focus",label:focusedFolderKey == node.key ? "Show Full Tree":"Focus On "+node.title,symbol:"pin",onSelect:{[weak self] in
                self?.focusFolder(self?.focusedFolderKey == node.key ? nil:node.key)
            }))
        }
        if !rest.isEmpty {actions.append(HaloAction(id:"divider-node",label:"",symbol:""));actions += rest}
        catalogueMenu.open(actions,at:point,in:view)
    }
    private func importKind(for node:Node)->String? {
        guard !isAsset(node) else{return nil}
        let libraryKinds=["mylibrary-palettes":"Palettes","mylibrary-fonts":"Fonts","mylibrary-images":"Images","mylibrary-photography":"Photographs","mylibrary-typography":"Typography Packs","mylibrary-ase":"ASE"]
        if let kind=libraryKinds[node.key] {return kind}
        guard case .group(let member,let bucket)=node.place,
              let schema=SchemaTrial.rows(of:SchemaTrial.schema(for:member)).first(where:{$0.node.id == bucket})?.node else{return nil}
        let type=SchemaTrial.type(of:schema)
        if let asset=SimpleAssetType.all.first(where:{$0.title.caseInsensitiveCompare(type) == .orderedSame || $0.id == node.assetTypeID}) {return asset.setupTitle}
        return type == "Photography" ? "Photographs" : WorkspaceImport.types.first(where:{$0.caseInsensitiveCompare(type) == .orderedSame})
    }
    private func refreshFavouriteColours(){favouriteColours=Dictionary(WorkspaceFavourites.records(favouritesKey).compactMap{record in guard let id=record["id"],let hex=record["colour"] else{return nil};return (id,Design.hex(hex))},uniquingKeysWith:{_,last in last})}
    private func sameNodes(_ a:[Node],_ b:[Node])->Bool {
        a.count == b.count && zip(a,b).allSatisfy{x,y in x.key == y.key && x.title == y.title && x.count == y.count && x.place == y.place && x.catalogue == y.catalogue && x.symbol == y.symbol && x.pulse == y.pulse && x.creationClient == y.creationClient && x.createClient == y.createClient && x.destination == y.destination && x.fontID == y.fontID && x.fontDestination == y.fontDestination && x.colours == y.colours && sameNodes(x.children,y.children)}
    }
    private let paletteFilters=PaletteFilterControls(frame:.zero)
    var filter=PaletteAssetHandler.Filter() {didSet{paletteFilters.value=filter}}
    var onPaletteFilter:((PaletteAssetHandler.Filter)->Void)?
    private var order:PaletteAssetHandler.Order {filter.order}
    func configureAssets(_ library:Library){assets=library;assetsByID=Dictionary(library.swatches.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})}
    func refreshAssetPresentation(_ library:Library) {
        configureAssets(library);renderedAssets=library
        for tree in [outline,favourites,myPalettes] {
            let rows=tree.rows(in:tree.visibleRect)
            guard rows.length > 0,tree.numberOfColumns > 0 else{continue}
            tree.reloadData(forRowIndexes:IndexSet(integersIn:rows.location..<rows.location+rows.length),columnIndexes:IndexSet(integer:0))
        }
    }

    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        catalogueSelector.borderless=true;catalogueSelector.setAccessibilityLabel("Select Catalogue");catalogueSelector.target=self;catalogueSelector.action=#selector(openCatalogues);addSubview(catalogueSelector)
        for panel in [paletteFilters] {
            addSubview(panel);panel.onChange={ [weak self] value in self?.onPaletteFilter?(value) }
        }
        myPalettes.showsConnectors=true;favourites.showsConnectors=true;catalogueList.showsConnectors=false
        // Every tree chooses a semantic depth palette explicitly; only user node colours override it.
        favourites.swatchFamily = .charcoal
        catalogueList.swatchFamily = .charcoal
        outline.swatchFamily = .charcoal
        myPalettes.swatchFamily = .charcoal
        for (tree,name) in [(favourites,"Library Favourites"),(catalogueList,"Catalogue List"),(outline,"Catalogue Library Tree"),(myPalettes,"My Palettes")] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(name))
            tree.leadingDisclosure=true
            tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
            tree.rowHeight=34;tree.indentationPerLevel=0;tree.intercellSpacing=NSSize(width:0,height:WorkspaceBranchTree.rowSpacing)
            tree.backgroundColor=Design.card;tree.appearance=Theme.appearance;tree.style = .plain
            tree.dataSource=self;tree.delegate=self;tree.focusRingType = .none;tree.setAccessibilityLabel(name)
            tree.setDraggingSourceOperationMask(.copy,forLocal:true)
            tree.rowColour={ [weak self,weak tree] item in
                guard let self,let node=item as? Node else{return nil}
                if tree === self.outline,node.pulse{return Design.mix(.white,Design.houseBlue,self.pulsePhase)}
                if tree === self.outline,node.key == "workspace-focus-back"{return NSColor(srgbRed:133/255,green:162/255,blue:165/255,alpha:1)}
                if tree === self.outline,let colour=WorkspaceNodeAppearance.colour(node.key){return colour}
                if tree === self.myPalettes {
                    if let colour=WorkspaceNodeAppearance.colour(node.key){return colour}
                }
                return self.isAsset(node) ? nil:self.favouriteColours[node.key]
            }
            tree.rowInk={ [weak self,weak tree] item in
                guard let self,let node=item as? Node else{return nil}
                if let ink=WorkspaceNodeAppearance.ink(node.key){return ink}
                if self.isAsset(node) {return Design.ink}
                if tree === self.outline,node.pulse{return self.pulsePhase > 0.55 ? .white:.black}
                if tree === self.outline,node.key == "workspace-focus-back"{return .black}
                if tree === self.outline,let ink=WorkspaceNodeAppearance.ink(node.key){return ink}
                guard tree === self.myPalettes else{return nil}
                if let ink=WorkspaceNodeAppearance.ink(node.key){return ink}
                return nil
            }
            tree.rowBorder={item in
                guard let node=item as? Node else{return nil}
                return WorkspaceNodeAppearance.borderColour(node.key)
            }
            tree.rowLeadingAccent={ [weak self] item in
                guard let self,let node=item as? Node else{return nil}
                if WorkspaceNodeAppearance.colour(node.key) != nil{return nil}
                return self.assetColour(node)
            }
            tree.rowClear={ [weak self] item in
                guard let self,let node=item as? Node else{return false}
                return self.isAsset(node) && WorkspaceNodeAppearance.colour(node.key) == nil
            }
            addSubview(tree);tree.installConnectors(in:self)
        }
        for tree in [outline,myPalettes] {
            tree.registerForDraggedTypes([PaletteDrag.type,FontDrag.type])
            tree.isDropTarget={ item in guard let node=item as? Node else{return false};return node.destination != nil || node.fontDestination != nil }
        }
        for tree in [outline,myPalettes,favourites] {
            tree.onContext={ [weak self,weak tree] item,point,view in
                guard let self,let node=item as? Node else{return}
                guard let tree else{return};self.nodeMenu(node,at:point,in:view,tree:tree)
            }
        }
        for heading in [cataloguesHeading,favsHeading,foldersHeading,myPalettesHeading] {
            heading.changed={ [weak self] in self?.refreshExtent() };addSubview(heading)
        }
        myPalettesHeading.setAction(symbol:"folder",title:"Reveal in Finder") {[weak self] in self?.onRevealMyLibrary?()}
        myPalettesHeading.onContext={ [weak self] point,view in
            guard let self else{return}
            self.catalogueMenu.open([
                HaloAction(id:"reveal",label:"Reveal in Finder",symbol:"folder",onSelect:{[weak self] in self?.onRevealMyLibrary?()}),
                HaloAction(id:"import-library",label:"Import Library…",symbol:"square.and.arrow.down",onSelect:{[weak self] in self?.onImportLibrary?()}),
                HaloAction(id:"export-library",label:"Export Library…",symbol:"square.and.arrow.up",onSelect:{[weak self] in self?.onExportLibrary?()})
            ],at:point,in:view)
        }
        for label in [emptyFavourites,emptyMyPalettes] {label.font=Design.Text.body.font();label.textColor=Design.quiet;addSubview(label)}
    }
    required init?(coder:NSCoder){fatalError()}
    func setCatalogueAction(_ action:@escaping()->Void){
        importCatalogue=action
        cataloguesHeading.setAction(symbol:"plus",title:"Import Catalogue…",run:action)
    }
    override func layout(){
        super.layout();dividerYs=[]
        cataloguesHeading.isHidden=false;catalogueList.isHidden=true;paletteFilters.isHidden=true;emptyMyPalettes.isHidden=true
        cataloguesHeading.frame=NSRect(x:0,y:0,width:bounds.width,height:WorkspaceSectionHeader.height)
        catalogueSelector.isHidden = !cataloguesHeading.expanded
        catalogueSelector.frame=NSRect(x:16,y:WorkspaceSectionHeader.height+6,width:min(catalogueSelector.fittedWidth,max(0,bounds.width-32)),height:32)
        var y:CGFloat=catalogueSectionHeight
        for (heading,tree,height) in sections {
            dividerYs.append(y)
            heading.frame=NSRect(x:0,y:y,width:bounds.width,height:WorkspaceSectionHeader.height)
            y+=WorkspaceSectionHeader.height
            tree.isHidden = !heading.expanded || (tree === favourites && favouriteRoots.isEmpty)
            tree.frame=NSRect(x:0,y:y+WorkspaceBranchTree.edgePadding,width:bounds.width,height:tree.isHidden ? 0:height)
            tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()
            if tree === myPalettes {emptyMyPalettes.frame=NSRect(x:16,y:y+WorkspaceBranchTree.edgePadding+4,width:max(0,bounds.width-32),height:20)}
            if tree === favourites {emptyFavourites.frame=NSRect(x:16,y:y+WorkspaceBranchTree.edgePadding+4,width:max(0,bounds.width-32),height:20)}
            if heading.expanded {
                y+=height+WorkspaceBranchTree.edgePadding+Self.sectionFooter
                dividerYs.append(y)
            }
        }
        emptyFavourites.isHidden = !favouriteRoots.isEmpty || !favsHeading.expanded
        emptyMyPalettes.isHidden = true
        emptyMyPalettes.stringValue=hasMyPalettes ? "No palettes match your filters.":"You have no palettes."
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){for y in Set(dividerYs) {hairline(x:0,y:y,width:bounds.width)}}
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
        let oldCatalogue=catalogueRoots,oldFavourites=favouriteRoots,oldRoots=roots,oldLibrary=myLibraryRoots
        let sameCatalogue=current == active
        var needsReload=true
        rebuilding=true
        defer{rebuilding=false;if needsReload{refreshExtent()}else{for tree in [outline,favourites,myPalettes]{tree.refreshSurfaces()}}}
        if current != active {
            if !current.isEmpty {AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey)}
            focusedFolderKey=nil;current=active;expanded=Set(AppPreferences.shared.stringArray(forKey:expandedKey) ?? [])
        }
        catalogueSelector.title=active;foldersHeading.title=active;foldersHeading.setAccessibilityLabel(active+" section")
        catalogueRoots=names.map{Node("catalogue:"+$0,$0,catalogue:$0,symbol:"books.vertical")}
        if !names.contains(active){catalogueRoots.insert(Node("catalogue:"+active,active,catalogue:active,symbol:"books.vertical"),at:0)}
        let root=Node("content",active)
        let originalExpansionCount=expanded.count
        do {
            var stack:[(Int,Node)]=[(-1,root)]
            for row in rows {
                let node:Node, level:Int
                switch row {
                case .palette(let palette):
                    // A leaf belongs under its real schema bucket. Selecting it opens the
                    // palette in the centre canvas; it never introduces another palette rail.
                    node=Node("palette:" + palette.id.uuidString,palette.name,count:palette.count,place:.palette(palette.id),symbol:linkedPaletteIDs.contains(palette.id) ? "link":"swatchpalette");level=palette.indent+1
                    node.colours=palette.colours
                    if let project=palette.project {node.destination=LibraryRail.DropDestination(project:project,bucket:palette.bucket)}
                case .group(let title,let key):
                    let target:StudioFrame.Place? = key?.hasPrefix("collection:") == true ? UUID(uuidString:String(key!.dropFirst(11))).map{.collection($0)} : (key == "palettes" ? .palettes : nil)
                    node=Node(key ?? title,title,place:target);level=0
                case .row(let title,let count,let place,let indent):
                    // Project and collection places contain their own UUID; never
                    // substitute the shared schema title or template for identity.
                    node=Node(String(describing:place),title,count:count,place:place,symbol:place == .catalogue ? "square.grid.2x2" : "folder");level=indent+1
                case .node(let title,let count,let project,let indent,let acceptsPalette,let id):
                    let role=SchemaTrial.role(of:SchemaNode(name:title))
                    let symbol=role == .palettes ? "swatchpalette" : role == .information ? "info.circle" : role == .typography ? "textformat" : role == .tags ? "tag" : title.lowercased() == "photography" ? "camera" : title.lowercased() == "assets" ? "shippingbox" : "square.dashed"
                    let scopedKey=WorkspaceNodeAppearance.projectNodeKey(project:project,node:id)
                    if expanded.contains(id.uuidString){expanded.insert(scopedKey)}
                    node=Node(scopedKey,title,count:count,place:.group(project,id),symbol:symbol);level=indent+1
                    if let schema = SchemaTrial.rows(of: SchemaTrial.schema(for: project)).first(where: { $0.node.id == id })?.node {
                        node.isAssetContainer=schema.kind == "Simple Assets"
                        if SchemaTrial.type(of:schema).caseInsensitiveCompare("Fonts") == .orderedSame {
                            node.fontDestination=LibraryRail.DropDestination(project:project,bucket:id)
                        }
                    }
                    if acceptsPalette {node.destination=LibraryRail.DropDestination(project:project,bucket:id)}
                case .tag:continue
                }
                while let last=stack.last,last.0 >= level{stack.removeLast()}
                if stack.last?.1.isAssetContainer == true {node.assetTypeID=SimpleAssetType.workspaceTypes(home:Catalogues.standard.root).first(where:{$0.title == node.title || $0.id == "photography" && node.title == "Photography"})?.id ?? node.title}
                stack.last?.1.children.append(node);stack.append((level,node))
            }
        }
        if expanded.count != originalExpansionCount {AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey)}
        func defaultAssetOrder(_ nodes:[Node]) {
            for node in nodes {
                if node.isAssetContainer,case .group(let project,_)=node.place,
                   !AppPreferences.shared.bool(forKey:"Workspace.AssetTree.ManualOrder."+project.uuidString) {
                    node.children.sort{ left,right in
                        let order=SimpleAssetType.defaultAssetIDs
                        let a=order.firstIndex(of:left.assetTypeID ?? "") ?? order.count
                        let b=order.firstIndex(of:right.assetTypeID ?? "") ?? order.count
                        return a == b ? left.title.localizedStandardCompare(right.title) == .orderedAscending : a < b
                    }
                }
                defaultAssetOrder(node.children)
            }
        }
        defaultAssetOrder(root.children)

        // Closed ancestors remain valid targets when their descendants identify one project.
        root.children.forEach{$0.resolveDestination()}

        favouriteRoots=root.children.first{$0.key == "favourites"}?.children ?? []
        WorkspaceFavourites.sync(favouritesKey,entries:allFavourites.map{("palette:"+$0.id.uuidString,$0.name)})
        myPaletteRoots=root.children.filter{["palettes","claimed"].contains($0.key)}.flatMap(\.children).filter{
            if case .palette=$0.place {return true};return false
        }
        roots=root.children.filter{!["catalogue","favourites","palettes","claimed"].contains($0.key)}
        if let config=SchemaTrial.structure {
            foldersHeading.setAction(symbol:"plus",title:"Add "+config.clientName){[weak self] in self?.onCreateClient?()}
            if SchemaTrial.collections.isEmpty {
                let client=Node("schema-preview-client",config.clientName)
                client.createClient=true;client.pulse=true;roots=[client]
            } else {
                for client in SchemaTrial.collections {
                    guard let root=roots.first(where:{$0.key == "collection:"+client.id.uuidString}) else{continue}
                    root.creationClient=client.id
                    let hasWork=assets.projects.contains{SchemaTrial.collection(of:$0.id).id == client.id}
                    if !hasWork {
                        let work=Node("schema-preview-work-"+client.id.uuidString,client.stack.name)
                        work.creationClient=client.id;work.pulse=true;root.children=[work]
                    }
                    for child in root.children {if case .project=child.place {child.creationClient=client.id}}
                }
            }
            if config.personalMode == true,let personal=SchemaTrial.personalCollection {
                foldersHeading.setAction(symbol:"plus",title:"Add "+config.singular){[weak self] in self?.onCreateWork?(personal.id)}
                roots=roots.flatMap { root in root.key.hasPrefix("collection:") ? root.children.filter{!$0.key.hasPrefix("schema-preview-")}:[root] }
                if assets.projects.isEmpty {let work=Node("schema-preview-personal",config.singular);work.creationClient=personal.id;work.pulse=true;roots=[work]}
            }
            if pulseTimer == nil, roots.contains(where:{$0.pulse || $0.children.contains(where:{$0.pulse})}) {
                pulseTimer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self] _ in self?.outline.refreshSurfaces()}
            }
        }
        refreshFavouriteColours()
        hasMyPalettes = !myPaletteRoots.isEmpty
        sortPalettes()
        let libraryRoot=Node("catalogue","Library")
        let informationNode=Node("mylibrary-information","Information",place:.librarySettings,symbol:"info.circle")
        let palettesNode=Node("mylibrary-palettes",WorkspaceSidebarStructure.paletteTitle,count:assets.swatches.count,place:.catalogue,symbol:"square.grid.2x2")
        palettesNode.children=myPaletteRoots.filter{node in if case .palette(let id)=node.place{return assetsByID[id]?.isTypography != true};return true}
        let typographyNode=Node("mylibrary-typography","Typography",place:.catalogue,symbol:"textformat")
        typographyNode.children=PaletteAssetHandler.ordered(assets.libraryPalettes.filter{$0.isTypography && filter.matches($0)},by:order,in:assets).map { palette in
            let node=Node("mylibrary-typography:"+palette.id.uuidString,palette.name,count:palette.entries.count,place:.palette(palette.id),symbol:"textformat")
            node.colours=palette.entries.map{assets.definition(of:$0.hex)?.master.display ?? Design.hex($0.hex)}
            return node
        }
        typographyNode.count=typographyNode.children.count;palettesNode.count=palettesNode.children.count
        let iccNode=Node("mylibrary-icc",WorkspaceSidebarStructure.iccTitle,symbol:"slider.horizontal.3")
        iccNode.children=[Node("icc-content","ICC Profiles")]
        let fontsNode=Node("mylibrary-fonts","Fonts",symbol:"textformat.abc")
        let indexedFonts=Dictionary(uniqueKeysWithValues:fontEntries.map{($0.id,$0)})
        fontsNode.children=fontEntries.map { entry in
            let leaf=Node("font:"+entry.id.uuidString,entry.info.family,symbol:"textformat")
            leaf.fontID=entry.id;leaf.fontFamily=entry.info.family
            return leaf
        }
        fontsNode.count=fontsNode.children.count
        favouriteRoots += fontEntries.filter{$0.info.favourite == true}.map { entry in
            let leaf=Node("favourite-font:"+entry.id.uuidString,entry.info.family,symbol:"textformat")
            leaf.fontID=entry.id;leaf.fontFamily=entry.info.family
            return leaf
        }
        let aseNode=Node("mylibrary-ase","ASE",symbol:"doc")
        let photosNode=Node("mylibrary-photography","Photographs",symbol:"camera")
        let imagesNode=Node("mylibrary-images","Images",symbol:"photo")
        func find(_ nodes:[Node], member:UUID, bucket:UUID?) -> Node? {
            for node in nodes {
                if case .group(let owner,let id)=node.place, owner == member, id == bucket { return node }
                if let found=find(node.children,member:member,bucket:bucket){return found}
            }
            return nil
        }
        for asset in importedAssets where asset.type != "Palettes" {
            let leaf=Node("imported:"+asset.id.uuidString,asset.name,symbol:asset.type == "Fonts" ? "textformat" : asset.external ? "link":"doc")
            leaf.importedAssetID=asset.id
            if asset.type == "Fonts",let entry=indexedFonts[asset.id] {leaf.fontID=entry.id;leaf.fontFamily=entry.info.family}
            if let member=asset.member {find(roots,member:member,bucket:asset.bucket)?.children.append(leaf)}
            else if asset.type == "ASE" {aseNode.children.append(leaf)}
            else if asset.type == "Fonts" {continue}
            else if asset.type == "Photographs" {photosNode.children.append(leaf)}
            else if asset.type == "Images" {imagesNode.children.append(leaf)}
            else {palettesNode.children.append(leaf)}
        }
        func assignFonts(_ node:Node) {
            if let destination=node.fontDestination,let bucket=destination.bucket {
                for family in FontProjectAssignments.families(project:destination.project,bucket:bucket) {
                    guard let entry=fontEntries.first(where:{$0.info.family.caseInsensitiveCompare(family) == .orderedSame}),
                          !node.children.contains(where:{$0.fontFamily?.caseInsensitiveCompare(family) == .orderedSame}) else {continue}
                    let leaf=Node("project-font:"+destination.project.uuidString+":"+bucket.uuidString+":"+entry.id.uuidString,entry.info.family,symbol:"textformat")
                    leaf.fontID=entry.id;leaf.fontFamily=entry.info.family;node.children.append(leaf)
                }
            }
            node.children.forEach(assignFonts)
        }
        roots.forEach(assignFonts)
        do {
            let enabled = GlobalAssets(home:Catalogues.standard.root).assetTypes
            let special:[String:Node]=["information":informationNode,"palettes":palettesNode,"typography":typographyNode,"fonts":fontsNode,"ase":aseNode,"icc":iccNode,"photography":photosNode,"images":imagesNode]
            let types=SimpleAssetType.workspaceTypes(home:Catalogues.standard.root)
            for id in enabled {
                guard let type=types.first(where:{$0.id == id}) else{continue}
                let node=special[id] ?? Node("mylibrary-"+id,type.title,symbol:type.symbol)
                node.assetTypeID=id;libraryRoot.children.append(node)
            }
            for id in ["palettes","typography","fonts","ase","photography","images"] where !enabled.contains(id) {
                if let node=special[id],!node.children.isEmpty {node.assetTypeID=id;libraryRoot.children.append(node)}
            }
            if !libraryRoot.children.contains(where:{$0.key == "mylibrary-fonts"}) {
                fontsNode.assetTypeID="fonts"
                libraryRoot.children.append(fontsNode)
            }
            if !AppPreferences.shared.bool(forKey:"Workspace.AssetTree.ManualOrder.Library") {
                libraryRoot.children.sort{ left,right in
                    let order=SimpleAssetType.defaultLibraryIDs
                    let a=order.firstIndex(of:left.assetTypeID ?? "") ?? order.count
                    let b=order.firstIndex(of:right.assetTypeID ?? "") ?? order.count
                    return a == b ? left.title.localizedStandardCompare(right.title) == .orderedAscending : a < b
                }
            }
        }
        myLibraryRoots=libraryRoot.children
        func aggregateFolderCounts(_ node:Node)->Int {
            if case .palette=node.place {return 1}
            if node.fontID != nil {return 1}
            if node.importedAssetID != nil {return 1}
            guard !node.children.isEmpty else{return node.count}
            let total=node.children.reduce(0){$0+aggregateFolderCounts($1)}
            if node.key != "icc-content" {node.count=total}
            return total
        }
        roots.forEach{_ = aggregateFolderCounts($0)}
        myLibraryRoots.forEach{_ = aggregateFolderCounts($0)}
        needsReload = !(sameCatalogue && renderedAssets == assets && sameNodes(oldCatalogue,catalogueRoots) && sameNodes(oldFavourites,favouriteRoots) && sameNodes(oldRoots,roots) && sameNodes(oldLibrary,myLibraryRoots))
        renderedAssets=assets
        if needsReload {for tree in [catalogueList,favourites,outline,myPalettes] {tree.reloadData()}}
        else {catalogueRoots=oldCatalogue;favouriteRoots=oldFavourites;roots=oldRoots;myLibraryRoots=oldLibrary}
        if let index=catalogueRoots.firstIndex(where:{$0.catalogue == active}) {
            catalogueList.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)
        }
        func restore(_ nodes:[Node]){for node in nodes {
            if expanded.contains(node.key) || node.key == "catalogue" || node.key == focusedFolderKey || node.key.hasPrefix("schema-preview-") || (SchemaTrial.structure != nil && node.key.hasPrefix("collection:")) {outline.expandItem(node)}
            restore(node.children)
        }}
        if needsReload{restore(roots)}
        func restoreLibrary(_ nodes:[Node]){for node in nodes{if expanded.contains(node.key){myPalettes.expandItem(node)};restoreLibrary(node.children)}}
        if needsReload{restoreLibrary(myLibraryRoots)}
        selectRoute(selected,key:selectedKey)
    }
    func selectRoute(_ selected:StudioFrame.Place,key selectedKey:String?=nil) {
        for tree in [outline,favourites,myPalettes] {
            var match:Int?
            for i in 0..<tree.numberOfRows {
                if let node=tree.item(atRow:i) as? Node,(selectedKey.map{node.key == $0} ?? (node.place == selected)) {match=i;break}
            }
            if let match {if tree.selectedRow != match{tree.selectRowIndexes(IndexSet(integer:match),byExtendingSelection:false)}}
            else {tree.deselectAll(nil)}
        }
    }
    private func sortPalettes(){
        func sorted(_ nodes:[Node])->[Node]{
            let visibleNodes=nodes.filter{node in if case .palette(let id)=node.place,let palette=assetsByID[id]{return filter.matches(palette)};return true}
            let palettes=visibleNodes.compactMap{node->Swatch? in if case .palette(let id)=node.place{return assetsByID[id]};return nil}
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
    private func findFolder(_ key:String,in nodes:[Node])->Node? {
        for node in nodes {if node.key == key{return node};if let found=findFolder(key,in:node.children){return found}}
        return nil
    }
    private var visibleFolderRoots:[Node] {
        guard let key=focusedFolderKey,let node=findFolder(key,in:roots) else{return roots}
        return [backNode,node]
    }
    private func focusFolder(_ key:String?) {
        focusedFolderKey=key
        rebuilding=true;outline.reloadData()
        func restore(_ nodes:[Node]){for node in nodes{if expanded.contains(node.key) || node.key == key{outline.expandItem(node)};restore(node.children)}}
        restore(visibleFolderRoots);rebuilding=false
        outline.refreshSurfaces();refreshExtent()
    }
    private func roots(for tree:NSOutlineView)->[Node]{tree === catalogueList ? catalogueRoots:(tree === favourites ? favouriteRoots:(tree === myPalettes ? myLibraryRoots:visibleFolderRoots))}
    func outlineView(_ tree:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int {(item as? Node)?.children.count ?? roots(for:tree).count}
    func outlineView(_ tree:NSOutlineView,child index:Int,ofItem item:Any?)->Any {(item as? Node)?.children[index] ?? roots(for:tree)[index]}
    func outlineView(_ tree:NSOutlineView,isItemExpandable item:Any)->Bool {!(item as! Node).children.isEmpty}
    func outlineView(_ tree:NSOutlineView,rowViewForItem item:Any)->NSTableRowView? {
        let row=WorkspaceBranchTree.Row();row.accordion=tree as? WorkspaceBranchTree;return row
    }
    func outlineView(_ tree:NSOutlineView,heightOfRowByItem item:Any)->CGFloat {
        if (item as? Node)?.key == "icc-content"{return (iccContent?.minimumContentHeight ?? 128)+16}
        let base:CGFloat = {if let node=item as? Node {if case .palette=node.place{return WorkspaceBranchTree.paletteRowHeight};if node.fontID != nil{return WorkspaceBranchTree.paletteRowHeight}};return 34}()
        return (tree as? WorkspaceBranchTree)?.colourTargetRowHeight(for:item,base:base) ?? base
    }
    func outlineView(_ tree:NSOutlineView,viewFor column:NSTableColumn?,item:Any)->NSView? {
        let node=item as! Node
        if node.key == "icc-content",let iccContent{return iccContent}
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:tree.tableColumns[0].width,height:34))
        cell.symbol=node.symbol
        cell.fontFamily=node.fontFamily
        cell.isAssetCategory=node.assetTypeID != nil
        if tree === outline || tree === myPalettes || tree === favourites {
            cell.trailingGearAndCount=true
            cell.catalogueAction.isHidden=false;cell.catalogueAction.symbol="gearshape"
            cell.catalogueAction.setAccessibilityLabel("Actions For "+node.title)
            cell.catalogueAction.toolTip="Actions For "+node.title
            cell.catalogueAction.run={ [weak self,weak cell,weak tree] in
                guard let self,let cell,let tree=tree as? WorkspaceBranchTree else{return}
                let anchor=cell.convert(NSPoint(x:cell.catalogueAction.frame.minX,y:cell.catalogueAction.frame.maxY),to:tree)
                self.nodeMenu(node,at:anchor,in:tree,tree:tree)
            }
        }
        if (tree === myPalettes || tree === outline) && node.assetTypeID != nil {
            cell.grip.isHidden=false
            cell.grip.toolTip="Drag To Reorder "+node.title
            cell.reorderDrag={ [weak self,weak tree,weak node] event in
                guard let self,let tree=tree as? WorkspaceBranchTree,let node else{return};self.dragAssetCategory(node,in:tree,from:event)
            }
        }
        cell.leadingDisclosure=(tree as? WorkspaceBranchTree)?.leadingDisclosure == true
        cell.spectrumColours=node.colours
        let label=NSTextField(labelWithString:node.title)
        cell.countLabel.stringValue=node.count == 0 ? "(0)":String(node.count)
        cell.countLabel.isHidden = node.key == backNode.key
        label.font=node.fontFamily.flatMap{NSFontManager.shared.font(withFamily:$0,traits:[],weight:5,size:TextSize.body)} ?? Design.Text.body.font()
        label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.key.hasPrefix("schema-preview-") ? "Catalogue structure — add a \(SchemaTrial.structure?.clientName ?? "Client") to start using this structure.":node.title
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
        if let id=node.fontID,let entry=fontEntries.first(where:{$0.id == id}) {
            cell.isPalette=true;cell.twoLines=true;cell.target.isHidden=true
            cell.fontDrag=(id,entry.info.family)
            cell.selectFont={ [weak self] in self?.onOpenFont?(id) }
            cell.dragChanged={ [weak self] active in self?.outline.paletteDragActive=active }
            cell.countLabel.stringValue="";cell.countLabel.isHidden=true
            cell.review.configure(name:entry.info.family,review:entry.info.review)
            cell.review.onRating={ [weak self] rating in
                var info=entry.info;info.review=PaletteReview(rating:rating,flag:info.review?.flag)
                self?.onFontUpdate?(id,info)
            }
            cell.review.onFlag={ [weak self] flag in
                var info=entry.info;info.review=PaletteReview(rating:info.review?.rating ?? 0,flag:flag)
                self?.onFontUpdate?(id,info)
            }
            cell.star.favourite=entry.info.favourite == true
            cell.star.setAccessibilityLabel((cell.star.favourite ? "Remove Favourite: ":"Add Favourite: ")+entry.info.family)
            cell.star.run={ [weak self] in var info=entry.info;info.favourite = !(info.favourite == true);self?.onFontUpdate?(id,info) }
            cell.tagIcon.setAccessibilityLabel("Tags: "+entry.info.family)
            cell.tagIcon.run={ [weak self] in self?.onOpenFont?(id) }
            cell.catalogueAction.run={ [weak self,weak cell,weak tree] in
                guard let self,let cell,let tree=tree as? WorkspaceBranchTree else{return}
                let anchor=cell.convert(NSPoint(x:cell.catalogueAction.frame.minX,y:cell.catalogueAction.frame.maxY),to:tree)
                self.nodeMenu(node,at:anchor,in:tree,tree:tree)
            }
        } else if case .palette(let id)=node.place {
            cell.isPalette=true
            cell.twoLines=true
            cell.renamePalette=lockedPaletteIDs.contains(id) ? nil : { [weak self] name in self?.onRename?(id,name) }
            cell.target.isEnabled = !lockedPaletteIDs.contains(id)
            cell.star.isEnabled = !lockedPaletteIDs.contains(id)
            cell.review.isReadOnly = lockedPaletteIDs.contains(id)
            if let palette=assetsByID[id]{
                let isTarget=assets.activeSwatchID == id
                cell.review.configure(name:palette.name,review:palette.review)
                cell.target.active=isTarget
                cell.target.symbol="scope"
                cell.target.setAccessibilityLabel((isTarget ? "Stop Targeting ":"Target New Picks To ")+palette.name)
                cell.target.toolTip=isTarget ? "New Picks Go Here":"Target For New Picks"
                cell.target.run={ [weak self] in self?.onTarget?(id) }
                cell.tagIcon.setAccessibilityLabel("Tags: "+palette.name)
                cell.tagIcon.toolTip="Tags"
                cell.tagIcon.run={ [weak self] in self?.onTags?(id) }
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
        } else {cell.star.isHidden=true}
        return cell
    }
    func outlineView(_ tree:NSOutlineView,pasteboardWriterForItem item:Any)->NSPasteboardWriting? {
        guard let node=item as? Node else{return nil}
        let writer=NSPasteboardItem()
        if let id=node.fontID {writer.setString(id.uuidString,forType:FontDrag.type);return writer}
        guard case .palette(let id)=node.place else{return nil}
        writer.setString(id.uuidString,forType:PaletteDrag.type);return writer
    }
    func outlineView(_ tree:NSOutlineView,draggingSession session:NSDraggingSession,willBeginAt screenPoint:NSPoint,forItems draggedItems:[Any]) {
        outline.paletteDragActive=true
    }
    func outlineView(_ tree:NSOutlineView,draggingSession session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        outline.paletteDragActive=false
    }
    func outlineView(_ tree:NSOutlineView,validateDrop info:NSDraggingInfo,proposedItem item:Any?,proposedChildIndex index:Int)->NSDragOperation {
        guard tree === outline || tree === myPalettes else{return []}
        let row=tree.row(at:tree.convert(info.draggingLocation,from:nil))
        guard row >= 0,let node=tree.item(atRow:row) as? Node else{return []}
        let hasFont=FontDrag.font(on:info.draggingPasteboard) != nil
        guard hasFont ? node.fontDestination != nil : (PaletteDrag.palette(on:info.draggingPasteboard) != nil && node.destination != nil) else{return []}
        tree.setDropItem(node,dropChildIndex:NSOutlineViewDropOnItemIndex)
        return .copy
    }
    func outlineView(_ tree:NSOutlineView,acceptDrop info:NSDraggingInfo,item:Any?,childIndex:Int)->Bool {
        defer{outline.paletteDragActive=false;myPalettes.paletteDragActive=false}
        guard let node=item as? Node,tree === outline else{return false}
        if let id=FontDrag.font(on:info.draggingPasteboard),let destination=node.fontDestination {onFontDrop?(id,destination);return true}
        guard let id=PaletteDrag.palette(on:info.draggingPasteboard),let destination=node.destination else{return false}
        onDrop?(id,destination);return true
    }
    private func dragAssetCategory(_ node:Node,in tree:WorkspaceBranchTree,from start:NSEvent) {
        guard let window,let parent=tree.parent(forItem:node) as? Node else{return}
        let siblings=parent.children.filter{$0.assetTypeID != nil}
        guard siblings.count > 1,let source=siblings.firstIndex(where:{$0 === node}) else{return}
        var slot=source,moved=false
        func position(_ event:NSEvent)->Int {
            let y=tree.convert(event.locationInWindow,from:nil).y
            for (index,sibling) in siblings.enumerated() {
                let row=tree.row(forItem:sibling)
                if row >= 0 && y < tree.rect(ofRow:row).midY{return index}
            }
            return siblings.count
        }
        while let event=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if event.type == .leftMouseUp {break}
            moved=true;slot=position(event)
            let boundary:CGFloat
            if slot < siblings.count {
                let row=tree.row(forItem:siblings[slot]);boundary=row >= 0 ? tree.rect(ofRow:row).minY:0
            } else {
                let row=tree.row(forItem:siblings[siblings.count-1]);boundary=row >= 0 ? tree.rect(ofRow:row).maxY:0
            }
            tree.reorderLineY=boundary
            tree.view(atColumn:0,row:tree.row(forItem:node),makeIfNecessary:false)?.alphaValue=0.55
        }
        tree.reorderLineY=nil
        tree.view(atColumn:0,row:tree.row(forItem:node),makeIfNecessary:false)?.alphaValue=1
        guard moved,slot != source,slot != source+1 else{return}
        if tree === myPalettes {
            var ordered=siblings.compactMap(\.assetTypeID)
            let id=ordered.remove(at:source);ordered.insert(id,at:slot > source ? slot-1:slot)
            onReorderAsset?(.library(ordered))
        } else if tree === outline,case .group(let project,_) = parent.place {
            var ordered=siblings.compactMap{item -> UUID? in if case .group(_,let id)=item.place{return id};return nil}
            guard ordered.count == siblings.count else{return}
            let id=ordered.remove(at:source);ordered.insert(id,at:slot > source ? slot-1:slot)
            onReorderAsset?(.catalogue(project,ordered))
        }
    }
    func outlineViewSelectionDidChange(_ notification:Notification){
        if (notification.object as? WorkspaceBranchTree)?.colourModeActive == true{return}
        guard !rebuilding,let tree=notification.object as? NSOutlineView,let node=tree.item(atRow:tree.selectedRow) as? Node else{return}
        if tree === outline,node.key == backNode.key{DispatchQueue.main.async{[weak self] in self?.focusFolder(nil)};return}
        // Finish the row's expand/collapse gesture before navigation rebuilds its node model.
        DispatchQueue.main.async { [weak self,weak tree] in
            guard let self,let tree,let selected=tree.item(atRow:tree.selectedRow) as? Node,selected.key == node.key else{return}
            if node.pulse {
                if node.createClient{self.onCreateClient?()}else if let id=node.creationClient{self.onCreateWork?(id)}
            } else if node.key == "mylibrary-fonts" {self.onFilter?("fonts")}
            else if let id=node.fontID {self.onOpenFont?(id)}
            else if tree !== self.catalogueList,(!node.children.isEmpty || node.fontDestination != nil || node.assetTypeID == "fonts"),node.key != "icc-content" {
                func sections(in parent:Node)->[WorkspaceTreeGridSection] {
                    let direct:[WorkspaceTreeGridAsset]=parent.children.compactMap{child in
                        if case .palette(let id)=child.place{return .palette(id)}
                        if let id=child.fontID{return .font(id)}
                        if let id=child.importedAssetID{return .imported(id)}
                        return nil
                    }
                    var result=direct.isEmpty ? []:[WorkspaceTreeGridSection(title:parent.title,assets:direct)]
                    for child in parent.children where !child.children.isEmpty {result += sections(in:child)}
                    return result
                }
                self.onBucketPick?(WorkspaceTreeGridScope(key:node.key,title:node.title,sections:sections(in:node),fontBucket:node.fontDestination != nil || node.assetTypeID == "fonts"))
            } else if let id=node.importedAssetID {self.onOpenImportedAsset?(id)}
            else if let catalogue=node.catalogue {if catalogue != self.current {self.onCatalogue?(catalogue)}else{self.onPick?(.catalogue)}}
            else if ["favourites","claimed","palettes"].contains(node.key){self.onFilter?(node.key)}
            else if node.key == "mylibrary-typography" {self.onFilter?("typography")}
            else if let place=node.place {self.onPick?(place)}
        }
    }
    func outlineViewItemDidExpand(_ notification:Notification){
        guard !rebuilding,let node=notification.userInfo?["NSObject"] as? Node else{return}
        expanded.insert(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey)
        // AppKit posts this before its visible row geometry has settled. Measuring
        // in the next turn keeps the following sections below every expanded row.
        DispatchQueue.main.async { [weak self] in self?.refreshExtent() }
    }
    func outlineViewItemDidCollapse(_ notification:Notification){
        guard !rebuilding,let node=notification.userInfo?["NSObject"] as? Node else{return}
        expanded.remove(node.key);AppPreferences.shared.set(expanded.sorted(),forKey:expandedKey)
        DispatchQueue.main.async { [weak self] in self?.refreshExtent() }
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
        let groupTitle:String?
        var isGroup:Bool {groupTitle != nil}
        var isDrive:Bool {isRoot && !isGroup && (url.path == "/" || url.deletingLastPathComponent().path == "/Volumes")}
        var children:[Node]?
        var loading=false
        var loadedKind:String?
        init(url:URL,isDirectory:Bool,isRoot:Bool=false,groupTitle:String?=nil){self.url=url;self.isDirectory=isDirectory;self.isRoot=isRoot;self.groupTitle=groupTitle}
        var title:String {
            if let groupTitle {return groupTitle}
            if isRoot && url == WorkspaceImageIntakePane.userHome { return "Home — \(url.lastPathComponent)" }
            if isRoot, let name = try? url.resourceValues(forKeys:[.volumeNameKey]).volumeName,
               url.path == "/" || url.deletingLastPathComponent().path == "/Volumes" { return name }
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
    }
    var scrollbarOnLeft=false
    var onImageFiles:((URL?,[URL],WorkspaceImageScanEvent)->Void)?
    var assetKind="Palettes" {didSet{
        guard oldValue != assetKind else{return}
        for tree in [favouriteOutline,outline] {
            let expanded=(0..<tree.numberOfRows).compactMap{row -> Node? in
                guard let node=tree.item(atRow:row) as? Node,node.isDirectory,tree.isItemExpanded(node) else{return nil}
                return node
            }
            expanded.forEach{load($0)}
        }
        if let folder=selectedFolder {scan(folder.url)}
    }}
    private static let favouritesKey="Workspace.Import.FavouriteFolders"
    private static let favouriteRecordsKey="Workspace.Import.Favourites"
    private static let lastSourceKey="Workspace.Import.LastSourceFolder"
    private var favouritePaths:[String]=[]
    private var favouriteRoots:[Node]=[]
    private let favouriteOutline=WorkspaceBranchTree()
    private let favouritesHeading=WorkspaceSectionHeader("")
    private let systemHeading=WorkspaceSectionHeader("")
    private let noFavourites=NSTextField(labelWithString:"No favourites listed")
    private let folderMenu=SwissContextMenu()
    private var selectedTree:WorkspaceBranchTree?
    private var favouritesHeight:CGFloat {favouritesHeading.expanded ? max(28,WorkspaceBranchTree.rowsHeight(favouriteOutline.numberOfRows))+2*WorkspaceBranchTree.edgePadding:0}
    private final class ControlsHeader:NSView {
        override var isFlipped:Bool {true}
        override func draw(_ dirtyRect:NSRect){fill(bounds,Design.card);hairline(x:0,y:bounds.height-1,width:bounds.width)}
    }
    private let controlsHeader=ControlsHeader()
    var pinnedControls:NSView {controlsHeader}
    var pinnedControlsHeight:CGFloat {32}
    var controlsArePinned=false {didSet{needsLayout=true}}
    var minimumContentHeight:CGFloat {(controlsArePinned ? 0:32)+WorkspaceSectionHeader.height+favouritesHeight+WorkspaceSectionHeader.height+(systemHeading.expanded ? WorkspaceBranchTree.rowsHeight(outline.numberOfRows)+2*WorkspaceBranchTree.edgePadding:0)}
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
            tree.swatchFamily = .drives
            tree.outlinedRows = true
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("Image Folder Tree"))
            tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
            tree.rowHeight=34;tree.indentationPerLevel=0;tree.intercellSpacing=NSSize(width:0,height:WorkspaceBranchTree.rowSpacing)
            tree.backgroundColor=Design.card;tree.appearance=Theme.appearance;tree.style = .plain
            tree.dataSource=self;tree.delegate=self;tree.focusRingType = .none;tree.allowsMultipleSelection=false
            tree.onContext={ [weak self] item,point,view in if let node=item as? Node {self?.showFolderMenu(node,at:point,in:view)} }
            tree.rowColour={ item in
                guard let node=item as? Node else{return nil}
                return WorkspaceFavourites.colour(Self.favouriteRecordsKey,id:node.url.standardizedFileURL.path)
            }
        }
        outline.setAccessibilityLabel("System folder tree")
        favouriteOutline.setAccessibilityLabel("Favourite folder tree")
        favouritesHeading.title="Favourites";systemHeading.title="Locations"
        for (index,heading) in [favouritesHeading,systemHeading].enumerated() {
            heading.tag=index;heading.target=self;heading.action=#selector(toggleSourceSection(_:));addSubview(heading)
        }
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
        let sectionHeight=WorkspaceSectionHeader.height
        let firstBodyY:CGFloat=32-offset+sectionHeight
        favouritesHeading.frame=NSRect(x:0,y:32-offset,width:bounds.width,height:sectionHeight)
        noFavourites.frame=NSRect(x:16,y:firstBodyY+4+WorkspaceBranchTree.edgePadding,width:max(0,bounds.width-32),height:22)
        noFavourites.isHidden = !favouritesHeading.expanded || !favouriteRoots.isEmpty
        favouriteOutline.isHidden = !favouritesHeading.expanded || favouriteRoots.isEmpty
        favouriteOutline.frame=NSRect(x:0,y:firstBodyY+WorkspaceBranchTree.edgePadding,width:bounds.width,height:favouriteOutline.isHidden ? 0:favouritesHeight-2*WorkspaceBranchTree.edgePadding)
        let systemY=firstBodyY+favouritesHeight
        systemHeading.frame=NSRect(x:0,y:systemY,width:bounds.width,height:sectionHeight)
        outline.isHidden = !systemHeading.expanded
        outline.frame=NSRect(x:0,y:systemY+sectionHeight+WorkspaceBranchTree.edgePadding,width:bounds.width,height:outline.isHidden ? 0:max(0,bounds.height-systemY-sectionHeight-2*WorkspaceBranchTree.edgePadding))
        for tree in [favouriteOutline,outline] {tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()}
    }
    override func draw(_ dirtyRect:NSRect){
        if !controlsArePinned {hairline(x:0,y:32,width:bounds.width,Design.rule)}
        hairline(x:0,y:(controlsArePinned ? 0:32)+WorkspaceSectionHeader.height+favouritesHeight-2,width:bounds.width,Design.rule)
    }
    @objc private func toggleSourceSection(_ sender:WorkspaceSectionHeader){
        refreshExtent()
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
        if node.isGroup {cell.star.isHidden=true;cell.colourButton.isHidden=true;return}
        cell.star.favourite=isFavourite(node)
        cell.star.setAccessibilityLabel((cell.star.favourite ? "Remove Favourite: ":"Add Favourite: ")+node.title)
        cell.star.toolTip=cell.star.favourite ? "Remove From Favourites":"Add To Favourites"
        cell.star.run={ [weak self,weak node] in if let node {self?.toggleFavourite(node)} }
        cell.star.needsDisplay=true
        cell.colourButton.isHidden=true
        cell.colourButton.run=nil
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
    static func standardRootLocations()->(common:[(URL,String)],internalDrives:[(URL,String)],externalDrives:[(URL,String)],networkDrives:[(URL,String)]) {
        let home=userHome,disk=URL(fileURLWithPath:"/",isDirectory:true)
        let folderNames=["Desktop","Documents","Downloads","Pictures","Movies","Music"]
        let common=[(home,"Home — \(home.lastPathComponent)")]+folderNames.compactMap{name -> (URL,String)? in
            let url=home.appendingPathComponent(name,isDirectory:true)
            return FileManager.default.fileExists(atPath:url.path) ? (url,name):nil
        }
        let volumes=FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:[.volumeNameKey,.volumeIsLocalKey],options:[.skipHiddenVolumes]) ?? []
        var external:[(URL,String)]=[],network:[(URL,String)]=[]
        for url in volumes where url.standardizedFileURL.path != "/" {
            let values=try? url.resourceValues(forKeys:[.volumeNameKey,.volumeIsLocalKey])
            let name=values?.volumeName ?? url.lastPathComponent
            if values?.volumeIsLocal == false {network.append((url,name))}
            else {external.append((url,name))}
        }
        return (common,[(disk,"Macintosh HD")],external,network)
    }
    private var requestingAccess=false
    private func reloadRoots(){
        let path:(URL)->String={$0.standardizedFileURL.path}
        let locations=Self.standardRootLocations()
        let groups:[(String,[(URL,String)])]=[
            ("Common Folders",locations.common),
            ("Internal Drives",locations.internalDrives),
            ("External Drives",locations.externalDrives),
            ("Network Drives",locations.networkDrives)
        ]
        let system=groups.flatMap{$0.1.map{$0.0}}
        let newPaths=Set(system.map(path)),removed=systemRootPaths.subtracting(newPaths)
        // Reuse objects so loaded children, independent expansion and selection survive hot-plugging.
        let oldNodes=roots.flatMap{$0.isGroup ? ($0.children ?? []):[$0]}
        let existing=Dictionary(oldNodes.map{(path($0.url),$0)},uniquingKeysWith:{first,_ in first})
        let extras=oldNodes.filter{!systemRootPaths.contains(path($0.url)) && !newPaths.contains(path($0.url))}
        let expanded=(0..<outline.numberOfRows).compactMap{index -> Node? in
            guard let node=outline.item(atRow:index) as? Node,outline.isItemExpanded(node) else{return nil}
            return node
        }
        let selected=outline.selectedRowIndexes.compactMap{outline.item(atRow:$0) as? Node}
        roots=groups.compactMap{title,locations -> Node? in
            guard !locations.isEmpty else{return nil}
            let group=Node(url:URL(fileURLWithPath:"/import-group/\(title)"),isDirectory:false,groupTitle:title)
            group.children=locations.map{url,_ in existing[path(url)] ?? Node(url:url,isDirectory:true,isRoot:true)}
            return group
        }
        if !extras.isEmpty {
            let other=Node(url:URL(fileURLWithPath:"/import-group/Other Folders"),isDirectory:false,groupTitle:"Other Folders")
            other.children=extras;roots.append(other)
        }
        systemRootPaths=newPaths
        func disconnected(_ url:URL)->Bool {
            let value=path(url)
            return removed.contains{value == $0 || value.hasPrefix($0+"/")}
        }
        rebuilding=true
        outline.reloadData()
        for group in roots where group.isGroup {outline.expandItem(group)}
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
    func openAtImportLanding(){
        favouritesHeading.expanded=true;systemHeading.expanded=true
        for group in roots where group.isGroup {outline.expandItem(group)}
        if let home=roots.first(where:{$0.groupTitle == "Common Folders"})?.children?.first {
            outline.expandItem(home)
        }
        restoreLastSourceIfNeeded()
        outline.refreshSurfaces();refreshExtent()
    }
    /// Re-entering Import clears its candidate grid, so republish the retained source even
    /// when the asset type has not changed. Folder loading may still be in progress.
    func refreshSelectedSource(){
        restoreLastSourceIfNeeded()
        guard let selectedFolder else{return}
        scan(selectedFolder.url)
    }
    private func restoreLastSourceIfNeeded(){
        guard selectedFolder == nil,
              let path=AppPreferences.shared.string(forKey:Self.lastSourceKey),
              FileManager.default.fileExists(atPath:path) else{return}
        let url=URL(fileURLWithPath:path,isDirectory:true)
        #if APPSTORE
        guard FolderAccess.covers(url) else{return}
        #endif
        let standard=url.standardizedFileURL.path
        let favourite=favouriteRoots.first{$0.url.standardizedFileURL.path == standard}
        let existing=roots.flatMap{$0.children ?? []}.first{$0.url.standardizedFileURL.path == standard}
        let node=favourite ?? existing ?? Node(url:url,isDirectory:true,isRoot:true)
        let tree:WorkspaceBranchTree
        if favourite != nil {tree=favouriteOutline}
        else {
            tree=outline
            if existing == nil {
                let group=roots.first{$0.groupTitle == "Other Folders"} ?? Node(url:URL(fileURLWithPath:"/import-group/Other Folders"),isDirectory:false,groupTitle:"Other Folders")
                if !roots.contains(where:{$0 === group}) {roots.append(group)}
                group.children=(group.children ?? [])+[node]
                outline.reloadData();outline.expandItem(group)
            }
        }
        selectedFolder=node;selectedTree=tree
        let row=tree.row(forItem:node)
        if row >= 0 {
            rebuilding=true
            tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
            rebuilding=false
        }
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
            else if let existing=self.roots.flatMap({$0.isGroup ? ($0.children ?? []):[$0]}).first(where:{$0.url.standardizedFileURL.path == granted}) {chosen=existing}
            else {
                chosen=Node(url:url,isDirectory:true,isRoot:true)
                if let other=self.roots.first(where:{$0.groupTitle == "Other Folders"}) {other.children=(other.children ?? [])+[chosen]}
                else {
                    let other=Node(url:URL(fileURLWithPath:"/import-group/Other Folders"),isDirectory:false,groupTitle:"Other Folders")
                    other.children=[chosen];self.roots.append(other)
                }
                self.outline.reloadData()
                if let other=self.roots.first(where:{$0.groupTitle == "Other Folders"}) {self.outline.expandItem(other)}
            }
            chosen.children=nil;self.selectedFolder=chosen
            AppPreferences.shared.set(chosen.url.standardizedFileURL.path,forKey:Self.lastSourceKey)
            self.load(chosen)
            let tree=self.tree(for:chosen),row=tree.row(forItem:chosen)
            self.selectedTree=tree
            self.rebuilding=true
            (tree === self.outline ? self.favouriteOutline:self.outline).deselectAll(nil)
            if row>=0 {tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            self.rebuilding=false
            tree.expandItem(chosen)
            self.refreshSelectedSource()
        }
    }
    private func acceptedFile(_ url:URL,kind:String)->Bool {
        let ext=url.pathExtension.lowercased()
        if WorkspaceImport.supportedTypes.contains(kind) {return WorkspaceImport.importExtensions(for:kind).contains(ext)}
        if let type=UTType(filenameExtension:ext),type.conforms(to:.image) {return true}
        return Self.supportedImageExtensions.contains(ext)
    }
    private func load(_ node:Node){
        guard node.isDirectory,(node.children == nil || node.loadedKind != assetKind),!node.loading else{return}
        #if APPSTORE
        guard FolderAccess.covers(node.url) else {requestAccess(node);return}
        #endif
        node.loading=true
        let url=node.url
        let kind=assetKind
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
                guard self?.acceptedFile(child,kind:kind) == true else{return nil}
                return Node(url:child,isDirectory:false)
            }.sorted{
                if $0.isDirectory != $1.isDirectory{return $0.isDirectory}
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            DispatchQueue.main.async { [weak self,weak node] in
                guard let self,let node else{return}
                let existing=Dictionary((node.children ?? []).filter(\.isDirectory).map{($0.url.standardizedFileURL.path,$0)},uniquingKeysWith:{first,_ in first})
                node.children=found.map{candidate in existing[candidate.url.standardizedFileURL.path] ?? candidate}
                node.loadedKind=kind;node.loading=false
                let tree=self.tree(for:node),expanded=tree.isItemExpanded(node)
                if tree.row(forItem:node) >= 0 {
                    tree.reloadItem(node,reloadChildren:true)
                    if expanded{tree.expandItem(node)}
                }
                tree.refreshSurfaces();self.refreshExtent()
                if kind != self.assetKind {self.load(node)}
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
        return (node.isDirectory || node.isGroup) && node.children?.isEmpty != true
    }
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{
        let row=WorkspaceBranchTree.Row();row.accordion=outlineView as? WorkspaceBranchTree;return row
    }
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:outlineView.tableColumns[0].width,height:34))
        let label=NSTextField(labelWithString:node.title)
        label.font=(node.isGroup ? Design.Text.bodyStrong:Design.Text.body).font();label.textColor=node.isDrive ? Design.card:node.isGroup ? Design.quiet:Design.ink;label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel(node.isGroup ? "Location group: \(node.title)":node.isDirectory ? "Folder: \(node.title)":"File: \(node.title)")
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.url.path;configureStar(cell,node:node,in:outlineView)
        return cell
    }
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node {load(node)};(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    func outlineViewItemDidCollapse(_ notification:Notification){(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    func outlineView(_ outlineView:NSOutlineView,shouldSelectItem item:Any)->Bool {(item as? Node)?.isGroup != true}
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
            AppPreferences.shared.set(folder.url.standardizedFileURL.path,forKey:Self.lastSourceKey)
            // The file scan is independent of loading the tree's child folders. Waiting for
            // that second enumeration left the viewport empty until the asset type changed.
        }
        let files=nodes.filter{ !$0.isDirectory && !$0.isGroup }.map(\.url)
        if !files.isEmpty {scanGeneration+=1;scanCancellation?.cancel();onImageFiles?(selectedFolder?.url,[],.began);onImageFiles?(selectedFolder?.url,files,.batch);onImageFiles?(selectedFolder?.url,[],.completed)}
        else if let folder=selectedFolder {scan(folder.url)}
        else {scanGeneration+=1;scanCancellation?.cancel();onImageFiles?(nil,[],.began);onImageFiles?(nil,[],.completed)}
    }
    @objc private func nestedFoldersChanged(){includeNested=nestedFolders.state == .on;if let folder=selectedFolder,folder.children != nil{scan(folder.url)}}
    private func scan(_ folder:URL){
        scanGeneration+=1;let generation=scanGeneration,recursive=includeNested,kind=assetKind
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
                guard !cancellation.isCancelled,self.acceptedFile(url,kind:kind) else{return}
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

final class WorkspaceImageDestinationPane:NSView,NSOutlineViewDataSource,NSOutlineViewDelegate,WorkspaceScrollableContent,WorkspacePinnedPanelContent {
    final class Node:NSObject {
        let title:String
        let key:String
        let destination:WorkspaceImport.ImageDestination?
        let folder:URL?
        var children:[Node]=[]
        var loaded=false
        init(_ title:String,key:String,destination:WorkspaceImport.ImageDestination?=nil,folder:URL?=nil){self.title=title;self.key=key;self.destination=destination;self.folder=folder}
    }
    private static let customKey="Workspace.Import.CustomDestinations"
    private var roots:[[Node]]=[[],[],[]]
    private let outlines=(0..<3).map{_ in WorkspaceBranchTree()}
    private let sectionHeaders=["Client Tree","My Library","Custom Folders"].map{title -> WorkspaceSectionHeader in
        let header=WorkspaceSectionHeader(title);return header
    }
    private let controls=WorkspaceImportControlsView(frame:.zero)
    private let methodButtons:[WorkspaceImportMethodButton] = {
        zip(["Copy","Move","Reference"],["doc.on.doc","arrow.right","link"]).map{title,symbol in
            let button=WorkspaceImportMethodButton(frame:.zero);button.title=title;button.symbol=symbol;return button
        }
    }()
    private let summary=NSTextField(wrappingLabelWithString:"")
    private let addButton=WorkspaceImportActionButton(frame:.zero)
    private var selected:Node?
    private var customRoots:[Node]=[]
    private var changingSelection=false
    private var catalogueName="Catalogue"
    private var assetKind="Photographs"
    var transfer:WorkspaceImport.ImageTransfer = .copy {didSet{refreshAction()}}
    var selectedCount=0 {didSet{refreshAction()}}
    var onAdd:((WorkspaceImport.ImageDestination,WorkspaceImport.ImageTransfer)->Void)?
    var onTransfer:((WorkspaceImport.ImageTransfer)->Void)?
    var pinnedControls:NSView {controls}
    var pinnedControlsHeight:CGFloat {152}
    var controlsArePinned=false
    var minimumContentHeight:CGFloat {
        let trees=outlines.enumerated().reduce(CGFloat(0)){height,part in
            height+WorkspaceSectionHeader.height+(sectionHeaders[part.offset].expanded ? WorkspaceBranchTree.rowsHeight(part.element.numberOfRows)+2*WorkspaceBranchTree.edgePadding:0)
        }
        return max(230,trees+68+(controlsArePinned ? 0:pinnedControlsHeight))
    }
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for (index,outline) in outlines.enumerated() {
            outline.swatchFamily = index == 1 ? .yellow:index == 2 ? .drives:.charcoal
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("Image Destination Tree \(index)"))
            outline.addTableColumn(column);outline.outlineTableColumn=column;outline.headerView=nil
            outline.rowHeight=34;outline.indentationPerLevel=0;outline.intercellSpacing = NSSize(width:0,height:WorkspaceBranchTree.rowSpacing)
            outline.backgroundColor=Design.card;outline.appearance=Theme.appearance;outline.style = .plain
            outline.leadingDisclosure=true
            outline.dataSource=self;outline.delegate=self;outline.focusRingType = .none
            outline.rowColour={item in
                guard let node=item as? Node else{return nil}
                return WorkspaceNodeAppearance.colour(node.key)
            }
            outline.rowInk={item in
                guard let node=item as? Node else{return nil}
                return WorkspaceNodeAppearance.ink(node.key)
            }
            outline.rowBorder={item in
                guard let node=item as? Node else{return nil}
                return WorkspaceNodeAppearance.borderColour(node.key)
            }
            outline.setAccessibilityLabel(["Client destinations","My Library destinations","Custom folder destinations"][index])
            addSubview(sectionHeaders[index]);addSubview(outline);outline.installConnectors(in:self)
            sectionHeaders[index].target=self;sectionHeaders[index].action=#selector(toggleSection(_:));sectionHeaders[index].tag=index
        }
        summary.font=Design.Text.body.font();summary.textColor=Design.quiet;summary.maximumNumberOfLines=3
        controls.addSubview(summary)
        for (index,button) in methodButtons.enumerated() {
            button.tag=index;button.target=self;button.action=#selector(selectMethod(_:));controls.addSubview(button)
        }
        addButton.title="Import Selected Images";addSubview(addButton)
        addButton.target=self;addButton.action=#selector(importImages)
        customRoots=(AppPreferences.shared.stringArray(forKey:Self.customKey) ?? []).map{Self.diskNode(URL(fileURLWithPath:$0,isDirectory:true))}
        refreshAction()
    }
    required init?(coder:NSCoder){fatalError()}
    func clearSelection(){selected=nil;outlines.forEach{$0.deselectAll(nil)};refreshAction()}
    private static func diskNode(_ folder:URL)->Node {
        Node(folder.lastPathComponent.isEmpty ? folder.path:folder.lastPathComponent,key:"disk:"+folder.standardizedFileURL.path,destination:.custom(folder),folder:folder)
    }
    func configure(library:Library,schema:SchemaTrial.SchemaFile,preselect:(UUID,UUID)?=nil,catalogueName:String="Catalogue",assetKind:String="Photographs"){
        self.catalogueName=catalogueName;self.assetKind=assetKind
        let previous=selected?.key
        var clients:[Node]=[]
        for collection in schema.collections {
            let root=Node(collection.name,key:"collection:"+collection.id.uuidString)
            for project in library.orderedProjects where SchemaTrial.collection(of:project.id,among:schema.collections,places:schema.places).id == collection.id {
                let work=Node(project.name,key:String(describing:StudioFrame.Place.project(project.id)))
                // The live Library tree reads the member's resolved schema, including
                // its current Assets branch. Project that same tree into Import.
                let stack=SchemaTrial.schema(for:project.id)
                func destinationBranch(_ branch:SchemaNode)->Node? {
                    let kind=SchemaTrial.type(of:branch)
                    let acceptsImages=kind.caseInsensitiveCompare("Photography") == .orderedSame || kind.caseInsensitiveCompare("Images") == .orderedSame
                    let children=branch.children.compactMap(destinationBranch)
                    guard acceptsImages || !children.isEmpty else{return nil}
                    let node=Node(branch.name,key:WorkspaceNodeAppearance.projectNodeKey(project:project.id,node:branch.id),destination:acceptsImages ? .catalogue(member:project.id,bucket:branch.id):nil)
                    node.children=children
                    return node
                }
                work.children=stack.children.compactMap(destinationBranch)
                if !work.children.isEmpty {root.children.append(work)}
            }
            if !root.children.isEmpty {clients.append(root)}
        }
        let libraryRoot=Node("My Library",key:"catalogue")
        libraryRoot.children=[Node(assetKind,key:assetKind == "Images" ? "mylibrary-images":"mylibrary-photography",destination:.library)]
        let custom=Node("Custom Folders",key:"custom-folders")
        let common=WorkspaceImageIntakePane.standardRootLocations()
        let groups:[(String,String,[(URL,String)])]=[
            ("Common Folders","common",common.common),
            ("Internal Drives","internal",common.internalDrives),
            ("External Drives","external",common.externalDrives),
            ("Network Drives","network",common.networkDrives)
        ]
        custom.children=groups.compactMap{title,key,locations in
            let children=locations.map{url,name -> Node in
                let node=Self.diskNode(url);return Node(name,key:node.key,destination:node.destination,folder:url)
            }
            guard !children.isEmpty else{return nil}
            let group=Node(title,key:"folder-group:"+key);group.children=children;return group
        }+customRoots
        roots=[clients.isEmpty ? [Node("No Clients In This Catalogue",key:"empty-clients")]:clients,[libraryRoot],[custom]]
        selected=nil
        for outline in outlines {outline.reloadData()}
        for (index,outline) in outlines.enumerated() {
            for root in roots[index] {outline.expandItem(root);for child in root.children where child.folder == nil {outline.expandItem(child)}}
        }
        if let preselect {selectDestination(member:preselect.0,bucket:preselect.1)}
        else if let previous {selectDestination(key:previous)}
        outlines.forEach{$0.refreshSurfaces()};refreshAction();refreshExtent()
    }
    func selectDestination(member:UUID?,bucket:UUID?) {
        let key=member.flatMap{owner in bucket.map{WorkspaceNodeAppearance.projectNodeKey(project:owner,node:$0)}} ?? (assetKind == "Images" ? "mylibrary-images":"mylibrary-photography")
        selectDestination(key:key)
    }
    private func selectDestination(key:String) {
        func path(in nodes:[Node])->[Node]? {
            for node in nodes {
                if node.key == key{return [node]}
                if let children=path(in:node.children){return [node]+children}
            }
            return nil
        }
        for (index,outline) in outlines.enumerated() {
            guard let nodes=path(in:roots[index]),let target=nodes.last else{continue}
            for ancestor in nodes.dropLast(){outline.expandItem(ancestor)}
            let row=outline.row(forItem:target)
            guard row >= 0 else{continue}
            outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
            outline.scrollRowToVisible(row)
            selected=outline.item(atRow:row) as? Node
            refreshAction()
            return
        }
    }
    private func refreshAction(){
        addButton.isEnabled=selectedCount > 0 && selected?.destination != nil
        addButton.title="Import"
        for (index,button) in methodButtons.enumerated() {button.chosen=index == (transfer == .copy ? 0:transfer == .move ? 1:2)}
        let action=transfer == .copy ? "Copy keeps the originals and makes new files in the selected folder." : transfer == .move ? "Move places the originals in the selected folder and removes them from their previous location." : "Reference leaves the originals where they are and stores links to them."
        let destination=selected?.destination == nil ? "Select a destination below." : "Destination: \(selected?.title ?? "")."
        summary.stringValue="Importing \(assetKind) to catalogue \(catalogueName). \(action) \(destination)"
    }
    func setContext(catalogue:String,kind:String){catalogueName=catalogue;assetKind=kind;refreshAction()}
    @objc private func selectMethod(_ sender:WorkspaceImportMethodButton){
        transfer=sender.tag == 1 ? .move:sender.tag == 2 ? .reference:.copy
        onTransfer?(transfer)
    }
    @objc private func toggleSection(_ sender:WorkspaceSectionHeader){
        refreshExtent()
    }
    @objc private func importImages(){guard let destination=selected?.destination,selectedCount > 0 else{return};onAdd?(destination,transfer)}
    @objc func chooseFolder(){
        guard let window else{return}
        let panel=NSOpenPanel();panel.title="Choose Image Destination";panel.prompt="Use This Folder";panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.message="Choose any disk folder for copied or moved images. The active catalogue tracks the files and includes them in portable exports."
        panel.beginSheetModal(for:window){[weak self] response in
            guard let self,response == .OK,let folder=panel.url else{return}
            do {try FolderAccess.authorize(folder)}catch{NSApp.presentError(error);return}
            let key="disk:"+folder.standardizedFileURL.path
            if !self.customRoots.contains(where:{$0.key == key}) {self.customRoots.append(Self.diskNode(folder));AppPreferences.shared.set(self.customRoots.compactMap{$0.folder?.path},forKey:Self.customKey)}
            guard let custom=self.roots[2].first else{return}
            custom.children.removeAll{$0.key == key};custom.children.append(Self.diskNode(folder))
            let tree=self.outlines[2];tree.reloadItem(custom,reloadChildren:true);tree.expandItem(custom)
            if let row=(0..<tree.numberOfRows).first(where:{(tree.item(atRow:$0) as? Node)?.key == key}) {tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
            tree.refreshSurfaces();self.refreshExtent()
        }
    }
    private func load(_ node:Node){
        guard let folder=node.folder,!node.loaded else{return}
        node.loaded=true
        guard FolderAccess.covers(folder) || FileManager.default.isReadableFile(atPath:folder.path) else{return}
        let urls=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])) ?? []
        node.children=urls.compactMap{url in
            guard let values=try? url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),values.isDirectory == true,values.isSymbolicLink != true else{return nil}
            return Self.diskNode(url)
        }.sorted{$0.title.localizedStandardCompare($1.title) == .orderedAscending}
        if let tree=outlines.first(where:{$0.row(forItem:node) >= 0}) {tree.reloadItem(node,reloadChildren:true);tree.refreshSurfaces();refreshExtent()}
    }
    func outlineView(_ tree:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int {(item as? Node)?.children.count ?? roots[outlines.firstIndex(where:{$0 === tree}) ?? 0].count}
    func outlineView(_ tree:NSOutlineView,child index:Int,ofItem item:Any?)->Any {(item as? Node)?.children[index] ?? roots[outlines.firstIndex(where:{$0 === tree}) ?? 0][index]}
    func outlineView(_ tree:NSOutlineView,isItemExpandable item:Any)->Bool {let node=item as! Node;return node.folder != nil && !node.loaded || !node.children.isEmpty}
    func outlineView(_ tree:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{let row=WorkspaceBranchTree.Row();row.accordion=tree as? WorkspaceBranchTree;return row}
    func outlineView(_ tree:NSOutlineView,viewFor column:NSTableColumn?,item:Any)->NSView? {
        let node=item as! Node
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:tree.tableColumns[0].width,height:34))
        cell.leadingDisclosure=true;cell.symbol="folder";cell.star.isHidden=true
        let label=NSTextField(labelWithString:node.title)
        label.font=Design.Text.body.font();label.textColor=node.destination == nil ? Design.quiet:Design.ink
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel((node.destination == nil ? "Destination group: ":"Import destination: ")+node.title)
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.folder?.path ?? node.title
        return cell
    }
    func outlineViewSelectionDidChange(_ notification:Notification){
        guard !changingSelection,let tree=notification.object as? WorkspaceBranchTree else{return}
        changingSelection=true
        for other in outlines where other !== tree {other.deselectAll(nil)}
        changingSelection=false
        selected=tree.selectedRow >= 0 ? tree.item(atRow:tree.selectedRow) as? Node:nil
        refreshAction();outlines.forEach{$0.refreshSurfaces()}
    }
    func outlineViewItemDidExpand(_ notification:Notification){if let node=notification.userInfo?["NSObject"] as? Node {load(node)};(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    func outlineViewItemDidCollapse(_ notification:Notification){(notification.object as? WorkspaceBranchTree)?.refreshSurfaces();refreshExtent()}
    private func refreshExtent(){needsLayout=true;var ancestor=superview;while let view=ancestor{if let panel=view as? WorkspacePanel{panel.rail?.arrange();break};ancestor=view.superview}}
    override func layout(){
        super.layout()
        if !controlsArePinned {controls.frame=NSRect(x:0,y:0,width:bounds.width,height:pinnedControlsHeight)}
        let width=controls.bounds.width,margin:CGFloat=10,gap:CGFloat=4
        let buttonWidth=max(0,(width-margin*2-gap*2)/3)
        for (index,button) in methodButtons.enumerated() {button.frame=NSRect(x:margin+CGFloat(index)*(buttonWidth+gap),y:12,width:buttonWidth,height:40)}
        summary.frame=NSRect(x:margin,y:64,width:max(0,width-margin*2),height:76)
        var y:CGFloat=controlsArePinned ? 0:pinnedControlsHeight
        for (index,tree) in outlines.enumerated() {
            let header=sectionHeaders[index];header.frame=NSRect(x:0,y:y,width:bounds.width,height:WorkspaceSectionHeader.height);y+=WorkspaceSectionHeader.height
            let height=header.expanded ? WorkspaceBranchTree.rowsHeight(tree.numberOfRows)+2*WorkspaceBranchTree.edgePadding:0
            tree.isHidden = !header.expanded
            tree.frame=NSRect(x:0,y:y+WorkspaceBranchTree.edgePadding,width:bounds.width,height:header.expanded ? height-2*WorkspaceBranchTree.edgePadding:0)
            tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors();y+=height
        }
        addButton.frame=NSRect(x:16,y:y+14,width:max(0,bounds.width-32),height:42)
    }
}
