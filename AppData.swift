import AppKit

/// The sole reader/writer of the app-home manifest. Catalogue contents remain in .colcat files.
struct AppDataStore {
    let root: URL
    var url: URL { root.appendingPathComponent("colorgain.coldata") }
    func read() throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Handler_File_Manager.shared.read(url)) as? [String: Any], value["version"] as? Int == 1 else {
            throw failure("The app data file is invalid or from a newer version. It has not been changed.")
        }
        return value
    }
    static func initialManifest() -> [String: Any] {
        ["version": 1, "catalogues": [], "settings": [:], "keys": "Keys/default.colkeys"]
    }
    /// Called only by an explicit legacy-workspace update action; reading never migrates.
    func migrateLegacy() throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw failure("This workspace already has a manifest.") }
        let old = root.appendingPathComponent("catalogues.json")
        let entries = try JSONDecoder().decode([Catalogues.Entry].self, from: Data(contentsOf: old))
        var value = Self.initialManifest()
        value["catalogues"] = entries.map { ["name": $0.name, "path": $0.path] }
        value["legacyMigrationPending"] = true
        if !entries.isEmpty { value["settings"] = ["assistantDone": true] }
        try write(value) // Keep catalogues.json intact as the original backup.
    }
    func write(_ value: [String: Any]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var value = value
        if value["workspaceID"] == nil {
            let existing = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            value["workspaceID"] = existing?["workspaceID"] ?? UUID().uuidString
        }
        try Handler_File_Manager.shared.write(JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), to: url)
    }
    func update(_ change: (inout [String: Any]) throws -> Void) throws {
        try Handler_File_Manager.shared.update(url, change)
    }
    func rememberDefaultCatalogue(_ name: String, id: String? = nil) throws {
        try update { manifest in
            var record: [String: Any] = ["name": name]
            if let id { record["id"] = id }
            manifest["defaultCatalogue"] = record
            var settings = manifest["settings"] as? [String: Any] ?? [:]
            settings[Catalogues.currentKey] = name
            if let id { settings["currentCatalogueID"] = id }
            else { settings.removeValue(forKey: "currentCatalogueID") }
            manifest["settings"] = settings
        }
    }
    static var current: AppDataStore { AppDataStore(root: Catalogues.standard.root) }
}

func failure(_ message: String) -> NSError { NSError(domain: "Colorgain", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

/// Portable app preferences. UserDefaults supplies the one-time legacy values and bootstrap location only.
final class AppPreferences {
    static let shared = AppPreferences()
    private let settingsCache = AppSettingsCache()
    /// Reset portable preferences while retaining workspace identity and completed setup.
    /// Tombstones prevent legacy defaults from being imported again on another machine.
    func resetUserPreferences() throws {
        let store = AppDataStore.current
        var manifest = try store.read()
        var settings = manifest["settings"] as? [String: Any] ?? [:]
        let retained: Set<String> = ["assistantDone", "setupDone", Catalogues.currentKey, "currentCatalogueID"]
        for key in settings.keys where !retained.contains(key) { settings[key] = NSNull() }
        manifest["settings"] = settings
        try store.write(manifest)
        settingsCache.invalidate()
        for key in settings.keys where !retained.contains(key) { preferences.removeObject(forKey: key) }
        NotificationCenter.default.post(name: .prefsDidChange, object: nil)
    }
    func object(forKey key: String) -> Any? {
        if CommandLine.arguments.contains("--self-test") { return preferences.object(forKey: key) }
        do {
            let settings = try settingsCache.read(AppDataStore.current)
            if let value = settings[key] {
                if value is NSNull { return nil }
                if let blob = value as? [String: String], let b64 = blob["$data"] { return Data(base64Encoded: b64) }
                return value
            }
            if let old = preferences.object(forKey: key) { return old }
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
            try Handler_File_Manager.shared.withTransaction(home: store.root) {
                try store.update { manifest in
                    var settings = manifest["settings"] as? [String: Any] ?? [:]
                    settings[key] = (value as? Data).map { ["$data": $0.base64EncodedString()] } ?? value ?? NSNull()
                    if key == "shortcuts" || key == "quickKeys" { try KeyProfiles.saveCurrent(settings: settings) }
                    manifest["settings"] = settings
                }
            }
            settingsCache.invalidate()
            preferences.set(value, forKey: key)
        } catch { FileIncidentCoordinator.report(error, at: AppDataStore.current.url) }
    }
    func rememberDefaultCatalogue(_ name: String, id: String?) {
        // Like ordinary preferences, self-tests must never reach the user's app manifest.
        if CommandLine.arguments.contains("--self-test") {
            preferences.set(name, forKey: Catalogues.currentKey)
            preferences.set(id, forKey: "currentCatalogueID")
            return
        }
        do {
            try AppDataStore.current.rememberDefaultCatalogue(name, id: id)
            settingsCache.invalidate()
            preferences.set(name, forKey: Catalogues.currentKey)
        } catch { FileIncidentCoordinator.report(error, at: AppDataStore.current.url) }
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
        let manifest = try AppDataStore.current.read()
        let url = folder.appendingPathComponent("default.colkeys")
        if !FileManager.default.fileExists(atPath: url.path), manifest["keys"] as? String == "Keys/default.colkeys" {
            throw FileIssue(url: url, state: .missing, message: "The active key profile is unavailable. Locate or restore it before replacing shortcuts.")
        }
    }
    static func read(_ url: URL) throws -> KeyProfile {
        let data = try Handler_File_Manager.shared.read(url)
        guard data.count < 1_000_000 else { throw failure("This key profile is too large.") }
        var value = try JSONDecoder().decode(KeyProfile.self, from: data)
        value.quickKeys = value.quickKeys.mapValues { $0.uppercased() }
        guard value.version == 1, value.name.count <= 120, value.description.count <= 2000, !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("This is not a supported key profile.") }
        return value
    }
    static func write(_ profile: KeyProfile, to url: URL) throws { try Handler_File_Manager.shared.write(ColourFiles.encoder().encode(profile), to: url) }
    static func list() throws -> [(URL, KeyProfile)] {
        try ensure()
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "colkeys" }
            .compactMap { url in (try? read(url)).map { (url, $0) } }
            .sorted { $0.1.name.localizedStandardCompare($1.1.name) == .orderedAscending }
    }
    static func saveCurrent(settings supplied: [String: Any]? = nil) throws {
        // Do not call ensure here: legacy preference migration may still be reading the other key map.
        try Handler_File_Manager.shared.createDirectory(folder)
        let settings = try supplied ?? (AppDataStore.current.read()["settings"] as? [String: Any] ?? [:])
        var profile: KeyProfile
        if FileManager.default.fileExists(atPath: activeURL.path) { profile = try read(activeURL) }
        else { throw FileIssue(url: activeURL, state: .missing, message: "The active keyboard profile is unavailable. Restore it or select another profile before saving shortcuts.") }
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

/// App-wide unassigned assets. Member-owned work is never stored here.
struct GlobalAssets {
    let home: URL
    static let folderName = "My Library"
    var root: URL { home.appendingPathComponent(Self.folderName,isDirectory:true) }
    private var oldRoot: URL { home.appendingPathComponent("Assets",isDirectory:true) }
    var libraryIndex:URL {root.appendingPathComponent("my_library.collib")}
    var legacyIndex:URL {root.appendingPathComponent("Assets.colcat")}
    var index:URL {FileManager.default.fileExists(atPath:libraryIndex.path) ? libraryIndex : FileManager.default.fileExists(atPath:legacyIndex.path) ? legacyIndex:libraryIndex}
    /// Move the app-wide library only when its index identifies the old Assets folder.
    /// A catalogue's own Assets pool is unrelated and must stay in place.
    func migrateWorkspaceDirectory() throws {
        let fm=FileManager.default
        let oldIndex=oldRoot.appendingPathComponent("my_library.collib")
        let oldLegacy=oldRoot.appendingPathComponent("Assets.colcat")
        let hasOldLibrary=fm.fileExists(atPath:oldIndex.path) || fm.fileExists(atPath:oldLegacy.path)
        let hasNewLibrary=fm.fileExists(atPath:libraryIndex.path) || fm.fileExists(atPath:legacyIndex.path)
        if hasOldLibrary && fm.fileExists(atPath:root.path) {
            throw FileIssue(url:root,state:.ambiguous,message:"Both Assets and My Library contain workspace files. They were left untouched so you can resolve the duplicate safely.")
        }
        if hasOldLibrary {
            try Handler_File_Manager.shared.withTransaction(home:home) {
                try Handler_File_Manager.shared.move(oldRoot,to:root)
                try AppDataStore(root:home).update{$0["assets"]=Self.folderName+"/my_library.collib"}
            }
        } else if hasNewLibrary {
            let manifest=try AppDataStore(root:home).read()
            if manifest["assets"] as? String != Self.folderName+"/my_library.collib" {
                try AppDataStore(root:home).update{$0["assets"]=Self.folderName+"/my_library.collib"}
            }
        }
    }
    var assetTypes:[String] {CatalogueTree.catalogue(in:root)?.libraryAssetTypes ?? ((try? AppDataStore(root:home).read()["libraryAssetTypes"]) as? [String]) ?? SimpleAssetType.defaultLibraryIDs}
    func setAssetTypes(_ types:[String],custom:[SimpleCustomAssetType]=[])throws {
        let known=Set(SimpleAssetType.all.map(\.id)+custom.map(\.id)+SimpleAssetType.workspaceCustomTypes(home:home).map(\.id))
        guard Set(types).count == types.count,types.allSatisfy({known.contains($0)}) else{throw failure("Unsupported library asset categories.")}
        try migrateLibraryIndex()
        guard var doc=CatalogueTree.catalogue(in:root) else{throw failure("My Library is unavailable.")}
        doc.libraryAssetTypes=types
        try Handler_File_Manager.shared.write(ColourFiles.encoder().encode(doc),to:libraryIndex)
    }
    /// Changes only the index and manifest reference; payload paths and library identity stay stable.
    func migrateLibraryIndex()throws {
        try migrateWorkspaceDirectory()
        let fm=FileManager.default,manager=Handler_File_Manager.shared
        guard fm.fileExists(atPath:legacyIndex.path),!fm.fileExists(atPath:libraryIndex.path) else{return}
        try manager.requireAvailableCatalogue(legacyIndex)
        let original=try manager.read(legacyIndex)
        var doc=try ColourFiles.decoder().decode(CatalogueFile.self,from:original)
        doc.libraryAssetTypes=doc.libraryAssetTypes ?? ((try? AppDataStore(root:home).read()["libraryAssetTypes"]) as? [String]) ?? SimpleAssetType.defaultLibraryIDs
        try manager.withTransaction(home:home) {
            let backup=home.appendingPathComponent("Backups/My Library Migration/"+UUID().uuidString+"/Assets.colcat")
            try manager.createDirectory(backup.deletingLastPathComponent())
            try manager.write(original,to:backup)
            try manager.write(ColourFiles.encoder().encode(doc),to:libraryIndex)
            try manager.requireAvailableCatalogue(libraryIndex)
            try AppDataStore(root:home).update{$0["assets"]=Self.folderName+"/my_library.collib";$0.removeValue(forKey:"libraryAssetTypes")}
            try manager.move(legacyIndex,to:backup.deletingLastPathComponent().appendingPathComponent("Original.colcat"))
        }
    }
    func load() throws -> Library {
        try migrateLibraryIndex()
        guard FileManager.default.fileExists(atPath: index.path) else {
            if FileManager.default.fileExists(atPath: AppDataStore(root: home).url.path),
               (try AppDataStore(root: home).read())["assets"] != nil { throw FileIssue(url: index, state: .missing, message: "The global assets index is unavailable. Its contents have not been recreated.") }
            return Library()
        }
        try Handler_File_Manager.shared.requireAvailableCatalogue(index)
        let cat = try ColourFiles.decoder().decode(CatalogueFile.self, from: Handler_File_Manager.shared.read(index))
        guard cat.version == 3 else { throw failure("The global Assets index is not supported.") }
        var lib = Library(); lib.tagInfo = cat.tags; lib.deleted = cat.deleted; lib.activeSwatchID = cat.activePalette
        var seenColours=Set<String>()
        for link in cat.libraryAssets {
            let doc = try PaletteAssetHandler.read(root.appendingPathComponent(link.file))
            var palette = doc.palette; palette.projectID = nil; lib.swatches.append(palette)
            for c in doc.colours where seenColours.insert(c.hex).inserted { lib.colours.append(c) }
        }
        if let file = cat.swatches {
            let doc = try ColourFiles.decoder().decode(SwatchesDocument.self, from: Handler_File_Manager.shared.read(root.appendingPathComponent(file)))
            for c in doc.colours where seenColours.insert(c.hex).inserted { lib.colours.append(c) }
        }
        if let file = cat.profiles { lib.colourProfiles = try ColourFiles.decoder().decode(ProfilesDocument.self, from: Handler_File_Manager.shared.read(root.appendingPathComponent(file))).profiles }
        return lib
    }
    func save(_ lib: Library,dirtyPalettes:Set<UUID>? = nil,previous:Library? = nil) throws {
        try migrateLibraryIndex()
        if let previous,try CatalogueTree.writePortableEdit(from:previous,to:lib,index:libraryIndex,validated:true) {return}
        if let previous,try CatalogueTree.writePortableRename(from:previous,to:lib,index:libraryIndex,validated:true) {return}
        try CatalogueTree.write(lib, schema: .init(collections: [], places: [:]), index: libraryIndex, name: Self.folderName, poolDirectory: "",dirtyPalettes:dirtyPalettes)
        if CatalogueTree.catalogue(in:root)?.libraryAssetTypes == nil {try setAssetTypes(assetTypes)}
        try AppDataStore(root: home).update { $0["assets"] = Self.folderName+"/my_library.collib";$0.removeValue(forKey:"libraryAssetTypes") }
    }
    static func split(_ lib: Library) -> (local: Library, global: Library) {
        var local = lib, global = lib
        local.swatches = lib.swatches.filter { $0.projectID != nil }
        global.swatches = lib.swatches.filter { $0.projectID == nil }; global.projects = []
        let localKeys = Set(local.swatches.flatMap { $0.entries.map { $0.hex } + ($0.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let globalKeys = Set(global.swatches.flatMap { $0.entries.map { $0.hex } + ($0.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        local.colours = lib.colours.filter { localKeys.contains($0.hex) }
        global.colours = lib.colours.filter { globalKeys.contains($0.hex) || !localKeys.contains($0.hex) }
        global.tagInfo = lib.tagInfo.filter { $0.projectID == nil && $0.groupID == nil }
        local.tagInfo = lib.tagInfo.filter { $0.projectID != nil || $0.groupID != nil }
        let profiles = Set(local.swatches.compactMap { $0.profile } + local.projects.compactMap { $0.profile })
        local.colourProfiles = lib.colourProfiles.filter { profiles.contains($0.id) }
        if !local.swatches.contains(where: { $0.id == local.activeSwatchID }) { local.activeSwatchID = nil }
        if !global.swatches.contains(where: { $0.id == global.activeSwatchID }) { global.activeSwatchID = nil }
        return (local, global)
    }
    static func joined(_ local: Library, _ global: Library) -> Library {
        var lib = local
        let globalNames=Set(global.tagInfo.map(\.name))
        lib.tagInfo.removeAll { $0.projectID == nil && $0.groupID == nil && globalNames.contains($0.name) }
        var swatchIDs=Set(lib.swatches.map(\.id))
        for swatch in global.swatches where swatchIDs.insert(swatch.id).inserted {lib.swatches.append(swatch)}
        var colourKeys=Set(lib.colours.map(\.hex))
        for colour in global.colours where colourKeys.insert(colour.hex).inserted {lib.colours.append(colour)}
        var profileIDs=Set(lib.colourProfiles.map(\.id))
        for profile in global.colourProfiles where profileIDs.insert(profile.id).inserted {lib.colourProfiles.append(profile)}
        struct TagKey:Hashable{let name:String;let project:UUID?}
        var tagKeys=Set(lib.tagInfo.map{TagKey(name:$0.name,project:$0.projectID)})
        for tag in global.tagInfo where tagKeys.insert(TagKey(name:tag.name,project:tag.projectID)).inserted {lib.tagInfo.append(tag)}
        if lib.activeSwatchID == nil { lib.activeSwatchID = global.activeSwatchID }
        return lib
    }
}

/// A recoverable journal spanning the catalogue and app-wide Assets. A failed or interrupted
/// write restores both snapshots before another read; global-to-member moves cannot lose payloads.
enum AssetTransaction {
    struct Journal: Codable { var catalogue: String; var home: String; var globalExisted: Bool }
    static func directory(_ home: URL) -> URL { home.appendingPathComponent("Backups/Asset Transaction") }
    static func items(_ root: URL, home: URL) throws -> [URL] {
        let protected: Set<String> = root.standardizedFileURL == home.standardizedFileURL
            ? ["Backups", "Assets", GlobalAssets.folderName, "Catalogues", "Keys", "colorgain.coldata", "catalogues.json", "Global.colhis"] : ["Backups"]
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { !protected.contains($0.lastPathComponent) }
    }
    static func recover(home: URL) throws {
        let file = directory(home).appendingPathComponent("journal.json")
        if FileManager.default.fileExists(atPath: file.path) {
            throw FileRecoveryReport(root: home, issues: [FileIssue(url: directory(home), state: .ambiguous,
                message: "An older recovery snapshot needs review. Current files and the snapshot have both been retained; automatic whole-folder replacement is disabled.")])
        }
        try FileOperationTransaction.recover(home: home)
    }
    static func perform(home: URL, catalogue: URL, _ operation: () throws -> Void) throws {
        try recover(home: home)
        try Handler_File_Manager.shared.withTransaction(home: home, operation)
    }

}


/// All new-home journeys use this idempotent seed before constructing a catalogue.
enum AppHomeSeed {
    static func ensure(at root: URL) throws {
        let fm = FileManager.default
        let store = AppDataStore(root: root)
        let creating = !fm.fileExists(atPath: store.url.path)
        if creating {
            if fm.fileExists(atPath: root.appendingPathComponent("Assets").path) || fm.fileExists(atPath: root.appendingPathComponent(GlobalAssets.folderName).path) || CatalogueFiles.anyIndex(in: root) != nil || fm.fileExists(atPath: root.appendingPathComponent("catalogues.json").path) {
                throw FileIssue(url: store.url, state: .missing, message: "Existing workspace files were found without their manifest. Locate/restore app data or explicitly update a legacy workspace; no fresh manifest was created.")
            }
            try Handler_File_Manager.shared.createDirectory(root)
            try store.write(AppDataStore.initialManifest())
        }
        let migrating = (try store.read())["legacyMigrationPending"] as? Bool == true
        let seeding = creating || migrating
        try GlobalAssets(home:root).migrateWorkspaceDirectory()
        if !seeding {
            try GlobalAssets(home:root).migrateLibraryIndex()
            let manifest = try store.read()
            for reference in try Handler_File_App_Data().references(manifest, at: store.url) { _ = try Handler_File_Manager.shared.read(reference.url) }
            return
        }
        try AppDataStore(root: root).update { value in
            value["assets"] = GlobalAssets.folderName+"/my_library.collib"
            value["history"] = "Global.colhis"
            if value["appbridge"] == nil { value["appbridge"] = [] }
        }
        let keys = root.appendingPathComponent("Keys")
        try fm.createDirectory(at: keys, withIntermediateDirectories: true)
        let key = keys.appendingPathComponent("default.colkeys")
        if !fm.fileExists(atPath: key.path) && seeding { try KeyProfiles.write(KeyProfile(name: "Default", description: "Your keyboard shortcuts.", shortcuts: [:], quickKeys: [:]), to: key) }
        let assets = GlobalAssets(home: root)
        if !fm.fileExists(atPath: assets.index.path) {
            guard seeding else { throw FileIssue(url: assets.index, state: .missing, message: "The global assets index is unavailable. It has not been recreated.") }
            try assets.save(Library())
        }
        let history = root.appendingPathComponent("Global.colcat")
        if !fm.fileExists(atPath: HistoryStore.url(beside: history).path) && seeding { try HistoryStore.save(StepHistory(), beside: history) }
        try Handler_File_Manager.shared.createDirectory(root.appendingPathComponent("Catalogues"))
        if migrating { try store.update { $0.removeValue(forKey: "legacyMigrationPending") } }
    }
}
