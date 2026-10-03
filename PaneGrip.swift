import AppKit

// ---------- The notch on a side pane's edge ----------
//
// A small curved tab on the inner edge of the sidebar and of each rail, sitting inside the pane and
// never over the page. Drag it to change the pane's width; double-click to put the width back to
// where it started. It wears the theme's button colours: at rest, under the pointer, and held.

final class PaneGrip: NSView {
    /// Which edge of its pane the notch sits on: the sidebar's is its right, a rail's is its left.
    enum Edge { case trailing, leading }
    /// As tall as the title panel, so beside a striped title it runs the stripes' full height.
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

    /// Puts the notch on the pane's inner edge, at the top, level with the title panel.
    func attach(to pane: NSView) {
        pane.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PaneGrip.size.width),
            heightAnchor.constraint(equalToConstant: PaneGrip.size.height),
            topAnchor.constraint(equalTo: pane.safeAreaLayoutGuide.topAnchor),
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
        (held ? Theme.buttonActiveBackground : hovering ? Theme.buttonHoverBackground : Theme.grey(0.14)).setFill()
        path.fill()
        // One short line down the middle, to say it can be held.
        let ink = held ? Theme.buttonActiveText : hovering ? Theme.buttonHoverText : Theme.text
        ink.withAlphaComponent(held || hovering ? 0.8 : 0.35).setFill()
        NSBezierPath(roundedRect: NSRect(x: b.midX - 1 + (edge == .trailing ? 2 : -2), y: b.midY - 8, width: 2, height: 16), xRadius: 1, yRadius: 1).fill()
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
