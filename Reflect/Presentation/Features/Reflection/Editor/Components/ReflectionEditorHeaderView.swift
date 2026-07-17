import SwiftUI

/// Editor header — shows the reflection's learning (read-only; the user picked the learning
/// before entering the editor) and a tappable date pill.
struct ReflectionEditorHeaderView: View {
    let selectedLearning: Learning?
    let selectedDate: Date
    let onSelectDate: () -> Void

    var body: some View {
        HStack {
            if let learning = selectedLearning {
                HStack(spacing: Constants.Spacing.xs) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: learning.colorHex).opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: learning.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: learning.colorHex))
                    }

                    Text(learning.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Date selector
            Button(action: onSelectDate) {
                Text(formatDateShort(selectedDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d"
        return formatter.string(from: date)
    }
}
