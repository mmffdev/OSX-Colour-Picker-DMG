import AppKit

final class DeltaWarningButton:NSButton {
    var enabledWarnings=false {didSet{title=enabledWarnings ? "Delta On":"Delta Off";setAccessibilityLabel("Delta Warnings: "+(enabledWarnings ? "On":"Off"));needsDisplay=true}}
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;toolTip="Delta Warnings · Show master colours above their printed predictions";title="Delta Off"}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){let hover=window.map{bounds.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil))} ?? false;if hover || isHighlighted{Design.mist.setFill();bounds.fill()};RowMark.draw("exclamationmark.triangle",x:0,baseline:17,colour:Design.ink);Design.attributed(title,.body).draw(x:20,baseline:17,width:bounds.width-20)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){needsDisplay=true}
    override func mouseExited(with event:NSEvent){needsDisplay=true}
}
