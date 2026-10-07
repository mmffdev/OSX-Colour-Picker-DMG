import AppKit
import QuartzCore

// ---------- The step cards: the wizard's journey ----------
//
// Eight cards in a row along the bottom of the wizard, 4 apart: the step's name in the pale top,
// its number large and thin in the coloured chip, flush right and bottom. Finished cards are solid,
// the current card carries a moving barber pole and stays level, cards to come wait at a third of
// their colour. On first open they fly in from the right and settle together. Chosen by Rick on
// 2026-10-07 from the Spotify concept he loves; built for every version of the app.

final class StepCards: NSView {
    static let labelHeight: CGFloat = 58, chipHeight: CGFloat = 66, gap: CGFloat = 4
    static var height: CGFloat { labelHeight + chipHeight }

    private let names: [String]
    private(set) var step = 0
    /// A finished card was clicked. Whoever owns the cards decides whether that goes back.
    var onPick: ((Int) -> Void)?
    private var cards: [Card] = []

    init(names: [String]) {
        self.names = names
        super.init(frame: .zero)
        wantsLayer = true
        for (i, n) in names.enumerated() {
            let c = Card(index: i, name: n, colour: Design.step(i))
            c.translatesAutoresizingMaskIntoConstraints = false
            addSubview(c)
            cards.append(c)
        }
        set(step: 0, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    override func layout() {
        super.layout()
        let n = CGFloat(cards.count)
        let w = (bounds.width - (n - 1) * Self.gap) / n
        for (i, c) in cards.enumerated() { c.frame = NSRect(x: (CGFloat(i) * (w + Self.gap)).rounded(), y: 0, width: w.rounded(), height: bounds.height) }
    }

    func set(step s: Int, animated: Bool) {
        step = max(0, min(names.count - 1, s))
        for (i, c) in cards.enumerated() { c.state = i < step ? .done : i == step ? .current : .toCome }
        setAccessibilityLabel("Step \(step + 1) of \(names.count), \(names[step])")
    }

    /// The cards arrive from the right, one after another, and settle together.
    func enter() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let now = CACurrentMediaTime()
        for (i, c) in cards.enumerated() {
            guard let l = c.layer else { continue }
            let g = CAAnimationGroup()
            let move = CABasicAnimation(keyPath: "transform.translation.x"); move.fromValue = 120; move.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1
            g.animations = [move, fade]
            g.duration = 0.9
            g.beginTime = now + Double(i) * 0.07
            g.fillMode = .backwards
            g.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            l.add(g, forKey: "arrive")
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = cards.firstIndex(where: { $0.frame.contains(p) }), i < step else { return }
        onPick?(i)
    }


    // MARK: One card

    final class Card: NSView {
        enum State { case done, current, toCome }
        let colour: Design.StepColour
        private let label: NSTextField
        private let numeral: NSTextField
        private let chip = CALayer()
        private let pole = CALayer()
        var state: State = .toCome { didSet { paint() } }

        init(index: Int, name: String, colour: Design.StepColour) {
            self.colour = colour
            label = Design.text(name, .body)
            numeral = Design.text("", .numeral, size: 40)
            numeral.attributedStringValue = Design.attributed(String(format: "%02d", index + 1), .numeral, size: 40, align: .right)
            numeral.alignment = .right
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            layer?.backgroundColor = Design.card.cgColor
            chip.masksToBounds = true
            layer?.addSublayer(chip)
            pole.isHidden = true
            layer?.insertSublayer(pole, at: 0)
            for v in [label, numeral] { addSubview(v) }
            label.lineBreakMode = .byTruncatingTail
            paint()
        }
        required init?(coder: NSCoder) { fatalError() }

        /// The card is placed by frame, so its pieces are too: the name 9 under the top at the left, the numeral flush right and bottom.
        override func layout() {
            super.layout()
            let ls = label.attributedStringValue.size(), ns = numeral.attributedStringValue.size()
            // A text cell pads its text by a few points each side, so each field gets the card's width and aligns itself.
            label.frame = NSRect(x: 8, y: bounds.height - 9 - ls.height, width: max(0, bounds.width - 14), height: ls.height)
            numeral.frame = NSRect(x: 6, y: 1, width: max(0, bounds.width - 12), height: ns.height + 2)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            chip.frame = CGRect(x: 0, y: 0, width: bounds.width, height: StepCards.chipHeight)
            pole.frame = CGRect(x: -40, y: StepCards.chipHeight, width: bounds.width + 80, height: StepCards.labelHeight)
            if state == .current { pole.contents = Card.stripes(colour: Design.card, width: Int(bounds.width + 80), height: Int(StepCards.labelHeight), scale: window?.backingScaleFactor ?? 2) }
            CATransaction.commit()
        }

        private func paint() {
            // The step being worked is the one colour and a quiet pole moves through its white box; the
            // rest are the grey. The eight step colours wait in Design.
            CATransaction.begin(); CATransaction.setDisableActions(true)
            pole.removeAllAnimations()
            pole.isHidden = state != .current
            switch state {
            case .done:
                chip.backgroundColor = Design.inactive.cgColor
                label.alphaValue = 1; numeral.alphaValue = 1
            case .current:
                chip.backgroundColor = Design.active.cgColor
                label.alphaValue = 1; numeral.alphaValue = 1
                needsLayout = true
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let a = CABasicAnimation(keyPath: "transform.translation.x")
                    a.fromValue = 0; a.toValue = 28.28; a.duration = 1.4; a.repeatCount = .infinity
                    pole.add(a, forKey: "pole")
                }
            case .toCome:
                chip.backgroundColor = Design.inactive.cgColor
                label.alphaValue = 0.55; numeral.alphaValue = 1
            }
            CATransaction.commit()
        }

        /// The barber pole: 10 on, 10 off, at −45°, the off stripe a paler tone of the same colour.
        static func stripes(colour: NSColor, width: Int, height: Int, scale: CGFloat) -> CGImage? {
            let w = Int(CGFloat(width) * scale), h = Int(CGFloat(height) * scale)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(colour.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(Design.mix(colour, Design.ink, 0.035).cgColor)
            let period = 28.28 * scale, band = 10 * scale * 1.414
            var x = -CGFloat(h)
            while x < CGFloat(w) + CGFloat(h) {
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + band, y: 0))
                ctx.addLine(to: CGPoint(x: x + band + CGFloat(h), y: CGFloat(h))); ctx.addLine(to: CGPoint(x: x + CGFloat(h), y: CGFloat(h)))
                ctx.closePath(); ctx.fillPath()
                x += period
            }
            return ctx.makeImage()
        }
    }
}
