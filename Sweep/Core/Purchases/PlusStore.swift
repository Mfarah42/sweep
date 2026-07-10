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

    /// User-facing store status — a buy button must never fail silently.
    @Published public private(set) var notice: String?

    public func load() async {
        product = try? await Product.products(for: [Self.productId]).first
        if product == nil {
            notice = "The store isn't reachable right now. In development, "
                + "run from Xcode (the Sweep scheme carries the test store)."
        } else {
            notice = nil
        }
        await refreshEntitlement()
    }

    public func purchase() async {
        if product == nil {
            await load()   // one retry — maybe the network came back
        }
        guard let product else { return }   // load() already set the notice
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                notice = nil
            case .success(.unverified):
                notice = "Purchase couldn't be verified — try Restore purchases."
            case .userCancelled:
                notice = nil
            case .pending:
                notice = "Purchase is pending approval."
            @unknown default:
                notice = nil
            }
        } catch {
            notice = "Purchase didn't complete: \(error.localizedDescription)"
        }
        await refreshEntitlement()
    }

    public func restore() async {
        do {
            try await AppStore.sync()
            notice = nil
        } catch {
            notice = "Restore didn't complete: \(error.localizedDescription)"
        }
        await refreshEntitlement()
        if !hasPlus {
            notice = "No previous purchase found for this Apple Account."
        }
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
