import SwiftUI

struct ErrorView: View {
    let error: Error
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Color.error)

            VStack(spacing: Constants.Spacing.xs) {
                Text("Something went wrong")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let retryAction = retryAction {
                PrimaryButton("Try Again", icon: "arrow.clockwise", action: retryAction)
                    .frame(maxWidth: 200)
            }
        }
        .padding(Constants.Spacing.xl)
    }
}

// MARK: - Inline Error View

struct InlineErrorView: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.error)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Constants.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                .fill(Color.error.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                .stroke(Color.error.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Toast View

struct ToastView: View {
    enum ToastType {
        case success
        case error
        case warning
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .success
            case .error: return .error
            case .warning: return .warning
            case .info: return .info
            }
        }
    }

    let message: String
    let type: ToastType

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(Constants.Spacing.md)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    VStack(spacing: 40) {
        ErrorView(error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to load data"])) {
            print("Retry")
        }

        InlineErrorView(message: "Invalid email format") {
            print("Dismiss")
        }
        .padding()

        ToastView(message: "Reflection saved!", type: .success)
        ToastView(message: "Something went wrong", type: .error)
    }
}
