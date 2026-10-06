import AppKit

// ---------- A project whose file is gone ----------
//
// A project's files are the only home of what is in it. When they cannot be reached the catalogue
// still lists the project, by name, and this page says what happened, where the files were
// expected, and the ways out: find them, or let the project go. Nothing is remade or written over
// on the app's own initiative, so the project is whole again as soon as its files are found.

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
        let delete = NSButton(title: "Delete Project\u{2026}", target: self, action: #selector(deleteTapped))
        let close = NSButton(title: "Not Now", target: self, action: #selector(closeTapped))
        close.keyEquivalent = "\u{1b}"
        for b in [find, delete, close] { b.bezelStyle = .rounded; b.controlSize = .large }
        let header = PageHeader(actions: [close])
        header.title.stringValue = project.name
        header.subtitle.stringValue = "Project Files Not Found"

        let what: String, where_: String
        switch loss {
        case .missing(let expected):
            what = "The files that hold this project cannot be found. They may have been moved or renamed. The project is still listed in the catalogue, and nothing has been written in its place."
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
        let keep = NSTextField(wrappingLabelWithString: "A project\u{2019}s palettes, swatches, typography and tags are kept in its own files, so they are out of reach until the files are found. Nothing has been deleted.")
        keep.font = NSFont.systemFont(ofSize: TextSize.body)
        keep.textColor = .secondaryLabelColor
        let options = NSTextField(wrappingLabelWithString: "Find The File points the app at the project where it is now: its .colspace file, or the folder holding it. Delete Project takes the project out of the catalogue; its files, wherever they are, are left alone.")
        options.font = NSFont.systemFont(ofSize: TextSize.body)
        options.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [find, delete])
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
    @objc private func deleteTapped() { library.delete(project: project.id) }
    @objc private func closeTapped() { library.onCover?(nil, false) }
}
