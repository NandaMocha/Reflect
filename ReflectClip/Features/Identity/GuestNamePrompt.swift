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
/// **Edit-name mode (AC-031):** `isEditMode` switches `submit()` from
/// `ClipSession.submitDisplayName(_:)` (which unconditionally mints a *new* `guestId` — correct
/// for first-run, since there is no existing identity to preserve) to
/// `ClipSession.updateDisplayName(_:)` (which renames in place, keeping the existing `guestId`).
/// The composer's "Edit name" toolbar affordance presents this view with `isEditMode: true` so a
/// mid-session rename can't orphan answers already submitted under the old `guestId` — AC-032's
/// dedup key is `guestId`+`questionId`, not display name.
struct GuestNamePrompt: View {
    let session: ClipSession
    var isEditMode: Bool = false

    @State private var name: String
    @FocusState private var nameFieldFocused: Bool
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 40
    @Environment(\.dismiss) private var dismiss

    /// Matches `GUEST_NAME_MAX_LENGTH` in `scripts/server/clip-feedback.php`.
    static let maxLength = 50

    init(session: ClipSession, isEditMode: Bool = false) {
        self.session = session
        self.isEditMode = isEditMode
        _name = State(initialValue: session.guestIdentity?.displayName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOverLimit: Bool {
        trimmedName.count > Self.maxLength
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !isOverLimit
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.lg) {
                header
                field
                Button(isEditMode ? "Save" : "Continue", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
            .padding(Constants.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { nameFieldFocused = true }
    }

    private var header: some View {
        VStack(spacing: Constants.Spacing.xs) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(isEditMode ? "Edit your name" : "What should we call you?")
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
                .accessibilityHint("Shown next to what you write in this feedback thread. Maximum \(Self.maxLength) characters.")

            Text("\(name.count)/\(Self.maxLength)")
                .font(.caption)
                .fontWeight(isOverLimit ? .bold : .regular)
                .foregroundStyle(isOverLimit ? .red : .secondary)
                .monospacedDigit()
                .accessibilityHidden(true)

            if isOverLimit {
                Text("Names can be at most \(Self.maxLength) characters.")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        if isEditMode {
            session.updateDisplayName(trimmedName)
            dismiss()
        } else {
            session.submitDisplayName(trimmedName)
        }
    }
}
