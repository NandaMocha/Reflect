# CLAUDE.md

Entry point for Claude Code working on this repo. Keep this file short — link out to `docs/` for detail.

## Project

**Reflect** (bundle name: ReflectLearn) — iOS learning journal app. Users capture reflections on their learning journey as text, images, voice notes, and videos, with iCloud backup.

## Stack

- iOS 17+, Swift 6.0, Xcode 15+
- SwiftUI (+ Observation framework, `@Observable` ViewModels)
- SwiftData for persistence
- Swift concurrency (`async`/`await`, `@MainActor`)
- CloudKit for sync
- Widget extension + "Quick Actions" app extension

## Architecture TL;DR

Clean Architecture + MVVM in four layers:

```
Presentation (SwiftUI + @Observable VMs)
        ↓
Domain      (Entities + UseCases — pure business logic)
        ↓
Data        (Repositories + SwiftData @Model classes)
        ↓
Services    (Audio, Speech, Image, Cloud)
```

Full reference: [docs/architecture.md](docs/architecture.md).

## Where things live

```
Reflect/
├── App/            # ReflectApp.swift, DIContainer.swift
├── Core/           # Extensions, constants, HapticManager
├── Domain/         # Entities/, UseCases/<Feature>/
├── Data/           # Models/, Repositories/{Protocols,Implementations}
├── Presentation/   # Components/, Features/<Feature>/{List,Form,Detail}, Modifiers/
├── Services/       # Audio/, Cloud/, Image/, Speech/, Achievement/
└── Resources/      # Assets, localizations (NOT dev docs — those live in /docs)
Quick Actions/      # Separate app extension target
```

## Key conventions

- **ViewModels**: `@Observable` + `@MainActor` + `final class`. Organize with `// MARK: -` sections: State, Dependencies, Initialization, Actions, Private Helpers.
- **Dependency injection**: `DIContainer.shared` is the one and only wiring point. Configure once at app launch with `configure(with: modelContext)`, then call `make…()` factories. Protocols over concrete types everywhere.
- **Use cases**: one class per action, naming `<Verb><Entity>UseCase` (`CreateReflectionUseCase`, `FetchLearningsUseCase`). Protocol + `struct Input` + `execute(input:) async throws`.
- **SwiftData**: `@preconcurrency @Model final class`. Unique ID with `@Attribute(.unique)`. Relationships with explicit delete rules.
- **Error handling**: domain-specific `enum … Error: Error, LocalizedError` per feature. Don't silently swallow with `try?` in production paths — log or propagate.
- **No `@Published` / `ObservableObject`** — use Observation macro.
- **No hardcoded colors** — use `Color` extensions and `Constants` tokens (see [docs/architecture.md](docs/architecture.md#design-system)).

## Run

```bash
open Reflect.xcodeproj
# In Xcode: select "Reflect" scheme, Cmd+R
```

## Test

**No test target exists yet.** See [docs/reviews/achievement-counter-review.md](docs/reviews/achievement-counter-review.md) — setting up Swift Testing is a noted follow-up.

## Build-and-verify workflow

**Standing rule: after finishing code changes, run `xcodebuild` in the terminal before declaring the task done.** Iterate until the build is green. Tests aren't wired up yet, so the build is the fastest full-repo sanity check we have.

```bash
xcodebuild -project Reflect.xcodeproj -scheme Reflect \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build 2>&1 | grep "error:"
```

- If the grep prints any line → a compile error. Read the file:line, fix it, rebuild. Loop until grep is empty.
- When grep is empty, spot-check `tail -5` of the unfiltered output for `** BUILD SUCCEEDED **`.
- Pick a simulator name that appears in `xcrun simctl list devices available`. The Reflect scheme currently targets iOS 26 simulators (iPhone 17 family), so use `iPhone 17`, `iPhone 17 Pro`, etc.
- Swift 6 concurrency warnings (non-Sendable types being passed across actor boundaries) are **warnings, not errors** — they exist in the codebase today and don't block the build. Don't chase them unless the task asks for it.

This comes *before* the commit step, not after. A red build is a task that isn't finished — don't commit claiming success and then let the build break.

`xcodebuild` is pre-allowed in [.claude/settings.json](.claude/settings.json) so this runs without a permission prompt.

## Commit workflow

**Standing rule: commit when a change is complete.** After finishing a logical unit of work (bug fix, feature, doc update, refactor), don't leave uncommitted changes in the working tree — stage the relevant files and create a commit. No need to ask the user first.

- One commit per logical unit. If you've made unrelated changes, split into separate commits instead of batching.
- Commit message: short imperative summary on line 1 (≤72 chars), blank line, 1–3 sentences explaining *why* in the body.
- Stage files explicitly by name when possible — avoid `git add -A` / `git add .` so `.env`, credentials, or build artifacts don't slip in.
- **Don't push** unless the user explicitly asks. Commits stay local.
- **Don't use** `--no-verify`, `--no-gpg-sign`, or `--amend` on already-pushed commits.
- If a pre-commit hook fails, fix the underlying issue and create a new commit — don't amend or bypass.

Git permissions for `git status`, `diff`, `log`, `add`, `commit` are pre-allowed in [.claude/settings.json](.claude/settings.json) so this runs without prompts. Destructive commands (`push`, `reset --hard`, `checkout --`, force-push) remain prompt-gated on purpose.

## Feature docs

- [Reflection](docs/features/reflection.md) — create / edit / move / delete flow, learning-assignment model
- [Achievement / Badges](docs/features/achievement.md) — the 17 badges, evaluation flow, celebration UI

## Reviews / known issues

- [Achievement counter code review](docs/reviews/achievement-counter-review.md) — static-analysis findings and prioritized fixes
- [Achievement counter deep-dive](docs/reviews/achievement-counter-deep-dive.md) — runtime trace of why the counter didn't update
- [Achievement counter root cause](docs/reviews/achievement-counter-root-cause.md) — orphaned ViewModel analysis and Option B refactor record
- [Streak docs vs. implementation](docs/reviews/streak-docs-vs-implementation.md) — doc–code drift analysis for the removed streak system

## Non-obvious gotchas

- `DIContainer.shared.configure(with:)` **must** be called before any `make…()` call or they `fatalError`. This happens in `ReflectApp.init` right after the `ModelContainer` initializes.
- Badge lifecycle uses two `NotificationCenter` names: `.badgesDidUnlock` (payload: `[BadgeID]`) and `.badgeProgressDidUpdate`. Both `CreateReflectionUseCase` and `UpdateReflectionUseCase` post them after `EvaluateBadgesUseCase` runs. Observers: `MainTabView` presents the full-screen `CelebrationView` on `.badgesDidUnlock`; `BadgeGridView` and `LearningListView` refresh on both.
- A reflection's `Learning` is **fixed at creation** from the list's filter — no picker in the editor. To reassign, use the row's swipe → Move action in `ReflectionListView`, which goes through `MoveReflectionUseCase`.
- Markdown docs live under `/docs` at repo root — **not** under `Reflect/Resources/`. Resources are shipped with the app; dev docs are not.
- The `docs/archive/streak-original-spec/` folder describes an earlier "streak" badge design that was intentionally removed. It's kept for reference but does not reflect current code. See the reconciliation review linked above.
