import SwiftUI

struct InsightCard: View {
    let insight: Insight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                // Type Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: insight.type.colorHex).opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: insight.type.icon)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: insight.type.colorHex))
                }

                // Content
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    Text(insight.preview)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Text(insight.createdAt.relativeFormatted)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(Constants.Spacing.md)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 16) {
        InsightCard(
            insight: Insight(text: "What's the difference between actors and classes in Swift 6?", type: .question)
        ) {
            print("Tapped")
        }

        InsightCard(
            insight: Insight(text: "SwiftData's @Model macro generates a lot of boilerplate under the hood.", type: .note)
        ) {
            print("Tapped")
        }
    }
    .padding()
}
