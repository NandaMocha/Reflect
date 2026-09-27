import SwiftUI

/// What a permission primer says. Data-driven so every permission-gated feature (camera now, voice
/// next) shows the same small sheet with its own glyph and copy.
struct PermissionPrimerContent {
    let icon: String
    let title: String
    let message: String
    /// UI-test hook for the sheet's root.
    let accessibilityIdentifier: String
    var color: Color = .primaryDefault
}

// MARK: - Presets

extension PermissionPrimerContent {
    static let camera = PermissionPrimerContent(
        icon: "camera.fill",
        title: "Allow Camera Access",
        message: "Reflect uses the camera only while you take a photo or video for a reflection.",
        accessibilityIdentifier: "camera.permissionPrimer"
    )
}

/// A small sheet shown right before a system permission prompt, only while that permission is
/// still undetermined (see `PermissionPrimer`). "Continue" hands control back to the presenter,
/// which fires the system prompt; "Not Now" backs out without asking.
struct PermissionPrimerView: View {
    let content: PermissionPrimerContent
    let onContinue: () -> Void
    let onNotNow: () -> Void

    /// Set on the first "Continue" tap so a second tap can't queue another system prompt.
    @State private var isContinuing = false

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            ScrollView {
                VStack(spacing: Constants.Spacing.md) {
                    heroIcon

                    VStack(spacing: Constants.Spacing.sm) {
                        Text(content.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(content.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Constants.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: Constants.Spacing.sm) {
                PrimaryButton("Continue", isLoading: isContinuing) {
                    isContinuing = true
                    onContinue()
                }

                Button(action: onNotNow) {
                    Text("Not Now")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(.secondary)
                .disabled(isContinuing)
            }
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.bottom, Constants.Spacing.md)
        .background(Color(.systemBackground))
        .accessibilityIdentifier(content.accessibilityIdentifier)
    }

    // MARK: - Hero

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(content.color.opacity(0.12))
                .frame(width: 80, height: 80)
            Image(systemName: content.icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(content.color)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .sheet(isPresented: .constant(true)) {
            PermissionPrimerView(content: .camera, onContinue: {}, onNotNow: {})
                .presentationDetents([.medium])
        }
}
