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
    var complete: Bool { issues.isEmpty }
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
                    if depth == 0, url.lastPathComponent == "Assets", FileManager.default.fileExists(atPath: url.appendingPathComponent("Assets.colcat").path) { continue }
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
        var result = inventory(root: root)
        // An unavailable parent is the incident; do not manufacture a child error for every link.
        guard !result.issues.contains(where: { $0.url.standardizedFileURL == root.standardizedFileURL }) else { return result }
        do {
            let handler = try self.handler(for: index)
            let bytes = try read(index)
            let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let references = try handler.references(object, at: index)
            var candidates: [String: [URL]] = [:]
            for url in result.files where ["colpal", "coltyp", "colinf"].contains(url.pathExtension.lowercased()) {
                do {
                    let h = try self.handler(for: url)
                    let doc = try JSONSerialization.jsonObject(with: read(url)) as! [String: Any]
                    if let id = h.identity(doc) { candidates[id.lowercased(), default: []].append(url) }
                } catch { result.issues.append(FileIssue.wrapping(error, at: url)) }
            }
            for (id, urls) in candidates where urls.count > 1 {
                result.issues.append(FileIssue(url: urls[0], state: .ambiguous, message: "Several files carry identity \(id). Choose which copy to use."))
            }
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
        } catch { result.issues.append(FileIssue.wrapping(error, at: index)) }
        // Parent failures group descendants. Keep the full expected graph untouched on disk.
        let all = result.issues
        result.issues = all.filter { issue in !all.contains { $0.url != issue.url && issue.url.path.hasPrefix($0.url.path + "/") } }
        return result
    }

    func requireAvailableCatalogue(_ index: URL) throws {
        let observed = inspectCatalogue(index)
        guard observed.complete else { throw FileRecoveryReport(root: observed.root, issues: observed.issues) }
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
