import AppKit
import WebKit
import UniformTypeIdentifiers

/// Structure is semantic; client/work-item names never identify asset ownership.
struct SimpleCatalogueStructure: Codable, Equatable {
    var family = "client-work-assets"
    var version = 1
    var singular = "Project"
    var plural = "Projects"
    var personalMode:Bool?
    var personalCollectionID:UUID?
    var clientLabel:String?
    var formPresets:[WorkFormPreset]?
    var customAssetFamilies:[String]?
    var customAssetTypes:[SimpleCustomAssetType]?
    var clientName:String {clientLabel ?? "Client"}
    var assetTypes = SimpleAssetType.defaultAssetIDs
    func validate() throws {
        guard family == "client-work-assets", version == 1 else { throw failure("This catalogue uses a structure this version cannot open.") }
        try SimpleCatalogue.validateLabel(clientName);try SimpleCatalogue.validateLabel(singular); try SimpleCatalogue.validateLabel(plural)
        let families=customAssetFamilies ?? []
        let customs=customAssetTypes ?? []
        for family in families {try SimpleCatalogue.validateLabel(family)}
        guard Set(families.map{$0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)}).count == families.count else {throw failure("Custom asset families need distinct names.")}
        let knownFamilies=Set(SimpleAssetType.all.map(\.family))
        guard families.allSatisfy({!knownFamilies.contains($0)}) else {throw failure("A custom asset family already exists.")}
        for type in customs {
            try SimpleCatalogue.validateLabel(type.title)
            guard ![".","..","my_library.collib","assets.colcat"].contains(type.title.lowercased()) else {throw failure("That asset type name is reserved for the library.")}
            guard type.id.hasPrefix("custom-"),type.family.count > 0,knownFamilies.contains(type.family) || families.contains(type.family) else {throw failure("A custom asset type has an invalid family or ID.")}
        }
        let names=SimpleAssetType.all.map(\.title)+customs.map(\.title)
        guard Set(names.map{$0.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:.current)}).count == names.count,Set(customs.map(\.id)).count == customs.count else {throw failure("Asset type names must be distinct.")}
        guard Set(assetTypes).count == assetTypes.count,assetTypes.allSatisfy({SimpleAssetType.find($0,in:self) != nil}) else {throw failure("This catalogue contains unsupported or duplicate asset categories.")}
    }
}
struct SimpleCustomAssetType:Codable,Equatable {
    var id:String
    var title:String
    var family:String
}
struct SimpleAssetType {
    let id:String, title:String, symbol:String
    let role:SchemaRole?
    let family:String
    /// New setup and import categories; other registered IDs keep existing catalogues readable.
    /// Historical IDs remain in `all` so existing catalogues still decode and display their assets.
    static let defaultAssetIDs=["palettes","typography","images","photography"]
    static let defaultLibraryIDs=["information"]+defaultAssetIDs
    static let setupImportIDs=["palettes","typography","images","photography","documents","ase","luts","icc","css"]
    static var setupImportTypes:[SimpleAssetType] {setupImportIDs.compactMap(find)}
    var selectable:Bool {Self.setupImportIDs.contains(id)}
    var setupTitle:String {id == "typography" ? "Typography Packs":title}
    var setupFamily:String {selectable ? "Import":family}
    static let all:[SimpleAssetType] = [
        .init(id:"information",title:"Information",symbol:"info.circle",role:nil,family:"Documents & Rights"),
        .init(id:"palettes",title:"Palettes",symbol:"swatchpalette",role:.palettes,family:"Colour & Measurement"),
        .init(id:"icc",title:"ICC Profiles",symbol:"slider.horizontal.3",role:nil,family:"Colour & Measurement"),
        .init(id:"device-link-profiles",title:"Device Link Profiles",symbol:"slider.horizontal.3",role:nil,family:"Colour & Measurement"),
        .init(id:"spectral-data",title:"Spectral Data",symbol:"waveform",role:nil,family:"Colour & Measurement"),
        .init(id:"test-charts-targets",title:"Test Charts & Targets",symbol:"square.grid.2x2",role:nil,family:"Colour & Measurement"),
        .init(id:"characterisation-data",title:"Characterisation Data Sets",symbol:"doc",role:nil,family:"Colour & Measurement"),
        .init(id:"measurements",title:"Colour Measurements",symbol:"ruler",role:nil,family:"Colour & Measurement"),
        .init(id:"tolerance-sets",title:"Tolerance Sets",symbol:"ruler",role:nil,family:"Colour & Measurement"),
        .init(id:"proof-reports",title:"Proof Verification Reports",symbol:"doc",role:nil,family:"Colour & Measurement"),
        .init(id:"display-calibration",title:"Display Calibration Records",symbol:"display",role:nil,family:"Colour & Measurement"),
        .init(id:"instrument-certificates",title:"Instrument Certificates",symbol:"doc",role:nil,family:"Colour & Measurement"),
        .init(id:"swatches",title:"Swatches",symbol:"square.grid.2x2",role:nil,family:"Colour & Measurement"),
        .init(id:"print-ready-pdfs",title:"Print-ready PDFs",symbol:"doc",role:nil,family:"Print Production"),
        .init(id:"paper-specs",title:"Substrate & Paper Specs",symbol:"doc",role:nil,family:"Print Production"),
        .init(id:"ink-sets",title:"Ink Sets & Recipes",symbol:"drop",role:nil,family:"Print Production"),
        .init(id:"dielines",title:"Dielines & Cutter Guides",symbol:"doc",role:nil,family:"Print Production"),
        .init(id:"job-tickets",title:"Job Tickets",symbol:"doc",role:nil,family:"Print Production"),
        .init(id:"press-scans",title:"Press Sheet Scans & Proofs",symbol:"photo",role:nil,family:"Print Production"),
        .init(id:"luts",title:"LUTs",symbol:"square.stack.3d.up",role:nil,family:"Screen, Video & Film"),
        .init(id:"video",title:"Video",symbol:"video",role:nil,family:"Screen, Video & Film"),
        .init(id:"audio",title:"Audio Clips",symbol:"waveform",role:nil,family:"Screen, Video & Film"),
        .init(id:"asc-cdl",title:"ASC CDL",symbol:"doc",role:nil,family:"Screen, Video & Film"),
        .init(id:"look-grade-files",title:"Look & Grade Files",symbol:"doc",role:nil,family:"Screen, Video & Film"),
        .init(id:"ocio-aces",title:"OCIO & ACES Configs",symbol:"doc",role:nil,family:"Screen, Video & Film"),
        .init(id:"camera-profiles",title:"Camera Profiles & IDTs",symbol:"camera",role:nil,family:"Screen, Video & Film"),
        .init(id:"reference-stills",title:"Reference Stills & Frame Grabs",symbol:"photo",role:nil,family:"Screen, Video & Film"),
        .init(id:"onset-captures",title:"On-set Chart Captures",symbol:"camera",role:nil,family:"Screen, Video & Film"),
        .init(id:"motion-graphics",title:"Motion Graphics",symbol:"video",role:nil,family:"Screen, Video & Film"),
        .init(id:"materials-shaders",title:"Materials & Shaders",symbol:"cube",role:nil,family:"3D & Materials"),
        .init(id:"textures-pbr",title:"Textures & PBR Maps",symbol:"square.stack.3d.up",role:nil,family:"3D & Materials"),
        .init(id:"hdris",title:"HDRIs & Environment Maps",symbol:"photo",role:nil,family:"3D & Materials"),
        .init(id:"models-3d",title:"3D Models",symbol:"cube",role:nil,family:"3D & Materials"),
        .init(id:"multilayer-exr",title:"Multi-layer EXR Render Passes",symbol:"square.stack.3d.up",role:nil,family:"3D & Materials"),
        .init(id:"typography",title:"Typography",symbol:"textformat",role:.typography,family:"Brand & Design"),
        .init(id:"photography",title:"Photographs",symbol:"camera",role:nil,family:"Brand & Design"),
        .init(id:"images",title:"Images",symbol:"photo",role:nil,family:"Brand & Design"),
        .init(id:"vector-artwork",title:"Vector Artwork & Logos",symbol:"pencil",role:nil,family:"Brand & Design"),
        .init(id:"design-sources",title:"Design Source Files",symbol:"doc",role:nil,family:"Brand & Design"),
        .init(id:"design-tokens",title:"Design Tokens & Code Colour Assets",symbol:"curlybraces",role:nil,family:"Brand & Design"),
        .init(id:"css",title:"CSS",symbol:"curlybraces",role:nil,family:"Brand & Design"),
        .init(id:"gradients-patterns",title:"Gradients & Patterns",symbol:"paintpalette",role:nil,family:"Brand & Design"),
        .init(id:"icon-sets",title:"Icon Sets",symbol:"square.grid.2x2",role:nil,family:"Brand & Design"),
        .init(id:"mockups-moodboards",title:"Mockups & Moodboards",symbol:"photo",role:nil,family:"Brand & Design"),
        .init(id:"screenshots",title:"Screenshots",symbol:"photo",role:nil,family:"Brand & Design"),
        .init(id:"brand-guidelines",title:"Brand Guidelines",symbol:"doc",role:nil,family:"Brand & Design"),
        .init(id:"physical-swatches",title:"Physical Swatch Records",symbol:"square.grid.2x2",role:nil,family:"Physical Samples"),
        .init(id:"documents",title:"Documents",symbol:"doc",role:nil,family:"Documents & Rights"),
        .init(id:"licences",title:"Licences",symbol:"doc",role:nil,family:"Documents & Rights"),
        .init(id:"approvals",title:"Approvals & Sign-offs",symbol:"checkmark",role:nil,family:"Documents & Rights"),
        .init(id:"specs-briefs",title:"Spec Sheets & Briefs",symbol:"doc",role:nil,family:"Documents & Rights"),
        .init(id:"orders-correspondence",title:"Purchase Orders & Correspondence",symbol:"doc",role:nil,family:"Documents & Rights"),
        .init(id:"links-bookmarks",title:"Links & Bookmarks",symbol:"link",role:nil,family:"Documents & Rights"),
        .init(id:"app-presets",title:"Application Presets",symbol:"gearshape",role:nil,family:"Automation & Settings"),
        .init(id:"archives-packages",title:"Archives & Packages",symbol:"archivebox",role:nil,family:"Automation & Settings"),
        .init(id:"catalogues",title:"Catalogues & Collections",symbol:"folder",role:nil,family:"Automation & Settings"),
        .init(id:"ase",title:"ASE",symbol:"doc",role:nil,family:"Palette Formats"),
        .init(id:"colour-presets",title:"Colour Presets",symbol:"slider.horizontal.3",role:nil,family:"Palette Formats")]
    static func find(_ id:String)->SimpleAssetType? {all.first{$0.id == id}}
    static func find(_ id:String,in config:SimpleCatalogueStructure)->SimpleAssetType? {
        find(id) ?? config.customAssetTypes?.first(where:{$0.id == id}).map{SimpleAssetType(id:$0.id,title:$0.title,symbol:"folder",role:nil,family:$0.family)}
    }
    static func types(in config:SimpleCatalogueStructure)->[SimpleAssetType] {
        all+(config.customAssetTypes ?? []).map{SimpleAssetType(id:$0.id,title:$0.title,symbol:"folder",role:nil,family:$0.family)}
    }
    /// Display only registered asset buckets; keep the original schema for persistence.
    static func visibleStack(_ root:SchemaNode,types:[SimpleAssetType])->SchemaNode {
        var visible=root
        if root.kind == "Simple Assets" {
            visible.children=visible.children.filter { node in
                types.contains { type in
                    SchemaTrial.type(of:node) == SchemaTrial.type(of:type.node)
                }
            }
        }
        visible.children=visible.children.map{visibleStack($0,types:types)}
        return visible
    }
    static func workspaceCustomTypes(home:URL)->[SimpleCustomAssetType] {
        guard let values=(try? AppDataStore(root:home).read()["customAssetTypes"]) as? [[String:String]] else{return []}
        return values.compactMap{value in guard let id=value["id"],let title=value["title"],let family=value["family"] else{return nil};return SimpleCustomAssetType(id:id,title:title,family:family)}
    }
    static func workspaceCustomFamilies(home:URL)->[String] {
        ((try? AppDataStore(root:home).read()["customAssetFamilies"]) as? [String]) ?? []
    }
    static func workspaceTypes(home:URL)->[SimpleAssetType] {
        all+workspaceCustomTypes(home:home).map{SimpleAssetType(id:$0.id,title:$0.title,symbol:"folder",role:nil,family:$0.family)}
    }
    static func includingWorkspace(_ config:SimpleCatalogueStructure,home:URL)->SimpleCatalogueStructure {
        var result=config
        var families=result.customAssetFamilies ?? []
        for family in workspaceCustomFamilies(home:home) where !families.contains(family) {families.append(family)}
        var types=result.customAssetTypes ?? []
        for type in workspaceCustomTypes(home:home) where !types.contains(where:{$0.id == type.id}) {types.append(type)}
        result.customAssetFamilies=families;result.customAssetTypes=types
        return result
    }
    var node:SchemaNode {SchemaNode(name:title,role:role,kind:id == "photography" ? "Photography":title)}
}
struct SimpleSetupClient:Codable,Equatable {
    var clientName:String
    var projectName:String
    var clientWord:String
    var workWord:String
    var assetTypes:[String]
}
enum SimpleCatalogue {
    static func settingPersonal(_ enabled:Bool,in source:SchemaTrial.SchemaFile)throws -> SchemaTrial.SchemaFile {
        var file=source;guard var config=file.structure else{throw failure("This catalogue needs the simplified structure first.")}
        if enabled,config.personalCollectionID.flatMap({id in file.collections.first{$0.id == id}}) == nil {
            let holder=client(uniqueName("Personal",among:file.collections.map(\.name)),config:config)
            config.personalCollectionID=holder.id;file.collections.append(holder)
        }
        config.personalMode=enabled;file.structure=config;try validate(file);return file
    }
    static func validateLabel(_ value:String)throws {
        guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,value.count <= 80,!value.contains("/"),!value.contains("\\"),!value.contains("\n") else {throw failure("Use a name of 1–80 characters without path separators.")}
    }
    static func stack(_ config:SimpleCatalogueStructure,existing:SchemaNode?=nil)->SchemaNode {
        var root=existing ?? SchemaNode(name:config.singular)
        root.name=config.singular
        let information=root.children.first{SchemaTrial.role(of:$0) == .information} ?? SchemaNode(name:"Information",role:.information)
        let tags=root.children.first{SchemaTrial.role(of:$0) == .tags} ?? SchemaNode(name:"Tags",role:.tags)
        // Reuse the original bucket identities. Only the organisational container is new.
        var assets=root.children.first{$0.kind == "Simple Assets" || $0.name == "Assets" && $0.role == nil} ?? SchemaNode(name:"Assets",kind:"Simple Assets")
        var held=(root.children.filter{$0.id != information.id && $0.id != tags.id && $0.id != assets.id})+assets.children
        for i in held.indices where held[i].name == "Photography" {held[i].kind="Photography"}
        for type in config.assetTypes.compactMap({SimpleAssetType.find($0,in:config)}) where !held.contains(where:{SchemaTrial.role(of:$0) == type.role && type.role != nil || SchemaTrial.type(of:$0) == (type.id == "photography" ? "Photography":type.title)}) {held.append(type.node)}
        assets.kind="Simple Assets"
        assets.children=held
        root.children=[information,assets,tags]
        return root
    }
    static func client(_ name:String,config:SimpleCatalogueStructure)->SchemaCollection {
        var value=SchemaCollection(name:name,stack:stack(config));value.workItemPlural=config.plural;return value
    }
    /// A conservative conversion. Deep ownership levels need a reviewed mapping, not a guessed flatten.
    static func converted(_ source:SchemaTrial.SchemaFile)->SchemaTrial.SchemaFile {
        var next=source
        let config=source.structure ?? SimpleCatalogueStructure()
        next.structure=config
        next.collections=source.collections.map { c in
            var value=c
            value.workItemPlural=c.workItemPlural ?? (c.stack.name == "Product" ? "Products":c.stack.name == "Work Order" ? "Work Orders":"Projects")
            if ["Projects","Products","Work Orders"].contains(value.name),value.folders.isEmpty {value.name="Internal"}
            var own=config;own.singular=c.stack.name;own.plural=value.workItemPlural ?? config.plural
            value.stack=stack(own,existing:c.stack)
            return value
        }
        if let stacks=source.stacks {next.stacks=stacks.mapValues{tree in var own=config;own.singular=tree.name;return stack(own,existing:tree)}}
        return next
    }
    static func validate(_ schema:SchemaTrial.SchemaFile)throws {
        guard let config=schema.structure else {throw failure("This is a legacy flexible schema. Convert it with a reviewed backup before importing it into the simplified system.")}
        try config.validate()
        for client in schema.collections {
            guard client.folders.isEmpty else {throw failure("This catalogue has extra ownership levels. They need explicit mapping before conversion.")}
            try validateLabel(client.name);try validateLabel(client.stack.name);try validateLabel(client.workItemPlural ?? config.plural)
        }
        let clients=Set(schema.collections.map(\.id))
        guard schema.places.values.allSatisfy({clients.contains($0.collection) && $0.folder == nil}) else {throw failure("A work item has an unresolved client destination.")}
    }
    @discardableResult static func migrate(root:URL,home:URL)throws -> URL? {
        let loaded=try CatalogueTree.read(root:root)
        if loaded.schema.structure != nil {try validate(loaded.schema);return nil}
        guard loaded.schema.collections.allSatisfy({$0.folders.isEmpty}),loaded.schema.places.values.allSatisfy({$0.folder == nil}) else {throw failure("Nested clients or streams require a reviewed ownership mapping. The original catalogue has not been changed.")}
        let manager=Handler_File_Manager.shared
        let backup=home.appendingPathComponent("Backups/Simple Structure/"+root.lastPathComponent+"-"+UUID().uuidString)
        let before=try manager.copySnapshot(root)
        try manager.copyVerified(root,to:backup)
        guard try manager.copySnapshot(root) == before else {throw failure("The catalogue changed during backup. Retry when other edits finish.")}
        let schema=converted(loaded.schema);try validate(schema)
        let store=LibraryStore(directory:root,legacyURL:nil,name:loaded.catalogue.name,assetsHome:home)
        let library=try store.load()
        try store.save(library,schema:schema)
        let after=try CatalogueTree.read(root:root)
        guard Set(after.library.projects.map(\.id)) == Set(loaded.library.projects.map(\.id)),Set(after.library.swatches.map(\.id)) == Set(loaded.library.swatches.map(\.id)) else {throw failure("Migration verification failed. Recovery copy: \(backup.path)")}
        return backup
    }
    struct Created {let home:URL;let name:String;let id:UUID}
    static func create(home:URL,parent:URL,name:String,config suppliedConfig:SimpleCatalogueStructure,clients:[SimpleSetupClient]=[])throws -> Created {
        let config=FileManager.default.fileExists(atPath:AppDataStore(root:home).url.path) ? SimpleAssetType.includingWorkspace(suppliedConfig,home:home) : suppliedConfig
        try validateLabel(name);try config.validate()
        var names=Set<String>()
        for client in clients {
            if config.personalMode != true {
                try validateLabel(client.clientName)
                guard names.insert(client.clientName.lowercased()).inserted else {throw failure("Each client needs a distinct name.")}
            }
            try validateLabel(client.projectName);try validateLabel(client.clientWord);try validateLabel(client.workWord)
            guard Set(client.assetTypes).count == client.assetTypes.count,client.assetTypes.allSatisfy({SimpleAssetType.find($0,in:config) != nil}) else {throw failure("A client has unsupported or duplicate asset categories.")}
        }
        var allTypes=config.assetTypes
        for type in clients.flatMap(\.assetTypes) where !allTypes.contains(type) {allTypes.append(type)}
        var defaults=config;defaults.assetTypes=allTypes
        let fm=FileManager.default,manager=Handler_File_Manager.shared
        let index=AppDataStore(root:home).url,existing=fm.fileExists(atPath:index.path)
        if !existing,fm.fileExists(atPath:home.path),!(try fm.contentsOfDirectory(atPath:home.path)).isEmpty {throw failure("Choose an empty app-data folder, or open the existing workspace instead.")}
        let destination=parent.appendingPathComponent(name)
        guard !fm.fileExists(atPath:destination.path) else {throw CatalogueError.nameTaken(name)}
        let cats=Catalogues(root:home,legacyURL:nil)
        guard !existing || !cats.names().contains(where:{$0.caseInsensitiveCompare(name) == .orderedSame}) else {throw CatalogueError.nameTaken(name)}
        // The transaction's journal/lock lives in this directory. No manifest or catalogue
        // is created until its final-review operation starts.
        try manager.createDirectory(home)
        return try manager.withTransaction(home:home) {
            try AppHomeSeed.ensure(at:home)
            let libraryTypes=existing ? GlobalAssets(home:home).assetTypes : ["information"]
            let combined=libraryTypes+allTypes.filter{!libraryTypes.contains($0)}
            try GlobalAssets(home:home).setAssetTypes(combined,custom:config.customAssetTypes ?? [])
            var schema=SchemaTrial.SchemaFile(collections:[],places:[:],structure:defaults)
            if config.personalMode == true {schema=try settingPersonal(true,in:schema)}
            var library=Library()
            for seed in clients {
                var own=defaults
                own.singular=seed.workWord
                own.plural=["Project":"Projects","Product":"Products","Campaign":"Campaigns","Work Order":"Work Orders"][seed.workWord] ?? seed.workWord
                own.assetTypes=seed.assetTypes
                let owner:UUID
                if config.personalMode == true {
                    guard let id=schema.structure?.personalCollectionID else {throw failure("The personal collection could not be created.")}
                    owner=id
                } else {
                    let made=client(seed.clientName,config:own)
                    owner=made.id;schema.collections.append(made)
                }
                let id=library.createProject(named:seed.projectName)
                _ = library.renameProject(id,to:seed.projectName)
                schema.places[id.uuidString]=SchemaPlace(collection:owner)
            }
            try validate(schema)
            let store=LibraryStore(directory:destination,legacyURL:nil,name:name,assetsHome:home)
            try store.save(library,schema:schema)
            try HistoryStore.save(StepHistory(),beside:store.url)
            // Empty categories are real destinations, even before their content adapter is available.
            for type in combined.compactMap({SimpleAssetType.find($0,in:config)}) {try manager.createDirectory(GlobalAssets(home:home).root.appendingPathComponent(type.title))}
            try cats.registerChecked(name,at:destination)
            let cat=try CatalogueTree.read(root:destination).catalogue
            try AppDataStore(root:home).update {manifest in
                manifest["customAssetFamilies"]=config.customAssetFamilies ?? []
                manifest["customAssetTypes"]=(config.customAssetTypes ?? []).map{["id":$0.id,"title":$0.title,"family":$0.family]}
                manifest["defaultCatalogue"]=["name":name,"id":cat.id.uuidString]
                var settings=manifest["settings"] as? [String:Any] ?? [:]
                settings[Catalogues.currentKey]=name;settings["currentCatalogueID"]=cat.id.uuidString;settings["assistantDone"]=true;settings["setupDone"]=true
                manifest["settings"]=settings
            }
            return Created(home:home,name:name,id:cat.id)
        }
    }
}

/// The approved wizard document is embedded in the app. Filesystem operations stay in native handlers.
final class SimpleSetupController:NSWindowController,WKNavigationDelegate,NSWindowDelegate {
    struct Draft:Codable {var home:URL;var parent:URL;var name="Master Catalogue";var config=SimpleCatalogueStructure();var step=0;var assetSelectionsInitialized:Bool?;var clients:[SimpleSetupClient]?;var activeClientIndex:Int?}
    static let draftKey="simpleSetupDraftV2"
    static let requestKey="startSimpleSetupOnNextLaunch"
    private var draft:Draft
    private let fixedHome:Bool
    private let onDone:(SimpleCatalogue.Created)->Void
    private let onCancel:()->Void
    private let onOpenExisting:(URL)->Void
    private let web:WKWebView
    private let bridge=SimpleSetupMessageBridge()
    private var finished=false
    private var creating=false
    private var appearanceIndex=AppearancePresets.selectedIndex
    init(home:URL?=nil,name:String="",done:@escaping(SimpleCatalogue.Created)->Void,cancel:@escaping()->Void,openExisting:@escaping(URL)->Void){
        fixedHome=home != nil;onDone=done;onCancel=cancel;onOpenExisting=openExisting
        let initial=home ?? Catalogues.realHome.appendingPathComponent("Desktop/Colorgain Workspace")
        draft=SetupDraft.load(Draft.self,key:Self.draftKey) ?? Draft(home:initial,parent:initial.appendingPathComponent("Catalogues"))
        if let home {draft.home=home;draft.parent=home.appendingPathComponent("Catalogues");draft.name=name.isEmpty ? "New Catalogue":name;draft.step=2}
        if FileManager.default.fileExists(atPath:AppDataStore(root:draft.home).url.path) {
            draft.config=SimpleAssetType.includingWorkspace(draft.config,home:draft.home)
        }
        let setupIDs=Set(SimpleAssetType.setupImportIDs)
        draft.config.assetTypes.removeAll{!setupIDs.contains($0)}
        draft.clients=draft.clients?.map{client in
            var result=client;result.assetTypes.removeAll{!setupIDs.contains($0)};return result
        }
        draft.step=min(7,max(0,draft.step))
        if draft.assetSelectionsInitialized != true {
            draft.assetSelectionsInitialized=true
            SetupDraft.save(draft,key:Self.draftKey)
        }
        let configuration=WKWebViewConfiguration()
        configuration.userContentController.add(bridge,name:"setup")
        web=WKWebView(frame:.zero,configuration:configuration)
        let available=NSScreen.main?.visibleFrame.size ?? NSSize(width:1440,height:900)
        let width=min(1440,available.width-64, (available.height-64)*1440/875)
        let window=SetupWindow(contentRect:NSRect(x:0,y:0,width:width,height:width*875/1440),styleMask:[.borderless,.resizable],backing:.buffered,defer:false)
        window.title="Set Up Colorgain"
        window.isReleasedWhenClosed=false;window.installSquareContent(web);window.contentAspectRatio=NSSize(width:1440,height:875)
        window.minSize=NSSize(width:960,height:960*875/1440);window.center()
        super.init(window:window)
        window.appearance=NSAppearance(named:.aqua);window.delegate=self
        bridge.owner=self;web.navigationDelegate=self
        web.loadHTMLString(SetupAppearanceHTML.document,baseURL:nil)
    }
    required init?(coder:NSCoder){fatalError()}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){restore();web.evaluateJavaScript("window.setSetupAppearance(\(SetupAppearanceHTML.payload(index:appearanceIndex)))",completionHandler:nil)}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow:.cancel)
    }
    private func restore(){
        let known=SimpleAssetType.types(in:draft.config)
        let branches=(draft.clients ?? []).map { seed -> [String:Any] in
            ["clientName":seed.clientName,"projectName":seed.projectName,"clientSingular":seed.clientWord,"singular":seed.workWord,"assets":seed.assetTypes.compactMap{id in known.first{$0.id == id && $0.selectable}?.setupTitle}]
        }
        let values:[String:Any] = ["page":draft.step,"folder":draft.home.path,"name":draft.name,"singular":draft.config.singular,"plural":draft.config.plural,"clientSingular":draft.config.clientName,"personalMode":draft.config.personalMode == true,"assets":draft.config.assetTypes.compactMap{id in known.first{$0.id == id && $0.selectable}?.setupTitle},"customAssetFamilies":draft.config.customAssetFamilies ?? [],"customAssetTypes":(draft.config.customAssetTypes ?? []).map{["id":$0.id,"title":$0.title,"family":$0.family]},"clients":branches,"activeClientIndex":draft.activeClientIndex ?? 0,"fixedHome":fixedHome]
        guard let bytes=try? JSONSerialization.data(withJSONObject:values),let json=String(data:bytes,encoding:.utf8) else{return}
        web.evaluateJavaScript("window.restoreSetup(\(json))",completionHandler:nil)
    }
    private func capture(_ values:[String:Any])throws {
        if let families=values["customAssetFamilies"] as? [String] {draft.config.customAssetFamilies=families}
        if let types=values["customAssetTypes"] as? [[String:String]] {
            draft.config.customAssetTypes=types.compactMap{value in guard let id=value["id"],let title=value["title"],let family=value["family"] else{return nil};return SimpleCustomAssetType(id:id,title:title,family:family)}
            guard draft.config.customAssetTypes?.count == types.count else{throw failure("A custom asset type is incomplete.")}
        }
        let known=SimpleAssetType.types(in:draft.config)
        if let value=values["name"] as? String {draft.name=value.trimmingCharacters(in:.whitespacesAndNewlines)}
        if let value=values["singular"] as? String {draft.config.singular=value.trimmingCharacters(in:.whitespacesAndNewlines);draft.config.plural=["Project":"Projects","Product":"Products","Campaign":"Campaigns","Work Order":"Work Orders"][draft.config.singular] ?? draft.config.singular}
        if let value=values["clientSingular"] as? String {draft.config.clientLabel=value.trimmingCharacters(in:.whitespacesAndNewlines)}
        if let value=values["personalMode"] as? Bool {draft.config.personalMode=value}
        if let values=values["assets"] as? [String] {
            let found=values.compactMap{label in known.first{$0.selectable && ($0.setupTitle == label || $0.title == label)}?.id}
            guard found.count == values.count else{throw failure("An unknown asset category was selected.")}
            draft.config.assetTypes=found
        }
        if let branches=values["clients"] as? [[String:Any]] {
            draft.clients=try branches.map { branch in
                let labels=branch["assets"] as? [String] ?? []
                let types=labels.compactMap{label in known.first{$0.selectable && ($0.setupTitle == label || $0.title == label)}?.id}
                guard types.count == labels.count else {throw failure("An unknown asset category was selected.")}
                return SimpleSetupClient(clientName:branch["clientName"] as? String ?? "",projectName:branch["projectName"] as? String ?? "",clientWord:branch["clientSingular"] as? String ?? "Client",workWord:branch["singular"] as? String ?? "Project",assetTypes:types)
            }
        }
        if let index=values["activeClientIndex"] as? Int {draft.activeClientIndex=index}
        if let page=values["page"] as? Int {draft.step=min(7,max(fixedHome ? 2:0,page));if draft.config.personalMode == true && draft.step == 3 {draft.step=4}}
        SetupDraft.save(draft,key:Self.draftKey)
    }
    fileprivate func receive(_ message:WKScriptMessage){
        guard message.frameInfo.isMainFrame,!finished,!creating,let body=message.body as? [String:Any],let action=body["action"] as? String else{return}
        do {
            if let values=body["draft"] as? [String:Any] {try capture(values)}
            switch action {
            case "cycleAppearance":appearanceIndex=AppearancePresets.next(after:appearanceIndex);web.evaluateJavaScript("window.setSetupAppearance(\(SetupAppearanceHTML.payload(index:appearanceIndex)))",completionHandler:nil)
            case "chooseFolder":chooseFolder()
            case "openWorkspace":openWorkspace()
            case "create":try create()
            case "close":cancelled()
            default:break
            }
        }catch{showError(error)}
    }
    private func create()throws {
        // Personal catalogues keep an internal owner, even though setup does not ask for a client label.
        if draft.config.personalMode == true && draft.config.clientName.isEmpty {draft.config.clientLabel="Client"}
        try SimpleCatalogue.validateLabel(draft.name);try draft.config.validate()
        creating=true
        web.evaluateJavaScript("window.setupBusy(true)",completionHandler:nil)
        // Let the progress state draw before the transactional filesystem operation.
        DispatchQueue.main.async { [weak self] in
            guard let self else{return}
            do {
                let result=try SimpleCatalogue.create(home:self.draft.home,parent:self.draft.parent,name:self.draft.name,config:self.draft.config,clients:self.draft.clients ?? [])
                SetupDraft.clear(key:Self.draftKey);preferences.removeObject(forKey:Self.requestKey)
                try AppDataStore(root:result.home).update { manifest in
                    var settings=manifest["settings"] as? [String:Any] ?? [:]
                    settings["theme.preset"]=AppearancePresets.all[self.appearanceIndex].id;manifest["settings"]=settings
                }
                self.finished=true;self.close();self.onDone(result)
            }catch{self.creating=false;self.web.evaluateJavaScript("window.setupBusy(false)",completionHandler:nil);self.showError(error)}
        }
    }
    private func showError(_ error:Error){if let window{NSAlert(error:error).beginSheetModal(for:window)}}
    private func chooseFolder(){
        guard !fixedHome,let window else{return}
        let panel=NSOpenPanel();panel.title="Choose Workspace Folder";panel.prompt="Use Folder";panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.directoryURL=draft.home
        panel.beginSheetModal(for:window){[weak self] result in
            guard let self,result == .OK,let url=panel.url else{return}
            do{try FolderAccess.authorize(url);self.draft.home=url;self.draft.parent=url.appendingPathComponent("Catalogues");if FileManager.default.fileExists(atPath:AppDataStore(root:url).url.path){self.draft.config=SimpleAssetType.includingWorkspace(self.draft.config,home:url)};SetupDraft.save(self.draft,key:Self.draftKey);self.restore()}catch{self.showError(error)}
        }
    }
    private func openWorkspace(){
        guard let window else{return}
        let panel=NSOpenPanel();panel.title="Open Workspace";panel.prompt="Open Workspace";panel.message="Choose the workspace folder containing colorgain.coldata.";panel.canChooseFiles=false;panel.canChooseDirectories=true
        panel.beginSheetModal(for:window){[weak self] result in
            guard let self,result == .OK,let folder=panel.url else{return}
            do {
                try FolderAccess.authorize(folder)
                _ = try AppDataStore(root:folder).read()
                preferences.removeObject(forKey:Self.requestKey);self.finished=true;self.close();self.onOpenExisting(folder)
            }catch{self.showError(error)}
        }
    }
    func windowWillClose(_ notification:Notification){if !finished{finished=true;onCancel()}}
    private func cancelled(){guard !finished else{return};finished=true;close();onCancel()}
}
private final class SimpleSetupMessageBridge:NSObject,WKScriptMessageHandler {
    weak var owner:SimpleSetupController?
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){owner?.receive(message)}
}

/// Native Settings is the only editor for the simplified catalogue's ownership structure.
final class SimpleCatalogueSettingsPanel:SettingsPanel {
    override func loadView(){view=CatalogueJourneyView(library:library,mode:"directory")}
    override func refresh(){(viewIfLoaded as? CatalogueJourneyView)?.refresh()}
}

/// Both catalogue entry points use this review/commit path. Originals are never modified.
enum SimpleCatalogueImport {
    struct Source {let root:URL;let temporary:Bool;let catalogue:CatalogueFile;let schema:SchemaTrial.SchemaFile;let library:Library;let shared:Library;let sharedCatalogue:UUID?;var sharedRecords:[WorkspaceImportedAsset]=[]}
    static func inspect(_ url:URL)throws -> Source {
        var root=url.hasDirectoryPath ? url:url.deletingLastPathComponent(),temporary=false
        if ["colshr","zip"].contains(url.pathExtension.lowercased()) {
            let checked=try Sharing.inspect(url)
            guard checked.ok,checked.manifest.level == .catalogue else {throw failure(checked.problems.isEmpty ? "Choose a complete catalogue archive.":checked.problems.joined(separator:"\n"))}
            root=try Sharing.stage(checked);temporary=true
        }
        do {
            guard let index=CatalogueFiles.index(in:root),index.pathExtension.lowercased() != "collib" else{throw failure("Choose a catalogue's .colcat file, containing folder or .colshr archive.")}
            try Handler_File_Manager.shared.requireAvailableCatalogue(index)
            let loaded=try CatalogueTree.read(root:root);try SimpleCatalogue.validate(loaded.schema)
            var shared=loaded.library;shared.projects=[];shared.swatches=loaded.library.swatches.filter{$0.projectID == nil}
            let bundle=root.appendingPathComponent("Support/Shared Library")
            var sharedID:UUID?=nil;var sharedRecords:[WorkspaceImportedAsset]=[]
            if CatalogueFiles.index(in:bundle) != nil {let read=try CatalogueTree.read(root:bundle);shared=GlobalAssets.joined(shared,read.library);sharedID=read.catalogue.id;sharedRecords=read.catalogue.importedAssets ?? []}
            return Source(root:root,temporary:temporary,catalogue:loaded.catalogue,schema:loaded.schema,library:loaded.library,shared:shared,sharedCatalogue:sharedID,sharedRecords:sharedRecords)
        }catch{if temporary{Sharing.discard(root)};throw error}
    }
    static func content(_ palette:Swatch,in library:Library)throws->String {
        var object=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(palette)) as! [String:Any]
        for key in ["id","projectID","bucketID","position","listPosition","favouritePosition","claim","copiedFrom"] {object.removeValue(forKey:key)}
        for key in Array(object.keys) where key.hasSuffix("At") {object.removeValue(forKey:key)}
        let keys=Set(palette.entries.map(\.hex)+(palette.styles ?? []).flatMap{[$0.ink,$0.paper]})
        object["colourDefinitions"]=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(library.colours.filter{keys.contains($0.hex)}.sorted{$0.hex < $1.hex}))
        func withoutCaptureDates(_ value:Any)->Any {
            if let fields=value as? [String:Any] {return fields.filter{!$0.key.hasSuffix("At")}.mapValues(withoutCaptureDates)}
            if let values=value as? [Any] {return values.map(withoutCaptureDates)}
            return value
        }
        return Sharing.sha256(try JSONSerialization.data(withJSONObject:withoutCaptureDates(object),options:.sortedKeys))
    }
    static func independent(_ palette:Swatch)throws->Swatch {
        var object=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(palette)) as! [String:Any]
        object["id"]=UUID().uuidString;object["copiedFrom"]=palette.id.uuidString;object.removeValue(forKey:"claim")
        return try ColourFiles.decoder().decode(Swatch.self,from:JSONSerialization.data(withJSONObject:object))
    }
    static func commit(_ source:Source,home:URL,includeShared:Bool,independentConflicts:Bool,localTerminology:SimpleCatalogueStructure?=nil)throws -> String {
        let manager=Handler_File_Manager.shared,cats=Catalogues(root:home,legacyURL:nil)
        try SimpleCatalogue.validate(source.schema)
        if let existing=cats.registry.first(where:{$0.id == source.catalogue.id}) {throw failure("This catalogue is already registered as “\(existing.name)”. Open it from Catalogues instead of importing another copy.")}
        let name=uniqueName(filesystemName(source.catalogue.name),among:cats.names())
        let destination=home.appendingPathComponent("Catalogues").appendingPathComponent(name)
        guard !destination.standardizedFileURL.path.hasPrefix(source.root.standardizedFileURL.path+"/") else{throw failure("Choose a source outside the destination catalogue folder.")}
        let original=try manager.copySnapshot(source.root)
        var shared=try GlobalAssets(home:home).load(),map:[UUID:UUID]=[:]
        let globalID=CatalogueTree.catalogue(in:GlobalAssets(home:home).root)?.id
        var sharedRecords=CatalogueTree.catalogue(in:GlobalAssets(home:home).root)?.importedAssets ?? []
        var payloads:[(URL,URL)]=[]
        // Decide every shared conflict before writing any catalogue or library bytes.
        if includeShared {
            for palette in source.shared.swatches {
                let digest=try content(palette,in:source.shared)
                let exact=try shared.swatches.first{try content($0,in:shared) == digest}
                if let exact {map[palette.id]=exact.id;continue}
                let twin=shared.swatches.first{$0.id == palette.id || $0.name.caseInsensitiveCompare(palette.name) == .orderedSame}
                if let twin,!independentConflicts {map[palette.id]=twin.id;continue}
                var incoming=try twin == nil ? palette:independent(palette)
                incoming.projectID=nil;incoming.bucketID=nil;incoming.name=uniqueName(incoming.name,among:shared.swatches.map(\.name))
                map[palette.id]=incoming.id;shared.swatches.append(incoming)
            }
            for record in source.sharedRecords {
                if let existing=sharedRecords.first(where:{$0.type == record.type && $0.external == record.external && $0.path == record.path}) {map[record.id]=existing.id;continue}
                let twin=sharedRecords.first{$0.id == record.id || ($0.type == record.type && $0.name.caseInsensitiveCompare(record.name) == .orderedSame)}
                if let twin,!independentConflicts {map[record.id]=twin.id;continue}
                var incoming=record
                if twin != nil {incoming.id=UUID();incoming.name=uniqueName(incoming.name,among:sharedRecords.map(\.name))}
                incoming.member=nil;incoming.bucket=nil
                if !record.external {
                    let original=try record.url(in:source.root.appendingPathComponent("Support/Shared Library"))
                    incoming.path="Imported/"+incoming.id.uuidString+"/"+original.lastPathComponent
                    payloads.append((original,try incoming.url(in:GlobalAssets(home:home).root)))
                }
                map[record.id]=incoming.id;sharedRecords.append(incoming)
            }
            for colour in source.shared.colours {
                if let old=shared.colours.first(where:{$0.hex == colour.hex}),old.source != colour.source || old.master != colour.master || old.kind != colour.kind {throw failure("A shared colour identity has a different master definition. Resolve that colour before import; existing values were not overwritten.")}
                if !shared.colours.contains(where:{$0.hex == colour.hex}) {shared.colours.append(colour)}
            }
            for profile in source.shared.colourProfiles {
                if let old=shared.colourProfiles.first(where:{$0.id == profile.id}),old != profile {throw failure("A shared colour profile has the same identity but different contents. Resolve that profile before importing; no files were changed.")}
                if !shared.colourProfiles.contains(where:{$0.id == profile.id}){shared.colourProfiles.append(profile)}
            }
        }
        return try manager.withTransaction(home:home) {
            guard !FileManager.default.fileExists(atPath:destination.path) else{throw CatalogueError.nameTaken(name)}
            try manager.copyVerified(source.root,to:destination)
            guard try manager.copySnapshot(source.root) == original else{throw failure("The source changed during import. Review it again; its originals are unchanged.")}
            guard let index=CatalogueFiles.index(in:destination) else{throw failure("The copied catalogue index is missing.")}
            // Retain labels by default. A deliberate terminology conversion changes labels only.
            var file=source.catalogue
            file.name=name
            if let terminology=localTerminology {
                for i in file.collections.indices {file.collections[i].template.name=terminology.singular;file.collections[i].workItemPlural=terminology.plural
                    for j in file.collections[i].members.indices {file.collections[i].members[j].schema?.name=terminology.singular}}
                file.structure?.singular=terminology.singular;file.structure?.plural=terminology.plural
            }
            let sharedIDs=Set(source.shared.swatches.map(\.id)+source.sharedRecords.map(\.id))
            if includeShared,globalID != nil {
                for (original,target) in payloads {try manager.copyVerified(original,to:target)}
                try GlobalAssets(home:home).save(shared)
                let globalIndex=GlobalAssets(home:home).index
                var globalFile=try ColourFiles.decoder().decode(CatalogueFile.self,from:manager.read(globalIndex))
                globalFile.importedAssets=sharedRecords
                try manager.write(ColourFiles.encoder().encode(globalFile),to:globalIndex)
                // Convert bundled shared-palette locations into explicit references to My Library.
                var references=file.importedAssets ?? []
                for link in file.libraryAssets where sharedIDs.contains(link.id) {
                    if let target=map[link.id],let path=CatalogueTree.file(ofPalette:target,in:GlobalAssets(home:home).root) {
                        references.append(WorkspaceImportedAsset(id:link.id,name:link.name,type:"Palettes",path:path.path,external:true))
                    }
                }
                for i in references.indices {
                    if let original=file.sharedAssetReferences?[references[i].id.uuidString],let id=UUID(uuidString:original),let target=map[id],let path=CatalogueTree.file(ofPalette:target,in:GlobalAssets(home:home).root) {references[i].path=path.path;references[i].external=true}
                }
                file.importedAssets=references
                // Owned palette files that travelled as shared assets must not be rediscovered
                // as catalogue-owned originals on the next scan.
                for link in file.libraryAssets where sharedIDs.contains(link.id) {
                    let original=try Handler_File_Manager.contained(link.file,under:destination)
                    if FileManager.default.fileExists(atPath:original.path) {
                        let transport=destination.appendingPathComponent("Support/Imported Shared Payload/"+link.file)
                        try manager.createDirectory(transport.deletingLastPathComponent());try manager.move(original,to:transport)
                    }
                }
                file.libraryAssets.removeAll{sharedIDs.contains($0.id)}
            }
            if !includeShared {
                for link in file.libraryAssets where sharedIDs.contains(link.id) {
                    let original=try Handler_File_Manager.contained(link.file,under:destination)
                    if FileManager.default.fileExists(atPath:original.path) {
                        let transport=destination.appendingPathComponent("Support/Imported Shared Payload/"+link.file)
                        try manager.createDirectory(transport.deletingLastPathComponent());try manager.move(original,to:transport)
                    }
                }
                file.libraryAssets.removeAll{sharedIDs.contains($0.id)}
            }
            try manager.write(ColourFiles.encoder().encode(file),to:index)
            // Bundles remain an immutable transport payload; their .colcat is not registered.
            try manager.requireAvailableCatalogue(index)
            _ = try CatalogueTree.read(root:destination)
            try cats.registerChecked(name,at:destination)
            return name
        }
    }
    static func choose(over window:NSWindow,library:LibraryController){
        let panel=NSOpenPanel();panel.title="Import Catalogue";panel.prompt="Review Catalogue";panel.canChooseDirectories=true;panel.canChooseFiles=true
        panel.allowedContentTypes=["colcat","colshr","zip"].compactMap{UTType(filenameExtension:$0)}
        panel.message="Choose a .colcat with its containing assets, a catalogue folder, or a .colshr archive. Import creates a copy; the original stays unchanged."
        panel.beginSheetModal(for:window){response in guard response == .OK,let url=panel.url else{return}
            do {try FolderAccess.authorize(url.hasDirectoryPath ? url:url.deletingLastPathComponent());let source=try inspect(url);review(source,over:window,library:library)}catch{NSAlert(error:error).beginSheetModal(for:window)}
        }
    }
    private static func review(_ source:Source,over window:NSWindow,library:LibraryController){
        guard let host=window.contentView else{if source.temporary{Sharing.discard(source.root)};return}
        let clients=source.schema.collections.map{"\($0.name): \($0.workItemPlural ?? $0.stack.name)"}.joined(separator:"\n")
        let modal=SwissFocusModal(title:"Import Catalogue",message:"\(source.catalogue.name)\n\nCatalogue → Client → Work Item → Assets\n\(clients.isEmpty ? "No clients yet":clients)\n\nClient terminology can differ without changing the structure. Originals remain unchanged.")
        let options=NSView(frame:NSRect(x:0,y:0,width:500,height:120))
        let shared=ClickCursorButton(checkboxWithTitle:"Add My Library (\(source.shared.swatches.count) Embedded, \(source.sharedRecords.count) References)",target:nil,action:nil);shared.state = .on;shared.frame=NSRect(x:0,y:84,width:500,height:28);shared.isEnabled = !source.shared.swatches.isEmpty || !source.sharedRecords.isEmpty
        let wording=ClickCursorButton(checkboxWithTitle:"Use My Catalogue's Default Work Item Wording",target:nil,action:nil);wording.frame=NSRect(x:0,y:50,width:500,height:28)
        let conflicts=AnalysisMenu("Shared Asset Conflicts",["Keep Existing Shared Assets","Import Conflicts As Independent Copies"]);conflicts.frame=NSRect(x:0,y:10,width:480,height:32)
        [shared,wording,conflicts].forEach(options.addSubview);modal.content(options,height:120)
        var finished=false
        func cleanup(){guard !finished else{return};finished=true;if source.temporary{Sharing.discard(source.root)}}
        modal.button("Import Catalogue",primary:true){
            do{let local=wording.state == .on ? SchemaTrial.read(in:library.store.root).structure:nil
                let name=try commit(source,home:Catalogues.standard.root,includeShared:shared.state == .on,independentConflicts:conflicts.indexOfSelectedItem == 1,localTerminology:local)
                cleanup();modal.dismissOverlay();library.open(catalogue:name);StudioWindowController.shared?.frame.go(.catalogue)
            }catch{NSAlert(error:error).beginSheetModal(for:window)}
        }
        modal.button("Cancel"){cleanup();modal.dismissOverlay()};modal.present(over:host)
    }
}

/// Optional shared-library payload inside the existing verified .colshr format.
enum SimpleSharedArchive {
    static let prefix="Support/Shared Library/"
    static func prepare(home:URL)throws->(entries:[Zip.StreamEntry],staging:URL) {
        let assets=GlobalAssets(home:home),library=try assets.load()
        let staging=FileManager.default.temporaryDirectory.appendingPathComponent("colorgain-shared-"+UUID().uuidString)
        var keep=false
        defer{if !keep{try? FileManager.default.removeItem(at:staging)}}
        try CatalogueTree.write(library,schema:.init(collections:[],places:[:]),index:staging.appendingPathComponent("Assets.colcat"),name:"My Library",carry:CatalogueTree.catalogue(in:assets.root),poolDirectory:"Library")
        let index=staging.appendingPathComponent("Assets.colcat")
        guard var document=CatalogueTree.catalogue(in:staging) else{throw failure("My Library could not be staged for export.")}
        var entries:[Zip.StreamEntry]=[]
        for i in (document.importedAssets ?? []).indices {
            guard var record=document.importedAssets?[i] else{continue}
            // Other external library references remain links in the archive; only
            // image references are bundled for a portable catalogue export.
            if record.external && record.type != "Photographs" && record.type != "Images" {continue}
            let original=try record.url(in:assets.root)
            let values=try original.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory != true,values.isSymbolicLink != true else{throw failure("A My Library asset is not a regular file: "+record.name)}
            if record.external {
                record.path="Support/Referenced Images/"+record.id.uuidString+"/"+filesystemName(original.lastPathComponent)
                record.external=false
                document.importedAssets?[i]=record
            }
            entries.append(.init(path:prefix+record.path,file:original))
        }
        let indexBytes=try Handler_File_Manager.shared.documentBytes(ColourFiles.encoder().encode(document),extension:"colcat")
        try indexBytes.write(to:index,options:.atomic)
        for (path,_) in try Handler_File_Manager.shared.copySnapshot(staging) {
            let url=staging.appendingPathComponent(path)
            entries.append(.init(path:prefix+path,file:url))
        }
        keep=true
        return (entries,staging)
    }
}
