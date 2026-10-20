import Foundation
import Darwin

/// Includes inode identity so atomic replacements invalidate a cache even with unchanged size/date.
struct FileVersion: Equatable {
    let modified: Date
    let bytes: UInt64
    let inode: UInt64
    static func read(_ url: URL) -> FileVersion? {
        var info=stat()
        let result=url.withUnsafeFileSystemRepresentation { path in
            path.map { fstatat(AT_FDCWD,$0,&info,0) } ?? -1
        }
        guard result == 0 else{return nil}
        let modified=Date(timeIntervalSince1970:Double(info.st_mtimespec.tv_sec)+Double(info.st_mtimespec.tv_nsec)/1_000_000_000)
        return FileVersion(modified:modified,bytes:UInt64(max(0,info.st_size)),inode:UInt64(info.st_ino))
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
        try HistoryStore.save(history, beside: index)
        let stamp = FileVersion.read(url)
        guard let read = try? Handler_File_Manager.shared.read(url),
              var actual = try? JSONSerialization.jsonObject(with: read) as? [String: Any],
              let intended = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { location = nil; return }
        actual.removeValue(forKey: "header")
        guard NSDictionary(dictionary: actual).isEqual(to: intended) else { location = nil; return }
        location = url; version = stamp; value = history
    }
}
