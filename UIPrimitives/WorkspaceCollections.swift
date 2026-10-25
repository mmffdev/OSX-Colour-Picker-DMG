import AppKit

/// Curated membership is independent of the catalogue's ownership/schema tree.
/// One stable asset identity may occur in any number of Collections.
struct AssetCollectionItem:Codable,Equatable,Hashable {
    var kind:String
    var identity:String
    var name:String
    var key:String {kind + "/" + identity}
    static func palette(_ id:UUID,name:String)->Self {.init(kind:"Palette",identity:id.uuidString,name:name)}
    static func colour(_ hex:String,name:String)->Self {.init(kind:"Colour",identity:hex.uppercased(),name:name)}
    static func imported(_ record:WorkspaceImportedAsset)->Self {.init(kind:record.type,identity:record.id.uuidString,name:record.name)}
    static func file(_ path:String,kind:String,name:String)->Self {.init(kind:kind,identity:URL(fileURLWithPath:path).standardizedFileURL.path,name:name)}
}

struct AssetCollectionEntry:Codable,Equatable,Identifiable {
    var id=UUID()
    var name:String
    var items:[AssetCollectionItem]=[]
    var colour:String?=nil
}

enum AssetCollections {
    static let defaultColour="#F4BE00"
    static func defaultEntry()->AssetCollectionEntry {.init(name:"My Collection",colour:defaultColour)}
    static func list(in store:LibraryStore)->[AssetCollectionEntry] {
        CatalogueTree.catalogue(in:store.root)?.assetCollections ?? []
    }
    static func rootColour(in store:LibraryStore)->String? {
        CatalogueTree.catalogue(in:store.root)?.assetCollectionsRootColour
    }
    static func setRootColour(_ hex:String?,in store:LibraryStore)throws {
        try Handler_File_Manager.shared.withTransaction(home:store.root) {
            try Handler_File_Manager.shared.update(store.url) { object in
                object["assetCollectionsRootColour"]=hex
            }
        }
    }
    /// Older catalogues have no membership field; an intentionally empty array stays empty.
    static func seedIfNeeded(in store:LibraryStore)throws {
        guard let catalogue=CatalogueTree.catalogue(in:store.root),catalogue.assetCollections == nil else{return}
        try update(in:store){rows in if rows.isEmpty {rows.append(defaultEntry())}}
    }
    static func update(in store:LibraryStore,_ change:(inout [AssetCollectionEntry]) throws -> Void)throws {
        try Handler_File_Manager.shared.withTransaction(home:store.root) {
            try mutateDocument(in:store,change)
        }
    }
    static func mutateDocument(in store:LibraryStore,_ change:(inout [AssetCollectionEntry]) throws -> Void)throws {
        try Handler_File_Manager.shared.update(store.url) { object in
            let data=try object["assetCollections"].map{try JSONSerialization.data(withJSONObject:$0)}
            var collections=try data.map{try ColourFiles.decoder().decode([AssetCollectionEntry].self,from:$0)} ?? []
            try change(&collections)
            object["assetCollections"]=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(collections))
        }
    }
    /// Called inside the asset's owning transaction after its catalogue write.
    /// A deleted identity must not survive in any Collection that linked it.
    static func removeDeletedInTransaction(_ keys:Set<String>,in store:LibraryStore)throws {
        guard !keys.isEmpty,
              let collections=CatalogueTree.catalogue(in:store.root)?.assetCollections,
              collections.contains(where:{$0.items.contains(where:{keys.contains($0.key)})}) else{return}
        try mutateDocument(in:store){rows in
            for index in rows.indices {rows[index].items.removeAll{keys.contains($0.key)}}
        }
    }
    /// Repair membership left by older builds after a palette has disappeared.
    /// Keep records for linked sources whose file is temporarily unavailable.
    static func removeMissingPalettes(in store:LibraryStore,library:Library)throws {
        let live=Set(library.swatches.map(\.id))
        let linked=Set(WorkspaceImport.records(store:store).map{$0.0.id})
        let missing=Set(list(in:store).flatMap(\.items).compactMap{item -> String? in
            guard item.kind == "Palette",let id=UUID(uuidString:item.identity),
                  !live.contains(id),!linked.contains(id) else{return nil}
            return item.key
        })
        guard !missing.isEmpty else{return}
        try Handler_File_Manager.shared.withTransaction(home:store.root){
            try removeDeletedInTransaction(missing,in:store)
        }
    }
    static func appendInTransaction(_ items:[AssetCollectionItem],to id:UUID,in store:LibraryStore)throws {
        try mutateDocument(in:store){rows in
            guard let index=rows.firstIndex(where:{$0.id == id}) else{throw failure("The chosen Collection no longer exists.")}
            var existing=Set(rows[index].items.map(\.key))
            rows[index].items += items.filter{existing.insert($0.key).inserted}
        }
    }
    @discardableResult static func create(_ name:String,colour:String=defaultColour,in store:LibraryStore)throws -> UUID {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else{throw failure("Enter a Collection name.")}
        let id=UUID()
        try update(in:store){ rows in
            guard !rows.contains(where:{$0.name.caseInsensitiveCompare(trimmed) == .orderedSame}) else{throw failure("A Collection with this name already exists.")}
            rows.append(.init(id:id,name:trimmed,colour:colour))
        }
        return id
    }
    static func rename(_ id:UUID,to name:String,in store:LibraryStore)throws {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else{throw failure("Enter a Collection name.")}
        try update(in:store){ rows in
            guard !rows.contains(where:{$0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame}),let index=rows.firstIndex(where:{$0.id == id}) else{throw failure("This Collection is missing or its name is taken.")}
            rows[index].name=trimmed
        }
    }
    static func edit(_ id:UUID,name:String,colour:String,in store:LibraryStore)throws {
        let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else{throw failure("Enter a Collection name.")}
        try update(in:store){ rows in
            guard !rows.contains(where:{$0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame}),let index=rows.firstIndex(where:{$0.id == id}) else{throw failure("This Collection is missing or its name is taken.")}
            rows[index].name=trimmed;rows[index].colour=colour
        }
    }
    static func setColour(_ hex:String?,for id:UUID,in store:LibraryStore)throws {
        try update(in:store){rows in
            guard let index=rows.firstIndex(where:{$0.id == id}) else{throw failure("This Collection is missing.")}
            rows[index].colour=hex
        }
    }
    static func reorderCollections(_ ids:[UUID],in store:LibraryStore)throws {
        try update(in:store){rows in
            guard Set(ids)==Set(rows.map(\.id)),ids.count==rows.count else{throw failure("The Collection order changed. Try again.")}
            let mapped=Dictionary(uniqueKeysWithValues:rows.map{($0.id,$0)})
            rows=ids.compactMap{mapped[$0]}
        }
    }
    static func reorderItems(_ keys:[String],in id:UUID,store:LibraryStore)throws {
        try update(in:store){rows in
            guard let index=rows.firstIndex(where:{$0.id==id}) else{throw failure("The Collection is missing.")}
            let items=rows[index].items
            guard Set(keys)==Set(items.map(\.key)),keys.count==items.count else{throw failure("The asset order changed. Try again.")}
            let mapped=Dictionary(uniqueKeysWithValues:items.map{($0.key,$0)})
            rows[index].items=keys.compactMap{mapped[$0]}
        }
    }
    static func remove(_ id:UUID,in store:LibraryStore)throws {
        try update(in:store){rows in rows.removeAll{$0.id == id}}
    }
    static func add(_ items:[AssetCollectionItem],to id:UUID,in store:LibraryStore)throws {
        try update(in:store){ rows in
            guard let index=rows.firstIndex(where:{$0.id == id}) else{throw failure("The chosen Collection no longer exists.")}
            var existing=Set(rows[index].items.map(\.key))
            rows[index].items += items.filter{existing.insert($0.key).inserted}
        }
    }
    static func remove(_ item:AssetCollectionItem,from id:UUID,in store:LibraryStore)throws {
        try update(in:store){rows in
            guard let index=rows.firstIndex(where:{$0.id == id}) else{return}
            rows[index].items.removeAll{$0.key == item.key}
        }
    }
    static func remove(_ items:[AssetCollectionItem],from id:UUID,in store:LibraryStore)throws {
        let keys=Set(items.map(\.key))
        try update(in:store){rows in
            guard let index=rows.firstIndex(where:{$0.id == id}) else{return}
            rows[index].items.removeAll{keys.contains($0.key)}
        }
    }
}

final class WorkspaceCollectionsPane:NSView,NSOutlineViewDataSource,NSOutlineViewDelegate,WorkspacePanelContentMetrics {
    final class Node:NSObject {
        enum Value {case root,add,collection(AssetCollectionEntry),asset(AssetCollectionItem,UUID)}
        var value:Value
        var children:[Node]=[]
        var accent:NSColor?
        init(_ value:Value){self.value=value}
    }
    private let tree=WorkspaceBranchTree(frame:.zero)
    private let contextMenu=SwissContextMenu()
    private let root=Node(.root)
    private var rootColour:String?
    private func assetColourKey(_ item:AssetCollectionItem,_ collection:UUID)->String{"collection-link:\(collection.uuidString):\(item.key)"}
    private func appearanceKey(_ node:Node)->String? {
        switch node.value {
        case .root:return "collections-root"
        case .collection(let entry):return "collection:"+entry.id.uuidString
        case .asset(let asset,let collection):return assetColourKey(asset,collection)
        case .add:return nil
        }
    }
    func installColourMode(_ mode:WorkspaceColourMode){
        mode.register(tree){[weak self] item in
            guard let self,let node=item as? Node else{return nil}
            switch node.value {
            case .add:return nil
            case .root:
                return WorkspaceColourMode.Target(id:"collections-root",name:"Collections",read:{[weak self] channel in
                    switch channel {
                    case .background:return self?.rootColour.map(Design.hex)
                    case .text:return WorkspaceNodeAppearance.textColour("collections-root")
                    case .border:return WorkspaceNodeAppearance.borderColour("collections-root")
                    }
                },write:{[weak self] channel,hex in
                    guard let self,let controller=self.controller else{return}
                    switch channel {
                    case .text:WorkspaceNodeAppearance.setText(hex,for:"collections-root");self.tree.repaintColours()
                    case .border:WorkspaceNodeAppearance.setBorder(hex,for:"collections-root");self.tree.repaintColours()
                    case .background:
                        do{try AssetCollections.setRootColour(hex,in:controller.store);self.rootColour=hex;self.tree.repaintColours()}
                        catch{controller.flash(error.localizedDescription)}
                    }
                })
            case .collection(let entry):
                let key="collection:"+entry.id.uuidString
                return WorkspaceColourMode.Target(id:key,name:entry.name,read:{[weak self] channel in
                    switch channel {
                    case .background:return self?.root.children.compactMap{node -> NSColor? in if case .collection(let current)=node.value,current.id == entry.id{return current.colour.map(Design.hex)};return nil}.first
                    case .text:return WorkspaceNodeAppearance.textColour(key)
                    case .border:return WorkspaceNodeAppearance.borderColour(key)
                    }
                },write:{[weak self] channel,hex in
                    guard let self,let controller=self.controller else{return}
                    switch channel {
                    case .text:WorkspaceNodeAppearance.setText(hex,for:key);self.tree.repaintColours()
                    case .border:WorkspaceNodeAppearance.setBorder(hex,for:key);self.tree.repaintColours()
                    case .background:
                        do{try AssetCollections.setColour(hex,for:entry.id,in:controller.store);self.repaintCollection(entry.id,colour:hex)}
                        catch{controller.flash(error.localizedDescription)}
                    }
                })
            case .asset(let asset,let collection):
                let key=self.assetColourKey(asset,collection)
                return WorkspaceColourMode.Target(id:key,name:asset.name,read:{channel in
                    switch channel {
                    case .background:return WorkspaceNodeAppearance.colour(key)
                    case .text:return WorkspaceNodeAppearance.textColour(key)
                    case .border:return WorkspaceNodeAppearance.borderColour(key)
                    }
                },write:{[weak self] channel,hex in
                    switch channel {
                    case .background:WorkspaceNodeAppearance.set(hex,for:key)
                    case .text:WorkspaceNodeAppearance.setText(hex,for:key)
                    case .border:WorkspaceNodeAppearance.setBorder(hex,for:key)
                    }
                    self?.tree.repaintColours()
                })
            }
        }
    }
    private weak var controller:LibraryController?
    private var loadedCataloguePath=""
    private var importedPalettePreviews:[String:ImportedPalette]=[:]
    private var importedPaletteLoading:Set<String>=[]
    var onOpenAsset:((AssetCollectionItem)->Void)?
    var customColoursAction:((AssetCollectionItem)->HaloAction?)?
    var onBucketPick:((WorkspaceTreeGridScope)->Void)?
    var onMultiColourSelect:((Node)->Void)?
    func selectColourTarget(_ node:Node,in mode:WorkspaceColourMode){mode.select(node,in:tree)}
    var onChanged:(()->Void)?
    var onColourChanged:(()->Void)?
    private func repaintCollection(_ id:UUID,colour:String?) {
        guard let node=root.children.first(where:{if case .collection(let entry)=$0.value{return entry.id == id};return false}),
              case .collection(var entry)=node.value else{return}
        entry.colour=colour;node.value = .collection(entry)
        for child in node.children {child.accent=colour.map(Design.hex)}
        tree.repaintColours()
        onColourChanged?()
    }
    var onFavourite:((UUID)->Void)?
    var onRename:((UUID,String)->Void)?
    var onTarget:((UUID)->Void)?
    var onTags:((UUID)->Void)?
    var onRating:((UUID,Int)->Void)?
    var onFlag:((UUID,PaletteReview.Flag?)->Void)?
    private var rowsHeight:CGFloat {(0..<tree.numberOfRows).reduce(0){sum,index in sum+outlineView(tree,heightOfRowByItem:tree.item(atRow:index)!)}+CGFloat(max(0,tree.numberOfRows-1))*WorkspaceBranchTree.rowSpacing}
    var minimumContentHeight:CGFloat {max(34,rowsHeight)+2*WorkspaceBranchTree.edgePadding}
    override var isFlipped:Bool{true}
    init(controller:LibraryController){
        self.controller=controller;super.init(frame:.zero)
        let column=NSTableColumn(identifier:.init("Collections"))
        tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
        tree.rowHeight=34;tree.intercellSpacing = NSSize(width:0,height:WorkspaceBranchTree.rowSpacing);tree.indentationPerLevel=0
        tree.backgroundColor=Design.card;tree.style = .plain;tree.focusRingType = .none
        tree.leadingDisclosure=true;tree.expandsOnSelection=false;tree.allowsEmptySelection=true
        tree.swatchFamily = .charcoal;tree.outlinedRows=true
        tree.delegate=self;tree.dataSource=self
        tree.rowColour={[weak self] item in
            guard let node=item as? Node else{return nil}
            switch node.value {
            case .root:return self?.rootColour.map(Design.hex)
            case .collection(let entry):return entry.colour.map(Design.hex)
            case .asset(let asset,let collection):return WorkspaceNodeAppearance.colour(self?.assetColourKey(asset,collection) ?? "")
            case .add:return nil
            }
        }
        tree.rowFill={[weak self] item in
            guard let node=item as? Node else{return false}
            switch node.value {
            case .root:return self?.rootColour != nil
            case .collection(let entry):return entry.colour != nil
            case .asset(let asset,let collection):return WorkspaceNodeAppearance.colour(self?.assetColourKey(asset,collection) ?? "") != nil
            case .add:return false
            }
        }
        tree.rowLeadingAccent={[weak self] item in
            guard let self,let node=item as? Node,case .asset(let asset,let collection)=node.value else{return nil}
            if WorkspaceNodeAppearance.colour(self.assetColourKey(asset,collection)) != nil{return nil}
            return node.accent
        }
        tree.rowClear={[weak self] item in
            guard let self,let node=item as? Node,case .asset(let asset,let collection)=node.value else{return false}
            return WorkspaceNodeAppearance.colour(self.assetColourKey(asset,collection)) == nil
        }
        tree.rowInk={[weak self] item in
            guard let self,let node=item as? Node,let key=self.appearanceKey(node) else{return nil}
            if let ink=WorkspaceNodeAppearance.textColour(key){return ink}
            if case .asset(let asset,let collection)=node.value{return WorkspaceNodeAppearance.ink(self.assetColourKey(asset,collection))}
            return nil
        }
        tree.rowBorder={[weak self] item in
            guard let self,let node=item as? Node,let key=self.appearanceKey(node) else{return nil}
            return WorkspaceNodeAppearance.borderColour(key)
        }
        tree.onContext={[weak self] item,point,view in
            guard let self,let node=item as? Node else{return}
            var actions:[HaloAction]
            switch node.value {
            case .root:
                var colour=HaloAction(id:"colour",label:"Colour",symbol:"square.fill",onSelect:{[weak self] in
                    self?.onMultiColourSelect?(node)
                })
                colour.menuSwatch=Design.hex(self.rootColour ?? (hexOf(Design.card) ?? "#F8F7F5"))
                actions=[colour,HaloAction(id:"divider-colour",label:"",symbol:""),
                         HaloAction(id:"new",label:"New Collection…",symbol:"plus",onSelect:{[weak self] in self?.createCollection()})]
            case .add:
                actions=[HaloAction(id:"new",label:"New Collection…",symbol:"plus",onSelect:{[weak self] in self?.createCollection()})]
            case .collection(let collection):
                actions=[
                    { () -> HaloAction in
                        var action=HaloAction(id:"colour",label:"Colour",symbol:"square.fill",onSelect:{[weak self] in
                            self?.onMultiColourSelect?(node)
                        })
                        action.menuSwatch=Design.hex(collection.colour ?? AssetCollections.defaultColour)
                        return action
                    }(),
                    HaloAction(id:"divider-colour",label:"",symbol:""),
                    HaloAction(id:"edit",label:"Edit Collection…",symbol:"slider.horizontal.3",onSelect:{[weak self] in self?.editCollection(collection)}),
                    HaloAction(id:"remove",label:"Remove Collection…",symbol:"trash",confirmation:("Slide to remove","Assets stay in their original locations"),onSelect:{[weak self] in
                        guard let self,let controller=self.controller else{return}
                        do{try AssetCollections.remove(collection.id,in:controller.store);self.refresh();self.onChanged?()}
                        catch{controller.flash(error.localizedDescription)}
                    })
                ]
            case .asset(let asset,let collectionID):
                let remove=HaloAction(id:"remove",label:"Remove From Collection",symbol:"minus.circle",onSelect:{[weak self] in
                    guard let self,let controller=self.controller else{return}
                    do{try AssetCollections.remove(asset,from:collectionID,in:controller.store);self.refresh();self.onChanged?()}
                    catch{controller.flash(error.localizedDescription)}
                })
                do {
                    actions=[HaloAction(id:"open",label:"Open",symbol:"arrow.up.right",onSelect:{[weak self] in self?.onOpenAsset?(asset)}),remove]
                    if let custom=customColoursAction?(asset){actions.insert(custom,at:1)}
                }
            }
            if case .add=node.value {} else {
                actions.insert(HaloAction(id:"multi-colour",label:"Multi Colour Select",symbol:"square.grid.2x2",onSelect:{[weak self] in self?.onMultiColourSelect?(node)}),at:0)
                actions.insert(HaloAction(id:"divider-multi-colour",label:"",symbol:""),at:1)
            }
            self.contextMenu.open(actions,at:point,in:view)
        }
        tree.setAccessibilityLabel("Collections and their assets")
        addSubview(tree);tree.installConnectors(in:self);refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    func refresh(){
        guard let controller else{return}
        loadedCataloguePath=controller.store.root.standardizedFileURL.path
        do{try AssetCollections.seedIfNeeded(in:controller.store)}catch{controller.flash(error.localizedDescription)}
        do{try AssetCollections.removeMissingPalettes(in:controller.store,library:controller.library)}catch{controller.flash(error.localizedDescription)}
        rootColour=AssetCollections.rootColour(in:controller.store)
        let imports=Dictionary(WorkspaceImport.records(store:controller.store).map{($0.0.id.uuidString,$0.0)},uniquingKeysWith:{first,_ in first})
        let previewRecords=AssetCollections.list(in:controller.store).flatMap(\.items).filter{$0.kind == "Palettes" && importedPalettePreviews[$0.identity] == nil && !importedPaletteLoading.contains($0.identity)}.compactMap{imports[$0.identity]}
        if !previewRecords.isEmpty {
            let root=controller.store.root
            importedPaletteLoading.formUnion(previewRecords.map{$0.id.uuidString})
            DispatchQueue.global(qos:.userInitiated).async{[weak self] in
                var loaded:[String:ImportedPalette]=[:]
                for record in previewRecords {
                    guard let url=try? record.url(in:root),let data=try? Data(contentsOf:url),let preview=PaletteImport.read(data,fallback:record.name).first else{continue}
                    loaded[record.id.uuidString]=preview
                }
                DispatchQueue.main.async{[weak self] in
                    guard let self else{return}
                    self.importedPaletteLoading.subtract(previewRecords.map{$0.id.uuidString})
                    guard self.loadedCataloguePath == root.standardizedFileURL.path else{return}
                    self.importedPalettePreviews.merge(loaded,uniquingKeysWith:{_,new in new})
                    self.tree.reloadData();self.tree.expandItem(self.root)
                    for node in self.root.children {self.tree.expandItem(node)}
                    self.tree.refreshSurfaces();self.needsLayout=true
                }
            }
        }
        func current(_ saved:AssetCollectionItem)->AssetCollectionItem {
            var item=saved
            if item.kind == "Palette",let id=UUID(uuidString:item.identity),let palette=controller.library.swatch(id){item.name=palette.name}
            else if item.kind == "Colour" {item.name=controller.library.name(of:item.identity,in:nil)}
            else if let record=imports[item.identity] {item.name=record.name}
            else if item.kind == "ICC Profile",let profile=ICCProfileLibrary.shared.profiles.first(where:{$0.id == item.identity}) {item.name=profile.name}
            return item
        }
        root.children=[Node(.add)]+AssetCollections.list(in:controller.store).map{ collection in
            let node=Node(.collection(collection))
            let accent=collection.colour.map(Design.hex)
            node.children=collection.items.filter{item in
                ["Palette","Colour","ICC Profile"].contains(item.kind) || WorkspaceImport.supportsRecord(item.kind)
            }.map{item in
                let asset=Node(.asset(current(item),collection.id));asset.accent=accent;return asset
            }
            return node
        }
        tree.reloadData();tree.expandItem(root)
        for node in root.children {tree.expandItem(node)}
        tree.refreshSurfaces();needsLayout=true
        if let panel=superview as? WorkspacePanel {panel.rail?.arrange()}
    }
    func refreshIfCatalogueChanged(){
        guard let controller,loadedCataloguePath != controller.store.root.standardizedFileURL.path else{return}
        refresh()
    }
    override func layout(){super.layout();tree.frame=NSRect(x:0,y:WorkspaceBranchTree.edgePadding,width:bounds.width,height:max(34,rowsHeight));tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()}
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{(item as? Node)?.children.count ?? 1}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{(item as? Node)?.children[index] ?? root}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!(item as! Node).children.isEmpty}
    func outlineView(_ outlineView:NSOutlineView,heightOfRowByItem item:Any)->CGFloat {
        let base:CGFloat
        if let node=item as? Node,case .asset(let asset,_)=node.value {
            base=["Palette","Palettes"].contains(asset.kind) ? WorkspaceBranchTree.paletteRowHeight:34
        } else {base=34}
        return (outlineView as? WorkspaceBranchTree)?.colourTargetRowHeight(for:item,base:base) ?? base
    }
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{let row=WorkspaceBranchTree.Row();row.accordion=tree;return row}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node,cell=WorkspaceBranchTree.Cell(frame:.zero)
        cell.leadingDisclosure=true;cell.star.isHidden=true
        let title:String
        switch node.value {
        case .root:
            title="Collections";cell.symbol="square.grid.2x2";cell.compactMetadata=true
            cell.inlineActionBeforeCount=true
            cell.countLabel.stringValue=String(root.children.count-1);cell.countLabel.isHidden=false
            cell.catalogueAction.isHidden=false;cell.catalogueAction.symbol="gearshape"
        case .add:title="Add Collection";cell.symbol="plus";cell.compactMetadata=true
        case .collection(let collection):
            title=collection.name;cell.symbol="folder"
            cell.inlineActionBeforeCount=true
            cell.countLabel.stringValue=collection.items.isEmpty ? "(0)":String(collection.items.count)
            cell.countLabel.isHidden=false
            cell.catalogueAction.isHidden=false;cell.catalogueAction.symbol="gearshape"
        case .asset(let asset,_):
            title=asset.name;cell.symbol="doc";cell.compactMetadata=true
            cell.trailingGearAndCount=true
            cell.countLabel.stringValue="(0)";cell.countLabel.isHidden=false
            cell.catalogueAction.isHidden=false;cell.catalogueAction.symbol="gearshape"
            if asset.kind == "Palette",let id=UUID(uuidString:asset.identity),let palette=controller?.library.swatch(id),let controller {
                cell.compactMetadata=false;cell.isPalette=true;cell.twoLines=true;cell.symbol="swatchpalette"
                cell.renamePalette={[weak self] name in self?.onRename?(id,name);self?.refresh()}
                cell.spectrumColours=palette.entries.map{controller.library.definition(of:$0.hex)?.master.display ?? Design.hex($0.hex)}
                cell.countLabel.stringValue=String(palette.entries.count);cell.countLabel.isHidden=false
                let value=PaletteAssetHandler.presentation(palette,in:controller.library)
                cell.review.configure(value);cell.review.onRating={[weak self] rating in self?.onRating?(id,rating);self?.refresh()}
                cell.review.onFlag={[weak self] flag in self?.onFlag?(id,flag);self?.refresh()}
                cell.target.active=value.isTarget;cell.target.symbol="scope"
                cell.target.setAccessibilityLabel((value.isTarget ? "Stop Targeting ":"Target New Picks To ")+palette.name)
                cell.target.run={[weak self] in self?.onTarget?(id);self?.refresh()}
                cell.tagIcon.setAccessibilityLabel("Tags: "+palette.name)
                cell.tagIcon.run={[weak self] in self?.onTags?(id)}
                cell.star.isHidden=false;cell.star.favourite=palette.favourite
                cell.star.setAccessibilityLabel((palette.favourite ? "Remove Favourite: ":"Add Favourite: ")+palette.name)
                cell.star.run={[weak self] in self?.onFavourite?(id);self?.refresh()}
                cell.paletteDrag=(id,palette.name,cell.spectrumColours)
                cell.selectPalette={[weak self,weak node] in
                    guard let self,let node else{return}
                    let row=self.tree.row(forItem:node)
                    if row >= 0{self.tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
                }
            } else if asset.kind == "Palettes" {
                cell.compactMetadata=false;cell.isPalette=true;cell.twoLines=true;cell.symbol="swatchpalette"
                if let preview=importedPalettePreviews[asset.identity] {
                    cell.spectrumColours=preview.colours.map{Design.hex($0.hex)}
                    cell.countLabel.stringValue=String(preview.colours.count);cell.countLabel.isHidden=false
                    cell.review.configure(name:preview.name,review:preview.review)
                }
                cell.review.isReadOnly=true
                cell.star.isHidden=false;cell.star.isEnabled=false
                cell.target.isHidden=false;cell.target.symbol="scope";cell.target.isEnabled=false
                cell.tagIcon.isHidden=true
            }
        }
        if !cell.catalogueAction.isHidden {
            cell.catalogueAction.setAccessibilityLabel("Actions For "+title)
            cell.catalogueAction.toolTip="Actions For "+title
            cell.catalogueAction.run={[weak self,weak cell] in
                guard let self,let cell else{return}
                self.tree.onContext?(node,NSPoint(x:cell.catalogueAction.frame.minX,y:cell.catalogueAction.frame.maxY),cell)
            }
        }
        switch node.value {
        case .collection:
            cell.grip.isHidden=false;cell.grip.toolTip="Drag To Reorder "+title
            cell.reorderDrag={[weak self,weak node] event in guard let self,let node else{return};self.dragNode(node,from:event)}
        case .root,.add,.asset:break
        }
        let label=NSTextField(labelWithString:title)
        label.font=Design.Text.body.font()
        label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label);cell.textField=label;cell.toolTip=title;return cell
    }
    func outlineViewSelectionDidChange(_ notification:Notification){
        if tree.colourModeActive{return}
        guard tree.selectedRow >= 0,let node=tree.item(atRow:tree.selectedRow) as? Node else{return}
        switch node.value {
        case .add:
            tree.deselectAll(nil)
            DispatchQueue.main.async{[weak self] in self?.createCollection()}
        case .asset(let item,_):onOpenAsset?(item)
        case .root,.collection:
            func sections(in parent:Node)->[WorkspaceTreeGridSection] {
                let direct:[WorkspaceTreeGridAsset]=parent.children.compactMap{child in
                    guard case .asset(let item,_)=child.value else{return nil}
                    if item.kind == "Palette",let id=UUID(uuidString:item.identity){return .palette(id)}
                    if item.kind == "Colour" {return .colour(item.identity)}
                    if let id=UUID(uuidString:item.identity){return .imported(id)}
                    return .other(name:item.name,kind:item.kind,identity:item.identity)
                }
                let title:String
                switch parent.value {case .root:title="Collections";case .collection(let entry):title=entry.name;default:title="Assets"}
                var result=direct.isEmpty ? []:[WorkspaceTreeGridSection(title:title,assets:direct)]
                for child in parent.children where !child.children.isEmpty {result += sections(in:child)}
                return result
            }
            let title:String,key:String
            switch node.value {case .root:title="Collections";key="collections-root";case .collection(let entry):title=entry.name;key="collection:"+entry.id.uuidString;default:return}
            onBucketPick?(WorkspaceTreeGridScope(key:key,title:title,sections:sections(in:node)))
        }
    }
    private func dragNode(_ node:Node,from start:NSEvent){
        guard let window,let parent=tree.parent(forItem:node) as? Node else{return}
        let siblings=parent.children.filter { candidate in
            switch (node.value,candidate.value) {
            case (.collection,.collection),(.asset,.asset):return true
            default:return false
            }
        }
        guard siblings.count > 1,let source=siblings.firstIndex(where:{$0 === node}) else{return}
        var slot=source,moved=false
        func position(_ event:NSEvent)->Int {
            let y=tree.convert(event.locationInWindow,from:nil).y
            for (index,sibling) in siblings.enumerated(){
                let row=tree.row(forItem:sibling)
                if row >= 0 && y < tree.rect(ofRow:row).midY{return index}
            }
            return siblings.count
        }
        while let event=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if event.type == .leftMouseUp{break}
            moved=true;slot=position(event)
            let boundary:CGFloat
            if slot < siblings.count {let row=tree.row(forItem:siblings[slot]);boundary=row >= 0 ? tree.rect(ofRow:row).minY:0}
            else {let row=tree.row(forItem:siblings[siblings.count-1]);boundary=row >= 0 ? tree.rect(ofRow:row).maxY:0}
            tree.reorderLineY=boundary
            tree.view(atColumn:0,row:tree.row(forItem:node),makeIfNecessary:false)?.alphaValue=0.55
        }
        tree.reorderLineY=nil
        tree.view(atColumn:0,row:tree.row(forItem:node),makeIfNecessary:false)?.alphaValue=1
        guard moved,slot != source,slot != source+1,let controller else{return}
        let index=slot > source ? slot-1:slot
        do{
            switch node.value {
            case .collection:
                var ids=siblings.compactMap{item -> UUID? in if case .collection(let entry)=item.value{return entry.id};return nil}
                let id=ids.remove(at:source);ids.insert(id,at:index)
                try AssetCollections.reorderCollections(ids,in:controller.store)
            case .asset(_,let collectionID):
                var keys=siblings.compactMap{item -> String? in if case .asset(let asset,_)=item.value{return asset.key};return nil}
                let key=keys.remove(at:source);keys.insert(key,at:index)
                try AssetCollections.reorderItems(keys,in:collectionID,store:controller.store)
            case .root,.add:break
            }
            refresh();onChanged?()
        }catch{controller.flash(error.localizedDescription)}
    }
    func createCollection(onCreated:((UUID)->Void)? = nil){
        let modal=SwissFocusModal(title:"New Collection",message:"Keep any combination of assets in a Collection. An asset can belong to several.")
        let field=modal.field("Collection Name",value:"")
        let colour=modal.colourField("Collection Colour",value:Design.hex(AssetCollections.defaultColour))
        modal.button("Create",primary:true){[weak self,weak modal] in
            guard let self,let controller=self.controller else{return}
            do{let id = try AssetCollections.create(field.stringValue,colour:hexOf(colour.color) ?? AssetCollections.defaultColour,in:controller.store);modal?.dismissOverlay();self.refresh();self.onChanged?();onCreated?(id)}
            catch{controller.flash(error.localizedDescription)}
        }
        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()}
        modal.present(over:self)
    }
    private func editCollection(_ collection:AssetCollectionEntry){
        let modal=SwissFocusModal(title:"Edit Collection",message:"Change this Collection's name and row colour. Its assets stay linked.")
        let field=modal.field("Collection Name",value:collection.name)
        let colour=modal.colourField("Collection Colour",value:Design.hex(collection.colour ?? AssetCollections.defaultColour))
        modal.button("Save",primary:true){[weak self,weak modal] in
            guard let self,let controller=self.controller else{return}
            do{try AssetCollections.edit(collection.id,name:field.stringValue,colour:hexOf(colour.color) ?? AssetCollections.defaultColour,in:controller.store);modal?.dismissOverlay();self.refresh();self.onColourChanged?();self.onChanged?()}
            catch{controller.flash(error.localizedDescription)}
        }
        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()}
        modal.present(over:self)
    }
}
