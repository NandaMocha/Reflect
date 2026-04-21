import Foundation

enum BadgeID: String, CaseIterable, Identifiable {

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

    // MARK: - Achievement Badges - Special (Permanent)

    case quarterlyChampion = "quarterly-champion"
    case halfYearHero = "half-year-hero"

    var id: String { rawValue }

    var displayName: String {
        switch self {
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
        case .quarterlyChampion: return "Quarterly Champion"
        case .halfYearHero: return "Half-Year Hero"
        }
    }

    var badgeDescription: String {
        switch self {
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
        case .quarterlyChampion: return "90 total reflections"
        case .halfYearHero: return "180 total reflections"
        }
    }

    var requirementDescription: String {
        switch self {
        // Reflection Milestones
        case .fiveReflections: return "5 reflections completed"
        case .tenReflections: return "10 reflections completed"
        case .twentyFiveReflections: return "25 reflections completed"
        case .fiftyReflections: return "50 reflections completed"
        case .hundredReflections: return "100 reflections completed"
        case .twoHundredFiftyReflections: return "250 reflections completed"
        case .fiveHundredReflections: return "500 reflections completed"
        case .thousandReflections: return "1000 reflections completed"

        // Media Master
        case .tenMedia: return "10 reflections using media (photo, video, or voice)"
        case .fiftyMedia: return "50 reflections using media (photo, video, or voice)"
        case .hundredMedia: return "100 reflections using media (photo, video, or voice)"

        // Prompt Explorer
        case .tenPrompts: return "10 reflections with guided prompts"
        case .fiftyPrompts: return "50 reflections with guided prompts"
        case .hundredPrompts: return "100 reflections with guided prompts"

        // Special
        case .quarterlyChampion: return "Complete 90 total reflections"
        case .halfYearHero: return "Complete 180 total reflections"
        }
    }

    var icon: String {
        switch self {
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
            case .quarterlyChampion: return "medal.fill"
            case .halfYearHero: return "figure.run"
        }
    }

    var badgeType: BadgeType {
        // All achievements are permanent
        return .permanent
    }

    var badgeCategory: BadgeCategory {
        switch self {
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
        case .quarterlyChampion, .halfYearHero:
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
        case .quarterlyChampion: return 90
        case .halfYearHero: return 180
        }
    }

    static var all: [BadgeID] {
        allCases
    }

    // Helper to get all achievement badges
    static var achievementBadges: [BadgeID] {
        allCases
    }

    // Helper to get badges by category
    static func badges(in category: BadgeCategory) -> [BadgeID] {
        allCases.filter { $0.badgeCategory == category }
    }

    // MARK: - Celebration

    /// Returns the appropriate celebration trigger for this badge
    var celebration: BadgeUnlockEvent.CelebrationTrigger {
        switch self {
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
        case .quarterlyChampion:
            return .fireworks
        case .halfYearHero:
            return .maximum
        }
    }
}

enum BadgeType: String, Codable {
    case permanent = "permanent"  // Earned once, kept forever
}

enum BadgeCategory: String, Codable {
    case reflections = "reflections"  // Total reflection count
    case media = "media"               // Reflections with media
    case prompts = "prompts"           // Reflections with prompts
    case special = "special"           // Special achievements
}
