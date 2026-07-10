import Foundation
import StoreKit

/// StoreKit 2 wrapper for the single non-consumable (spec §11).
/// Every ticket-saving alert is free forever; Plus adds multiple cars,
/// curb-card themes, and Longest Spot. StoreKit is the source of truth; the
/// App Group flag is only a mirror for widgets.
@MainActor
public final class PlusStore: ObservableObject {

    public static let productId = "sweep.plus"

    @Published public private(set) var hasPlus = false
    @Published public private(set) var product: Product?

    private let store: PersistenceStore
    private var updatesTask: Task<Void, Never>?

    public init(store: PersistenceStore) {
        self.store = store
        hasPlus = store.hasPlus
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func load() async {
        product = try? await Product.products(for: [Self.productId]).first
        await refreshEntitlement()
    }

    public func purchase() async {
        guard let product else { return }
        guard let result = try? await product.purchase() else { return }
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
        }
        await refreshEntitlement()
    }

    public func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productId {
                entitled = true
            }
        }
        hasPlus = entitled
        store.hasPlus = entitled   // mirror into App Group for widgets
    }
}
