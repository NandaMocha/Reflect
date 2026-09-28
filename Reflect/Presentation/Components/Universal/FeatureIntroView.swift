import SwiftUI

/// A one-time, onboarding-styled instruction sheet shown the first time a feature is opened.
///
/// This is the generic sibling of `CameraReflectionIntroView`: same visual language (hero glyph,
/// highlight rows, primary CTA) built from the shared onboarding building blocks, but driven by
/// data so every feature intro looks identical. Present it via `View.firstOpenIntro(_:flagKey:)`,
/// which handles the "only on first open" gating with a `UserDefaults` flag.
struct FeatureIntro {
    let icon: String
    let title: String
    let subtitle: String
    let highlights: [OnboardingHighlight]
    var color: Color = .primaryDefault
    var buttonTitle: String = "Got it"
    var buttonIcon: String? = nil
}

// MARK: - Presets

extension FeatureIntro {
    /// Voice notes — what they are, plus a heads-up that mic + speech access are needed. Its CTA
    /// primes those permissions (see `VoiceAudioView`), so the button reads "Continue".
    static let voice = FeatureIntro(
        icon: "mic.fill",
        title: "Voice Notes",
        subtitle: "Record a spoken reflection — we'll transcribe it for you.",
        highlights: [
            OnboardingHighlight(icon: "waveform", text: "Tap record and just talk; play it back before saving."),
            OnboardingHighlight(icon: "text.quote", text: "Your words are transcribed on-device as you speak."),
            OnboardingHighlight(icon: "lock.fill", text: "Microphone and Speech Recognition access are needed to record.")
        ],
        color: .primaryDefault,
        buttonTitle: "Continue",
        buttonIcon: "arrow.right"
    )
}

// MARK: - View

struct FeatureIntroView: View {
    let intro: FeatureIntro
    /// Called for both the primary button and the close (X). The presenter decides what "done"
    /// means (dismiss, request a permission, …).
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: Constants.Spacing.xl) {
                    heroIcon

                    VStack(spacing: Constants.Spacing.sm) {
                        Text(intro.title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(intro.subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                        ForEach(intro.highlights) { highlight in
                            OnboardingHighlightRow(highlight: highlight, color: intro.color)
                        }
                    }
                }
                .padding(.horizontal, Constants.Spacing.lg)
                .padding(.top, Constants.Spacing.md)
                .padding(.bottom, Constants.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close")
        }
        .padding(Constants.Spacing.md)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack {
            PrimaryButton(intro.buttonTitle, icon: intro.buttonIcon) {
                onDismiss()
            }
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.top, Constants.Spacing.md)
        .padding(.bottom, Constants.Spacing.lg)
        .background(Color(.systemBackground))
    }

    // MARK: - Hero

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(intro.color.opacity(0.12))
                .frame(width: 120, height: 120)
            Image(systemName: intro.icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(intro.color)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - First-open gating

/// Presents `intro` as a full-screen cover the first time the modified view appears, then never
/// again. The "seen" flag is written on dismiss, so it sticks whether the user taps the button
/// or the close control. A cover (rather than a sheet) matches `CameraReflectionIntroView` and
/// stays reliable even when the host is itself a sheet (e.g. the Achievements gallery).
private struct FirstOpenIntroModifier: ViewModifier {
    let intro: FeatureIntro
    let flagKey: String

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !UserDefaults.standard.bool(forKey: flagKey) {
                    isPresented = true
                }
            }
            .fullScreenCover(isPresented: $isPresented, onDismiss: markSeen) {
                FeatureIntroView(intro: intro) { isPresented = false }
            }
    }

    private func markSeen() {
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}

extension View {
    /// Shows a one-time `FeatureIntroView` the first time this view appears, gated by `flagKey`
    /// (a `Constants.UserDefaults` key). No-op on every subsequent appearance.
    func firstOpenIntro(_ intro: FeatureIntro, flagKey: String) -> some View {
        modifier(FirstOpenIntroModifier(intro: intro, flagKey: flagKey))
    }
}
