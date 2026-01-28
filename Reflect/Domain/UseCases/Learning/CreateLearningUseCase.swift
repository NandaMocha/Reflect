import Foundation

protocol CreateLearningUseCaseProtocol {
    func execute(title: String, description: String?, colorHex: String, iconName: String) async throws -> Learning
}

final class CreateLearningUseCase: CreateLearningUseCaseProtocol {
    private let repository: LearningRepositoryProtocol

    init(repository: LearningRepositoryProtocol) {
        self.repository = repository
    }

    func execute(title: String, description: String?, colorHex: String, iconName: String) async throws -> Learning {
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

        let learning = Learning(
            title: trimmedTitle,
            descriptionText: description?.trimmingCharacters(in: .whitespaces),
            colorHex: colorHex,
            iconName: iconName
        )

        try await repository.create(learning)
        return learning
    }
}

enum LearningError: Error, LocalizedError {
    case titleRequired
    case titleTooLong
    case descriptionTooLong
    case notFound

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            return "Title is required"
        case .titleTooLong:
            return "Title is too long (max \(Constants.Limits.learningTitleMaxLength) characters)"
        case .descriptionTooLong:
            return "Description is too long (max \(Constants.Limits.learningDescriptionMaxLength) characters)"
        case .notFound:
            return "Learning not found"
        }
    }
}
