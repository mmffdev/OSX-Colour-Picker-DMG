// Not in the Store build: a root helper and an administrator password are both outside the sandbox.
#if !APPSTORE
import Foundation
import ServiceManagement

// ---------- The Adobe helper, from the app's side ----------
//
// Turning it on registers the helper inside this app with the system, which asks the user to allow it
// in System Settings ▸ General ▸ Login Items. From then on palettes go into Adobe's folders without a
// password. Off, or anything going wrong, and the app falls back to asking for the password each time.

enum AdobeHelper {
    enum State { case unsupported, wrongPlace, off, needsApproval, on }

    static var state: State {
        guard #available(macOS 13.0, *) else { return .unsupported }
        // A helper that runs as root must not live where any program could quietly swap it for another.
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return .wrongPlace }
        switch SMAppService.daemon(plistName: AdobeHelperRules.plistName).status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Registers the helper. Where the user has yet to allow it, opens the place in System Settings to do so.
    static func turnOn() throws {
        guard #available(macOS 13.0, *), state != .wrongPlace else { return }
        let service = SMAppService.daemon(plistName: AdobeHelperRules.plistName)
        do { try service.register() } catch {
            // Registering reports "not permitted" until the user allows it; that is the next step, not a failure.
            guard service.status == .requiresApproval else { throw error }
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    static func turnOff() throws {
        guard #available(macOS 13.0, *) else { return }
        try SMAppService.daemon(plistName: AdobeHelperRules.plistName).unregister()
    }

    /// Has the helper write the files into an Adobe library folder. False when it is off, when the folder
    /// is not one it serves, or when anything fails: the caller then asks for the password instead.
    static func install(_ files: [URL], into folder: URL) -> Bool {
        guard #available(macOS 13.0, *), state == .on else { return false }
        let loaded = files.compactMap { f in (try? Data(contentsOf: f)).map { (f.lastPathComponent, $0) } }
        guard loaded.count == files.count,
              loaded.allSatisfy({ AdobeHelperRules.refusal(name: $0.0, folder: folder.path, bytes: $0.1.count) == nil }) else { return false }
        let connection = NSXPCConnection(machServiceName: AdobeHelperRules.service, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AdobeHelperProtocol.self)
        connection.setCodeSigningRequirement(AdobeHelperRules.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }
        var ok = true
        guard let helper = connection.synchronousRemoteObjectProxyWithErrorHandler({ _ in ok = false }) as? AdobeHelperProtocol else { return false }
        for (name, data) in loaded where ok {
            helper.install(data, named: name, inFolder: folder.path) { if $0 != nil { ok = false } }
        }
        return ok
    }
}

// ---------- Adobe access, whichever way it is granted ----------
//
// One switch for the user: "add palettes to Adobe apps without a password". In /Applications it is
// kept by the helper above. Anywhere else, or on an older macOS, the user's own account is given
// leave to add files to the Adobe library folders instead: one password, then none, until Adobe's
// yearly upgrade replaces the folders.

enum AdobeAccess {
    enum Way { case helper, unlock }
    enum State { case on, waiting, off, nothingToDo }

    static var way: Way {
        switch AdobeHelper.state {
        case .unsupported, .wrongPlace: return .unlock
        default: return .helper
        }
    }

    /// The Adobe library folders on this Mac, each once.
    static var folders: [URL] {
        var seen: [URL] = []
        for d in AdobeDestination.installed() where !seen.contains(d.folder) { seen.append(d.folder) }
        return seen
    }

    static var state: State {
        let folders = self.folders
        guard !folders.isEmpty else { return .nothingToDo }
        if folders.allSatisfy(unlocked) { return .on }
        switch way {
        case .unlock: return .off
        case .helper:
            switch AdobeHelper.state {
            case .on: return .on
            case .needsApproval: return .waiting
            default: return .off
            }
        }
    }

    /// What the folders would grant the user: adding files and replacing them.
    static let grant = "allow add_file,delete_child,file_inherit,directory_inherit"

    /// Whether this account may already add files to `folder`, by the folder's own access rules.
    static func unlocked(_ folder: URL) -> Bool {
        guard let acl = acl_get_file(folder.path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard let text = acl_to_text(acl, nil) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(text)) }
        return grantsAdding(String(cString: text), user: NSUserName(), uid: getuid())
    }

    /// Reads the text macOS gives for a folder's rules, such as
    /// "user:<uuid>:rick:501:allow,file_inherit,directory_inherit:write,delete_child".
    static func grantsAdding(_ aclText: String, user: String, uid: uid_t) -> Bool {
        aclText.split(separator: "\n").contains { line in
            let f = line.split(separator: ":", omittingEmptySubsequences: false)
            guard f.count == 6, f[0] == "user", f[2] == Substring(user), f[3] == Substring(String(uid)) else { return false }
            let how = f[4].split(separator: ","), what = f[5].split(separator: ",")
            return how.first == "allow" && what.contains("write") && what.contains("delete_child")
        }
    }

    /// Grants or withdraws access. False when the user cancelled the password dialog.
    static func turnOn() throws -> Bool {
        if way == .helper { try AdobeHelper.turnOn(); return true }
        let apps = AdobeDestination.installed().map { $0.app }
        let prompt = "\(Brand.name) wants to let your account add swatch files to the library folders of \(list(apps))."
        return try runAsAdministrator(["/bin/chmod", "+a", "user:\(NSUserName()) \(grant)"] + folders.map { $0.path }, prompt: prompt) == .copied
    }

    static func turnOff() throws -> Bool {
        if way == .helper { try AdobeHelper.turnOff() }
        let open = folders.filter(unlocked)
        guard !open.isEmpty else { return true }
        let prompt = "\(Brand.name) wants to take back your account's leave to add swatch files to Adobe's library folders."
        return try runAsAdministrator(["/bin/chmod", "-a", "user:\(NSUserName()) \(grant)"] + open.map { $0.path }, prompt: prompt) == .copied
    }

    private static func list(_ names: [String]) -> String {
        var names = names
        var seen: [String] = []
        names = names.filter { if seen.contains($0) { return false }; seen.append($0); return true }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
}
#endif
