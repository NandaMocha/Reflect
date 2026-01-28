import Foundation
import SwiftData
import Observation

@Observable
final class LearningFormViewModel {
    // MARK: - Form State
    var title: String = ""
    var descriptionText: String = ""
    var selectedIconName: String = "book.fill"
    var selectedColorHex: String = Constants.LearningColors.ocean

    // MARK: - UI State
    var isLoading: Bool = false
    var errorMessage: String?
    var hasChanges: Bool = false

    // MARK: - Mode
    private(set) var isEditing: Bool = false
    private var existingLearning: Learning?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let createUseCase: CreateLearningUseCaseProtocol
    private let updateUseCase: UpdateLearningUseCaseProtocol

    // MARK: - Available Options
    let availableIcons: [String] = [
        "book.fill", "lightbulb.fill", "brain.head.profile", "graduationcap.fill",
        "pencil.and.outline", "doc.text.fill", "folder.fill", "star.fill",
        "heart.fill", "flame.fill", "leaf.fill", "globe", "music.note",
        "paintbrush.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "camera.fill", "mic.fill", "video.fill", "gamecontroller.fill"
    ]

    let availableColors: [String] = [
        Constants.LearningColors.coral,
        Constants.LearningColors.ocean,
        Constants.LearningColors.lavender,
        Constants.LearningColors.mint,
        Constants.LearningColors.peach,
        Constants.LearningColors.sky,
        Constants.LearningColors.rose,
        Constants.LearningColors.sage
    ]

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        createUseCase: CreateLearningUseCaseProtocol? = nil,
        updateUseCase: UpdateLearningUseCaseProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.createUseCase = createUseCase ?? CreateLearningUseCase(
            repository: LearningRepository(modelContext: modelContext)
        )
        self.updateUseCase = updateUseCase ?? UpdateLearningUseCase(
            repository: LearningRepository(modelContext: modelContext)
        )
    }

    // MARK: - Setup

    func configure(with learning: Learning?) {
        if let learning = learning {
            isEditing = true
            existingLearning = learning
            title = learning.title
            descriptionText = learning.descriptionText ?? ""
            selectedIconName = learning.iconName
            selectedColorHex = learning.colorHex
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        title.count <= Constants.Limits.learningTitleMaxLength
    }

    var titleError: String? {
        if title.isEmpty {
            return nil
        }
        if title.count > Constants.Limits.learningTitleMaxLength {
            return "Title is too long (max \(Constants.Limits.learningTitleMaxLength) characters)"
        }
        return nil
    }

    var descriptionError: String? {
        if descriptionText.count > Constants.Limits.learningDescriptionMaxLength {
            return "Description is too long (max \(Constants.Limits.learningDescriptionMaxLength) characters)"
        }
        return nil
    }

    // MARK: - Actions

    func save() async -> Bool {
        guard isValid else {
            errorMessage = "Please fill in all required fields"
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            if isEditing, let existing = existingLearning {
                try await updateUseCase.execute(
                    learning: existing,
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: descriptionText.isEmpty ? nil : descriptionText.trimmingCharacters(in: .whitespaces),
                    colorHex: selectedColorHex,
                    iconName: selectedIconName
                )
            } else {
                _ = try await createUseCase.execute(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: descriptionText.isEmpty ? nil : descriptionText.trimmingCharacters(in: .whitespaces),
                    colorHex: selectedColorHex,
                    iconName: selectedIconName
                )
            }

            isLoading = false
            HapticManager.shared.success()
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    func updateIcon(_ iconName: String) {
        selectedIconName = iconName
        hasChanges = true
        HapticManager.shared.selection()
    }

    func updateColor(_ colorHex: String) {
        selectedColorHex = colorHex
        hasChanges = true
        HapticManager.shared.selection()
    }

    func trackChanges() {
        hasChanges = true
    }
}
