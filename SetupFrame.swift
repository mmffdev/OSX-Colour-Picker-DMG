import AppKit
import QuartzCore

// ---------- The setup frame ----------
//
// The borderless panel every version of the app sets itself up in, to the design guide's wizard
// frame (c_c_c_design_grid_wizard.md): the band in the step's colour across the top, the step line
// under it, the title in columns 1 to 5, the words in 7 to 12, the actions
// on one baseline at the right, and the step cards settling together along the bottom. Moving to
// another step is animated: the page rolls out and the new one rolls in with its pieces arriving
// one after another, quickly. Reduce Motion shows each step with no movement. The steps belong to
// whoever uses the frame (SetupAssistant, for this app).

/// A borderless window that still takes the keyboard.
final class SetupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SetupFrame: NSView {
    typealias W = Design.Wizard

    let cards: StepCards
    let logo = Logo()
    let stepLabel = Design.text("", .label, colour: Design.quiet)
    let skipSetup = SwissButton("Skip Setup", .quiet)
    let hint = Design.text("", .caption, colour: Design.quiet)
    let back = SwissButton("Back", .quiet)
    let skip = SwissButton("Skip", .quiet)
    let primary = SwissButton("Continue", .primary)
    let body = NSStackView()
    /// Words under the title, in its columns: for a step whose right column holds something that is not text.
    let aside = NSStackView()
    private let band = NSView()
    private let page = NSView()
    private let titleView = NSTextField(wrappingLabelWithString: "")
    private let actions = NSStackView()
    private var bodyLeading: NSLayoutConstraint!, bodyWidth: NSLayoutConstraint!, actionsTop: NSLayoutConstraint!, cardsHeight: NSLayoutConstraint!
    /// The words take every column and the title goes, for a step that needs the room (the halo).
    var wide = false { didSet { layoutColumns() } }
    /// The cards shrink to a strip of their colours, for the step that needs the height (the halo).
    var slim = false { didSet { cards.slim = slim; cardsHeight.constant = slim ? StepCards.slimHeight : StepCards.height } }

    init(steps: [String]) {
        cards = StepCards(names: steps)
        super.init(frame: NSRect(origin: .zero, size: W.size))
        wantsLayer = true
        layer?.backgroundColor = Design.paper.cgColor
        layer?.cornerRadius = W.radius
        layer?.masksToBounds = true

        band.wantsLayer = true
        band.layer?.backgroundColor = Design.active.cgColor
        skipSetup.leadingArrow = true
        primary.fixedWidth = PermissionRow.buttonWidth
        titleView.maximumNumberOfLines = 3
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = Design.beat(6)
        actions.orientation = .horizontal
        actions.alignment = .lastBaseline
        actions.spacing = Design.beat(6)
        actions.setViews([hint, back, skip, primary], in: .leading)
        actions.setCustomSpacing(Design.beat(8), after: hint)
        page.wantsLayer = true
        page.layer?.masksToBounds = true
        aside.orientation = .vertical
        aside.alignment = .leading
        aside.spacing = Design.beat(6)

        for v in [band, stepLabel, skipSetup, page, cards, titleView, body, actions, aside] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        translatesAutoresizingMaskIntoConstraints = false
        cardsHeight = cards.heightAnchor.constraint(equalToConstant: StepCards.height)
        addSubview(band); addSubview(logo); addSubview(stepLabel); addSubview(skipSetup); addSubview(page); addSubview(cards)
        page.addSubview(titleView); page.addSubview(body); page.addSubview(actions); page.addSubview(aside)
        bodyLeading = body.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: W.column(7))
        bodyWidth = body.widthAnchor.constraint(equalToConstant: W.span(7, 12))
        // The actions sit on a row of their own, a fixed distance above the cards, the same on every step.
        actionsTop = actions.bottomAnchor.constraint(equalTo: page.bottomAnchor)   // the page ends one gutter above the cards
        NSLayoutConstraint.activate([
            band.topAnchor.constraint(equalTo: topAnchor), band.leadingAnchor.constraint(equalTo: leadingAnchor),
            band.trailingAnchor.constraint(equalTo: trailingAnchor), band.heightAnchor.constraint(equalToConstant: W.band),
            // The top line: the mark at column 1, the step label one gutter after it, Skip Setup at the right, one baseline.
            logo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: W.margin),
            logo.lastBaselineAnchor.constraint(equalTo: topAnchor, constant: 44),
            stepLabel.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: W.gutter),
            stepLabel.lastBaselineAnchor.constraint(equalTo: logo.lastBaselineAnchor),
            skipSetup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -W.margin),
            skipSetup.lastBaselineAnchor.constraint(equalTo: stepLabel.lastBaselineAnchor),
            page.topAnchor.constraint(equalTo: topAnchor, constant: 96),
            page.leadingAnchor.constraint(equalTo: leadingAnchor), page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.bottomAnchor.constraint(equalTo: cards.topAnchor, constant: -Design.beat(6)),
            cards.leadingAnchor.constraint(equalTo: leadingAnchor, constant: W.margin),
            cards.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -W.margin),
            cards.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
            cardsHeight,
            widthAnchor.constraint(equalToConstant: W.size.width), heightAnchor.constraint(equalToConstant: W.size.height),
            titleView.topAnchor.constraint(equalTo: page.topAnchor),
            titleView.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: W.column(1)),
            titleView.widthAnchor.constraint(equalToConstant: W.span(1, 5)),
            aside.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: Design.beat(8)),
            aside.leadingAnchor.constraint(equalTo: titleView.leadingAnchor),
            aside.widthAnchor.constraint(equalToConstant: W.span(1, 5)),
            body.topAnchor.constraint(equalTo: page.topAnchor, constant: Self.capAlignment),
            bodyLeading, bodyWidth,
            actionsTop,
            actions.topAnchor.constraint(greaterThanOrEqualTo: body.bottomAnchor, constant: Design.beat(6)),
            actions.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -W.margin),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// How far below the title's top the words start, so the capitals of their first line sit level
    /// with the capitals of the title: the two line boxes hold their letters at different heights.
    static var capAlignment: CGFloat {
        func capTop(_ style: Design.Text, _ size: CGFloat) -> CGFloat {
            let f = style.font(size), line = (size * style.lineHeight).rounded()
            return (line - (f.ascender - f.descender)) / 2 + (f.ascender - f.capHeight)
        }
        return (capTop(.title, 44) - capTop(.lead, 20)).rounded()
    }

    private func layoutColumns() {
        titleView.isHidden = wide
        bodyLeading.constant = wide ? W.column(1) : W.column(7)
        bodyWidth.constant = wide ? W.span(1, 12) : W.span(7, 12)
    }

    /// The two-tone title: the first line in ink, the second in soft grey.
    func title(_ first: String, _ second: String?) {
        let s = NSMutableAttributedString()
        let size: CGFloat = 44
        s.append(Design.attributed(first, .title, size: size, lineHeight: true))
        if let second = second, !second.isEmpty {
            s.append(Design.attributed("\n" + second, .title, size: size, colour: Design.soft, lineHeight: true))
        }
        titleView.attributedStringValue = s
    }

    func setStep(_ i: Int, of n: Int, animated: Bool) {
        stepLabel.attributedStringValue = Design.attributed(String(format: "Step %02d of %02d", i + 1, n), .label, colour: Design.quiet)
        let colour = Design.active
        if animated && !reduceMotion && window?.isVisible == true {
            // The new colour slides in the direction of travel and pushes the old one off.
            let dir: CGFloat = i >= cards.step ? 1 : -1
            let old = NSView(frame: band.bounds); old.wantsLayer = true; old.layer?.backgroundColor = band.layer?.backgroundColor
            old.autoresizingMask = [.width, .height]
            band.addSubview(old)
            band.layer?.backgroundColor = colour.cgColor
            let w = band.bounds.width
            band.layer?.sublayerTransform = CATransform3DIdentity
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = 0; slide.toValue = w * dir; slide.duration = 0.55
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.2, 1)
            slide.fillMode = .forwards; slide.isRemovedOnCompletion = false
            CATransaction.begin(); CATransaction.setCompletionBlock { old.removeFromSuperview() }
            old.layer?.add(slide, forKey: "off")
            let arrive = CABasicAnimation(keyPath: "transform.translation.x")
            arrive.fromValue = -w * dir; arrive.toValue = 0; arrive.duration = 0.55
            arrive.timingFunction = slide.timingFunction
            band.layer?.add(arrive, forKey: "in")
            CATransaction.commit()
        } else {
            band.layer?.backgroundColor = colour.cgColor
        }
        cards.set(step: i, animated: animated)
    }

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

    /// The title, what the step put in its body (a cascade's rows one by one), then the actions.
    private func pieces() -> [NSView] {
        var out: [NSView] = wide ? [] : [titleView] + aside.arrangedSubviews
        for v in body.arrangedSubviews where !v.isHidden {
            if let list = v as? NSStackView, list.identifier == Self.cascade { out += list.arrangedSubviews }
            else { out.append(v) }
        }
        out.append(actions)
        return out
    }
    /// Marks a stack whose rows should arrive one after another rather than as one piece.
    static let cascade = NSUserInterfaceItemIdentifier("setupCascade")

    private static func slide(from: CGFloat, to: CGFloat) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.translation.x"); a.fromValue = from; a.toValue = to; return a
    }
    private static func fade(from: CGFloat, to: CGFloat) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = from; a.toValue = to; return a
    }

    // MARK: Pieces a step is built from, to the design

    /// A paragraph in the Lead style, the first words of a step.
    static func lead(_ s: String, width: CGFloat) -> NSTextField {
        let l = Design.text(s, .lead, wraps: true)
        l.preferredMaxLayoutWidth = width
        return l
    }
    /// A paragraph in the Body style.
    static func body(_ s: String, width: CGFloat) -> NSTextField {
        let l = Design.text(s, .body, wraps: true)
        l.preferredMaxLayoutWidth = width
        return l
    }
    /// A field as the design draws one: a hairline above, a caption label, then the value at 17 with
    /// its quiet action on the same baseline.
    static func field(_ caption: String, _ value: String, action: String?, target: AnyObject?, selector: Selector?, width: CGFloat, rule: Bool = true, oneLine: Bool = false) -> (row: NSView, value: NSTextField) {
        let cap = Design.text(caption, .caption, colour: Design.quiet)
        let val = Design.text(value, .headline, size: 17, wraps: true)
        val.preferredMaxLayoutWidth = width - 90
        if oneLine { val.maximumNumberOfLines = 1; val.lineBreakMode = .byTruncatingMiddle; val.cell?.truncatesLastVisibleLine = true }
        let line = NSStackView(views: [val])
        line.orientation = .horizontal
        line.alignment = .lastBaseline
        if let a = action { line.addArrangedSubview(NSView()); line.addArrangedSubview(SwissButton(a, .quiet, target: target, action: selector)) }
        let col = NSStackView(views: (rule ? [Design.hairline()] : []) + [cap, line])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        col.widthAnchor.constraint(equalToConstant: width).isActive = true
        if rule { col.setCustomSpacing(Design.beat(4), after: col.arrangedSubviews[0]); col.arrangedSubviews[0].widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true }
        line.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        return (col, val)
    }
    /// A text field as the design draws one: a caption label, the text at 17, a hairline under.
    static func entry(_ caption: String, _ value: String, placeholder: String, width: CGFloat, target: AnyObject?, action: Selector?) -> (row: NSView, field: NSTextField) {
        let cap = Design.text(caption, .caption, colour: Design.quiet)
        let f = NSTextField(string: value)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Design.font(17, .regular)
        f.textColor = Design.ink
        f.placeholderAttributedString = Design.attributed(placeholder, .headline, size: 17, colour: Design.soft)
        f.target = target
        f.action = action
        let col = NSStackView(views: [cap, f, Design.hairline(Design.ink)])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        col.translatesAutoresizingMaskIntoConstraints = false
        col.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        col.arrangedSubviews[2].widthAnchor.constraint(equalTo: col.widthAnchor).isActive = true
        return (col, f)
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
    /// A permission restart resumes the test's draft instead of resetting its throwaway home.
    static func arguments(for arguments: [String]) -> [String] {
        if arguments.contains("--new-user"), !arguments.contains("--resume-new-user") {
            return arguments + ["--resume-new-user"]
        }
        return arguments
    }

    /// Whether a debugger (Xcode) is attached: a relaunch would end its session, which reads as the app dying.
    static var debugged: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }

    /// Opens a fresh copy of the app and quits this one.
    static func now() {
        if debugged {
            if CommandLine.arguments.contains("--new-user") {
                preferences.set(true, forKey: "resumeNewUserAfterDebuggerRestart")
            }
            let a = NSAlert()
            a.messageText = "Run it again from Xcode"
            a.informativeText = "macOS applies what you just allowed to a fresh copy of the app. Outside Xcode the app reopens itself; under the debugger that would end the session, so stop and press Run again."
            a.runModal()
            return
        }
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let c = NSWorkspace.OpenConfiguration()
            c.createsNewApplicationInstance = true
            // The flags this copy was opened with go with it, so a restart comes back the same way.
            c.arguments = arguments(for: Array(CommandLine.arguments.dropFirst()))
            NSWorkspace.shared.openApplication(at: bundle, configuration: c) { _, error in
                DispatchQueue.main.async {
                    // A relaunch that did not start leaves this copy running and says so, rather than quitting into nothing.
                    if let error = error {
                        Diagnostics.log("relaunch", error: error)
                        let a = NSAlert(); a.messageText = "Colorgain could not reopen itself"; a.informativeText = error.localizedDescription + " Quit and open it again from Applications."
                        a.runModal()
                        return
                    }
                    NSApp.terminate(nil)
                }
            }
        } else if let exe = Bundle.main.executableURL {   // the bare binary Xcode runs
            let p = Process()
            p.executableURL = exe
            p.arguments = arguments(for: Array(CommandLine.arguments.dropFirst()))
            do {
                try p.run()
                NSApp.terminate(nil)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
