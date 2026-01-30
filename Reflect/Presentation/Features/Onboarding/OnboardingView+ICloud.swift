import SwiftUI

// MARK: - iCloud Check Page Extension

extension OnboardingView {
    var iCloudCheckPage: some View {
        VStack(spacing: Constants.Spacing.xl) {
            Spacer()

            if viewModel?.isCheckingCloud == true {
                NativeLoadingSpinner()

                Text("Checking iCloud...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else if viewModel?.isRestoring == true {
                VStack(spacing: Constants.Spacing.md) {
                    NativeLoadingSpinner()

                    Text("Restoring Data...")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Please wait while we restore your reflections")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if let summary = viewModel?.cloudDataSummary {
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

                HStack(spacing: Constants.Spacing.lg) {
                    OnboardingDataBadge(count: summary.learningsCount, label: "Learnings")
                    OnboardingDataBadge(count: summary.reflectionsCount, label: "Reflections")
                }
                .padding(.top, Constants.Spacing.md)

            } else {
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
}
