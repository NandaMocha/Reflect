import Foundation

protocol UpdateLearningUseCaseProtocol {
    func execute(learning: Learning, title: String, description: String?, colorHex: String, iconName: String) async throws
}

final class UpdateLearningUseCase: UpdateLearningUseCaseProtocol {
    private let repository: LearningRepositoryProtocol

    init(repository: LearningRepositoryProtocol) {
        self.repository = repository
    }

    func execute(learning: Learning, title: String, description: String?, colorHex: String, iconName: String) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

        guard !trimmedTitle.isEmpty else {
            throw LearningError.titleRequired
        }

        guard trimmedTitle.count <= Constants.Limits.learningTitleMaxLength else {
            throw LearningError.titleTooLong
        }

        if let desc = description, desc.count > Constants.Limits.learningDescriptionMaxLength {
            throw LearningError.descriptionTooLong
        }

        learning.title = trimmedTitle
        learning.descriptionText = description?.trimmingCharacters(in: .whitespaces)
        learning.colorHex = colorHex
        learning.iconName = iconName

        try await repository.update(learning)
    }
}
