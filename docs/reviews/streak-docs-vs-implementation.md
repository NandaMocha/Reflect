# Streak Docs vs. Current Implementation — Reconciliation

**Date**: 2026-04-21 (updated same day with product decisions applied)
**Archived docs**: [../archive/streak-original-spec/](../archive/streak-original-spec/) (10 files)
**Current implementation**: [../features/achievement.md](../features/achievement.md)

The user's question: *"is the documentation correct instead of the implementation?"* — i.e. if the streak docs describe the intended design and the code drifted, the docs might be the right thing to restore. This review compares both sides fairly and makes a recommendation.

## Product decisions (2026-04-21)

The two open questions at the bottom of the original review were answered by the product owner:

1. **Criterion change (consecutive days / monthly burst → lifetime totals) — intentional.** The lifetime-totals basis is kept.
2. **Monthly-tied achievements — remove.** Monthly Champion and Perfectionist were removed from the code. With streaks already gone, the achievement system is now entirely lifetime-count based.
3. **Sort order — by `requiredCount` ascending** (easier first) across the whole grid.

These decisions have been applied to the code. The tables below still reflect the pre-decision comparison for historical reference; see [../features/achievement.md](../features/achievement.md) for the current 16-badge list.

## TL;DR

- **The docs are not aspirational.** They describe a system that was *built*, *shipped*, and *later removed*. [`IMPLEMENTATION_STATUS.md`](../archive/streak-original-spec/IMPLEMENTATION_STATUS.md) (March 9, 2026) declares the streak system "100% Complete" with files like `StreakData.swift`, `StreakRepository.swift`, `StreakCalculationService.swift`, `SubmitStreakReflectionUseCase.swift` — none of which exist in the repo today.
- **The removal was deliberate.** [`BadgeGridViewModel.swift:43-46`](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift) carries the comment *"All badges are permanent now after removing streaks"*. That's an explicit product decision, not accidental drift.
- **Recommendation: archive, don't restore.** The current count-based achievement system is coherent and shipping. The streak docs' correctness is moot — they describe a feature that no longer exists. See [Recommendation](#recommendation) at the bottom for the per-file call.

## What the streak docs specified

Summarized from [`01_OVERVIEW.md`](../archive/streak-original-spec/01_OVERVIEW.md), [`02_BADGES.md`](../archive/streak-original-spec/02_BADGES.md), [`03_ALGORITHMS.md`](../archive/streak-original-spec/03_ALGORITHMS.md), [`04_MODELS.md`](../archive/streak-original-spec/04_MODELS.md):

**Badges (v2, per `02_BADGES.md`)**:
- **Streak badges** (per-month, repeatable): 3-Day, 7-Day, 14-Day, 30-Day, Monthly Start, Perfectionist
- **Achievement badges** (lifetime, permanent): 8 reflection milestones (5→1000), 3 media, 3 prompts, 4 special (Monthly Champion, Quarterly Champion, Half-Year Hero, + Perfectionist cross-listed)
- Total: ~22 badges across both systems

**Models**: `Badge`, `StreakData` (singleton), `MonthlyAchievement`, `StreakStats` (display model), `MonthHeatmapData` (calendar UI), `BadgeUnlockEvent`, enhanced `Reflection` (with `submittedDate`, `isStreakSubmission`).

**Services**: `StreakCalculationService` (consecutive-day logic, streak resets), `BadgeEvaluationService`.

**Use cases**: `GetStreakStatsUseCase`, `CalculateStreakUseCase`, `SubmitStreakReflectionUseCase`, plus per-badge evaluation.

**UI**: GitHub-style monthly calendar heatmap, month selector (`< March 2025 >`), badge gallery split into streak vs. achievement sections, celebration animations tied to unlock events.

## What the code actually implements

Summarized from [`BadgeID.swift`](../../Reflect/Data/Models/BadgeID.swift), [`BadgeEvaluationService.swift`](../../Reflect/Services/Achievement/BadgeEvaluationService.swift), [`EvaluateBadgesUseCase.swift`](../../Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift), [`BadgeGridView.swift`](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift):

**Badges**: 18 total, **all permanent** (see [`features/achievement.md`](../features/achievement.md) for the list). `BadgeType` enum has `case permanent` only — no repeatable / monthly cases in code.

**Models**: `Badge`, `MonthlyAchievement`, `BadgeUnlockEvent`. **No `StreakData`, no `StreakStats`, no `MonthHeatmapData`.**

**Services**: `BadgeEvaluationService` only. No `StreakCalculationService`.

**Use cases**: `EvaluateBadgesUseCase` only. No streak-related use cases.

**UI**: `BadgeGridView` (single screen, not split into streak/achievement sections), `BadgeCard`, `BadgeDetailView`, `CelebrationView`. No calendar heatmap. No month selector.

## Side-by-side comparison

### Badges

| Streak docs | Current code | Status |
|---|---|---|
| 3-Day Streak (per-month, repeatable) | — | **Removed** |
| 7-Day Streak (per-month, repeatable) | — | **Removed** |
| 14-Day Streak (per-month, repeatable) | — | **Removed** |
| 30-Day Streak (per-month, repeatable) | — | **Removed** |
| Monthly Start (per-month, repeatable) | — | **Removed** |
| Perfectionist (repeatable monthly) | `perfectionist` (effectively permanent — see [review L4](./achievement-counter-review.md#l4-perfectionist-unlock-gate-contradicts-repeatable-intent)) | **Semantically changed** |
| 5/10/25/50/100/250/500/1000 reflection badges | ✅ same, all 8 present in `BadgeID.swift` | **Matches** |
| 10/50/100 media badges | ✅ same | **Matches** |
| 10/50/100 prompt badges | ✅ same | **Matches** |
| Monthly Champion (first full month = 30+ reflections in one month, per `02_BADGES.md:193-197`) | `monthlyChampion` unlocks at `totalReflections >= 30` (lifetime count, [`BadgeEvaluationService.swift:76-78`](../../Reflect/Services/Achievement/BadgeEvaluationService.swift)) | **Criterion changed** — now lifetime count, not monthly cadence |
| Quarterly Champion (90 *consecutive* days, per `02_BADGES.md:199-203`) | `quarterlyChampion` unlocks at `totalReflections >= 90` (lifetime count) | **Criterion changed** — was consecutive, now cumulative |
| Half-Year Hero (180 *consecutive* days) | `halfYearHero` unlocks at `totalReflections >= 180` (lifetime count) | **Criterion changed** — was consecutive, now cumulative |

### Models

| Streak docs | Current code | Status |
|---|---|---|
| `Badge` | `Badge` | **Matches structurally** (fields present: `id`, `type`, `category`, `name`, `badgeDescription`, `icon`, `isUnlocked`, `unlockedAt`, `unlockedCount`) |
| `StreakData` (singleton) | — | **Removed** |
| `MonthlyAchievement` | `MonthlyAchievement` (with `hasFullMonth`, `hasHalfMonth`, `hasFirstDayReflection`) | **Partially used** — only `hasFullMonth` is read (for Perfectionist); `hasHalfMonth` and `hasFirstDayReflection` are dead flags |
| `StreakStats` | — | **Removed** |
| `MonthHeatmapData` | — | **Removed** |
| `BadgeUnlockEvent` | `BadgeUnlockEvent` | **Matches** |
| Enhanced `Reflection` (`submittedDate`, `isStreakSubmission`) | Standard `Reflection` | **Reverted** |

### Services and use cases

| Streak docs | Current code | Status |
|---|---|---|
| `StreakCalculationService` | — | **Removed** |
| `BadgeEvaluationService` | ✅ | **Matches, but streak methods absent** |
| `GetStreakStatsUseCase` | — | **Removed** |
| `CalculateStreakUseCase` | — | **Removed** |
| `SubmitStreakReflectionUseCase` | — | **Replaced** — streak submission is gone; `CreateReflectionUseCase` simply calls `EvaluateBadgesUseCase` |

### UI

| Streak docs | Current code | Status |
|---|---|---|
| GitHub-style calendar heatmap | — | **Removed** |
| Month selector | — | **Removed** |
| Badge gallery split into streak/achievement | Single unified grid | **Consolidated** |
| Celebration animations | `CelebrationView.swift` | **Matches** |

## Divergence analysis — was streak removal intentional?

**Yes.** Three lines of evidence:

1. **In-code comment of intent.** [`BadgeGridViewModel.swift:43-46`](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift):
   ```swift
   // MARK: - Badge Categories
   /// All permanent achievement badges (all badges are now permanent after removing streaks)
   var permanentBadges: [Badge] {
       badges  // All badges are permanent now
   }
   ```
   The phrase *"after removing streaks"* is explicit.

2. **Type-system removal.** [`BadgeID.swift:264-266`](../../Reflect/Data/Models/BadgeID.swift):
   ```swift
   enum BadgeType: String, Codable {
       case permanent = "permanent"  // Earned once, kept forever
   }
   ```
   If streaks were ever coming back, the `repeatable` / `monthly` cases documented in `02_BADGES.md` would have been kept as dead cases. They weren't — they were deleted from the type.

3. **Use-case restructure.** The streak docs require `SubmitStreakReflectionUseCase` to track streak continuity. The code now uses `CreateReflectionUseCase` with a post-save badge evaluation hook — a lighter integration that doesn't need streak state. That's a design-level simplification, not a bug.

**What about the Monthly Champion / Quarterly / Half-Year criterion change?** Harder to read. The docs say Monthly Champion is "first full month of journaling" (i.e., 30+ reflections in a single month) and Quarterly / Half-Year are consecutive-day streaks. The code checks lifetime totals instead. This could be:

- **(a)** A simplification that fell out of removing the streak system (you can't check 90 consecutive days without a streak tracker), or
- **(b)** An accidental weakening of the criteria that nobody noticed.

I can't tell from the code which. The criterion `totalReflections >= 30` for Monthly Champion is much easier to hit than "30 reflections in one month" — a user with one-per-week habits would earn it in ~7 months instead of never. Worth asking the product owner whether the intent is (a) or (b). Flagging as an **open question**, not marking either doc or code as "right".

## Per-file recommendation

Each archived file gets a clear call:

| File | Recommendation | Rationale |
|---|---|---|
| `INDEX.md` | **Keep archived** | Navigation for the other archived files |
| `01_OVERVIEW.md` | **Keep archived** | Historical feature overview |
| `02_BADGES.md` | **Keep archived** | The lifetime-achievement portion is close to what shipped, but it's entangled with the streak sections — not worth extracting. [`features/achievement.md`](../features/achievement.md) is the replacement. |
| `03_ALGORITHMS.md` | **Keep archived** | Streak algorithms no longer used |
| `04_MODELS.md` | **Keep archived** | Three of the five models it specifies no longer exist |
| `05_QUICK_REFERENCE.md` | **Keep archived** | Tied to the old badge set |
| `IMPLEMENTATION_STATUS.md` | **Keep archived** | Frozen as-of March 9, 2026 — valuable because it names the exact files that were later deleted |
| `CLAUDE_CODE_READY.md` | **Keep archived** | Historical Claude handoff notes |
| `README_Claude.md` | **Keep archived** | Historical Claude handoff notes |

**No file is recommended for deletion**, and **no file is recommended for update in place** — the archive should stay frozen. The replacement is [`docs/features/achievement.md`](../features/achievement.md), written from the code.

## Recommendation — resolved

The current archive structure is preserved. The two open questions are now closed:

- **Criterion change (lifetime totals)**: intentional. Code unchanged.
- **Monthly Champion + Perfectionist**: removed from `BadgeID`, `BadgeEvaluationService`, and `EvaluateBadgesUseCase`. The `MonthlyAchievement` SwiftData model is left in the schema (dormant) to avoid a migration — a future cleanup can remove it along with `MonthlyAchievementRepository` and the DIContainer factory. Old `monthly-champion` / `perfectionist` badge rows in existing installs are cleaned up automatically by the orphan-badge migration at [`ReflectApp.initializeBadges()`](../../Reflect/ReflectApp.swift) on next launch; [`BadgeGridViewModel.loadBadges()`](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift) also defensively filters them out of the UI.
- **Grid sort**: now flat by `BadgeID.requiredCount` ascending, ties broken by enum declaration order. The old per-badge difficulty map was deleted.

Net badge count: **16** (8 reflection milestones, 3 media, 3 prompts, 2 special — Quarterly Champion and Half-Year Hero).
