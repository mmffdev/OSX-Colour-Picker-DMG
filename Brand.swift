import AppKit

// ---------- The product's name and its own colour ----------
//
// Since 2026-10-07 the app is Colorgain: one word, capital C, American "Color". It ships as two
// editions, Colorgain Studio (the full app, built first) and Colorgain Light (what it keeps is
// decided as Studio is built). New text takes the names from here, so the rename of what is still
// "MMFFDev Colour 3" (bundle, folders, feed) has one place to look. Everything else keeps British
// spelling.

enum Brand {
    static let name = "Colorgain"
    static let studio = "Colorgain Studio"
    static let light = "Colorgain Light"
    /// What this build calls itself: Studio, until the Light edition exists.
    static let edition = studio
    /// The wordmark as text, lowercase and bold, until there is a logo.
    static let wordmark = "colorgain"
    /// Colorgain's own master colour, Blue Ribbon: the footer's current colour and the halo's wedge. Not a UI accent.
    static let masterHex = "#2456F5"
    static let masterName = "Blue Ribbon"
    static let master = NSColor(srgbRed: 0x24 / 255, green: 0x56 / 255, blue: 0xF5 / 255, alpha: 1)
}
