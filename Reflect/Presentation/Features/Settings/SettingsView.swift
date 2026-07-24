import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.UserDefaults.selectedTheme) private var selectedTheme: String = "system"
    @AppStorage(Constants.UserDefaults.defaultLanguage) private var defaultLanguage: String = "en-US"
#if DEBUG
    @AppStorage(Constants.UserDefaults.debugAlwaysShowOnboarding) private var debugAlwaysShowOnboarding: Bool = false
#endif

    @State var showClearDataAlert = false
    @State var showExportSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: CloudSyncView()) {
                        HStack {
                            Image(systemName: "icloud")
                                .foregroundStyle(Color.primaryDefault)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text("iCloud Sync")
                                Text("Backup and restore your data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Sync")
                }

//                Section {
//                    Picker("Theme", selection: $selectedTheme) {
//                        Text("System").tag("system")
//                        Text("Light").tag("light")
//                        Text("Dark").tag("dark")
//                    }
//                } header: {
//                    Text("Appearance")
//                }

//                Section {
//                    Picker("Default Voice Language", selection: $defaultLanguage) {
//                        Text("English").tag("en-US")
//                        Text("Indonesian").tag("id-ID")
//                    }
//                } header: {
//                    Text("Preferences")
//                }

                Section {
                    Button {
                        showExportSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.primaryDefault)
                                .frame(width: 28)
                            Text("Export Data")
                                .foregroundStyle(.primary)
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

#if DEBUG
                Section {
                    NavigationLink(destination: SpaceDebugView()) {
                        Text("🧪 Space Debug (spike)")
                    }

                    Toggle("🧪 Always show onboarding", isOn: $debugAlwaysShowOnboarding)
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Re-presents the welcome screen on every launch. Takes effect the next time you open the app.")
                }
#endif
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .deleteConfirmationAlert(
                itemName: "All Data",
                isPresented: $showClearDataAlert,
                additionalMessage: "This will permanently delete all your learnings, reflections, images, and voice notes. This action cannot be undone."
            ) {
                clearAllData()
            }
            .sheet(isPresented: $showExportSheet) {
                SettingsExportDataSheet()
            }
        }
    }

    func clearAllData() {
        do {
            try modelContext.delete(model: ImageAttachment.self)
            try modelContext.delete(model: VoiceRecording.self)
            try modelContext.delete(model: Reflection.self)
            try modelContext.delete(model: Learning.self)
            try modelContext.save()
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
