import Foundation

extension Date {
    // MARK: - Relative Formatting

    var relativeFormatted: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else if calendar.isDate(self, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        } else if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
                  calendar.isDate(self, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return "Last Week"
        } else if calendar.isDate(self, equalTo: now, toGranularity: .month) {
            return "This Month"
        } else if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
                  calendar.isDate(self, equalTo: lastMonth, toGranularity: .month) {
            return "Last Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: self)
        }
    }

    // MARK: - Standard Formats

    var shortFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var mediumFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var longFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var dateTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    // MARK: - Grouping Key

    var groupingKey: String {
        relativeFormatted
    }

    // MARK: - Comparison Helpers

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var isThisWeek: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .weekOfYear)
    }

    var isThisMonth: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .month)
    }

    var isThisYear: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
    }

    var monthYearFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: self)
    }
}

// MARK: - TimeInterval Formatting

extension TimeInterval {
    var durationFormatted: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var longDurationFormatted: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
