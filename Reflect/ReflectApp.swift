//
//  ReflectApp.swift
//  Reflect
//
//  Created by Nanda Mochammad on 27/01/26.
//

import SwiftUI
import SwiftData

@main
struct ReflectApp: App {
    let modelContainer: ModelContainer
    @AppStorage(Constants.UserDefaults.selectedTheme) private var selectedTheme: String = "system"

    init() {
        do {
            let schema = Schema([
                Learning.self,
                Reflection.self,
                ImageAttachment.self,
                VoiceRecording.self
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
            MainTabView()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(modelContainer)
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
