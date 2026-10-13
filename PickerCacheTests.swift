import Foundation

func runPickerCacheTests(check: (Bool, String) -> Void) {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("picker-cache-" + UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    do {
        let store = AppDataStore(root: root)
        try store.write(["version": 1, "settings": ["format": "RGB"], "catalogues": []])
        let cache = AppSettingsCache()
        for _ in 0..<1000 { _ = try cache.read(store) }
        check(cache.loadCount == 1, "Repeated preference reads decode the unchanged manifest only once")
        let stamp = FileVersion.read(store.url)!
        try store.write(["version": 1, "settings": ["format": "HEX"], "catalogues": []])
        try fm.setAttributes([.modificationDate: stamp.modified], ofItemAtPath: store.url.path)
        check(try cache.read(store)["format"] as? String == "HEX", "Atomic external replacement invalidates settings even when size/date match")
        let other = AppDataStore(root: root.appendingPathComponent("Other"))
        try other.write(["version": 1, "settings": ["format": "Lab"], "catalogues": []])
        check(try cache.read(other)["format"] as? String == "Lab", "Changing workspaces does not reuse another workspace's cached settings")
        cache.invalidate()
        check(try cache.read(store)["format"] as? String == "HEX", "Explicit reset/invalidation reloads the current manifest")
        let index = root.appendingPathComponent("Global.colcat"), historyCache = HistoryFileCache()
        var history = StepHistory(); history.record("First", library: Library(), before: nil, limit: 0)
        try historyCache.save(history, beside: index)
        for _ in 0..<1000 { _ = historyCache.read(beside: index) }
        check(historyCache.loadCount == 0 && historyCache.read(beside: index).steps.count == 1, "Saved global history is reused between picks without redundant decoding")
        history.record("External", library: Library(), before: nil, limit: 0)
        try HistoryStore.save(history, beside: index)
        check(historyCache.read(beside: index).steps.last?.title == "External", "External history updates remain visible to the next pick")
        check(ColourFormat.luv.caption("#232425").hasPrefix("CIELUV ") && ColourFormat.luv.caption("#232425") != ColourFormat.cmyk.caption("#232425"), "Swatch metadata follows the selected colour model")
        check(ColourFormat.cmyk.caption("#232425", sourceCMYK: "12, 34, 56, 78") == "CMYK 12, 34, 56, 78", "CMYK metadata preserves exact ASE source values")
    } catch { check(false, "Picker cache validation: \(error)") }
}
