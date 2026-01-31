import SwiftUI

// MARK: - Floating Action Menu

struct FloatingActionMenu: View {
    @Binding var isExpanded: Bool
    var onTap: () -> Void
    var onCameraTap: () -> Void
    var onVoiceTap: () -> Void

    @Namespace private var namespace

    // Button sizes
    private let mainButtonSize: CGFloat = 56
    private let actionButtonSize: CGFloat = 44
    private let buttonSpacing: CGFloat = 12
    private let bottomOffset: CGFloat = 16

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 0) {
                // Action buttons (above main button)
                if isExpanded {
                    VStack(spacing: buttonSpacing) {
                        cameraButton
                        voiceButton
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                    ))
                }

                // Main FAB button
                mainButton
            }
        }
    }

    // MARK: - Main Button

    private var mainButton: some View {
        Button(action: {
            HapticManager.shared.mediumImpact()
            onTap()
        }) {
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: mainButtonSize, height: mainButtonSize)
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
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
        .glassEffectID("fab", in: namespace)
    }

    // MARK: - Camera Button

    private var cameraButton: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
            // Small delay to allow collapse animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onCameraTap()
            }
        }) {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: actionButtonSize, height: actionButtonSize)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(
                            color: Color.accentColor.opacity(0.3),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                )
        }
        .buttonStyle(FABButtonStyle())
        .glassEffect()
        .glassEffectID("camera", in: namespace)
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
            // Small delay to allow collapse animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onVoiceTap()
            }
        }) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: actionButtonSize, height: actionButtonSize)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(
                            color: Color.accentColor.opacity(0.3),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                )
        }
        .buttonStyle(FABButtonStyle())
        .glassEffect()
        .glassEffectID("voice", in: namespace)
    }
}

// MARK: - Long Press Gesture Modifier

struct LongPressGestureModifier: ViewModifier {
    @Binding var isExpanded: Bool
    var onLongPress: () -> Void

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: 0.3,
                pressing: { isPressing in
                    // Optional visual feedback during press
                },
                perform: {
                    if !isExpanded {
                        HapticManager.shared.lightImpact()
                        withAnimation(.bouncy(duration: 0.4)) {
                            isExpanded = true
                        }
                        onLongPress()
                    }
                }
            )
    }
}

extension View {
    func longPressToExpand(
        _ isExpanded: Binding<Bool>,
        onLongPress: @escaping () -> Void
    ) -> some View {
        self.modifier(LongPressGestureModifier(isExpanded: isExpanded, onLongPress: onLongPress))
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var isExpanded = false

    ZStack {
        Color.backgroundPrimaryLight
            .ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionMenu(
                    isExpanded: $isExpanded,
                    onTap: { print("Tap") },
                    onCameraTap: { print("Camera") },
                    onVoiceTap: { print("Voice") }
                )
                .padding()
            }
        }
    }
}
