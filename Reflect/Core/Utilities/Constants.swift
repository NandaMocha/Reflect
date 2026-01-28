import Foundation
import SwiftUI

// MARK: - Type Aliases for Convenience
typealias SpeechLanguage = Constants.SpeechLanguage
typealias SortOption = Constants.SortOption
typealias ThemeOption = Constants.ThemeOption

enum Constants {
    // MARK: - App Info
    enum App {
        static let name = "ReflectLearn"
        static let bundleIdentifier = "com.reflectlearn.app"
        static let iCloudContainerIdentifier = "iCloud.com.reflectlearn.app"
    }

    // MARK: - Validation Limits
    enum Limits {
        static let learningTitleMaxLength = 30
        static let learningDescriptionMaxLength = 500
        static let reflectionTitleMaxLength = 200
        static let hashtagMaxLength = 50
        static let maxImagesPerReflection = 10
        static let maxVoiceNotesPerReflection = 5
        static let maxHashtagsPerReflection = 20
        static let maxImageSizeMB = 10
        static let maxVoiceDurationMinutes = 5
    }

    // MARK: - Spacing Tokens
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Animation
    enum Animation {
        static let defaultDuration: Double = 0.3
        static let quickDuration: Double = 0.15
        static let slowDuration: Double = 0.5
    }

    // MARK: - Learning Category Colors
    enum LearningColors {
        static let coral = "#FF8A80"
        static let ocean = "#80DEEA"
        static let lavender = "#B39DDB"
        static let mint = "#A5D6A7"
        static let peach = "#FFCC80"
        static let sky = "#81D4FA"
        static let rose = "#F48FB1"
        static let sage = "#C5E1A5"

        static let all: [String] = [coral, ocean, lavender, mint, peach, sky, rose, sage]
    }

    // MARK: - Default Icons
    enum Icons {
        static let defaultLearningIcon = "book.fill"
        static let learningIcons: [String] = [
            "book.fill",
            "lightbulb.fill",
            "laptopcomputer",
            "paintbrush.fill",
            "music.note",
            "gamecontroller.fill",
            "globe",
            "star.fill",
            "heart.fill",
            "flag.fill",
            "brain.head.profile",
            "graduationcap.fill",
            "text.book.closed.fill",
            "pencil",
            "doc.text.fill",
            "chart.bar.fill",
            "function",
            "atom",
            "leaf.fill",
            "camera.fill"
        ]
    }

    // MARK: - User Defaults Keys
    enum UserDefaults {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let selectedTheme = "selectedTheme"
        static let defaultLanguage = "defaultLanguage"
        static let lastSyncDate = "lastSyncDate"
    }

    // MARK: - Speech Languages
    enum SpeechLanguage: String, CaseIterable, Identifiable {
        case indonesian = "id-ID"
        case english = "en-US"
        case englishUK = "en-GB"

        var id: String { rawValue }

        var localeCode: String { rawValue }

        var localeIdentifier: String { rawValue }

        var displayName: String {
            switch self {
            case .indonesian: return "Indonesian"
            case .english: return "English"
            case .englishUK: return "English (UK)"
            }
        }

        var flag: String {
            switch self {
            case .indonesian: return "🇮🇩"
            case .english: return "🇺🇸"
            case .englishUK: return "🇬🇧"
            }
        }
    }

    // MARK: - Theme Options
    enum ThemeOption: String, CaseIterable, Identifiable {
        case system = "system"
        case light = "light"
        case dark = "dark"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // MARK: - Sort Options
    enum SortOption: String, CaseIterable, Identifiable {
        case newestFirst = "newest"
        case oldestFirst = "oldest"
        case alphabeticalAZ = "az"
        case alphabeticalZA = "za"
        case recentlyUpdated = "updated"

        var id: String { rawValue }

        var title: String { displayName }

        var displayName: String {
            switch self {
            case .newestFirst: return "Newest First"
            case .oldestFirst: return "Oldest First"
            case .alphabeticalAZ: return "A to Z"
            case .alphabeticalZA: return "Z to A"
            case .recentlyUpdated: return "Recently Updated"
            }
        }

        var icon: String {
            switch self {
            case .newestFirst: return "arrow.down.circle"
            case .oldestFirst: return "arrow.up.circle"
            case .alphabeticalAZ: return "textformat.abc"
            case .alphabeticalZA: return "textformat.abc"
            case .recentlyUpdated: return "clock.arrow.circlepath"
            }
        }
    }
}
