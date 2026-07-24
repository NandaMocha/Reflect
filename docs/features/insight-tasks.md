# Insight Feature — Task Breakdown

> Planner output (by Fable) for [insight.md](insight.md), branch `feature/insight`, worktree
> `.../Repo's/Reflect/Reflect-insight`. All paths relative to that worktree root unless absolute.
> This breakdown was verified against the actual worktree and **overrides** any stale spec/CLAUDE.md
> claims — see Ground-truth corrections below.

## Ground-truth corrections (verified against the worktree)

1. **`DIContainer.shared.configure(with:)` is called nowhere in this worktree** (`feature/insight` is
   off `main`, which is behind the audio branch). Every Insight factory must be self-contained —
   wired to `InsightStore.container.mainContext` — and must never guard on the unset private
   `modelContext` (that guard `fatalError`s).
2. **`MainTabView.swift` has no `.badgesDidUnlock` `.fullScreenCover` today.** It is a thin wrapper:
   `LearningListView(widgetAction:)` + onboarding `.sheet`. There is no celebration cover to preserve.
3. **pbxproj**: `objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup`. Targets `Reflect`
   (`042635EF2F288EA100BB939D`) and `Quick ActionsExtension` (`04F2606D2F33602B00BF5E99`, bundle
   `xyz.nandamochammad.Reflect.Quick-Actions`). Only the app target sets `CODE_SIGN_ENTITLEMENTS`.
4. **Widget deep-link plumbing**: `enum WidgetAction { write, camera, voice }` at the top of
   `Reflect/ReflectApp.swift`; `handleWidgetURL` maps `url.host`; `LearningListView.handleWidgetAction`
   navigates into a Learning for **any** non-nil action — a new `.insight` case must be kept out of that path.
5. URL scheme `reflect` already registered in `Reflect/Info.plist`. Deployment target iOS 26.x.
   `Reflect/Reflect.entitlements` has aps/iCloud/journaling keys, **no App Group**.
6. `Quick Actions/Quick_Actions.swift` defines its own local `Color(hex:)`. Shared files must store
   `colorHex` as `String` and import no SwiftUI, so each target resolves its own color extension.

---

## Tickets

Legend — Executor: **Sonnet (main)** = design/judgment/cross-target; **Haiku (supporting)** = mechanical mirror.

### T1 — Create the shared Insight data core (`Shared/Insight/`) · Haiku (supporting)
- **Scope**: New top-level `Shared/Insight/` folder (sibling of `Reflect/`, `Quick Actions/`):
  - `InsightType.swift` — `enum InsightType: String, Codable, CaseIterable, Identifiable, AppEnum` (cases `question/note/reflection`; `import AppIntents`; `title`, `pluralTitle`, `icon`, `colorHex` as **String**, no SwiftUI; `typeDisplayRepresentation` + `caseDisplayRepresentations`).
  - `Insight.swift` — `@preconcurrency @Model final class Insight`, mirror `Reflect/Data/Models/Learning.swift`: `@Attribute(.unique) var id: UUID`, `text`, `typeRawValue` + computed `type` accessor (fallback `.note`), `createdAt`, `updatedAt`; memberwise init; **zero relationships**.
  - `InsightStore.swift` — `enum InsightStore` with `appGroupID = "group.xyz.nandamochammad.Reflect"` and `static let container: ModelContainer` from `ModelConfiguration(schema: Schema([Insight.self]), groupContainer: .identifier(appGroupID), cloudKitDatabase: .none)`; `fatalError` on failure.
  - **Out of scope**: pbxproj registration (T2), App Intent (T4), anything under `Reflect/`.
- **Depends on**: none
- **Acceptance**: Files exist with the exact API; no Learning/Reflection refs; no SwiftUI import; build unchanged (folder not yet in a target until T2); committed.
- **Watch-outs**: `AppEnum` needs `import AppIntents`; keep `title`/`pluralTitle` plain `String`, use `DisplayRepresentation` for AppEnum requirements.

### T2 — Register `Shared/` into both targets + App Group entitlements (pbxproj) · Sonnet (main)
- **Scope**: Edit `Reflect.xcodeproj/project.pbxproj`: (1) add a `PBXFileSystemSynchronizedRootGroup` for `Shared`; (2) add its ID to the root `PBXGroup` children; (3) add its ID to `fileSystemSynchronizedGroups` of **both** `Reflect` and `Quick ActionsExtension`; (4) entitlements — add `com.apple.security.application-groups = [group.xyz.nandamochammad.Reflect]` to `Reflect/Reflect.entitlements`, create `Quick Actions/Quick_Actions.entitlements` with the same key, set `CODE_SIGN_ENTITLEMENTS` in Debug+Release of the extension target.
  - **Out of scope**: developer-portal capability (T3, manual); any Swift.
- **Depends on**: T1
- **Acceptance**: `xcodebuild ... | grep error:` empty + `** BUILD SUCCEEDED **` (now compiles `Shared/Insight/*` into both app and appex); pbxproj diff additions-only; committed.
- **Watch-outs**: New `.entitlements` inside a synchronized folder may need a `membershipExceptions` entry so it isn't bundled as a resource; device signing may fail until T3 (simulator is the gate); generate collision-free 24-hex IDs.

### T3 — MANUAL CHECKPOINT: enable App Group capability in Xcode signing · Human (neither model)
- **Scope**: Human-only. Xcode → each target (`Reflect`, `Quick ActionsExtension`) → Signing & Capabilities → add **App Groups** → `group.xyz.nandamochammad.Reflect`.
- **Depends on**: T2
- **Acceptance**: Both targets show the App Group, no signing errors, device build signs. Does not block T4–T12 on simulator.
- **Watch-outs**: Xcode may rewrite entitlements/pbxproj — diff and reconcile into one commit afterward.

### T4 — App Intent + AppShortcuts · Sonnet (main)
- **Scope**: In `Shared/Insight/` (both targets via T2): `CreateInsightIntent.swift` (`AppIntent`, `openAppWhenRun = false`, `@Parameter text: String`, `@Parameter type: InsightType = .note`, `@MainActor perform()` inserts into `InsightStore.container.mainContext`, saves, returns dialog) and `InsightShortcuts.swift` (`AppShortcutsProvider`, phrases containing `${applicationName}`).
- **Depends on**: T1, T2
- **Acceptance**: Build green (both targets); no Learning/Reflection refs; intent visible in Shortcuts and creating one persists an `Insight`; committed.
- **Watch-outs**: `mainContext` is `@MainActor`; only ONE `AppShortcutsProvider` per app — if the appex membership causes duplicate registration, restrict the provider to the app target via `membershipExceptions` and record it.

### T5 — Insight repository (protocol + implementation) · Haiku (supporting)
- **Scope**: `Reflect/Data/Repositories/Protocols/InsightRepositoryProtocol.swift` + `.../Implementations/InsightRepository.swift`, mirroring the Learning repository: `fetchAll` (createdAt desc), `fetch(id:)`, `create`, `update` (bumps `updatedAt`), `delete`; `init(modelContext:)`.
- **Depends on**: T1, T2
- **Acceptance**: Build green; names mirror the Learning slice; no Learning/Reflection refs; committed.
- **Watch-outs**: Use `#Predicate { $0.id == id }` form.

### T6 — Insight use cases + `InsightError` + Constants limit · Haiku (supporting)
- **Scope**: `Reflect/Domain/UseCases/Insight/{Create,Update,Delete,Fetch}InsightUseCase.swift` mirroring the Learning use cases (protocol + `execute(...) async throws`); `enum InsightError: LocalizedError` (`textRequired`, `textTooLong`, `notFound`) in the Create file; add `static let insightTextMaxLength = 500` to `Constants.Limits`.
- **Depends on**: T5
- **Acceptance**: Build green; validation enforced in Create + Update; committed.
- **Watch-outs**: Propagate errors (no silent `try?`); `Update` sets `updatedAt` via the repository.

### T7 — DIContainer insight factories · Haiku (supporting)
- **Scope**: Additive `// MARK: - Insight` in `Reflect/App/DIContainer.swift`: `@MainActor func makeInsightRepository()` wired to `InsightStore.container.mainContext`, plus `@MainActor` factories for the four use cases. Do NOT guard on the private `modelContext`.
- **Depends on**: T6
- **Acceptance**: Build green; no Insight path can hit the `configure` `fatalError`; existing factories untouched; committed.
- **Watch-outs**: `mainContext` is `@MainActor` — factories must be `@MainActor`.

### T8 — Insight editor (compose/edit sheet) · Sonnet (main)
- **Scope**: `Reflect/Presentation/Features/Insight/Editor/InsightEditorViewModel.swift` (`@Observable @MainActor`, `enum Mode { create; edit(Insight) }`, `text`, `type`, `canSave`, `save() async -> Bool` via Create/Update use cases, haptics) + `InsightEditorView.swift` (`TextEditor` + counter + type `Picker` + Save/Cancel, `Constants.Spacing`, `Color(hex: type.colorHex)`); add `@MainActor func makeInsightEditorViewModel(mode:)` to `DIContainer.swift`.
- **Depends on**: T7
- **Acceptance**: Build green; both modes save via use cases (no direct `modelContext.insert` in the view); dismisses on save; committed.
- **Watch-outs**: Writes go through use cases wired to `InsightStore`, not `@Environment(\.modelContext)`.

### T9 — Insight list slice (tab content) · Sonnet (main)
- **Scope**: Under `Reflect/Presentation/Features/Insight/List/`: `InsightDateGroup.swift` (mirror `ReflectionDateGroup` + `group(for:)`), `InsightCard.swift` (tinted type icon, preview, `Date.relativeFormatted`), `InsightListViewModel.swift` (`@Observable @MainActor`; `typeFilter`, `searchQuery`, pure `groups(from:)`, `delete(_:)`), `InsightListView.swift` (`NavigationStack` + `@Query(sort: \Insight.createdAt, order: .reverse)`, grouped `List(.plain)`, `.searchable`, type-filter `Menu` + `+`, `EmptyStateView`, swipe-delete, tap→edit sheet, compose hook for the deep link); add `@MainActor func makeInsightListViewModel()` to `DIContainer.swift`.
- **Depends on**: T8
- **Acceptance**: Build green; `@Query` compiles; filter applies before grouping; delete via use case; no Learning/Reflection refs; committed.
- **Watch-outs**: `@Query` reads the environment container — only populated once T10 injects `InsightStore.container`; previews inject their own in-memory container.

### T10 — Introduce TabView + `reflect://insight` deep link (shared surfaces) · Sonnet (main)
- **Scope**: `Reflect/ReflectApp.swift` — add `.insight` to `WidgetAction` + `case "insight"` in `handleWidgetURL` (do NOT touch main `Schema`). `MainTabView.swift` — real `TabView` (iOS 18+/26 `Tab` API): Tab "Learnings" (`book.fill`) hosts unchanged `LearningListView`; Tab "Insights" (`lightbulb.fill`) hosts `InsightListView(...)` with `.modelContainer(InsightStore.container)` on that tab only; keep onboarding `.sheet`; `.onChange(of: widgetAction)` routes `.insight` → Insights tab + compose, and guard `.insight` out of `LearningListView.handleWidgetAction`.
- **Depends on**: T9
- **Acceptance**: Build green; two-tab bar; Learnings flows (state restore, write/camera/voice, onboarding) unchanged; `reflect://insight` opens Insights tab + compose; committed.
- **Watch-outs**: Adding the `WidgetAction` case breaks exhaustive switches — fix at source; `.modelContainer` wraps only the Insights tab (Learnings keeps the main container).

### T11 — Widget "Add Insight" action · Haiku (supporting)
- **Scope**: `Quick Actions/Quick_Actions.swift` only: add an `insightButton` = `Link(destination: URL(string: "reflect://insight")!)` mirroring `cameraButton`/`voiceButton` (SF Symbol `lightbulb.fill`), add to the bottom `HStack`; update the widget `description`.
- **Depends on**: T2 (buildable); functional end-to-end after T10.
- **Acceptance**: Build green; `#Preview` renders 4 actions without clipping in small+medium; committed.
- **Watch-outs**: systemSmall is tight — if clipping, shrink circle frames uniformly rather than restructuring.

### T12 — End-to-end verification, decoupling audit, polish · Sonnet (main)
- **Scope**: Run the spec Verification section: build green; simulator pass (two tabs, Learnings unchanged incl. `simctl openurl reflect://write|camera|voice`, Insights CRUD + group + filter + search + persist); `reflect://insight` → compose; Shortcuts "Add insight to Reflect" → appears in app; decoupling audit (`grep -ri` over `Shared/Insight` + `Reflect/**/*Insight*`, `Schema` diff-clean). Fix ≤10-line issues inline; escalate structural gaps to the planner.
- **Depends on**: T4, T10, T11 (T3 for device-signing checks only)
- **Acceptance**: All checks pass with evidence; per-ticket commits on `feature/insight`; no push.
- **Watch-outs**: Cross-process SwiftData staleness — if seen, add a refetch on `scenePhase == .active` in `InsightListView` (in scope). Shortcut indexing can lag on simulator — retry after reinstall before filing a bug.

---

## Suggested execution waves

| Wave | Tickets | Notes |
|---|---|---|
| 1 | T1 | Solo (new folder, zero conflicts). |
| 2 | T2 | **Serial, solo** — only ticket touching `project.pbxproj`. |
| 3 | T4 ∥ (T5→T6→T7) ∥ T11; hand **T3 to the human** now | Disjoint files. T5–T7 is a serial chain in one lane. T3 doesn't block simulator work. |
| 4 | T8 → T9 | Serial (both add a factory to `DIContainer.swift`; T9 presents T8's editor). |
| 5 | T10 | **Serial, solo** — only ticket touching `MainTabView.swift` / `ReflectApp.swift`. |
| 6 | T12 | Final gate; reconcile any late T3 entitlements diff here. |

**Shared-file locks the orchestrator must enforce**: `project.pbxproj` → T2 only (+ possible T3 human fallout);
`DIContainer.swift` → T7→T8→T9 strictly in order; `MainTabView.swift`/`ReflectApp.swift` → T10 only;
`Constants.swift` → T6 only; `Quick_Actions.swift` → T11 only.

## Review checkpoints (bring the planner back in)

1. **After T2 (before wave 3 fans out)** — verify `Shared` is in **both** targets' `fileSystemSynchronizedGroups`,
   entitlements on both, build green incl. appex. *Gap signature*: app builds but `Insight` unresolved in the
   appex → group added to only one target; cut a corrective ticket, don't duplicate files.
2. **After T7** — non-UI slice alignment: no Insight path hits the `configure` fatalError; repo/use-case naming
   mirrors Learning; zero Learning/Reflection refs. *Gap signature*: a factory guarding on `modelContext`, or the
   repository reaching into `InsightStore` instead of taking a context.
3. **After T10 (before T12)** — regression review of shared surfaces: write/camera/voice equivalent, main `Schema`
   untouched, `.insight` excluded from `LearningListView` routing, container injection scoped to the Insights tab.
   *Gap signature*: widget write action landing on Insights, or `Insight.self` in `ReflectApp`'s schema.
4. **T12 escalation rule** — anything beyond a ≤10-line fix → send the planner the evidence to cut follow-up
   tickets rather than let the executor redesign.

## Base-branch note (orchestrator)

`feature/insight` is based off `main` (`5a295bf`), which is **behind** the active audio branch. The tickets are
self-contained and decoupled, so this is safe, but before merging, rebase onto the team's integration branch
(`develop` or updated `main`) and re-run T12.
