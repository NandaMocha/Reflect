import Foundation

enum BadgeID: String, CaseIterable, Identifiable {

    // MARK: - Streak Badges (Per Month, Repeatable)

    case threeDayStreak = "3day-streak"
    case sevenDayStreak = "7day-streak"
    case fourteenDayStreak = "14day-streak"
    case thirtyDayStreak = "30day-streak"

    // MARK: - Achievement Badges - Reflection Milestones (Permanent)

    case fiveReflections = "5-reflections"
    case tenReflections = "10-reflections"
    case twentyFiveReflections = "25-reflections"
    case fiftyReflections = "50-reflections"
    case hundredReflections = "100-reflections"
    case twoHundredFiftyReflections = "250-reflections"
    case fiveHundredReflections = "500-reflections"
    case thousandReflections = "1000-reflections"

    // MARK: - Achievement Badges - Media Master (Permanent)

    case tenMedia = "10-media"
    case fiftyMedia = "50-media"
    case hundredMedia = "100-media"

    // MARK: - Achievement Badges - Prompt Explorer (Permanent)

    case tenPrompts = "10-prompts"
    case fiftyPrompts = "50-prompts"
    case hundredPrompts = "100-prompts"

    // MARK: - Achievement Badges - Special (Permanent except Perfectionist)

    case monthlyChampion = "monthly-champion"
    case quarterlyChampion = "quarterly-champion"
    case halfYearHero = "half-year-hero"
    case perfectionist = "perfectionist" // Repeatable monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        // Streak Badges
        case .threeDayStreak: return "3-Day Streak"
        case .sevenDayStreak: return "7-Day Streak"
        case .fourteenDayStreak: return "14-Day Streak"
        case .thirtyDayStreak: return "30-Day Streak"

        // Reflection Milestones
        case .fiveReflections: return "Curious Mind"
        case .tenReflections: return "Dedicated Learner"
        case .twentyFiveReflections: return "Consistent Creator"
        case .fiftyReflections: return "Wisdom Seeker"
        case .hundredReflections: return "Reflection Master"
        case .twoHundredFiftyReflections: return "Seasoned Sage"
        case .fiveHundredReflections: return "Knowledge Keeper"
        case .thousandReflections: return "Legendary Learner"

        // Media Master
        case .tenMedia: return "Visual Storyteller"
        case .fiftyMedia: return "Memory Maker"
        case .hundredMedia: return "Content Creator"

        // Prompt Explorer
        case .tenPrompts: return "Guided Path"
        case .fiftyPrompts: return "Deep Thinker"
        case .hundredPrompts: return "Philosopher's Path"

        // Special
        case .monthlyChampion: return "Monthly Champion"
        case .quarterlyChampion: return "Quarterly Champion"
        case .halfYearHero: return "Half-Year Hero"
        case .perfectionist: return "Perfectionist"
        }
    }

    var badgeDescription: String {
        switch self {
        // Streak Badges
        case .threeDayStreak: return "3 consecutive days of reflections"
        case .sevenDayStreak: return "7 consecutive days of reflections"
        case .fourteenDayStreak: return "14 consecutive days of reflections"
        case .thirtyDayStreak: return "30 consecutive days of reflections"

        // Reflection Milestones
        case .fiveReflections: return "Every journey begins with a single step. You've started yours!"
        case .tenReflections: return "Building momentum, one reflection at a time"
        case .twentyFiveReflections: return "Making reflection your daily superpower"
        case .fiftyReflections: return "A growing collection of insights and discoveries"
        case .hundredReflections: return "A century of learning - impressive dedication!"
        case .twoHundredFiftyReflections: return "Your journal holds a wealth of wisdom"
        case .fiveHundredReflections: return "An extraordinary milestone of personal growth"
        case .thousandReflections: return "You've achieved the impossible - truly remarkable!"

        // Media Master
        case .tenMedia: return "Capturing life's moments, one memory at a time"
        case .fiftyMedia: return "Your visual journal tells a beautiful story"
        case .hundredMedia: return "A masterpiece of photos and videos"

        // Prompt Explorer
        case .tenPrompts: return "Following questions to deeper understanding"
        case .fiftyPrompts: return "Every prompt unlocks new insights"
        case .hundredPrompts: return "Mastering the art of self-discovery"

        // Special
        case .monthlyChampion: return "Completed your first full month of journaling"
        case .quarterlyChampion: return "90 days of unwavering consistency"
        case .halfYearHero: return "180 days of dedication - extraordinary!"
        case .perfectionist: return "Flawless consistency - 30 days in a row"
        }
    }

    var icon: String {
        switch self {
            // Streak Badges
            case .threeDayStreak: return "flame.fill"
            case .sevenDayStreak: return "flame.fill"
            case .fourteenDayStreak: return "flame.fill"
            case .thirtyDayStreak: return "flame.fill"

            // Reflection Milestones
            case .fiveReflections: return "star.fill"
            case .tenReflections: return "star.circle.fill"
            case .twentyFiveReflections: return "sparkles"
            case .fiftyReflections: return "book.fill"
            case .hundredReflections: return "graduationcap.fill"
            case .twoHundredFiftyReflections: return "lightbulb.max.fill"
            case .fiveHundredReflections: return "books.vertical.fill"
            case .thousandReflections: return "crown.fill"

            // Media Master
            case .tenMedia: return "camera.fill"
            case .fiftyMedia: return "photo.stack"
            case .hundredMedia: return "video.fill"

            // Prompt Explorer
            case .tenPrompts: return "lightbulb"
            case .fiftyPrompts: return "brain.head.profile"
            case .hundredPrompts: return "building.columns.fill"

            // Special
            case .monthlyChampion: return "trophy.fill"
            case .quarterlyChampion: return "medal.fill"
            case .halfYearHero: return "figure.run"
            case .perfectionist: return "diamond.fill"
        }
    }

    var badgeType: BadgeType {
        switch self {
        // Streak Badges (Monthly, repeatable)
        case .threeDayStreak, .sevenDayStreak, .fourteenDayStreak, .thirtyDayStreak:
            return .monthlyStreak

        // Special - Perfectionist is repeatable monthly
        case .perfectionist:
            return .monthlyStreak

        // All other achievements are permanent
        default:
            return .permanent
        }
    }

    var badgeCategory: BadgeCategory {
        switch self {
        // Streak Badges
        case .threeDayStreak, .sevenDayStreak, .fourteenDayStreak, .thirtyDayStreak:
            return .streak

        // Reflection Milestones
        case .fiveReflections, .tenReflections, .twentyFiveReflections, .fiftyReflections,
             .hundredReflections, .twoHundredFiftyReflections, .fiveHundredReflections, .thousandReflections:
            return .reflections

        // Media Master
        case .tenMedia, .fiftyMedia, .hundredMedia:
            return .media

        // Prompt Explorer
        case .tenPrompts, .fiftyPrompts, .hundredPrompts:
            return .prompts

        // Special
        case .monthlyChampion, .quarterlyChampion, .halfYearHero, .perfectionist:
            return .special
        }
    }

    var requiredCount: Int {
        switch self {
        case .fiveReflections: return 5
        case .tenReflections, .tenMedia, .tenPrompts: return 10
        case .twentyFiveReflections: return 25
        case .fiftyReflections, .fiftyMedia, .fiftyPrompts: return 50
        case .hundredReflections, .hundredMedia, .hundredPrompts: return 100
        case .twoHundredFiftyReflections: return 250
        case .fiveHundredReflections: return 500
        case .thousandReflections: return 1000
        case .threeDayStreak: return 3
        case .sevenDayStreak: return 7
        case .fourteenDayStreak: return 14
        case .thirtyDayStreak: return 30
        case .monthlyChampion: return 1
        case .quarterlyChampion: return 90
        case .halfYearHero: return 180
        case .perfectionist: return 30
        }
    }

    static var all: [BadgeID] {
        allCases
    }

    // Helper to get all streak badges
    static var streakBadges: [BadgeID] {
        [.threeDayStreak, .sevenDayStreak, .fourteenDayStreak, .thirtyDayStreak]
    }

    // Helper to get all achievement badges
    static var achievementBadges: [BadgeID] {
        allCases.filter { $0.badgeType == .permanent || $0 == .perfectionist }
    }

    // Helper to get badges by category
    static func badges(in category: BadgeCategory) -> [BadgeID] {
        allCases.filter { $0.badgeCategory == category }
    }

    // MARK: - Celebration

    /// Returns the appropriate celebration trigger for this badge
    var celebration: BadgeUnlockEvent.CelebrationTrigger {
        switch self {
        // Streak badges
        case .threeDayStreak:
            return .confetti
        case .sevenDayStreak:
            return .sparkles
        case .fourteenDayStreak:
            return .fireworks
        case .thirtyDayStreak:
            return .maximum

        // First reflection milestone
        case .fiveReflections:
            return .confetti

        // Higher reflection milestones
        case .tenReflections, .twentyFiveReflections:
            return .sparkles

        // Major reflection milestones
        case .fiftyReflections, .hundredReflections:
            return .fireworks

        // Epic reflection milestones
        case .twoHundredFiftyReflections, .fiveHundredReflections, .thousandReflections:
            return .maximum

        // Media milestones
        case .tenMedia:
            return .confetti
        case .fiftyMedia:
            return .sparkles
        case .hundredMedia:
            return .fireworks

        // Prompt milestones
        case .tenPrompts:
            return .confetti
        case .fiftyPrompts:
            return .sparkles
        case .hundredPrompts:
            return .fireworks

        // Special achievements
        case .monthlyChampion:
            return .sparkles
        case .quarterlyChampion:
            return .fireworks
        case .halfYearHero:
            return .maximum
        case .perfectionist:
            return .maximum
        }
    }
}

enum BadgeType: String, Codable {
    case monthlyStreak = "monthly_streak"    // Repeatable each month
    case permanent = "permanent"              // Earned once, kept forever

    // MARK: - Backward Compatibility

    @available(*, deprecated, message: "Use monthlyStreak instead. This case exists only for migrating old data.")
    case repeatedStreak = "repeated_streak"  // Old name, migrated to monthlyStreak
}

enum BadgeCategory: String, Codable {
    case streak = "streak"                    // Consecutive day streaks
    case reflections = "reflections"          // Total reflection count
    case media = "media"                      // Reflections with media
    case prompts = "prompts"                  // Reflections with prompts
    case special = "special"                  // Special achievements
}
