import AppKit

// ---------- A project whose file is gone ----------
//
// The library still holds the project, so nothing is lost but the file. The page says what happened
// and where the file was expected, and offers the ways out: find it, write it again, or let the
// project go. Nothing is remade on the app's own initiative.

final class LostProjectController: NSViewController {
    private let library: LibraryController
    private let project: Project
    private let loss: ProjectFiles.Loss

    init(library: LibraryController, project: Project, loss: ProjectFiles.Loss) {
        self.library = library
        self.project = project
        self.loss = loss
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        let find = NSButton(title: "Find The File\u{2026}", target: self, action: #selector(findTapped))
        find.keyEquivalent = "\r"
        let again = NSButton(title: "Write It Again", target: self, action: #selector(againTapped))
        let delete = NSButton(title: "Delete Project\u{2026}", target: self, action: #selector(deleteTapped))
        let close = NSButton(title: "Not Now", target: self, action: #selector(closeTapped))
        close.keyEquivalent = "\u{1b}"
        for b in [find, again, delete, close] { b.bezelStyle = .rounded; b.controlSize = .large }
        let header = PageHeader(actions: [close])
        header.title.stringValue = project.name
        header.subtitle.stringValue = "Project file missing"

        let what: String, where_: String
        switch loss {
        case .missing(let expected):
            what = "The file that holds this project on disk has gone. It was written before, so it has not been made again: it may have been moved, renamed or deleted on purpose."
            where_ = "It was expected at:\n\((expected.path as NSString).abbreviatingWithTildeInPath)"
        case .unavailable(let folder):
            what = "The folder this project is kept under is not there. If it is on a drive or a cloud folder that is not connected, connect it and the project will be found again."
            where_ = "The folder:\n\((folder.path as NSString).abbreviatingWithTildeInPath)"
        }
        let story = NSTextField(wrappingLabelWithString: what)
        story.font = NSFont.systemFont(ofSize: TextSize.body)
        let place = NSTextField(wrappingLabelWithString: where_)
        place.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        place.textColor = .secondaryLabelColor
        let keep = NSTextField(wrappingLabelWithString: "Your palettes, swatches, typography and tags are still in the library. Only the file is missing.")
        keep.font = NSFont.systemFont(ofSize: TextSize.body)
        keep.textColor = .secondaryLabelColor
        let options = NSTextField(wrappingLabelWithString: "Find The File points the app at the file where it is now; a file on its own is given its folder structure. Write It Again makes a fresh file from the library. Delete Project removes the project from the library as well.")
        options.font = NSFont.systemFont(ofSize: TextSize.body)
        options.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [find, again, delete])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let column = NSStackView(views: [story, place, keep, options, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        for v in [story, place, keep, options] { v.preferredMaxLayoutWidth = 560 }
        for v in [header, column] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
            column.topAnchor.constraint(equalTo: header.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: PageStyle.side),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
        ])
        view = root
    }

    @objc private func findTapped() { library.relocateProject(project.id) }
    @objc private func againTapped() { library.rewriteProjectFile(project.id) }
    @objc private func deleteTapped() { library.delete(project: project.id) }
    @objc private func closeTapped() { library.onCover?(nil, false) }
}
