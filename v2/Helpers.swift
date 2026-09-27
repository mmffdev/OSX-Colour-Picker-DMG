import AppKit

let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"

func playShutter() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    p.arguments = [shutterPath]
    try? p.run()
}

func copyToClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}

func hexOf(_ color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    let r = Int(round(rgb.redComponent * 255))
    let g = Int(round(rgb.greenComponent * 255))
    let b = Int(round(rgb.blueComponent * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}

func colorFromHex(_ hex: String) -> NSColor? {
    guard let (r, g, b) = rgbComponents(hex) else { return nil }
    return NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
}

func plural(_ n: Int, _ word: String, _ many: String? = nil) -> String {
    "\(n) \(n == 1 ? word : (many ?? word + "s"))"
}

func symbolButton(_ symbol: String, tooltip: String, target: AnyObject, action: Selector) -> NSButton {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
    let b = NSButton(image: image, target: target, action: action)
    b.isBordered = false
    b.toolTip = tooltip
    b.setAccessibilityLabel(tooltip)
    b.contentTintColor = .secondaryLabelColor
    return b
}
