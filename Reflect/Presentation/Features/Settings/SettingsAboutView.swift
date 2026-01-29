import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primaryDefault)
                    .padding(.top, Constants.Spacing.xl)

                VStack(spacing: Constants.Spacing.xs) {
                    Text("ReflectLearn")
                        .font(.largeTitle.weight(.bold))

                    Text("Capture your learning journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    SettingsFeatureRow(icon: "lightbulb.fill", title: "Organize Learnings", description: "Create categories with custom icons and colors")
                    SettingsFeatureRow(icon: "text.book.closed.fill", title: "Rich Reflections", description: "Capture thoughts with text, images, and voice")
                    SettingsFeatureRow(icon: "mic.fill", title: "Voice Transcription", description: "Speak in English or Indonesian")
                    SettingsFeatureRow(icon: "icloud.fill", title: "iCloud Backup", description: "Keep your data safe in the cloud")
                }
                .padding(.horizontal, Constants.Spacing.lg)

                Spacer()
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundColor(.primaryDefault)
                .frame(width: 44, height: 44)
                .background(Color.primaryDefault.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
