import CloudKit
import Foundation
import Observation

/// Drives the create-space sheet. On a successful save it exposes the freshly created
/// `Space` and its `CKShare` so the view can immediately present the sharing controller —
/// create → invite is one continuous flow (plan §6.1–6.2).
@Observable
@MainActor
final class SpaceFormViewModel {

    // MARK: - State

    var name: String = ""
    var detail: String = ""
    var iconName: String = ""
    var colorHex: String = ""
    var isSaving: Bool = false
    var errorMessage: String?

    /// Set only after a successful create, for the invite hand-off.
    var createdSpace: Space?
    var createdShare: CKShare?

    // MARK: - Dependencies

    private let createUseCase: CreateSpaceUseCaseProtocol

    // MARK: - Initialization

    init(createUseCase: CreateSpaceUseCaseProtocol) {
        self.createUseCase = createUseCase
    }

    // MARK: - Computed

    var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= characterLimit && !isSaving
    }

    var characterCount: Int { name.count }

    var characterLimit: Int { Constants.Limits.spaceNameMaxLength }

    // MARK: - Actions

    /// Creates the space (validated in the use case) and fetches its share. Returns the
    /// new space on success, or `nil` after surfacing `errorMessage`.
    func save() async -> Space? {
        guard canSave else { return nil }

        isSaving = true
        errorMessage = nil

        do {
            // The use case hands back the CKShare it just created alongside the space — use it
            // directly. Re-fetching the share here previously raced CloudKit's read-after-write
            // on the new zone and threw `.notFound` ("That space could not be found").
            let (space, share) = try await createUseCase.execute(
                name: name,
                detail: detail,
                iconName: iconName.isEmpty ? nil : iconName,
                colorHex: colorHex.isEmpty ? nil : colorHex
            )

            createdSpace = space
            createdShare = share
            isSaving = false
            HapticManager.shared.success()
            return space
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return nil
        }
    }
}
