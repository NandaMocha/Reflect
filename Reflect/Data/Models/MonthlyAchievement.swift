import Foundation
import SwiftData

@Model
final class MonthlyAchievement {
    @Attribute(.unique) var id: String  // Format: "YYYY-MM"

    var year: Int
    var month: Int  // 1-12

    var reflectionCount: Int = 0
    var hasFullMonth: Bool = false      // 30+
    var hasHalfMonth: Bool = false      // 14+
    var hasAnyReflection: Bool = false  // 1+
    var hasFirstDayReflection: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(year: Int, month: Int) {
        self.id = String(format: "%04d-%02d", year, month)
        self.year = year
        self.month = month
    }

    // MARK: - Computed Properties

    var yearMonthString: String {
        String(format: "%04d-%02d", year, month)
    }

    var displayName: String {
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: dateComponents) else {
            return yearMonthString
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var progressToFullMonth: Double {
        min(Double(reflectionCount) / 30.0, 1.0)
    }

    var progressToHalfMonth: Double {
        min(Double(reflectionCount) / 14.0, 1.0)
    }
}
