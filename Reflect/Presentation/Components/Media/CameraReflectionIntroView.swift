import SwiftUI

/// One-time, onboarding-styled intro for camera reflections. Two steps: (1) explain what a camera
/// reflection is, (2) choose front/back camera. "Continue" hands control back to the flow, which
/// requests permission and opens the camera. Presented by `CameraReflectionFlowModifier`.
struct CameraReflectionIntroView: View {
    @Binding var position: CameraPosition
    let onContinue: () -> Void
    let onCancel: () -> Void

    /// 0 = explain, 1 = choose camera.
    @State private var step: Int = 0

    private var isLastStep: Bool { step == 1 }

    var body: some View {
        VStack(spacing: 0) {
            header

            TabView(selection: $step) {
                explainStep.tag(0)
                chooseStep.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: step)

            footer
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(Constants.Spacing.md)
    }

    // MARK: - Step 1: Explain

    private var explainStep: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                heroIcon("camera.fill")

                VStack(spacing: Constants.Spacing.sm) {
                    Text("Camera Reflections")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Capture a moment from your day as a photo or short video and attach it to your reflection.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Constants.Spacing.md) {
                    highlightRow("photo.on.rectangle.angled", "Add a photo or a short video, up to 60 seconds.")
                    highlightRow("lock.fill", "The camera is only used while you capture — nothing is shared.")
                }
            }
            .padding(.horizontal, Constants.Spacing.lg)
            .padding(.top, Constants.Spacing.md)
            .padding(.bottom, Constants.Spacing.xl)
        }
    }

    // MARK: - Step 2: Choose camera

    private var chooseStep: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                VStack(spacing: Constants.Spacing.sm) {
                    Text("Choose Your Camera")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("You can still switch cameras once the camera is open.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: Constants.Spacing.md) {
                    ForEach(CameraPosition.allCases) { option in
                        cameraOptionCard(option)
                    }
                }
            }
            .padding(.horizontal, Constants.Spacing.lg)
            .padding(.top, Constants.Spacing.md)
            .padding(.bottom, Constants.Spacing.xl)
        }
    }

    private func cameraOptionCard(_ option: CameraPosition) -> some View {
        let isSelected = position == option
        return Button {
            HapticManager.shared.selection()
            position = option
        } label: {
            HStack(spacing: Constants.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                        .fill(Color.primaryDefault.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: option.icon)
                        .font(.title3)
                        .foregroundStyle(Color.primaryDefault)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.body.weight(.semibold))
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.primaryDefault : Color.secondary.opacity(0.4))
            }
            .multilineTextAlignment(.leading)
            .padding(Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(isSelected ? Color.primaryDefault.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .stroke(isSelected ? Color.primaryDefault : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Constants.Spacing.md) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.primaryDefault : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }

            if isLastStep {
                PrimaryButton("Continue", icon: "camera.fill") {
                    onContinue()
                }
            } else {
                PrimaryButton("Next", icon: "arrow.right") {
                    withAnimation { step = 1 }
                }
            }
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.top, Constants.Spacing.md)
        .padding(.bottom, Constants.Spacing.lg)
        .background(Color(.systemBackground))
    }

    // MARK: - Building blocks (mirrors OnboardingPageView)

    private func heroIcon(_ name: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.primaryDefault.opacity(0.12))
                .frame(width: 120, height: 120)
            Image(systemName: name)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.primaryDefault)
        }
        .accessibilityHidden(true)
    }

    private func highlightRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Constants.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                    .fill(Color.primaryDefault.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(Color.primaryDefault)
            }
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    @Previewable @State var position: CameraPosition = .back
    return CameraReflectionIntroView(
        position: $position,
        onContinue: {},
        onCancel: {}
    )
}
