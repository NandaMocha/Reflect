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
            let fetchDescriptor = FetchDescriptor<Badge>()
            let existingBadges = try context.fetch(fetchDescriptor)

            if existingBadges.isEmpty {
                for badgeID in BadgeID.allCases {
                    let badge = Badge(from: badgeID)
                    context.insert(badge)
                }
                try context.save()
            }
        } catch {
            print("Failed to initialize badges: \(error)")
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
