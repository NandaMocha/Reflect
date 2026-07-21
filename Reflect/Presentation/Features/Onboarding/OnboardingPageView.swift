import SwiftUI

/// One page of the onboarding pager. Scrollable so the longest page still fits on the
/// smallest supported screen without the fixed footer eating its content.
struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                heroIcon

                VStack(spacing: Constants.Spacing.sm) {
                    Text(page.title)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(page.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    ForEach(page.highlights) { highlight in
                        OnboardingHighlightRow(highlight: highlight, color: page.color)
                    }
                }
            }
            .padding(.horizontal, Constants.Spacing.lg)
            .padding(.top, Constants.Spacing.xxl)
            .padding(.bottom, Constants.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(page.color.opacity(0.12))
                .frame(width: 120, height: 120)
            Image(systemName: page.icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(page.color)
        }
        .accessibilityHidden(true)
    }
}

/// A single highlight line: tinted glyph in a soft square, then the copy.
struct OnboardingHighlightRow: View {
    let highlight: OnboardingHighlight
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: highlight.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)

            Text(highlight.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Nudge the copy onto the glyph's optical centre line.
                .padding(.top, 8)
        }
    }
}

/// The pager's position indicator. Hand-rolled rather than `PageTabViewStyle`'s built-in
/// dots so it can sit in the fixed footer above the CTA and use the app's colour tokens.
struct OnboardingPageIndicator: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: Constants.Spacing.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.primaryDefault : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
    }
}

struct OnboardingDataBadge: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: Constants.Spacing.xxs) {
            Text("\(count)")
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.primaryDefault)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Constants.Spacing.md)
        .frame(minWidth: 100)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    OnboardingPageView(page: OnboardingPage.all[3])
}
