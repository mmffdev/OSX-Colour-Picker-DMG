import Foundation

extension Handler_File_Manager {
    /// Explicit user-approved repair, separate from ordinary saves (which reject corrupt originals).
    func restoreOwnedFile(at destination: URL, from source: URL, expectedIdentity: String?, revision: FileRevision, workspace: URL) throws {
        let handler = try self.handler(for: destination)
        guard (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= handler.descriptor.maximumBytes else { throw failure("The selected recovery file exceeds its supported size.") }
        let bytes = try filesystem.read(source)
        _ = try handler.canonical(bytes)
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw failure("Invalid recovery document.") }
        if let expectedIdentity, handler.identity(object)?.caseInsensitiveCompare(expectedIdentity) != .orderedSame { throw FileIssue(url: source, state: .identityMismatch, message: "The selected backup belongs to a different document.") }
        let restored = try documentBytes(bytes, extension: destination.pathExtension, preservingLegacyProvenance: true)
        try withTransaction(home: workspace) {
            guard try FileRevision.read(destination) == revision else { throw failure("The original changed while recovery was being reviewed.") }
            if revision.digest != nil {
                let backup = workspace.appendingPathComponent("Backups/Recovered Originals/" + UUID().uuidString + "-" + destination.lastPathComponent + ".bak")
                try createDirectory(backup.deletingLastPathComponent())
                try publishRaw(filesystem.read(destination), to: backup, createOnly: true)
            }
            try createDirectory(destination.deletingLastPathComponent())
            try publishRaw(restored, to: destination, expected: revision)
        }
    }
}
