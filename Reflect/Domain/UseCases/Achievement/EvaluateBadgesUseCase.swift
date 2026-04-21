import Foundation
import SwiftData
import os

protocol EvaluateBadgesUseCaseProtocol {
    func execute(input: EvaluateBadgesInput) async throws -> [BadgeID]
}

struct EvaluateBadgesInput {
    let modelContext: ModelContext
    let newReflection: Reflection
}

final class EvaluateBadgesUseCase: EvaluateBadgesUseCaseProtocol {
    private let badgeEvaluationService: BadgeEvaluationService
    private let badgeRepository: BadgeRepositoryProtocol
    private let logger = Logger(subsystem: "com.reflectlearn.app", category: "Achievement")

    init(
        badgeEvaluationService: BadgeEvaluationService = BadgeEvaluationService(),
        badgeRepository: BadgeRepositoryProtocol
    ) {
        self.badgeEvaluationService = badgeEvaluationService
        self.badgeRepository = badgeRepository
    }

    func execute(input: EvaluateBadgesInput) async throws -> [BadgeID] {
        var newlyUnlockedBadges: [BadgeID] = []

        // Get current counts
        let totalReflections = await getTotalReflectionCount(input.modelContext)
        let mediaCount = await getMediaReflectionCount(input.modelContext)
        let promptCount = await getPromptReflectionCount(input.modelContext)

        // Get previous counts from badges
        let allBadges = try await badgeRepository.fetchAll()
        let previousTotal = allBadges
            .first(where: { BadgeID(rawValue: $0.id)?.badgeCategory == .reflections })?
            .unlockedCount ?? 0

        // Evaluate reflection milestones
        let reflectionBadges = badgeEvaluationService.evaluateReflectionMilestoneBadges(
            totalReflections: totalReflections,
            previousTotal: previousTotal
        )
        newlyUnlockedBadges.append(contentsOf: reflectionBadges)

        // Evaluate media milestones
        let previousMedia = allBadges.filter({ BadgeID(rawValue: $0.id)?.badgeCategory == .media }).first?.unlockedCount ?? 0
        let mediaBadges = badgeEvaluationService.evaluateMediaMilestoneBadges(
            mediaCount: mediaCount,
            previousCount: previousMedia
        )
        newlyUnlockedBadges.append(contentsOf: mediaBadges)

        // Evaluate prompt milestones
        let previousPrompt = allBadges.filter({ BadgeID(rawValue: $0.id)?.badgeCategory == .prompts }).first?.unlockedCount ?? 0
        let promptBadges = badgeEvaluationService.evaluatePromptMilestoneBadges(
            promptCount: promptCount,
            previousCount: previousPrompt
        )
        newlyUnlockedBadges.append(contentsOf: promptBadges)

        // Check special achievements
        let specialBadges = try await checkSpecialAchievements(
            modelContext: input.modelContext,
            totalReflections: totalReflections,
            existingBadges: allBadges
        )
        newlyUnlockedBadges.append(contentsOf: specialBadges)

        // Update progress for all badges
        await updateBadgeProgress(
            modelContext: input.modelContext,
            totalReflections: totalReflections,
            mediaCount: mediaCount,
            promptCount: promptCount
        )

        // Unlock newly earned badges
        for badgeID in newlyUnlockedBadges {
            await unlockBadge(
                badgeID,
                modelContext: input.modelContext,
                count: getCountForBadge(badgeID, total: totalReflections, media: mediaCount, prompt: promptCount)
            )
        }

        return newlyUnlockedBadges
    }

    // MARK: - Private Helper Methods

    private func checkSpecialAchievements(
        modelContext: ModelContext,
        totalReflections: Int,
        existingBadges: [Badge]
    ) async throws -> [BadgeID] {
        var unlockedBadges: [BadgeID] = []

        let quarterlyChampionBadge = existingBadges.first { $0.id == "quarterly-champion" }
        if badgeEvaluationService.checkQuarterlyChampion(
            totalReflections: totalReflections,
            hasUnlockedBefore: quarterlyChampionBadge?.isUnlocked ?? false
        ) {
            unlockedBadges.append(.quarterlyChampion)
        }

        let halfYearHeroBadge = existingBadges.first { $0.id == "half-year-hero" }
        if badgeEvaluationService.checkHalfYearHero(
            totalReflections: totalReflections,
            hasUnlockedBefore: halfYearHeroBadge?.isUnlocked ?? false
        ) {
            unlockedBadges.append(.halfYearHero)
        }

        return unlockedBadges
    }

    private func updateBadgeProgress(
        modelContext: ModelContext,
        totalReflections: Int,
        mediaCount: Int,
        promptCount: Int
    ) async {
        let allBadges = (try? modelContext.fetch(FetchDescriptor<Badge>())) ?? []

        for badge in allBadges {
            guard let badgeID = BadgeID(rawValue: badge.id) else { continue }

            switch badgeID.badgeCategory {
            case .reflections:
                badge.unlockedCount = totalReflections
            case .media:
                badge.unlockedCount = mediaCount
            case .prompts:
                badge.unlockedCount = promptCount
            case .special:
                badge.unlockedCount = totalReflections
            }
        }

        save(modelContext)
    }

    private func unlockBadge(_ badgeID: BadgeID, modelContext: ModelContext, count: Int) async {
        let allBadges = (try? modelContext.fetch(FetchDescriptor<Badge>())) ?? []
        let existingBadges = allBadges.filter { $0.id == badgeID.rawValue }

        if let existingBadge = existingBadges.first {
            if !existingBadge.isUnlocked {
                existingBadge.isUnlocked = true
                existingBadge.unlockedAt = Date()
                existingBadge.unlockedCount = count
            }
        } else {
            let newBadge = Badge(from: badgeID)
            newBadge.isUnlocked = true
            newBadge.unlockedAt = Date()
            newBadge.unlockedCount = count
            modelContext.insert(newBadge)
        }

        save(modelContext)
    }

    private func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            logger.error("Badge save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func getCountForBadge(_ badgeID: BadgeID, total: Int, media: Int, prompt: Int) -> Int {
        switch badgeID.badgeCategory {
        case .reflections:
            return total
        case .media:
            return media
        case .prompts:
            return prompt
        case .special:
            return total
        }
    }

    // MARK: - Database Queries

    private func getTotalReflectionCount(_ modelContext: ModelContext) async -> Int {
        let descriptor = FetchDescriptor<Reflection>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func getMediaReflectionCount(_ modelContext: ModelContext) async -> Int {
        let descriptor = FetchDescriptor<Reflection>()
        let reflections = (try? modelContext.fetch(descriptor)) ?? []
        return reflections.filter { reflection in
            !reflection.images.isEmpty || !reflection.videos.isEmpty || !reflection.voiceRecordings.isEmpty
        }.count
    }

    private func getPromptReflectionCount(_ modelContext: ModelContext) async -> Int {
        let descriptor = FetchDescriptor<Reflection>()
        let reflections = (try? modelContext.fetch(descriptor)) ?? []
        return reflections.filter { $0.promptID != nil }.count
    }

}
