import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: OnboardingViewModel?

    private let features: [OnboardingPage] = [
        OnboardingPage(
            icon: "book.closed.fill",
            title: "Capture Everything",
            subtitle: "Save learnings with voice, text, and images in seconds.",
            color: .primaryDefault
        ),
        OnboardingPage(
            icon: "folder.fill.badge.gearshape",
            title: "Organize Your Learnings",
            subtitle: "Create categories and find any insight instantly.",
            color: .success
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "Speak Your Thoughts",
            subtitle: "Dictate in Indonesian or English and get an instant transcript.",
            color: .warning
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Constants.Spacing.xl) {
                    heroSection
                    featureListSection
                    iCloudSection
                }
                .padding(.horizontal, Constants.Spacing.lg)
                .padding(.top, Constants.Spacing.xxl)
                .padding(.bottom, Constants.Spacing.lg)
            }
            ctaFooter
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

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: Constants.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.primaryDefault.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.primaryDefault)
            }
            VStack(spacing: Constants.Spacing.xs) {
                Text("Welcome to ReflectLearn")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Your personal learning companion")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feature List Section

    private var featureListSection: some View {
        VStack(spacing: 0) {
            ForEach(features) { page in
                FeatureRowView(page: page)
                if page.id != features.last?.id {
                    Divider()
                        .padding(.leading, 44 + Constants.Spacing.md)
                }
            }
        }
    }

    // MARK: - iCloud Section

    @ViewBuilder
    private var iCloudSection: some View {
        if viewModel?.isCheckingCloud == true {
            HStack(spacing: Constants.Spacing.md) {
                NativeLoadingSpinner()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    Text("Checking iCloud...")
                        .font(.body.weight(.semibold))
                    Text("Looking for your previous data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Constants.Spacing.sm)
        } else if let summary = viewModel?.cloudDataSummary {
            VStack(spacing: Constants.Spacing.md) {
                HStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primaryDefault)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Previous Data Found")
                            .font(.body.weight(.semibold))
                        Text("Restore your reflections from iCloud")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: Constants.Spacing.lg) {
                    OnboardingDataBadge(count: summary.learningsCount, label: "Learnings")
                    OnboardingDataBadge(count: summary.reflectionsCount, label: "Reflections")
                }
            }
            .padding(Constants.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
            )
        } else if let error = viewModel?.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - CTA Footer

    private var ctaFooter: some View {
        VStack(spacing: Constants.Spacing.sm) {
            if viewModel?.isCheckingCloud == false, viewModel?.cloudDataSummary != nil {
                PrimaryButton(
                    viewModel?.isRestoring == true ? "Restoring..." : "Restore from iCloud",
                    icon: "icloud.and.arrow.down",
                    isLoading: viewModel?.isRestoring == true,
                    isDisabled: viewModel?.isRestoring == true
                ) {
                    Task {
                        let success = await viewModel?.restoreFromCloud() ?? false
                        if success { completeOnboarding() }
                    }
                }
                Button("Start Fresh") {
                    completeOnboarding()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .disabled(viewModel?.isRestoring == true)
            } else {
                PrimaryButton(
                    "Get Started",
                    icon: "arrow.right",
                    isDisabled: viewModel?.isCheckingCloud == true
                ) {
                    completeOnboarding()
                }
            }
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.top, Constants.Spacing.md)
        .padding(.bottom, Constants.Spacing.xl)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        isPresented = false
        HapticManager.shared.success()
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
