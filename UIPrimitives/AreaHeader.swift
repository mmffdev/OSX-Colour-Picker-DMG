import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

enum AreaHeader {
    static let headingBaseline: CGFloat = StudioRail.top + 14
    static let labelBaseline: CGFloat = headingBaseline + 33
    static let rule: CGFloat = StudioRail.top + 14 + 16 + 27
    /// Where an area's own content starts: a unit of air under the Rule, in every rail and on every page (Rick, 2026-10-09).
    static var height: CGFloat { rule + 1 + Design.App.unit }
    /// The arrow at the right: none; "open", the stroke up and right, pressed to open or widen; "close", turned 180, pressed to close.
    enum Arrow { case none, open, close }
    static func arrowRect(in bounds: NSRect, insetRight: CGFloat) -> NSRect { NSRect(x: bounds.width - insetRight - 16, y: headingBaseline - 13, width: 16, height: 16) }
    static func draw(heading: String, left: String, right: String, in bounds: NSRect, inset: CGFloat, insetRight: CGFloat? = nil, arrow: Arrow = .open, headingRight:String = "",headingTrailingInset:CGFloat=0,centreTabRowLabels:Bool=false) {
        let r = bounds.width - (insetRight ?? inset)
        let companion=Design.attributed(headingRight,.body)
        let companionWidth=headingRight.isEmpty ? 0:companion.size().width+24
        Design.attributed(heading, .heading).draw(x: inset, baseline: headingBaseline, width: max(0,r - inset - 24-companionWidth-headingTrailingInset))
        if !headingRight.isEmpty {companion.draw(x:r-companion.size().width,baseline:headingBaseline,width:companion.size().width)}
        if arrow != .none { Design.arrow(16, back: arrow == .close).draw(in: arrowRect(in: bounds, insetRight: insetRight ?? inset), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
        // Each Label keeps to its half, cut short rather than running into the other: the words are written to fit, never the box.
        let half = ((r - inset) / 2 - 8).rounded(.down)
        let baseline:CGFloat
        if centreTabRowLabels {
            let font=Design.Text.label.font()
            baseline=(WorkspaceTabContour.height-WorkspaceTabContour.topOverlap+rule)/2+(font.ascender+font.descender)/2
        } else {baseline=labelBaseline}
        Design.attributed(left, .label, colour: Design.quiet).draw(x: inset, baseline: baseline, width: half)
        let rightText = Design.attributed(right, .label, colour: Design.quiet)
        rightText.draw(x: r - min(rightText.size().width, half), baseline: baseline, width: half)
        hairline(x: inset, y: rule, width: r - inset, Design.rule)
    }
}
