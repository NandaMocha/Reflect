import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.UserDefaults.selectedTheme) private var selectedTheme: String = "system"
    @AppStorage(Constants.UserDefaults.defaultLanguage) private var defaultLanguage: String = "en-US"

    @State private var showClearDataAlert = false
    @State private var showExportSheet = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Sync Section
                Section {
                    NavigationLink(destination: CloudSyncView()) {
                        HStack {
                            Image(systemName: "icloud")
                                .foregroundColor(.primaryDefault)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text("iCloud Sync")
                                Text("Backup and restore your data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sync")
                }

                // MARK: - Appearance Section
                Section {
                    Picker("Theme", selection: $selectedTheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                } header: {
                    Text("Appearance")
                }

                // MARK: - Preferences Section
                Section {
                    Picker("Default Voice Language", selection: $defaultLanguage) {
                        Text("English").tag("en-US")
                        Text("Indonesian").tag("id-ID")
                    }
                } header: {
                    Text("Preferences")
                }

                // MARK: - Data Section
                Section {
                    Button {
                        showExportSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.primaryDefault)
                                .frame(width: 28)
                            Text("Export Data")
                                .foregroundColor(.primary)
                        }
                    }

                    Button(role: .destructive) {
                        showClearDataAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .frame(width: 28)
                            Text("Clear All Data")
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Clearing data will permanently delete all learnings, reflections, and attachments.")
                }

                // MARK: - About Section
                Section {
                    NavigationLink(destination: AboutView()) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.primaryDefault)
                                .frame(width: 28)
                            Text("About ReflectLearn")
                        }
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.primaryDefault)
                                .frame(width: 28)
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.primaryDefault)
                                .frame(width: 28)
                            Text("Terms of Service")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(spacing: 4) {
                        Text("ReflectLearn v\(Bundle.main.appVersion)")
                        Text("Build \(Bundle.main.buildNumber)")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Constants.Spacing.lg)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will permanently delete all your learnings, reflections, images, and voice notes. This action cannot be undone.")
            }
            .sheet(isPresented: $showExportSheet) {
                ExportDataSheet()
            }
        }
    }

    private func clearAllData() {
        do {
            try modelContext.delete(model: ImageAttachment.self)
            try modelContext.delete(model: VoiceRecording.self)
            try modelContext.delete(model: Hashtag.self)
            try modelContext.delete(model: Reflection.self)
            try modelContext.delete(model: Learning.self)
            try modelContext.save()
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                // App Icon
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primaryDefault)
                    .padding(.top, Constants.Spacing.xl)

                // App Name
                VStack(spacing: Constants.Spacing.xs) {
                    Text("ReflectLearn")
                        .font(.largeTitle.weight(.bold))

                    Text("Capture your learning journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Features
                VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                    FeatureRow(icon: "lightbulb.fill", title: "Organize Learnings", description: "Create categories with custom icons and colors")
                    FeatureRow(icon: "text.book.closed.fill", title: "Rich Reflections", description: "Capture thoughts with text, images, and voice")
                    FeatureRow(icon: "mic.fill", title: "Voice Transcription", description: "Speak in English or Indonesian")
                    FeatureRow(icon: "icloud.fill", title: "iCloud Backup", description: "Keep your data safe in the cloud")
                }
                .padding(.horizontal, Constants.Spacing.lg)

                Spacer()
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureRow: View {
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

// MARK: - Export Data Sheet

struct ExportDataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Constants.Spacing.lg) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.primaryDefault)

                VStack(spacing: Constants.Spacing.xs) {
                    Text("Export Your Data")
                        .font(.title2.weight(.bold))

                    Text("Export all your learnings and reflections as a JSON file that you can backup or share.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                        .padding()
                } else {
                    PrimaryButton("Export Data", icon: "arrow.down.doc") {
                        Task {
                            await exportData()
                        }
                    }
                }
            }
            .padding(Constants.Spacing.lg)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    @MainActor
    private func exportData() async {
        isExporting = true

        // Export logic would go here
        // For now, just simulate
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        isExporting = false
        HapticManager.shared.success()

        // Show share sheet with exported file
        showShareSheet = true
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
