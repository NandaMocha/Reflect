import SwiftUI

/// First-run walkthrough: a swipeable pager introducing Reflect and its three pillars —
/// Learnings, Insights, Spaces.
///
/// Two deliberate constraints:
/// - Paging is **swipe-only** — there is no Next button. The **Get Started** button only
///   appears on the last page, so the walkthrough is read rather than skipped. Its slot is
///   height-reserved on every page so the dots never shift as you page through.
/// - The sheet is **not** interactively dismissable (`interactiveDismissDisabled`). Leaving
///   is only possible through the CTA, which is what marks onboarding complete — a
///   swipe-away would otherwise re-present it on the next launch.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: OnboardingViewModel?
    @State private var currentPage: Int = 0

    private let pages = OnboardingPage.all

    /// Matches `PrimaryButton`'s rendered height, so the empty slot on earlier pages
    /// reserves exactly what the button will occupy on the last one.
    private let ctaSlotHeight: CGFloat = 50

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            // Dots are drawn in the footer instead, so the built-in ones are suppressed.
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
        .onAppear {
            if viewModel == nil {
                viewModel = OnboardingViewModel(modelContext: modelContext)
            }
        }
        .task {
            await viewModel?.checkForCloudData()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Constants.Spacing.md) {
            // Restore is only offered at the end — surfacing it mid-walkthrough would
            // compete with the pages for attention.
            if isLastPage {
                iCloudSection
            }

            OnboardingPageIndicator(pageCount: pages.count, currentPage: currentPage)

            callToAction
                // Reserve the CTA's height on every page so the dots don't shift when the
                // button fades in on the last one.
                .frame(minHeight: ctaSlotHeight)
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.top, Constants.Spacing.md)
        .padding(.bottom, Constants.Spacing.xl)
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.25), value: isLastPage)
    }

    @ViewBuilder
    private var callToAction: some View {
        if !isLastPage {
            // Intentionally empty: paging is swipe-only. The height is explicit rather
            // than `minHeight` — an unbounded `Color.clear` is greedy and would grow the
            // footer until it squeezed the pager off the screen.
            Color.clear.frame(height: ctaSlotHeight)
        } else if viewModel?.cloudDataSummary != nil {
            // Previous data found: restoring is the primary action, starting clean the
            // secondary one. Both complete onboarding.
            VStack(spacing: Constants.Spacing.sm) {
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
                .foregroundStyle(.secondary)
                .disabled(viewModel?.isRestoring == true)
            }
            .transition(.opacity)
        } else {
            PrimaryButton(
                "Get Started",
                icon: "arrow.right",
                isDisabled: viewModel?.isCheckingCloud == true
            ) {
                completeOnboarding()
            }
            .transition(.opacity)
        }
    }

    // MARK: - iCloud Section

    @ViewBuilder
    private var iCloudSection: some View {
        if viewModel?.isCheckingCloud == true {
            HStack(spacing: Constants.Spacing.sm) {
                NativeLoadingSpinner()
                    .frame(width: 24, height: 24)
                Text("Checking iCloud for your previous data…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        } else if let summary = viewModel?.cloudDataSummary {
            VStack(spacing: Constants.Spacing.sm) {
                HStack(spacing: Constants.Spacing.sm) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.primaryDefault)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Previous Data Found")
                            .font(.body.weight(.semibold))
                        Text("Restore your reflections from iCloud")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
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
