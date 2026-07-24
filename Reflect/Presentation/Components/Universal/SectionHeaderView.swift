import SwiftUI

// MARK: - Universal Section Header View

/// A reusable section header component with title and optional subtitle
struct SectionHeaderView<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 8
    var titleFont: Font = .title.weight(.bold)
    var subtitleFont: Font = .subheadline
    var accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 8,
        titleFont: Font = .title.weight(.bold),
        subtitleFont: Font = .subheadline,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.alignment = alignment
        self.spacing = spacing
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            if alignment == .leading {
                VStack(alignment: alignment, spacing: spacing) {
                    Text(title)
                        .font(titleFont)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(subtitleFont)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                accessory
            } else {
                VStack(alignment: alignment, spacing: spacing) {
                    Text(title)
                        .font(titleFont)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(subtitleFont)
                            .foregroundStyle(.secondary)
                    }
                }

                accessory
            }
        }
    }
}

// Convenience initializer without accessory
extension SectionHeaderView where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 8,
        titleFont: Font = .title.weight(.bold),
        subtitleFont: Font = .subheadline
    ) {
        self.title = title
        self.subtitle = subtitle
        self.alignment = alignment
        self.spacing = spacing
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.accessory = EmptyView()
    }
}

// MARK: - List Section Header

/// A section header styled for list sections
struct ListSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(iconColor ?? Color.primaryDefault)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Detail Section Header

/// A header for detail views with title and date
struct DetailSectionHeader: View {
    let title: String
    var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.title.weight(.bold))

                Spacer()
            }

            if let date = date {
                Text(date.formatted())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings Section Header

/// A header component for settings pages
struct SettingsSectionHeader: View {
    let title: String
    var icon: String? = nil
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color ?? Color.primaryDefault)
                    .frame(width: 28)
            }

            Text(title)
                .font(.headline)

            Spacer()
        }
    }
}

// MARK: - Collapsible Section Header

/// A section header that can collapse/expand content
struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(Color.primaryDefault)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle = subtitle, isExpanded {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Padded Section Header

/// A section header with standard padding
struct PaddedSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}

// MARK: - View Extensions

extension View {
    /// Wraps the view in a section header container
    func sectionHeader(
        title: String,
        subtitle: String? = nil,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            SectionHeaderView(title: title, subtitle: subtitle, alignment: alignment)

            self
        }
    }

    /// Adds a section divider below the view
    func sectionDivider() -> some View {
        VStack(spacing: 0) {
            self

            Divider()
                .opacity(0.3)
        }
    }
}

// MARK: - Section Container

/// A container that includes header and content with consistent styling
struct SectionContainer<Header: View, Content: View>: View {
    let spacing: CGFloat?
    let header: Header
    let content: Content

    init(spacing: CGFloat? = 16, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            content
        }
    }
}
