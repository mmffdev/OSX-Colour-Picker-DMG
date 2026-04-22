import AppKit
import CoreGraphics

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let outDir = "/tmp/colour-dab-build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let bgColor = NSColor(red: 0xF5/255.0, green: 0xF3/255.0, blue: 0xEE/255.0, alpha: 1.0)
let segmentCount = 12

for (size, name) in sizes {
    let S = CGFloat(size)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { continue }

    // Rounded-rect background
    let radius = S * 0.2237
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(bgColor.cgColor)
    ctx.fillPath()

    // Subtle border
    ctx.addPath(bgPath)
    ctx.setStrokeColor(NSColor(white: 0, alpha: 0.06).cgColor)
    ctx.setLineWidth(S * 0.008)
    ctx.strokePath()

    let centre = CGPoint(x: S/2, y: S/2)
    let wheelR = S * 0.36
    let holeR = S * 0.11

    // Drop shadow for depth
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -S * 0.008),
        blur: S * 0.025,
        color: NSColor(white: 0, alpha: 0.18).cgColor
    )
    // Draw solid circle as shadow anchor (will be overdrawn by segments)
    ctx.beginPath()
    ctx.addEllipse(in: CGRect(x: centre.x - wheelR, y: centre.y - wheelR, width: wheelR*2, height: wheelR*2))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 12 hue segments — rotate so red is at the top
    let startOffset: CGFloat = -.pi / 2 - (.pi / CGFloat(segmentCount))
    for i in 0..<segmentCount {
        let a0 = startOffset + CGFloat(i) * (2 * .pi / CGFloat(segmentCount))
        let a1 = startOffset + CGFloat(i+1) * (2 * .pi / CGFloat(segmentCount))
        let hue = CGFloat(i) / CGFloat(segmentCount)
        let color = NSColor(hue: hue, saturation: 0.82, brightness: 0.97, alpha: 1.0)

        ctx.beginPath()
        ctx.move(to: centre)
        ctx.addArc(center: centre, radius: wheelR, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    // Hairline separators between segments (white, very thin)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.55).cgColor)
    ctx.setLineWidth(max(0.5, S * 0.003))
    for i in 0..<segmentCount {
        let a = startOffset + CGFloat(i) * (2 * .pi / CGFloat(segmentCount))
        ctx.beginPath()
        ctx.move(to: centre)
        ctx.addLine(to: CGPoint(x: centre.x + cos(a)*wheelR, y: centre.y + sin(a)*wheelR))
        ctx.strokePath()
    }

    // Centre hole — cream-coloured to match background
    ctx.beginPath()
    ctx.addEllipse(in: CGRect(x: centre.x - holeR, y: centre.y - holeR, width: holeR*2, height: holeR*2))
    ctx.setFillColor(bgColor.cgColor)
    ctx.fillPath()
    // Thin ring around hole
    ctx.addEllipse(in: CGRect(x: centre.x - holeR, y: centre.y - holeR, width: holeR*2, height: holeR*2))
    ctx.setStrokeColor(NSColor(white: 0, alpha: 0.12).cgColor)
    ctx.setLineWidth(max(0.5, S * 0.004))
    ctx.strokePath()

    // Outer ring stroke
    ctx.addEllipse(in: CGRect(x: centre.x - wheelR, y: centre.y - wheelR, width: wheelR*2, height: wheelR*2))
    ctx.setStrokeColor(NSColor(white: 0, alpha: 0.14).cgColor)
    ctx.setLineWidth(max(0.5, S * 0.005))
    ctx.strokePath()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(name)")
}
