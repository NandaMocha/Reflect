import Foundation

struct MonthHeatmapData {
    let year: Int
    let month: Int
    let reflectionCountByDay: [Int: Int]  // day -> count

    // MARK: - Computed Properties

    var displayMonth: String {
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let date = Calendar.current.date(from: dateComponents) else {
            return "\(month)/\(year)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    var daysInMonth: Int {
        let dateComponents = DateComponents(year: year, month: month)
        guard let date = Calendar.current.date(from: dateComponents),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }

    var weekGrid: [[Int?]] {
        let firstDay = DateComponents(year: year, month: month, day: 1)
        guard let firstDate = Calendar.current.date(from: firstDay) else {
            return []
        }

        let firstWeekday = Calendar.current.component(.weekday, from: firstDate) - 1
        let totalDays = daysInMonth

        var grid: [[Int?]] = []
        var week: [Int?] = Array(repeating: nil, count: firstWeekday)

        for day in 1...totalDays {
            week.append(day)
            if week.count == 7 {
                grid.append(week)
                week = []
            }
        }

        if !week.isEmpty {
            while week.count < 7 {
                week.append(nil)
            }
            grid.append(week)
        }

        return grid
    }

    func colorForDay(_ day: Int) -> HeatmapColor {
        let count = reflectionCountByDay[day] ?? 0
        switch count {
        case 0:
            return .empty
        case 1:
            return .light
        case 2...3:
            return .medium
        default:
            return .dark
        }
    }

    enum HeatmapColor {
        case empty      // Gray
        case light      // Light green
        case medium     // Medium green
        case dark       // Dark green

        var backgroundColor: String {
            switch self {
            case .empty: return "#EEEEEE"
            case .light: return "#C6E48B"
            case .medium: return "#7BC96F"
            case .dark: return "#239A3B"
            }
        }
    }
}
