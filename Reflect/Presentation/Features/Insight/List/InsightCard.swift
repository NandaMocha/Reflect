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

                    HStack(spacing: Constants.Spacing.xs) {
                        Text(insight.createdAt.relativeFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if insight.hasFollowUp {
                            followedUpBadge
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Constants.Spacing.md)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Followed-up Badge

    private var followedUpBadge: some View {
        Label("Followed up", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(hex: "628141"))
            .padding(.horizontal, Constants.Spacing.xs)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(hex: "628141").opacity(0.12))
            )
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
            insight: Insight(
                text: "SwiftData's @Model macro generates a lot of boilerplate under the hood.",
                type: .note,
                followUp: "Confirmed via -Xfrontend -dump-macro-expansions: it synthesizes the PersistentModel conformance."
            )
        ) {
            print("Tapped")
        }
    }
    .padding()
}
