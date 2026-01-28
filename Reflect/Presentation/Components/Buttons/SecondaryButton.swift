import SwiftUI

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.isDestructive = isDestructive
        self.action = action
    }

    private var foregroundColor: Color {
        if isDisabled {
            return .gray
        }
        return isDestructive ? .error : .primaryDefault
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            HStack(spacing: Constants.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: foregroundColor))
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
                    .stroke(foregroundColor, lineWidth: 1.5)
            )
            .foregroundColor(foregroundColor)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(PressableCardStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        SecondaryButton("Cancel", icon: "xmark") {
            print("Tapped")
        }

        SecondaryButton("Delete", icon: "trash", isDestructive: true) {
            print("Tapped")
        }

        SecondaryButton("Disabled", isDisabled: true) {
            print("Tapped")
        }
    }
    .padding()
}
