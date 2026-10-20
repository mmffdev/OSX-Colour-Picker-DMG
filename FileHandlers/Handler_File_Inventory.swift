import Foundation

extension Notification.Name { static let fileManagementIssue = Notification.Name("Colorgain.FileManagementIssue") }

struct FileRecoveryReport: Error, LocalizedError {
    let root: URL
    let issues: [FileIssue]
    var errorDescription: String? {
        "\(root.lastPathComponent) needs file recovery. Its files and references have been retained.\n" + issues.prefix(12).map { $0.errorDescription ?? $0.message }.joined(separator: "\n")
    }
}

struct FileInventory {
    let root: URL
    var files: [URL] = []
    var folders: [URL] = []
    var issues: [FileIssue] = []
    var relocated: [String: URL] = [:]
    var assetPayloads:[String:Data]=[:]
    var assetHeads:[String:InspectedAssetIdentity]=[:]
    var observedAssets:[CatalogueTree.FoundAsset]=[]
    var assetHeadsComplete=false
    var catalogueDocument:CatalogueFile?
    var complete: Bool { issues.isEmpty }
}

struct InspectedAssetIdentity {
    let id:UUID
    let owner:UUID?
    let kind:String
    init?(_ object:[String:Any]) {
        if let palette=object["palette"] as? [String:Any],
           let raw=palette["id"] as? String,let id=UUID(uuidString:raw) {
            self.id=id
            owner=(object["project"] as? String).flatMap(UUID.init(uuidString:))
            kind=palette["styles"] is [Any] ? "typography":"palette"
        } else if let raw=object["member"] as? String,let id=UUID(uuidString:raw) {
            self.id=id;owner=id;kind="information"
        } else {return nil}
    }
}

/// A file's inode, size and modification time change on coordinated atomic writes.
/// Reuse an already validated identity and payload only while that exact disk version
/// remains present. The inventory still walks every directory and validates links.
enum InspectedAssetCache {
    private static let lock=NSLock()
    private static var entries:[String:(FileVersion,String,Data,InspectedAssetIdentity?,PaletteDocument?)]=[:]
    private static var bytes=0
    static func get(_ url:URL)->(String,Data,InspectedAssetIdentity?,PaletteDocument?)? {
        guard let version=FileVersion.read(url) else{return nil}
        let path=url.standardizedFileURL.path
        lock.lock();defer{lock.unlock()}
        guard let item=entries[path],item.0 == version else{return nil}
        return (item.1,item.2,item.3,item.4)
    }
    static func put(_ url:URL,id:String,data:Data,head:InspectedAssetIdentity?,document:PaletteDocument?) {
        guard data.count <= 1_048_576,let version=FileVersion.read(url) else{return}
        let path=url.standardizedFileURL.path
        lock.lock();defer{lock.unlock()}
        if let old=entries.removeValue(forKey:path){bytes -= old.2.count}
        if bytes+data.count > 67_108_864 {entries.removeAll();bytes=0}
        entries[path]=(version,id,data,head,document);bytes += data.count
    }
    static func invalidate(in root:URL) {
        let prefix=root.resolvingSymlinksInPath().standardizedFileURL.path+"/"
        lock.lock();defer{lock.unlock()}
        entries=entries.filter{!URL(fileURLWithPath:$0.key).resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(prefix)}
        bytes=entries.values.reduce(0){$0+$1.2.count}
    }
}

extension Handler_File_Manager {
    /// Strict disk observation. A failed subtree is never represented as an empty successful scan.
    func inventory(root: URL, maximumFiles: Int = 20_000) -> FileInventory {
        var result = FileInventory(root: root)
        func walk(_ folder: URL, depth: Int) {
            guard depth < 32 else { result.issues.append(FileIssue(url: folder, state: .unknown, message: "The folder nesting exceeds the inspection limit.")); return }
            do {
                let children = try filesystem.list(folder)
                var names = Set<String>()
                for url in children where !url.lastPathComponent.hasPrefix(".") {
                    let key = url.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
                    if !names.insert(key).inserted { result.issues.append(FileIssue(url: url, state: .ambiguous, message: "Several folder entries differ only by case or Unicode spelling. Resolve them before moving or saving files.")) }
                    if depth == 0, ["Backups", "Catalogues"].contains(url.lastPathComponent) { continue }
                    if depth == 0, url.lastPathComponent == "Assets", (FileManager.default.fileExists(atPath: url.appendingPathComponent("Assets.colcat").path) || FileManager.default.fileExists(atPath:url.appendingPathComponent("my_library.collib").path)) { continue }
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true { result.issues.append(FileIssue(url: url, state: .ambiguous, message: "Symbolic links need explicit review before file operations.")); continue }
                    if values.isDirectory == true { result.folders.append(url); walk(url, depth: depth + 1) }
                    else {
                        guard result.files.count < maximumFiles else { throw FileIssue(url: folder, state: .unknown, message: "The file inspection limit was reached.") }
                        result.files.append(url)
                    }
                }
            } catch { result.issues.append(FileIssue.wrapping(error, at: folder)) }
        }
        walk(root, depth: 0)
        return result
    }

    func inspectCatalogue(_ index: URL) -> FileInventory {
        let root = index.deletingLastPathComponent()
        let trace=ProcessInfo.processInfo.environment["COLORGAIN_PERF_TRACE"] == "1"
        let started=Date()
        func report(_ label:String,_ from:Date) {
            if trace {print(String(format:"PERF inspect %@ %.3f s",label,Date().timeIntervalSince(from)))}
        }
        var result = inventory(root: root)
        report("inventory",started)
        // An unavailable parent is the incident; do not manufacture a child error for every link.
        guard !result.issues.contains(where: { $0.url.standardizedFileURL == root.standardizedFileURL }) else { return result }
        do {
            let referencesStarted=Date()
            let handler = try self.handler(for: index)
            let bytes = try read(index)
            let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            result.catalogueDocument=CatalogueTree.decode(bytes)
            let rootIsLink=(try? root.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true
            let references: [FileReference]
            if result.complete,!rootIsLink,let catalogue=handler as? Handler_File_Catalogue {
                references=try catalogue.referencesInInspectedTree(object,at:index)
            } else {references=try handler.references(object,at:index)}
            report("references",referencesStarted)
            var candidates: [String: [URL]] = [:]
            var inspectedIdentities:[String:String]=[:]
            var cachedPayloadBytes=0
            let assets=result.files.filter{["colpal","coltyp","colinf"].contains($0.pathExtension.lowercased())}
            result.assetHeadsComplete=true
            if result.files.contains(where:{$0.pathExtension.lowercased() == ColourFiles.legacyPalette}) {result.assetHeadsComplete=false}
            let logicalRoot=root.path+"/",physicalRoot=root.resolvingSymlinksInPath().standardizedFileURL.path+"/"
            let assetsStarted=Date()
            let inspected=inspectAssetFiles(assets)
            report("assetValidation",assetsStarted)
            for (url,inspection) in zip(assets,inspected) {
                switch inspection {
                case .failure(let issue):result.issues.append(issue)
                case .success(let asset):
                    guard let id=asset.identity else{result.assetHeadsComplete=false;continue}
                    candidates[id.lowercased(),default:[]].append(url)
                    inspectedIdentities[url.path]=id
                    let listed=url.path
                    let relativePath:String
                    if listed.hasPrefix(logicalRoot) {relativePath=String(listed.dropFirst(logicalRoot.count))}
                    else if listed.hasPrefix(physicalRoot) {relativePath=String(listed.dropFirst(physicalRoot.count))}
                    else {
                        let resolved=url.resolvingSymlinksInPath().standardizedFileURL.path
                        guard resolved.hasPrefix(physicalRoot) else {result.assetHeadsComplete=false;continue}
                        relativePath=String(resolved.dropFirst(physicalRoot.count))
                    }
                    inspectedIdentities[physicalRoot+relativePath]=id
                    inspectedIdentities[logicalRoot+relativePath]=id
                    if let head=asset.head {result.assetHeads[url.path]=head}
                    let retainPayload=asset.data.count <= 1_048_576 && cachedPayloadBytes+asset.data.count <= 67_108_864
                    if retainPayload {
                        result.assetPayloads[url.path]=asset.data
                        cachedPayloadBytes += asset.data.count
                    }
                    if let head=asset.head {
                        let display=root.appendingPathComponent(relativePath)
                        inspectedIdentities[display.path]=id
                        let kind:CatalogueTree.FoundAsset.Kind=head.kind == "information" ? .information:head.kind == "typography" ? .typography:.palette
                        result.observedAssets.append(.init(url:display,kind:kind,id:head.id,owner:head.owner,payload:retainPayload ? asset.data:nil,document:asset.document))
                    } else {result.assetHeadsComplete=false}
                }
            }
            for (id, urls) in candidates where urls.count > 1 {
                result.issues.append(FileIssue(url: urls[0], state: .ambiguous, message: "Several files carry identity \(id). Choose which copy to use."))
            }
            var referenceMisses=0
            for reference in references {
                if reference.kind == "Folder" {
                    // Existing resolver may find a proven relocation by member identities. Missing empty
                    // folders have no such proof and remain recoverable rather than inferred deleted.
                    if FileManager.default.fileExists(atPath: reference.url.path) { continue }
                    let descendantLinks = references.filter { $0.kind != "Folder" && $0.url.path.hasPrefix(reference.url.path + "/") && $0.identity != nil }
                    if !descendantLinks.isEmpty && descendantLinks.allSatisfy({ candidates[$0.identity!.lowercased()]?.count == 1 }) { continue }
                    result.issues.append(FileIssue(url: reference.url, state: .missing, message: "A catalogue folder is unavailable. Locate it or explicitly remove its reference.")); continue
                }
                do {
                    if let inspected=inspectedIdentities[reference.url.path] {
                        if let expected=reference.identity,inspected.caseInsensitiveCompare(expected) != .orderedSame {
                            throw FileIssue(url:reference.url,state:.identityMismatch,message:"This file does not match the catalogue reference.")
                        }
                        continue
                    }
                    referenceMisses += 1
                    let h = try self.handler(for: reference.url)
                    let doc = try JSONSerialization.jsonObject(with: read(reference.url)) as! [String: Any]
                    if let expected = reference.identity, h.identity(doc)?.caseInsensitiveCompare(expected) != .orderedSame {
                        throw FileIssue(url: reference.url, state: .identityMismatch, message: "This file does not match the catalogue reference.")
                    }
                } catch {
                    let issue = FileIssue.wrapping(error, at: reference.url)
                    if issue.state == .missing, let id = reference.identity, let urls = candidates[id.lowercased()], urls.count == 1 { result.relocated[reference.url.path] = urls[0] }
                    else { result.issues.append(issue) }
                }
            }
            if trace && assets.count > 1_000 {print("PERF inspect heads \(result.observedAssets.count)/\(assets.count) complete=\(result.assetHeadsComplete) referenceMisses=\(referenceMisses)")}
            report("total",started)
        } catch { result.issues.append(FileIssue.wrapping(error, at: index)) }
        // Parent failures group descendants. Keep the full expected graph untouched on disk.
        let all = result.issues
        result.issues = all.filter { issue in !all.contains { $0.url != issue.url && issue.url.path.hasPrefix($0.url.path + "/") } }
        return result
    }

    func requireCatalogueIdentity(_ index: URL, expected: UUID?) throws {
        guard let expected else { return }
        let actual = try ColourFiles.decoder().decode(CatalogueFile.self, from: read(index)).id
        guard actual == expected else {
            throw FileRecoveryReport(root: index.deletingLastPathComponent(), issues: [FileIssue(url: index, state: .identityMismatch, message: "This folder belongs to a different catalogue. Locate the original or detach this reference; the disk files have been retained.")])
        }
    }

    @discardableResult
    func validatedCatalogue(_ index: URL) throws -> FileInventory {
        let observed = inspectCatalogue(index)
        guard observed.complete else { throw FileRecoveryReport(root: observed.root, issues: observed.issues) }
        return observed
    }

    func requireAvailableCatalogue(_ index: URL) throws {
        _ = try validatedCatalogue(index)
    }
}

/// UI consumes each changed incident once; dismissal never removes expected file references.
final class FileIncidentCoordinator {
    static let shared = FileIncidentCoordinator()
    private let lock = NSLock()
    private var generations: [String: String] = [:]
    private var blockedParents = Set<String>()
    static func report(_ error: Error, at url: URL) {
        let issue = FileIssue.wrapping(error, at: url)
        Diagnostics.log("files", error: issue)
        NotificationCenter.default.post(name: .fileManagementIssue, object: nil, userInfo: ["error": issue])
    }
    func shouldPresent(root: URL, issues: [FileIssue]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = root.standardizedFileURL.path
        if blockedParents.contains(key) { return false }
        let value = issues.map { $0.url.path + ":" + $0.state.rawValue + ":" + $0.message }.sorted().joined(separator: "\n")
        guard generations[key] != value else { return false }
        generations[key] = value
        if issues.contains(where: { $0.url.standardizedFileURL == root.standardizedFileURL || $0.url.pathExtension == "colcat" }) { blockedParents.insert(key) }
        return !issues.isEmpty
    }
    func resolved(_ root: URL) { lock.lock(); defer { lock.unlock() }; generations[root.standardizedFileURL.path] = nil; blockedParents.remove(root.standardizedFileURL.path) }
}
