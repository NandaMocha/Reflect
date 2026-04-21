# Achievement Counter — Code Review

**Date**: 2026-04-21
**Branch**: `fix/achievement-counter`
**Scope**: The "achievement counter" — the feature that tallies how many badges a user has unlocked and drives the Achievements screen.

This review is **analysis only**. No code was changed in this pass.

## Files reviewed

- [Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift](../../Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift)
- [Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift](../../Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift)
- [Reflect/Services/Achievement/BadgeEvaluationService.swift](../../Reflect/Services/Achievement/BadgeEvaluationService.swift)
- [Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridView.swift)
- [Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift](../../Reflect/Presentation/Features/Achievement/Badges/BadgeGridViewModel.swift)
- [Reflect/Data/Models/Badge.swift](../../Reflect/Data/Models/Badge.swift), [BadgeID.swift](../../Reflect/Data/Models/BadgeID.swift), [MonthlyAchievement.swift](../../Reflect/Data/Models/MonthlyAchievement.swift)
- [Reflect/Data/Repositories/Implementations/BadgeRepository.swift](../../Reflect/Data/Repositories/Implementations/BadgeRepository.swift)
- [Reflect/App/DIContainer.swift](../../Reflect/App/DIContainer.swift)

## Current architecture (how the counter actually works today)

1. Reflection is created → [`CreateReflectionUseCase`](../../Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift) saves, then if `evaluateBadgesUseCase != nil`, calls it (lines 76–92).
2. [`EvaluateBadgesUseCase.execute`](../../Reflect/Domain/UseCases/Achievement/EvaluateBadgesUseCase.swift) runs five phases: count queries → milestone eval → special-achievement checks → progress write-back for *all* badges → unlock newly-earned badges.
3. `CreateReflectionUseCase` posts `.badgesDidUnlock` (if any newly unlocked) and `.badgeProgressDidUpdate` (always).
4. `BadgeGridView.onReceive(...)` fires `viewModel.loadBadges()` on either notification.
5. `BadgeGridViewModel.loadBadges()` does `badgeRepository.fetchAll()`, assigns `badges`, and the `@Observable` macro triggers a re-render.
6. `viewModel.totalUnlocked` is computed as `badges.filter { $0.isUnlocked }.count` and drives the big `"\(totalUnlocked)"` Text at the top of the grid.

**Concurrency**: `loadBadges()` is `async`; the ViewModel has **no** `@MainActor` annotation.
**Persistence**: SwiftData. All counts come from SwiftData queries at evaluation time.

---

## Findings

Ordered by severity. "File:line" references are against the code at the time of review.

### 🔴 High

#### H1. `previousTotal` picks the wrong badge's count
**File**: `EvaluateBadgesUseCase.swift:35`
```swift
let previousTotal = allBadges.first(where: { BadgeID(rawValue: $0.id) != nil })?.unlockedCount ?? 0
```

The filter accepts *any* badge with a valid `BadgeID` — regardless of whether it's a reflection, media, prompt, or special badge. Since `updateBadgeProgress` (run at the end of the prior evaluation) sets each badge's `unlockedCount` to the count for *its* category, `previousTotal` can end up holding the media count or the prompt count, not the reflection total.

The analogous lines for media (line 45) and prompt (line 53) correctly filter by `.badgeCategory`. Line 35 is an inconsistency.

**User-visible effect**: reflection-milestone badges may unlock late (if a media badge's count is higher than the previous reflection total) or too early (if lower), depending on which badge happens to be first in `allBadges`. The order from SwiftData isn't specified, so this is non-deterministic.

**Fix**:
```swift
let previousTotal = allBadges
    .first(where: { BadgeID(rawValue: $0.id)?.badgeCategory == .reflections })?
    .unlockedCount ?? 0
```

Same pattern as the media (line 45) and prompt (line 53) lookups — consistent and correct.

---

#### H2. ViewModel missing `@MainActor`
**File**: `BadgeGridViewModel.swift:5-6`
```swift
@Observable
final class BadgeGridViewModel {
```

The VM drives UI (`badges`, `isLoading`, `errorMessage` are observed by SwiftUI) but is not constrained to the main actor. `loadBadges()` is `async` — depending on the calling context, the mutations at lines 77, 81, 83, 86 run on whatever actor suspended last. This can cause:

- Dropped animations / delayed renders (SwiftUI expects observable writes on main)
- Data-race warnings under Swift 6 strict concurrency
- Unpredictable ordering of `isLoading` transitions

Conventions in [architecture.md](../architecture.md#mainactor) already state that UI-driving ViewModels should be `@MainActor`. This one missed the rule.

**Fix**: `@MainActor final class BadgeGridViewModel`.

---

#### H3. No test coverage
No test target exists in the Xcode project. The achievement system is the most rule-heavy part of the codebase — milestone crossings, special-badge gates, Perfectionist's monthly logic — and all of it is tested manually by creating reflections.

This isn't a "style" issue; it's why the recent "achievement counter not updating" bug (commit `0ad9793`) wasn't caught automatically, and why H1 above went unnoticed until read carefully.

**Follow-up**: create a `ReflectTests` target using **Swift Testing** (not XCTest — see [conventions.md](../conventions.md#testing-when-the-target-exists)). Highest-value targets to test first: `BadgeEvaluationService` (pure — no SwiftData dependency), then `EvaluateBadgesUseCase` with an in-memory `ModelContainer`.

---

### 🟡 Medium

#### M1. Inefficient `getMediaReflectionCount` / `getPromptReflectionCount`
**File**: `EvaluateBadgesUseCase.swift:237-243` and `245-249`
```swift
private func getMediaReflectionCount(_ modelContext: ModelContext) async -> Int {
    let descriptor = FetchDescriptor<Reflection>()
    let reflections = (try? modelContext.fetch(descriptor)) ?? []
    return reflections.filter { reflection in
        !reflection.images.isEmpty || !reflection.videos.isEmpty || !reflection.voiceRecordings.isEmpty
    }.count
}
```

Fetches **all** reflections into memory, decodes each one, then filters. For a user with thousands of reflections, this becomes expensive, and it runs on every single reflection save.

`getTotalReflectionCount` (line 232) already does the right thing: `fetchCount(descriptor)` which runs a SQL `COUNT(*)` and never materializes the objects.

**Fix**: use `FetchDescriptor<Reflection>(predicate: #Predicate { … })` + `fetchCount`:

```swift
private func getMediaReflectionCount(_ modelContext: ModelContext) async -> Int {
    let descriptor = FetchDescriptor<Reflection>(
        predicate: #Predicate<Reflection> {
            !$0.images.isEmpty || !$0.videos.isEmpty || !$0.voiceRecordings.isEmpty
        }
    )
    return (try? modelContext.fetchCount(descriptor)) ?? 0
}
```

Same treatment for `getPromptReflectionCount` with `predicate: #Predicate { $0.promptID != nil }`.

---

#### M2. `print()` debug statements in production
**File**: `EvaluateBadgesUseCase.swift:156-160, 183, 188, 199, 206-207`

Lines like `print("🔄 Updating badge progress:")` and `print("🏆 UNLOCKING: \(existingBadge.name)")` ship to production. They bloat console output (the evaluation runs on every reflection save), provide no filtering, and aren't captured by Console.app in a useful way.

**Fix**: use `Logger` from `os`:

```swift
import os
private let log = Logger(subsystem: "com.reflectlearn.app", category: "BadgeEvaluation")
// …
log.debug("Updating badge progress: reflections=\(totalReflections), media=\(mediaCount), prompts=\(promptCount)")
```

Or, if the team simply doesn't want them anymore, delete them. They were useful for debugging the "not updating" bug but the bug is fixed.

---

#### M3. Silenced save errors
**File**: `EvaluateBadgesUseCase.swift:187, 214, 266`

Three places use `try? modelContext.save()`, which swallows the error. If a save fails (schema migration issue, disk full, conflict), the evaluation appears to succeed but progress isn't persisted — and the user never sees a complaint.

**Fix**: at minimum, log the error:

```swift
do { try modelContext.save() }
catch { log.error("Badge save failed: \(error.localizedDescription)") }
```

Ideally, `execute` should be marked `throws` all the way up and `CreateReflectionUseCase` should decide whether a save failure should poison the whole reflection creation flow. My call: no — a reflection creation should still succeed even if badge bookkeeping fails. Log + continue is appropriate.

---

#### M4. `@State` wrapping a parent-injected `@Observable` is fragile
**File**: `BadgeGridView.swift:5-11`
```swift
struct BadgeGridView: View {
    @State private var viewModel: BadgeGridViewModel
    …
    init(viewModel: BadgeGridViewModel, …) {
        self._viewModel = State(initialValue: viewModel)
```

`@State` takes the `initialValue` the *first* time the view is installed and ignores subsequent changes. If the parent creates a new `BadgeGridViewModel` on its own redraw and re-injects, the child keeps the stale VM. With `@Observable` this is usually fine (the observed state is the VM's internals, not the VM reference), but the pattern is a foot-gun — a future change to the parent could break achievement loading in non-obvious ways.

**Two cleaner options**:

1. **Parent owns the VM as `@State`, child binds to the reference**:
   ```swift
   // Child
   @Bindable var viewModel: BadgeGridViewModel
   init(viewModel: BadgeGridViewModel) { self.viewModel = viewModel }
   ```
   Then the VM lifetime is clearly the parent's.

2. **Child creates its own VM from environment**:
   ```swift
   @Environment(\.modelContext) private var modelContext
   @State private var viewModel: BadgeGridViewModel?
   // lazily initialize in .task
   ```
   Better if the VM is logically view-owned.

Pick (1) if achievements need to survive parent-scoped state; pick (2) if the VM's lifetime naturally matches the view.

---

#### M5. Redundant `.filter { $0.isUnlocked }` across computed properties
**File**: `BadgeGridViewModel.swift:15-39, 50-52`

`unlockedBadges`, `latestAchievement`, and `totalUnlocked` each re-filter the full `badges` array. The sorted `sortedAchievements` in the *view* re-filters too (BadgeGridView.swift:130-148). At 18 badges this is irrelevant; at 1000 it would matter — but mostly it's just duplicated logic. A single computed `unlockedSorted` / `locked` pair, cached on assignment, would be cleaner.

**Fix**: compute once when `badges` is set, or memoize with a lazy wrapper.

---

### 🟢 Low

#### L1. Dead initializer
**File**: `BadgeGridViewModel.swift:68-72`
```swift
init(badgeRepository: BadgeRepositoryProtocol) {
    fatalError("Use init(modelContext:) instead")
}
```
An init that only crashes serves no purpose. Delete it.

---

#### L2. `EvaluateBadgesUseCase.execute` does too much
**File**: `EvaluateBadgesUseCase.swift:25-86`

Five responsibilities in one method (count, evaluate milestones, check special, update progress, unlock). Not a bug, but splitting into `collectCounts() → evaluate(counts:) → persist(evaluation:)` would make each step individually testable. Worth doing once the test target exists.

---

#### L3. Two `onReceive` blocks with identical handlers
**File**: `BadgeGridView.swift:30-39`
```swift
.onReceive(NotificationCenter.default.publisher(for: .badgeProgressDidUpdate)) { _ in
    Task { await viewModel.loadBadges() }
}
.onReceive(NotificationCenter.default.publisher(for: .badgesDidUnlock)) { _ in
    Task { await viewModel.loadBadges() }
}
```
Can be merged with `Publishers.Merge` if you prefer, but this is fine as-is — only flagging because the duplication invites someone to change one and forget the other.

---

#### L4. ~~Perfectionist unlock gate contradicts "repeatable" intent~~ — RESOLVED (2026-04-21)

Product decision: the Perfectionist badge was removed entirely (along with Monthly Champion), because the team wants achievements based strictly on lifetime totals, not monthly cadence. See [streak-docs-vs-implementation.md](./streak-docs-vs-implementation.md) for context.

This finding is closed — the code at `EvaluateBadgesUseCase.swift:136-141` no longer exists.

---

## Recommended fix order

Group by effort and risk. Each group is a small PR.

| # | PR | Contains | Risk |
|---|---|---|---|
| 1 | **Correctness: previousTotal bug** | H1 | Low — one-line change, matches existing pattern |
| 2 | **Concurrency: @MainActor** | H2 | Low — compiler will flag any resulting issues |
| 3 | **Noise: logger + silenced errors** | M2 + M3 | Very low |
| 4 | **Perf: predicate-based counts** | M1 | Low — well-scoped |
| 5 | **Cleanup: dead init, onReceive merge** | L1 + L3 | Trivial |
| ~~6~~ | ~~**Perfectionist decision**~~ | ~~L4~~ | Resolved — badge removed 2026-04-21 |
| 7 | **VM lifetime refactor** | M4 | Medium — touches parent & child; gate behind manual UI test |
| 8 | **Tests target + first tests** | H3 | Medium setup, low ongoing |
| 9 | **Execute refactor** | L2 | Defer until #8 lands, then this becomes straightforward |

## Follow-ups beyond this review

- Add a `ReflectTests` target with Swift Testing. First suite: `BadgeEvaluationServiceTests` (pure functions, no SwiftData). Next: `EvaluateBadgesUseCaseTests` using an in-memory `ModelContainer`.
- Introduce a single `Logger` category for achievement code so debug output can be filtered in Console.app without needing to grep `print` statements.
- Consider moving `evaluateBadgesUseCase` from an optional parameter in `CreateReflectionUseCase` (currently `Protocol? = nil`, line 12) to a required one now that `DIContainer` always wires it. The optional was likely a migration scaffold.
