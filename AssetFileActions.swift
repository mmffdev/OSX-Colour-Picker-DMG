import AppKit

/// File-location and macOS sharing actions used by asset menus and halos.
enum AssetFileActions {
    static func relativePath(of file: URL, under root: URL?) -> String? {
        guard let root else { return nil }
        let path = file.standardizedFileURL.path
        let parent = root.standardizedFileURL.path
        let prefix = parent == "/" ? "/" : parent + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    static func copy(_ value: String, label: String, feedback: (String) -> Void) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        feedback("Copied \(label).")
    }

    static func reveal(_ file: URL?, feedback: (String) -> Void) {
        guard let file, FileManager.default.fileExists(atPath: file.path) else {
            feedback("The asset file is unavailable. Locate its source first.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    static func share(_ file: URL?, using serviceName: NSSharingService.Name, title: String, feedback: (String) -> Void) {
        guard let file, FileManager.default.isReadableFile(atPath: file.path) else {
            feedback("The asset file is unavailable. Locate its source first.")
            return
        }
        guard let service = NSSharingService(named: serviceName), service.canPerform(withItems: [file]) else {
            feedback(serviceName == .composeEmail ? "Email sharing is unavailable on this Mac." : "AirDrop is unavailable on this Mac.")
            return
        }
        if serviceName == .composeEmail { service.subject = title }
        service.perform(withItems: [file])
    }

    static func pathActions(file: URL?, root: URL?, feedback: @escaping (String) -> Void) -> [HaloAction] {
        let relative = file.flatMap { relativePath(of: $0, under: root) }
        return [
            HaloAction(id: "copy-absolute-path", label: "Copy Absolute Path", symbol: "doc.on.doc", disabled: file == nil) {
                guard let file else { return }; copy(file.path, label: "absolute path", feedback: feedback)
            },
            HaloAction(id: "copy-relative-path", label: "Copy Relative Path", symbol: "doc.on.doc", description: relative == nil ? "Available for assets inside the catalogue or My Library." : nil, disabled: relative == nil) {
                guard let relative else { return }; copy(relative, label: "relative path", feedback: feedback)
            },
            HaloAction(id: "copy-file-url", label: "Copy File URL", symbol: "link", disabled: file == nil) {
                guard let file else { return }; copy(file.absoluteString, label: "file URL", feedback: feedback)
            },
            HaloAction(id: "copy-remote-url", label: "Copy Remote File URL", symbol: "link", description: "Remote URLs require a configured server mapping.", disabled: true),
            HaloAction(id: "copy-remote-url-from", label: "Copy Remote File URL From…", symbol: "link", description: "Remote URLs require a configured server mapping.", disabled: true)
        ]
    }

    static func sharingActions(file: URL?, title: String, feedback: @escaping (String) -> Void) -> [HaloAction] {
        let missing = file.map { !FileManager.default.isReadableFile(atPath: $0.path) } ?? true
        return [
            HaloAction(id: "share-email", label: "Email", symbol: "envelope", disabled: missing) {
                share(file, using: .composeEmail, title: title, feedback: feedback)
            },
            HaloAction(id: "share-airdrop", label: "AirDrop", symbol: "airdrop", disabled: missing) {
                share(file, using: .sendViaAirDrop, title: title, feedback: feedback)
            }
        ]
    }
}
