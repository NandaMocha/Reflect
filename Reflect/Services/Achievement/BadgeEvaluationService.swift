import Foundation

final class BadgeEvaluationService {

    // MARK: - Reflection Milestones (Permanent)

    /// Evaluates reflection count milestone badges
    func evaluateReflectionMilestoneBadges(totalReflections: Int, previousTotal: Int) -> [BadgeID] {
        var unlockedBadges: [BadgeID] = []

        let milestones: [(BadgeID, Int)] = [
            (.fiveReflections, 5),
            (.tenReflections, 10),
            (.twentyFiveReflections, 25),
            (.fiftyReflections, 50),
            (.hundredReflections, 100),
            (.twoHundredFiftyReflections, 250),
            (.fiveHundredReflections, 500),
            (.thousandReflections, 1000)
        ]

        for (badgeID, required) in milestones {
            if previousTotal < required && totalReflections >= required {
                unlockedBadges.append(badgeID)
            }
        }

        return unlockedBadges
    }

    // MARK: - Media Milestones (Permanent)

    /// Evaluates media count milestone badges
    func evaluateMediaMilestoneBadges(mediaCount: Int, previousCount: Int) -> [BadgeID] {
        var unlockedBadges: [BadgeID] = []

        let milestones: [(BadgeID, Int)] = [
            (.tenMedia, 10),
            (.fiftyMedia, 50),
            (.hundredMedia, 100)
        ]

        for (badgeID, required) in milestones {
            if previousCount < required && mediaCount >= required {
                unlockedBadges.append(badgeID)
            }
        }

        return unlockedBadges
    }

    // MARK: - Prompt Milestones (Permanent)

    /// Evaluates prompt count milestone badges
    func evaluatePromptMilestoneBadges(promptCount: Int, previousCount: Int) -> [BadgeID] {
        var unlockedBadges: [BadgeID] = []

        let milestones: [(BadgeID, Int)] = [
            (.tenPrompts, 10),
            (.fiftyPrompts, 50),
            (.hundredPrompts, 100)
        ]

        for (badgeID, required) in milestones {
            if previousCount < required && promptCount >= required {
                unlockedBadges.append(badgeID)
            }
        }

        return unlockedBadges
    }

    // MARK: - Special Achievements

    /// Checks if user has completed their first full month of journaling
    func checkMonthlyChampion(totalReflections: Int, hasUnlockedBefore: Bool) -> Bool {
        !hasUnlockedBefore && totalReflections >= 30
    }

    /// Checks if user has maintained 90 total reflections
    func checkQuarterlyChampion(totalReflections: Int, hasUnlockedBefore: Bool) -> Bool {
        !hasUnlockedBefore && totalReflections >= 90
    }

    /// Checks if user has maintained 180 total reflections
    func checkHalfYearHero(totalReflections: Int, hasUnlockedBefore: Bool) -> Bool {
        !hasUnlockedBefore && totalReflections >= 180
    }

    /// Checks if user has reflected every single day for a full month (30/30 days)
    /// This is repeatable each month
    func checkPerfectionist(monthlyAchievement: MonthlyAchievement) -> Bool {
        // Use the existing hasFullMonth flag which tracks 30+ reflections
        monthlyAchievement.hasFullMonth
    }

    /// Checks if perfectionist badge should be awarded for a specific month
    func checkPerfectionistForMonth(month: Int, year: Int, monthlyData: MonthlyAchievement?) -> Bool {
        guard let data = monthlyData else { return false }
        // Check if this month has 30+ reflections
        return data.hasFullMonth
    }
}
