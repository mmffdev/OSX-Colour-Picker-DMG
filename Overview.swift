import AppKit

// ---------- A project's Overview page ----------
//
// Every project has an Information bucket at the top of its tree, and in it one page to begin
// with: Overview. It is part of the scaffold a project is made with, so it is there for every
// project, old or new, without anything being stored. For now the page is its header only: the
// title on the project's stripes, and the action bar naming the project. What it holds comes next.

final class OverviewViewController: NSViewController {
    private let library: LibraryController
    private let header = PageHeader()
    private(set) var projectID: UUID?

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
        ])
    }

    func show(_ id: UUID) {
        projectID = id
        reload()
    }

    func reload() {
        _ = view
        guard let id = projectID, let project = library.library.project(id) else { return }
        header.title.stringValue = "Overview"
        header.subtitle.stringValue = "Information"
        // A page of a project wears the project's marks: its name as a pill, stripes behind the title, its padlock.
        header.setProject(project.name) { [weak self] in self?.library.onRevealProject?(id) }
        header.striped = true
        header.lock = project.isLocked
    }
}
