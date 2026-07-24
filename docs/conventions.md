# Conventions

Quick reference. Full context in [architecture.md](architecture.md). Where a rule is explained there, this file just names it and links.

## File naming

| Kind | Pattern | Example |
|---|---|---|
| View | `<Feature>View.swift` | `BadgeGridView.swift` |
| ViewModel | `<Feature>ViewModel.swift` | `BadgeGridViewModel.swift` |
| Use case | `<Verb><Entity>UseCase.swift` | `CreateReflectionUseCase.swift` |
| Repository protocol | `<Entity>RepositoryProtocol.swift` | `BadgeRepositoryProtocol.swift` |
| Repository impl | `<Entity>Repository.swift` | `BadgeRepository.swift` |
| SwiftData model | `<Entity>.swift` | `Reflection.swift` |
| Service | `<Domain>Service.swift` | `BadgeEvaluationService.swift` |

## MARK section order

Inside a type, use these section markers in this order when present:

```swift
// MARK: - State
// MARK: - Dependencies
// MARK: - Initialization
// MARK: - Public Properties
// MARK: - Actions
// MARK: - Private Helpers
// MARK: - Setup
```

## ViewModels

- `@Observable final class … @MainActor` (the `@MainActor` is mandatory for anything that drives UI)
- No `ObservableObject`, no `@Published`, no Combine for state — use the Observation macro
- Mark dependencies `private let …` and inject via the initializer only (no globals, no singletons except `DIContainer.shared`)

## Use cases

- One file = one use case
- Protocol + concrete class. Protocol carries the `execute(input:)` signature; class holds dependencies.
- `struct …Input` for parameters if there's more than one
- Return the domain entity or a result type — never the SwiftData model leaking to presentation

## SwiftData models

- `@preconcurrency @Model final class`
- `@Attribute(.unique) var id: UUID` (or a stable string id for well-known enums like `BadgeID.rawValue`)
- `@Relationship(deleteRule: .nullify, inverse: \Other.self)` — always state the delete rule explicitly
- Computed properties use `var`, not `let`

## Dependency injection

- Wire everything through `DIContainer.shared`. Every dependency has a `make…()` factory.
- `DIContainer.shared.configure(with: modelContext)` must run before any factory call — this happens in `ReflectApp.swift`.
- Depend on protocols, not concrete types.

## Async & concurrency

- Repository methods: `async throws`
- Callers from SwiftUI: `Task { await … }` inside `.task { … }` or action closures
- Anything mutating `@Observable` state: on `@MainActor`
- No detached tasks except for genuinely background work; if you reach for `Task.detached`, think twice

## Error handling

- One domain-specific `enum …Error: Error, LocalizedError` per feature (see `ReflectionError` for shape)
- Don't silence errors with `try?` in production code paths — log with `Logger` from `os`, or propagate
- Use `do/catch` in ViewModels and surface via `errorMessage: String?`

## UI

- Colors: `Color` extensions from `Core/Extensions/Color+Hex.swift`, never hex literals in views
- Spacing / radius / animation durations: `Constants.Spacing.*`, `Constants.CornerRadius.*`, `Constants.Animation.*`
- Glass morphism: `.glassBackground(…)` / `.glassCard()` modifiers
- Buttons: `PrimaryButton`, `SecondaryButton`, `IconButton` — not ad-hoc `Button {}` for main actions

## Comments

- Default to no comments. Only write one when the *why* is non-obvious: a hidden constraint, a subtle invariant, a known bug workaround.
- Don't explain what the code does; names should carry that.
- Don't reference tickets, commits, or prior callers — that context rots.

## Testing (when the target exists)

- **Swift Testing**, not XCTest
- `@Test` functions, `#expect(...)` assertions
- Follow the `Given / When / Then` comment structure from [architecture.md](architecture.md#testing-guidelines)
- Name: `<method>_<condition>_<outcome>`, e.g. `deleteItem_removesFromList`

## Common pitfalls (copied from architecture.md)

1. Don't use `@Published` — use `@Observable`
2. Don't force-unwrap in production code — `guard let` or optional chaining
3. Don't call async from sync without `Task { … }`
4. Don't forget `DIContainer.configure(with:)` before factory calls
5. Don't hardcode colors
6. Don't skip error handling
7. Don't mutate state from a background thread — use `@MainActor`
8. Don't build direct dependencies — always inject via `DIContainer`
