import SwiftUI

struct LearningCard: View {
    let learning: Learning
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Constants.Spacing.sm) {
                // Icon Container
                ZStack {
                    RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                        .fill(Color(hex: learning.colorHex).opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: learning.iconName)
                        .font(.title3)
                        .foregroundStyle(Color(hex: learning.colorHex))
                }

                // Content
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    Text(learning.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(learning.reflectionCount) reflections")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                
                // Chevron
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(Constants.Spacing.md)
            .glassCard()
        }
    }
}

#Preview {
    let learning = Learning(
        title: "Swift Programming",
        descriptionText: "Learning Swift basics",
        colorHex: "3AAFA9",
        iconName: "swift"
    )

    LearningCard(learning: learning) {
        print("Tapped")
    }
    .padding()
}
