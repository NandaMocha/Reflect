import SwiftUI

struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: Constants.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: Constants.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)

                    if let message = message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .padding(Constants.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}

// MARK: - Sync Progress View

struct SyncProgressView: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: Constants.Spacing.md) {
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .primaryDefault))
                .frame(width: 200)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(Int(progress * 100))%")
                .font(.headline)
                .foregroundStyle(Color.primaryDefault)
        }
        .padding(Constants.Spacing.lg)
        .glassCard()
    }
}

#Preview {
    VStack(spacing: 40) {
        LoadingView(message: "Loading reflections...")

        SyncProgressView(progress: 0.65, message: "Syncing with iCloud...")
    }
}
