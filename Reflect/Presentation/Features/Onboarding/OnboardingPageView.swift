import SwiftUI

struct FeatureRowView: View {
    let page: OnboardingPage

    var body: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                    .fill(page.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: page.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(page.color)
            }
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                Text(page.title)
                    .font(.body.weight(.semibold))
                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Constants.Spacing.sm)
    }
}

struct OnboardingDataBadge: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: Constants.Spacing.xxs) {
            Text("\(count)")
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundColor(.primaryDefault)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(Constants.Spacing.md)
        .frame(minWidth: 100)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(.ultraThinMaterial)
        )
    }
}
