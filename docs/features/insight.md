# Insight Feature

> Status: **Planned** (branch `feature/insight`). This document is the agreed
> implementation plan and feature spec. Task breakdown lives in
> [insight-tasks.md](insight-tasks.md).

## Overview

**Insight** is a lightweight, standalone inbox for short thoughts the user captures to
follow up on or find the answer to later. Each insight is a bit of text tagged as a
**question**, **note**, or **reflection**. It lives in its own bottom tab, is fully
browsable/searchable, and has **no status/flag lifecycle** — the "review later" need is
served simply by it being a persistent, scannable list.

Users can capture insights three ways:
1. In-app **compose sheet** (a `+` button on the Insights tab).
2. A home-screen **widget** ("Add Insight").
3. An **App Intent / AppShortcut** — Siri, Spotlight, and the Shortcuts app.

### Product decisions (locked)

| Decision | Choice |
|---|---|
| Placement | New bottom tab (introduces a real `TabView`; the app has none today) |
| Lifecycle | None — no flags, no open/reviewed state |
| Association | Always standalone — never linked to `Learning` or `Reflection` |
| In-app capture | Compose sheet via `+` button |
| Widget + App Intent/AppShortcut | Yes |
| Capture path | **Direct-write via App Group** (background save, no app launch) |
| Constraint | Must NOT touch Reflection/Learning business logic; reuse shared infra; iOS 26 APIs |

## Why a dedicated App-Group store

- The "Widget extension" and "Quick Actions" are the **same** WidgetKit target
  (`Quick Actions/`), currently **deep-link only** (`Link(destination: "reflect://write")`),
  reading no data.
- **No App Group exists today.** The main `ModelContainer` (`Reflect/ReflectApp.swift`) uses
  the default store, `cloudKitDatabase: .none`. No `AppIntent`/`AppShortcut` anywhere.
- Bundle IDs: app `xyz.nandamochammad.Reflect`, widget
  `xyz.nandamochammad.Reflect.Quick-Actions`. App Group: `group.xyz.nandamochammad.Reflect`.

Because **Insight has zero relationships** to Reflection/Learning, it gets its **own
dedicated `ModelContainer`** (schema `[Insight.self]`) stored in the App Group container,
shared by the app and the widget extension. This enables background direct-write **and**
leaves the existing store completely untouched — no data migration, no coupling.

## Architecture

Three concerns:

### A) Shared Insight core — compiled into **both** targets (`Reflect` + `Quick Actions`)

New `Shared/Insight/` synchronized folder added to both targets:

- `InsightType.swift` — `enum InsightType: String, Codable, CaseIterable, Identifiable, AppEnum`
  (`question/note/reflection`; `title`, `pluralTitle`, `icon`, `colorHex`). `AppEnum`
  conformance so it is a valid App Intent parameter.
- `Insight.swift` — `@preconcurrency @Model final class Insight` (`id` unique, `text`,
  `typeRawValue` + typed `type` accessor, `createdAt`, `updatedAt`; **no relationships**).
- `InsightStore.swift` — the shared `ModelContainer` factory:
  `ModelConfiguration(schema: [Insight.self], groupContainer: .identifier("group.xyz.nandamochammad.Reflect"), cloudKitDatabase: .none)`.
  Single source of the store for app + extension.
- `CreateInsightIntent.swift` — `struct CreateInsightIntent: AppIntent` with
  `@Parameter var text: String` and `@Parameter var type: InsightType` (default `.note`);
  `openAppWhenRun = false`; `perform()` inserts into `InsightStore.container`, saves, returns
  a confirmation dialog.
- `InsightShortcuts.swift` — `struct InsightShortcuts: AppShortcutsProvider` exposing
  `CreateInsightIntent` with natural-language phrases ("Add insight to Reflect", …).

### B) In-app Insight tab — `Reflect` target only

Under `Reflect/Presentation/Features/Insight/`. **Reads** use SwiftData `@Query` against the
shared container (mirrors `LearningListView`); **writes** go through use cases (Clean
Architecture write path):

- `List/InsightDateGroup.swift` — date buckets + `group(for:)`; reuses `Date.monthYearFormatted`.
- `List/InsightListView.swift` — `NavigationStack` + grouped `List(.plain)`,
  `@Query(sort: \Insight.createdAt, order: .reverse)`, `.searchable`, type filter, `+` toolbar
  button, `EmptyStateView` (reused), swipe-to-delete, tap-to-edit, `.sheet` editor.
- `List/InsightCard.swift` — type icon + colored accent + text preview + relative time.
- `List/InsightListViewModel.swift` — `@Observable`, `@MainActor` async methods (matches
  `LearningListViewModel`): `typeFilter`/`searchQuery`, groups the queried array,
  `delete(_:)` via `DeleteInsightUseCase`.
- `Editor/InsightEditorView.swift` — compose/edit sheet: `TextEditor` + type `Picker` + Save/Cancel.
- `Editor/InsightEditorViewModel.swift` — `@Observable`, `enum Mode { case create; case edit(Insight) }`,
  `text`, `type`, `canSave`, `save() async -> Bool` via Create/Update use cases.

Repository + use cases (`Reflect` target), mirroring the `Learning` slice but backed by the
**shared** container context:

- `Reflect/Data/Repositories/Protocols/InsightRepositoryProtocol.swift`
- `Reflect/Data/Repositories/Implementations/InsightRepository.swift` — `init(modelContext:)`
  given `InsightStore.container.mainContext`.
- `Reflect/Domain/UseCases/Insight/{Create,Update,Delete,Fetch}InsightUseCase.swift`
  (+ `enum InsightError: LocalizedError`), `execute(...) async throws`, mirrors
  `CreateLearningUseCase.swift`.

### C) Widget quick-add — `Quick Actions/Quick_Actions.swift`

Add an "Add Insight" action. A widget can't host a keyboard, so it **deep-links**
`reflect://insight` to open the Insights tab with the compose sheet ready (mirrors the
existing `Link` pattern). Background direct-write is handled by the App Intent/AppShortcut
(Siri/Shortcuts/Spotlight supply the text).

## Modified shared surfaces (mostly additive)

1. `Reflect/ReflectApp.swift` — add `reflect://insight` handling in `handleWidgetURL` → route to
   the Insights tab + compose. **Do not** add `Insight` to the main `Schema` (own container).
2. `Reflect/Presentation/Features/MainTab/MainTabView.swift` — introduce a real `TabView`
   (iOS 18+/26 `Tab` API): Tab 1 "Learnings" → existing `LearningListView` (untouched);
   Tab 2 "Insights" → `InsightListView().modelContainer(InsightStore.container)`. Keep
   onboarding `.sheet` + `.badgesDidUnlock` `.fullScreenCover` at the `TabView` root. Own
   `selectedTab` state so the widget deep link can switch tabs + trigger compose.
3. `Reflect/App/DIContainer.swift` — additive `makeInsight…()` factories; repository wired to
   `InsightStore.container.mainContext`.
4. `Reflect/Core/Utilities/Constants.swift` — add `insightTextMaxLength` to `Limits`.
5. **App Group entitlements:** add `com.apple.security.application-groups` to
   `Reflect/Reflect.entitlements`; create `Quick Actions/Quick_Actions.entitlements` with the
   same group; set `CODE_SIGN_ENTITLEMENTS` for the extension.
6. `Reflect.xcodeproj/project.pbxproj` — register the `Shared/` synchronized group into both
   targets; wire extension entitlements; link `AppIntents`/`WidgetKit` as needed.

## ⚠️ Manual step (signing)

Enabling the **App Group capability** requires registration on the Apple Developer
account/provisioning. In Xcode → **Signing & Capabilities** → add **App Groups** →
`group.xyz.nandamochammad.Reflect` to **both** the `Reflect` and `Quick Actions` targets
(auto-registered with "Automatically manage signing"). Until then, device builds may fail
code-signing (Simulator builds generally still run).

## Reused infrastructure (no duplication)

`Constants` (Spacing/Colors/Limits) · `Date+Formatting` (`monthYearFormatted`,
`relativeFormatted`) · `Color(hex:)` · `EmptyStateView` · `HapticManager.shared` ·
`PrimaryButton` · the `reflect://` URL scheme + `.onOpenURL` pattern · `DIContainer.shared`.

## Risks / notes

- **Cross-process SwiftData freshness:** an insight written by the extension appears in the app
  on next `@Query` refresh; add a refresh on scene `.foreground` if staleness shows.
- **`AppEnum` for `InsightType`:** required so `type` is a valid App Intent parameter.
- **Single `AppShortcutsProvider`:** if others are added later they must be combined.

## Verification

1. **Build** (standing rule):
   ```
   xcodebuild -project Reflect.xcodeproj -scheme Reflect \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     -configuration Debug build 2>&1 | grep "error:"
   ```
   Iterate until grep is empty; confirm `** BUILD SUCCEEDED **`. Build the `Quick Actions` scheme too.
2. **Simulator:** two-tab bar; Learnings tab unchanged. Insights tab: add question/note/reflection
   via `+` sheet → grouped by date; edit text+type; filter; search; swipe-delete; relaunch → persists.
3. **App Intent/AppShortcut:** run "Add insight to Reflect" in Shortcuts with text → appears in app.
4. **Widget:** "Add Insight" opens the Insights tab compose sheet.
5. **Decoupling check:** `grep -ri "Reflection\|Learning" Shared/Insight Reflect/**/Insight*` → empty;
   main `Schema` unchanged.
6. **Commit** on `feature/insight`, staging only new `Insight`/`Shared` files + listed shared edits.
