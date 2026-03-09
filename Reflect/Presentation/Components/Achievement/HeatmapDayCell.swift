import SwiftUI

struct HeatmapDayCell: View {
    let day: Int?
    let color: MonthHeatmapData.HeatmapColor
    let isToday: Bool

    var body: some View {
        ZStack {
            // Background color based on reflection count
            RoundedRectangle(cornerRadius: 2)
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            // Day number
            if let day = day {
                Text("\(day)")
                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? .white : textColor)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(borderColor, lineWidth: isToday ? 2 : 0)
        )
    }

    private var backgroundColor: Color {
        switch color {
        case .empty:
            return Color(red: 0.93, green: 0.93, blue: 0.93) // #EEEEEE
        case .light:
            return Color(red: 0.77, green: 0.89, blue: 0.54) // #C6E48B
        case .medium:
            return Color(red: 0.48, green: 0.79, blue: 0.43) // #7BC96F
        case .dark:
            return Color(red: 0.14, green: 0.60, blue: 0.23) // #239A3B
        }
    }

    private var textColor: Color {
        switch color {
        case .empty:
            return .secondary
        case .light, .medium, .dark:
            return .white
        }
    }

    private var borderColor: Color {
        isToday ? .blue : .clear
    }
}

#Preview {
    VStack(spacing: 8) {
        HStack(spacing: 4) {
            Text("Empty")
            HeatmapDayCell(day: 1, color: .empty, isToday: false)
        }

        HStack(spacing: 4) {
            Text("Light")
            HeatmapDayCell(day: 5, color: .light, isToday: false)
        }

        HStack(spacing: 4) {
            Text("Medium")
            HeatmapDayCell(day: 10, color: .medium, isToday: false)
        }

        HStack(spacing: 4) {
            Text("Dark")
            HeatmapDayCell(day: 15, color: .dark, isToday: false)
        }

        HStack(spacing: 4) {
            Text("Today")
            HeatmapDayCell(day: 9, color: .medium, isToday: true)
        }

        HStack(spacing: 4) {
            Text("No Day")
            HeatmapDayCell(day: nil, color: .empty, isToday: false)
        }
    }
    .padding()
}
