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

- [Achievement / Badges](docs/features/achievement.md) — what's currently implemented

## Reviews / known issues

- [Achievement counter code review](docs/reviews/achievement-counter-review.md) — bugs and improvements in the current achievement counter
- [Streak docs vs. implementation](docs/reviews/streak-docs-vs-implementation.md) — doc–code drift analysis

## Non-obvious gotchas

- `DIContainer.shared.configure(with:)` **must** be called before any `make…()` call or they `fatalError`. This happens in `ReflectApp.swift` after the `ModelContainer` initializes.
- The achievement UI refreshes via two `NotificationCenter` names: `.badgesDidUnlock` and `.badgeProgressDidUpdate`. `CreateReflectionUseCase` posts them after `EvaluateBadgesUseCase` runs; `BadgeGridView.onReceive(...)` reacts.
- Markdown docs live under `/docs` at repo root — **not** under `Reflect/Resources/`. Resources are shipped with the app; dev docs are not.
- The `docs/archive/streak-original-spec/` folder describes an earlier "streak" badge design that was intentionally removed. It's kept for reference but does not reflect current code. See the reconciliation review linked above.
