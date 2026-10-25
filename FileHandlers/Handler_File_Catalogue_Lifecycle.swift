import Foundation

struct FileCatalogueRemovalPlan {
    enum Outcome {
        case detach
        case archive(URL)
        case transfer(target: String, create: Bool, expected: FileRevision? = nil)
        case binOwnedFiles
    }
    let workspace: URL
    let name: String
    let root: URL
    let index: URL
    let identity: UUID?
    let inventory: FileInventory
    let lastKnown: [String: Int]
    let verified: [String: Int]
    let revisions: [String: FileRevision]
    let ownedFiles: [URL]
    let otherFiles: [URL]
    let estimatedBytes: Int64
    var canTransfer: Bool { inventory.complete && identity != nil }
    var summary: String {
        let counts = verified.keys.sorted().map { "\(verified[$0]!) \($0)" }.joined(separator: ", ")
        let known = lastKnown.keys.sorted().map { "\(lastKnown[$0]!) \($0)" }.joined(separator: ", ")
        return "Approximate Unique File Bytes: " + ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file) + "\nVerified On Disk: " + (counts.isEmpty ? "None" : counts) + "\nLast Known In Catalogue: " + (known.isEmpty ? "Unavailable" : known)
            + "\n\(otherFiles.count) other files will remain untouched. Shared global assets and external originals are retained."
    }
}

extension Handler_File_Manager {
    func prepareCatalogueRemoval(name: String, catalogues: Catalogues) throws -> FileCatalogueRemovalPlan {
        let root = catalogues.directory(for: name)
        let index = CatalogueFiles.index(in: root) ?? root.appendingPathComponent(filesystemName(name) + ".colcat")
        var observed = inspectCatalogue(index)
        let registeredID = catalogues.registry.first(where: { $0.name == name })?.id
        let doc = (try? read(index)).flatMap { try? ColourFiles.decoder().decode(CatalogueFile.self, from: $0) }
        if let registeredID, let doc, registeredID != doc.id { observed.issues.append(FileIssue(url: index, state: .identityMismatch, message: "This folder contains a different catalogue. Only detaching this registration and leaving all disk files is available.")) }
        var known: [String: Int] = [:], verified: [String: Int] = [:], owned: [URL] = [], others: [URL] = []
        if let doc {
            let assets = doc.libraryAssets + doc.collections.flatMap { $0.allMembers.flatMap { $0.member.assets } }
            known["Palettes"] = assets.filter { $0.kind == .palette }.count
            known["Typography Palettes"] = assets.filter { $0.kind == .typography }.count
            known["Colours"] = doc.colours.count
            known["Projects"] = doc.collections.reduce(0) { $0 + $1.allMembers.count }
        }
        let protectedHome = root.standardizedFileURL == catalogues.root.standardizedFileURL
        let native: Set<String> = ["colcat", "colpal", "coltyp", "colswa", "colinf", "colprf", "colhis", "colase", "colcal", "coltra", "colnode"]
        let homeItems = protectedHome ? Set(Catalogues.catalogueItems(at: root)) : []
        var revisions: [String: FileRevision] = [AppDataStore(root: catalogues.root).url.path: try FileRevision.read(AppDataStore(root: catalogues.root).url)]
        for file in observed.files {
            let relative = CatalogueTree.relative(file, to: root)
            if protectedHome && !homeItems.contains(String(relative.split(separator: "/").first ?? "")) { continue }
            revisions[file.path] = try FileRevision.read(file)
            let ext = file.pathExtension.lowercased()
            if native.contains(ext) || relative.hasPrefix("Library/ASE/") && ext == "ase" { owned.append(file) }
            else { others.append(file) }
            let label: String
            switch ext {
            case "colpal": label = "Palettes"
            case "coltyp": label = "Typography Palettes"
            case "colswa":
                if let data = try? read(file), let pool = try? ColourFiles.decoder().decode(SwatchesDocument.self, from: data) { verified["Loose Colours", default: 0] += pool.colours.count }
                label = "Loose Colour Files"
            case "colinf": label = "Projects"
            case "colcal": label = "Proof Configurations"
            case "ase": label = "ASE Files"
            case "png", "jpg", "jpeg", "heic", "tif", "tiff", "exr", "psd", "webp", "gif": label = "Image Files"
            default: label = native.contains(ext) ? "Supporting Files" : "Other Files"
            }
            verified[label, default: 0] += 1
        }
        revisions[index.path] = try FileRevision.read(index)
        var identities = Set<String>(), estimatedBytes: Int64 = 0
        for file in owned + others {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let identity = String(describing: attributes[.systemNumber]) + ":" + String(describing: attributes[.systemFileNumber])
            if identities.insert(identity).inserted { estimatedBytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0 }
        }
        return FileCatalogueRemovalPlan(workspace: catalogues.root, name: name, root: root, index: index, identity: registeredID ?? doc?.id,
            inventory: observed, lastKnown: known, verified: verified, revisions: revisions, ownedFiles: owned, otherFiles: others, estimatedBytes: estimatedBytes)
    }

    func validate(_ plan: FileCatalogueRemovalPlan) throws {
        for (path, revision) in plan.revisions where try FileRevision.read(URL(fileURLWithPath: path)) != revision { throw failure("Files changed after the review. Inspect the catalogue again before continuing.") }
        let current = inventory(root: plan.root)
        guard Set(current.files.map { $0.path }) == Set(plan.inventory.files.map { $0.path }), Set(current.folders.map(\.path)) == Set(plan.inventory.folders.map(\.path)) else { throw failure("The catalogue's contents changed after the review.") }
    }

    func detachCatalogue(_ plan: FileCatalogueRemovalPlan) throws {
        try update(AppDataStore(root: plan.workspace).url) { manifest in
            var links = manifest["catalogues"] as? [[String: Any]] ?? []
            links.removeAll { row in
                if let id = plan.identity?.uuidString, row["id"] as? String == id { return true }
                return row["name"] as? String == plan.name
            }
            manifest["catalogues"] = links
            var detached = manifest["detachedCatalogues"] as? [String] ?? []
            if !detached.contains(plan.root.standardizedFileURL.path) { detached.append(plan.root.standardizedFileURL.path) }
            let canonical = plan.root.resolvingSymlinksInPath().path
            if !detached.contains(canonical) { detached.append(canonical) }
            manifest["detachedCatalogues"] = detached
            if let id = plan.identity?.uuidString {
                var ids = manifest["detachedCatalogueIDs"] as? [String] ?? []
                if !ids.contains(id) { ids.append(id) }; manifest["detachedCatalogueIDs"] = ids
            }
            let saved = manifest["defaultCatalogue"] as? [String: Any]
            var settings = manifest["settings"] as? [String: Any] ?? [:]
            if saved?["name"] as? String == plan.name || settings["currentCatalogue"] as? String == plan.name {
                manifest.removeValue(forKey: "defaultCatalogue")
                settings.removeValue(forKey: "currentCatalogue"); settings.removeValue(forKey: "currentCatalogueID")
                manifest["settings"] = settings
            }
            if let id = plan.identity?.uuidString {
                var mirrors = manifest["metadataFiltersByCatalogue"] as? [String: Any] ?? [:]
                mirrors.removeValue(forKey: id); manifest["metadataFiltersByCatalogue"] = mirrors
            }
        }
    }

    func relinkCatalogue(name: String, from oldRoot: URL, to newRoot: URL, workspace: URL) throws {
        guard let index = CatalogueFiles.index(in: newRoot) else { throw failure("The selected folder has no catalogue index.") }
        try requireAvailableCatalogue(index)
        let doc = try ColourFiles.decoder().decode(CatalogueFile.self, from: read(index))
        try update(AppDataStore(root: workspace).url) { manifest in
            var rows = manifest["catalogues"] as? [[String: Any]] ?? []
            if let at = rows.firstIndex(where: { $0["name"] as? String == name }) {
                if let expected = rows[at]["id"] as? String, expected != doc.id.uuidString { throw failure("This is a different catalogue. The original reference has been retained.") }
                rows[at]["path"] = newRoot.path; rows[at]["id"] = doc.id.uuidString
            } else { rows.append(["name": name, "path": newRoot.path, "id": doc.id.uuidString]) }
            manifest["catalogues"] = rows
            manifest["detachedCatalogues"] = (manifest["detachedCatalogues"] as? [String] ?? []).filter { $0 != newRoot.standardizedFileURL.path && $0 != newRoot.resolvingSymlinksInPath().path }
            manifest["detachedCatalogueIDs"] = (manifest["detachedCatalogueIDs"] as? [String] ?? []).filter { UUID(uuidString: $0) != doc.id }
        }
        FileIncidentCoordinator.shared.resolved(oldRoot)
    }

    /// Copies verified source bytes into a standard checked share; never a claim that external
    /// ICC/ASE links or unavailable files were bundled. Incomplete sources cannot take this path.
    func archiveCatalogue(_ plan: FileCatalogueRemovalPlan, to destination: URL, includeShared:Bool=false) throws {
        guard plan.canTransfer, let id = plan.identity else { throw failure("Recover missing files before creating an archive. Detach And Leave Files is still available.") }
        guard !destination.standardizedFileURL.path.hasPrefix(plan.root.standardizedFileURL.path + "/") else { throw failure("Save the archive outside the catalogue being removed.") }
        var entries: [Zip.StreamEntry] = []
        for file in plan.ownedFiles + plan.otherFiles {
            entries.append(Zip.StreamEntry(path: CatalogueTree.relative(file, to: plan.root), file: file))
        }
        var indexed = try JSONSerialization.jsonObject(with: read(plan.index)) as! [String: Any]
        let required = try handler(for: plan.index).references(indexed, at: plan.index).filter { $0.kind != "Folder" }
        let paths = Set(entries.map(\.path))
        guard required.allSatisfy({ reference in paths.contains(CatalogueTree.relative(plan.inventory.relocated[reference.url.path] ?? reference.url, to: plan.root)) }) else { throw failure("The archive inventory does not include every referenced asset. Recover or explicitly relocate the affected files before archiving.") }
        // External image links become owned files in this archive only. The live catalogue
        // continues to point at the originals until the user changes those references.
        if var records = indexed["importedAssets"] as? [[String: Any]] {
            for i in records.indices where records[i]["external"] as? Bool == true {
                let record = try ColourFiles.decoder().decode(WorkspaceImportedAsset.self, from: JSONSerialization.data(withJSONObject: records[i]))
                guard record.type == "Photographs" || record.type == "Images" else { continue }
                let source = try record.url(in: plan.root)
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isDirectory != true, values.isSymbolicLink != true else { throw failure("The linked image is not a regular file: " + record.name) }
                let relative = "Support/Referenced Images/" + record.id.uuidString + "/" + filesystemName(source.lastPathComponent)
                entries.append(.init(path: relative, file: source))
                records[i]["external"] = false
                records[i]["path"] = relative
            }
            indexed["importedAssets"] = records
            let indexPath = CatalogueTree.relative(plan.index, to: plan.root)
            guard let at = entries.firstIndex(where: { $0.path == indexPath }) else { throw failure("The catalogue index is missing from the archive inventory.") }
            entries[at] = .init(path: indexPath, data: try JSONSerialization.data(withJSONObject: indexed, options: .sortedKeys))
        }
        let links = try ASERegistry.read(plan.root).sources
        guard !links.contains(where: { $0.folder }) else { throw failure("This catalogue monitors an ASE folder. Choose individual ASE files in Appbridge before making a portable archive; detaching will preserve the folder link.") }
        let ase = try ASERegistry.harvest(root: plan.root, selected: Set(links.map { $0.id }))
        let replacedPaths = Set(ase.map { $0.path })
        entries.removeAll { $0.path.hasSuffix(".colase") || replacedPaths.contains($0.path) }
        entries += ase.map{.init(path:$0.path,data:$0.data)}
        var sharedStaging:URL?
        defer{if let sharedStaging{try? FileManager.default.removeItem(at:sharedStaging)}}
        if includeShared {
            let shared=try SimpleSharedArchive.prepare(home:plan.workspace)
            sharedStaging=shared.staging
            let sharedIDs=Set(try GlobalAssets(home:plan.workspace).load().swatches.map(\.id))
            var links:[String:String]=[:]
            for record in CatalogueTree.catalogue(in:plan.root)?.importedAssets ?? [] where record.external && record.type == "Palettes" {
                let source=try record.url(in:plan.root)
                if let doc=try? PaletteAssetHandler.read(source),sharedIDs.contains(doc.palette.id){links[record.id.uuidString]=doc.palette.id.uuidString}
            }
            let indexPath=CatalogueTree.relative(plan.index,to:plan.root)
            if let at=entries.firstIndex(where:{$0.path == indexPath}) {
                indexed["sharedAssetReferences"]=links
                entries[at] = .init(path:indexPath,data:try JSONSerialization.data(withJSONObject:indexed,options:.sortedKeys))
            }
            entries.removeAll{$0.path.hasPrefix(SimpleSharedArchive.prefix)}
            entries += shared.entries
        }
        let files=try entries.map { entry -> ShareManifest.File in
            if let data=entry.data{return .init(path:entry.path,bytes:data.count,sha256:Sharing.sha256(data))}
            guard let file=entry.file,let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                  let digest=try FileRevision.read(file).digest else {throw failure("An archive source is unavailable: " + entry.path)}
            return .init(path:entry.path,bytes:size,sha256:digest)
        }
        let manifest = ShareManifest(level: .catalogue, exportedAt: Date(), catalogue: .init(id: id, name: plan.name), subject: .init(id: id, name: plan.name),
            files: files)
        try createDirectory(destination.deletingLastPathComponent())
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw failure("The archive destination already exists. Choose a new filename.") }
        let manifestBytes=try ColourFiles.encoder().encode(manifest)
        if files.allSatisfy({$0.bytes <= 40*1024*1024}) && files.reduce(0,{$0+$1.bytes}) <= 256*1024*1024 {
            let small=try entries.map{entry -> Zip.Entry in
                if let data=entry.data{return .init(path:entry.path,data:data)}
                guard let file=entry.file else{throw failure("An archive source is unavailable.")}
                return .init(path:entry.path,data:try filesystem.read(file))
            }
            try Zip.write([.init(path:ShareManifest.fileName,data:manifestBytes)]+small,to:destination,manager:self)
        } else {
            let checkedManifest=try documentBytes(manifestBytes,extension:"colmanifest")
            try Zip.writeStreaming([.init(path:ShareManifest.fileName,data:checkedManifest)]+entries,to:destination)
        }
        let inspected=try Sharing.inspect(destination)
        defer{if let staged=inspected.stagedRoot{Sharing.discard(staged)}}
        guard inspected.ok else {throw failure(inspected.problems.joined(separator:"\n"))}
    }

    /// Backup/export publishes a verified archive without detaching or changing the catalogue.
    func createCatalogueArchive(name: String, catalogues: Catalogues, to destination: URL, includeShared:Bool=false) throws {
        let plan = try prepareCatalogueRemoval(name: name, catalogues: catalogues)
        try withTransaction(home: plan.workspace) {
            try validate(plan)
            try archiveCatalogue(plan, to: destination,includeShared:includeShared)
            try validate(plan)
        }
    }

    func executeCatalogueRemoval(_ plan: FileCatalogueRemovalPlan, outcome: FileCatalogueRemovalPlan.Outcome, cancellation: FileOperationCancellation? = nil) throws {
        try cancellation?.check()
        try validate(plan)
        try withTransaction(home: plan.workspace, fault: { _ in try cancellation?.check() }) {
            try validate(plan)
            switch outcome {
            case .detach: break
            case .archive(let destination): try archiveCatalogue(plan, to: destination)
            case .binOwnedFiles:
                guard plan.inventory.complete else { throw failure("Recover unavailable files before removing owned files. Detaching leaves them intact.") }
                let sharedRoot = Catalogues(root: plan.workspace, legacyURL: nil).registry.contains {
                    $0.name != plan.name && $0.url(in: plan.workspace)?.resolvingSymlinksInPath() == plan.root.resolvingSymlinksInPath()
                }
                guard !sharedRoot else { throw failure("Another catalogue registration uses this folder. Detach this entry and retain the shared files.") }
                for file in plan.ownedFiles { try trash(file) }
            case .transfer(let target, let create, let expected):
                try transferCatalogue(plan, to: target, create: create, expected: expected)
            }
            try detachCatalogue(plan)
        }
        FileIncidentCoordinator.shared.resolved(plan.root)
    }

    func transferCatalogue(_ plan: FileCatalogueRemovalPlan, to targetName: String, create: Bool, expected: FileRevision? = nil) throws {
        guard plan.canTransfer, targetName != plan.name else { throw failure("Choose another catalogue and recover unavailable source files before transfer.") }
        let catalogues = Catalogues(root: plan.workspace, legacyURL: nil)
        let target: String
        if create {
            guard !catalogues.names().contains(where: { $0.caseInsensitiveCompare(targetName) == .orderedSame }) else { throw CatalogueError.nameTaken(targetName) }
            target = try catalogues.create(targetName)
        } else {
            guard catalogues.names().contains(targetName) else { throw CatalogueError.missing(targetName) }
            target = targetName
        }
        let targetStore = catalogues.store(for: target)
        if let expected, try FileRevision.read(targetStore.url) != expected { throw failure("The destination changed after the structure review. Review it again before transferring.") }
        var destination = try targetStore.load(), schema = targetStore.schema
        let source = try CatalogueTree.read(root: plan.root)
        let staged = Sharing.Staged(level: .catalogue, root: plan.root, library: source.library, schema: source.schema, palette: nil)
        _ = Sharing.commit(staged, choices: .init(ticked: nil, placement: .catalogue, otherwise: .keepBoth), into: &destination, schema: &schema)
        try targetStore.save(destination, schema: schema)
        // Preserve files outside model payloads and the source's history in a verified archive.
        let archive = targetStore.root.appendingPathComponent("Library/Archives/" + filesystemName(plan.name) + "-" + UUID().uuidString + ".colshr")
        try archiveCatalogue(plan, to: archive)
        try requireAvailableCatalogue(targetStore.url)
    }
}
