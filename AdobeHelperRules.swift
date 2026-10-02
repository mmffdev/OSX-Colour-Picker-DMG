import Foundation

// ---------- The Adobe helper's rules ----------
//
// Shared by the app and its helper. The helper runs as root, started by the system once the user has
// allowed it in System Settings ▸ General ▸ Login Items, so that adding a palette to an Adobe app
// needs no password. It does one thing: write a swatch file into an Adobe library folder. Everything
// here exists to make sure it can be made to do nothing else.

@objc protocol AdobeHelperProtocol {
    /// Writes the file. Replies with nil, or with why it would not.
    func install(_ data: Data, named name: String, inFolder folder: String, reply: @escaping (String?) -> Void)
}

enum AdobeHelperRules {
    static let service = "com.mmffdev.mmffdevcolour3.helper"
    static let plistName = "com.mmffdev.mmffdevcolour3.helper.plist"
    /// A swatch file is a few kilobytes. Nothing near this size is one.
    static let maxBytes = 4 << 20

    /// Only code signed by us, with a Developer ID, may talk to the helper, and the app talks only to such a helper.
    private static let ours = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"6QVKGBRP5J\""
    static let appRequirement = "identifier \"com.mmffdev.mmffdevcolour3\" and " + ours
    static let helperRequirement = "identifier \"\(service)\" and " + ours

    /// Why this file may not go in this folder, or nil when it may. Looks only at the words:
    /// the helper also checks what is really on disk.
    static func refusal(name: String, folder: String, bytes: Int) -> String? {
        guard bytes > 0, bytes <= maxBytes else { return "The file is empty or too large to be a swatch file." }
        let kinds = ["ase", "aco", "acb", "act"]
        guard !name.isEmpty, name.utf8.count <= 200, !name.hasPrefix("."), !name.contains("/"), !name.contains("\0"),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              kinds.contains((name as NSString).pathExtension.lowercased()) else { return "That is not the name of a swatch file." }
        let parts = folder.components(separatedBy: "/")
        // "/Applications/Adobe Photoshop 2026/Presets/Color Books" → ["", "Applications", "Adobe Photoshop 2026", …]
        guard parts.count >= 5, parts[0] == "", parts[1] == "Applications" else { return "That is not an Adobe library folder." }
        let app = parts[2].components(separatedBy: " ")
        guard app.count == 3, app[0] == "Adobe", app[2].count == 4, app[2].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return "That is not an Adobe library folder."
        }
        let rest = Array(parts.dropFirst(3))
        switch app[1] {
        case "Photoshop" where rest == ["Presets", "Color Books"] || rest == ["Presets", "Color Swatches"]: return nil
        case "InDesign" where rest == ["Presets", "Swatch Libraries"]: return nil
        case "Illustrator" where rest.count == 3 && rest[0] == "Presets.localized" && rest[2] == "Swatches"
            && !rest[1].isEmpty && rest[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_") }): return nil
        default: return "That is not an Adobe library folder."
        }
    }
}
