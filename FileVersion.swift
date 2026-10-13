import Foundation

/// Includes inode identity so atomic replacements invalidate a cache even with unchanged size/date.
struct FileVersion: Equatable {
    let modified: Date
    let bytes: UInt64
    let inode: UInt64
    static func read(_ url: URL) -> FileVersion? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileVersion(modified: modified, bytes: (attributes[.size] as? NSNumber)?.uint64Value ?? 0, inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
    }
}

final class AppSettingsCache {
    private let lock = NSLock()
    private var location: URL?
    private var version: FileVersion?
    private var settings: [String: Any] = [:]
    private var reads = 0
    var loadCount: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func invalidate() { lock.lock(); defer { lock.unlock() }; location = nil }
    func read(_ store: AppDataStore) throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let url = store.url.standardizedFileURL, stamp = FileVersion.read(url)
        if location == url, version == stamp { return settings }
        let values = try store.read()["settings"] as? [String: Any] ?? [:]
        settings = values; location = url; version = stamp; reads += 1
        return values
    }
}

/// Global history still saves on every change; only redundant decoding is skipped.
final class HistoryFileCache {
    private var location: URL?
    private var version: FileVersion?
    private var value = StepHistory()
    private(set) var loadCount = 0
    func read(beside index: URL) -> StepHistory {
        let url = HistoryStore.url(beside: index).standardizedFileURL, stamp = FileVersion.read(url)
        if location != url || stamp != version {
            value = HistoryStore.load(beside: index); location = url; version = stamp; loadCount += 1
        }
        return value
    }
    func save(_ history: StepHistory, beside index: URL) throws {
        let url = HistoryStore.url(beside: index).standardizedFileURL
        let data = try HistoryStore.encoded(history)
        try data.write(to: url, options: .atomic)
        let stamp = FileVersion.read(url)
        guard (try? Data(contentsOf: url)) == data else { location = nil; return }
        location = url; version = stamp; value = history
    }
}
