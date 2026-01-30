import Foundation

struct SearchFilters {
    var query: String = ""
    var learningId: UUID?
    var favoritesOnly: Bool = false
    var dateRange: DateRange?
    var sortOption: Constants.SortOption = .newestFirst
    var limit: Int = 50
    var offset: Int = 0

    struct DateRange {
        let startDate: Date
        let endDate: Date
    }

    var isEmpty: Bool {
        query.isEmpty &&
        learningId == nil &&
        !favoritesOnly &&
        dateRange == nil
    }

    mutating func reset() {
        query = ""
        learningId = nil
        favoritesOnly = false
        dateRange = nil
        sortOption = .newestFirst
        limit = 50
        offset = 0
    }
}
