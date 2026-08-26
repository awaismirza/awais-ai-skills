import StoreKit
import SwiftUI

/// Paywall sheet shown by the top-right upgrade pill, a Settings row, or a
/// triggered usage-based nudge (Feature 4) — all three should present this
/// same view via one shared `isPaywallPresented` flag.
///
/// Works for EITHER monetization model without hardcoding one:
/// - Auto-renewable subscription: pass 2+ products, price cards render as
///   selectable tiers.
/// - One-time non-consumable "lifetime unlock": pass exactly 1 product, the
///   single price card renders pre-selected with no tier picker.
///
/// See references/premium-entry-point.md for how to detect (or ask once)
/// which model an app actually uses before wiring this up.
public struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    let eyebrow: String                 // e.g. "VOICEALARM PRO"
    let headline: String                // benefit-led, states the outcome
    let featureBullets: [String]        // 2-4 short lines
    let products: [Product]             // 1 = one-time unlock, 2+ = subscription tiers
    let legalFinePrint: String          // renewal/expiry terms, stated plainly
    let onPurchase: (Product) async -> Void
    let onRestore: () async -> Void

    @State private var selectedProductID: String?
    @State private var isPurchasing = false

    public init(
        eyebrow: String,
        headline: String,
        featureBullets: [String],
        products: [Product],
        legalFinePrint: String,
        onPurchase: @escaping (Product) async -> Void,
        onRestore: @escaping () async -> Void
    ) {
        self.eyebrow = eyebrow
        self.headline = headline
        self.featureBullets = featureBullets
        self.products = products
        self.legalFinePrint = legalFinePrint
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self._selectedProductID = State(initialValue: products.first?.id)
    }

    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }

            Text(eyebrow)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.accentColor)

            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(featureBullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.body)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Price card(s) — one row per product. A single product renders as
            // one pre-selected "lifetime unlock" card; multiple products render
            // as a selectable subscription-tier picker.
            VStack(spacing: 10) {
                ForEach(products, id: \.id) { product in
                    priceCard(for: product)
                }
            }

            Button {
                guard let product = products.first(where: { $0.id == selectedProductID }) else { return }
                isPurchasing = true
                Task {
                    await onPurchase(product)
                    isPurchasing = false
                }
            } label: {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(products.count > 1 ? "Subscribe" : "Buy for \(selectedPriceText)")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .disabled(isPurchasing || selectedProductID == nil)

            Button("Not Now") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Restore Purchases") {
                Task { await onRestore() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)

            Text(legalFinePrint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var selectedPriceText: String {
        products.first(where: { $0.id == selectedProductID })?.displayPrice ?? ""
    }

    @ViewBuilder
    private func priceCard(for product: Product) -> some View {
        let isSelected = product.id == selectedProductID
        Button {
            selectedProductID = product.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(priceSubtitle(for: product))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func priceSubtitle(for product: Product) -> String {
        switch product.type {
        case .autoRenewable: return "auto-renews, cancel anytime"
        case .nonConsumable: return "one-time purchase"
        default: return ""
        }
    }
}
