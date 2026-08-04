import Foundation

struct SpaceQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var text: String
    var order: Int

    static func encodeJSON(_ questions: [SpaceQuestion]) -> String {
        guard let data = try? JSONEncoder().encode(questions),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decodeJSON(_ json: String) -> [SpaceQuestion] {
        guard let data = json.data(using: .utf8),
              let questions = try? JSONDecoder().decode([SpaceQuestion].self, from: data) else {
            return []
        }
        return questions.sorted { $0.order < $1.order }
    }

    static func validate(_ questions: [SpaceQuestion]) throws {
        guard !questions.isEmpty else { throw SpaceError.emptyQuestionText }
        guard questions.count <= Constants.Limits.spaceMaxQuestions else { throw SpaceError.tooManyQuestions }
        for question in questions {
            let trimmed = question.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw SpaceError.emptyQuestionText }
            guard trimmed.count <= Constants.Limits.spaceQuestionTextMaxLength else { throw SpaceError.questionTextTooLong }
        }
    }
}
