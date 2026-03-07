import Foundation

final class BadgeEvaluationService {
    func evaluateStreakBadges(newStreak: Int, previousStreak: Int) -> [BadgeID] {
        var unlockedBadges: [BadgeID] = []

        if previousStreak < 3 && newStreak >= 3 {
            unlockedBadges.append(.threeDay)
        }
        if previousStreak < 7 && newStreak >= 7 {
            unlockedBadges.append(.sevenDay)
        }
        if previousStreak < 14 && newStreak >= 14 {
            unlockedBadges.append(.fourteenDay)
        }
        if previousStreak < 30 && newStreak >= 30 {
            unlockedBadges.append(.thirtyDay)
        }

        return unlockedBadges
    }

    func checkFirstDayOfMonth(submittedDate: Date) -> Bool {
        Calendar.current.component(.day, from: submittedDate) == 1
    }

    func checkFirstReflection(totalReflections: Int) -> Bool {
        totalReflections == 1
    }

    func getCelebrationForStreak(_ newStreak: Int, previousStreak: Int) -> BadgeUnlockEvent.CelebrationTrigger {
        if previousStreak < 30 && newStreak >= 30 {
            return .maximum
        } else if previousStreak < 14 && newStreak >= 14 {
            return .fireworks
        } else if previousStreak < 7 && newStreak >= 7 {
            return .sparkles
        } else if previousStreak < 3 && newStreak >= 3 {
            return .confetti
        }
        return .none
    }

    func checkFullMonth(achievement: MonthlyAchievement) -> Bool {
        achievement.reflectionCount >= 30 && !achievement.hasFullMonth
    }

    func checkHalfMonth(achievement: MonthlyAchievement) -> Bool {
        achievement.reflectionCount >= 14 && !achievement.hasHalfMonth
    }

    func check6MonthConsistency(_ achievements: [MonthlyAchievement]) -> Bool {
        checkConsistency(achievements, months: 6)
    }

    func check12MonthConsistency(_ achievements: [MonthlyAchievement]) -> Bool {
        checkConsistency(achievements, months: 12)
    }

    private func checkConsistency(_ achievements: [MonthlyAchievement], months: Int) -> Bool {
        var requiredMonths = Set<String>()
        var current = Calendar.current.startOfDay(for: .now)

        for _ in 0..<months {
            let year = Calendar.current.component(.year, from: current)
            let month = Calendar.current.component(.month, from: current)
            requiredMonths.insert(String(format: "%04d-%02d", year, month))
            current = Calendar.current.date(byAdding: .month, value: -1, to: current) ?? current
        }

        let achievementDict = Dictionary(grouping: achievements, by: { $0.id })

        for monthStr in requiredMonths {
            guard let achievement = achievementDict[monthStr]?.first,
                  achievement.hasAnyReflection else {
                return false
            }
        }

        return true
    }
}
