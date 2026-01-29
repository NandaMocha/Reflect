import SwiftUI

// MARK: - Navigation Buttons Extension

extension OnboardingView {
    var navigationButtons: some View {
        Group {
            if currentPage < pages.count {
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

    func nextPage() {
        withAnimation {
            currentPage += 1
        }
        HapticManager.shared.lightImpact()
    }

    func skipToEnd() {
        withAnimation {
            currentPage = pages.count
        }
        HapticManager.shared.lightImpact()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        isPresented = false
        HapticManager.shared.success()
    }
}
