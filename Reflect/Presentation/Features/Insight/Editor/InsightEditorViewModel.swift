import Foundation
import Observation

@Observable
@MainActor
final class InsightEditorViewModel {
    // MARK: - Mode

    enum Mode {
        case create
        case edit(Insight)
    }

    // MARK: - State

    var text: String = ""
    var type: InsightType = .note
    var followUp: String = ""
    var isSaving: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let mode: Mode
    private let createUseCase: CreateInsightUseCaseProtocol
    private let updateUseCase: UpdateInsightUseCaseProtocol

    // MARK: - Initialization

    init(
        mode: Mode,
        createUseCase: CreateInsightUseCaseProtocol,
        updateUseCase: UpdateInsightUseCaseProtocol
    ) {
        self.mode = mode
        self.createUseCase = createUseCase
        self.updateUseCase = updateUseCase

        if case .edit(let insight) = mode {
            text = insight.text
            type = insight.type
            followUp = insight.followUp
        }
    }

    // MARK: - Computed

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= Constants.Limits.insightTextMaxLength
    }

    var characterCount: Int {
        text.count
    }

    var characterLimit: Int {
        Constants.Limits.insightTextMaxLength
    }

    // MARK: - Actions

    func save() async -> Bool {
        guard canSave else { return false }

        isSaving = true
        errorMessage = nil

        do {
            switch mode {
            case .create:
                _ = try await createUseCase.execute(text: text, type: type, followUp: followUp)
            case .edit(let insight):
                try await updateUseCase.execute(insight: insight, text: text, type: type, followUp: followUp)
            }

            isSaving = false
            HapticManager.shared.success()
            return true
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }
}
