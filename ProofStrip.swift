import AppKit
import QuartzCore

// ---------- The proof strip: a setup's journey ----------
//
// The colour bar printed along the edge of a press sheet: a registration mark at each end and one
// patch per step between them. A step's patch inks across when it is reached, crop marks snap round
// the step being worked, and every patch is named underneath. The patches are tones of one colour,
// pale for the first step and full strength for the last. Chosen by Rick on 2026-10-07 from five
// designs; built to serve every version of the app: hand it the step names and a colour.

final class ProofStrip: NSView {
    static let height: CGFloat = 86

    private let names: [String]
    private let ink: NSColor
    private(set) var step = 0
    /// A finished patch was clicked. Whoever owns the strip decides whether that goes back.
    var onPick: ((Int) -> Void)?

    private let metaLeft = CATextLayer(), metaRight = CATextLayer()
    private var marks: [CALayer] = []
    private var patches: [CALayer] = [], inks: [CALayer] = [], labels: [CATextLayer] = []
    private let crop = CAShapeLayer()
    private var labelOn: CGColor = NSColor.labelColor.cgColor, labelOff: CGColor = NSColor.secondaryLabelColor.cgColor

    private let reg: CGFloat = 22, gap: CGFloat = 3, patchTop: CGFloat = 26, patchHeight: CGFloat = 34

    init(names: [String], ink: NSColor) {
        self.names = names
        self.ink = ink
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Self.height))
        wantsLayer = true
        guard let root = layer else { return }
        for t in [metaLeft, metaRight] { style(t, weight: .regular); root.addSublayer(t) }
        metaRight.alignmentMode = .right
        for _ in 0..<2 {
            let mark = CALayer()
            let ring = CAShapeLayer(), dot = CAShapeLayer()
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: 4, y: 4, width: 12, height: 12))
            p.move(to: CGPoint(x: 10, y: 0)); p.addLine(to: CGPoint(x: 10, y: 20))
            p.move(to: CGPoint(x: 0, y: 10)); p.addLine(to: CGPoint(x: 20, y: 10))
            ring.path = p
            ring.fillColor = nil
            ring.lineWidth = 1
            dot.path = CGPath(ellipseIn: CGRect(x: 7.5, y: 7.5, width: 5, height: 5), transform: nil)
            mark.addSublayer(ring)
            mark.addSublayer(dot)
            root.addSublayer(mark)
            marks.append(mark)
        }
        for _ in names {
            let patch = CALayer(), fill = CALayer(), label = CATextLayer()
            patch.borderWidth = 1
            patch.masksToBounds = true
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.transform = CATransform3DMakeScale(0.0001, 1, 1)
            patch.addSublayer(fill)
            style(label, weight: .regular)
            root.addSublayer(patch)
            root.addSublayer(label)
            patches.append(patch); inks.append(fill); labels.append(label)
        }
        crop.fillColor = nil
        crop.lineWidth = 1
        root.addSublayer(crop)
        colour()
        set(step: 0, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    private func style(_ t: CATextLayer, weight: NSFont.Weight) {
        t.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: weight)
        t.fontSize = TextSize.caption
        t.truncationMode = .end
        t.isWrapped = false
        t.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// The tone a step's patch is inked in: the paper for none of the colour, the colour at full strength for the last step.
    static func tone(step i: Int, of count: Int, ink: NSColor, paper: NSColor) -> NSColor {
        let strength = 0.30 + 0.70 * CGFloat(i) / CGFloat(max(1, count - 1))
        let i = ink.usingColorSpace(.sRGB) ?? ink, p = paper.usingColorSpace(.sRGB) ?? paper
        return p.blended(withFraction: strength, of: i) ?? i
    }

    private func colour() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let paper = NSColor.windowBackgroundColor
            for (i, fill) in inks.enumerated() { fill.backgroundColor = Self.tone(step: i, of: names.count, ink: ink, paper: paper).cgColor }
            for p in patches {
                p.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
                p.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            }
            let line = NSColor.labelColor.withAlphaComponent(0.7).cgColor
            for m in marks {
                (m.sublayers?[0] as? CAShapeLayer)?.strokeColor = line
                (m.sublayers?[1] as? CAShapeLayer)?.fillColor = line
            }
            crop.strokeColor = NSColor.labelColor.cgColor
            labelOn = NSColor.labelColor.cgColor
            labelOff = NSColor.secondaryLabelColor.cgColor
            metaLeft.foregroundColor = labelOff
            metaRight.foregroundColor = labelOff
        }
        paintLabels()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colour() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for t in [metaLeft, metaRight] + labels { t.contentsScale = scale }
    }

    private func patchFrame(_ i: Int) -> CGRect {
        let n = CGFloat(names.count)
        let width = (bounds.width - 2 * reg - (n + 1) * gap) / n
        return CGRect(x: reg + gap + CGFloat(i) * (width + gap), y: bounds.height - patchTop - patchHeight, width: width, height: patchHeight)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = bounds.width, h = bounds.height
        metaLeft.frame = CGRect(x: 0, y: h - 14, width: w / 2, height: 14)
        metaRight.frame = CGRect(x: w / 2, y: h - 14, width: w / 2, height: 14)
        let py = h - patchTop - patchHeight
        marks[0].frame = CGRect(x: 0, y: py + (patchHeight - 20) / 2, width: 20, height: 20)
        marks[1].frame = CGRect(x: w - 20, y: py + (patchHeight - 20) / 2, width: 20, height: 20)
        for i in names.indices {
            let f = patchFrame(i)
            patches[i].frame = f
            inks[i].bounds = CGRect(origin: .zero, size: f.size)
            inks[i].position = CGPoint(x: 0, y: f.height / 2)
            labels[i].frame = CGRect(x: f.minX, y: py - 9 - 14, width: f.width, height: 14)
        }
        placeCrop()
        crop.path = cropPath(crop.bounds.size)
        CATransaction.commit()
    }

    private func placeCrop() {
        let f = patchFrame(step).insetBy(dx: -6, dy: -6)
        crop.bounds = CGRect(origin: .zero, size: f.size)
        crop.position = CGPoint(x: f.midX, y: f.midY)
    }

    private func cropPath(_ s: CGSize) -> CGPath {
        let p = CGMutablePath(), l: CGFloat = 7
        for (x, dx) in [(CGFloat(0), CGFloat(1)), (s.width, -1)] {
            for (y, dy) in [(CGFloat(0), CGFloat(1)), (s.height, -1)] {
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + dy * l))
            }
        }
        return p
    }

    private func paintLabels() {
        for (i, t) in labels.enumerated() {
            t.string = String(format: "%02d %@", i + 1, names[i])
            t.foregroundColor = i <= step ? labelOn : labelOff
            t.font = NSFont.monospacedDigitSystemFont(ofSize: TextSize.caption, weight: i == step ? .semibold : .regular)
        }
        metaLeft.string = "SETUP PROOF \u{00B7} \(names.count) PATCHES"
        metaRight.string = String(format: "PATCH %02d / %02d", step + 1, names.count)
    }

    /// Inks every patch up to `s`, and moves the crop marks onto it.
    func set(step s: Int, animated: Bool) {
        let moved = s != step
        step = max(0, min(names.count - 1, s))
        let motion = animated && moved && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(!motion)
        CATransaction.setAnimationDuration(0.42)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        for (i, fill) in inks.enumerated() { fill.transform = CATransform3DMakeScale(i <= step ? 1 : 0.0001, 1, 1) }
        placeCrop()
        paintLabels()
        CATransaction.commit()
        if motion {
            let pop = CAAnimationGroup()
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.25; scale.toValue = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            pop.animations = [scale, fade]
            pop.duration = 0.35
            pop.beginTime = CACurrentMediaTime() + 0.12
            pop.fillMode = .backwards
            pop.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.15)
            crop.add(pop, forKey: "pop")
        }
        setAccessibilityLabel("Step \(step + 1) of \(names.count), \(names[step])")
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = names.indices.first(where: { patchFrame($0).insetBy(dx: 0, dy: -24).contains(p) }), i < step else { return }
        onPick?(i)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .progressIndicator }
}
