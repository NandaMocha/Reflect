import SwiftUI

/// Root view for the Clip — switches on `ClipSession.phase`. Every case here is a lightweight
/// placeholder; the phases fill in with real composer/all-feedback screens across later tickets
/// (AC-030/031/032). Uses only system semantic colors — `Reflect/Core/Extensions/Color+Hex.swift`
/// isn't shared into this target yet (see `Reflect/ClipShared/README.md`).
struct ClipRootView: View {
    let session: ClipSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
            case .needsName:
                NeedsNamePlaceholderView(session: session)
            case .compose:
                PhasePlaceholderView(
                    systemImage: "square.and.pencil",
                    title: "Ready to respond",
                    message: composeGreeting
                )
            case .allFeedback:
                PhasePlaceholderView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "Everyone's answers",
                    message: "The shared feed lands in a later ticket."
                )
            case .invalidLink:
                PhasePlaceholderView(
                    systemImage: "link.badge.plus",
                    title: "This link isn't working",
                    message: "Ask for a fresh invite — this one may have expired or been revoked."
                )
            }
        }
        .animation(.default, value: session.phase)
    }

    private var composeGreeting: String {
        guard let name = session.guestIdentity?.displayName, !name.isEmpty else {
            return "The composer lands in a later ticket."
        }
        return "Hi \(name) — the composer lands in a later ticket."
    }
}

/// Collects the guest's display name once; `ClipSession.submitDisplayName` persists it and
/// advances the phase machine.
private struct NeedsNamePlaceholderView: View {
    let session: ClipSession
    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            VStack(spacing: Constants.Spacing.xs) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("What should we call you?")
                    .font(.title2.bold())
                Text("Your name is shown next to what you write.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .focused($nameFieldFocused)
                .submitLabel(.done)
                .onSubmit(submit)

            Button("Continue", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Constants.Spacing.lg)
        .onAppear { nameFieldFocused = true }
    }

    private func submit() {
        session.submitDisplayName(name)
    }
}

private struct PhasePlaceholderView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Constants.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Constants.Spacing.lg)
    }
}
