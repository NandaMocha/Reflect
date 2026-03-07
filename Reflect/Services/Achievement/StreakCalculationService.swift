import Foundation

final class StreakCalculationService {
    func calculateCurrentStreak(reflections: [Reflection]) -> Int {
        let streakSubmissions = reflections
            .filter { $0.isStreakSubmission }
            .sorted { ($0.submittedDate ?? Date()) > ($1.submittedDate ?? Date()) }

        var streak = 0
        var checkDate = Calendar.current.startOfDay(for: .now)

        for reflection in streakSubmissions {
            guard let reflectionDay = reflection.submittedDate else { continue }
            let reflectionStartOfDay = Calendar.current.startOfDay(for: reflectionDay)

            // Check if dates match (same day)
            if checkDate == reflectionStartOfDay {
                streak += 1
                checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            }
            // Check if one day gap (consecutive)
            else if Calendar.current.dateComponents([.day], from: reflectionStartOfDay, to: checkDate).day == 1 {
                streak += 1
                checkDate = reflectionStartOfDay
            }
            // Gap > 1 day, streak is broken
            else {
                break
            }
        }

        return streak
    }
}
