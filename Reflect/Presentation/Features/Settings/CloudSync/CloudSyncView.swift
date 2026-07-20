import SwiftUI
import SwiftData

struct CloudSyncView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var learnings: [Learning]
    @Query private var reflections: [Reflection]

    @State private var viewModel: CloudSyncViewModel?
    @State private var showRestoreAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.xl) {
                // Cloud Status
                cloudStatusSection

                Divider()

                // Local Data
                localDataSection

                // Cloud Data
                if let cloudData = viewModel?.cloudDataSummary {
                    cloudDataSection(cloudData)
                }

                Divider()

                // Actions
                actionButtons

                // Warning
                warningSection
            }
            .padding(Constants.Spacing.lg)
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupViewModel()
        }
        .task {
            await viewModel?.checkCloudStatus()
        }
        .alert("Restore from iCloud?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task {
                    await viewModel?.restore()
                }
            }
        } message: {
            Text("This will replace all your local data with the data from iCloud. This action cannot be undone.")
        }
    }

    // MARK: - Cloud Status Section

    private var cloudStatusSection: some View {
        VStack(spacing: Constants.Spacing.md) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(statusColor)
            }

            // Status Text
            VStack(spacing: Constants.Spacing.xs) {
                Text(statusTitle)
                    .font(.headline)

                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Last Sync
            if let lastSync = viewModel?.lastSyncDate {
                Text("Last synced: \(lastSync.relativeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusIcon: String {
        switch viewModel?.cloudAvailability {
        case .available: return "icloud.fill"
        case .noAccount: return "icloud.slash"
        case .networkUnavailable: return "wifi.slash"
        default: return "icloud"
        }
    }

    private var statusColor: Color {
        switch viewModel?.cloudAvailability {
        case .available: return .success
        case .noAccount, .restricted: return .error
        case .networkUnavailable, .temporarilyUnavailable: return .warning
        default: return .secondary
        }
    }

    private var statusTitle: String {
        switch viewModel?.cloudAvailability {
        case .available: return "iCloud Connected"
        case .noAccount: return "Not Signed In"
        case .restricted: return "iCloud Restricted"
        case .networkUnavailable: return "No Network"
        case .temporarilyUnavailable: return "Temporarily Unavailable"
        default: return "Checking..."
        }
    }

    private var statusSubtitle: String {
        switch viewModel?.cloudAvailability {
        case .available: return "Your data can be synced to iCloud"
        case .noAccount: return "Sign in to iCloud in Settings to enable sync"
        case .restricted: return "iCloud access is restricted on this device"
        case .networkUnavailable: return "Check your internet connection"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        default: return "Checking iCloud status..."
        }
    }

    // MARK: - Local Data Section

    private var localDataSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Text("Local Data")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack {
                DataCountCard(
                    icon: "book.fill",
                    count: learnings.count,
                    label: "Learnings",
                    color: .primaryDefault
                )

                DataCountCard(
                    icon: "text.book.closed.fill",
                    count: reflections.count,
                    label: "Reflections",
                    color: .primaryDark
                )
            }

            HStack {
                DataCountCard(
                    icon: "photo.fill",
                    count: reflections.reduce(0) { $0 + $1.images.count },
                    label: "Images",
                    color: .info
                )

                DataCountCard(
                    icon: "mic.fill",
                    count: reflections.reduce(0) { $0 + $1.voiceRecordings.count },
                    label: "Voice Notes",
                    color: .warning
                )
            }
        }
    }

    // MARK: - Cloud Data Section

    private func cloudDataSection(_ data: CloudDataSummary) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            HStack {
                Text("iCloud Data")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let date = data.lastBackupDate {
                    Text(date.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                DataCountCard(
                    icon: "book.fill",
                    count: data.learningsCount,
                    label: "Learnings",
                    color: .primaryDefault.opacity(0.7)
                )

                DataCountCard(
                    icon: "text.book.closed.fill",
                    count: data.reflectionsCount,
                    label: "Reflections",
                    color: .primaryDark.opacity(0.7)
                )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Constants.Spacing.md) {
            // Backup Button
            PrimaryButton(
                viewModel?.isBackingUp == true ? "Backing Up..." : "Backup to iCloud",
                icon: "icloud.and.arrow.up"
            ) {
                Task {
                    await viewModel?.backup()
                }
            }
            .disabled(viewModel?.cloudAvailability != .available || viewModel?.isBackingUp == true)

            // Restore Button
            SecondaryButton(
                viewModel?.isRestoring == true ? "Restoring..." : "Restore from iCloud",
                icon: "icloud.and.arrow.down"
            ) {
                showRestoreAlert = true
            }
            .disabled(
                viewModel?.cloudAvailability != .available ||
                viewModel?.isRestoring == true ||
                viewModel?.cloudDataSummary == nil
            )

            // Progress
            if let progress = viewModel?.syncProgress, progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.top, Constants.Spacing.sm)
            }
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)

            Text("Restoring will replace all local data with iCloud data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Constants.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(Color.warning.opacity(0.1))
        )
    }

    // MARK: - Setup

    private func setupViewModel() {
        if viewModel == nil {
            viewModel = CloudSyncViewModel(modelContext: modelContext)
        }
    }
}

// MARK: - Data Count Card

struct DataCountCard: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Constants.Spacing.md)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

#Preview {
    NavigationStack {
        CloudSyncView()
    }
    .modelContainer(for: [Learning.self, Reflection.self], inMemory: true)
}
