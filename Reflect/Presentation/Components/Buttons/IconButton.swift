import SwiftUI

struct IconButton: View {
    let icon: String
    let size: Size
    let color: Color
    let action: () -> Void

    enum Size {
        case small
        case medium
        case large

        var dimension: CGFloat {
            switch self {
            case .small: return 32
            case .medium: return 44
            case .large: return 56
            }
        }

        var iconFont: Font {
            switch self {
            case .small: return .body
            case .medium: return .title3
            case .large: return .title2
            }
        }
    }

    init(
        icon: String,
        size: Size = .medium,
        color: Color = .primaryDefault,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            action()
        }) {
            Image(systemName: icon)
                .font(size.iconFont)
                .foregroundColor(color)
                .frame(width: size.dimension, height: size.dimension)
                .contentShape(Circle())
        }
        .buttonStyle(IconButtonStyle())
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    HStack(spacing: 20) {
        IconButton(icon: "plus", size: .small) {
            print("Small")
        }

        IconButton(icon: "gear", size: .medium) {
            print("Medium")
        }

        IconButton(icon: "trash", size: .large, color: .error) {
            print("Large")
        }
    }
}
