import SwiftUI

struct CelebrationView: View {
    let trigger: BadgeUnlockEvent.CelebrationTrigger
    let badgeName: String
    let onDismiss: () -> Void

    @State private var showCelebration = false
    @State private var autoDismissTask: Task<Void, Never>?

    init(
        trigger: BadgeUnlockEvent.CelebrationTrigger,
        badgeName: String = "Achievement Unlocked!",
        onDismiss: @escaping () -> Void = {}
    ) {
        self.trigger = trigger
        self.badgeName = badgeName
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            switch trigger {
            case .confetti:
                celebrationContent {
                    AnyView(ConfettiView())
                }
            case .sparkles:
                celebrationContent {
                    AnyView(SparklesView())
                }
            case .fireworks:
                celebrationContent {
                    AnyView(FireworksView())
                }
            case .maximum:
                celebrationContent {
                    AnyView(MaximumCelebrationView())
                }
            case .none:
                EmptyView()
            }
        }
        .onAppear {
            showCelebration = true
            scheduleAutoDismiss()
        }
        .onDisappear {
            autoDismissTask?.cancel()
        }
    }

    @ViewBuilder
    private func celebrationContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            content()

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button(action: dismiss) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            showCelebration = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func scheduleAutoDismiss() {
        let duration: Double
        switch trigger {
        case .confetti:
            duration = 3.0
        case .sparkles:
            duration = 3.5
        case .fireworks:
            duration = 4.0
        case .maximum:
            duration = 5.0
        case .none:
            return
        }

        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Confetti") {
    CelebrationView(
        trigger: .confetti,
        badgeName: "3-Day Streak"
    )
}

#Preview("Sparkles") {
    CelebrationView(
        trigger: .sparkles,
        badgeName: "7-Day Streak"
    )
}

#Preview("Fireworks") {
    CelebrationView(
        trigger: .fireworks,
        badgeName: "14-Day Streak"
    )
}

#Preview("Maximum") {
    CelebrationView(
        trigger: .maximum,
        badgeName: "30-Day Streak"
    )
}
