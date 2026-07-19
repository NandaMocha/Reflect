import SwiftUI

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            HStack(spacing: Constants.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }

                Text(title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Constants.Spacing.sm)
            .padding(.horizontal, Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(isDisabled ? Color.gray : Color.primaryDefault)
            )
            .foregroundStyle(.white)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(PressableCardStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        PrimaryButton("Save", icon: "checkmark") {
            print("Tapped")
        }

        PrimaryButton("Loading", isLoading: true) {
            print("Tapped")
        }

        PrimaryButton("Disabled", isDisabled: true) {
            print("Tapped")
        }
    }
    .padding()
}
