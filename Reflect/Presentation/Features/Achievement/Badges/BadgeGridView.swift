import SwiftUI
import SwiftData

struct BadgeGridView: View {
    @State private var viewModel: BadgeGridViewModel
    var onBadgeTap: ((Badge) -> Void)?

    init(viewModel: BadgeGridViewModel, onBadgeTap: ((Badge) -> Void)? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.onBadgeTap = onBadgeTap
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    ProgressView("Loading badges...")
                } else if viewModel.badges.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .padding()
        }
        .task {
            await viewModel.loadBadges()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 24) {
            // Progress Header
            progressHeader

            // Newly Unlocked Section (if any)
            if viewModel.hasNewUnlocks {
                newlyUnlockedSection
            }

            // Unlocked Badges
            if !viewModel.unlockedBadges.isEmpty {
                unlockedSection
            }

            // Locked Badges
            if !viewModel.lockedBadges.isEmpty {
                lockedSection
            }
        }
    }

    // MARK: - Sections

    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text("Your Badges")
                .font(.title2.bold())

            // Progress bar
            VStack(spacing: 4) {
                HStack {
                    Text("\(viewModel.totalUnlocked) of \(viewModel.totalBadges)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue)
                            .frame(width: geometry.size.width * viewModel.progress, height: 8)
                            .animation(.easeInOut, value: viewModel.progress)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private var newlyUnlockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)

                Text("Recently Unlocked")
                    .font(.headline)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(viewModel.newlyUnlockedBadges) { badge in
                    BadgeCard(badge: badge) {
                        onBadgeTap?(badge)
                    }
                }
            }
        }
    }

    private var unlockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earned")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(viewModel.unlockedBadges.filter { !$0.isNew }) { badge in
                    BadgeCard(badge: badge) {
                        onBadgeTap?(badge)
                    }
                }
            }
        }
    }

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Locked")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(viewModel.lockedBadges) { badge in
                    BadgeCard(badge: badge) {
                        onBadgeTap?(badge)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Badges Yet")
                .font(.headline)

            Text("Start reflecting to earn your first badge!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Preview

#Preview {
    Text("Badge Grid Preview")
}
