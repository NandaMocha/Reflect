import SwiftUI

// MARK: - Floating Action Menu

struct FloatingActionMenu: View {
    @Binding var isExpanded: Bool
    var onTap: () -> Void
    var onCameraTap: () -> Void
    var onVoiceTap: () -> Void

    @Namespace private var namespace
    @State private var isPressing = false

    // Button sizes
    private let mainButtonSize: CGFloat = 56
    private let actionButtonSize: CGFloat = 44
    private let buttonSpacing: CGFloat = 12

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
                    .padding(.bottom, 16)
                }
                

                // Main FAB button
                mainButton
            }
        }
    }

    // MARK: - Main Button

    private var mainButton: some View {
        ZStack {
            // Morphing glass backdrop effect
            MorphingGlassBackdrop(
                isPressing: $isPressing,
                size: mainButtonSize,
                color: .primaryDefault
            )

            Circle()
                .fill(Color.primaryDefault)
                .shadow(
                    color: Color.primaryDefault.opacity(0.4),
                    radius: 8,
                    x: 0,
                    y: 4
                )

            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isExpanded)
        }
        .frame(width: mainButtonSize, height: mainButtonSize)
        .contentShape(Circle())
        .scaleEffect(isPressing ? 0.92 : 1.0)
        .glassEffect()
        .glassEffectID("fab", in: namespace)
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            // Long press completed
            handleLongPress()
        } onPressingChanged: { pressing in
            // Visual feedback during press
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressing = pressing
            }
        }
    }

    // MARK: - Handlers

    private func handleLongPress() {
        guard !isExpanded else { return }
        HapticManager.shared.lightImpact()
        // Reset pressing state after long press completes
        isPressing = false
        withAnimation(.bouncy(duration: 0.4)) {
            isExpanded = true
        }
    }

    private func handleTap() {
        HapticManager.shared.mediumImpact()
        if isExpanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
        } else {
            onTap()
        }
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
