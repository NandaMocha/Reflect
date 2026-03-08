import Foundation
import SwiftData
import Observation

@Observable
final class CalendarHeatmapViewModel {
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let calendar = Calendar.current

    var heatmapData: MonthHeatmapData?
    var isLoading: Bool = false
    var errorMessage: String?

    var selectedMonth: Date = Date() {
        didSet {
            Task {
                await loadHeatmapData()
            }
        }
    }

    init(modelContext: ModelContext) {
        // Use DIContainer pattern - assume ReflectionRepository is available
        // For now, we'll create it directly
        self.reflectionRepository = ReflectionRepository(modelContext: modelContext)
    }

    init(reflectionRepository: ReflectionRepositoryProtocol) {
        self.reflectionRepository = reflectionRepository
    }

    // MARK: - Data Loading

    func loadHeatmapData() async {
        isLoading = true
        errorMessage = nil

        do {
            let components = calendar.dateComponents([.month, .year], from: selectedMonth)
            guard let month = components.month, let year = components.year else {
                errorMessage = "Invalid month"
                isLoading = false
                return
            }

            // Fetch reflections for the selected month
            let reflections = try await fetchReflectionsForMonth(month: month, year: year)

            // Count reflections per day
            var reflectionCountByDay: [Int: Int] = [:]
            for reflection in reflections {
                guard let submittedDate = reflection.submittedDate else { continue }
                let day = calendar.component(.day, from: submittedDate)
                reflectionCountByDay[day, default: 0] += 1
            }

            // Create MonthHeatmapData
            heatmapData = MonthHeatmapData(
                year: year,
                month: month,
                reflectionCountByDay: reflectionCountByDay
            )

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshData() async {
        await loadHeatmapData()
    }

    // MARK: - Helpers

    private func fetchReflectionsForMonth(month: Int, year: Int) async throws -> [Reflection] {
        // Create date range for the month
        let startDateComponents = DateComponents(year: year, month: month, day: 1)
        guard let startDate = calendar.date(from: startDateComponents) else {
            return []
        }

        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let endDateComponents = DateComponents(year: endYear, month: endMonth, day: 1)
        guard let endDate = calendar.date(from: endDateComponents) else {
            return []
        }

        // Fetch all reflections (filter in memory since we need submittedDate)
        // TODO: Optimize with database query if performance issues
        let allReflections = try await reflectionRepository.fetchAll()

        // Filter by submittedDate in the selected month
        return allReflections.filter { reflection in
            guard let submittedDate = reflection.submittedDate else { return false }
            return submittedDate >= startDate && submittedDate < endDate
        }
    }

    var selectedMonthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedMonth)
    }

    var isToday: (Int) -> Bool {
        { [self] day in
            let today = calendar.startOfDay(for: Date())
            let components = calendar.dateComponents([.month, .year], from: selectedMonth)
            guard let month = components.month, let year = components.year else { return false }

            let todayComponents = calendar.dateComponents([.day, .month, .year], from: today)
            guard let todayDay = todayComponents.day,
                  let todayMonth = todayComponents.month,
                  let todayYear = todayComponents.year else { return false }

            return day == todayDay && month == todayMonth && year == todayYear
        }
    }

    var totalReflectionsInMonth: Int {
        heatmapData?.reflectionCountByDay.values.reduce(0, +) ?? 0
    }

    var activeDaysInMonth: Int {
        heatmapData?.reflectionCountByDay.count ?? 0
    }

    var longestStreakInMonth: Int {
        // Calculate longest consecutive day streak in the month
        guard let heatmapData = heatmapData else { return 0 }

        let sortedDays = heatmapData.reflectionCountByDay.keys.sorted()
        var currentStreak = 0
        var longestStreak = 0
        var previousDay = 0

        for day in sortedDays {
            if day == previousDay + 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
            longestStreak = max(longestStreak, currentStreak)
            previousDay = day
        }

        return longestStreak
    }
}
