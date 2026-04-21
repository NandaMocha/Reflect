# Achievement Counter — Root Cause (the real one)

**Date**: 2026-04-21
**Branch**: `fix/achievement-counter`
**Scope**: Why `BadgeGridView.achievementCountHeader` still shows an unchanged `totalUnlocked` after a reflection is created — despite all the fixes in commits `8359133`, `25a9749`, `03cba6f`, `2b45b8e`, `0ed0a3a`, `7003d96`.

## TL;DR

**`ReflectionEditorViewModel` is an orphaned class.** `ReflectionEditorView` — the actual view that ships in the app — holds its own `@State` for every field and saves by calling `modelContext.insert(reflection); try modelContext.save()` directly. It never instantiates or talks to `ReflectionEditorViewModel`, so `CreateReflectionUseCase` / `UpdateReflectionUseCase` / `EvaluateBadgesUseCase` **never run in production code paths**. The badge-evaluation pipeline has been disconnected from the user flow since at least commit `ea9f734` ("integrate evaluation use case in view model"), which fixed the VM but didn't wire the view to it.

Every achievement-system commit on this branch — including the two just landed (`0ed0a3a`, `7003d96`) — has been **patching dead code**.

## Resolved

**Option B landed in commit `133ceb0`.** The view now owns a `ReflectionEditorViewModel` via `@State` and delegates save to it. `CreateReflectionUseCase` / `UpdateReflectionUseCase` run on every create and edit, followed by `EvaluateBadgesUseCase`. Badge notifications fire, `BadgeGridView.achievementCountHeader` updates, and the celebration overlay now shows when a badge unlocks.

Also fixed along the way (latent bugs the root-cause trace exposed):
- `DIContainer.shared.configure(with:)` was never called anywhere in the app, so every factory would have fatalError'd. `ReflectApp.init` now configures it on the main context.
- The view's `isValid` had an operator-precedence bug that let saves pass without a learning selected when voice recordings existed. Fixed in both the view and the VM.
- `UpdateReflectionUseCase` was missing video handling. Rewritten to reconcile images/videos/voice uniformly.
- `CapturedLocation` was defined in the Presentation layer and referenced from a Domain input — layer violation. Moved to Domain.

Open follow-up (documented but not blocking the counter): migrate the view's form `@State` fields onto the VM so bindings flow through `$viewModel.title` etc. directly, and remove the copy-over bridge in `ReflectionEditorView+Save.swift`.

## Evidence

### The view never uses the VM

[`ReflectionEditorView.swift:1-56`](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView.swift):

```swift
struct ReflectionEditorView: View {
    let mode: ReflectionEditorMode
    var preselectedLearning: Learning?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Learning.sortOrder) var learnings: [Learning]

    // Form State
    @State var title = ""
    @State var content = ""
    @State var selectedLearning: Learning?
    @State var images: [ImageInput] = []
    …
    @State var showCelebration = false
    @State var celebrationTrigger: BadgeUnlockEvent.CelebrationTrigger = .none
```

No `@State var viewModel`. No `@Bindable`. No `makeReflectionEditorViewModel()` call. The view owns 30+ `@State` fields and 1 `@Environment(\.modelContext)` — that's its entire state model.

### The view saves directly to SwiftData, bypassing the use case

[`ReflectionEditorView+SaveLogic.swift:121-123`](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView+SaveLogic.swift) — the create path:

```swift
modelContext.insert(reflection)
try modelContext.save()
```

[`ReflectionEditorView+SaveLogic.swift:249`](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView+SaveLogic.swift) — the update path:

```swift
try modelContext.save()
```

No `createUseCase.execute(...)`. No `updateUseCase.execute(...)`. No badge evaluation. No `.badgesDidUnlock` / `.badgeProgressDidUpdate` notifications posted.

### `ReflectionEditorViewModel` has zero inbound callers

```
$ grep -rn "ReflectionEditorViewModel" Reflect/Presentation
# Hits: only the class definition, its own extensions, and DIContainer.makeReflectionEditorViewModel
# No `@State var viewModel: ReflectionEditorViewModel`
# No `= ReflectionEditorViewModel(...)` at a call site
# No DIContainer.shared.makeReflectionEditorViewModel() invocation
```

The factory [`DIContainer.swift:172`](../../Reflect/App/DIContainer.swift) exists but is never called. The VM's own [`+SaveLogic.swift`](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel+SaveLogic.swift) defines `save()` that calls `createUseCase.execute` and `updateUseCase.execute` — **these methods on the VM are themselves dead**.

### The parallel save logic

There are **two** save implementations with the same shape:

| File | Type | Uses |
|---|---|---|
| `ReflectionEditorViewModel+SaveLogic.swift:7-72` | `extension ReflectionEditorViewModel` | Calls `createUseCase.execute` / `updateUseCase.execute` (correct, but dead code) |
| `ReflectionEditorView+SaveLogic.swift:8-308` | `extension ReflectionEditorView` | Calls `modelContext.insert` / `modelContext.save()` directly (live code, but bypasses use cases) |

The ViewModel extension was likely the intended target of the MVVM refactor. The View extension is what actually runs.

### Historical trace

`git show --stat ea9f734` ("Fix achievement counter - integrate evaluation use case in view model") touched:

- `ReflectionEditorViewModel.swift` — wired `evaluateBadgesUseCase` into the VM's inline graph
- `LearningListView.swift`, `ReflectionListView.swift`, `SettingsView.swift`, `ReflectApp.swift`
- **Not** `ReflectionEditorView.swift` or `ReflectionEditorView+SaveLogic.swift`

The commit name claims integration, but only the VM side was touched. The view continued to save directly. The bug has been latent ever since.

## Why every earlier "fix" looked like it worked in code but didn't in the app

| Fix | Commit | What it touched | What the app runs |
|---|---|---|---|
| `previousTotal` category filter | `8359133` | `EvaluateBadgesUseCase.swift` | `modelContext.save()` — never calls EvaluateBadgesUseCase |
| `@MainActor` on BadgeGridViewModel | `8359133` | `BadgeGridViewModel.swift` | BadgeGridView reads correctly; the VM has nothing to show because data never changes |
| Remove `print()` / log via Logger | `25a9749` | `EvaluateBadgesUseCase.swift` | Still never called |
| Predicate-based counts | `03cba6f` | `EvaluateBadgesUseCase.swift` | Still never called |
| Dead init + merge onReceive | `2b45b8e` | BadgeGridView/VM | Correct but the notifications never fire |
| Update-path badge eval | `0ed0a3a` | `UpdateReflectionUseCase.swift`, VM init, DI, VM save logic | `ReflectionEditorView` never calls the VM's update path |
| Celebration subscription on VM | `7003d96` | `ReflectionEditorViewModel.swift` | VM is never instantiated — observer is never installed |

Every commit is correct in isolation. Every commit is dead on arrival in the running app.

## What the user actually sees

Step-by-step trace for "create a reflection → counter doesn't update":

1. User taps New Reflection → SwiftUI presents `ReflectionEditorView`.
2. User fills out the form. State lives in the view's `@State`.
3. User taps Save → `ReflectionEditorView+SaveLogic.save()` runs.
4. `createReflection()` builds a `Reflection` model, appends images/videos/voice, does `modelContext.insert(reflection)` and `modelContext.save()`.
5. `NotificationCenter.default.post(name: .init("ReflectionDidSave"), object: nil)` fires at line 47 — but this is a different notification, not `.badgesDidUnlock` / `.badgeProgressDidUpdate`.
6. View dismisses.
7. `LearningListView` observes `.badgeProgressDidUpdate` — never posted. Its `badges` state remains stale. The icon strip doesn't change.
8. User opens the achievements sheet → `BadgeGridView.task` fires → `viewModel.loadBadges()` → `BadgeRepository.fetchAll()` → all 16 badges with `isUnlocked=false, unlockedCount=0` (their initial state from `initializeBadges` at app launch).
9. `totalUnlocked = badges.filter { $0.isUnlocked }.count = 0`.
10. `achievementCountHeader` renders `Text("0")`. **This is what the user sees.**

The counter is **correctly reflecting the database**, which has not been updated because nothing ran the evaluation.

## The fix — two options

### Option A — Minimal: call the use case from the view

Cheapest path to working counters. Inside [`ReflectionEditorView+SaveLogic.swift`](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView+SaveLogic.swift), after each `modelContext.save()`:

```swift
let evaluateBadgesUseCase = EvaluateBadgesUseCase(
    badgeRepository: BadgeRepository(modelContext: modelContext)
)
let unlocked = try? await evaluateBadgesUseCase.execute(
    input: EvaluateBadgesInput(modelContext: modelContext, newReflection: reflection)
)
if let unlocked, !unlocked.isEmpty {
    NotificationCenter.default.post(name: .badgesDidUnlock, object: unlocked)
    celebrationTrigger = headlineBadge(from: unlocked).celebration
    showCelebration = true
}
NotificationCenter.default.post(name: .badgeProgressDidUpdate, object: nil)
```

Pros: one-file change, immediately unblocks the counter. Keeps the existing direct-save structure of the view.
Cons: duplicates the notification-posting logic that already exists in `CreateReflectionUseCase` / `UpdateReflectionUseCase`. The use-case layer remains dead. Architecture drift continues.

### Option B — Proper: wire the view to the ViewModel

The MVVM refactor the original author intended. Convert `ReflectionEditorView` to a `@State`-owned `ReflectionEditorViewModel`, drop the view's `@State` form fields (they now live on the VM), and call `viewModel.save()` from the toolbar. Delete `ReflectionEditorView+SaveLogic.swift` in favor of the VM's `+SaveLogic.swift`. The celebration state moves from the view's `@State` to the VM's `@Observable` properties (binding via `$viewModel.showCelebration` in the celebration modifier).

Pros: fixes the counter *and* restores the architecture. Removes ~300 lines of duplicated save logic in the view extension. Future evaluation additions (e.g. new badge types) happen in the use case, once.
Cons: larger change touching many files and all the view's form inputs. Needs manual UI verification — the editor is the most-interacted-with screen in the app. High reward, medium risk.

## Recommendation

Go with **Option A now** to unblock users, then schedule **Option B** as a follow-up. The incremental cost of A is small and it gets the counter working this turn; B is a proper refactor that deserves its own PR and simulator testing.

## Other things this explains

- **Why `LearningListView`'s icon strip doesn't update either**: same root cause — no notifications fire, its `loadBadges()` only re-runs on `.onAppear`, so the icons only update on full tab switches.
- **Why the celebration modifier never fires**: `showCelebration` on the view is only written by `CelebrationView.swift:45` (its internal state) and the example comment in `CelebrationModifier.swift:79`. Nothing in the real save path writes it.
- **Why `CreateReflectionUseCase`'s two recent historical fixes** (`0ad9793`, `ea9f734`) didn't durably fix things: they assumed the VM was in the call path. It wasn't.

## Follow-ups (captured for separate tasks)

- Once the view is wired to a VM (Option B), `ReflectionEditorView+SaveLogic.swift` should be deleted outright — it's a 308-line duplicate.
- `DIContainer.makeReflectionEditorViewModel` currently has zero callers; it becomes the correct instantiation point after the refactor.
- The orphaned VM tells us tests would have caught this immediately. Reinforces the pending H3 finding in the first review (add a test target).
