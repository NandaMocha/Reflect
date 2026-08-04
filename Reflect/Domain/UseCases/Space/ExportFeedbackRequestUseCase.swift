import Foundation

enum FeedbackExportFormat {
    case json
    case csv
}

protocol ExportFeedbackRequestUseCaseProtocol {
    func execute(input: ExportFeedbackRequestUseCase.Input) async throws -> URL
}

/// Exports a feedback request (reflection + questions + answers) to a file in
/// `FileManager.default.temporaryDirectory`, grouped by question.
final class ExportFeedbackRequestUseCase: ExportFeedbackRequestUseCaseProtocol {
    struct Input {
        let reflection: SpaceReflection
        let answers: [SpaceAnswer]
        let format: FeedbackExportFormat
    }

    func execute(input: Input) async throws -> URL {
        switch input.format {
        case .json:
            return try exportJSON(input)
        case .csv:
            // CSV path lands in TASK-035.
            throw SpaceError.exportFormatUnsupported
        }
    }

    // MARK: - JSON

    private func exportJSON(_ input: Input) throws -> URL {
        let questions = input.reflection.questions.sorted { $0.order < $1.order }
        let questionExports = questions.map { question in
            FeedbackQuestionExport(
                id: question.id,
                text: question.text,
                order: question.order,
                answers: input.answers
                    .filter { $0.questionId == question.id }
                    .map(FeedbackAnswerExport.init)
            )
        }

        let export = FeedbackRequestExport(
            requestId: input.reflection.id,
            title: input.reflection.title,
            note: input.reflection.note,
            exportDate: Date(),
            questions: questionExports
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(export)

        let fileName = "\(Constants.App.name)_Feedback_\(Date().feedbackExportFileName).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try jsonData.write(to: tempURL)
        return tempURL
    }
}

// MARK: - Export Structures

struct FeedbackRequestExport: Codable {
    let requestId: String
    let title: String
    let note: String?
    let exportDate: Date
    let questions: [FeedbackQuestionExport]
}

struct FeedbackQuestionExport: Codable {
    let id: String
    let text: String
    let order: Int
    let answers: [FeedbackAnswerExport]
}

struct FeedbackAnswerExport: Codable {
    let memberRecordName: String
    let displayName: String
    let text: String
    let hasPhoto: Bool
    let photoFileName: String?
    let timestamp: Date?

    init(from answer: SpaceAnswer) {
        self.memberRecordName = answer.authorRecordName ?? ""
        self.displayName = answer.authorDisplayName ?? ""
        self.text = answer.text
        self.hasPhoto = answer.imageData != nil
        self.photoFileName = answer.imageData != nil ? "\(answer.id).jpg" : nil
        self.timestamp = answer.modifiedAt ?? answer.createdAt
    }
}

// MARK: - Date Extension

private extension Date {
    var feedbackExportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: self)
    }
}
