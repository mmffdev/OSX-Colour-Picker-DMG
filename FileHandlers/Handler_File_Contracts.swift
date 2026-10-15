import Foundation
import CryptoKit

enum FileAvailability: String, Codable {
    case available, missing, inaccessible, accessExpired, volumeUnavailable, corrupt
    case unsupportedVersion, identityMismatch, ambiguous, unknown
}

enum FileValidationError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? { switch self { case .unsupported(let name): return "Unsupported " + name + " format or version. The original file has been retained." } }
}

struct FileIssue: Error, LocalizedError, Equatable {
    let url: URL
    let state: FileAvailability
    let message: String
    var underlyingDomain: String? = nil
    var underlyingCode: Int? = nil
    var errorDescription: String? { "\(url.lastPathComponent): \(message)" }
    static func wrapping(_ error: Error, at url: URL) -> FileIssue {
        if let issue = error as? FileIssue { return issue }
        let value = error as NSError
        let state: FileAvailability
        let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError
        let deviceError = [value, underlying].compactMap { $0 }.contains { $0.domain == NSPOSIXErrorDomain && [6, 19, 70].contains($0.code) }
        if deviceError { state = .volumeUnavailable }
        else if error is FileValidationError { state = .unsupportedVersion }
        else if value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code) || value.domain == NSPOSIXErrorDomain && value.code == 2 { state = .missing }
        else if FolderAccess.requiresRenewal(url) { state = .accessExpired }
        else if value.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(value.code) || value.domain == NSPOSIXErrorDomain && [1, 13].contains(value.code) { state = .inaccessible }
        else { state = .corrupt }
        return FileIssue(url: url, state: state, message: error.localizedDescription, underlyingDomain: value.domain, underlyingCode: value.code)
    }
}

struct FileDescriptor {
    let name: String
    let extensions: [String]
    let format: String?
    let versions: Set<Int>
    var maximumBytes = 40 * 1024 * 1024
    var archive = false
}

struct FileReference: Equatable {
    let url: URL
    let identity: String?
    let kind: String
}

protocol Handler_File_Protocol: AnyObject {
    var descriptor: FileDescriptor { get }
    /// Returns the known schema re-encoded, allowing unknown metadata to be retained separately.
    func canonical(_ data: Data) throws -> Data
    func identity(_ object: [String: Any]) -> String?
    func references(_ object: [String: Any], at url: URL) throws -> [FileReference]
}

/// Format implementations own validation/encoding; the manager owns all filesystem mutation.
class Handler_File_JSON: Handler_File_Protocol {
    let descriptor: FileDescriptor
    private let codec: (Data) throws -> Data
    init(_ descriptor: FileDescriptor, codec: @escaping (Data) throws -> Data) {
        self.descriptor = descriptor; self.codec = codec
    }
    func canonical(_ data: Data) throws -> Data {
        guard data.count <= descriptor.maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Invalid or oversized \(descriptor.name) document.") }
        guard let version = object["version"] as? Int, descriptor.versions.contains(version),
              descriptor.format == nil || object["format"] as? String == descriptor.format else {
            throw FileValidationError.unsupported(descriptor.name)
        }
        if let header = object["header"] {
            let metadata = try JSONDecoder().decode(FileDocumentHeader.self, from: JSONSerialization.data(withJSONObject: header))
            try metadata.validate()
            if let id = identity(object), metadata.documentID.caseInsensitiveCompare(id) != .orderedSame { throw failure("File metadata identity does not match its document.") }
        }
        return try codec(data)
    }
    func identity(_ object: [String: Any]) -> String? {
        object["id"] as? String ?? (object["palette"] as? [String: Any])?["id"] as? String
            ?? (object["profile"] as? [String: Any])?["id"] as? String
            ?? object["member"] as? String
    }
    func references(_ object: [String: Any], at url: URL) throws -> [FileReference] { [] }
    static func codec<T: Codable>(_ type: T.Type, _ data: Data, libraryDates: Bool = true) throws -> Data {
        let value = try (libraryDates ? ColourFiles.decoder() : JSONDecoder()).decode(type, from: data)
        return try (libraryDates ? ColourFiles.encoder() : JSONEncoder()).encode(value)
    }
}

struct FileRevision: Equatable, Codable {
    let digest: String?
    static func read(_ url: URL) throws -> FileRevision {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
            return FileRevision(digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
        }
        catch { let issue = FileIssue.wrapping(error, at: url); if issue.state == .missing { return FileRevision(digest: nil) }; throw issue }
    }
}

struct FileSystemAccess {
    var read: (URL) throws -> Data = { try Data(contentsOf: $0) }
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    var list: (URL) throws -> [URL] = { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) }
    var authorize: (URL) throws -> Void = { try FolderAccess.authorize($0) }
    var trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
}

final class FileOperationCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw CocoaError(.userCancelled) } }
}
