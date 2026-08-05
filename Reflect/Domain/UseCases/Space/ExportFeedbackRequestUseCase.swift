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
            return try exportCSV(input)
        }
    }

    // MARK: - CSV

    private func exportCSV(_ input: Input) throws -> URL {
        let questions = input.reflection.questions.sorted { $0.order < $1.order }
        var lines: [String] = []

        for question in questions {
            lines.append(csvField("Question \(question.order + 1): \(question.text)"))
            lines.append(["member", "answer", "photo", "timestamp", "answerIndex"].map(csvField).joined(separator: ","))

            let questionAnswers = input.answers.filter { $0.questionId == question.id }
            let answers = answerIndices(for: questionAnswers).map { FeedbackAnswerExport(from: $0.0, answerIndex: $0.1) }
            for answer in answers {
                let row = [
                    answer.displayName,
                    answer.text,
                    answer.hasPhoto ? (answer.photoFileName ?? "") : "",
                    answer.timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                    String(answer.answerIndex)
                ]
                lines.append(row.map(csvField).joined(separator: ","))
            }

            lines.append("")
        }

        let csvString = lines.joined(separator: "\n")
        let fileName = "\(Constants.App.name)_Feedback_\(Date().feedbackExportFileName).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    /// Pairs each answer with its 0-based index among that member's answers to
    /// the same question, ordered by `modifiedAt ?? createdAt`.
    private func answerIndices(for answers: [SpaceAnswer]) -> [(SpaceAnswer, Int)] {
        let sorted = answers.sorted {
            ($0.modifiedAt ?? $0.createdAt ?? .distantPast) < ($1.modifiedAt ?? $1.createdAt ?? .distantPast)
        }
        var nextIndexByMember: [String: Int] = [:]
        var indexByAnswerId: [String: Int] = [:]
        for answer in sorted {
            let member = answer.authorRecordName ?? ""
            let index = nextIndexByMember[member, default: 0]
            indexByAnswerId[answer.id] = index
            nextIndexByMember[member] = index + 1
        }
        return answers.map { ($0, indexByAnswerId[$0.id] ?? 0) }
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - JSON

    private func exportJSON(_ input: Input) throws -> URL {
        let questions = input.reflection.questions.sorted { $0.order < $1.order }
        let questionExports = questions.map { question in
            let questionAnswers = input.answers.filter { $0.questionId == question.id }
            return FeedbackQuestionExport(
                id: question.id,
                text: question.text,
                order: question.order,
                answers: answerIndices(for: questionAnswers).map { FeedbackAnswerExport(from: $0.0, answerIndex: $0.1) }
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
    let answerIndex: Int

    init(from answer: SpaceAnswer, answerIndex: Int) {
        self.memberRecordName = answer.authorRecordName ?? ""
        self.displayName = answer.authorDisplayName ?? ""
        self.text = answer.text
        self.hasPhoto = answer.imageData != nil
        self.photoFileName = answer.imageData != nil ? "\(answer.id).jpg" : nil
        self.timestamp = answer.modifiedAt ?? answer.createdAt
        self.answerIndex = answerIndex
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
