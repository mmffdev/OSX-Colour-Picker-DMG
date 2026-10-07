import Foundation

// ---------- Keeping hold of folders the user chose ----------
//
// Under the App Sandbox (the Store build) a folder picked in an open panel can be read and written only
// until the app quits. To reach it again the app keeps a security-scoped bookmark of it and, at the next
// launch, resolves every bookmark and starts using them all, for as long as it runs. Everything else in
// the app goes on working in paths exactly as before: the sync folder, the projects folder, a moved data
// home, a catalogue registered elsewhere, a project kept in its own folder. The paths stay in the
// preferences and the catalogue files (they are what syncs between Macs and what the user reads); the
// bookmarks are this Mac's own side table, keyed by path.
//
// Outside the sandbox nothing is needed, and every call here does nothing.

enum FolderAccess {
    private static let key = "folderBookmarks"

    /// The folders whose bookmarks are in use, by path.
    private(set) static var held: [String: URL] = [:]
    /// Those of them the sandbox had to be asked to open. A folder already inside the app's own container needs no asking.
    private static var scoped: Set<String> = []

    /// Keeps hold of a folder (or file) the user has just chosen in a panel, so it stays reachable after a relaunch.
    static func remember(_ url: URL) {
        #if APPSTORE
        let path = url.standardizedFileURL.path
        guard held[path] == nil else { return }
        let data: Data
        do { data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { NSLog("FolderAccess: could not make a bookmark for %@: %@", path, error.localizedDescription); return }
        var all = stored
        all[path] = data
        stored = all
        if url.startAccessingSecurityScopedResource() { scoped.insert(path) }
        held[path] = url
        #endif
    }

    /// Lets go of a folder the app no longer needs: sync turned off, a projects folder changed.
    static func forget(_ url: URL) {
        #if APPSTORE
        let path = url.standardizedFileURL.path
        if scoped.remove(path) != nil { held[path]?.stopAccessingSecurityScopedResource() }
        held[path] = nil
        var all = stored
        all[path] = nil
        stored = all
        #endif
    }

    /// At launch: every remembered folder is opened again. A bookmark gone stale (the folder moved) is
    /// remade from where it now resolves. One that does not resolve is kept and logged: a drive not
    /// mounted or a cloud folder not yet downloaded resolves next time, and dropping it would lose the grant for good.
    static func restoreAll() {
        #if APPSTORE
        var all = stored
        for (path, data) in all {
            var stale = false
            let url: URL
            do { url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) }
            catch { NSLog("FolderAccess: could not resolve the bookmark for %@: %@", path, error.localizedDescription); continue }
            if url.startAccessingSecurityScopedResource() { scoped.insert(path) }
            held[path] = url
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                all[path] = fresh
            }
        }
        stored = all
        #endif
    }

    /// Whether a path is one the user has granted, or lies inside one.
    static func covers(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return held.keys.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static var stored: [String: Data] {
        get { preferences.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { preferences.set(newValue, forKey: key) }
    }
}
