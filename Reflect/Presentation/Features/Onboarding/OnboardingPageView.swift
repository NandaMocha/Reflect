import SwiftUI

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Constants.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.color.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: page.icon)
                    .font(.system(size: 70))
                    .foregroundColor(page.color)
            }

            VStack(spacing: Constants.Spacing.sm) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(Constants.Spacing.xl)
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
