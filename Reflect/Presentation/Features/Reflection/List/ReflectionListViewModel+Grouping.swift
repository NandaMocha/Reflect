import Foundation

// MARK: - Grouping Extension

extension ReflectionListViewModel {
    func groupReflectionsByDate() async {
        // Perform date grouping on background thread to avoid blocking UI
        let grouped = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [:] }
            return self.groupReflections(self.reflections)
        }.value

        await MainActor.run {
            self.groupedReflections = grouped
        }
    }

    private func groupReflections(_ reflections: [Reflection]) -> [ReflectionDateGroup: [Reflection]] {
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

        return groups
    }

    var sortedDateGroups: [ReflectionDateGroup] {
        groupedReflections.keys.sorted()
    }
}
