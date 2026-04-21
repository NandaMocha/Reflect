# Achievement System

**Status**: Implemented. Active in-app feature.
**Last verified against code**: 2026-04-21

This document describes what the achievement system **actually is in the current code**. The earlier "streak"-based design is archived under [../archive/streak-original-spec/](../archive/streak-original-spec/) and does **not** reflect the current implementation — see [../reviews/streak-docs-vs-implementation.md](../reviews/streak-docs-vs-implementation.md) for the reconciliation.

## What it does

When a user creates a reflection, the system:

1. Increments the user's total reflection count (plus media and prompt subcounts where applicable).
2. Evaluates whether any new badge thresholds were crossed.
3. Unlocks newly earned badges, updates in-flight progress on all badges, and posts notifications.
4. The badge grid UI (`BadgeGridView`) refreshes and, if any badges unlocked, plays a celebration animation.

The Achievements screen shows a big number (`totalUnlocked`), the most recent badge, and a 2-column grid of all badges (unlocked first, then locked by difficulty).

## The 16 badges

All badges are **permanent**: once a user crosses the threshold, the badge stays unlocked forever. Progress is based on **lifetime totals**, not streaks or monthly bursts. The two previously monthly-tied badges (Monthly Champion, Perfectionist) were removed — see [../reviews/streak-docs-vs-implementation.md](../reviews/streak-docs-vs-implementation.md) for the product decision.

### Reflection milestones — 8 badges, `BadgeCategory.reflections`

| ID | Name | Threshold |
|---|---|---|
| `5-reflections` | Curious Mind | 5 |
| `10-reflections` | Dedicated Learner | 10 |
| `25-reflections` | Consistent Creator | 25 |
| `50-reflections` | Wisdom Seeker | 50 |
| `100-reflections` | Reflection Master | 100 |
| `250-reflections` | Seasoned Sage | 250 |
| `500-reflections` | Knowledge Keeper | 500 |
| `1000-reflections` | Legendary Learner | 1000 |

### Media milestones — 3 badges, `BadgeCategory.media`

Counts reflections that have at least one image, video, or voice recording.

| ID | Name | Threshold |
|---|---|---|
| `10-media` | Visual Storyteller | 10 |
| `50-media` | Memory Maker | 50 |
| `100-media` | Content Creator | 100 |

### Prompt milestones — 3 badges, `BadgeCategory.prompts`

Counts reflections that were created from a guided prompt (`reflection.promptID != nil`).

| ID | Name | Threshold |
|---|---|---|
| `10-prompts` | Guided Path | 10 |
| `50-prompts` | Deep Thinker | 50 |
| `100-prompts` | Philosopher's Path | 100 |

### Special — 2 badges, `BadgeCategory.special`

| ID | Name | Criterion |
|---|---|---|
| `quarterly-champion` | Quarterly Champion | `totalReflections >= 90` |
| `half-year-hero` | Half-Year Hero | `totalReflections >= 180` |

Canonical source: [`BadgeID.swift`](../../Reflect/Data/Models/BadgeID.swift).

## Ordering in the UI

The badge grid sorts flat by `BadgeID.requiredCount` ascending — easier first. Ties (e.g. `10-reflections`, `10-media`, `10-prompts` all require 10) are broken by `BadgeID.allCases` declaration order. Unlocked and locked badges are interleaved; the "Latest Achieved" card at the top of the screen separately highlights the most recent unlock.

## Data flow

```
User submits reflection
        │
        ▼
CreateReflectionUseCase.execute(input:)          [Reflect/Domain/UseCases/Reflection/]
        │
        │  1. Save reflection to SwiftData
        │  2. If evaluateBadgesUseCase is wired → call execute(...)
        ▼
EvaluateBadgesUseCase.execute(input:)            [Reflect/Domain/UseCases/Achievement/]
        │
        │  count queries (SwiftData)
        ├──▶ getTotalReflectionCount
        ├──▶ getMediaReflectionCount
        ├──▶ getPromptReflectionCount
        │
        │  delegate rule checks
        ├──▶ BadgeEvaluationService             [Reflect/Services/Achievement/]
        │       .evaluateReflectionMilestoneBadges(...)
        │       .evaluateMediaMilestoneBadges(...)
        │       .evaluatePromptMilestoneBadges(...)
        │       .checkMonthlyChampion / Quarterly / HalfYear / Perfectionist
        │
        │  write back
        ├──▶ updateBadgeProgress  (SwiftData save)
        └──▶ unlockBadge          (SwiftData insert/update + save)
        │
        ▼
CreateReflectionUseCase posts to NotificationCenter:
  - .badgesDidUnlock       (if any newly unlocked)
  - .badgeProgressDidUpdate (always)
        │
        ▼
BadgeGridView.onReceive(...)                     [Reflect/Presentation/Features/Achievement/Badges/]
        │
        ▼
BadgeGridViewModel.loadBadges() → BadgeRepository.fetchAll()
        │
        ▼
@Observable state change → SwiftUI re-render
```

## Key files

| Role | Path |
|---|---|
| View | [Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift) |
| ViewModel | [Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift) |
| Badge cards | [Reflect/Presentation/Components/Achievement/BadgeCard.swift](../../Reflect/Presentation/Components/Achievement/BadgeCard.swift) |
| Badge detail | [Reflect/Presentation/Components/Achievement/BadgeDetailView.swift](../../Reflect/Presentation/Components/Achievement/BadgeDetailView.swift) |
| Celebration | [Reflect/Presentation/Components/Achievement/Celebrations/CelebrationView.swift](../../Reflect/Presentation/Components/Achievement/Celebrations/CelebrationView.swift) |
| Badge model | [Reflect/Data/Models/Badge.swift](../../Reflect/Data/Models/Badge.swift) |
| Badge ID enum (canonical list) | [Reflect/Data/Models/BadgeID.swift](../../Reflect/Data/Models/BadgeID.swift) |
| Monthly achievement model | [Reflect/Data/Models/MonthlyAchievement.swift](../../Reflect/Data/Models/MonthlyAchievement.swift) |
| Unlock event (for celebrations) | [Reflect/Data/Models/BadgeUnlockEvent.swift](../../Reflect/Data/Models/BadgeUnlockEvent.swift) |
| Repository protocol | [Reflect/Data/Repositories/Protocols/BadgeRepositoryProtocol.swift](../../Reflect/Data/Repositories/Protocols/BadgeRepositoryProtocol.swift) |
| Repository | [Reflect/Data/Repositories/Implementations/BadgeRepository.swift](../../Reflect/Data/Repositories/Implementations/BadgeRepository.swift) |
| Monthly repo | [Reflect/Data/Repositories/Implementations/MonthlyAchievementRepository.swift](../../Reflect/Data/Repositories/Implementations/MonthlyAchievementRepository.swift) |
| Rules service | [Reflect/Services/Achievement/BadgeEvaluationService.swift](../../Reflect/Services/Achievement/BadgeEvaluationService.swift) |
| Use case (orchestrator) | [Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift](../../Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift) |
| Reflection use case (caller) | [Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift](../../Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift) |
| Notification names | [Reflect/Domain/Notifications/BadgeNotifications.swift](../../Reflect/Domain/Notifications/BadgeNotifications.swift) |
| DI wiring | [Reflect/App/DIContainer.swift](../../Reflect/App/DIContainer.swift) (lines 33–133) |

## Persistence

- **SwiftData.** All models are `@Model` classes. Badges have `@Attribute(.unique) var id: String` where `id` matches `BadgeID.rawValue`.
- Progress lives on the `Badge.unlockedCount` field. It's overwritten on every evaluation to match the relevant current total (reflection / media / prompt / lifetime total for special).
- `MonthlyAchievement` model still exists in the SwiftData schema (registered in [`ReflectApp.swift`](../../Reflect/ReflectApp.swift)) but is **dormant** — no code reads or writes it after the monthly-tied badges were removed. Kept in the schema to avoid a SwiftData migration; a future cleanup can remove it.
- Orphaned badges (SwiftData rows whose `id` isn't in `BadgeID.allCases` — e.g. leftover `monthly-champion` / `perfectionist` records from a previous install) are cleaned up by the migration in [`ReflectApp.initializeBadges()`](../../Reflect/ReflectApp.swift) on launch, and defensively filtered out by [`BadgeGridViewModel.loadBadges()`](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift) so they never render.

## Known issues

See [../reviews/achievement-counter-review.md](../reviews/achievement-counter-review.md) for a prioritized list: a category-filter bug in `EvaluateBadgesUseCase:35`, missing `@MainActor`, inefficient media/prompt queries, silenced save errors, stray `print()` statements, and no test coverage.
