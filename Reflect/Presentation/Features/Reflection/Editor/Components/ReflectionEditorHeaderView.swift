import SwiftUI

struct ReflectionEditorHeaderView: View {
    let selectedLearning: Learning?
    let selectedDate: Date
    let learningsCount: Int
    let onSelectLearning: () -> Void
    let onSelectDate: () -> Void

    var body: some View {
        HStack {
            // Learning selector
            Button(action: onSelectLearning) {
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
                } else {
                    Text(learningsCount == 0 ? "Create learning..." : "Select learning...")
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
