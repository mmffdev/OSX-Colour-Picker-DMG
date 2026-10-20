import Foundation
import Darwin

/// Cooperative Colorgain edit ownership. The UI's unlock action claims the file for one process.
struct FileEditOwner: Codable, Equatable {
    var session: String
    var machine: String
    var user: String
    var claimedAt: String
}
struct FileEditControl: Codable, Equatable {
    var version = 1
    var requiresUnlock = true
    var owner: FileEditOwner?
    var state: String { owner == nil ? "available" : "claimed" }
}

final class Handler_File_Sidecar: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Asset Sidecar", extensions: ["colcar"], format: "colorgain-sidecar", versions: [1])) { data in
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String, UUID(uuidString: id) != nil,
                  let source = object["sourceFile"] as? String, !source.isEmpty, !source.contains("/"),
                  object["payload"] is [String: Any] else { throw failure("Invalid Colorgain sidecar.") }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
    }
}

enum FileEditAccess {
    static let session = UUID().uuidString
    private static let mutex = NSRecursiveLock()
    private static var claimed: [String: URL] = [:]
    private static let guardKey = "Colorgain.FileEdit.Guards"
    static func sidecar(for source: URL) -> URL { source.appendingPathExtension("colcar") }
    private static func canonical(_ source: URL) -> URL {
        let asset = source.pathExtension.lowercased() == "colcar" ? source.deletingPathExtension() : source
        return asset.resolvingSymlinksInPath().standardizedFileURL
    }
    static func isNative(_ source: URL, manager: Handler_File_Manager = .shared) -> Bool {
        guard let handler = try? manager.handler(for: source) else { return false }
        return !handler.descriptor.archive
    }
    private static func metadataURL(_ source: URL, manager: Handler_File_Manager) -> URL {
        isNative(source, manager: manager) ? source : sidecar(for: source)
    }
    private static func readObject(_ url: URL) throws -> [String: Any] {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 40 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw failure("Invalid or oversized asset metadata.") }
        return object
    }
    static func control(for source: URL, manager: Handler_File_Manager = .shared) throws -> FileEditControl? {
        let url = metadataURL(canonical(source), manager: manager)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let object = try readObject(url)
        guard let header = object["header"] as? [String: Any], let value = header["editControl"] else {
            if url.pathExtension.lowercased() == "colcar" { throw failure("The sidecar has no valid edit-control metadata.") }
            return nil
        }
        let valueData = try JSONSerialization.data(withJSONObject: value)
        let control = try JSONDecoder().decode(FileEditControl.self, from: valueData)
        guard control.version == 1, control.requiresUnlock,
              control.owner == nil || UUID(uuidString: control.owner!.session) != nil else { throw failure("Unsupported edit-control metadata. The asset remains locked.") }
        return control
    }
    /// An exclusive sibling directory serialises the ownership check and metadata update across clients.
    /// A crash during this short critical section leaves the guard in place; no automatic stealing.
    static func withGuard<T>(for source: URL, _ operation: () throws -> T) throws -> T {
        let source = canonical(source), key = source.path
        var held = Thread.current.threadDictionary[guardKey] as? Set<String> ?? []
        if held.contains(key) { return try operation() }
        let gate = source.deletingLastPathComponent().appendingPathComponent("." + source.lastPathComponent + ".colguard")
        guard mkdir(gate.path, mode_t(0o700)) == 0 else {
            if errno == EEXIST { throw failure("Another Colorgain operation is using this asset. Its edit guard has been retained; try again when that operation finishes.") }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Cannot coordinate access beside " + source.lastPathComponent + ". Check the folder's write permission."])
        }
        held.insert(key); Thread.current.threadDictionary[guardKey] = held
        defer {
            var current = Thread.current.threadDictionary[guardKey] as? Set<String> ?? []
            current.remove(key); Thread.current.threadDictionary[guardKey] = current
            _ = rmdir(gate.path)
        }
        return try operation()
    }
    @discardableResult static func ensure(for source: URL, manager: Handler_File_Manager = .shared) throws -> URL {
        let source = canonical(source)
        return try withGuard(for: source) {
            let url = metadataURL(source, manager: manager)
            if !isNative(source, manager: manager), !FileManager.default.fileExists(atPath: url.path) {
                var object: [String: Any] = ["format": "colorgain-sidecar", "version": 1, "id": UUID().uuidString, "sourceFile": source.lastPathComponent, "payload": [String: Any](), "history": [[String: Any]]()]
                var header = try manager.metadata.header(identity: object["id"] as? String, previous: nil, existing: false)
                header["editControl"] = try encoded(FileEditControl())
                object["header"] = header
                try manager.write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), to: url, createOnly: true)
            } else if try control(for: source, manager: manager) == nil {
                try store(FileEditControl(), source: source, manager: manager)
            }
            _ = try control(for: source, manager: manager)
            return url
        }
    }
    private static func encoded(_ control: FileEditControl) throws -> [String: Any] {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(control)) as! [String: Any]
        value["state"] = control.state
        return value
    }
    private static func store(_ control: FileEditControl, source: URL, manager: Handler_File_Manager) throws {
        let url = metadataURL(source, manager: manager), original = try Data(contentsOf: url)
        var object = try readObject(url)
        let handler = try manager.handler(for: url)
        _ = try handler.canonical(original)
        var header = try (object["header"] as? [String: Any] ?? manager.metadata.header(identity: handler.identity(object), previous: nil, existing: true))
        header["editControl"] = try encoded(control); object["header"] = header
        try manager.publishEditMetadata(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: url, expected: FileRevision(digest: Sharing.sha256(original)))
    }
    static func setEditing(_ enabled: Bool, source: URL, owner: String = session, manager: Handler_File_Manager = .shared) throws {
        let source = canonical(source)
        try withGuard(for: source) {
            _ = try ensure(for: source, manager: manager)
            var value = try control(for: source, manager: manager)!
            if let current = value.owner, current.session != owner {
                throw failure("This asset is being edited by " + current.user + " on " + current.machine + ". Only that session can release its lock.")
            }
            if enabled {
                value.owner = FileEditOwner(session: owner, machine: ProcessInfo.processInfo.hostName, user: NSFullUserName(), claimedAt: FileDocumentHeader.stamp(Date()))
            } else { value.owner = nil }
            try store(value, source: source, manager: manager)
            if owner == session { mutex.lock(); if enabled { claimed[source.path] = source } else { claimed.removeValue(forKey: source.path) }; mutex.unlock() }
        }
    }
    static func owns(_ source: URL) -> Bool {
        (try? control(for: source))?.owner?.session == session
    }
    /// Every managed native or standard-format write goes through the same cross-client gate.
    static func withWriteAccess<T>(to source: URL, manager: Handler_File_Manager = .shared, _ operation: () throws -> T) throws -> T {
        let source = canonical(source)
        guard FileManager.default.fileExists(atPath: source.deletingLastPathComponent().path) else { return try operation() }
        return try withGuard(for: source) {
            if let value = try control(for: source, manager: manager), value.owner?.session != session {
                throw failure("This asset is locked for editing. Unlock it in Colorgain before making changes; another session's lock cannot be overridden.")
            }
            return try operation()
        }
    }
    static func releaseOwned() {
        mutex.lock(); let sources = Array(claimed.values); mutex.unlock()
        for source in sources { do { try setEditing(false, source: source) } catch { Diagnostics.log("edit-lock", error.localizedDescription) } }
    }
}
