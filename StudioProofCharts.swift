import AppKit

/// Deliberately separate from ProofEngine: these are editable illustrative assumptions, never measurements.
final class ProofDensitySimulation {
    var current = 1.61, optimum = 1.67, minimum = 1.30, curvature = 88.89, tolerance = 2.5
    func difference(at density: Double) -> Double { minimum + curvature * pow(density-optimum,2) }
    var radius: Double? { tolerance >= minimum ? sqrt((tolerance-minimum)/curvature) : nil }
    var interval: ClosedRange<Double>? { radius.map { max(0,optimum-$0)...(optimum+$0) } }
}

/// House diagonal arrow, with a full control target, hover, keyboard focus and accessible name.
final class ProofChartArrow: NSButton {
    var contracts = false
    private var hover = false
    private var tracking: NSTrackingArea?
    init(_ title: String, contracts: Bool = false) {
        super.init(frame:.zero); self.contracts=contracts; self.title=title
        isBordered=false; setAccessibilityLabel(title); toolTip=title
    }
    required init?(coder:NSCoder) { fatalError() }
    override func draw(_ dirtyRect:NSRect) {
        if hover { fill(bounds,Design.mist) }
        Design.arrow(16,back:contracts).draw(in:NSRect(x:(bounds.width-16)/2,y:(bounds.height-16)/2,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        if window?.firstResponder === self { Design.ink.setStroke(); NSBezierPath(rect:bounds.insetBy(dx:1,dy:1)).stroke() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hover=true;needsDisplay=true;NSCursor.pointingHand.set() }
    override func mouseExited(with event:NSEvent) { hover=false;needsDisplay=true;NSCursor.arrow.set() }
}
