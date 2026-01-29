import SwiftUI
import SwiftData

struct SettingsExportDataSheet: View {
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
                    ReflectionShareSheet(items: [url])
                }
            }
        }
    }

    @MainActor
    private func exportData() async {
        isExporting = true

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        isExporting = false
        HapticManager.shared.success()

        showShareSheet = true
    }
}
