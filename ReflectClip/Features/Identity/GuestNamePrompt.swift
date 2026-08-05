import SwiftUI

/// Collects the guest's display name once per device — shown when `ClipSession.phase` is
/// `.needsName`, before the composer becomes reachable. `ClipSession.submitDisplayName(_:)`
/// persists the result via `GuestIdentityStore` and advances the phase machine; a relaunch with
/// a stored identity skips this screen entirely (`ClipSession.refreshPhaseFromStoredIdentity()`).
///
/// Validation mirrors the full app's own name prompts (trimmed, non-empty — see
/// `SpaceFormViewModel.canSave`/`SpaceMembersViewModel.saveDisplayName`) plus a hard character
/// cap: `scripts/server/clip-feedback.php` rejects `guestName` over `GUEST_NAME_MAX_LENGTH` (50),
/// so the client enforces the same limit rather than letting a guest type a name the endpoint
/// will later bounce.
///
/// Uses only system semantic colors — `Reflect/Core/Extensions/Color+Hex.swift` (incl.
/// `Color.error`) isn't shared into this target yet (see `Reflect/ClipShared/README.md`), same
/// constraint noted in `ClipRootView`.
///
/// **Edit-name stub:** initializing with an already-saved identity (`session.guestIdentity` is
/// non-nil) prefills the field with the current name instead of starting blank, so this same view
/// doubles as an "edit name" prompt. No call site presents it that way yet — the composer
/// toolbar affordance that does is AC-031's job — but the prompt itself is ready for it.
struct GuestNamePrompt: View {
    let session: ClipSession

    @State private var name: String
    @FocusState private var nameFieldFocused: Bool
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40

    /// Matches `GUEST_NAME_MAX_LENGTH` in `scripts/server/clip-feedback.php`.
    static let maxLength = 50

    init(session: ClipSession) {
        self.session = session
        _name = State(initialValue: session.guestIdentity?.displayName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOverLimit: Bool {
        name.count > Self.maxLength
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !isOverLimit
    }

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            header
            field
            Button("Continue", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
        }
        .padding(Constants.Spacing.lg)
        .onAppear { nameFieldFocused = true }
    }

    private var header: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("What should we call you?")
                .font(.title2.bold())
            Text("Your name is shown next to what you write.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: Constants.Spacing.xs) {
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .focused($nameFieldFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityLabel("Your name")
                .accessibilityHint("Shown next to what you write in this feedback thread.")

            Text("\(name.count)/\(Self.maxLength)")
                .font(.caption)
                .foregroundStyle(isOverLimit ? .red : .secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        session.submitDisplayName(trimmedName)
    }
}
