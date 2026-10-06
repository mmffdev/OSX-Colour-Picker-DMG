import AppKit
import QuartzCore

// ---------- The setup frame ----------
//
// The window every version of the app sets itself up in: the proof strip across the top, a page
// for the step being worked, and a bar along the bottom with the step's hint on the left and its
// buttons on the right. Moving to another step is animated: the page rolls out, and the new one
// rolls in with its pieces arriving one after another, quickly. Reduce Motion shows each step with
// no movement. The steps themselves belong to whoever uses the frame (SetupAssistant, for this app).

final class SetupFrame: NSView {
    static let size = NSSize(width: 760, height: 728)
    static let side: CGFloat = 28
    /// The width a step's own content may take.
    static let pageWidth: CGFloat = size.width - 2 * side

    let strip: ProofStrip
    let titleLabel = NSTextField(labelWithString: "")
    let body = NSStackView()
    let hint = NSTextField(labelWithString: "")
    let back = ThemedButton(title: "Back", image: nil, target: nil, action: nil)
    let skip = ThemedButton(title: "Skip", image: nil, target: nil, action: nil)
    let primary = ThemedButton(title: "Continue", image: nil, target: nil, action: nil)
    private let page = NSView()
    private let column: NSStackView

    init(steps: [String], ink: NSColor) {
        strip = ProofStrip(names: steps, ink: ink)
        column = NSStackView(views: [titleLabel, body])
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        titleLabel.font = PageStyle.titleFont
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 14
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 18
        hint.font = NSFont.systemFont(ofSize: TextSize.caption)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        primary.prominent = ink
        primary.keyEquivalent = "\r"

        page.wantsLayer = true
        page.layer?.masksToBounds = true
        let rule = NSBox()
        rule.boxType = .separator
        let bar = ActionBar(leading: [hint], trailing: [back, skip, primary])
        bar.setGap(10, after: back)

        for v in [strip, page, rule, bar, column] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(strip); addSubview(page); addSubview(rule); addSubview(bar)
        page.addSubview(column)
        let s = Self.side
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: s),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -s),
            strip.heightAnchor.constraint(equalToConstant: ProofStrip.height),
            page.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 6),
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.bottomAnchor.constraint(equalTo: rule.topAnchor),
            column.topAnchor.constraint(equalTo: page.topAnchor, constant: 12),
            column.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: s),
            column.widthAnchor.constraint(equalToConstant: Self.pageWidth),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -14),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: s),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -s),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            hint.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Rebuilds the page through `rebuild`. With a direction (1 forward, -1 back) the old page rolls
    /// out that way and the new one rolls in behind it; with 0 the page simply changes.
    func go(direction: Int, rebuild: () -> Void) {
        let motion = direction != 0 && !reduceMotion && window?.isVisible == true
        var shot: NSImageView?
        if motion, let rep = page.bitmapImageRepForCachingDisplay(in: page.bounds) {
            page.cacheDisplay(in: page.bounds, to: rep)
            let image = NSImage(size: page.bounds.size)
            image.addRepresentation(rep)
            let v = NSImageView(frame: page.bounds)
            v.image = image
            v.imageScaling = .scaleNone
            v.wantsLayer = true
            shot = v
        }
        rebuild()
        layoutSubtreeIfNeeded()
        guard motion, let old = shot, let oldLayer = old.layer else { return }
        let d = CGFloat(direction)

        page.addSubview(old)
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperview() }
        let out = CAAnimationGroup()
        out.animations = [Self.slide(from: 0, to: -56 * d), Self.fade(from: 1, to: 0)]
        out.duration = 0.2
        out.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        out.fillMode = .forwards
        out.isRemovedOnCompletion = false
        oldLayer.add(out, forKey: "rollOut")
        CATransaction.commit()

        let now = CACurrentMediaTime()
        for (i, piece) in pieces().enumerated() {
            piece.wantsLayer = true
            let arrive = CAAnimationGroup()
            arrive.animations = [Self.slide(from: 64 * d, to: 0), Self.fade(from: 0, to: 1)]
            arrive.duration = 0.42
            arrive.beginTime = now + 0.07 + Double(min(i, 10)) * 0.038
            arrive.fillMode = .backwards
            arrive.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            piece.layer?.add(arrive, forKey: "rollIn")
        }
    }

    /// The title and what the step put in its body, with the rows of a list taken one by one, so each arrives in turn.
    private func pieces() -> [NSView] {
        var out: [NSView] = [titleLabel]
        for v in body.arrangedSubviews where !v.isHidden {
            if let list = v as? NSStackView, list.identifier == Self.cascade { out += list.arrangedSubviews.flatMap { ($0 as? NSStackView)?.identifier == Self.cascade ? ($0 as! NSStackView).arrangedSubviews : [$0] } }
            else { out.append(v) }
        }
        return out
    }
    /// Marks a stack whose rows should arrive one after another rather than as one piece.
    static let cascade = NSUserInterfaceItemIdentifier("setupCascade")

    private static func slide(from: CGFloat, to: CGFloat) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.translation.x")
        a.fromValue = from; a.toValue = to
        return a
    }
    private static func fade(from: CGFloat, to: CGFloat) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from; a.toValue = to
        return a
    }
}

// ---------- A setup's draft, kept across a relaunch ----------

/// What a setup has chosen so far, so a relaunch (which macOS asks for after Screen Recording is
/// allowed) carries on at the step it left. Kept in the preferences until the setup creates things.
enum SetupDraft {
    static func save<T: Encodable>(_ value: T, key: String, in defaults: UserDefaults = preferences) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
    static func load<T: Decodable>(_ type: T.Type, key: String, in defaults: UserDefaults = preferences) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    static func clear(key: String, in defaults: UserDefaults = preferences) { defaults.removeObject(forKey: key) }
}

enum Relaunch {
    /// Opens a fresh copy of the app and quits this one.
    static func now() {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let c = NSWorkspace.OpenConfiguration()
            c.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: c) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let exe = Bundle.main.executableURL {   // the bare binary Xcode runs
            let p = Process()
            p.executableURL = exe
            p.arguments = Array(CommandLine.arguments.dropFirst())
            try? p.run()
            NSApp.terminate(nil)
        }
    }
}
