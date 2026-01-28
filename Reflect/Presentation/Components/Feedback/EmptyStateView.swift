import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var buttonTitle: String?
    var buttonAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        subtitle: String,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    var body: some View {
        VStack(spacing: Constants.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: Constants.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                PrimaryButton(buttonTitle, icon: "plus", action: buttonAction)
                    .frame(maxWidth: 200)
            }
        }
        .padding(Constants.Spacing.xl)
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    static var noLearnings: EmptyStateView {
        EmptyStateView(
            icon: "book.closed",
            title: "No Learnings Yet",
            subtitle: "Tap + to add your first learning category",
            buttonTitle: "Add Learning"
        )
    }

    static var noReflections: EmptyStateView {
        EmptyStateView(
            icon: "text.book.closed",
            title: "Start Your Journey",
            subtitle: "Capture your first reflection to begin tracking your learning progress"
        )
    }

    static var noSearchResults: EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No Results Found",
            subtitle: "Try adjusting your search or filters"
        )
    }

    static var noFavorites: EmptyStateView {
        EmptyStateView(
            icon: "star",
            title: "No Favorites",
            subtitle: "Star your important reflections to find them easily"
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        EmptyStateView.noLearnings

        Divider()

        EmptyStateView.noSearchResults
    }
}
