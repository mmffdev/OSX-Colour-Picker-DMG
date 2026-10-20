import Foundation

final class Handler_File_Manager {
    static let shared = Handler_File_Manager()
    let filesystem: FileSystemAccess
    var metadata: FileMetadataProvider
    private let lock = NSRecursiveLock()
    var isBusy: Bool { if lock.try() { lock.unlock(); return false }; return true }
    private var handlers: [String: Handler_File_Protocol] = [:]

    private static func defaultHandlers() -> [Handler_File_Protocol] {
        [Handler_File_App_Data(), Handler_File_Catalogue(), Handler_File_Palette(), Handler_File_Typography(),
         Handler_File_Swatches(), Handler_File_Swatch(), Handler_File_Information(), Handler_File_Colour_Profiles(),
         Handler_File_Print_Profile(), Handler_File_Proof(), Handler_File_History(), Handler_File_Key_Profile(),
         Handler_File_ASE_Registry(), Handler_File_Sidecar(), Handler_File_Share(), Handler_File_QR()]
    }

    init(filesystem: FileSystemAccess = FileSystemAccess(), metadata: FileMetadataProvider = FileMetadataProvider(), registerDefaults: Bool = true) {
        self.filesystem = filesystem; self.metadata = metadata
        if registerDefaults {
            for handler in Self.defaultHandlers() { try! register(handler) }
        }
    }
    func register(_ handler: Handler_File_Protocol) throws {
        lock.lock(); defer { lock.unlock() }
        guard handler.descriptor.extensions.allSatisfy({ handlers[$0.lowercased()] == nil }) else { throw failure("A file extension is already registered.") }
        for ext in handler.descriptor.extensions { handlers[ext.lowercased()] = handler }
    }
    var descriptors: [FileDescriptor] {
        lock.lock(); defer { lock.unlock() }
        return Array(Dictionary(handlers.values.map { ($0.descriptor.name, $0.descriptor) }, uniquingKeysWith: { first, _ in first }).values)
    }
    func handler(for url: URL) throws -> Handler_File_Protocol {
        lock.lock(); defer { lock.unlock() }
        guard let handler = handlers[url.pathExtension.lowercased()] else { throw FileIssue(url: url, state: .unsupportedVersion, message: "This file type is not supported. It has been left unchanged.") }
        return handler
    }
    private func validateContainer(_ data: Data, at url: URL) throws {
        if ["colshr", "colshare"].contains(url.pathExtension.lowercased()), data.prefix(2) != Data([0x50, 0x4b]) { throw failure("This share must be a checked archive, not a manifest by itself.") }
    }
    func read(_ url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        do {
            let handler = try handler(for: url)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= handler.descriptor.maximumBytes else { throw failure("The file exceeds its supported size.") }
            let data = try filesystem.read(url)
            try validateContainer(data, at: url)
            _ = try handler.canonical(data)
            return data
        } catch { throw FileIssue.wrapping(error, at: url) }
    }

    struct InspectedAssetPayload {
        let data:Data
        let identity:String?
        let head:InspectedAssetIdentity?
        let document:PaletteDocument?
    }
    /// Inspect independent asset files concurrently while holding the manager's
    /// write lock. Each worker uses an immutable handler snapshot; custom test
    /// managers retain serial reads through their injected filesystem.
    func inspectAssetFiles(_ urls:[URL])->[Result<InspectedAssetPayload,FileIssue>] {
        lock.lock();defer{lock.unlock()}
        let handlerSnapshot=self.handlers,readFilesystem=self.filesystem
        let requested=Int(ProcessInfo.processInfo.environment["COLORGAIN_INSPECTION_WORKERS"] ?? "") ?? 4
        let workers=self === Self.shared ? min(max(1,min(12,requested)),ProcessInfo.processInfo.activeProcessorCount,max(1,urls.count)):1
        var results:[Int:Result<InspectedAssetPayload,FileIssue>]=[:]
        let resultsLock=NSLock()
        DispatchQueue.concurrentPerform(iterations:workers) { worker in
            for index in stride(from:worker,to:urls.count,by:workers) {
                let url=urls[index]
                let result:Result<InspectedAssetPayload,FileIssue>
                do {
                    if let cached=InspectedAssetCache.get(url) {
                        result = .success(InspectedAssetPayload(data:cached.1,identity:cached.0,head:cached.2,document:cached.3))
                    } else {
                        guard let handler=handlerSnapshot[url.pathExtension.lowercased()] else {
                            throw FileIssue(url:url,state:.unsupportedVersion,message:"This file type is not supported.")
                        }
                        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size <= handler.descriptor.maximumBytes else {throw failure("The file exceeds its supported size.")}
                        let data=try readFilesystem.read(url)
                        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw failure("Invalid asset document.")}
                        let document:PaletteDocument?
                        if (handler is Handler_File_Palette || handler is Handler_File_Typography),
                           let paletteHandler=handler as? Handler_File_JSON {
                            document=try paletteHandler.inspectedDocument(data,object:object,at:url)
                        } else {
                            _ = try handler.canonical(data)
                            document=nil
                        }
                        let identity=handler.identity(object),head=InspectedAssetIdentity(object)
                        if let identity {InspectedAssetCache.put(url,id:identity,data:data,head:head,document:document)}
                        result = .success(InspectedAssetPayload(data:data,identity:identity,head:head,document:document))
                    }
                } catch {result = .failure(FileIssue.wrapping(error,at:url))}
                resultsLock.lock();results[index]=result;resultsLock.unlock()
            }
        }
        return (0..<urls.count).map{results[$0]!}
    }

    /// Portable native output (without a filesystem destination); creation provenance belongs to
    /// this exported document. Existing-file provenance is retained by write(_:to:).
    func documentBytes(_ data: Data, extension ext: String, includePersonalNames: Bool = true, preservingLegacyProvenance: Bool = false) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let handler = try self.handler(for: URL(fileURLWithPath: "/document." + ext))
        _ = try handler.canonical(data)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let previous = object["header"] as? [String: Any]
        let header = try metadata.header(identity: handler.identity(object), previous: previous, existing: preservingLegacyProvenance, derivedFrom: (object["palette"] as? [String: Any])?["copiedFrom"] as? String)
        let decoded = try JSONDecoder().decode(FileDocumentHeader.self, from: JSONSerialization.data(withJSONObject: header))
        object["header"] = includePersonalNames ? header : try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded.forSharing(includePersonalNames: false)))
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Serialize read/modify/write; file coordination and expected bytes guard external edits.
    func write(_ data: Data, to url: URL, expected: FileRevision? = nil, createOnly: Bool = false) throws {
        try FileEditAccess.withWriteAccess(to: url, manager: self) { try writeWithAccess(data, to: url, expected: expected, createOnly: createOnly) }
    }
    private func writeWithAccess(_ data: Data, to url: URL, expected: FileRevision?, createOnly: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let trace=ProcessInfo.processInfo.environment["COLORGAIN_PERF_TRACE"] == "1" && url.pathExtension == "colcat"
        let writeStarted=Date()
        func report(_ label:String,_ started:Date) {
            if trace {print(String(format:"PERF index %@ %.3f s",label,Date().timeIntervalSince(started)))}
        }
        var coordinateError: NSError?, operationError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinateError) { coordinated in
            do {
                let handler = try self.handler(for: coordinated)
                try self.validateContainer(data, at: coordinated)
                let incomingCanonical = try handler.canonical(data)
                report("incomingCanonical",writeStarted)
                if handler.descriptor.archive && coordinated.pathExtension.lowercased() != "colmanifest" {
                    try self.publishRaw(data, to: coordinated, expected: expected, createOnly: createOnly)
                    return
                }
                var incoming = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let old: Data?
                do { old = try self.filesystem.read(coordinated) }
                catch { if FileIssue.wrapping(error, at: coordinated).state == .missing { old = nil } else { throw error } }
                if createOnly && old != nil { throw failure("A file already exists at this destination.") }
                if let expected, expected.digest != old.map(Sharing.sha256) { throw failure("The file changed after this operation was planned. Review it again before saving.") }
                var previous: [String: Any]?
                if let old {
                    let oldStarted=Date()
                    let canonical = try handler.canonical(old)
                    report("oldCanonical",oldStarted)
                    previous = try JSONSerialization.jsonObject(with: old) as? [String: Any]
                    let known = try JSONSerialization.jsonObject(with: canonical)
                    incoming = try Self.retainingUnknown(previous!, known: known, incoming: incoming) as! [String: Any]
                    report("retainUnknown",oldStarted)
                    // Preserve identity. Independent copies must be written to a new destination.
                    if let oldID = handler.identity(previous!), let newID = handler.identity(incoming), oldID != newID { throw failure("The destination belongs to a different document.") }
                    if Self.equal(Self.withoutHeader(incoming), Self.withoutHeader(previous!)) { return }
                }
                _ = incomingCanonical
                let priorHeader = old == nil ? incoming["header"] : previous?["header"]
                incoming["header"] = try self.metadata.header(identity: handler.identity(incoming), previous: priorHeader as? [String: Any], existing: old != nil, derivedFrom: (incoming["palette"] as? [String: Any])?["copiedFrom"] as? String)
                let output = try JSONSerialization.data(withJSONObject: incoming, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
                let outputStarted=Date()
                _ = try handler.canonical(output)
                report("outputCanonical",outputStarted)
                try FileOperationTransaction.current?.prepare(coordinated, after: Sharing.sha256(output))
                try self.filesystem.write(output, coordinated)
                report("total",writeStarted)
            } catch { operationError = error }
        }
        if let error = operationError ?? coordinateError {
            if (error as NSError).code == NSUserCancelledError { throw error }
            throw FileIssue.wrapping(error, at: url)
        }
    }
    func update(_ url: URL, _ change: (inout [String: Any]) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        let before = try read(url)
        var object = try JSONSerialization.jsonObject(with: before) as! [String: Any]
        try change(&object)
        try write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), to: url, expected: FileRevision(digest: Sharing.sha256(before)))
    }
    func withTransaction<T>(home: URL, fault: ((String) throws -> Void)? = nil, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        return try FileOperationTransaction.perform(home: home, fault: fault, operation)
    }
    /// Standard-format adapters and archive output preserve their native bytes.
    func publishRaw(_ data: Data, to url: URL, expected: FileRevision? = nil, createOnly: Bool = false) throws {
        try FileEditAccess.withWriteAccess(to: url, manager: self) { try publishRawWithAccess(data, to: url, expected: expected, createOnly: createOnly) }
    }
    /// Ownership transitions change metadata only, under FileEditAccess's exclusive guard.
    func publishEditMetadata(_ data: Data, to url: URL, expected: FileRevision) throws {
        var before = try JSONSerialization.jsonObject(with: filesystem.read(url)) as! [String: Any]
        var after = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        before.removeValue(forKey: "header"); after.removeValue(forKey: "header")
        guard Self.equal(before, after) else { throw failure("An edit-lock transition cannot change asset contents.") }
        try publishRawWithAccess(data, to: url, expected: expected, createOnly: false)
    }
    private func publishRawWithAccess(_ data: Data, to url: URL, expected: FileRevision?, createOnly: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        let before: Data?
        do { before = try filesystem.read(url) }
        catch { if FileIssue.wrapping(error, at: url).state == .missing { before = nil } else { throw error } }
        if createOnly && before != nil { throw failure("The destination already exists.") }
        if let expected, expected.digest != before.map(Sharing.sha256) { throw failure("The destination changed after review.") }
        if before == data { return }
        try FileOperationTransaction.current?.prepare(url, after: Sharing.sha256(data))
        try filesystem.write(data, url)
    }
    func createDirectory(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: url.path) { return }
        let parent = url.deletingLastPathComponent()
        if parent != url { try createDirectory(parent) }
        try FileOperationTransaction.current?.prepare(url, after: Sharing.sha256(Data("directory".utf8)))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    func move(_ source: URL, to destination: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw failure("The destination already exists. Choose a different name.") }
        let digest = try FileOperationTransaction.digest(source)
        guard digest != nil else { throw FileIssue(url: source, state: .missing, message: "The source is unavailable.") }
        try createDirectory(destination.deletingLastPathComponent())
        try FileOperationTransaction.current?.prepare(destination, after: digest)
        try FileOperationTransaction.current?.prepare(source, after: nil)
        try FileManager.default.moveItem(at: source, to: destination)
    }
    func trash(_ url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        try FileOperationTransaction.current?.prepare(url, after: nil)
        try filesystem.trash(url)
    }
    static func contained(_ relative: String, under root: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else { throw failure("A file reference escapes its owning folder.") }
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        let fm = FileManager.default
        // Resolve the nearest existing ancestor. Foundation can shorten /private/tmp and
        // /private/var differently for a missing leaf; string prefixes are not file identity.
        var ancestor = candidate
        while true {
            do { _ = try fm.attributesOfItem(atPath: ancestor.path); break }
            catch {
                let issue = FileIssue.wrapping(error, at: ancestor)
                guard issue.state == .missing else { throw issue }
                let parent = ancestor.deletingLastPathComponent()
                guard parent != ancestor else { throw issue }
                ancestor = parent
            }
        }
        var relationship = FileManager.URLRelationship.other
        try fm.getRelationship(&relationship, ofDirectoryAt: root.resolvingSymlinksInPath(), toItemAt: ancestor.resolvingSymlinksInPath())
        guard relationship == .same || relationship == .contains else { throw failure("A file reference escapes its owning folder.") }
        return candidate
    }
    private static func withoutHeader(_ value: [String: Any]) -> [String: Any] { var result = value; result["header"] = nil; return result }
    private static func equal(_ a: Any, _ b: Any) -> Bool { (a as? NSObject)?.isEqual(b) == true }
    private static func containsUnknown(_ original: Any, known: Any) -> Bool {
        if let original = original as? [String: Any], let known = known as? [String: Any] {
            return original.contains { key, value in known[key] == nil || containsUnknown(value, known: known[key]!) }
        }
        if let original = original as? [Any], let known = known as? [Any], original.count == known.count {
            return zip(original, known).contains { containsUnknown($0, known: $1) }
        }
        return false
    }
    /// Compare original bytes with the old codec projection, keeping only fields the codec did not understand.
    static func retainingUnknown(_ original: Any, known: Any, incoming: Any) throws -> Any {
        if let original = original as? [String: Any], let known = known as? [String: Any], var next = incoming as? [String: Any] {
            for (key, value) in original {
                if known[key] == nil && next[key] == nil { next[key] = value }
                else if let oldKnown = known[key], let new = next[key] { next[key] = try retainingUnknown(value, known: oldKnown, incoming: new) }
            }
            return next
        }
        if let old = original as? [[String: Any]], let known = known as? [[String: Any]], let next = incoming as? [[String: Any]], old.count == known.count {
            let keys = ["id", "hex", "path", "member", "key", "name", "space"]
            var exact:[String:Int]=[:], foldedUUID:[String:Int]=[:]
            for (index,candidate) in known.enumerated() {
                for key in keys {
                    guard let value=candidate[key] as? String else{continue}
                    let token=key+"\u{0}"+value
                    if exact[token] == nil {exact[token]=index}
                    if UUID(uuidString:value) != nil {
                        let folded=key+"\u{0}"+value.lowercased()
                        if foldedUUID[folded] == nil {foldedUUID[folded]=index}
                    }
                }
            }
            return try next.enumerated().map { index, item -> [String: Any] in
                let identity = keys.first { item[$0] is String }
                let match: Int?
                if let key = identity, let value = item[key] as? String {
                    let original=exact[key+"\u{0}"+value]
                    let folded=foldedUUID[key+"\u{0}"+value.lowercased()]
                    match=[original,folded].compactMap{$0}.min()
                } else {
                    match = index < known.count ? index : nil
                    if let match, containsUnknown(old[match], known: known[match]), !equal(known[match], item) {
                        throw failure("Newer metadata in this list cannot be matched safely after the edit. The original file has been retained.")
                    }
                }
                guard let match else { return item }
                return try retainingUnknown(old[match], known: known[match], incoming: item) as! [String: Any]
            }
        }
    
        return incoming
    }
}
