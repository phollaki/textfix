import StoreKit

@MainActor
final class Store: ObservableObject {
    static let productIds = [
        "com.puteanihollakos.textfix.pro.monthly",
        "com.puteanihollakos.textfix.pro.yearly",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var transaction: String?
    var onChange: (() -> Void)?
    private var updates: Task<Void, Never>?

    func start() {
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await refresh()
            }
        }
        Task {
            products = ((try? await Product.products(for: Self.productIds)) ?? []).sorted { $0.price < $1.price }
            await refresh()
        }
    }

    func refresh() async {
        var latest: String?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIds.contains(transaction.productID) {
                latest = result.jwsRepresentation
            }
        }
        transaction = latest
        onChange?()
    }

    func buy(_ product: Product) async -> String? {
        do {
            let result = try await product.purchase()
            if case .success(.verified(let transaction)) = result { await transaction.finish() }
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func restore() async -> String? {
        do {
            try await AppStore.sync()
            await refresh()
            return transaction == nil ? "No active TextFix Pro subscription was found." : nil
        } catch {
            return error.localizedDescription
        }
    }
}
