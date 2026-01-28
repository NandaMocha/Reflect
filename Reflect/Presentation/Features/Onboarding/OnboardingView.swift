import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: OnboardingViewModel?

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "book.closed.fill",
            title: "Welcome to ReflectLearn",
            subtitle: "Capture your learning journey with voice, text, and images",
            color: .primaryDefault
        ),
        OnboardingPage(
            icon: "folder.fill.badge.gearshape",
            title: "Organize Your Learnings",
            subtitle: "Create categories, add hashtags, and find insights instantly",
            color: .success
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "Speak Your Thoughts",
            subtitle: "Record and transcribe in Indonesian or English",
            color: .warning
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page Content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }

                // Cloud check page
                iCloudCheckPage
                    .tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page Indicator
            HStack(spacing: 8) {
                ForEach(0..<(pages.count + 1), id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.primaryDefault : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.bottom, Constants.Spacing.lg)

            // Navigation Buttons
            navigationButtons
                .padding(.horizontal, Constants.Spacing.lg)
                .padding(.bottom, Constants.Spacing.xl)
        }
        .background(Color(.systemBackground))
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelContext: modelContext)
            }
        }
        .task {
            await viewModel?.checkForCloudData()
        }
    }

    // MARK: - iCloud Check Page

    private var iCloudCheckPage: some View {
        VStack(spacing: Constants.Spacing.xl) {
            Spacer()

            if viewModel?.isCheckingCloud == true {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Checking iCloud...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else if let summary = viewModel?.cloudDataSummary {
                // Found existing data
                Image(systemName: "icloud.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.primaryDefault)

                VStack(spacing: Constants.Spacing.xs) {
                    Text("We found existing data!")
                        .font(.title2.weight(.bold))

                    Text("Would you like to restore your reflections from iCloud?")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Data summary
                HStack(spacing: Constants.Spacing.lg) {
                    DataBadge(count: summary.learningsCount, label: "Learnings")
                    DataBadge(count: summary.reflectionsCount, label: "Reflections")
                }
                .padding(.top, Constants.Spacing.md)

            } else {
                // No existing data
                Image(systemName: "sparkles")
                    .font(.system(size: 80))
                    .foregroundColor(.primaryDefault)

                VStack(spacing: Constants.Spacing.xs) {
                    Text("You're All Set!")
                        .font(.title2.weight(.bold))

                    Text("Start capturing your first learning reflection")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding(Constants.Spacing.xl)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        Group {
            if currentPage < pages.count {
                // Standard pages
                HStack {
                    Button("Skip") {
                        skipToEnd()
                    }
                    .foregroundColor(.secondary)

                    Spacer()

                    PrimaryButton("Next", icon: "arrow.right") {
                        nextPage()
                    }
                    .frame(width: 120)
                }
            } else {
                // iCloud page
                if viewModel?.cloudDataSummary != nil {
                    VStack(spacing: Constants.Spacing.md) {
                        PrimaryButton("Yes, Restore Data", icon: "icloud.and.arrow.down") {
                            Task {
                                await viewModel?.restoreFromCloud()
                                completeOnboarding()
                            }
                        }

                        Button("Start Fresh") {
                            completeOnboarding()
                        }
                        .foregroundColor(.secondary)
                    }
                } else {
                    PrimaryButton("Get Started", icon: "arrow.right") {
                        completeOnboarding()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func nextPage() {
        withAnimation {
            currentPage += 1
        }
        HapticManager.shared.lightImpact()
    }

    private func skipToEnd() {
        withAnimation {
            currentPage = pages.count
        }
        HapticManager.shared.lightImpact()
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        isPresented = false
        HapticManager.shared.success()
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Constants.Spacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: page.icon)
                    .font(.system(size: 70))
                    .foregroundColor(page.color)
            }

            // Text
            VStack(spacing: Constants.Spacing.sm) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(Constants.Spacing.xl)
    }
}

// MARK: - Data Badge

struct DataBadge: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: Constants.Spacing.xxs) {
            Text("\(count)")
                .font(.title.weight(.bold).monospacedDigit())
                .foregroundColor(.primaryDefault)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(Constants.Spacing.md)
        .frame(minWidth: 100)
        .background(
            RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
