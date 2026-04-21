import SwiftUI

struct MonthSelectorView: View {
    let currentMonth: Date
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Previous Month Button
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(hasPrevious ? .primary : .secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!hasPrevious)

            Spacer()

            // Current Month Label
            VStack(spacing: 4) {
                Text(monthYearString)
                    .font(.title3.bold())
                Text("Streak Badges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Next Month Button
            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(hasNext ? .primary : .secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(!hasNext)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
}

#Preview {
    VStack(spacing: 20) {
        MonthSelectorView(
            currentMonth: Date(),
            hasPrevious: true,
            hasNext: true,
            onPrevious: {},
            onNext: {}
        )

        MonthSelectorView(
            currentMonth: Date(),
            hasPrevious: false,
            hasNext: true,
            onPrevious: {},
            onNext: {}
        )

        MonthSelectorView(
            currentMonth: Date(),
            hasPrevious: true,
            hasNext: false,
            onPrevious: {},
            onNext: {}
        )
    }
    .padding()
}
