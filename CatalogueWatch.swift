import Foundation
import CoreServices

// ---------- Watching the catalogue's folders ----------
//
// The disk decides what exists, so a rename, a drop or a deletion made in Finder has to reach the app
// without a relaunch. The watch listens to the catalogue's tree and, a moment after anything in it
// changes, compares the tree's signature with the one taken after the app's own last write. The same
// signature is the app's own doing; a different one is Finder's, and the catalogue is read again.

final class CatalogueWatch {
    let root: URL
    private var stream: FSEventStreamRef?
    private var known: String
    private let onChange: () -> Void
    private var timer: Timer?

    init(root: URL, onChange: @escaping () -> Void) {
        self.root = root
        self.onChange = onChange
        known = CatalogueTree.signature(root: root)
    }

    deinit { stop() }

    /// Takes the tree as it stands as the app's own: whatever it looks like now is not news.
    func settle() { known = CatalogueTree.signature(root: root) }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            Unmanaged<CatalogueWatch>.fromOpaque(info).takeUnretainedValue().noticed()
        }
        guard let made = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.6,
                                             FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)) else { return }
        stream = made
        FSEventStreamSetDispatchQueue(made, .main)
        FSEventStreamStart(made)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        timer?.invalidate()
    }

    /// Something changed under the root. A moment later, once Finder has finished, the tree is compared with what the app last wrote.
    private func noticed() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.compare() }
    }

    private func compare() {
        let now = CatalogueTree.signature(root: root)
        guard now != known else { return }
        known = now
        onChange()
    }
}
