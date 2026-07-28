# Performance & Glitch Review

> Static analysis only — no code was changed. Focus: list/card rendering, SwiftData fetch
> efficiency, concurrency, and SwiftUI glitches in the high-traffic surfaces (Reflection list,
> Insight list, Learnings list, shared `EntryCard`, media/celebration).
> Date: 2026-07-28. Reviewer pass over `develop`.

Each finding: **severity** (P0 breaks/janks visibly · P1 noticeable · P2 minor), file:line,
what's wrong + user-visible symptom, and a concrete fix with rough effort (S/M/L). Ranked
most-impactful first.

---

## Quick wins (P1/P2, effort S — knock these out fast)

1. **Remove the `os_log` PERF instrumentation from the reflection load path** — runs on every
   list load. `ReflectionListViewModel+DataLoading.swift:11-33`, `+Grouping.swift:12-45`. (F10)
2. **Kill the double reload after a quick-action save** — handlers both `await loadReflections()`
   *and* post `.reflectionDidSave` (which reloads again). `ReflectionListView.swift:271-274,
   326-329, 373-377` + `onReceive` at `134-139`. (F6)
3. **Scope / drop `.animation(value: navigationPath.count)`** applied to the whole
   `NavigationStack`. `LearningListView.swift:111-112`. (F7)
4. **Generate confetti particle params once, not in computed body props** — currently re-randomised
   every body eval. `ConfettiView.swift:38-69`. (F8)
5. **Collapse the LearningCard row to a single `NavigationLink(value:)`** — drop the
   zero-opacity hidden link + empty-action Button. `LearningListView.swift:216-239`. (F9)
6. **Skip the redundant in-memory re-sort** for `.newestFirst` (store already returns it sorted).
   `SearchReflectionsUseCase.swift:56-74`. (F11)

---

## Findings (ranked)

### F1 — Thumbnail decoded from disk on the main thread, per row, every recompute  [P1, borderline P0]

**Files**
- `Reflect/Data/Models/ImageAttachment.swift:39-42` — `var thumbnail: UIImage? { UIImage(data: thumbnailData) }` (no cache)
- `Reflect/Data/Models/Reflection.swift:89-94` — `firstThumbnailImage` → `firstImage?.thumbnail`
- `Reflect/Data/Models/Reflection.swift:69-71` — `firstImage` does `images.sorted{…}.first`
- `Reflect/Presentation/Components/Cards/ReflectionCard.swift:18` — calls `reflection.firstThumbnailImage` in `body`
- `EntryCard.swift:137-143` renders the resulting `UIImage`

**What's wrong.** `thumbnailData` is `@Attribute(.externalStorage)`, so it lives in a sidecar file
on disk. Every time a `ReflectionCard` body evaluates, it: (a) faults the `images` relationship,
(b) `sorted{}` the whole array to pick the first, (c) faults `thumbnailData` in from external
storage, and (d) runs `UIImage(data:)` — all synchronously on the main actor, with **no caching**.
`List` rebuilds each row as it scrolls into view (and again on any state change), so this repeats
per row on every scroll pass.

**Symptom.** Visible stutter / dropped frames when scrolling a reflection list that contains image
or video thumbnails; worse on older devices and larger thumbnails.

**Fix.** Decode off the main thread and cache the decoded `UIImage` keyed by the attachment's
`id` (an `NSCache<NSUUID, UIImage>` alongside the existing `ImageProcessingService` cache).
Have `ReflectionCard` show a placeholder and load the thumbnail via `.task(id: reflection.id)`
that reads the cache or decodes in a detached task. Also replace `images.sorted{}.first` with a
`min(by:)` (no full sort). Effort **M**.

---

### F2 — `LearningCard` faults the entire `reflections` relationship just to show a count  [P1]

**Files**
- `Reflect/Data/Models/Learning.swift:38-40` — `var reflectionCount: Int { reflections.count }`
- `Reflect/Presentation/Components/Cards/LearningCard.swift:28` — `Text("\(learning.reflectionCount) reflections")`
- (same anti-pattern in the delete alert: `LearningListView.swift:99` reads `$0.reflections.count`)

**What's wrong.** Reading `reflections.count` on a to-many SwiftData relationship materialises the
whole array of `Reflection` objects for that learning. This happens per card, on the main actor,
on the landing tab (Learnings). With several learnings each holding many reflections, opening or
scrolling the Learnings list faults a large object graph up front.

**Symptom.** Hitch when the Learnings tab appears / scrolls; grows with the number of reflections.

**Fix.** Compute counts once per list load in the ViewModel with `modelContext.fetchCount(
FetchDescriptor<Reflection>(predicate: #Predicate { $0.learning?.id == learningId }))`, or keep a
denormalised counter on `Learning` updated by the create/delete/move use cases. Pass the count into
`LearningCard` instead of reading the relationship in `body`. Effort **M**.

---

### F3 — Insight list re-filters + re-groups the whole set on every render, twice, with no debounce  [P1]

**Files**
- `Reflect/Presentation/Features/Insight/List/InsightListView.swift:21-23` — `groupedInsights`
  is a computed property, evaluated at `:31` (`groupedInsights.isEmpty`) **and** again inside
  `insightList` at `:130` (`ForEach(groupedInsights…)`) → two full passes per body.
- `InsightListViewModel.swift:46-78` — `filteredAndGrouped` filters, buckets, `sorted{}` each
  bucket, then `sorted{}` the groups: O(n log n).
- `InsightDateGroup.swift:20-41` — `group(for:)` recomputes `startOfDay(Date())` and several
  `calendar.date(byAdding:)` calls **per insight** inside the loop.
- `InsightListView.swift:55` — `.searchable(text: $viewModel.searchQuery)` with **no debounce**
  (the reflection list debounces 300ms; insights do not).

**What's wrong.** `@Query` loads all insights; then on every SwiftUI invalidation — including every
keystroke in the search field — the full filter/group/sort runs twice on the main thread, and the
date-bucketing does redundant Calendar arithmetic for each item.

**Symptom.** Laggy typing in Insight search and increasingly janky scroll as the insight count
grows.

**Fix.** (1) Compute the grouped result **once** per body into a `let` and reuse it for both the
empty-check and the `ForEach`. (2) Hoist `today` and the week/month boundaries out of the per-item
loop. (3) Debounce search and/or cache the grouped output keyed by
`(insights.count, searchQuery, typeFilter, followUpFilter)` so an unrelated re-render doesn't
recompute. Buckets are already sorted by `createdAt` from the query — the per-bucket re-sort at
`:75` is redundant. Effort **M**.

---

### F4 — Reflection list is silently capped at 50 items with no pagination  [P1, correctness/UX]

**Files**
- `Reflect/Domain/Entities/SearchFilters.swift:9-10` — `var limit: Int = 50`, `var offset: Int = 0`
- `Reflect/Presentation/Features/Reflection/List/ReflectionListViewModel+Filtering.swift:36-43` —
  `buildFilters()` constructs `SearchFilters(query:learningId:favoritesOnly:sortOption:)` and never
  overrides `limit`/`offset`, so every fetch uses the default `limit = 50, offset = 0`.
- `ReflectionListViewModel+DataLoading.swift:20` — `reflections = try await …execute(filters:)`
  **replaces** the array (no append), and nothing increments `offset` / triggers a "load more".

**What's wrong.** The repository fetch applies `fetchLimit = 50`. Only the 50 newest reflections
(per learning, or globally in "All Reflections") are ever loaded, and there is no infinite-scroll
trigger to page in the rest.

**Symptom.** For any learning with more than 50 reflections, older ones are invisible with no way to
reach them — data appears lost. (The date sections silently stop.)

**Fix.** Either remove the cap for this screen (pass `limit: nil` / a large limit and fetch all),
or implement offset pagination: bump `offset` and append when the last row appears
(`.onAppear` on the final `ReflectionCard`). If you keep a cap, add a visible "showing newest 50"
affordance. Effort **M**.

---

### F5 — Quick-action video import loads + saves a large blob on the main actor  [P1]

**Files**
- `Reflect/Presentation/Features/Reflection/List/ReflectionListView.swift:283-335`
  (`handleVideoPicked`, `@MainActor`) — `:301` `Data(contentsOf: url)` reads the entire video into
  memory, `:307` `jpegData` for the thumbnail, `:322-323` `modelContext.insert` + `save()`.
- Same shape (save of a large blob on main) in `handlePhotoPicked:267-268` and
  `handleVoiceRecording:369-371`, though those already compress off-main first.

**What's wrong.** The whole video file is read synchronously into `Data` on the main actor, then
persisted on the main actor. Videos can be tens of MB; the read + the `save()` that writes the blob
to external storage both block UI.

**Symptom.** Freeze/hitch after picking a video from the FAB / camera quick-action, right before
the list refreshes.

**Fix.** Move `Data(contentsOf:)` and blob preparation into a detached task (or hand the URL to the
repository and let it stage the file off-main), keeping only the lightweight model wiring on the
main actor. Prefer routing quick-action saves through the same `CreateReflectionUseCase` /
repository path the editor uses rather than inserting into `modelContext` inline. Effort **M**.

---

### F6 — Every quick-action save reloads the list twice  [P2]

**Files** `ReflectionListView.swift:271-274, 326-329, 373-377` (each handler calls
`await viewModel?.loadReflections()`) **and** posts `.reflectionDidSave` at `:271, :326, :374`,
which the same view observes at `:134-139` and reloads again.

**Symptom.** Two full fetch + group cycles per quick save (extra main-thread work, a possible
double flash of the list). **Fix.** Pick one path — either reload directly or rely on the
notification, not both. Effort **S**.

---

### F7 — `.animation(value: navigationPath.count)` on the whole NavigationStack + tab-bar toggle  [P2]

**Files** `LearningListView.swift:111-112`:
```
.toolbar(navigationPath.count >= 2 ? .hidden : .automatic, for: .tabBar)
.animation(.easeInOut(duration: 0.3), value: navigationPath.count)
```

**What's wrong.** An implicit animation scoped to the entire stack and keyed on navigation depth.
It animates the tab-bar hide/show (already transitioned by the system) and can bleed into unrelated
content on push/pop. Worse, `restoreState()` (`:183-198`) appends to `navigationPath` in
`onAppear`, so the cold-launch auto-open of the last learning animates a spurious push.

**Symptom.** Janky tab-bar slide and an unexpected animated auto-push on launch / when returning to
the tab. **Fix.** Drop the blanket `.animation` (let the toolbar transition itself), or narrow it to
the tab-bar visibility. Perform the restore append inside `withTransaction` with animations
disabled. Effort **S**.

---

### F8 — Confetti particle properties are randomised inside computed body props  [P2]

**Files** `ConfettiView.swift:38-59` (`color`, `rotation`, `duration`, `delay` as computed vars
using `random`) and `:66-69` (`x` offset uses `CGFloat.random` directly in `body`).

**What's wrong.** Because these are recomputed on each body evaluation, a particle's colour,
rotation, and horizontal position can change between renders instead of being stable for its
lifetime. 50 particles each re-roll.

**Symptom.** Particles can flicker / jump / recolour mid-celebration. **Fix.** Compute each
particle's params once (e.g. a `let particles: [ParticleSpec]` built in `init` or seeded `@State`)
and read them; don't call `random` in `body`. Effort **S**.

---

### F9 — Hidden zero-opacity NavigationLink layered under an empty-action Button per row  [P2]

**Files** `LearningListView.swift:216-239`:
```
ZStack {
    NavigationLink(value: learning) { EmptyView() }.opacity(0)
    LearningCard(learning: learning) {}   // Button with empty action
}
```
Plus `.standardSwipeActions` and `.standardContextMenu` on the same row.

**What's wrong.** A legacy pre-iOS-16 pattern: two overlapping hit targets (a hidden link and a
Button whose action is a no-op), which is fragile with the row's context menu / swipe actions and
adds a redundant Button per row.

**Symptom.** Occasional mis-fires between tap-to-navigate and the context menu; unnecessary view
overhead per row. **Fix.** Make the row a single `NavigationLink(value: learning) { LearningCard(…) }`
(card rendered as pure content, `.buttonStyle(.plain)`), dropping the hidden link and the empty
Button — matching how the Reflection list already wraps `ReflectionCard`. Effort **S**.

---

### F10 — Debug `os_log` PERF instrumentation left in the hot load path  [P2]

**Files** `ReflectionListViewModel+DataLoading.swift:11-33`, `ReflectionListViewModel+Grouping.swift:12-45`.

Multiple `CFAbsoluteTimeGetCurrent()` reads + `os_log` string formatting run on every
`loadReflections()` (which fires on appear, on every search keystroke via debounce, on sort/filter
changes, and after every save). Minor overhead but constant log noise in production.
**Fix.** Gate behind `#if DEBUG` or remove. Effort **S**.

---

### F11 — Redundant in-memory re-sort after the store already sorted  [P2]

**Files** `SearchReflectionsUseCase.swift:56-74`. The repository fetches with
`SortDescriptor(\.createdAt, order: .reverse)` (`ReflectionRepository.swift:13, 29, 38, 54`), then
the use case sorts again in memory (`:63-64` for `.newestFirst`), and the ViewModel regroups.
For the default sort this is a wasted O(n log n) pass. **Fix.** Skip the re-sort when the store
order already matches the requested option (or push the sort option into the `FetchDescriptor`).
Effort **S**.

---

### F12 — Thumbnail cache key derived from `UIImage.hashValue`  [P2]

**Files** `ImageProcessingService.swift:34` — `cacheKey = "…-\(image.hashValue)"`. `UIImage.hashValue`
is not a stable content hash, so two distinct `UIImage` instances of the same source rarely share a
key; the thumbnail cache mostly misses and regenerates. **Fix.** Key on a stable identifier (source
asset id / data hash) if the cache is meant to be reused across calls. Effort **S**.

---

## Secondary note (correctness, outside the perf/glitch scope but observed in-file)

- **Search ignores the learning scope.** `SearchReflectionsUseCase.swift:18-40`: when `query` is
  non-empty it calls `repository.search(query:)` (all reflections) and never applies
  `filters.learningId`. Searching inside a specific learning returns matches from *other* learnings.
  Observable, but a behaviour bug rather than a performance/glitch issue — flagging so it isn't lost.

## Notes / non-issues verified

- `Reflection` has `#Index<Reflection>([\.createdAt], [\.isFavorite])` (`Reflection.swift:9`) —
  good; the hot sort/favorite queries are indexed. `Insight` has **no** `#Index`
  (`Shared/Insight/Insight.swift`); its `@Query` sorts by `createdAt` unindexed — low priority
  given insights are lightweight, but worth an index if volumes grow.
- Reflection grouping is correctly kept on the main actor with live models
  (`+Grouping.swift:6-15`) — the comment documents a prior `Task.detached` data race that was fixed.
  Leave as-is.
- Image compression/thumbnail generation already runs off-main via `Task.detached`
  (`ImageProcessingService.swift:20-66`). The cost in F1 is the **read-back/decode** on the card
  side, not generation.
- CloudKit `backup()` uploads reflections and insights serially (`CloudSyncService.swift:149-175`)
  while learnings go 5-wide (`:130-146`); the incremental auto-sync path batches 200-wide via
  `modifyRecords` (`:840-871`). The serial manual-backup path is slower but is a user-initiated
  background op with progress, so it is not a UI-jank concern — left out of the ranked list.
</content>
</invoke>
