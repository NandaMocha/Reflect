import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Constants.UserDefaults.selectedTheme) private var selectedTheme: String = "system"
    @AppStorage(Constants.UserDefaults.defaultLanguage) private var defaultLanguage: String = "en-US"

    @State var showClearDataAlert = false
    @State var showExportSheet = false

    var body: some View {
        NavigationStack {
            List {
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

//                Section {
//                    NavigationLink(destination: SettingsAboutView()) {
//                        HStack {
//                            Image(systemName: "info.circle")
//                                .foregroundColor(.primaryDefault)
//                                .frame(width: 28)
//                            Text("About ReflectLearn")
//                        }
//                    }
//
//                    Link(destination: URL(string: "https://example.com/privacy")!) {
//                        HStack {
//                            Image(systemName: "hand.raised")
//                                .foregroundColor(.primaryDefault)
//                                .frame(width: 28)
//                            Text("Privacy Policy")
//                                .foregroundColor(.primary)
//                            Spacer()
//                            Image(systemName: "arrow.up.right")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    }
//
//                    Link(destination: URL(string: "https://example.com/terms")!) {
//                        HStack {
//                            Image(systemName: "doc.text")
//                                .foregroundColor(.primaryDefault)
//                                .frame(width: 28)
//                            Text("Terms of Service")
//                                .foregroundColor(.primary)
//                            Spacer()
//                            Image(systemName: "arrow.up.right")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                } header: {
//                    Text("About")
//                } footer: {
//                    VStack(spacing: 4) {
//                        Text("ReflectLearn v\(Bundle.main.appVersion)")
//                        Text("Build \(Bundle.main.buildNumber)")
//                    }
//                    .font(.caption)
//                    .frame(maxWidth: .infinity)
//                    .padding(.top, Constants.Spacing.lg)
//                }

#if DEBUG
                Section {
                    NavigationLink(destination: SpaceDebugView()) {
                        Text("🧪 Space Debug (spike)")
                    }
                } header: {
                    Text("Debug")
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
