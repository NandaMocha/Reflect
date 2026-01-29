import Foundation
import SwiftData

@Observable
final class SettingsViewModel {
    // MARK: - State
    var selectedTheme: String = "system"
    var defaultLanguage: String = "en-US"
    var showClearDataAlert = false
    var showExportSheet = false
    var isClearing = false
    var isExporting = false
    var errorMessage: String?

    // MARK: - Dependencies
    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSettings()
    }

    // MARK: - Settings

    private func loadSettings() {
        selectedTheme = UserDefaults.standard.string(forKey: Constants.UserDefaults.selectedTheme) ?? "system"
        defaultLanguage = UserDefaults.standard.string(forKey: Constants.UserDefaults.defaultLanguage) ?? "en-US"
    }

    func updateTheme(_ theme: String) {
        selectedTheme = theme
        UserDefaults.standard.set(theme, forKey: Constants.UserDefaults.selectedTheme)
        HapticManager.shared.selection()
    }

    func updateDefaultLanguage(_ language: String) {
        defaultLanguage = language
        UserDefaults.standard.set(language, forKey: Constants.UserDefaults.defaultLanguage)
        HapticManager.shared.selection()
    }

    // MARK: - Data Actions

    @MainActor
    func clearAllData() async {
        isClearing = true
        errorMessage = nil

        do {
            try modelContext.delete(model: ImageAttachment.self)
            try modelContext.delete(model: VoiceRecording.self)
            try modelContext.delete(model: Reflection.self)
            try modelContext.delete(model: Learning.self)
            try modelContext.save()

            isClearing = false
            HapticManager.shared.success()
        } catch {
            isClearing = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    @MainActor
    func exportData() async -> URL? {
        isExporting = true
        errorMessage = nil

        do {
            // Fetch all data
            let learnings = try modelContext.fetch(FetchDescriptor<Learning>())
            let reflections = try modelContext.fetch(FetchDescriptor<Reflection>())

            // Create export structure
            let exportData = ExportData(
                exportDate: Date(),
                version: Bundle.main.appVersion,
                learnings: learnings.map { LearningExport(from: $0) },
                reflections: reflections.map { ReflectionExport(from: $0) }
            )

            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let jsonData = try encoder.encode(exportData)

            // Save to temp file
            let fileName = "ReflectLearn_Export_\(Date().exportFileName).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try jsonData.write(to: tempURL)

            isExporting = false
            HapticManager.shared.success()
            return tempURL
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return nil
        }
    }
}

// MARK: - Export Data Structures

struct ExportData: Codable {
    let exportDate: Date
    let version: String
    let learnings: [LearningExport]
    let reflections: [ReflectionExport]
}

struct LearningExport: Codable {
    let id: String
    let title: String
    let description: String?
    let colorHex: String
    let iconName: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date

    init(from learning: Learning) {
        self.id = learning.id.uuidString
        self.title = learning.title
        self.description = learning.descriptionText
        self.colorHex = learning.colorHex
        self.iconName = learning.iconName
        self.sortOrder = learning.sortOrder
        self.createdAt = learning.createdAt
        self.updatedAt = learning.updatedAt
    }
}

struct ReflectionExport: Codable {
    let id: String
    let learningId: String?
    let title: String
    let content: String
    let isFavorite: Bool
    let createdAt: Date
    let updatedAt: Date
    let imageCount: Int
    let voiceRecordingCount: Int

    init(from reflection: Reflection) {
        self.id = reflection.id.uuidString
        self.learningId = reflection.learning?.id.uuidString
        self.title = reflection.title
        self.content = reflection.plainTextContent
        self.isFavorite = reflection.isFavorite
        self.createdAt = reflection.createdAt
        self.updatedAt = reflection.updatedAt
        self.imageCount = reflection.images.count
        self.voiceRecordingCount = reflection.voiceRecordings.count
    }
}

// MARK: - Date Extension

private extension Date {
    var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter.string(from: self)
    }
}
