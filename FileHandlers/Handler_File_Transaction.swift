import Foundation
import Darwin

/// Journal intent before each mutation. Recovery only replaces bytes matching that intent;
/// unrelated external edits remain untouched and keep the journal available for recovery.
final class FileOperationTransaction {
    struct Entry: Codable {
        var path: String
        var before: String?
        var after: String?
        var snapshot: String?
        var restored: Bool? = nil
    }
    struct Journal: Codable {
        var version = 1
        var id: String
        var committed = false
        var entries: [Entry] = []
    }
    static let contextKey = "Colorgain.FileOperationTransaction"
    private static let executionLock = NSRecursiveLock()
    static var current: FileOperationTransaction? { Thread.current.threadDictionary[contextKey] as? FileOperationTransaction }
    let directory: URL
    private(set) var journal: Journal
    private let fm = FileManager.default
    var fault: ((String) throws -> Void)?

    init(home: URL) throws {
        guard try home.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw failure("The workspace folder is unavailable.") }
        let id = UUID().uuidString
        directory = home.appendingPathComponent("Backups/File Transactions/" + id)
        journal = Journal(id: id)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try persist()
    }
    private init(directory: URL, journal: Journal) { self.directory = directory; self.journal = journal }
    private func persist() throws { try JSONEncoder().encode(journal).write(to: directory.appendingPathComponent("journal.json"), options: .atomic) }
    private func cleanup() throws {
        try fm.removeItem(at: directory)
        let parent = directory.deletingLastPathComponent(), backups = parent.deletingLastPathComponent()
        if (try? fm.contentsOfDirectory(atPath: parent.path).isEmpty) == true { try? fm.removeItem(at: parent) }
        if (try? fm.contentsOfDirectory(atPath: backups.path).isEmpty) == true { try? fm.removeItem(at: backups) }
    }
    private static func acquireLock(_ home: URL) throws -> Int32 {
        let path = home.appendingPathComponent(".colorgain-file-management.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw FileIssue(url: home, state: .unknown, message: "Another Colorgain process is updating these files. Wait for it to finish, then retry.")
        }
        return descriptor
    }
    private static func releaseLock(_ descriptor: Int32) { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }

    static func digest(_ url: URL) throws -> String? {
        let fm = FileManager.default
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) }
        catch { if FileIssue.wrapping(error, at: url).state == .missing { return nil }; throw error }
        guard values.isSymbolicLink != true else { throw failure("Symbolic links cannot be changed by a file transaction.") }
        if values.isDirectory != true { return try FileRevision.read(url).digest }
        var rows: [String] = ["directory"]
        for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            rows.append(child.lastPathComponent + ":" + (try digest(child) ?? "missing"))
        }
        return Sharing.sha256(Data(rows.joined(separator: "\n").utf8))
    }

    func prepare(_ url: URL, after: String?) throws {
        try fault?("before-intent")
        let before = try Self.digest(url)
        let snapshot = before == nil ? nil : "Snapshot-" + String(journal.entries.count)
        if let snapshot { try fm.copyItem(at: url, to: directory.appendingPathComponent(snapshot)) }
        journal.entries.append(Entry(path: url.path, before: before, after: after, snapshot: snapshot))
        try persist()
        try fault?("after-intent")
    }
    func commit() throws {
        try fault?("before-commit")
        journal.committed = true
        try persist()
        // Once committed, cleanup is never allowed to trigger rollback.
        do { try fault?("before-cleanup"); try cleanup() } catch { /* A committed journal is cleaned on the next successful recovery. */ }
    }
    func rollback() throws {
        var conflicts: [FileIssue] = []
        for index in journal.entries.indices.reversed() {
            let entry = journal.entries[index]
            if entry.restored == true { continue }
            let url = URL(fileURLWithPath: entry.path)
            let current = try Self.digest(url)
            if current == entry.before { journal.entries[index].restored = true; try persist(); continue }
            guard current == entry.after else {
                conflicts.append(FileIssue(url: url, state: .ambiguous, message: "This file changed outside the operation. Its current contents and recovery snapshot have both been retained.")); continue
            }
            if let snapshot = entry.snapshot {
                let source = directory.appendingPathComponent(snapshot)
                guard try Self.digest(source) == entry.before else { throw failure("A recovery snapshot is damaged. No replacement was attempted.") }
                if current != nil { try fm.removeItem(at: url) }
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: url)
            } else if current != nil { try fm.removeItem(at: url) }
            journal.entries[index].restored = true
            try persist()
        }
        guard conflicts.isEmpty else { throw FileRecoveryReport(root: directory, issues: conflicts) }
        try cleanup()
    }
    static func recover(home: URL, holdingLock: Bool = false) throws {
        executionLock.lock(); defer { executionLock.unlock() }
        if current != nil { return }
        let parent = home.appendingPathComponent("Backups/File Transactions")
        guard FileManager.default.fileExists(atPath: parent.path) else { return }
        let descriptor = holdingLock ? nil : try acquireLock(home)
        defer { if let descriptor { releaseLock(descriptor) } }
        for dir in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            guard try dir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw failure("Invalid recovery journal location.") }
            let value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: dir.appendingPathComponent("journal.json")))
            guard value.version == 1, value.id == dir.lastPathComponent,
                  value.entries.allSatisfy({ $0.path.hasPrefix("/") && ($0.snapshot == nil || $0.snapshot!.hasPrefix("Snapshot-") && !$0.snapshot!.contains("/")) }) else { throw failure("Unsupported recovery journal. Its contents have been retained.") }
            let transaction = FileOperationTransaction(directory: dir, journal: value)
            if value.committed { try? transaction.cleanup() }
            else { try transaction.rollback() }
        }
    }
    static func perform<T>(home: URL, fault: ((String) throws -> Void)? = nil, _ operation: () throws -> T) throws -> T {
        executionLock.lock(); defer { executionLock.unlock() }
        if current != nil { return try operation() }
        let descriptor = try acquireLock(home)
        defer { releaseLock(descriptor) }
        try recover(home: home, holdingLock: true)
        let transaction = try FileOperationTransaction(home: home)
        transaction.fault = fault
        Thread.current.threadDictionary[contextKey] = transaction
        defer { Thread.current.threadDictionary.removeObject(forKey: contextKey) }
        do {
            let result = try operation()
            try transaction.commit()
            return result
        } catch {
            let original = error
            try transaction.rollback()
            throw original
        }
    }
}
