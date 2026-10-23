import Combine
import Foundation
import StoreKit

@MainActor
final class ProStore: ObservableObject {
    @Published private(set) var isPro = SkuffProduct.paywallDisabled
    @Published private(set) var product: Product?
    @Published var lastError: String?
    private var listening = false

    var upgradeLabel: String {
        if let price = product?.displayPrice {
            return "Upgrade · \(price)"
        }
        return "Upgrade"
    }

    func start() {
        guard !listening else { return }
        listening = true
        Task { await listen() }
        Task { await loadProduct() }
        Task { await refreshEntitlements() }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [SkuffProduct.proID]).first
        } catch {
            product = nil
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == SkuffProduct.proID else { continue }
            guard transaction.revocationDate == nil else { continue }
            entitled = true
            await transaction.finish()
        }
        isPro = entitled || SkuffProduct.paywallDisabled
    }

    func purchase() async {
        lastError = nil
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            lastError = "The Pro product isn't available from the App Store yet."
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "The purchase couldn't be verified."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                lastError = "No Pro purchase was found for this Apple ID."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func listen() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}
