import Foundation
import SwiftUI

@Observable
final class MainTabViewModel {
    var showOnboarding: Bool = false

    private let cloudSyncService: CloudSyncServiceProtocol

    init(cloudSyncService: CloudSyncServiceProtocol) {
        self.cloudSyncService = cloudSyncService
        checkOnboardingStatus()
    }

    func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasCompletedOnboarding)
        showOnboarding = !hasCompletedOnboarding
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        showOnboarding = false
    }
}
