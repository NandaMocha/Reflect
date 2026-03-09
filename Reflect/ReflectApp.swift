//
//  ReflectApp.swift
//  Reflect
//
//  Created by Nanda Mochammad on 27/01/26.
//

import SwiftUI
import SwiftData

// MARK: - Widget Action Enum

enum WidgetAction {
    case write
    case camera
    case voice
}

@main
struct ReflectApp: App {
    let modelContainer: ModelContainer
    @AppStorage(Constants.UserDefaults.selectedTheme) private var selectedTheme: String = "system"

    // Widget action handling
    @State private var widgetAction: WidgetAction?

    init() {
        do {
            let schema = Schema([
                Learning.self,
                Reflection.self,
                ImageAttachment.self,
                VoiceRecording.self,
                VideoAttachment.self,
                // Streak & Badge models
                Badge.self,
                StreakData.self,
                MonthlyAchievement.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none // Manual sync, not automatic
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(widgetAction: $widgetAction)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    handleWidgetURL(url)
                }
                .onAppear {
                    initializeBadges()
                }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Badge Initialization

    private func initializeBadges() {
        do {
            let context = modelContainer.mainContext

            // Try to fetch existing badges - this will fail if old schema exists
            let fetchDescriptor = FetchDescriptor<Badge>()
            let existingBadges: [Badge]

            do {
                existingBadges = try context.fetch(fetchDescriptor)
            } catch {
                // Fetch failed due to schema mismatch (old Badge model without category field)
                print("⚠️ Old badge schema detected. Performing reset...")
                // Create new badges directly
                createNewBadges(context: context)
                return
            }

            if existingBadges.isEmpty {
                // No badges exist, create them
                createNewBadges(context: context)
            } else {
                // Badges exist, check if migration needed
                migrateBadgesIfNeeded(existingBadges: existingBadges, context: context)
            }
        } catch {
            print("❌ Failed to initialize badges: \(error)")
        }
    }

    private func createNewBadges(context: ModelContext) {
        var createdCount = 0
        for badgeID in BadgeID.allCases {
            if badgeID.badgeType == .permanent {
                let badge = Badge(from: badgeID)
                context.insert(badge)
                createdCount += 1
            }
        }

        do {
            try context.save()
            print("✅ Created \(createdCount) permanent badges")
        } catch {
            print("❌ Failed to save badges: \(error)")
        }
    }

    private func migrateBadgesIfNeeded(existingBadges: [Badge], context: ModelContext) {
        var needsSave = false

        // Migration 1: Convert old .repeatedStreak to .monthlyStreak
        let badgesWithOldType = existingBadges.filter { $0.type == .repeatedStreak }
        if !badgesWithOldType.isEmpty {
            print("🔄 Migrating \(badgesWithOldType.count) badges from repeatedStreak to monthlyStreak...")
            for badge in badgesWithOldType {
                badge.type = .monthlyStreak
                badge.updatedAt = Date()
                needsSave = true
            }
        }

        // Migration 2: Check if we have old badge IDs
        let currentBadgeIDs = Set(BadgeID.allCases.map { $0.rawValue })
        let oldBadges = existingBadges.filter { !currentBadgeIDs.contains($0.id) }

        if !oldBadges.isEmpty {
            print("🔄 Found \(oldBadges.count) old badges. Cleaning up...")

            // Delete old badges
            for badge in oldBadges {
                context.delete(badge)
            }
            needsSave = true

            // Create any missing new badges
            let existingIDs = Set(existingBadges.map { $0.id })
            var createdCount = 0

            for badgeID in BadgeID.allCases {
                if badgeID.badgeType == .permanent && !existingIDs.contains(badgeID.rawValue) {
                    let badge = Badge(from: badgeID)
                    context.insert(badge)
                    createdCount += 1
                }
            }

            print("✅ Migration complete: Deleted \(oldBadges.count) old badges, created \(createdCount) new badges")
        }

        if needsSave {
            do {
                try context.save()
                print("✅ Badge migration saved successfully")
            } catch {
                print("❌ Failed to save migration: \(error)")
            }
        } else {
            print("✅ Badges already up to date")
        }
    }

    // MARK: - Widget URL Handling

    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == "reflect" else { return }

        switch url.host {
        case "write":
            widgetAction = .write
        case "camera":
            widgetAction = .camera
        case "voice":
            widgetAction = .voice
        default:
            break
        }
    }

    private var colorScheme: ColorScheme? {
        switch selectedTheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}
