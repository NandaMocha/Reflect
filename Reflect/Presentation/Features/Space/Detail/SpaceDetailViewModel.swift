import Foundation
import Observation
import UIKit

/// Backs a space's detail screen: its reflections, plus composing a new one and deleting
/// your own. Cache-first paint, then a sync-on-appear fetch (plan §9: fetch makes it
/// correct).
@Observable
@MainActor
final class SpaceDetailViewModel {

    // MARK: - State

    let space: Space
    var reflections: [SpaceReflection] = []
    var isRefreshing: Bool = false
    var errorMessage: String?

    // Compose
    var newTitle: String = ""
    var newNote: String = ""
    var newQuestions: [SpaceQuestion] = [SpaceQuestion(id: UUID().uuidString, text: "", order: 0)]
    var newImage: UIImage?
    var isSaving: Bool = false

    // MARK: - Dependencies

    private let fetchUseCase: FetchSpaceReflectionsUseCaseProtocol
    private let createUseCase: CreateSpaceReflectionUseCaseProtocol
    private let deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol
    private let repository: SpaceRepositoryProtocol

    // MARK: - Initialization

    init(
        space: Space,
        fetchUseCase: FetchSpaceReflectionsUseCaseProtocol,
        createUseCase: CreateSpaceReflectionUseCaseProtocol,
        deleteUseCase: DeleteOwnSpaceContentUseCaseProtocol,
        repository: SpaceRepositoryProtocol
    ) {
        self.space = space
        self.fetchUseCase = fetchUseCase
        self.createUseCase = createUseCase
        self.deleteUseCase = deleteUseCase
        self.repository = repository
    }

    // MARK: - Computed

    var titleCount: Int { newTitle.count }
    var titleLimit: Int { Constants.Limits.spaceReflectionTitleMaxLength }
    var noteLimit: Int { Constants.Limits.spaceReflectionNoteMaxLength }
    var questionLimit: Int { Constants.Limits.spaceQuestionTextMaxLength }

    var canSave: Bool {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title.count <= titleLimit else { return false }
        guard note.count <= noteLimit else { return false }
        guard (1...Constants.Limits.spaceMaxQuestions).contains(newQuestions.count) else { return false }
        for question in newQuestions {
            let text = question.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty && text.count <= questionLimit else { return false }
        }
        return !isSaving
    }

    /// Reflections bucketed into date sections (newest group first, newest reflection first
    /// within each group) so the list is easy to scan by when things were posted.
    var groupedReflections: [(group: SpaceReflectionDateGroup, reflections: [SpaceReflection])] {
        var buckets: [SpaceReflectionDateGroup: [SpaceReflection]] = [:]
        for reflection in reflections {
            let group = SpaceReflectionDateGroup.group(for: reflection.createdAt ?? .distantPast)
            buckets[group, default: []].append(reflection)
        }
        return buckets
            .map { (group: $0.key, reflections: $0.value.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }) }
            .sorted { $0.group < $1.group }
    }

    // MARK: - Actions

    func load() async {
        reflections = repository.cachedReflections(spaceID: space.id)
        // If the user has already chosen a display name, mirror it into this space on open
        // so their name propagates to other members without needing to open the roster.
        await registerMyDisplayNameIfKnown()
        await refresh()
    }

    /// Best-effort: writes the user's saved display name (if any) into the space's zone.
    /// Silent — a failed registration must never disrupt loading the space.
    private func registerMyDisplayNameIfKnown() async {
        guard let name = UserDefaults.standard.spaceDisplayName() else { return }
        try? await repository.registerDisplayName(name, in: space)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            reflections = try await fetchUseCase.execute(for: space)
            errorMessage = nil
        } catch is CancellationError {
            // Cancelled pull-to-refresh — not a real error.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates the reflection and inserts it locally (optimistic-after-ack). Returns true on
    /// success so the view can dismiss the composer.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        // Register our name before the reflection lands (covers a name changed since open),
        // so other members see who posted it.
        await registerMyDisplayNameIfKnown()
        do {
            let reflection = try await createUseCase.execute(in: space, title: newTitle, note: newNote, questions: newQuestions, image: newImage)
            reflections.append(reflection)
            reflections.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            newTitle = ""
            newNote = ""
            newQuestions = [SpaceQuestion(id: UUID().uuidString, text: "", order: 0)]
            newImage = nil
            HapticManager.shared.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    func deleteOwn(_ reflection: SpaceReflection) async {
        do {
            try await deleteUseCase.execute(reflection: reflection, in: space)
            reflections.removeAll { $0.id == reflection.id }
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}
