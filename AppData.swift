import AppKit

/// The sole reader/writer of the app-home manifest. Catalogue contents remain in .colcat files.
struct AppDataStore {
    let root: URL
    var url: URL { root.appendingPathComponent("colorgain.coldata") }
    func read() throws -> [String: Any] {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                  value["version"] as? Int == 1 else { throw failure("The app data file is invalid or from a newer version. It has not been overwritten.") }
            return value
        }
        let old = root.appendingPathComponent("catalogues.json")
        var value: [String: Any] = ["version": 1, "catalogues": [], "settings": [:], "keys": "Keys/default.colkeys"]
        if fm.fileExists(atPath: old.path) {
            let entries = try JSONDecoder().decode([Catalogues.Entry].self, from: Data(contentsOf: old))
            value["catalogues"] = entries.map { ["name": $0.name, "path": $0.path] }
            try write(value)
            // Keep the old index intact as a migration backup.
        }
        return value
    }
    func write(_ value: [String: Any]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    func update(_ change: (inout [String: Any]) throws -> Void) throws {
        var value = try read(); try change(&value); try write(value)
    }
    static var current: AppDataStore { AppDataStore(root: Catalogues.standard.root) }
}

func failure(_ message: String) -> NSError { NSError(domain: "Colorgain", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

/// Portable app preferences. UserDefaults supplies the one-time legacy values and bootstrap location only.
final class AppPreferences {
    static let shared = AppPreferences()
    func object(forKey key: String) -> Any? {
        if CommandLine.arguments.contains("--self-test") { return preferences.object(forKey: key) }
        do {
            let settings = try AppDataStore.current.read()["settings"] as? [String: Any] ?? [:]
            if let value = settings[key] {
                if value is NSNull { return nil }
                if let blob = value as? [String: String], let b64 = blob["$data"] { return Data(base64Encoded: b64) }
                return value
            }
            if let old = preferences.object(forKey: key) { set(old, forKey: key); return old }
        } catch { NSLog("App data: %@", error.localizedDescription) }
        return preferences.object(forKey: key)
    }
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    func integer(forKey key: String) -> Int { object(forKey: key) as? Int ?? 0 }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func set(_ value: Any?, forKey key: String) {
        if CommandLine.arguments.contains("--self-test") { preferences.set(value, forKey: key); return }
        do {
            let store = AppDataStore.current
            var manifest = try store.read()
            var settings = manifest["settings"] as? [String: Any] ?? [:]
            settings[key] = (value as? Data).map { ["$data": $0.base64EncodedString()] } ?? value ?? NSNull()
            manifest["settings"] = settings
            let isKeys = key == "shortcuts" || key == "quickKeys"
            let profileURL = KeyProfiles.activeURL
            let existed = FileManager.default.fileExists(atPath: profileURL.path)
            let previous = isKeys && existed ? try Data(contentsOf: profileURL) : nil
            if isKeys { try KeyProfiles.saveCurrent(settings: settings) }
            do { try store.write(manifest) }
            catch {
                if isKeys {
                    if let previous { try previous.write(to: profileURL, options: .atomic) }
                    else { try FileManager.default.removeItem(at: profileURL) }
                }
                throw error
            }
            preferences.set(value, forKey: key)
        } catch { NSApp.presentError(error) }
    }
}

struct KeyProfile: Codable {
    var version = 1
    var name: String
    var description: String
    var shortcuts: [String: String]
    var quickKeys: [String: String]
}

enum KeyProfiles {
    static var folder: URL { Catalogues.standard.root.appendingPathComponent("Keys", isDirectory: true) }
    static var activeURL: URL {
        let path = (try? AppDataStore.current.read()["keys"] as? String) ?? "Keys/default.colkeys"
        // Profiles always live inside Keys; a moved app home needs no path rewriting.
        return folder.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
    }
    static func ensure() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("default.colkeys")
        if !FileManager.default.fileExists(atPath: url.path) {
            let profile = KeyProfile(name: "Default", description: "Your keyboard shortcuts.", shortcuts: Prefs.shortcuts, quickKeys: Prefs.quickKeys)
            try write(profile, to: url)
        }
        try AppDataStore.current.update { if $0["keys"] == nil { $0["keys"] = "Keys/default.colkeys" } }
    }
    static func read(_ url: URL) throws -> KeyProfile {
        let data = try Data(contentsOf: url)
        guard data.count < 1_000_000 else { throw failure("This key profile is too large.") }
        var value = try JSONDecoder().decode(KeyProfile.self, from: data)
        value.quickKeys = value.quickKeys.mapValues { $0.uppercased() }
        guard value.version == 1, value.name.count <= 120, value.description.count <= 2000, !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("This is not a supported key profile.") }
        return value
    }
    static func write(_ profile: KeyProfile, to url: URL) throws { try ColourFiles.encoder().encode(profile).write(to: url, options: .atomic) }
    static func list() throws -> [(URL, KeyProfile)] {
        try ensure()
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "colkeys" }
            .compactMap { url in (try? read(url)).map { (url, $0) } }
            .sorted { $0.1.name.localizedStandardCompare($1.1.name) == .orderedAscending }
    }
    static func saveCurrent(settings supplied: [String: Any]? = nil) throws {
        // Do not call ensure here: legacy preference migration may still be reading the other key map.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = try supplied ?? (AppDataStore.current.read()["settings"] as? [String: Any] ?? [:])
        var profile: KeyProfile
        if FileManager.default.fileExists(atPath: activeURL.path) { profile = try read(activeURL) }
        else { profile = KeyProfile(name: "Default", description: "Your keyboard shortcuts.", shortcuts: [:], quickKeys: [:]) }
        profile.shortcuts = settings["shortcuts"] as? [String: String] ?? preferences.dictionary(forKey: "shortcuts") as? [String: String] ?? [:]
        profile.quickKeys = settings["quickKeys"] as? [String: String] ?? preferences.dictionary(forKey: "quickKeys") as? [String: String] ?? [:]
        try write(profile, to: activeURL)
    }
    static func validate(_ profile: KeyProfile) throws {
        let known = Set(Shortcuts.commands.map(\.id))
        guard profile.shortcuts.keys.allSatisfy({ known.contains($0) }), profile.quickKeys.keys.allSatisfy({ id in QuickKeys.commands.contains { $0.id == id } }) else { throw failure("This profile contains commands this version does not recognise.") }
        var used = [Shortcut: String]()
        for command in Shortcuts.commands {
            let encoded = profile.shortcuts[command.id]
            let shortcut = encoded.map { Shortcut(encoded: $0) } ?? Shortcuts.defaultShortcut(for: command.id)
            if let encoded = encoded, !encoded.isEmpty, Shortcut(encoded: encoded) == nil { throw failure("Invalid shortcut for \(command.title).") }
            if let shortcut = shortcut {
                guard shortcut.key.count == 1, shortcut.modifiers.rawValue & ~15 == 0 else { throw failure("Invalid key for \(command.title).") }
                if let why = Shortcuts.problem(with: shortcut, keyCode: nil, for: command.id, reserved: Shortcuts.reserved, system: [], assigned: []) { throw failure(why.message(for: shortcut)) }
                if let name = used[shortcut] { throw failure("\(command.title) and \(name) use the same shortcut.") }
                used[shortcut] = command.title
            }
        }
        var quick = Set<String>()
        for command in QuickKeys.commands {
            let key = profile.quickKeys[command.id] ?? command.fallback
            guard key.isEmpty || key.count == 1 || (key.hasPrefix("⇧") && key.count == 2) else { throw failure("Invalid quick key for \(command.title).") }
            if !key.isEmpty && !quick.insert(key).inserted { throw failure("Two quick commands use \(key).") }
        }
    }
    static func activate(_ url: URL) throws {
        let profile = try read(url); try validate(profile)
        if url.standardizedFileURL != activeURL.standardizedFileURL { try saveCurrent() }
        try AppDataStore.current.update {
            var settings = $0["settings"] as? [String: Any] ?? [:]
            settings["shortcuts"] = profile.shortcuts; settings["quickKeys"] = profile.quickKeys
            $0["settings"] = settings; $0["keys"] = "Keys/" + url.lastPathComponent
        }
        preferences.set(profile.shortcuts, forKey: "shortcuts"); preferences.set(profile.quickKeys, forKey: "quickKeys")
        Shortcuts.refresh()
    }
    static func copyIn(_ profile: KeyProfile) throws -> URL {
        try ensure(); try validate(profile)
        let base = filesystemName(profile.name).isEmpty ? "Keys" : filesystemName(profile.name)
        var url = folder.appendingPathComponent(base + ".colkeys"), index = 2
        while FileManager.default.fileExists(atPath: url.path) { url = folder.appendingPathComponent("\(base) \(index).colkeys"); index += 1 }
        try write(profile, to: url); return url
    }
}
