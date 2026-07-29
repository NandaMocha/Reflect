import SwiftUI

struct LearningCard: View {
    let learning: Learning
    /// Optional tap action. When `nil`, the card renders as pure content so a parent
    /// `NavigationLink` can own the tap target (avoids nesting a Button inside a link).
    var onTap: (() -> Void)?

    init(learning: Learning, onTap: (() -> Void)? = nil) {
        self.learning = learning
        self.onTap = onTap
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { cardContent }
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
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
        }
        .padding(Constants.Spacing.md)
        .glassCard()
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
