import AppKit
import QuartzCore

/// A01 / Centre Out: upright swatches converge into a balanced spectral field.
/// Core Animation runs the entrance while the main window is being prepared.
final class SplashWindowController: NSWindowController {
    private var completionTimer: Timer?
    private var completion: (() -> Void)?
    private static let size = NSSize(width: 680, height: 424)

    init() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.title = "Colorgain"
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(completion: @escaping () -> Void) {
        self.completion = completion
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let content = NSView(frame: NSRect(origin: .zero, size: Self.size))
        content.wantsLayer = true
        let root = content.layer!
        root.backgroundColor = Self.rgb(0x161A22).cgColor
        root.cornerRadius = 16
        root.masksToBounds = true
        window?.contentView = content

        let field = CALayer()
        field.frame = content.bounds
        root.addSublayer(field)
        // Match the selected concept's 15 × 7 field and neutral centre.
        for x in -7...7 {
            for y in -3...3 {
                let swatch = CALayer()
                let colour = x == 0 && y == 0 ? Self.rgb(0xF7EFDD)
                    : Self.hsl(hue: Double(190 + x * 12 + abs(y) * 5),
                               saturation: 0.64, lightness: Double(65 - abs(y) * 4) / 100)
                swatch.backgroundColor = colour.cgColor
                swatch.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
                let target = CGPoint(x: 340 + x * 25, y: 270 - y * 25)
                swatch.position = target
                field.addSublayer(swatch)
                if !reducedMotion {
                    let delay = Double(abs(x) + abs(y)) * 0.022
                    let duration = (0.82 + delay * 0.35 - delay) * 3
                    let entrance = CAAnimationGroup()
                    entrance.animations = [Self.animation("position", from: NSValue(point: NSPoint(x: 340, y: 270)), to: NSValue(point: target), duration: duration),
                                           Self.animation("transform.scale", from: 0.15, to: 1, duration: duration),
                                           Self.animation("opacity", from: 0, to: 1, duration: duration)]
                    entrance.beginTime = CACurrentMediaTime() + delay * 3
                    entrance.duration = duration
                    entrance.fillMode = .backwards
                    swatch.add(entrance, forKey: "entrance")
                }
            }
        }

        let brand = NSView(frame: NSRect(x: 20, y: 53, width: 640, height: 70))
        brand.wantsLayer = true
        content.addSubview(brand)
        let name = Self.label("Colorgain", font: NSFont(name: "AvenirNext-DemiBold", size: 49)
                             ?? NSFont.systemFont(ofSize: 49, weight: .semibold), colour: Self.rgb(0xF5F4EF))
        name.frame = NSRect(x: 0, y: 20, width: 640, height: 59)
        brand.addSubview(name)
        let tagline = Self.label("One palette. Every possibility.", font: .systemFont(ofSize: 13), colour: Self.rgb(0xBDC4CC))
        tagline.frame = NSRect(x: 0, y: 0, width: 640, height: 20)
        brand.addSubview(tagline)
        let footer = Self.label("Colour profile management", font: .systemFont(ofSize: 11), colour: Self.rgb(0xB8C1C8))
        footer.alignment = .left
        footer.frame = NSRect(x: 24, y: 15, width: 400, height: 19)
        content.addSubview(footer)
        if !reducedMotion, let layer = brand.layer {
            let entrance = CAAnimationGroup()
            entrance.animations = [Self.animation("opacity", from: 0.2, to: 1, duration: 1.8),
                                   Self.animation("transform.translation.y", from: -12, to: 0, duration: 1.8)]
            entrance.beginTime = CACurrentMediaTime() + 0.69
            entrance.duration = 1.8
            entrance.fillMode = .backwards
            layer.add(entrance, forKey: "brandEntrance")
        }
        window?.orderFrontRegardless()
        content.displayIfNeeded()
        CATransaction.flush()
        // The complete three-second entrance includes a short settled hold.
        completionTimer = Timer.scheduledTimer(withTimeInterval: reducedMotion ? 0.35 : 3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.completionTimer = nil
            let finished = self.completion
            self.completion = nil
            finished?()
        }
    }

    override func close() {
        completionTimer?.invalidate()
        completionTimer = nil
        completion = nil
        super.close()
    }

    private static func label(_ text: String, font: NSFont, colour: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = colour
        label.alignment = .center
        return label
    }

    /// A smooth ease-out matching the prototype's deliberate, non-spring motion.
    private static func animation(_ key: String, from: Any, to: Any, duration: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        return animation
    }

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                green: Double((value >> 8) & 255) / 255,
                blue: Double(value & 255) / 255, alpha: 1)
    }

    private static func hsl(hue: Double, saturation: Double, lightness: Double) -> NSColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let components: (Double, Double, Double)
        switch h {
        case ..<1: components = (chroma, x, 0)
        case ..<2: components = (x, chroma, 0)
        case ..<3: components = (0, chroma, x)
        case ..<4: components = (0, x, chroma)
        case ..<5: components = (x, 0, chroma)
        default: components = (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return NSColor(srgbRed: components.0 + m, green: components.1 + m, blue: components.2 + m, alpha: 1)
    }
}
