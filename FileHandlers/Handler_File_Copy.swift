import Foundation

extension Handler_File_Manager {
    func copySnapshot(_ root: URL) throws -> [String: FileRevision] {
        var result: [String: FileRevision] = [:]
        func walk(_ directory: URL, relative: String, depth: Int) throws {
            guard depth < 32, result.count <= 20_000 else { throw failure("This folder exceeds the managed-copy inspection limit.") }
            for child in try filesystem.list(directory) {
                let path = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                if path == ".colorgain-file-management.lock" || path == "Backups/File Transactions" { continue }
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw FileIssue(url: child, state: .ambiguous, message: "Review symbolic links before relocating this folder.") }
                if values.isDirectory == true { try walk(child, relative: path, depth: depth + 1) }
                else { result[path] = try FileRevision.read(child) }
            }
        }
        try walk(root, relative: "", depth: 0)
        return result
    }
    /// Publish a verified byte copy. Binary/third-party content keeps its native bytes and provenance.
    /// The caller owns the transaction and chooses whether the original is retained or binned.
    func copyVerified(_ source: URL, to destination: URL, depth: Int = 0) throws {
        guard depth < 32 else { throw failure("This folder exceeds the managed-copy nesting limit.") }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw FileIssue(url: source, state: .ambiguous, message: "Review symbolic links before copying this folder.") }
        if values.isDirectory == true {
            try createDirectory(destination)
            for child in try filesystem.list(source) where child.lastPathComponent != ".colorgain-file-management.lock" {
                if child.lastPathComponent == "File Transactions", source.lastPathComponent == "Backups" { continue }
                try copyVerified(child, to: destination.appendingPathComponent(child.lastPathComponent), depth: depth + 1)
            }
        } else {
            let revision = try FileRevision.read(source)
            try createDirectory(destination.deletingLastPathComponent())
            if (values.fileSize ?? 0) > 256 * 1024 * 1024 {
                guard !FileManager.default.fileExists(atPath:destination.path) else { throw failure("The destination already exists.") }
                let temporary=destination.deletingLastPathComponent().appendingPathComponent(".colorgain-copy-"+UUID().uuidString)
                defer { try? FileManager.default.removeItem(at:temporary) }
                try FileManager.default.copyItem(at:source,to:temporary)
                guard try FileRevision.read(temporary) == revision,try FileRevision.read(source) == revision else { throw failure("The source changed while it was being copied.") }
                try FileOperationTransaction.current?.prepare(destination,after:revision.digest)
                try FileManager.default.moveItem(at:temporary,to:destination)
            } else {
                let bytes = try filesystem.read(source)
                guard Sharing.sha256(bytes) == revision.digest else { throw failure("The source changed while it was being copied.") }
                try publishRaw(bytes, to: destination, createOnly: true)
            }
            guard try FileRevision.read(destination) == revision, try FileRevision.read(source) == revision else { throw failure("The copied file could not be verified. The original is retained.") }
        }
    }
}
