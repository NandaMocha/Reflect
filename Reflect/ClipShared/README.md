# Reflect/ClipShared

Cross-target source folder. Everything under this folder compiles into **both** the `Reflect`
app target and the `ReflectClip` App Clip target, via a nested `PBXFileSystemSynchronizedRootGroup`
(`path = Reflect/ClipShared`) attached to both targets' `fileSystemSynchronizedGroups` in
`Reflect.xcodeproj/project.pbxproj`. This is the mechanism ticket AC-001
([docs/features/app-clip-tasks.md](../../docs/features/app-clip-tasks.md)) establishes; later
tickets add files here (e.g. AC-010's `ClipMirrorSchema.swift`) without touching the pbxproj.

## Purity rule

Files here (and any other file given Clip-target membership) must never import the full app's
persistence framework, or reference its dependency container, its Space-sync store, its cached
model types, or its cloud sync service. Enforced by the grep gate every Clip-touching ticket runs
before committing (checked against `*.swift` sources only — this README documents the banned
terms, so it is intentionally excluded):

```
grep -rn --include='*.swift' -E "SwiftData|\bDIContainer\b|SpaceStore|Cached" ReflectClip/ Reflect/ClipShared/
```

Zero hits expected. Note the `\b` word boundaries on both sides of the dependency-container name
— `ClipDIContainer` (the Clip's own, separate container type) must not trip the gate.

## Pre-existing files given Clip-target membership (not moved, dual-membership only)

These already live under `Reflect/` for the app target and are additionally exposed to
`ReflectClip` via explicit `PBXFileReference` + `PBXBuildFile` entries in the Clip's Sources
build phase (they stay physically in place — only their Clip-target *membership* is added, the
same effect as ticking "Target Membership → ReflectClip" on a file in Xcode's File Inspector).
Verified free of SwiftData/CloudKit-private imports as of this ticket:

- `Reflect/Domain/Entities/Space/SpaceReflection.swift`
- `Reflect/Domain/Entities/Space/SpaceAnswer.swift`
- `Reflect/Domain/Entities/Space/SpaceQuestion.swift`
- `Reflect/Domain/Entities/Space/SpaceError.swift`
- `Reflect/Core/Utilities/Constants.swift` (spacing/limits tokens; `SpaceQuestion.validate` depends
  on `Constants.Limits`, so it rides along)

**Deliberately NOT given Clip-target membership yet:** `Reflect/Core/Extensions/Color+Hex.swift`
(locate via `grep -rn "primaryDefault" Reflect/Core`). Its `Color.primaryDefault` etc. tokens
resolve through Xcode's generated asset-catalog symbols (`Color(.primaryDefault)`), which only
exist for a target whose *own* asset catalog defines those named colors. `ReflectClip`'s asset
catalog currently ships only a minimal `AccentColor` (per this ticket's scope: "minimal asset
catalog, accent color + Clip icon placeholder"), so compiling `Color+Hex.swift` into the Clip
target fails at build time ("reference to member 'primaryDefault' cannot be resolved"). Sharing
it requires also giving the Clip target the `Colors` asset-catalog group (or an equivalent
subset) — deferred to whichever ticket first needs real design tokens in Clip UI (AC-031/032, or
the AC-033 polish pass). Until then, Clip-side placeholder UI uses system semantic colors
(`.tint`, `.secondary`, etc.), never hardcoded hex.

Future tickets should prefer creating *new* shared code directly inside this folder over adding
more dual-membership exceptions on existing app files.
