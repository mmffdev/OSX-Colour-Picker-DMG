import AppKit
import UniformTypeIdentifiers

/// A content-sized Rail1 panel. Lists share the Library's branching outline and outer rail scroll.
final class ICCProfilePanel:NSView,NSOutlineViewDataSource,NSOutlineViewDelegate,NSSearchFieldDelegate,WorkspacePanelContentMetrics {
    private final class Node:NSObject {
        let key:String,title:String
        var profile:ICCProfileLibrary.Profile?,children:[Node]=[]
        init(_ key:String,_ title:String,profile:ICCProfileLibrary.Profile?=nil){self.key=key;self.title=title;self.profile=profile}
    }
    private let store=ICCProfileLibrary.shared
    private let search=NSSearchField()
    private let refreshButton=PaletteAssetIcon(frame:.zero)
    private let addFile=SwissButton("Add File…",.quiet),addFolder=SwissButton("Add Folder…",.quiet)
    private let use=SwissButton("Use As Target",.quiet),locateButton=SwissButton("Locate…",.quiet),remove=SwissButton("Remove Link",.quiet)
    private let tree=WorkspaceBranchTree()
    private let context=SwissContextMenu()
    private let details=NSTextField(wrappingLabelWithString:"")
    private let status=NSTextField(wrappingLabelWithString:"Loading System Profiles…")
    private var roots:[Node]=[],selected:Node?,observer:NSObjectProtocol?
    private var expanded:Set<String>=["yours","missing"]
    private var previousMissing=Set<String>()
    private var rebuilding=false,busy=false
    var onContentHeightChange:(()->Void)?
    var onTarget:((ICCProfileLibrary.Profile)->Void)?
    var onCollectionActions:((ICCProfileLibrary.Profile)->HaloAction)?
    override var isFlipped:Bool {true}
    private var treeHeight:CGFloat {CGFloat(tree.numberOfRows)*34}
    var minimumContentHeight:CGFloat {treeHeight+108+(selected == nil ? 0:212)}
    override init(frame:NSRect){
        super.init(frame:frame)
        search.appearance=NSAppearance(named:.aqua);search.textColor=Design.ink;search.backgroundColor=Design.card
        search.placeholderString="Search ICC Profiles";search.font=Design.Text.body.font();search.delegate=self;search.setAccessibilityLabel("Search ICC Profiles")
        for button in [addFile,addFolder,use,locateButton,remove]{addSubview(button);button.target=self}
        addFile.action=#selector(chooseFiles);addFolder.action=#selector(chooseFolder);use.action=#selector(useSelected);locateButton.action=#selector(locateSelected);remove.action=#selector(removeSelected)
        addSubview(search);addSubview(details);addSubview(status);addSubview(refreshButton)
        refreshButton.symbol="arrow.clockwise";refreshButton.setAccessibilityLabel("Refresh ICC Profiles");refreshButton.toolTip="Refresh ICC Profiles";refreshButton.run={ [weak self] in self?.refresh() }
        details.font=Design.Text.caption.font();details.textColor=Design.ink;details.maximumNumberOfLines=6
        status.font=Design.Text.caption.font();status.textColor=Design.quiet;status.maximumNumberOfLines=1
        let column=NSTableColumn(identifier:.init("ICCProfiles"));tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
        tree.swatchFamily = .yellow
        tree.leadingDisclosure=true;tree.depthOffset=2;tree.connectsFromParent=true
        tree.rowHeight=34;tree.intercellSpacing = .zero;tree.indentationPerLevel=0;tree.backgroundColor=Design.card;tree.style = .plain;tree.focusRingType = .none
        tree.delegate=self;tree.dataSource=self;tree.setAccessibilityLabel("ICC Profile Library")
        addSubview(tree);tree.installConnectors(in:self)
        tree.target=self;tree.doubleAction=#selector(openSelected)
        tree.onContext={ [weak self] item,point,view in
            guard let self,let profile=(item as? Node)?.profile else{return}
            let linked=self.store.profiles.contains{$0.id == profile.id},available=self.store.space(for:profile.key) != nil
            var actions=[HaloAction(id:"use",label:"Use As Colour Target",symbol:"scope",disabled:!profile.canTarget || !available,onSelect:{[weak self] in self?.onTarget?(profile)})]
            if linked && !available {actions.append(HaloAction(id:"locate",label:"Locate ICC Profile…",symbol:"folder",onSelect:{[weak self] in self?.locate(profile.id)}))}
            actions.append(HaloAction(id:"reveal",label:"Show In Finder",symbol:"arrow.up.right",disabled:!FileManager.default.fileExists(atPath:ICCProfileLibrary.resolvedURL(profile).path),onSelect:{NSWorkspace.shared.activateFileViewerSelecting([ICCProfileLibrary.resolvedURL(profile)])}))
            if linked{actions.append(HaloAction(id:"remove",label:"Remove Link",symbol:"minus",onSelect:{[weak self] in self?.store.remove(profile.id)}))}
            if let collection=self.onCollectionActions?(profile){actions.append(collection)}
            self.context.open(actions,at:point,in:view)
        }
        observer=NotificationCenter.default.addObserver(forName:ICCProfileLibrary.changed,object:nil,queue:.main){[weak self] _ in self?.reload()}
        if let saved=AppPreferences.shared.stringArray(forKey:"Workspace.ICC.Expanded"){expanded=Set(saved)}
        store.start();reload()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{if let observer{NotificationCenter.default.removeObserver(observer)}}
    func refresh(){store.refresh()}
    func controlTextDidChange(_ obj:Notification){reload()}
    private func reload(){
        let selectedKey=selected?.key,query=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let matches:(ICCProfileLibrary.Profile)->Bool={profile in query.isEmpty || [profile.name,profile.model,profile.path,profile.profileClass].contains{$0.localizedCaseInsensitiveContains(query)}}
        let system=Node("system","System Profiles"),yours=Node("yours","Your ICC Profiles"),missing=Node("missing","Missing Profiles")
        let groups=store.grouped(store.profiles)
        let missingKeys=Set(groups.missing.map(\.id));if !missingKeys.subtracting(previousMissing).isEmpty{expanded.insert("missing")};previousMissing=missingKeys
        missing.children=groups.missing.filter(matches).map{Node($0.id,$0.name,profile:$0)}
        system.children=store.system.filter(matches).map{Node("system:"+$0.path,$0.name,profile:$0)}
        for profile in groups.available.filter(matches) {
            var parent=yours
            if let folder=profile.folder {
                let base=URL(fileURLWithPath:folder),relative=URL(fileURLWithPath:profile.path).deletingLastPathComponent().path
                var parts=[base.lastPathComponent]
                if relative.hasPrefix(folder+"/"){parts += String(relative.dropFirst(folder.count+1)).split(separator:"/").map(String.init)}
                var key="folder:"+folder
                for (index,part) in parts.enumerated(){if index > 0{key+="/"+part};if let existing=parent.children.first(where:{$0.key == key}){parent=existing}else{let child=Node(key,part);parent.children.append(child);parent=child}}
            }
            parent.children.append(Node(profile.id,profile.name,profile:profile))
        }
        roots=(missing.children.isEmpty ? []:[missing])+[system,yours];rebuilding=true;tree.reloadData()
        func expand(_ nodes:[Node]){for node in nodes where node.profile == nil {if expanded.contains(node.key) || !query.isEmpty {tree.expandItem(node);expand(node.children)}}}
        expand(roots)
        selected=nil
        if let selectedKey,let row=(0..<tree.numberOfRows).first(where:{(tree.item(atRow:$0) as? Node)?.key == selectedKey}){tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);selected=tree.item(atRow:row) as? Node}
        rebuilding=false;tree.refreshSurfaces();updateDetails();refreshExtent()
    }
    private func updateDetails(){
        guard let node=selected,let profile=node.profile else {details.isHidden=true;[use,locateButton,remove].forEach{$0.isHidden=true};status.stringValue=busy ? "Reading ICC Profiles…":"\(store.system.count) System · \(store.profiles.count) Linked";return}
        details.isHidden=false
        let isLinked=store.profiles.contains{$0.id == profile.id},state=store.status(profile)
        let kind=["mntr":"Display","prtr":"Output","scnr":"Input","spac":"Colour Space","link":"Device Link","abst":"Abstract","nmcl":"Named Colour"][profile.profileClass] ?? profile.profileClass
        details.stringValue="\(profile.name)\n\(profile.model) · ICC \(profile.version) · \(kind)\n\(state)\n\(ICCProfileLibrary.resolvedURL(profile).path)\nCopyright: \(profile.copyright)"
        details.toolTip=details.stringValue
        use.isHidden=false;use.isEnabled=profile.canTarget && store.space(for:profile.key) != nil
        locateButton.isHidden = !isLinked || !store.needsLocate(profile);remove.isHidden = !isLinked
        status.stringValue=profile.canTarget ? "Linked Files Stay In Their Original Location":"This Profile Type Can Be Inspected Only"
    }
    override func draw(_ dirtyRect:NSRect){
        let depth=tree.numberOfRows > 0 ? tree.level(forRow:tree.numberOfRows-1)+tree.depthOffset:tree.depthOffset
        fill(bounds,depth > 0 ? Design.mix(Design.card,WorkspaceBranchTree.tint(depth-1,family:.yellow),0.045):Design.card)
        hairline(x:0,y:treeHeight,width:bounds.width)
    }
    override func layout(){
        super.layout();let w=max(0,bounds.width-32)
        tree.frame=NSRect(x:0,y:0,width:bounds.width,height:treeHeight);tree.tableColumns.first?.width=bounds.width;tree.layoutConnectors()
        let bottom=treeHeight
        search.frame=NSRect(x:16,y:bottom+12,width:max(0,w-36),height:28)
        refreshButton.ink=Design.ink;refreshButton.frame=NSRect(x:bounds.width-40,y:bottom+12,width:24,height:28)
        addFile.frame=NSRect(x:16,y:bottom+48,width:132,height:32);addFolder.frame=NSRect(x:164,y:bottom+48,width:max(0,w-148),height:32)
        let detailTop=bottom+96
        details.frame=NSRect(x:16,y:detailTop,width:w,height:124)
        use.frame=NSRect(x:16,y:detailTop+128,width:140,height:32);locateButton.frame=NSRect(x:164,y:detailTop+128,width:max(0,w-148),height:32)
        remove.frame=NSRect(x:16,y:detailTop+160,width:140,height:32)
        status.frame=NSRect(x:16,y:bottom+(selected == nil ? 88:300),width:w,height:20)
    }

    private func refreshExtent(){needsLayout=true;needsDisplay=true;onContentHeightChange?();var view=superview;while let current=view{if let panel=current as? WorkspacePanel{panel.rail?.arrange();break};view=current.superview}}
    @objc private func chooseFiles(){choose(folder:false)}
    @objc private func chooseFolder(){choose(folder:true)}
    private func choose(folder:Bool){
        guard let window,!busy else{return}
        let panel=NSOpenPanel();panel.title=folder ? "Link A Folder Of ICC Profiles":"Link ICC Profiles";panel.prompt="Link";panel.canChooseDirectories=folder;panel.canChooseFiles = !folder;panel.allowsMultipleSelection = !folder
        if !folder{panel.allowedContentTypes=[UTType(filenameExtension:"icc"),UTType(filenameExtension:"icm")].compactMap{$0}}
        panel.beginSheetModal(for:window){[weak self] response in
            guard let self,response == .OK else{return}
            do{try panel.urls.forEach{try FolderAccess.authorize($0)}}catch{NSApp.presentError(error);return}
            self.importURLs(panel.urls,folder:folder)
        }
    }
    private func importURLs(_ urls:[URL],folder:Bool){
        busy=true;addFile.isEnabled=false;addFolder.isEnabled=false;updateDetails()
        DispatchQueue.global(qos:.userInitiated).async {[weak self] in
            var profiles:[ICCProfileLibrary.Profile]=[],failed:[String]=[]
            for url in urls {
                do {let files=folder ? try ICCProfileLibrary.files(in:url):[url]
                    for file in files {do{profiles.append(try ICCProfileLibrary.read(file,folder:folder ? url.path:nil))}catch{failed.append(file.lastPathComponent+": "+error.localizedDescription)}}
                }catch{failed.append(url.lastPathComponent+": "+error.localizedDescription)}
            }
            DispatchQueue.main.async {
                guard let self else{return};self.busy=false;self.addFile.isEnabled=true;self.addFolder.isEnabled=true
                self.expanded.insert("yours");for profile in profiles {if let folder=profile.folder{self.expanded.insert("folder:"+folder)}}
                self.store.add(profiles);self.reload()
                if !failed.isEmpty {let alert=NSAlert();alert.messageText="Some Files Could Not Be Linked";alert.informativeText=failed.prefix(8).joined(separator:"\n");if let window=self.window{alert.beginSheetModal(for:window)}}
                else if profiles.isEmpty{self.status.stringValue="No ICC Profiles Found In This Folder"}
            }
        }
    }
    @objc private func openSelected(){guard let profile=selected?.profile else{return};if store.space(for:profile.key) != nil && profile.canTarget{onTarget?(profile)}else if store.profiles.contains(where:{$0.id == profile.id}){locate(profile.id)}}
    @objc private func useSelected(){if let profile=selected?.profile{onTarget?(profile)}}
    @objc private func locateSelected(){if let profile=selected?.profile{locate(profile.id)}}
    func locate(_ id:String){
        guard let profile=store.profiles.first(where:{$0.id == id}),let window else{return}
        let panel=NSOpenPanel();panel.title="Locate "+profile.name;panel.prompt="Relocate";panel.canChooseFiles=true;panel.canChooseDirectories=false;panel.allowedContentTypes=[UTType(filenameExtension:"icc"),UTType(filenameExtension:"icm")].compactMap{$0}
        panel.beginSheetModal(for:window){[weak self] response in guard response == .OK,let url=panel.url else{return};do{try self?.store.relocate(id,to:url)}catch{NSApp.presentError(error)}}
    }
    @objc private func removeSelected(){if let id=selected?.profile?.id{store.remove(id);selected=nil;reload()}}
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{(item as? Node)?.children.count ?? roots.count}
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{(item as? Node)?.children[index] ?? roots[index]}
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{!(item as! Node).children.isEmpty}
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView?{let row=WorkspaceBranchTree.Row();row.accordion=tree;return row}
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView?{
        let node=item as! Node,cell=WorkspaceBranchTree.Cell(frame:.zero)
        cell.compactMetadata=true;cell.leadingDisclosure=true
        cell.symbol=node.profile == nil ? "folder":"doc";cell.star.isHidden=true
        let missing=node.profile.map{store.needsLocate($0)} ?? false
        cell.warning=missing
        let label=NSTextField(labelWithString:node.title+(missing ? " · Missing":""));label.font=Design.Text.body.font();label.textColor=Design.ink;label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.profile.map{$0.name+"\n"+$0.path+"\n"+store.status($0)} ?? node.title
        cell.countLabel.stringValue=node.profile == nil ? String(count(node)):node.profile!.model;cell.countLabel.isHidden=false
        cell.setAccessibilityLabel(node.profile.map{$0.name+", "+$0.model+", "+store.status($0)} ?? node.title)
        return cell
    }
    private func count(_ node:Node)->Int{node.profile == nil ? node.children.reduce(0){$0+count($1)}:1}
    func outlineViewSelectionDidChange(_ notification:Notification){guard !rebuilding else{return};selected=tree.item(atRow:tree.selectedRow) as? Node;if selected?.profile == nil{selected=nil};updateDetails();refreshExtent()}
    func outlineViewItemDidExpand(_ notification:Notification){expandedChanged(notification,open:true)}
    func outlineViewItemDidCollapse(_ notification:Notification){expandedChanged(notification,open:false)}
    private func expandedChanged(_ notification:Notification,open:Bool){guard !rebuilding,let node=notification.userInfo?["NSObject"] as? Node else{return};if open{expanded.insert(node.key)}else{expanded.remove(node.key)};AppPreferences.shared.set(expanded.sorted(),forKey:"Workspace.ICC.Expanded");tree.refreshSurfaces();refreshExtent()}
}
