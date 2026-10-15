import Foundation

func runFileCatalogueLifecycleTests(check: (Bool, String) -> Void) {
    print("Catalogue retention, archive and transfer plans")
    let fm = FileManager.default, manager = Handler_File_Manager.shared
    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let catalogues = Catalogues(root: fixture.root, legacyURL: nil)
        let plan = try manager.prepareCatalogueRemoval(name: "First", catalogues: catalogues)
        check(plan.canTransfer && plan.verified["Palettes"] == 1 && plan.verified["Typography Palettes"] == 1, "Removal inventory distinguishes verified palette and typography counts")
        let originalFiles = try FileHandlerFixture.snapshot(fixture.first)
        try manager.executeCatalogueRemoval(plan, outcome: .detach)
        check(try FileHandlerFixture.snapshot(fixture.first) == originalFiles, "Detach leaves every source catalogue byte in place")
        let detachedInventory = try WorkspaceInventory.read(root: fixture.root)
        check(!catalogues.names().contains("First") && !detachedInventory.catalogues.contains { $0.name == "First" }, "Detached catalogue stays out of registry and disk discovery")
        let movedDetached = catalogues.folder.appendingPathComponent("Moved Detached Catalogue")
        try fm.moveItem(at: fixture.first, to: movedDetached)
        check(try !catalogues.names().contains("Moved Detached Catalogue") && !WorkspaceInventory.read(root: fixture.root).catalogues.contains { $0.id == fixture.catalogue.id }, "A detached catalogue stays detached after a Finder rename because its UUID is excluded")
        try fm.moveItem(at: movedDetached, to: fixture.first)
        try catalogues.registerChecked("First", at: fixture.first)
        check(catalogues.names().contains("First") && catalogues.registry.first { $0.name == "First" }?.id == fixture.catalogue.id, "Explicit reattachment restores the same catalogue identity")

        let stale = try manager.prepareCatalogueRemoval(name: "First", catalogues: catalogues)
        let added = fixture.first.appendingPathComponent("Keep Me.txt")
        try Data("unrelated original".utf8).write(to: added)
        do { try manager.executeCatalogueRemoval(stale, outcome: .detach); check(false, "Stale inventory rejected") }
        catch { check(catalogues.names().contains("First"), "New files invalidate a reviewed removal plan without detaching") }
        let archivePlan = try manager.prepareCatalogueRemoval(name: "First", catalogues: catalogues)
        let archive = fixture.root.appendingPathComponent("Retained.colshr")
        try manager.executeCatalogueRemoval(archivePlan, outcome: .archive(archive))
        check(try Sharing.inspect(archive).ok, "Archive is verified against its checked share manifest before detachment")
        check(try FileHandlerFixture.snapshot(fixture.first)["Keep Me.txt"] == Data("unrelated original".utf8), "Archive and detach preserve unrelated source files")
        let inspection = try Sharing.inspect(archive)
        let staging = try Sharing.stage(inspection); defer { Sharing.discard(staging) }
        let restored = try Sharing.read(staging: staging, level: .catalogue)
        check(restored.library.swatches.count == 2 && restored.aseLinks.count == 1, "Removal archive can be reopened with native assets and portable ASE links")
    } catch { check(false, "Catalogue detach/archive: \(error)") }
    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let catalogues = Catalogues(root: fixture.root, legacyURL: nil)
        let plan = try manager.prepareCatalogueRemoval(name: "First", catalogues: catalogues)
        try manager.executeCatalogueRemoval(plan, outcome: .transfer(target: "Retained Work", create: true))
        let target = catalogues.store(for: "Retained Work")
        let content = try target.load()
        check(content.swatches.count == 2 && content.projects.count == 1, "Transfer to a new catalogue retains native palettes, typography and member records")
        check(target.schema.collections.count >= 2, "Transfer preserves the source schema alongside the destination schema")
        check(fm.fileExists(atPath: fixture.palette.path) && !catalogues.names().contains("First"), "Transfer detaches only after destination verification and retains source originals")
        let archives = try fm.contentsOfDirectory(at: target.root.appendingPathComponent("Library/Archives"), includingPropertiesForKeys: nil)
        let archiveOK = archives.count == 1 ? try Sharing.inspect(archives[0]).ok : false
        check(archiveOK, "Transfer retains history and other source files in a verified destination archive")
    } catch { check(false, "Catalogue transfer: \(error)") }
    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let unknown = fixture.first.appendingPathComponent("Unowned Image.png")
        try Data("external artwork fixture".utf8).write(to: unknown)
        let catalogues = Catalogues(root: fixture.root, legacyURL: nil)
        let plan = try manager.prepareCatalogueRemoval(name: "First", catalogues: catalogues)
        let before = try FileHandlerFixture.snapshot(fixture.first)
        var fs = FileSystemAccess()
        fs.trash = { try fm.removeItem(at: $0) } // Isolated fake Bin, never the user's Trash.
        fs.write = { data, url in
            if url.lastPathComponent == "colorgain.coldata" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        do { try Handler_File_Manager(filesystem: fs).executeCatalogueRemoval(plan, outcome: .binOwnedFiles); check(false, "Failed registration finalization reported") }
        catch { check(try FileHandlerFixture.snapshot(fixture.first) == before, "Failed finalization restores all files moved by the operation") }
        check(catalogues.names().contains("First") && fm.fileExists(atPath: unknown.path), "Bin/finalization failure retains registration and unowned artwork")
    } catch { check(false, "Catalogue Bin failure: \(error)") }
    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let cats = Catalogues(root: fixture.root, legacyURL: nil)
        let original = try FileHandlerFixture.snapshot(fixture.root)
        let cancelled = fixture.root.appendingPathComponent("Cancelled.colshr")
        let cancellation = FileOperationCancellation()
        var fs = FileSystemAccess()
        fs.write = { bytes, url in try bytes.write(to: url, options: .atomic); if url.resolvingSymlinksInPath() == cancelled.resolvingSymlinksInPath() { cancellation.cancel() } }
        let plan = try manager.prepareCatalogueRemoval(name: "First", catalogues: cats)
        do { try Handler_File_Manager(filesystem: fs).executeCatalogueRemoval(plan, outcome: .archive(cancelled), cancellation: cancellation) } catch {}
        check(try FileHandlerFixture.snapshot(fixture.root) == original, "Cancellation after archive publication rolls back output and retains catalogue registration")
        var bin = FileSystemAccess(); bin.trash = { try fm.removeItem(at: $0) }
        let binPlan = try manager.prepareCatalogueRemoval(name: "First", catalogues: cats)
        try Handler_File_Manager(filesystem: bin).executeCatalogueRemoval(binPlan, outcome: .binOwnedFiles)
        check(!cats.names().contains("First") && binPlan.ownedFiles.allSatisfy { !fm.fileExists(atPath: $0.path) }, "A successful owned-file Bin outcome finalizes registration after removing only planned files")
        check(fm.fileExists(atPath: fixture.root.appendingPathComponent("External/Linked.ase").path), "Successful Bin retains externally linked ASE originals")
        let last = try manager.prepareCatalogueRemoval(name: "Second", catalogues: cats)
        try manager.executeCatalogueRemoval(last, outcome: .detach)
        check(cats.names().isEmpty, "Detaching the last catalogue leaves an empty workspace without inventing Main")
    } catch { check(false, "Catalogue cancellation, Bin and final entry: \(error)") }

    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let cats = Catalogues(root: fixture.root, legacyURL: nil)
        let diskBefore = try FileHandlerFixture.snapshot(fixture.first)
        try AppDataStore(root: fixture.root).update { manifest in
            var rows = manifest["catalogues"] as! [[String: Any]]
            let index = rows.firstIndex { $0["name"] as? String == "First" }!
            rows[index]["id"] = UUID().uuidString; manifest["catalogues"] = rows
        }
        let store = cats.store(for: "First")
        check((try? store.load()) == nil, "A registered UUID mismatch prevents opening another catalogue at the remembered path")
        check((try? store.save(Library())) == nil, "A registered UUID mismatch prevents overwriting the foreign catalogue")
        let removal = try manager.prepareCatalogueRemoval(name: "First", catalogues: cats)
        check(!removal.canTransfer && removal.inventory.issues.contains { $0.state == .identityMismatch }, "A mismatched catalogue permits only a leave-files detach plan")
        var fs = FileSystemAccess(); var binned = false; fs.trash = { _ in binned = true }
        do { try Handler_File_Manager(filesystem: fs).executeCatalogueRemoval(removal, outcome: .binOwnedFiles) } catch {}
        check(try !binned && FileHandlerFixture.snapshot(fixture.first) == diskBefore, "Mismatched catalogue removal never bins or rewrites the disk files")
        let inventory = try WorkspaceInventory.read(root: fixture.root)
        check(inventory.catalogues.first { $0.name == "First" }?.state == .invalid, "Startup exposes registered UUID mismatch as a recovery case")
    } catch { check(false, "Registered identity mismatch: \(error)") }

    do {
        let fixture=try FileHandlerFixture();defer{fixture.remove()}
        let cats=Catalogues(root:fixture.root,legacyURL:nil)
        let before=try FileHandlerFixture.snapshot(fixture.first)
        let manifest=try Data(contentsOf:AppDataStore(root:fixture.root).url)
        let output=fixture.root.appendingPathComponent("Backups/Catalogues/First.colshr")
        try manager.createCatalogueArchive(name:"First",catalogues:cats,to:output)
        check(try FileHandlerFixture.snapshot(fixture.first) == before && Data(contentsOf:AppDataStore(root:fixture.root).url) == manifest,"Catalogue backup/export preserves every original byte and registration")
        check(try manager.handler(for:output).canonical(Data(contentsOf:output)).count > 0,"Catalogue backup/export produces a validated share archive")
        check((try? manager.createCatalogueArchive(name:"First",catalogues:cats,to:output)) == nil,"Catalogue backup/export never overwrites an existing archive")
    } catch {check(false,"Catalogue row archive: \(error)")}

}
