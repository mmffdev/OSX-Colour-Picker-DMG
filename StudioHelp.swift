import AppKit

/// Bundled Markdown articles are the source of truth for the in-app help library.
/// The initial article stays native and uses the same readable type as the app.
final class StudioHelpPage: NSView, PageSection {
    var onResize: (() -> Void)?
    private var blocks: [(text: String, heading: Bool)] = []
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); reload() }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    func reload() {
        let url = Bundle.main.url(forResource: "getting-started", withExtension: "md", subdirectory: "HelpResources")
            ?? Bundle.main.url(forResource: "getting-started", withExtension: "md")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "# Help\n\nHelp articles could not be loaded."
        blocks = text.components(separatedBy: "\n\n").compactMap { paragraph in
            let clean = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            let heading = clean.hasPrefix("#")
            return (heading ? String(clean.drop(while: { $0 == "#" || $0 == " " })) : clean, heading)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text.replacingOccurrences(of: "#", with: ""))
        needsDisplay = true
        onResize?()
    }
    private func render(width: CGFloat, draw: Bool) -> CGFloat {
        let readableWidth = min(680, max(1, width))
        var y: CGFloat = Design.App.textBaseline
        for block in blocks {
            let text = Design.attributed(block.text, block.heading ? .heading : .body)
            let height = ceil(text.boundingRect(with: NSSize(width: readableWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            if draw {
                text.draw(with: NSRect(x: 0, y: y - text.baselineFont.ascender, width: readableWidth, height: height + 2),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            y += max(Design.App.unit, ceil(height / Design.App.unit) * Design.App.unit) + Design.App.unit
        }
        return y + Design.App.unit
    }
    func height(forWidth width: CGFloat) -> CGFloat { render(width: width, draw: false) }
    override func draw(_ dirtyRect: NSRect) { _ = render(width: bounds.width, draw: true) }
}
