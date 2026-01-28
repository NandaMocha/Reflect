import Foundation

struct SearchFilters {
    var query: String = ""
    var learningId: UUID?
    var hashtags: [String] = []
    var favoritesOnly: Bool = false
    var dateRange: DateRange?
    var sortOption: Constants.SortOption = .newestFirst

    struct DateRange {
        let startDate: Date
        let endDate: Date
    }

    var isEmpty: Bool {
        query.isEmpty &&
        learningId == nil &&
        hashtags.isEmpty &&
        !favoritesOnly &&
        dateRange == nil
    }

    mutating func reset() {
        query = ""
        learningId = nil
        hashtags = []
        favoritesOnly = false
        dateRange = nil
        sortOption = .newestFirst
    }
}
