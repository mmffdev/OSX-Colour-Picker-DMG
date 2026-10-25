import Foundation

func runWorkspaceImportTests(check: (Bool, String) -> Void) {
    runWorkspaceImportBatchTests(check: check)
    print("Workspace import destinations and transactions")
    check(WorkspaceImport.importExtensions(for:"Palettes").contains("colplt"),"palette source scanning accepts .colplt files")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Colorgain-Import-" + UUID().uuidString)
    defer { FileEditAccess.releaseOwned(); try? FileManager.default.removeItem(at: root) }
    do {
        let store = LibraryStore(directory: root.appendingPathComponent("Catalogue"), legacyURL: nil)
        var library = Library()
        let a = library.createProject(named: "Alpha"), b = library.createProject(named: "Beta")
        let nested = SchemaNode(name: "Artwork", children: [SchemaNode(name: "Palettes", role: .palettes)])
        let tree = SchemaNode(name: "Owner", children: [nested])
        let collection = SchemaCollection(name: "Clients", stack: tree)
        let schema = SchemaTrial.SchemaFile(collections: [collection], places: [a.uuidString: .init(collection: collection.id), b.uuidString: .init(collection: collection.id)])
        try store.save(library, schema: schema)
        library = try store.load()
        let seeded=AssetCollections.list(in:store)
        check(seeded.count == 1 && seeded[0].name == "My Collection" && seeded[0].colour == AssetCollections.defaultColour && seeded[0].items.isEmpty,"new .colcat seeds one editable My Collection")
        let choices = WorkspaceImport.destinations(library: library, schema: schema, type: "ASE")
        guard let alpha = choices.first(where: { $0.member == a && $0.parent == nested.id }) else { throw failure("Missing destination fixture.") }
        check(choices.contains { $0.member == b } && choices.contains{$0.title == "My Library"} && choices.contains{$0.title == "Custom Folders"}, "import lists every real branch, My Library and Custom Folders")
        let paletteChoices = WorkspaceImport.destinations(library: library, schema: schema, type: "Palettes")
        check(paletteChoices.contains { $0.member == a && $0.title == "Palettes" && $0.parent == nested.id && $0.bucket == nested.children[0].id }, "palette destination shows its real palette node and keeps its identity")
        check(!SchemaTrial.start.children.contains { WorkspaceImport.matches($0, type: "ASE") } && SchemaTrial.nestedNames.contains("ASE"), "ASE is a schema option without seeding it into existing/default trees")
        let source = root.appendingPathComponent("Original.ase")
        let bytes = ExportFormat.ase.data([ExportPalette(name: "Test", colours: [.init(name: "Red", hex: "#FF0000")])])!
        try Handler_File_Manager.shared.publishRaw(bytes, to: source)
        let before = try Data(contentsOf: store.url)
        do { try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, target: alpha, allowBucket: false, store: store); check(false, "missing ASE bucket requires consent") }
        catch { check(try Data(contentsOf: store.url) == before, "declining a missing ASE bucket leaves the catalogue unchanged") }
        let bad = root.appendingPathComponent("Invalid.ase")
        try Handler_File_Manager.shared.publishRaw(Data("invalid".utf8), to: bad)
        do { try WorkspaceImport.perform(urls: [source, bad], type: "ASE", reference: false, target: alpha, allowBucket: true, store: store); check(false, "invalid batch rejected") }
        catch { check(try Data(contentsOf: store.url) == before, "invalid batch creates neither a bucket nor a partial import") }
        do {
            try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, target: alpha, allowBucket: true, store: store, fault: { point in
                if point == "before-commit" { throw failure("Injected commit failure") }
            })
            check(false, "interrupted import rolls back")
        } catch {
            check(try Data(contentsOf: store.url) == before && ASERegistry.resolved(store.root).isEmpty, "failed commit rolls back the new schema bucket, ASE copy and both indexes")
        }
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, target: alpha, allowBucket: true, store: store)
        _ = try store.load()
        check(store.schema.stacks?[a.uuidString] != nil && store.schema.stacks?[b.uuidString] == nil && store.schema.collections[0].stack == tree, "confirmed ASE bucket changes only the selected branch, not its sibling or master template")
        guard let record = WorkspaceImport.records(store: store).first?.0 else { throw failure("Missing imported ASE index entry.") }
        let copy = try record.url(in: store.root)
        check(try Data(contentsOf: copy) == bytes && copy != source && Data(contentsOf: source) == bytes, "ASE import copies exact bytes into its nested destination without changing the source")
        check(copy.path.contains("Alpha/Artwork/ASE/"), "ASE copy resolves the full nested schema path")
        check(try ASERegistry.resolved(store.root).contains { $0.url == copy }, "ASE registry opens files stored in schema buckets")
        // Link the original into another branch. No source move, conversion or duplication.
        let beta = choices.first { $0.member == b && $0.parent == nested.id }!
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: true, target: beta, allowBucket: true, store: store)
        let linked = WorkspaceImport.records(store: store).first { $0.0.external }!.0
        check(try linked.path == source.path && Data(contentsOf: source) == bytes, "Add Reference retains the original location and bytes in the catalogue index")
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: true, target: beta, allowBucket: false, store: store)
        check(WorkspaceImport.records(store: store).filter { $0.0.external }.count == 1, "re-adding the same reference to one bucket does not duplicate it")
        try WorkspaceImport.changeReference(linked, index: store.url, replacement: nil, store: store)
        check(try !ASERegistry.resolved(store.root).contains { $0.url == source } && Data(contentsOf: source) == bytes, "removing a reference detaches its ASE connection without deleting source bytes")
        let moving = root.appendingPathComponent("Moving.ase")
        try Handler_File_Manager.shared.publishRaw(bytes, to: moving)
        try WorkspaceImport.perform(urls: [moving], type: "ASE", transfer: .move, targets: [alpha,beta], allowBucket: true, store: store)
        let moved=WorkspaceImport.records(store: store).filter{$0.0.name == "Moving"}
        check(!FileManager.default.fileExists(atPath:moving.path) && moved.count == 2 && moved.allSatisfy{(try? Data(contentsOf:$0.0.url(in:$0.1.deletingLastPathComponent()))) == bytes}, "Move imports every selected destination before removing the original")
        let rollbackSource=root.appendingPathComponent("Rollback-Move.ase")
        try Handler_File_Manager.shared.publishRaw(bytes,to:rollbackSource)
        do {
            try WorkspaceImport.perform(urls:[rollbackSource],type:"ASE",transfer:.move,targets:[alpha],allowBucket:true,store:store,fault:{point in if point == "before-commit"{throw failure("Injected move failure")}})
            check(false,"interrupted Move reports a failure")
        } catch {
            check(try Data(contentsOf:rollbackSource) == bytes && !WorkspaceImport.records(store:store).contains{$0.0.name == "Rollback-Move"},"failed Move restores the original and rolls back imported copies")
        }
        let css = root.appendingPathComponent("Brand.css")
        try Handler_File_Manager.shared.publishRaw(Data(":root {\n  --red: #FF0000;\n}".utf8), to: css)
        let paletteTarget = paletteChoices.first { $0.member == a && $0.bucket != nil }!
        try WorkspaceImport.perform(urls: [css], type: "Palettes", reference: false, target: paletteTarget, allowBucket: false, store: store)
        try WorkspaceImport.perform(urls: [css], type: "Palettes", reference: false, target: paletteTarget, allowBucket: false, store: store)
        let imported = try store.load().swatches.filter { $0.projectID == a }
        check(imported.count == 2 && imported.allSatisfy { $0.bucketID == paletteTarget.bucket } && Set(imported.map(\.name)).count == 2, "palette imports make independent named copies in the chosen bucket")
        let collectionA=try AssetCollections.create("Proof Set",in:store)
        let collectionB=try AssetCollections.create("Client Review",in:store)
        try AssetCollections.edit(collectionA,name:"Proof Set",colour:"#4285F4",in:store)
        check(AssetCollections.list(in:store).first{$0.id == collectionA}?.colour == "#4285F4","Collection swatch colour persists in .colcat")
        try AssetCollections.reorderCollections([collectionB,seeded[0].id,collectionA],in:store)
        check(AssetCollections.list(in:store).map(\.id) == [collectionB,seeded[0].id,collectionA],"Collection drag order persists in .colcat")
        let collected=AssetCollectionItem.palette(imported[0].id,name:imported[0].name)
        try AssetCollections.add([collected],to:collectionA,in:store)
        try AssetCollections.add([collected],to:collectionB,in:store)
        try store.save(try store.load())
        check(AssetCollections.list(in:store).filter{$0.items.contains(collected)}.count == 2,"one asset can belong to multiple Collections saved in .colcat")
        try AssetCollections.remove(collected,from:collectionA,in:store)
        check(AssetCollections.list(in:store).first{$0.id == collectionB}?.items.contains(collected) == true,"removing one membership leaves the other Collection intact")
        var doomedID=UUID()
        _ = try store.mutate { lib in
            doomedID=lib.createSwatch(named:"Delete Me",hexes:["#173B5D"])
            lib.setFavourite(doomedID,true)
        }
        let doomed=AssetCollectionItem.palette(doomedID,name:"Delete Me")
        try AssetCollections.add([doomed],to:collectionA,in:store)
        try AssetCollections.add([doomed],to:collectionB,in:store)
        _ = try store.mutate{$0.deleteAssignedPalettes([doomedID],removeClaimed:false,catalogue:nil)}
        let afterDeletion=try store.load()
        check(AssetCollections.list(in:store).allSatisfy{!$0.items.contains(doomed)} && !afterDeletion.orderedFavourites.contains(where:{$0.id == doomedID}),
              "deleting a favourite palette removes its membership from every Collection and Favourites")
        let staleCollectionItem=AssetCollectionItem.palette(UUID(),name:"Already Deleted")
        try AssetCollections.add([staleCollectionItem],to:collectionA,in:store)
        try AssetCollections.removeMissingPalettes(in:store,library:try store.load())
        check(AssetCollections.list(in:store).allSatisfy{!$0.items.contains(staleCollectionItem)},"opening Collections repairs older missing-palette memberships")
        var changed = try store.load(); changed.renameProject(a, to: "Renamed")
        try store.save(changed)
        let renamed = WorkspaceImport.records(store: store).first { !$0.0.external }!.0
        check(FileManager.default.fileExists(atPath: try renamed.url(in: store.root).path) && renamed.path.contains("Renamed/"), "owned ASE paths follow a renamed tree branch")
        try WorkspaceImport.perform(urls: [css], type: "Palettes", reference: true, target: .init(title: "My Library", path: "My Library", depth: 0), allowBucket: false, store: store)
        let paletteLink = WorkspaceImport.records(store: store).first { $0.0.type == "Palettes" }!.0
        check(paletteLink.external && paletteLink.path == css.path, "palette reference stores its location without introducing an editable duplicate")
        let sidecar = FileEditAccess.sidecar(for: css)
        check(FileManager.default.fileExists(atPath: sidecar.path), "standard-format references create a colocated .colcar sidecar")
        let sidecarBytes = try Data(contentsOf: sidecar)
        _ = try FileEditAccess.ensure(for: css)
        check(try Data(contentsOf: sidecar) == sidecarBytes, "reimport reuses the existing sidecar without resetting its payload")
        let otherSession = UUID().uuidString
        try FileEditAccess.setEditing(true, source: css, owner: otherSession)
        do { try FileEditAccess.setEditing(true, source: css); check(false, "another session cannot acquire an existing sidecar lock") }
        catch { check(true, "another session cannot acquire an existing sidecar lock") }
        do { try FileEditAccess.setEditing(false, source: css); check(false, "another session cannot release an existing sidecar lock") }
        catch { check(true, "another session cannot release an existing sidecar lock") }
        do { try Handler_File_Manager.shared.publishRaw(Data("changed".utf8), to: css); check(false, "raw asset writes honour sidecar ownership") }
        catch { check(true, "raw asset writes honour sidecar ownership") }
        try FileEditAccess.setEditing(false, source: css, owner: otherSession)
        try FileEditAccess.setEditing(true, source: css)
        try Handler_File_Manager.shared.update(sidecar) { $0["payload"] = ["exposure": 0.5] }
        try FileEditAccess.setEditing(false, source: css)
        _ = try FileEditAccess.ensure(for: css)
        let retainedSidecar = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as! [String: Any]
        check((retainedSidecar["payload"] as? [String: Double])?["exposure"] == 0.5, "sidecar payload survives lock release and subsequent import")
        try FileEditAccess.withGuard(for: css) {
            let gate = css.deletingLastPathComponent().appendingPathComponent("." + css.lastPathComponent + ".colguard")
            check(FileManager.default.fileExists(atPath: gate.path), "ownership transitions hold an exclusive on-disk guard")
        }
        let linkedCSS = try store.load()
        check(linkedCSS.swatch(paletteLink.id)?.entries.count == 1 && !store.linkedPalettes.canEdit(paletteLink.id), "linked files appear as stable palette cards and start locked")
        let native = root.appendingPathComponent("Linked.colpal")
        var original = Library()
        let originalID = original.createSwatch(named: "Linked Original", hexes: ["#112233"])
        try PaletteAssetHandler.store(PaletteAssetHandler.document(original.swatch(originalID)!, in: original, member: nil, file: "Linked"), at: native)
        try WorkspaceImport.perform(urls: [native], type: "Palettes", reference: true, target: .init(title: "My Library", path: "My Library", depth: 0), allowBucket: false, store: store)
        let reference = WorkspaceImport.records(store: store).first { $0.0.path == native.path }!.0
        let baseline = try Data(contentsOf: native)
        _ = try store.load()
        do { _ = try store.mutate { $0.renameSwatch(reference.id, to: "Blocked") }; check(false, "locked reference rejects rename") }
        catch { check(try Data(contentsOf: native) == baseline, "locked reference rejects rename without changing the source") }
        do { _ = try store.mutate { $0.activeSwatchID = reference.id }; check(false, "locked reference rejects picker targeting") }
        catch { check(true, "locked reference rejects picker targeting") }
        try FileEditAccess.setEditing(true, source: native, owner: otherSession)
        do { try store.linkedPalettes.setEditing(true, id: reference.id); check(false, "native metadata prevents another session from unlocking") }
        catch { check(true, "native metadata prevents another session from unlocking") }
        try FileEditAccess.setEditing(false, source: native, owner: otherSession)
        try store.linkedPalettes.setEditing(true, id: reference.id)
        let edited = try store.mutate { value in
            value.renameSwatch(reference.id, to: "Linked Edited")
            _ = value.add(["#445566"], toSwatch: reference.id)
            PaletteAssetHandler.setRating(4, on: reference.id, in: &value)
            value.activeSwatchID = reference.id
        }
        let saved = try PaletteAssetHandler.read(native)
        check(saved.palette.id == originalID && saved.palette.name == "Linked Edited" && saved.palette.entries.count == 2 && saved.palette.review?.rating == 4, "unlocked edits update the original palette and retain its native identity")
        check(edited.swatch(reference.id)?.name == "Linked Edited" && edited.activeSwatchID == reference.id, "linked palette edits and picker target survive model reload")
        let owned = try CatalogueTree.read(root: store.root).library
        check(owned.swatch(reference.id) == nil && !owned.colours.contains { $0.hex == "#445566" }, "saving a linked palette creates neither an owned palette copy nor orphan source colours")
        let savedBytes = try Data(contentsOf: native)
        do {
            try Handler_File_Manager.shared.withTransaction(home: store.root, fault: { if $0 == "before-commit" { throw failure("Injected reference failure") } }) {
                _ = try store.mutate { $0.renameSwatch(reference.id, to: "Rolled Back") }
            }
            check(false, "linked transaction fault rolls back")
        } catch { check(try Data(contentsOf: native) == savedBytes, "catalogue transaction failure rolls back the external source too") }
        var stale = try store.load()
        stale.renameSwatch(reference.id, to: "Stale Edit")
        var external = try PaletteAssetHandler.read(native); external.palette.name = "External Edit"
        try PaletteAssetHandler.store(external, at: native)
        do { try store.save(stale); check(false, "concurrent external change rejected") }
        catch { check(try PaletteAssetHandler.read(native).palette.name == "External Edit", "a stale linked edit never overwrites an external file change") }
        _ = try store.load()
        try store.linkedPalettes.setEditing(false, id: reference.id)
        check(try store.load().activeSwatchID != reference.id && !store.linkedPalettes.canEdit(reference.id), "relocking disables edits and picker targeting")
        try FileManager.default.removeItem(at: native)
        let offline = try store.load()
        check(offline.swatch(reference.id) != nil && offline.swatch(reference.id)?.entries.isEmpty == true && store.linkedPalettes.sources[reference.id]?.problem != nil, "offline references keep a recoverable card without stale proof colours")

    } catch { check(false, "workspace import: " + error.localizedDescription) }
}

func runWorkspaceImportBatchTests(check: (Bool, String) -> Void) {
    print("Workspace import tree and multiple destinations")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Colorgain-Import-Batch-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let store = LibraryStore(directory: root.appendingPathComponent("Catalogue"), legacyURL: nil)
        var library = Library()
        let a = library.createProject(named: "Same Name"), b = library.createProject(named: "Other Owner")
        let paletteBucket = SchemaNode(name: "Brand Colours", role: .palettes)
        let artwork = SchemaNode(name: "Artwork", children: [paletteBucket])
        let photography = SchemaNode(name: "Pictures", kind: "Photography")
        let tree = SchemaNode(name: "Owner", children: [artwork, photography, SchemaNode(name: "Assets", kind: "Assets")])
        let first = SchemaCollection(name: "Clients", stack: tree)
        let second = SchemaCollection(name: "Own Work", stack: SchemaNode(name: "Job", children: [SchemaNode(name: "Photography", kind: "Photography")]))
        let schema = SchemaTrial.SchemaFile(collections: [first, second], places: [a.uuidString: .init(collection: first.id), b.uuidString: .init(collection: second.id)])
        try store.save(library, schema: schema)
        library = try store.load()
        let choices = WorkspaceImport.destinations(library: library, schema: schema, type: "ASE")
        let roots = WorkspaceImport.destinationTree(choices)
        check(roots.count == 4 && roots[0].children.first?.destination.member == a && roots[1].children.first?.destination.member == b && roots[2].destination.title == "My Library" && roots[3].destination.title == "Custom Folders", "destination tree preserves owners, My Library and browsable disk folders")
        check(!choices.contains { $0.customPath == nil && ["Pictures", "Assets", "Brand Colours"].contains($0.title) }, "import tree hides irrelevant typed leaves and implicit asset buckets")
        let paletteChoices = WorkspaceImport.destinations(library: library, schema: schema, type: "Palettes")
        check(paletteChoices.first { $0.parent == artwork.id }?.bucket == paletteBucket.id, "type-filtered tree keeps the actual parent of a renamed palette bucket")
        check(!paletteChoices.contains { $0.customPath == nil && ["Pictures", "Assets"].contains($0.title) } && paletteChoices.contains { $0.title == "Brand Colours" }, "palette destination tree shows the palette branch without unrelated asset types")
        let targets = [choices.first { $0.member == a && $0.parent == tree.id }!, choices.first { $0.member == b }!]
        let source = root.appendingPathComponent("Batch.ase")
        let bytes = ExportFormat.ase.data([ExportPalette(name: "Red", colours: [.init(name: "Red", hex: "#FF0000")])])!
        try Handler_File_Manager.shared.publishRaw(bytes, to: source)
        let before = try Data(contentsOf: store.url)
        do {
            try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, targets: targets, allowBucket: true, store: store, fault: { if $0 == "before-commit" { throw failure("Batch rollback") } })
            check(false, "multi-destination failure must roll back")
        } catch {
            check(try Data(contentsOf: store.url) == before && ASERegistry.resolved(store.root).isEmpty && WorkspaceImport.records(store: store).isEmpty, "failed multi-destination import rolls back all buckets, copies and indexes")
        }
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, targets: targets + [targets[0]], allowBucket: true, store: store)
        let copied = WorkspaceImport.records(store: store).map(\.0)
        check(copied.count == 2 && Set(copied.compactMap(\.member)) == Set([a,b]), "multi-destination copies reach each owner exactly once")
        check(try copied.allSatisfy { try Data(contentsOf: $0.url(in: store.root)) == bytes } && Data(contentsOf: source) == bytes, "every ASE destination receives exact bytes and the original is unchanged")
        _ = try store.load()
        check(store.schema.stacks?.count == 2 && store.schema.collections == schema.collections, "batch bucket creation preserves both shared schema templates")
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: true, targets: targets, allowBucket: false, store: store)
        try WorkspaceImport.perform(urls: [source], type: "ASE", reference: true, targets: targets, allowBucket: false, store: store)
        check(WorkspaceImport.records(store: store).filter { $0.0.external }.count == 2, "batch references retain one link per destination without duplicate originals")
        let native = root.appendingPathComponent("Palette.colpal")
        var original = Library()
        let id = original.createSwatch(named: "Source", hexes: ["#112233"])
        try PaletteAssetHandler.store(PaletteAssetHandler.document(original.swatch(id)!, in: original, member: nil, file: "Source"), at: native)
        let paletteTargets = [paletteChoices.first { $0.member == a && !$0.heading && $0.bucket == paletteBucket.id }!,paletteChoices.first { $0.member == b && !$0.heading }!]
        try WorkspaceImport.perform(urls: [native], type: "Palettes", reference: false, targets: paletteTargets, allowBucket: true, store: store)
        let palettes = try store.load().swatches.filter { $0.projectID == a || $0.projectID == b }
        check(palettes.count == 2 && Set(palettes.map(\.id)).count == 2 && palettes.allSatisfy { $0.id != id && $0.bucketID != nil }, "batch native palettes have independent identities and correct destination buckets")
        let paletteFolder=root.appendingPathComponent("Palette Destination",isDirectory:true)
        try FileManager.default.createDirectory(at:paletteFolder,withIntermediateDirectories:true)
        let diskTarget=WorkspaceImport.diskDestination(paletteFolder)
        try WorkspaceImport.perform(urls:[native],type:"Palettes",transfer:.copy,targets:[diskTarget],allowBucket:false,store:store)
        let diskCopy=paletteFolder.appendingPathComponent(native.lastPathComponent)
        let diskRecord=WorkspaceImport.records(store:store).first{$0.0.path == diskCopy.path}?.0
        check(try diskRecord?.external == true && PaletteAssetHandler.read(diskCopy).palette == PaletteAssetHandler.read(native).palette,"palette copy writes the same palette to a selected Custom Folder and indexes its physical path")
        let rename=WorkspaceImport.Renaming(enabled:true,template:.customSequence,customName:"Brand",startNumber:7)
        try WorkspaceImport.perform(urls:[native],type:"Palettes",transfer:.copy,targets:[diskTarget],allowBucket:false,store:store,rename:rename)
        let renamed=paletteFolder.appendingPathComponent("Brand-007.colpal")
        check(try PaletteAssetHandler.read(renamed).palette == PaletteAssetHandler.read(native).palette,"file renaming adds a zero-padded sequence while preserving the original extension and palette")
        let importCollection=try AssetCollections.create("Import Review",in:store)
        let collectedRename=WorkspaceImport.Renaming(enabled:true,template:.customSequence,customName:"Review",startNumber:9)
        try WorkspaceImport.perform(urls:[native],type:"Palettes",transfer:.copy,targets:[diskTarget],allowBucket:false,store:store,rename:collectedRename,collectionID:importCollection)
        let collectedPath=paletteFolder.appendingPathComponent("Review-009.colpal").path
        let collectedRecord=WorkspaceImport.records(store:store).first{$0.0.path == collectedPath}?.0
        check(AssetCollections.list(in:store).first{$0.id == importCollection}?.items.contains(where:{$0.identity == collectedRecord?.id.uuidString}) == true,"Import adds its successful asset identity to the chosen Collection")
        try WorkspaceImport.perform(urls:[native],type:"Palettes",transfer:.move,targets:[diskTarget],allowBucket:false,store:store,rename:rename,skipExisting:true)
        check(FileManager.default.fileExists(atPath:native.path) && !FileManager.default.fileExists(atPath:paletteFolder.appendingPathComponent("Brand-007 2.colpal").path),"skipping an existing destination never deletes the move source")
        do {
            try WorkspaceImport.perform(urls:[native],type:"Palettes",transfer:.reference,targets:[diskTarget],allowBucket:false,store:store)
            check(false,"Custom Folders cannot silently accept a Reference with no physical drop")
        } catch {check(FileManager.default.fileExists(atPath:native.path),"rejected Custom Folder reference leaves the original intact")}
        let snapshot = try Data(contentsOf: store.url)
        var stale = targets[1]; stale.parent = UUID()
        do {
            try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, targets: [targets[0], stale], allowBucket: true, store: store)
            check(false, "stale second destination rejected")
        } catch { check(try Data(contentsOf: store.url) == snapshot, "a stale destination cannot partially import into earlier selections") }
        do {
            try WorkspaceImport.perform(urls: [source], type: "ASE", reference: false, targets: [choices.first { $0.heading }!], allowBucket: true, store: store)
            check(false, "collection headings cannot receive files")
        } catch { check(try Data(contentsOf: store.url) == snapshot, "heading selection never redirects files to My Library") }
        let imageBytes=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2sAAAAASUVORK5CYII=")!
        let copiedImage=root.appendingPathComponent("Copy.png")
        let movedImage=root.appendingPathComponent("Move.png")
        let linkedImage=root.appendingPathComponent("Link.png")
        for url in [copiedImage,movedImage,linkedImage]{try imageBytes.write(to:url)}
        _ = try WorkspaceImport.addImages([copiedImage],destination:.catalogue(member:a,bucket:photography.id),kind:"Photographs",transfer:.copy,store:store,collectionID:importCollection)
        _ = try WorkspaceImport.addImages([movedImage],member:a,bucket:photography.id,kind:"Photographs",transfer:.move,store:store)
        _ = try WorkspaceImport.addImages([linkedImage],member:b,bucket:second.stack.children[0].id,kind:"Photographs",transfer:.reference,store:store)
        let imageRecords=WorkspaceImport.records(store:store).map(\.0).filter{$0.type == "Photographs"}
        check(imageRecords.count == 3 && imageRecords.filter{!$0.external}.count == 2 && imageRecords.filter{$0.external}.count == 1,"Image import records copy, move and reference as distinct ownership choices")
        check(AssetCollections.list(in:store).first{$0.id == importCollection}?.items.contains(where:{item in imageRecords.contains{$0.id.uuidString == item.identity}}) == true,"Image Import adds its new record to the chosen Collection")
        check(try Data(contentsOf:copiedImage) == imageBytes && !FileManager.default.fileExists(atPath:movedImage.path) && Data(contentsOf:linkedImage) == imageBytes,"Copy and reference retain originals; move removes only its selected source")
        check(try imageRecords.filter{!$0.external}.allSatisfy{try Data(contentsOf:$0.url(in:store.root)) == imageBytes},"Copied and moved images retain exact bytes in their chosen folders")
        let linkedRecord=imageRecords.first{$0.external && $0.path == linkedImage.path}!
        try AssetCollections.add([AssetCollectionItem.imported(linkedRecord)],to:importCollection,in:store)
        try WorkspaceImport.changeReference(linkedRecord,index:store.url,replacement:nil,store:store)
        check(!WorkspaceImport.records(store:store).contains(where:{$0.0.id == linkedRecord.id}) &&
              AssetCollections.list(in:store).allSatisfy{$0.items.allSatisfy{$0.identity != linkedRecord.id.uuidString}} &&
              FileManager.default.fileExists(atPath:linkedImage.path),
              "removing an imported reference clears its Collection membership and preserves the source file")
        let outside=root.appendingPathComponent("External Images",isDirectory:true)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
        let customSource=root.appendingPathComponent("Custom.png")
        try imageBytes.write(to:customSource)
        _ = try WorkspaceImport.addImages([customSource],destination:.custom(outside),kind:"Photographs",transfer:.copy,store:store)
        let custom=WorkspaceImport.records(store:store).map(\.0).first{$0.path.hasPrefix(outside.path)}
        check(custom?.external == true && custom?.member == nil && custom?.path.hasSuffix("Custom.png") == true && FileManager.default.fileExists(atPath:outside.appendingPathComponent("Custom.png").path),"custom disk destinations are tracked by the active catalogue while retaining the chosen physical folder")
    } catch { check(false, "workspace import batch: " + error.localizedDescription) }
}
