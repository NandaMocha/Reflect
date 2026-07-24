# Achievement Counter — Deep-Dive Root Cause Analysis

**Date**: 2026-04-21
**Branch**: `fix/achievement-counter` (8 commits ahead of `main`)
**Scope**: Why the user still reports the achievement counter "does not work" after the fixes in commits `8359133`, `25a9749`, `03cba6f`, `2b45b8e`.

The first review (`achievement-counter-review.md`) was static analysis — it found and fixed several correctness issues, but they were all in the **happy-path create flow**. The user's complaint persists, so something else is wrong. This deep-dive traces the full runtime flow and ranks the actual user-visible bugs by likelihood.

## TL;DR

The happy-path *create* flow is now correct. **What's still broken is everything else.** The four bugs below, in impact order, explain why a user would say "the counter isn't working":

1. **Editing a reflection never re-evaluates badges.** ✅ **Fixed in commit `0ed0a3a`** — `UpdateReflectionUseCase` now accepts and runs `evaluateBadgesUseCase` end-to-end, mirroring the create path.
2. **Celebrations never fire.** ✅ **Fixed in commit `7003d96`** — the VM now subscribes to `.badgesDidUnlock` on the main queue and sets `showCelebration` / `celebrationTrigger` from the payload, picking the most dramatic celebration tier when multiple badges unlock simultaneously.
3. **The main-screen UI has no numeric counter.** ⏳ Open — needs a product call on whether the icon-strip is intentional or should carry a `5/16`-style number.
4. **Sheet re-renders reinstantiate the VM.** ⏳ Open — not strictly broken, but fragile; medium-risk refactor gated behind manual UI testing.

## Evidence for each

### 1. `UpdateReflectionUseCase` has zero badge evaluation

[Reflect/Domain/UseCases/Reflection/UpdateReflectionUseCase.swift](../../Reflect/Domain/UseCases/Reflection/UpdateReflectionUseCase.swift) — **entire file reviewed**. Compare with `CreateReflectionUseCase`:

| | Create | Update |
|---|---|---|
| Takes `evaluateBadgesUseCase` param | ✅ (line 12, 18) | ❌ not in constructor |
| Calls `evaluateBadgesUseCase.execute` after save | ✅ (lines 76–92) | ❌ no such call |
| Posts `.badgesDidUnlock` / `.badgeProgressDidUpdate` | ✅ (lines 84–91) | ❌ no notifications |

The update path is used by [`ReflectionEditorViewModel+SaveLogic.swift:31-60`](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel+SaveLogic.swift) whenever `mode == .edit(…)`. Scenarios that silently no-op:

- User creates a text-only reflection, realizes they want to attach a photo, taps Edit, adds the photo, saves. `mediaCount` in the DB changes, but `EvaluateBadgesUseCase` never runs, so `10-media` / `50-media` / `100-media` badges don't check their thresholds. No badge unlock, no notification, no UI refresh. The Badge.unlockedCount for media badges also doesn't get bumped until the NEXT *creation* re-runs the evaluation.
- Same for adding voice recordings after creation.
- Removing media doesn't recount either (though this is less user-visible — you can't un-earn a badge, but the count snapshot in `Badge.unlockedCount` goes stale).

**Why this is the #1 suspect**: it's the most common real-user workflow (draft a reflection → come back → attach media) and it's silently broken. The create path works, so a casual test might not catch it.

### 2. Celebration is wired at the view but never triggered

The pieces exist:

- `celebration()` modifier defined in [CelebrationModifier.swift:11-63](../../Reflect/Presentation/Modifiers/CelebrationModifier.swift) — looks good
- Applied in [ReflectionEditorView.swift:152](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView.swift) — `.celebration(isPresented: $showCelebration, trigger: celebrationTrigger)`
- Backing state on the VM at [ReflectionEditorViewModel.swift:27-28](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel.swift): `var showCelebration: Bool = false`, `var celebrationTrigger: … = .none`

**The missing link**: nothing ever writes `true` to `showCelebration` or assigns a trigger in response to a real unlock event.

- `CreateReflectionUseCase.execute` posts `.badgesDidUnlock` with `object: unlockedBadges` ([line 86](../../Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift)), payload `[BadgeID]`.
- The ViewModel's `setupNotificationObservers()` is a no-op ([line 100-102](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel.swift)) with a comment `// No streak notifications needed`.
- `createUseCase.execute()` returns `Reflection`, not the unlocked-badge list — so even if the VM wanted to act on unlocks synchronously, it can't.

The only two places that write `showCelebration = true` in the whole repo are inside [an example comment block in CelebrationModifier.swift:79](../../Reflect/Presentation/Modifiers/CelebrationModifier.swift) and [inside CelebrationView.swift:45](../../Reflect/Presentation/Components/Achievement/Celebrations/CelebrationView.swift) (which is the celebration view itself, not a caller). **No production code path fires the celebration when a badge actually unlocks.**

### 3. The main screen doesn't display a numeric count

[LearningListView.swift:266-314](../../Reflect/Presentation/Features/Learning/List/LearningListView.swift) — the `achievementEntrySection`:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Achievements")
        .font(.headline)
}
// …
if !latestAchievements.isEmpty {
    HStack(spacing: 8) {
        ForEach(latestAchievements.prefix(4)) { badge in
            Image(systemName: badge.icon) … // up to 4 circles
        }
    }
}
```

No `Text("\(totalUnlocked)")` anywhere on the main screen. The big blue `48pt` counter lives only in [BadgeGridView.swift:65](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift), behind a sheet. A user looking at the main screen after earning a milestone sees the icons change (if there's room in the top-4) but no counter increment — because there *is* no counter.

Whether this is a "bug" depends on intent. If the spec calls for a counter on the main screen, it's missing. If the strip is meant to be icon-only, nothing's wrong here — but then the user's complaint needs re-framing.

### 4. Sheet closure recreates the VM

```swift
// LearningListView.swift:95-97
.sheet(isPresented: $showAchievementGallery) {
    let viewModel = BadgeGridViewModel(modelContext: modelContext)
    NavigationView {
        BadgeGridView(viewModel: viewModel)
```

Every time SwiftUI re-evaluates the sheet's content (Environment changes, AppStorage changes, outer view identity changes), this closure runs and allocates a new `BadgeGridViewModel`. Because `BadgeGridView` uses `@State` with `State(initialValue:)` in its init, the `@State` wrapper ignores subsequent instances and keeps the original — so the allocated-then-dropped VMs don't strictly break anything. But:

- Every re-render does a pointless alloc of the whole VM graph (VM → BadgeRepository → ModelContext closure).
- The VM's `loadBadges()` does fire once (via `.task`), but notification observers live on the *view*, not the VM — so they keep targeting the originally-captured VM, which is fine here but means the `@State` / `@Observable` combo is holding together by luck.
- If the sheet is dismissed and re-presented, the view identity resets, new VM wins, state is lost (expected behavior, just worth being aware of).

This is the M4 finding from the original review, now promoted because it's part of the overall fragility story.

## Why it's not these things

Ruled out during the trace:

- **DIContainer wiring of `evaluateBadgesUseCase`** — correct in `makeCreateReflectionUseCase()`, but `ReflectionEditorViewModel.init` builds its own graph inline ([lines 61-77](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel.swift)), bypassing the DIContainer entirely. So the DIContainer wiring is dead code for this path. It's correct-but-unused.
- **`ModelContext` mismatch** — everything resolves from the single `ModelContainer` set in `ReflectApp.body` and threaded through `@Environment(\.modelContext)`. VM's `modelContext`, BadgeRepository's context, and EvaluateBadgesUseCase's `input.modelContext` all point at the same instance in practice.
- **`initializeBadges` timing** — runs on `MainTabView.onAppear`, which fires before the user can reach any reflection form. `migrateBadgesIfNeeded` is idempotent on re-entry.
- **Migration of removed monthly-tied badges** — the orphan cleanup at [ReflectApp.swift:154-168](../../Reflect/ReflectApp.swift) correctly removes old `monthly-champion` / `perfectionist` rows on next launch. Confirmed working.
- **Stale `previousTotal`** — fixed in commit `8359133`.

## Recommended fix order

| # | Fix | Files | Risk | Status |
|---|---|---|---|---|
| 1 | Wire `evaluateBadgesUseCase` into `UpdateReflectionUseCase` — mirror what `CreateReflectionUseCase` does | UpdateReflectionUseCase.swift, CreateReflectionInput.swift, ReflectionEditorViewModel.swift, ReflectionEditorViewModel+SaveLogic.swift, DIContainer.swift | Low | ✅ `0ed0a3a` |
| 2 | Subscribe `ReflectionEditorViewModel` to `.badgesDidUnlock` and set `celebrationTrigger` / `showCelebration` from the payload | ReflectionEditorViewModel.swift | Low | ✅ `7003d96` |
| 3 | Decide main-screen counter intent: add a `Text("\(totalUnlocked) / \(totalBadges)")` to `achievementEntrySection`, **or** confirm icons-only is intentional and close this | LearningListView.swift | UX decision, then low | ⏳ Open — product question |
| 4 | Move VM ownership out of the sheet closure: parent holds `@State var achievementVM: BadgeGridViewModel?`, initializes lazily in `.task`, and passes `@Bindable` to `BadgeGridView` | LearningListView.swift, BadgeGridView.swift | Medium (touches SwiftUI lifecycle — verify in simulator) | ⏳ Open |

Fixes 1 and 2 were the highest-leverage. With them landed, the edit-and-attach-media workflow now produces badge unlocks, and any unlock shows the celebration animation.

## Open question for the product owner

For fix 3 — what's the intended main-screen achievement display? "Show 4 latest icons" (current) or "Show a `5/16` counter with icons" (arguably what the user expected)? Worth confirming before adding chrome.
