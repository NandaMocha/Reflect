import SwiftUI

/// Insight list row. Reuses the shared `EntryCard` (same visual as `ReflectionCard`),
/// adding the insight type tag and a "Followed up" badge — bits that reflections omit.
struct InsightCard: View {
    let insight: Insight
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            EntryCard(
                tag: EntryCardTag(
                    label: insight.type.title,
                    icon: insight.type.icon,
                    colorHex: insight.type.colorHex
                ),
                bodyText: insight.preview,
                dateText: insight.createdAt.relativeFormatted,
                showFollowedUp: insight.hasFollowUp
            )
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
            insight: Insight(
                text: "SwiftData's @Model macro generates a lot of boilerplate under the hood.",
                type: .note,
                followUp: "Confirmed via -Xfrontend -dump-macro-expansions: it synthesizes the PersistentModel conformance."
            )
        ) {
            print("Tapped")
        }

        InsightCard(
            insight: Insight(text: "I keep reaching for force-unwraps when I'm tired — worth a habit check.", type: .reflection)
        ) {
            print("Tapped")
        }
    }
    .padding()
}
