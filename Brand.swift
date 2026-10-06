import AppKit

// ---------- The product's name and its own colour ----------
//
// Since 2026-10-07 the app is Colorgain: one word, capital C, American "Color". New text takes the
// name from here, so the rename of what is still "MMFFDev Colour 3" (bundle, folders, feed) has one
// place to look. Everything else in the app keeps British spelling.

enum Brand {
    static let name = "Colorgain"
    /// Colorgain's own master colour, Blue Ribbon. The setup's proof strip and its leading button are inked in it.
    static let masterHex = "#2456F5"
    static let masterName = "Blue Ribbon"
    static let master = NSColor(srgbRed: 0x24 / 255, green: 0x56 / 255, blue: 0xF5 / 255, alpha: 1)
}
