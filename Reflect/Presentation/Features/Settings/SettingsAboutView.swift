import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.primaryDefault)
                    .padding(.top, Constants.Spacing.xl)

                VStack(spacing: Constants.Spacing.xs) {
                    Text(Constants.App.name)
                        .font(.largeTitle.weight(.bold))

                    Text("Capture your learning journey")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    SettingsFeatureRow(icon: "lightbulb.fill", title: "Organize Learnings", description: "Create categories with custom icons and colors")
                    SettingsFeatureRow(icon: "text.book.closed.fill", title: "Rich Reflections", description: "Capture thoughts with text, images, and voice")
                    SettingsFeatureRow(icon: "mic.fill", title: "Voice Transcription", description: "Speak in English or Indonesian")
                    SettingsFeatureRow(icon: "icloud.fill", title: "iCloud Backup", description: "Keep your data safe in the cloud")
                }
                .padding(.horizontal, Constants.Spacing.lg)

                VStack(spacing: 0) {
                    SettingsLegalLinkRow(icon: "hand.raised.fill", title: "Privacy Policy") {
                        SettingsPrivacyPolicyView()
                    }
                    .accessibilityIdentifier("about.privacyPolicy")

                    Divider()
                        .padding(.leading, Constants.Spacing.md)

                    SettingsLegalLinkRow(icon: "doc.text.fill", title: "Terms of Use") {
                        SettingsTermsOfUseView()
                    }
                    .accessibilityIdentifier("about.termsOfUse")
                }
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
                .padding(.horizontal, Constants.Spacing.lg)

                Spacer()
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsLegalLinkRow<Destination: View>: View {
    let icon: String
    let title: LocalizedStringKey
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Constants.Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(Color.primaryDefault)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Constants.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Scrollable layout shared by the Privacy Policy and Terms of Use screens.
struct SettingsLegalDocumentView<Content: View>: View {
    let title: LocalizedStringKey
    let lastUpdated: LocalizedStringKey
    let accessibilityID: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.lg) {
                Text(lastUpdated)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Constants.Spacing.lg)
        }
        .accessibilityIdentifier(accessibilityID)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsLegalSection: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Constants.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.primaryDefault)
                .frame(width: 44, height: 44)
                .background(Color.primaryDefault.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
