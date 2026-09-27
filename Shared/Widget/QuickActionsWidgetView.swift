import SwiftUI
import WidgetKit

// MARK: - Widget View

/// Picks the layout for the current widget family. The two layouts are separate views so the
/// tests can render each one directly (a test can't set `widgetFamily`).
struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: QuickActionsEntry

    var body: some View {
        switch widgetFamily {
        case .systemMedium:
            MediumQuickActionsView(entry: entry)
        default:
            SmallQuickActionsView(entry: entry)
        }
    }
}

// MARK: - Small

/// Small widget: a labelled Write action on top, the other three actions as icons below.
/// At accessibility text sizes the labels go and the four actions become an icon grid.
struct SmallQuickActionsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: QuickActionsEntry

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            QuickActionGrid(showsLabels: false)
        } else {
            VStack(spacing: 8) {
                QuickActionLink(action: .write) {
                    HStack(spacing: 6) {
                        QuickActionIcon(action: .write)
                        QuickActionLabel(title: QuickAction.write.title, font: .headline)
                    }
                    .padding(.horizontal, 8)
                }

                HStack(spacing: 8) {
                    ForEach(QuickAction.all.dropFirst()) { action in
                        QuickActionLink(action: action) {
                            QuickActionIcon(action: action)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Medium

/// Medium widget: the four actions on the left, the day's quote on the right.
struct MediumQuickActionsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: QuickActionsEntry

    var body: some View {
        HStack(spacing: 12) {
            QuickActionGrid(showsLabels: !dynamicTypeSize.isAccessibilitySize)
                .frame(maxWidth: .infinity)
                .accessibilitySortPriority(1)

            DailyQuoteView(quote: entry.quote)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Building blocks

/// 2 x 2 grid of the four actions, filling the space it is given.
private struct QuickActionGrid: View {
    let showsLabels: Bool

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                tile(.write)
                tile(.photo)
            }
            GridRow {
                tile(.voice)
                tile(.insight)
            }
        }
    }

    private func tile(_ action: QuickAction) -> some View {
        QuickActionLink(action: action) {
            VStack(spacing: 2) {
                QuickActionIcon(action: action)
                if showsLabels {
                    QuickActionLabel(title: action.title, font: .caption2)
                }
            }
            .padding(4)
        }
    }
}

/// A deep link on a card-surface tile. VoiceOver reads the action's label and hint, not the
/// visible title or the SF Symbol name.
private struct QuickActionLink<Label: View>: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let action: QuickAction
    @ViewBuilder let label: Label

    var body: some View {
        Link(destination: action.url) {
            label
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tileBackground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(action.accessibilityHint)
        .accessibilityAddTraits(.isLink)
    }

    @ViewBuilder
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if renderingMode == .fullColor {
            shape.fill(WidgetPalette.cardSurface)
        } else {
            // Accented and vibrant modes flatten colours to luminance, so an opaque card
            // would turn into a solid block that hides the icon. A faint fill keeps the shape.
            shape.fill(.quaternary)
        }
    }
}

private struct QuickActionIcon: View {
    let action: QuickAction

    var body: some View {
        Image(systemName: action.systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(WidgetPalette.color(action.tint))
            // Icons stop growing at the largest non-accessibility size so four still fit.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

private struct QuickActionLabel: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let title: String
    let font: Font

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(renderingMode == .fullColor ? WidgetPalette.textPrimary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The day's quote, read by VoiceOver as one element after the actions.
private struct DailyQuoteView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.widgetRenderingMode) private var renderingMode
    let quote: DailyQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "quote.opening")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WidgetPalette.color(QuickAction.write.tint))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .widgetAccentable()
            }

            Text(quote.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(renderingMode == .fullColor ? WidgetPalette.textPrimary : Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 5)
                .minimumScaleFactor(0.4)

            if let author = quote.author {
                Text("— \(author)")
                    .font(.caption2)
                    .foregroundStyle(renderingMode == .fullColor ? WidgetPalette.textSecondary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    // The author gets its line first, so the quote is what shrinks.
                    .layoutPriority(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let author = quote.author {
            return "Daily quote: \(quote.text), by \(author)"
        }
        return "Daily quote: \(quote.text)"
    }
}
