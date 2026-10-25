import Foundation

func runSimpleCatalogueTests(check:(Bool,String)->Void){
    print("Simplified ownership, setup, migration and catalogue exchange")
    check(SimpleAssetType.setupImportTypes.map(\.id) == ["palettes","typography","images","photography","documents","ase","luts","icc","css"] && SimpleAssetType.setupImportTypes.map(\.setupTitle) == WorkspaceImport.types,"Setup and Import offer the nine focused asset types in the same order")
    check(SimpleCatalogueStructure().assetTypes == SimpleAssetType.defaultAssetIDs && SimpleAssetType.defaultLibraryIDs == ["information","palettes","typography","images","photography"],"New clients and My Library seed the five requested sections in order")
    let defaultStack=SimpleCatalogue.stack(SimpleCatalogueStructure())
    check(defaultStack.children.first?.name == "Information" && defaultStack.children.first(where:{$0.kind == "Simple Assets"})?.children.map(\.name) == ["Palettes","Typography","Images","Photographs"],"New client stacks contain Information then the four default asset buckets in order")
    check(SimpleAssetType.find("photography")?.selectable == true && SimpleAssetType.find("images")?.selectable == true && SimpleAssetType.find("audio")?.selectable == false,"Images and Photographs are setup choices; historical broad types stay readable")
    let retired=SchemaNode(name:"Retired Asset",kind:"Retired Asset")
    let stored=SchemaNode(name:"Owner",children:[SchemaNode(name:"Assets",children:[SimpleAssetType.find("palettes")!.node,retired],kind:"Simple Assets")])
    let displayed=SimpleAssetType.visibleStack(stored,types:SimpleAssetType.all)
    check(displayed.children[0].children.count == 1 && stored.children[0].children.count == 2,"Unregistered asset buckets stay out of navigation without modifying the stored schema")
    check(!WorkspaceImport.supportsRecord("Retired Asset") && WorkspaceImport.supportsRecord("Palettes") && WorkspaceImport.supportsRecord("Images"),"Import listings exclude retired records and retain supported assets")
    let fm=FileManager.default
    do {
        let root=fm.temporaryDirectory.appendingPathComponent("Colorgain-Simple-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:root)}
        var config=SimpleCatalogueStructure();config.singular="Product";config.plural="Products";config.clientLabel="Customer";config.assetTypes=["palettes","photography","audio","css"]
        let created=try SimpleCatalogue.create(home:root,parent:root.appendingPathComponent("Catalogues"),name:"First",config:config)
        let cats=Catalogues(root:root,legacyURL:nil),store=cats.store(for:created.name)
        let loaded=try store.load()
        check(loaded.projects.isEmpty && store.schema.collections.isEmpty,"New setup creates no placeholder client or work item")
        check(store.schema.structure == config,"Setup persists terminology and stable asset types in the catalogue")
        check(store.schema.structure?.clientName == "Customer" && store.schema.structure?.assetTypes.contains("audio") == true,"Setup round trip retains lvl2 custom terminology and Audio Clips")
        let loopRoot=fm.temporaryDirectory.appendingPathComponent("Colorgain-Setup-Loop-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:loopRoot)}
        var loopConfig=SimpleCatalogueStructure();loopConfig.assetTypes=[]
        let seeds=[SimpleSetupClient(clientName:"Acme",projectName:"Launch",clientWord:"Client",workWord:"Project",assetTypes:["palettes"]),SimpleSetupClient(clientName:"Beta",projectName:"Website",clientWord:"Client",workWord:"Campaign",assetTypes:["icc"])]
        let loopMade=try SimpleCatalogue.create(home:loopRoot,parent:loopRoot.appendingPathComponent("Catalogues"),name:"Loop",config:loopConfig,clients:seeds)
        let loopStore=Catalogues(root:loopRoot,legacyURL:nil).store(for:loopMade.name)
        let loopLibrary=try loopStore.load(),loopSchema=loopStore.schema
        check(loopSchema.collections.map(\.name) == ["Acme","Beta"] && loopLibrary.projects.map(\.name) == ["Launch","Website"] && loopSchema.places.count == 2,"Repeated setup branches create real clients and work items")
        check(loopSchema.collections.map{$0.stack.name} == ["Project","Campaign"] && loopSchema.collections.map{$0.workItemPlural ?? ""} == ["Projects","Campaigns"] && loopSchema.places[loopLibrary.projects[0].id.uuidString]?.collection == loopSchema.collections[0].id && loopSchema.places[loopLibrary.projects[1].id.uuidString]?.collection == loopSchema.collections[1].id,"Each setup work item keeps its client and terminology")
        check(Set(GlobalAssets(home:loopRoot).assetTypes) == Set(["information","palettes","icc"]),"My Library receives Information and selected categories from all setup branches")
        var customConfig=SimpleCatalogueStructure();customConfig.assetTypes=[]
        customConfig.customAssetFamilies=["Press Archives"]
        customConfig.customAssetTypes=[SimpleCustomAssetType(id:"custom-finish",title:"Finish Samples",family:"Print Production"),SimpleCustomAssetType(id:"custom-plates",title:"Plate Records",family:"Press Archives")]
        let customSeed=SimpleSetupClient(clientName:"Gamma",projectName:"Run",clientWord:"Client",workWord:"Project",assetTypes:["custom-finish","custom-plates"])
        let customMade=try SimpleCatalogue.create(home:loopRoot,parent:loopRoot.appendingPathComponent("Catalogues"),name:"Custom",config:customConfig,clients:[customSeed])
        let customStore=Catalogues(root:loopRoot,legacyURL:nil).store(for:customMade.name)
        _ = try customStore.load()
        let customManifest=try AppDataStore(root:loopRoot).read()
        check(customStore.schema.structure?.customAssetTypes == customConfig.customAssetTypes && customStore.schema.structure?.customAssetFamilies == customConfig.customAssetFamilies,"Custom categories and types round-trip in the catalogue structure")
        check((customManifest["customAssetTypes"] as? [[String:String]])?.count == 2 && (customManifest["customAssetFamilies"] as? [String]) == ["Press Archives"],"Custom asset definitions persist in .coldata for the next client")
        check(Set(GlobalAssets(home:loopRoot).assetTypes).isSuperset(of:["custom-finish","custom-plates"]) && fm.fileExists(atPath:GlobalAssets(home:loopRoot).root.appendingPathComponent("Plate Records").path),"My Library includes selected custom categories and their disk destinations")
        let nextClientConfig=SimpleAssetType.includingWorkspace(SimpleCatalogueStructure(),home:loopRoot)
        check(nextClientConfig.customAssetTypes?.count == 2 && SimpleAssetType.find("custom-plates",in:nextClientConfig) != nil,"A subsequent client form can reuse workspace custom types")
        let personalRoot=fm.temporaryDirectory.appendingPathComponent("Colorgain-Personal-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:personalRoot)}
        var personalConfig=config;personalConfig.personalMode=true
        let personalCreated=try SimpleCatalogue.create(home:personalRoot,parent:personalRoot.appendingPathComponent("Catalogues"),name:"Personal",config:personalConfig)
        let personalSchema=try CatalogueTree.read(root:Catalogues(root:personalRoot,legacyURL:nil).directory(for:personalCreated.name)).schema
        check(personalSchema.structure?.personalMode == true && personalSchema.structure?.personalCollectionID == personalSchema.collections.first?.id && personalSchema.collections.count == 1,"Personal setup creates a stable internal owner and no client prompt")
        var legacyObject=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(config)) as! [String:Any]
        legacyObject.removeValue(forKey:"clientLabel")
        let legacy=try ColourFiles.decoder().decode(SimpleCatalogueStructure.self,from:JSONSerialization.data(withJSONObject:legacyObject))
        check(legacy.clientName == "Client","Earlier catalogue structures retain Client wording when the new optional label is absent")
        check(GlobalAssets(home:root).assetTypes == ["information"]+config.assetTypes && fm.fileExists(atPath:GlobalAssets(home:root).index.path),"Setup initialises My Library with Information and the catalogue selection")
        let before=try FileHandlerFixture.snapshot(root)
        check((try? SimpleCatalogue.create(home:root,parent:cats.folder,name:"First",config:config)) == nil,"Repeated setup cannot overwrite an existing catalogue")
        check(try before == FileHandlerFixture.snapshot(root),"Rejected repeated setup leaves existing workspace bytes unchanged")
        var schema=store.schema,lib=loaded
        var a=SimpleCatalogue.client("Alpha",config:config)
        a.profile=["clientEmail":"person@example.com","clientCompany":"Alpha Ltd"]
        schema.structure?.formPresets=[WorkFormPreset(id:"preset",name:"Production",fields:[WorkFormField(id:"quantity",label:"Quantity",type:"Number")])]
        var betaConfig=config;betaConfig.singular="Work Order";betaConfig.plural="Work Orders"
        let b=SimpleCatalogue.client("Beta",config:betaConfig)
        schema.collections=[a,b]
        let first=lib.createProject(named:"One"),second=lib.createProject(named:"Two")
        schema.places[first.uuidString] = .init(collection:a.id);schema.places[second.uuidString] = .init(collection:b.id)
        lib.setProjectDetails(first,["description":"A project","custom.quantity":"42","customForm":"[{\"id\":\"quantity\",\"label\":\"Quantity\",\"type\":\"Number\"}]"])
        try store.save(lib,schema:schema)
        let reread=try CatalogueTree.read(root:store.root)
        check(reread.schema.collections.map{$0.stack.name} == ["Product","Work Order"] && reread.schema.collections.map{$0.workItemPlural ?? ""} == ["Products","Work Orders"],"Sibling clients retain independent singular and plural labels after round trip")
        check(reread.schema.collections.first?.profile == a.profile,"Client contact profile survives catalogue persistence")
        check(reread.library.project(first)?.details?["custom.quantity"] == "42" && reread.library.project(first)?.details?["customForm"] != nil,"Project custom form and answers survive catalogue persistence")
        check(reread.schema.structure?.formPresets?.first?.fields.first?.label == "Quantity","Form presets retain field definitions independently of project answers")
        let personal=try SimpleCatalogue.settingPersonal(true,in:reread.schema)
        let personalAgain=try SimpleCatalogue.settingPersonal(true,in:personal)
        let restored=try SimpleCatalogue.settingPersonal(false,in:personalAgain)
        check(personal.collections.count == reread.schema.collections.count+1 && personalAgain.collections.count == personal.collections.count,"Personal mode creates one stable internal owner")
        check(restored.places == reread.schema.places && restored.collections.first?.profile == a.profile,"Personal mode retains existing ownership and client profiles")
        check(restored.structure?.personalMode == false && restored.structure?.personalCollectionID == personal.structure?.personalCollectionID,"Client organisation can be enabled again without replacing personal work")
        try SimpleCatalogue.validate(reread.schema)
        var invalid=reread.schema;invalid.collections[0].folders=[SchemaFolder(name:"Extra Level")]
        check((try? SimpleCatalogue.validate(invalid)) == nil,"Fixed structure rejects extra ownership levels instead of guessing")
        var future=config;future.version=99
        check((try? future.validate()) == nil,"Unsupported structure versions are refused")
    }catch{check(false,"Simple setup: \(error)")}
    do {
        let fixture=try FileHandlerFixture();defer{fixture.remove()}
        let initial=try CatalogueTree.read(root:fixture.first)
        let photo=SchemaNode(name:"Photography",kind:"Photography")
        var originalSchema=initial.schema;originalSchema.collections[0].stack.children.append(photo)
        let fixtureStore=LibraryStore(directory:fixture.first,legacyURL:nil,name:"First",assetsHome:fixture.root)
        _ = try fixtureStore.load();try fixtureStore.save(initial.library,schema:originalSchema)
        let originalMember=initial.library.projects.first!.id
        let memberFolder=CatalogueTree.folder(ofWorkGroup:originalMember,in:fixture.first)!
        let originalBinary=Data([0,17,255,4,0,93])
        try originalBinary.write(to:memberFolder.appendingPathComponent("Photography/original.bin"))
        let before=try CatalogueTree.read(root:fixture.first)
        let member=before.library.projects.first!.id
        let original=try FileHandlerFixture.snapshot(fixture.first)
        let backup=try SimpleCatalogue.migrate(root:fixture.first,home:fixture.root)
        check(try backup != nil && FileHandlerFixture.snapshot(backup!) == original,"Migration makes a complete byte-identical recovery copy")
        let migrated=try CatalogueTree.read(root:fixture.first)
        check(Set(migrated.library.swatches.map(\.id)) == Set(before.library.swatches.map(\.id)) && migrated.library.projects.map(\.id) == before.library.projects.map(\.id),"Migration retains palette and work-item identities")
        let stack=migrated.schema.stacks?[member.uuidString] ?? migrated.schema.collections[0].stack
        check(stack.children.contains{$0.kind == "Simple Assets" && $0.children.contains{SchemaTrial.role(of:$0) == .palettes}},"Migration moves palette buckets beneath one Assets container")
        let movedMember=CatalogueTree.folder(ofWorkGroup:member,in:fixture.first)!
        check(try Data(contentsOf:movedMember.appendingPathComponent("Assets/Photography/original.bin")) == originalBinary,"Migration moves complete binary category folders without decoding or discarding originals")
        check(try SimpleCatalogue.migrate(root:fixture.first,home:fixture.root) == nil,"A second migration is an idempotent no-op")
        let target=fm.temporaryDirectory.appendingPathComponent("Colorgain-Import-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:target)}
        _ = try SimpleCatalogue.create(home:target,parent:target.appendingPathComponent("Catalogues"),name:"Empty",config:.init())
        let source=try SimpleCatalogueImport.inspect(fixture.first.appendingPathComponent("First.colcat"))
        let snapshot=try FileHandlerFixture.snapshot(fixture.first)
        let name=try SimpleCatalogueImport.commit(source,home:target,includeShared:false,independentConflicts:false)
        check(try snapshot == FileHandlerFixture.snapshot(fixture.first),"Catalogue import never changes source bytes")
        let imported=try CatalogueTree.read(root:Catalogues(root:target,legacyURL:nil).directory(for:name))
        check(imported.catalogue.id == migrated.catalogue.id && imported.schema.collections[0].stack.name == migrated.schema.collections[0].stack.name,"Import keeps incoming catalogue identity and client terminology")
        check((try? SimpleCatalogueImport.commit(source,home:target,includeShared:false,independentConflicts:false)) == nil,"Already registered catalogue identities are not silently duplicated")
        var global=try GlobalAssets(home:fixture.root).load()
        let sharedID=global.createSwatch(named:"Shared Brand",hexes:["#123456"])
        try GlobalAssets(home:fixture.root).save(global)
        let external=WorkspaceImportedAsset(name:"External Reference",type:"Palettes",path:"/unavailable/reference.colplt",external:true)
        let owned=WorkspaceImportedAsset(name:"Owned Reference",type:"ASE",path:"Imported/reference.ase",external:false)
        let ownedBytes=Data([65,83,69,70,0,255])
        let assets=GlobalAssets(home:fixture.root)
        try fm.createDirectory(at:assets.root.appendingPathComponent("Imported"),withIntermediateDirectories:true)
        try ownedBytes.write(to:owned.url(in:assets.root))
        var globalFile=CatalogueTree.catalogue(in:assets.root)!
        globalFile.importedAssets=[external,owned]
        try ColourFiles.encoder().encode(globalFile).write(to:assets.index)
        let libraryExport=fixture.root.appendingPathComponent("Library Export",isDirectory:false)
        try MyLibraryFile.export(home:fixture.root,to:libraryExport)
        let libraryTarget=fm.temporaryDirectory.appendingPathComponent("Colorgain-Library-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:libraryTarget)}
        _ = try SimpleCatalogue.create(home:libraryTarget,parent:libraryTarget.appendingPathComponent("Catalogues"),name:"Empty",config:.init())
        let sourceSnapshot=try FileHandlerFixture.snapshot(libraryExport)
        try MyLibraryFile.merge(libraryExport,home:libraryTarget)
        let once=CatalogueTree.catalogue(in:GlobalAssets(home:libraryTarget).root)!
        try MyLibraryFile.merge(libraryExport,home:libraryTarget)
        let twice=CatalogueTree.catalogue(in:GlobalAssets(home:libraryTarget).root)!
        check(once.libraryAssets.count == twice.libraryAssets.count && once.importedAssets?.count == twice.importedAssets?.count,"Repeated library import reuses palettes and referenced payloads")
        check(try FileHandlerFixture.snapshot(libraryExport) == sourceSnapshot,"Library import leaves exported source bytes unchanged")
        check((try? SimpleCatalogueImport.inspect(libraryExport.appendingPathComponent("my_library.collib"))) == nil,"Library indexes cannot be imported as client catalogues")
        let migratedAssets=GlobalAssets(home:libraryTarget),identity=twice.id
        try fm.moveItem(at:migratedAssets.libraryIndex,to:migratedAssets.legacyIndex)
        try AppDataStore(root:libraryTarget).update{$0["assets"]="My Library/Assets.colcat";$0["libraryAssetTypes"]=["palettes","audio"]}
        var old=twice;old.libraryAssetTypes=nil
        try ColourFiles.encoder().encode(old).write(to:migratedAssets.legacyIndex)
        _ = try migratedAssets.load()
        check(CatalogueTree.catalogue(in:migratedAssets.root)?.id == identity && migratedAssets.assetTypes == ["palettes","audio"],"Legacy library migration preserves identity and transfers category choices")
        let migratedSnapshot=try FileHandlerFixture.snapshot(libraryTarget)
        try migratedAssets.migrateLibraryIndex()
        check(try FileHandlerFixture.snapshot(libraryTarget) == migratedSnapshot,"Library migration is idempotent")
        check(try AppDataStore(root:libraryTarget).read()["libraryAssetTypes"] == nil,"Workspace manifest no longer owns library category choices")
        let linkedImage=fm.temporaryDirectory.appendingPathComponent("Colorgain-Linked-"+UUID().uuidString+".png")
        defer{try? fm.removeItem(at:linkedImage)}
        let imageBytes=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2sAAAAASUVORK5CYII=")!
        try imageBytes.write(to:linkedImage)
        let photoRecord=WorkspaceImportedAsset(name:linkedImage.lastPathComponent,type:"Photographs",path:linkedImage.path,external:true,member:member,bucket:photo.id)
        try WorkspaceImport.updateRecords(at:fixtureStore.url){$0.append(photoRecord)}
        let liveIndex=try Data(contentsOf:fixtureStore.url)
        let archive=fixture.root.appendingPathComponent("Portable.colshr")
        try Handler_File_Manager.shared.createCatalogueArchive(name:"First",catalogues:Catalogues(root:fixture.root,legacyURL:nil),to:archive,includeShared:true)
        let packed=try SimpleCatalogueImport.inspect(archive);defer{if packed.temporary{Sharing.discard(packed.root)}}
        let bundledImage=packed.catalogue.importedAssets?.first{$0.id == photoRecord.id}
        let bundledBytes:Data? = try bundledImage.map{try Data(contentsOf:$0.url(in:packed.root))}
        check(bundledImage?.external == false && bundledBytes == imageBytes,"Portable catalogue archive embeds linked images and rewrites their paths")
        check(try Data(contentsOf:fixtureStore.url) == liveIndex && Data(contentsOf:linkedImage) == imageBytes,"Export retains the live image reference and original bytes")
        check(packed.shared.swatches.contains{$0.id == sharedID},"Verified catalogue archive optionally carries My Library assets")
        let secondTarget=fm.temporaryDirectory.appendingPathComponent("Colorgain-Shared-"+UUID().uuidString,isDirectory:true)
        defer{try? fm.removeItem(at:secondTarget)}
        _ = try SimpleCatalogue.create(home:secondTarget,parent:secondTarget.appendingPathComponent("Catalogues"),name:"Empty",config:.init())
        let importedName=try SimpleCatalogueImport.commit(packed,home:secondTarget,includeShared:true,independentConflicts:false)
        let receivedRoot=Catalogues(root:secondTarget,legacyURL:nil).directory(for:importedName)
        let receivedImage=CatalogueTree.catalogue(in:receivedRoot)?.importedAssets?.first{$0.id == photoRecord.id}
        let receivedBytes:Data? = try receivedImage.map{try Data(contentsOf:$0.url(in:receivedRoot))}
        check(receivedImage?.external == false && receivedBytes == imageBytes,"Imported catalogue restores linked photographs as owned files")
        check(try GlobalAssets(home:secondTarget).load().swatches.contains{$0.id == sharedID},"Included shared assets are placed in My Library rather than transferred to catalogue ownership")
        let importedGlobal=GlobalAssets(home:secondTarget),importedFile=CatalogueTree.catalogue(in:importedGlobal.root)!
        check(importedFile.importedAssets?.contains(external) == true,"Unavailable external My Library references survive exchange without claiming embedded originals")
        let importedOwned=importedFile.importedAssets!.first{$0.id == owned.id}!
        check(try Data(contentsOf:importedOwned.url(in:importedGlobal.root)) == ownedBytes,"Owned referenced payloads retain their exact bytes through shared archive exchange")
    }catch{check(false,"Simple migration/import: \(error)")}
}
