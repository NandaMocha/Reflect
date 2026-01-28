import Foundation
import UIKit
import SwiftData

@Observable
final class ReflectionDetailViewModel {
    // MARK: - State
    var reflection: Reflection
    var showDeleteAlert = false
    var showShareSheet = false
    var showFullscreenImage: ImageAttachment?
    var error: Error?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let deleteUseCase: DeleteReflectionUseCaseProtocol

    // MARK: - Initialization

    init(
        reflection: Reflection,
        modelContext: ModelContext,
        deleteUseCase: DeleteReflectionUseCaseProtocol? = nil
    ) {
        self.reflection = reflection
        self.modelContext = modelContext
        self.deleteUseCase = deleteUseCase ?? DeleteReflectionUseCase(
            reflectionRepository: ReflectionRepository(modelContext: modelContext), hashtagRepository: HashtagRepository(modelContext: modelContext)
        )
    }

    // MARK: - Computed Properties

    var shareText: String {
        var text = "# \(reflection.title)\n\n"
        text += reflection.plainTextContent

        if !reflection.hashtags.isEmpty {
            text += "\n\n"
            text += reflection.hashtags.map { $0.displayName }.joined(separator: " ")
        }

        return text
    }

    var formattedDate: String {
        reflection.createdAt.formatted()
    }

    var sortedImages: [ImageAttachment] {
        reflection.images.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedVoiceRecordings: [VoiceRecording] {
        reflection.voiceRecordings.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Actions

    func toggleFavorite() {
        reflection.isFavorite.toggle()
        reflection.updatedAt = Date()
        try? modelContext.save()
        HapticManager.shared.selection()
    }

    func copyText() {
        UIPasteboard.general.string = shareText
        HapticManager.shared.success()
    }

    func showImage(_ image: ImageAttachment) {
        showFullscreenImage = image
    }

    func confirmDelete() {
        showDeleteAlert = true
    }

    func share() {
        showShareSheet = true
    }

    @MainActor
    func deleteReflection() async -> Bool {
        do {
            try await deleteUseCase.execute(reflection: reflection)
            HapticManager.shared.success()
            return true
        } catch {
            self.error = error
            HapticManager.shared.error()
            return false
        }
    }
}
