import AppKit
import AppIntents

// ---------- Pick Colour, for Shortcuts ----------
//
// The `--pick` command line mode, offered to Shortcuts: a shortcut can run it from any app and bind
// it to a key of the user's own, which is what a Store app offers instead of a path to its binary.
// It does what `--pick` does: the loupe, the pick added to the library, its text on the clipboard,
// the hex returned. Shortcuts sees it in the build Xcode makes; the direct download keeps `--pick`.

struct PickColourIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick Colour"
    static let description = IntentDescription("Picks a colour anywhere on the screen with the loupe, adds it to the library, copies it, and gives back its hex.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        FolderAccess.restoreAll()
        let picked: String? = await withCheckedContinuation { done in
            NSColorSampler().show { color in
                guard let color = color, let seen = ColourDefinition.picked(color) else { done.resume(returning: nil); return }
                var key: String?
                _ = try? LibraryStore.standard.mutate { key = $0.addPick(seen) }
                if let hex = key { copyToClipboard(Prefs.copyText(hex)); playShutter() }
                done.resume(returning: key)
            }
        }
        guard let hex = picked else { throw PickError.nothingPicked }
        return .result(value: hex)
    }
}

enum PickError: Error, CustomLocalizedStringResourceConvertible {
    case nothingPicked
    var localizedStringResource: LocalizedStringResource { "No colour was picked." }
}

/// Listed in Shortcuts and Spotlight without the user adding anything.
struct ColourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PickColourIntent(), phrases: ["Pick a colour with \(.applicationName)"],
                    shortTitle: "Pick Colour", systemImageName: "eyedropper")
    }
}
