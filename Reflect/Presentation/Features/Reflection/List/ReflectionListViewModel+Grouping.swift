import Foundation
import OSLog

// MARK: - Grouping Extension

extension ReflectionListViewModel {
    // Grouped on the main actor: `reflections` are live SwiftData models bound to the main
    // ModelContext and must not be read off-main (was a data race via Task.detached). The
    // bucketing is only a few ms, so there's nothing to offload.
    @MainActor
    func groupReflectionsByDate() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        groupedReflections = groupReflections(reflections)
        os_log("📅 [PERF] groupReflectionsByDate took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    @MainActor
    private func groupReflections(_ reflections: [Reflection]) -> [ReflectionDateGroup: [Reflection]] {
        let startTime = CFAbsoluteTimeGetCurrent()
        var groups: [ReflectionDateGroup: [Reflection]] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for reflection in reflections {
            let reflectionDate = calendar.startOfDay(for: reflection.createdAt)
            let group: ReflectionDateGroup

            if reflectionDate == today {
                group = .today
            } else if reflectionDate == calendar.date(byAdding: .day, value: -1, to: today) {
                group = .yesterday
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
                      reflectionDate > weekAgo {
                group = .thisWeek
            } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: today),
                      reflectionDate > monthAgo {
                group = .thisMonth
            } else {
                group = .older(reflectionDate)
            }

            groups[group, default: []].append(reflection)
        }

        os_log("📊 [PERF] Grouped %d reflections in %.3fms", log: .default, type: .info, reflections.count, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        return groups
    }

    var sortedDateGroups: [ReflectionDateGroup] {
        groupedReflections.keys.sorted()
    }
}
