import AppKit
import StoreKit

// ---------- Standard and Pro, bought through Apple ----------
//
// The Store build sells two editions as in-app purchases, both non-consumable: Standard, and Pro which
// includes it. What this Mac is entitled to is read from the App Store at launch and whenever a purchase
// lands, and the rest of the app asks one question, `Store.allows(.pro)`, before showing a Pro feature.
// Which features those are is not decided here. The direct download has everything.

enum Edition: Int, Comparable {
    case none, standard, pro
    static func < (a: Edition, b: Edition) -> Bool { a.rawValue < b.rawValue }

    var name: String {
        switch self {
        case .none: return "No edition yet"
        case .standard: return "Standard"
        case .pro: return "Pro"
        }
    }
}

extension Notification.Name {
    static let editionDidChange = Notification.Name("editionDidChange")
}

enum Store {
    static let standardID = "com.mmffdev.mmffdevcolour3.standard"
    static let proID = "com.mmffdev.mmffdevcolour3.pro"
    static let ids = [standardID, proID]

    /// What this Mac may use. The direct download is Pro throughout.
    private(set) static var edition: Edition = {
        #if APPSTORE
        return .none
        #else
        return .pro
        #endif
    }()

    /// The one question asked before a feature of an edition is shown.
    static func allows(_ needs: Edition) -> Bool { edition >= needs }

    static func edition(of productID: String) -> Edition {
        switch productID {
        case proID: return .pro
        case standardID: return .standard
        default: return .none
        }
    }

    #if APPSTORE
    /// The products the Store has on offer, once loaded.
    private(set) static var products: [Product] = []
    /// What the last load or purchase said, for the Settings panel.
    private(set) static var status = "Checking with the App Store\u{2026}"

    /// At launch: reads the entitlements and then keeps listening for purchases made anywhere.
    static func start() {
        Task {
            await refresh()
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await refresh()
            }
        }
    }

    @MainActor
    static func refresh() async {
        do {
            products = try await Product.products(for: ids).sorted { edition(of: $0.id) < edition(of: $1.id) }
            status = products.isEmpty ? "The App Store lists no editions yet." : ""
        } catch {
            products = []
            status = "The App Store could not be reached: \(error.localizedDescription)"
        }
        var have = Edition.none
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { have = max(have, edition(of: t.productID)) }
        }
        edition = have
        NotificationCenter.default.post(name: .editionDidChange, object: nil)
    }

    @MainActor
    static func buy(_ product: Product) async throws {
        switch try await product.purchase() {
        case .success(let verification):
            if case .verified(let t) = verification { await t.finish() }
        case .userCancelled, .pending: break
        @unknown default: break
        }
        await refresh()
    }

    @MainActor
    static func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
    #endif
}

#if APPSTORE
// MARK: Settings ▸ Edition

final class EditionPanel: SettingsPanel {
    private let current = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var buys: [NSButton] = []

    override func rows() -> [[NSView]] {
        current.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        message.font = NSFont.systemFont(ofSize: TextSize.body)
        message.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 400
        let heading = NSTextField(labelWithString: "Edition")
        heading.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let restore = button("Restore Purchases", #selector(restoreTapped))
        buys = Store.products.enumerated().map { i, p in
            let b = button("\(p.displayName) \u{2014} \(p.displayPrice)", #selector(buyTapped(_:)))
            b.tag = i
            return b
        }
        let actions = NSStackView(views: buys + [restore])
        actions.orientation = .horizontal
        actions.spacing = 8
        let explain = NSTextField(wrappingLabelWithString: "Standard and Pro are bought once, through the App Store, and shared by every Mac signed in with the same Apple Account. Pro includes everything in Standard.")
        explain.font = NSFont.systemFont(ofSize: TextSize.body)
        explain.textColor = .secondaryLabelColor
        explain.preferredMaxLayoutWidth = 400
        NotificationCenter.default.addObserver(self, selector: #selector(editionChanged), name: .editionDidChange, object: nil)
        refresh()
        return [
            [heading, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, current],
            [NSGridCell.emptyContentView, actions],
            [NSGridCell.emptyContentView, message],
            [NSGridCell.emptyContentView, explain],
        ]
    }

    override func refresh() {
        current.stringValue = Store.edition.name
        message.stringValue = Store.status
        for (i, b) in buys.enumerated() where i < Store.products.count {
            b.isEnabled = Store.edition < Store.edition(of: Store.products[i].id)
        }
    }

    @objc private func editionChanged() { refresh() }

    @objc private func buyTapped(_ sender: NSButton) {
        guard sender.tag < Store.products.count else { return }
        let product = Store.products[sender.tag]
        Task { @MainActor in
            do { try await Store.buy(product) } catch { self.library.show(error) }
            self.refresh()
        }
    }

    @objc private func restoreTapped() {
        Task { @MainActor in
            await Store.restore()
            self.refresh()
        }
    }
}
#endif
