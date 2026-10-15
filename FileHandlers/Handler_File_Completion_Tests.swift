import Foundation
import Darwin

func runFileHandlerCompletionTests(check: (Bool, String) -> Void) {
    print("File handler completion safety gates")
    do {
        let fixture = try FileHandlerFixture()
        defer { fixture.remove() }
        let manager = Handler_File_Manager.shared
        let outside = fixture.root.deletingLastPathComponent().appendingPathComponent("Colorgain-Outside-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = fixture.root.appendingPathComponent("Outside Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        check((try? Handler_File_Manager.contained("Outside Link/Missing.colpal", under: fixture.root)) == nil, "A missing leaf below an escaping symbolic link cannot pass containment")
        try FileManager.default.removeItem(at: link)
        check((try? Handler_File_Manager.contained("Missing Folder/Missing.colpal", under: fixture.root)) != nil, "A genuinely missing owned descendant remains a valid reference for recovery")
        check(FileIssue.wrapping(NSError(domain: NSPOSIXErrorDomain, code: 19), at: fixture.root).state == .volumeUnavailable, "A device-unavailable error remains distinct from an ordinary missing file")
        let before = try FileHandlerFixture.snapshot(fixture.root)
        let store = LibraryStore(directory: fixture.first, legacyURL: nil, assetsHome: fixture.root)
        _ = try store.load()
        check(try FileHandlerFixture.snapshot(fixture.root) == before, "Opening an existing catalogue is byte-identical and performs no reconciliation writes")
        let bytes = try Data(contentsOf: fixture.palette)
        let backup = fixture.root.appendingPathComponent("Backup.colpal")
        try bytes.write(to: backup)
        let id = try PaletteAssetHandler.read(bytes).palette.id.uuidString
        try FileManager.default.removeItem(at: fixture.palette)
        try manager.restoreOwnedFile(at: fixture.palette, from: backup, expectedIdentity: id, revision: FileRevision(digest: nil), workspace: fixture.root)
        check(try PaletteAssetHandler.read(fixture.palette).palette.id.uuidString == id, "Explicit file recovery validates and restores the referenced palette identity")
        let restored = try Data(contentsOf: fixture.palette)
        do { try manager.restoreOwnedFile(at: fixture.palette, from: backup, expectedIdentity: UUID().uuidString, revision: FileRevision.read(fixture.palette), workspace: fixture.root) } catch {}
        check(try Data(contentsOf: fixture.palette) == restored, "A wrong-identity backup cannot replace the current file")
        let plan = try manager.prepareCatalogueRemoval(name: "First", catalogues: Catalogues(root: fixture.root, legacyURL: nil))
        let cancellation = FileOperationCancellation(); cancellation.cancel()
        let retained = try FileHandlerFixture.snapshot(fixture.root)
        do { try manager.executeCatalogueRemoval(plan, outcome: .detach, cancellation: cancellation) } catch {}
        check(try FileHandlerFixture.snapshot(fixture.root) == retained, "Cancellation before catalogue removal preserves every workspace file")
        let destination = fixture.root.deletingLastPathComponent().appendingPathComponent("Colorgain-Relocation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        try Catalogues.relocateHome(from: fixture.root, to: destination)
        let relocated = Catalogues(root: destination, legacyURL: nil)
        check(relocated.registry.contains { $0.name == "First" && $0.path.hasPrefix(destination.resolvingSymlinksInPath().path) }, "Verified workspace relocation rebases internal catalogue references")
        check(try PaletteAssetHandler.read(fixture.palette).palette.id.uuidString == id, "Relocation retains the source workspace as a recovery copy")
        check(try relocated.store(for: "First").load().swatches.count == 2, "The relocated workspace reopens with its original native assets")
        let finderFolder = fixture.first.appendingPathComponent("Finder Collection")
        try FileManager.default.createDirectory(at: finderFolder, withIntermediateDirectories: true)
        let reconciliationStore = LibraryStore(directory: fixture.first, legacyURL: nil, assetsHome: fixture.root)
        let index = reconciliationStore.url, indexBefore = try Data(contentsOf: reconciliationStore.url)
        _ = try reconciliationStore.load()
        check(try reconciliationStore.pendingReconciliation != nil && Data(contentsOf: index) == indexBefore, "Finder additions produce an explicit reconciliation plan without writing the index")
        try reconciliationStore.acceptDiskReconciliation()
        check(try reconciliationStore.pendingReconciliation == nil && Data(contentsOf: index) != indexBefore, "Accepting a current reconciliation plan publishes the reviewed structure")
        let lockURL = fixture.root.appendingPathComponent(".colorgain-file-management.lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw failure("Could not open test operation lock") }
        defer { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw failure("Could not lock test workspace") }
        var blocked = false
        do { try manager.withTransaction(home: fixture.root) { try manager.update(AppDataStore(root: fixture.root).url) { $0["unexpected"] = true } } }
        catch { blocked = true }
        let manifestAfterLock = try AppDataStore(root: fixture.root).read()
        check(blocked && manifestAfterLock["unexpected"] == nil, "A competing filesystem lock prevents another operation from publishing")
    } catch { check(false, "Completion safety gates: \(error)") }
}

func runFileHandlerFormatMatrix(check: (Bool, String) -> Void) {
    print("Native format header and future-version matrix")
    do {
        let fixture = try FileHandlerFixture(); defer { fixture.remove() }
        let manager = Handler_File_Manager.shared
        var examples: [String: Data] = [:]
        for (path, bytes) in fixture.before {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            if (try? manager.handler(for: URL(fileURLWithPath: path))) != nil { examples[ext] = bytes }
        }
        let encoder = ColourFiles.encoder()
        let library = try CatalogueTree.read(root: fixture.first).library
        let palette = library.swatches.first { !$0.isTypography }!
        examples["colswatch"] = try encoder.encode(SwatchDocument(palette.entries[0].hex, in: palette.id, of: library)!)
        examples["colprf"] = try encoder.encode(ProfilesDocument(catalogue: fixture.catalogue.id, profiles: []))
        examples["colpro"] = try encoder.encode(SavedPrintProfiles.Exchange(profile: SavedPrintProfile(name: "Matrix", description: "Fixture", settings: PrintProfileSettings())))
        let reference = ProofDataset(name: "Fixture", source: "Test", sha256: "Fixture", metadata: [:], patches: [ProofPatch(id: "A", name: "A", l: 50, a: 0, b: 0)])
        examples["colcal"] = try JSONEncoder().encode(ProofConfiguration(name: "Fixture", session: ProofSession(reference: reference, options: ProofOptions())))
        examples["colqr"] = try ColourQR.data(ColourQR.Document(type: "palette", name: "Fixture", colours: [.init(name: "A", source: .init(space: "xyz", values: [0.1, 0.2, 0.3]), master: XYZ(x: 0.1, y: 0.2, z: 0.3), kind: .surface)]))
        examples["colmanifest"] = try encoder.encode(ShareManifest(level: .catalogue, exportedAt: Date(), catalogue: .init(id: fixture.catalogue.id, name: "First"), subject: .init(id: fixture.catalogue.id, name: "First"), files: []))
        let plistURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let plist = Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] != nil ? Bundle.main.infoDictionary! : (try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any])
        let declarations = plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        var owners: [String: Int] = [:]
        for declaration in declarations {
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any] ?? [:]
            for ext in tags["public.filename-extension"] as? [String] ?? [] { owners[ext, default: 0] += 1 }
        }
        for ext in manager.descriptors.flatMap(\.extensions) where ext != "colmanifest" { check(owners[ext] == 1, "Finder has one canonical declaration for .\(ext)") }
        let directory = fixture.root.appendingPathComponent("Matrix")
        try manager.createDirectory(directory)
        for descriptor in manager.descriptors {
            let ext = descriptor.extensions[0]
            let sampleExt = descriptor.archive ? "colmanifest" : ext
            guard let bytes = examples[sampleExt] else { check(false, "No fixture for \(descriptor.name)"); continue }
            let native = try manager.documentBytes(bytes, extension: sampleExt)
            let object = try JSONSerialization.jsonObject(with: native) as! [String: Any]
            check((object["header"] as? [String: Any])?["lastSavedWith"] != nil, "\(descriptor.name) carries application/version/date/creator metadata")
            let file = directory.appendingPathComponent(sampleExt + "." + sampleExt)
            try manager.write(native, to: file, createOnly: true)
            let original = try Data(contentsOf: file)
            var future = object; future["version"] = 999
            do { try manager.write(JSONSerialization.data(withJSONObject: future), to: file) } catch {}
            check(try Data(contentsOf: file) == original, "\(descriptor.name) rejects future versions without changing the original")
        }
    } catch { check(false, "Native format matrix: \(error)") }
}
