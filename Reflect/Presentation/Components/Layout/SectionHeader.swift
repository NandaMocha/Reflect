import SwiftUI

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionLabel: String?

    init(
        _ title: String,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil
    ) {
        self.title = title
        self.action = action
        self.actionLabel = actionLabel
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primaryDefault)
                }
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, Constants.Spacing.xs)
    }
}

// MARK: - Date Section Header

struct DateSectionHeader: View {
    let date: Date

    var body: some View {
        HStack {
            Text(date.relativeFormatted)
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, Constants.Spacing.xs)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        SectionHeader("Recent")

        SectionHeader("Learnings", action: {
            print("See all")
        }, actionLabel: "See All")

        DateSectionHeader(date: Date())
    }
}
