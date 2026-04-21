# ARCHIVED — DO NOT USE AS A REFERENCE FOR CURRENT CODE

> **Status**: Frozen. These documents describe an earlier design that was **intentionally abandoned**. They are preserved for historical reference and for the reconciliation review.

## What's in here

10 files describing a "Streak & Badge" system for Reflect:

| File | Content |
|---|---|
| `INDEX.md` | Navigation guide for this doc set |
| `01_OVERVIEW.md` | Feature overview |
| `02_BADGES.md` | Badge specifications (mixes streak + achievement badges) |
| `03_ALGORITHMS.md` | Streak calculation and badge evaluation algorithms |
| `04_MODELS.md` | SwiftData model specs (Badge, StreakData, MonthlyAchievement, …) |
| `05_QUICK_REFERENCE.md` | Checklists and snippets |
| `IMPLEMENTATION_STATUS.md` | Progress tracker (dated March 9, 2026) |
| `CLAUDE_CODE_READY.md`, `README_Claude.md` | Historical Claude handoff notes |

## Why archived

The streak-based portion of the design (3/7/14/30-day streaks, Monthly Start, Full Month / Half Month badges, `StreakData`, `StreakCalculationService`, `SubmitStreakReflectionUseCase`, calendar heatmap UI) was **implemented, then deliberately removed** in favor of a count-based achievement system.

Evidence in the current code:

- [`BadgeGridViewModel.swift:43-46`](../../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift) comment reads "All badges are permanent now after removing streaks".
- `BadgeType` enum in [`BadgeID.swift:264-266`](../../../Reflect/Data/Models/BadgeID.swift) has only `case permanent` — the `repeatable` / `monthly` cases described in `02_BADGES.md` do not exist.
- `StreakData.swift`, `StreakRepository.swift`, `StreakCalculationService.swift` described in `IMPLEMENTATION_STATUS.md` no longer exist anywhere in the repo.
- The current `BadgeID` enum defines 16 badges (reflection milestones 5→1000, media 10/50/100, prompt 10/50/100, plus 2 special — Quarterly Champion and Half-Year Hero). A later product decision also removed the two monthly-tied special badges (Monthly Champion, Perfectionist). None of these match the streak badges described here.

## Where to look instead

- Current implementation reference: [../../features/achievement.md](../../features/achievement.md)
- Doc–code drift analysis (why and how they diverged): [../../reviews/streak-docs-vs-implementation.md](../../reviews/streak-docs-vs-implementation.md)
- Known issues with the current achievement system: [../../reviews/achievement-counter-review.md](../../reviews/achievement-counter-review.md)

## Can I update these files?

**No.** The archive is frozen on purpose — if you update stale specs to match new code, the reconciliation review loses its reference point, and readers can no longer tell what was intended vs. what shipped. If the current code is wrong and the streak design should be restored, open a new design doc under [`docs/features/`](../../features/) citing these archived files, and leave the archive untouched.
