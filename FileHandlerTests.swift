import Foundation

/// All handler tests own their temporary roots. No Catalogues.standard or user bootstrap state.
struct FileHandlerFixture {
    let root: URL
    let first: URL
    let second: URL
    let catalogue: CatalogueFile
    let palette: URL
    let before: [String: Data]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Colorgain-Handlers-" + UUID().uuidString)
        first = root.appendingPathComponent("Catalogues/First")
        second = root.appendingPathComponent("Catalogues/Second")
        try AppHomeSeed.ensure(at: root)
        var library = Library()
        let project = library.createProject(named: "Client", at: Date(timeIntervalSince1970: 1_700_000_000))
        let id = library.createSwatch(named: "Brand", hexes: ["#123456", "#FEDCBA"])
        library.move(id, to: project, index: 0, at: Date(timeIntervalSince1970: 1_700_000_000))
        _ = library.createTypography(named: "Headings", in: project)
        try CatalogueTree.write(library, schema: .fresh, index: first.appendingPathComponent("First.colcat"))
        try CatalogueTree.write(Library(), schema: SchemaTrial.SchemaFile(collections: [], places: [:]), index: second.appendingPathComponent("Second.colcat"))
        let catalogues = Catalogues(root: root, legacyURL: nil)
        try catalogues.registerChecked("First", at: first)
        try catalogues.registerChecked("Second", at: second)
        let external = root.appendingPathComponent("External/Linked.ase")
        try FileManager.default.createDirectory(at: external.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AdobeASE.empty.write(to: external)
        try ASERegistry.write([AppbridgeStore.Source(path: external.path, folder: false)], root: first, name: "First")
        catalogue = CatalogueTree.catalogue(in: first)!
        palette = CatalogueTree.file(ofPalette: id, in: first)!
        before = try Self.snapshot(root)
    }

    static func snapshot(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return files }
        for case let url as URL in walker {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[CatalogueTree.relative(url, to: root)] = try Data(contentsOf: url)
            }
        }
        return files
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

func runFileHandlerBaselineTests(check: (Bool, String) -> Void) {
    print("File handler isolated baseline")
    do {
        let fixture = try FileHandlerFixture()
        defer { fixture.remove() }
        check(fixture.before == (try FileHandlerFixture.snapshot(fixture.root)), "Handler fixture has byte-identical repeatable snapshots")
        check(try CatalogueTree.read(root: fixture.first).library.swatches.count == 2, "Handler fixture covers palette and typography in a member schema")
        check(try CatalogueTree.read(root: fixture.second).schema.collections.isEmpty, "Handler fixture has a distinct empty target schema")
        let registryBefore = try Data(contentsOf: AppDataStore(root: fixture.root).url)
        try FileManager.default.removeItem(at: fixture.palette)
        check((try? CatalogueTree.read(root: fixture.first)) == nil, "The protected tree reader rejects the original missing-palette deletion reproduction")
        check(try Data(contentsOf: AppDataStore(root: fixture.root).url) == registryBefore, "Direct baseline scan does not alter the workspace manifest")
        let filters = MetadataFilterStore(catalogueURL: fixture.first.appendingPathComponent("First.colcat"), appData: AppDataStore(root: fixture.root))
        try FileManager.default.moveItem(at: fixture.first, to: fixture.root.appendingPathComponent("Unavailable"))
        var reports = 0
        for _ in 0..<3 {
            do { _ = try CatalogueTree.read(root: fixture.first) } catch { reports += 1 }
            do { _ = try filters.read(catalogueID: fixture.catalogue.id) } catch { reports += 1 }
        }
        check(reports == 6, "Baseline reproduces repeated parent and filter errors from the same unavailable catalogue")
        check(try Data(contentsOf: AppDataStore(root: fixture.root).url) == registryBefore, "Baseline missing-parent reproduction retains registry bytes")
    } catch { check(false, "Handler baseline: \(error)") }
}

func runFileHandlerManagerTests(check: (Bool, String) -> Void) {
    print("File handler manager, provenance and preservation")
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("Colorgain-Manager-" + UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    do {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = FileMetadataProvider(now: { clock }, identifier: { "fixture-document" },
            application: { FileApplicationIdentity(bundleIdentifier: "test.colorgain", name: "Test", version: "1.2", build: "34") },
            creator: { FileCreatorIdentity(displayName: "Test Creator", accountName: "fixture") })
        let manager = Handler_File_Manager(metadata: metadata)
        check(manager.descriptors.count == 19, "Manager registers one class per native document format")
        do { try manager.register(Handler_File_Palette()); check(false, "Duplicate format registration rejected") }
        catch { check(true, "Duplicate format registration rejected") }
        let unknown = root.appendingPathComponent("unknown.colfuture")
        try Data("untouched".utf8).write(to: unknown)
        let unknownBytes = try Data(contentsOf: unknown)
        check((try? manager.read(unknown)) == nil && unknownBytes == Data("untouched".utf8), "Unknown col types are refused without touching their bytes")
        let url = root.appendingPathComponent("Brand.colpal")
        var lib = Library()
        let id = lib.createSwatch(named: "Brand", hexes: ["#123456", "#654321"])
        var doc = PaletteAssetHandler.document(lib.swatch(id)!, in: lib, member: nil, file: "Brand")
        try manager.write(ColourFiles.encoder().encode(doc), to: url, createOnly: true)
        func object() throws -> [String: Any] { try JSONSerialization.jsonObject(with: manager.read(url)) as! [String: Any] }
        let first = try object()
        let initialHeader = first["header"] as! [String: Any]
        check(initialHeader["documentID"] as? String == id.uuidString && initialHeader["createdAt"] as? String == FileDocumentHeader.stamp(clock), "New palette header carries stable identity and deterministic creation date")
        check((initialHeader["createdBy"] as? [String: Any])?["displayName"] as? String == "Test Creator", "Creator identity is supplied independently of the workspace")
        clock.addTimeInterval(60)
        doc.palette.name = "Edited"
        try manager.write(ColourFiles.encoder().encode(doc), to: url)
        let edited = try object()["header"] as! [String: Any]
        check(edited["createdAt"] as? String == initialHeader["createdAt"] as? String && edited["lastSavedAt"] as? String == FileDocumentHeader.stamp(clock), "Editing retains creation provenance and advances successful-save metadata")
        let beforeNoop = try Data(contentsOf: url)
        clock.addTimeInterval(60)
        try manager.write(ColourFiles.encoder().encode(doc), to: url)
        check(try Data(contentsOf: url) == beforeNoop, "A no-op save does not advance provenance or rewrite bytes")
        var withFuture = try object()
        withFuture["futureRoot"] = ["preserve": true]
        var palette = withFuture["palette"] as! [String: Any]; palette["futureNested"] = "keep"; withFuture["palette"] = palette
        try JSONSerialization.data(withJSONObject: withFuture).write(to: url)
        doc.palette.name = "Edited Again"
        try manager.write(ColourFiles.encoder().encode(doc), to: url)
        let retained = try object()
        check(retained["futureRoot"] != nil && (retained["palette"] as? [String: Any])?["futureNested"] as? String == "keep", "Known edits preserve unknown root and nested document fields")
        var extraColour = try object()
        var records = extraColour["colours"] as! [[String: Any]]
        records[0]["futureColourNote"] = "Keep With This Colour"
        let annotatedKey = records[0]["hex"] as! String
        extraColour["colours"] = records
        try JSONSerialization.data(withJSONObject: extraColour).write(to: url)
        doc.colours.reverse()
        try manager.write(ColourFiles.encoder().encode(doc), to: url)
        let reordered = try object()["colours"] as! [[String: Any]]
        check(reordered.first { $0["hex"] as? String == annotatedKey }?["futureColourNote"] as? String == "Keep With This Colour", "Unknown colour metadata follows stable colour identity when records reorder")
        var copy = doc; copy.palette = Sharing.independentCopy(doc.palette)
        let copiedURL = root.appendingPathComponent("Independent Copy.colpal")
        try manager.write(ColourFiles.encoder().encode(copy), to: copiedURL, createOnly: true)
        let copiedObject = try JSONSerialization.jsonObject(with: manager.read(copiedURL)) as! [String: Any]
        check((copiedObject["header"] as? [String: Any])?["derivedFrom"] as? String == id.uuidString, "An independent palette copy records its source identity without a private path")
        let revision = try FileRevision.read(url)
        var foreign = try object(); foreign["externalEdit"] = true
        try JSONSerialization.data(withJSONObject: foreign).write(to: url)
        let changed = try Data(contentsOf: url)
        do { try manager.write(ColourFiles.encoder().encode(doc), to: url, expected: revision); check(false, "Stale plan is rejected") }
        catch { check(try Data(contentsOf: url) == changed, "Stale plan is rejected without losing external edits") }
        doc.version = 999
        do { try manager.write(ColourFiles.encoder().encode(doc), to: url); check(false, "Unsupported version rejected") }
        catch { check(try Data(contentsOf: url) == changed, "Unsupported version cannot overwrite a valid document") }
        let old = root.appendingPathComponent("Legacy.colpal"); doc.version = 1
        try ColourFiles.encoder().encode(doc).write(to: old)
        doc.palette.name = "Legacy Edit"
        try manager.write(PaletteAssetHandler.data(doc), to: old)
        let oldHeader = (try JSONSerialization.jsonObject(with: manager.read(old)) as! [String: Any])["header"] as! [String: Any]
        check(oldHeader["createdAt"] == nil && oldHeader["createdBy"] == nil && oldHeader["lastSavedAt"] != nil, "The production palette facade saves legacy content without inventing its original creator")
        check((try? Handler_File_Manager.contained("../escape.colpal", under: root)) == nil, "Owned references cannot traverse outside their root")
        let escapeCatalogue:[String:Any]=["libraryAssets":[["id":UUID().uuidString,"file":"../escape.colpal","kind":"palette","name":"Escape"]]]
        check((try? Handler_File_Catalogue().referencesInInspectedTree(escapeCatalogue,at:root.appendingPathComponent("Test.colcat"))) == nil,
              "Fast catalogue reference validation still rejects paths outside its root")
        let decoded = try JSONDecoder().decode(FileDocumentHeader.self, from: JSONSerialization.data(withJSONObject: edited))
        check(decoded.forSharing(includePersonalNames: false).lastSavedBy.accountName == nil && decoded.lastSavedBy.accountName == "fixture", "Share metadata can omit personal names without changing source provenance")
        check(!FileApplicationIdentity.current().version.isEmpty, "Bare binary metadata has an explicit development fallback")
        var failingFS = FileSystemAccess()
        failingFS.write = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        let failingManager = Handler_File_Manager(filesystem: failingFS, metadata: metadata)
        do { try failingManager.write(ColourFiles.encoder().encode(doc), to: url); check(false, "Failed save reported") }
        catch { check(try Data(contentsOf: url) == changed, "Disk-full failure leaves content and saved metadata unchanged") }
    } catch { check(false, "Handler manager: \(error)") }
}
