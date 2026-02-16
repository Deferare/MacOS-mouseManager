import SwiftUI
import StoreKit

struct AboutView: View {
    private let supportEmail = "deferare@icloud.com"
    @StateObject private var donationStore = DonationStore()

    var body: some View {
        Form {
            Section {
                FormRowLabel(
                    "Mouse Manager",
                    subtitle: "Public Preview for macOS 26+ focused on mouse buttons and smooth scrolling."
                )
                FormRowLabel(
                    "Notes",
                    subtitle: "This build is distributed as a Public Preview. First launch may require right-click Open and Open Anyway in Privacy & Security."
                )
                FormRowLabel(
                    "Permissions",
                    subtitle: "Mouse and scroll interception features require Accessibility permission."
                )
                FormRowLabel(
                    "Updates",
                    subtitle: "Updates are manual. Install the latest GitHub Release ZIP and replace the app in /Applications."
                )
                FormRowLabel(
                    "Support Email",
                    subtitle: "\(supportEmail) (subject: [MouseManager Preview])"
                )
            }

            Section("Support") {
                VStack(alignment: .leading, spacing: 12) {
                    FormRowLabel(
                        "Support Mouse Manager",
                        subtitle: "If this app helps your workflow, you can support future development."
                    )

                    if donationStore.isLoadingProducts {
                        ProgressView("Loading donation options...")
                    } else if donationStore.products.isEmpty {
                        FormHelpText(text: "No donation products are available yet. Check App Store Connect product IDs.", leadingPadding: 0)
                    } else {
                        HStack(spacing: 10) {
                            ForEach(donationStore.products, id: \.id) { product in
                                Button {
                                    Task {
                                        await donationStore.purchase(product)
                                    }
                                } label: {
                                    Label(product.displayPrice, systemImage: "heart.fill")
                                        .frame(minWidth: 72)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(donationStore.isPurchasing)
                            }
                        }
                    }

                    if donationStore.isPurchasing {
                        ProgressView("Processing purchase...")
                            .controlSize(.small)
                    }

                    if let statusMessage = donationStore.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            await donationStore.loadProducts()
        }
    }
}

@MainActor
private final class DonationStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var statusMessage: String?

    private static let donationProductIDs = [
        "com.deferare.MouseManager.tip.1",
        "com.deferare.MouseManager.tip.3",
        "com.deferare.MouseManager.tip.5"
    ]

    func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: Self.donationProductIDs)
            let displayOrder = Dictionary(uniqueKeysWithValues: Self.donationProductIDs.enumerated().map { ($1, $0) })
            products = loadedProducts.sorted { (displayOrder[$0.id] ?? .max) < (displayOrder[$1.id] ?? .max) }
        } catch {
            statusMessage = "Couldn't load donation options. \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    statusMessage = "Thanks for supporting Mouse Manager."
                case .unverified(_, let error):
                    statusMessage = "Purchase verification failed. \(error.localizedDescription)"
                }
            case .pending:
                statusMessage = "Purchase is pending approval."
            case .userCancelled:
                statusMessage = "Purchase was cancelled."
            @unknown default:
                statusMessage = "Purchase failed due to an unknown error."
            }
        } catch {
            statusMessage = "Purchase failed. \(error.localizedDescription)"
        }
    }
}

#Preview("AboutView") {
    MainActor.assumeIsolated {
        PreviewHost.defaults {
            AboutView()
                .frame(width: 720, height: 460)
        }
    }
}
