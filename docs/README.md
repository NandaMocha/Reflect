# Reflect — Documentation

This directory is the single home for all project documentation. Files inside the app bundle (`Reflect/Resources/`) are ship-time assets only.

## Start here

| For | Read |
|---|---|
| New engineers | [getting-started.md](getting-started.md) → [architecture.md](architecture.md) → [conventions.md](conventions.md) |
| Claude Code sessions | [/CLAUDE.md](../CLAUDE.md) first, then the feature doc relevant to your task |
| Feature work | [features/](features/) — current implementation references |
| Debugging known issues | [reviews/](reviews/) |
| Historical context | [archive/](archive/) |

## Layout

```
docs/
├── README.md              # this file — docs index
├── architecture.md        # layers, patterns, DI, SwiftData, design system
├── getting-started.md     # setup, build, run
├── conventions.md         # coding rules cheat sheet
├── features/
│   ├── achievement.md     # 17 badges, evaluation flow, celebration UI
│   └── reflection.md      # create / edit / move / delete flow, learning model
├── reviews/
│   ├── achievement-counter-review.md        # static-analysis findings + fix priorities
│   ├── achievement-counter-deep-dive.md     # runtime trace of the counter bug
│   ├── achievement-counter-root-cause.md    # orphaned VM analysis + Option-B refactor
│   └── streak-docs-vs-implementation.md     # doc↔code drift for removed streak system
└── archive/
    ├── refactoring-2025-01.md
    ├── access-control-fixes.md
    ├── performance-optimization-plan.md
    └── streak-original-spec/   # 10 files — earlier "streak" design, superseded
```

## Documentation rules

- **Dev docs live here**, not under `Reflect/Resources/`. That directory is shipped to the built app.
- **One canonical source per topic.** If two docs drift, merge or archive the stale one; don't leave two sources of truth.
- **Feature docs describe what the code does**, not what a past spec wanted it to do. If they diverge, write a review under `reviews/` and decide which side to change.
- **Archives are frozen.** Don't update files under `archive/` to match current code — that defeats the point. Add a pointer to the current doc instead.
- **Link, don't duplicate.** Cross-link between docs rather than copy-pasting content.
