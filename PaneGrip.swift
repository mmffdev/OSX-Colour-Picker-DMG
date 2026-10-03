import AppKit

// ---------- The notch on a side pane's edge ----------
//
// A small curved tab on the inner edge of the sidebar and of each rail, sitting inside the pane and
// never over the page. Drag it to change the pane's width; double-click to put the width back to
// where it started. It wears the theme's button colours: at rest, under the pointer, and held.

final class PaneGrip: NSView {
    /// Which edge of its pane the notch sits on: the sidebar's is its right, a rail's is its left.
    enum Edge { case trailing, leading }
    /// As tall as the title panel.
    static var size: NSSize { NSSize(width: 16, height: PageStyle.titlePanelHeight) }

    private let edge: Edge
    /// Asked for the pane's width now, at the start of a drag.
    var width: () -> CGFloat = { 0 }
    /// Told the width the drag asks for.
    var onResize: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    private var hovering = false
    private var held = false
    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0
    private var tracking: NSTrackingArea?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: NSRect(origin: .zero, size: PaneGrip.size))
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "Drag To Resize; Double-Click To Reset The Width"
        watchTheme(self)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Puts the notch on the pane's inner edge, at the bottom, resting on the footer.
    func attach(to pane: NSView) {
        pane.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PaneGrip.size.width),
            heightAnchor.constraint(equalToConstant: PaneGrip.size.height),
            bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            edge == .trailing ? trailingAnchor.constraint(equalTo: pane.trailingAnchor) : leadingAnchor.constraint(equalTo: pane.leadingAnchor),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds, curve: CGFloat = 20
        // The flat side lies on the pane's edge; the notch swells into the pane in one smooth curve.
        let flat = edge == .trailing ? b.maxX : b.minX, deep = edge == .trailing ? b.minX : b.maxX
        let path = NSBezierPath()
        path.move(to: NSPoint(x: flat, y: b.minY))
        path.curve(to: NSPoint(x: deep, y: b.minY + curve), controlPoint1: NSPoint(x: flat, y: b.minY + curve / 2), controlPoint2: NSPoint(x: deep, y: b.minY + curve / 2))
        path.line(to: NSPoint(x: deep, y: b.maxY - curve))
        path.curve(to: NSPoint(x: flat, y: b.maxY), controlPoint1: NSPoint(x: deep, y: b.maxY - curve / 2), controlPoint2: NSPoint(x: flat, y: b.maxY - curve / 2))
        path.close()
        // The whole notch changes: the button's resting grey, its hover colour under the pointer, its active colour while held.
        (held ? Theme.buttonActiveBackground : hovering ? Theme.buttonHoverBackground : Theme.buttonRest).setFill()
        path.fill()
        // Three dots down the middle, to say it can be held.
        let ink = held ? Theme.buttonActiveText : hovering ? Theme.buttonHoverText : Theme.text
        ink.withAlphaComponent(held || hovering ? 0.9 : 0.4).setFill()
        let dot: CGFloat = 3, gap: CGFloat = 4
        let x = b.midX - dot / 2 + (edge == .trailing ? 2 : -2)
        for i in -1...1 {
            NSBezierPath(ovalIn: NSRect(x: x, y: b.midY - dot / 2 + CGFloat(i) * (dot + gap), width: dot, height: dot)).fill()
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?(); return }
        held = true
        startX = event.locationInWindow.x
        startWidth = width()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard held else { return }
        let moved = event.locationInWindow.x - startX
        onResize?(startWidth + (edge == .trailing ? moved : -moved))
    }

    override func mouseUp(with event: NSEvent) {
        held = false
        needsDisplay = true
    }
}
