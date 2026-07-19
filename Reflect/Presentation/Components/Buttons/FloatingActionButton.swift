import SwiftUI

struct FloatingActionButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    init(icon: String = "plus", accessibilityLabel: String = "Add", action: @escaping () -> Void) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        GlassEffectContainer {
            Button(action: {
                HapticManager.shared.mediumImpact()
                action()
            }) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(Color.primaryDefault)
                            .shadow(
                                color: Color.primaryDefault.opacity(0.4),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    )
            }
            .buttonStyle(FABButtonStyle())
            .glassEffect()
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimaryLight
            .ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton {
                    print("FAB tapped")
                }
                .padding()
            }
        }
    }
}
