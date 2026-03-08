import Foundation

// MARK: - Streak System Notifications

extension Notification.Name {
    /// Posted when a reflection is saved and streak/badges are evaluated
    /// UserInfo keys:
    /// - "newStreak": Int - The new streak count
    /// - "unlockedBadges": [BadgeID] - Badges that were unlocked
    /// - "celebrationTrigger": BadgeUnlockEvent.CelebrationTrigger - Celebration to show
    static let streakDidUpdate = Notification.Name("com.reflect.streakDidUpdate")

    /// Posted when a new badge is unlocked
    /// UserInfo keys:
    /// - "badgeID": BadgeID - The badge that was unlocked
    /// - "celebrationTrigger": BadgeUnlockEvent.CelebrationTrigger - Celebration to show
    static let badgeDidUnlock = Notification.Name("com.reflect.badgeDidUnlock")
}
