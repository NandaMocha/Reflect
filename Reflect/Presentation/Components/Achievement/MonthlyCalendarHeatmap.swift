import SwiftUI

struct MonthlyCalendarHeatmap: View {
    @State private var viewModel: CalendarHeatmapViewModel
    let onMonthChange: ((Date) -> Void)?

    init(viewModel: CalendarHeatmapViewModel, onMonthChange: ((Date) -> Void)? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.onMonthChange = onMonthChange
    }

    var body: some View {
        VStack(spacing: 16) {
            if let heatmapData = viewModel.heatmapData {
                // Calendar Grid (no month header)
                calendarGrid(heatmapData: heatmapData)

                // Stats Row
                statsRow(heatmapData: heatmapData)

                // Legend
                legend
            } else if viewModel.isLoading {
                ProgressView("Loading calendar...")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .task {
            await viewModel.loadHeatmapData()
        }
        .onChange(of: viewModel.selectedMonth) { oldValue, newValue in
            onMonthChange?(newValue)
        }
    }

    // MARK: - Calendar Grid

    private func calendarGrid(heatmapData: MonthHeatmapData) -> some View {
        VStack(spacing: 8) {
            // Weekday Headers
            weekdayHeaders

            // Day Grid
            VStack(spacing: 4) {
                ForEach(heatmapData.weekGrid.indices, id: \.self) { weekIndex in
                    let week = heatmapData.weekGrid[weekIndex]
                    HStack(spacing: 4) {
                        ForEach(week.indices, id: \.self) { dayIndex in
                            let day = week[dayIndex]
                            if let day = day {
                                let color = heatmapData.colorForDay(day)
                                let isToday = viewModel.isToday(day)
                                HeatmapDayCell(day: day, color: color, isToday: isToday)
                            } else {
                                // Empty cell for padding
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.clear)
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                }
            }
        }
    }

    private var weekdayHeaders: some View {
        HStack(spacing: 4) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Stats Row

    private func statsRow(heatmapData: MonthHeatmapData) -> some View {
        HStack(spacing: 16) {
            // Longest Streak
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)

                Text("\(viewModel.longestStreakInMonth)")
                    .font(.headline)

                Text("Longest Streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 30)

            // Active Days
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.green)

                Text("\(viewModel.activeDaysInMonth)")
                    .font(.headline)

                Text("Active Days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 30)

            // Total
            VStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.blue)

                Text("\(viewModel.totalReflectionsInMonth)")
                    .font(.headline)

                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach([MonthHeatmapData.HeatmapColor.empty, .light, .medium, .dark], id: \.backgroundColor) { color in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForLegend(color))
                    .frame(width: 12, height: 12)
            }

            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Reflections per day")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func colorForLegend(_ color: MonthHeatmapData.HeatmapColor) -> Color {
        switch color {
        case .empty:
            return Color(red: 0.93, green: 0.93, blue: 0.93)
        case .light:
            return Color(red: 0.77, green: 0.89, blue: 0.54)
        case .medium:
            return Color(red: 0.48, green: 0.79, blue: 0.43)
        case .dark:
            return Color(red: 0.14, green: 0.60, blue: 0.23)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MonthlyCalendarHeatmap(
            viewModel: {
                let vm = CalendarHeatmapViewModel(
                    reflectionRepository: MockReflectionRepository()
                )
                vm.selectedMonth = Date()
                return vm
            }()
        )
    }
    .padding()
}

// MARK: - Mock for Preview

private struct MockReflectionRepository: ReflectionRepositoryProtocol {
    func fetchAll(limit: Int?, offset: Int?) async throws -> [Reflection] {
        return try await fetchAll()
    }

    func fetch(id: UUID) async throws -> Reflection? { nil }

    func fetchByLearning(_ learningId: UUID, limit: Int?, offset: Int?) async throws -> [Reflection] {
        return try await fetchByLearning(learningId)
    }

    func fetchByLearning(_ learningId: UUID) async throws -> [Reflection] { [] }

    func fetchFavorites(limit: Int?, offset: Int?) async throws -> [Reflection] {
        return try await fetchFavorites()
    }

    func fetchFavorites() async throws -> [Reflection] { [] }

    func search(query: String, limit: Int?, offset: Int?) async throws -> [Reflection] { [] }

    func fetchAll() async throws -> [Reflection] {
        // Return mock reflections for current month
        let calendar = Calendar.current
        let now = Date()
        var reflections: [Reflection] = []

        for day in 1...15 {
            let reflection = Reflection(
                title: "Mock Reflection \(day)",
                contentData: nil,
                plainTextContent: "Mock content for day \(day)",
                isFavorite: false,
                createdAt: calendar.date(byAdding: .day, value: -day, to: now) ?? Date()
            )
            reflection.submittedDate = calendar.date(byAdding: .day, value: -day, to: now)
            reflections.append(reflection)
        }

        return reflections
    }

    func create(_ reflection: Reflection) async throws {}
    func update(_ reflection: Reflection) async throws {}
    func delete(_ reflection: Reflection) async throws {}
    func toggleFavorite(_ reflection: Reflection) async throws {}
}
