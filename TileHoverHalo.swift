import AppKit

/// Scrolling moves content under a stationary pointer; only a real pointer move may reopen a halo.
struct HoverScrollGate {
    private var pointer:NSPoint?
    mutating func suppress(at point:NSPoint){pointer=point}
    mutating func allows(at point:NSPoint)->Bool {
        guard let pointer else{return true}
        guard abs(point.x-pointer.x)>0.5 || abs(point.y-pointer.y)>0.5 else{return false}
        self.pointer=nil;return true
    }
}

/// Fixed, direct actions: the familiar halo ground without rotary selection.
final class TileHoverHalo: NSView {
    struct Action { var title: String; var symbol: String; var run: () -> Void }
    var onDismiss: (() -> Void)?
    var onScroll: ((NSEvent)->Void)?
    private var buttons: [HoverHaloButton] = []
    private var label = "Actions"
    private var colours: [NSColor] = []
    private var progress: CGFloat = 0
    private var destination: CGFloat = 1
    private var timer: Timer?
    private var monitor: Any?
    override var isFlipped: Bool { true }
    init(colours: [NSColor], actions: [Action], palette: (() -> Void)?) {
        self.colours = colours; super.init(frame:.zero); alphaValue=0
        for a in actions {
            let b = HoverHaloButton(a.symbol, label:a.title) { [weak self] in self?.dismiss(); a.run() }
            b.onHover = { [weak self] on in self?.label = on ? a.title : "Actions"; self?.needsDisplay = true }
            buttons.append(b); addSubview(b)
        }
        if let palette {
            let b = HoverHaloButton("square.grid.2x2",label:"Open Swatches") { [weak self] in self?.dismiss(); palette() }
            b.onHover = { [weak self] on in self?.label = on ? "Swatches" : "Actions"; self?.needsDisplay = true }
            buttons.append(b); addSubview(b)
        }
        setAccessibilityLabel("Colour Actions")
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { timer?.invalidate(); if let monitor { NSEvent.removeMonitor(monitor) } }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        if monitor == nil { monitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.scrollWheel]) { [weak self] event in
            guard let self, self.destination > 0 else { return event }
            if event.type == .scrollWheel, event.window === self.window, self.bounds.contains(self.convert(event.locationInWindow,from:nil)) { self.scrollWheel(with:event); return nil }
            if event.type == .keyDown && event.keyCode == 53 { self.dismiss(); return nil }
            if event.type == .leftMouseDown && !self.bounds.contains(self.convert(event.locationInWindow,from:nil)) { self.dismiss() }
            return event
        } }
        animate()
    }
    func dismiss() { guard destination != 0 else { return }; destination = 0; animate() }
    func dismissForScrolling() {
        timer?.invalidate();timer=nil;destination=0;progress=0;finish()
    }
    override func scrollWheel(with event:NSEvent) {
        if let onScroll {onScroll(event)} else {dismissForScrolling();super.scrollWheel(with:event)}
    }
    private func animate() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { progress = destination; finish(); return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval:1/60,repeats:true) { [weak self] _ in
            guard let self else { return }; self.progress += (self.destination-self.progress)*0.3
            if abs(self.progress-self.destination)<0.01 { self.progress=self.destination; self.timer?.invalidate(); self.timer=nil; self.finish() }
            self.alphaValue=self.progress; self.needsDisplay=true
        }
    }
    private func finish() { alphaValue=progress; needsDisplay=true; if destination == 0 { if let monitor { NSEvent.removeMonitor(monitor); self.monitor=nil }; removeFromSuperview(); onDismiss?() } }
    override func layout() {
        super.layout(); let radius = min(bounds.width,bounds.height)/2 - 20
        for (i,b) in buttons.enumerated() {
            if i == 4 { b.frame=NSRect(x:bounds.midX-14,y:bounds.midY+16,width:28,height:28) }
            else { let a = CGFloat(i)*CGFloat.pi/2 - .pi/2; b.frame=NSRect(x:bounds.midX+cos(a)*radius-16,y:bounds.midY+sin(a)*radius-16,width:32,height:32) }
        }
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill(); bounds.fill()
        let diameter = min(bounds.width,bounds.height)-6, size = diameter*(0.86+0.14*progress)
        let circle=NSRect(x:bounds.midX-size/2,y:bounds.midY-size/2,width:size,height:size)
        HaloPalette.theme.ring(0).band.setFill(); NSBezierPath(ovalIn:circle).fill()
        let centre = circle.insetBy(dx:34,dy:34); HaloPalette.theme.centre.setFill(); NSBezierPath(ovalIn:centre).fill()
        let strip=NSRect(x:centre.minX+12,y:bounds.midY-23,width:max(10,centre.width-24),height:14)
        if !colours.isEmpty { for (i,c) in colours.enumerated() { c.setFill(); NSRect(x:strip.minX+CGFloat(i)*strip.width/CGFloat(colours.count),y:strip.minY,width:strip.width/CGFloat(colours.count)+0.5,height:strip.height).fill() } }
        let text=Design.attributed(label,.caption,colour:HaloPalette.theme.centreInk)
        text.draw(x:max(centre.minX+4,bounds.midX-text.size().width/2),baseline:bounds.midY+10,width:max(1,centre.width-8))
    }
    override func mouseDown(with event:NSEvent) { dismiss() }
}
private final class HoverHaloButton:NSButton {
    let symbol:String; let run:()->Void
    var onHover:((Bool)->Void)?
    private var hovering=false
    init(_ symbol:String,label:String,run:@escaping()->Void) { self.symbol=symbol;self.run=run;super.init(frame:.zero);title=label;isBordered=false;target=self;action=#selector(pressed);toolTip=label;setAccessibilityLabel(label) }
    required init?(coder:NSCoder){fatalError()}
    @objc private func pressed(){run()}
    override func scrollWheel(with event:NSEvent){superview?.scrollWheel(with:event)}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){ if hovering || isHighlighted { HaloPalette.theme.ring(0).cursor.setFill();NSBezierPath(ovalIn:bounds).fill() };let image=RowMark.image(symbol,colour:hovering || isHighlighted ? HaloPalette.theme.ring(0).cursorInk : HaloPalette.theme.ring(0).bandInk);image.draw(in:bounds.insetBy(dx:7,dy:7),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){hovering=true;needsDisplay=true;onHover?(true)}
    override func mouseExited(with event:NSEvent){hovering=false;needsDisplay=true;onHover?(false)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
}
