import Foundation

// The Adobe helper. Started by the system, as root, when the app asks for it; gone again when idle.
// See AdobeHelperRules.swift for what it will and will not do.

final class Helper: NSObject, NSXPCListenerDelegate, AdobeHelperProtocol {
    private var requests = 0

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The system drops any message from a caller that is not our signed app.
        connection.setCodeSigningRequirement(AdobeHelperRules.appRequirement)
        connection.exportedInterface = NSXPCInterface(with: AdobeHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func install(_ data: Data, named name: String, inFolder folder: String, reply: @escaping (String?) -> Void) {
        reply(write(data, named: name, inFolder: folder))
        leaveWhenIdle()
    }

    private func write(_ data: Data, named name: String, inFolder folder: String) -> String? {
        if let no = AdobeHelperRules.refusal(name: name, folder: folder, bytes: data.count) { return no }
        let fm = FileManager.default
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        // The folder must be the real thing: no link leading elsewhere, and installed by an administrator
        // (owned by root), which a folder somebody made up to look like Adobe's would not be.
        var dir: ObjCBool = false
        guard url.resolvingSymlinksInPath().path == folder, fm.fileExists(atPath: folder, isDirectory: &dir), dir.boolValue,
              (try? fm.attributesOfItem(atPath: folder))?[.ownerAccountID] as? Int == 0 else { return "That is not an Adobe library folder." }
        let file = url.appendingPathComponent(name)
        // Only ever replace a plain file. `attributesOfItem` does not follow a link, so a link is seen as one.
        if let type = (try? fm.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType, type != .typeRegular {
            return "Something that is not a file is already there under that name."
        }
        do {
            try data.write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Nothing to do for a while: go. The system starts the helper again when it is next wanted.
    func leaveWhenIdle() {
        requests += 1
        let seen = requests
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { if self.requests == seen { exit(0) } }
    }
}

let helper = Helper()
let listener = NSXPCListener(machServiceName: AdobeHelperRules.service)
listener.delegate = helper
listener.resume()
helper.leaveWhenIdle()
RunLoop.main.run()
