# Reflection System

**Status**: Implemented. Active in-app feature.
**Last verified against code**: 2026-04-21

This document describes what the reflection system **actually is in the current code** — the capture, edit, move, and delete flows for user reflections. For the achievement side (badges that unlock on reflection milestones) see [achievement.md](achievement.md).

## What a reflection is

A reflection is a dated journal entry belonging to exactly one **Learning**. It can combine any of:

- Plain text (title + body)
- Images (up to `Constants.Limits.maxImagesPerReflection`)
- Videos (up to `Constants.Limits.maxVideosPerReflection`)
- Voice recordings with optional transcription (up to `Constants.Limits.maxVoiceNotesPerReflection`)
- An optional `promptID` if the reflection was started from a guided prompt
- An optional `CapturedLocation` (latitude + longitude + place name) from a Journaling Suggestion

Canonical source: [`Reflection.swift`](../../Reflect/Data/Models/Reflection.swift) + [`CreateReflectionInput.swift`](../../Reflect/Domain/Entities/CreateReflectionInput.swift).

## Learning assignment model

**A reflection always belongs to exactly one Learning, and it's assigned at creation time from the list context.** The user picks the learning by entering that learning's reflection list — there's no picker inside the editor.

Consequences:
- `ReflectionListView` is always filtered to a single learning (its `learning: Learning?` property; in practice always non-nil on navigation from `LearningListView`).
- The FAB's create flow (`.fullScreenCover` on [ReflectionListView.swift:67](../../Reflect/Presentation/Features/Reflection/List/ReflectionListView.swift)) passes that learning to the editor as `preselectedLearning`.
- The editor's header shows the learning as a read-only chip ([ReflectionEditorHeaderView.swift](../../Reflect/Presentation/Features/Reflection/Editor/Components/ReflectionEditorHeaderView.swift)) — no tap target for learning.
- The detail view also shows the learning as a read-only chip ([ReflectionDetailView+Components.swift](../../Reflect/Presentation/Features/Reflection/Detail/ReflectionDetailView+Components.swift), `learningBadge`).
- To change a reflection's learning, the user **swipes the row → Move** in the list, which opens [`LearningPickerSheet`](../../Reflect/Presentation/Components/LearningPickerSheet.swift) filtered to exclude the current learning.

This model was adopted 2026-04-21 (commits `8f8c2b2` / `62a8c12` / `4a2adad`) after earlier UIs had three ways to reassign a learning — inline picker in the editor, implicit via Edit flow, tappable detail badge — which were confusing and let reflections land in the wrong learning when the preselected value wasn't passed correctly.

## Data flow

### Create

```
User taps + in ReflectionListView (filtered to a Learning)
       ↓
.fullScreenCover presents
  ReflectionEditorView(mode: .create, preselectedLearning: learning)
       ↓
View's form @State is bridged onto ReflectionEditorViewModel at save time
       ↓
viewModel.save() builds CreateReflectionInput and calls
  CreateReflectionUseCase.execute(input:)  [Domain/UseCases/Reflection]
       ↓
CreateReflectionUseCase:
  1. Validates learningId + fetches Learning
  2. Builds a Reflection, wires learning, createdAt, location, promptID
  3. Compresses images / generates thumbnails, appends ImageAttachment
  4. Appends VideoAttachment (thumbnail as JPEG data)
  5. Appends VoiceRecording
  6. reflectionRepository.create(reflection)
  7. If evaluateBadgesUseCase is wired → runs badge evaluation
       ↓
On success:
  - UserDefaults.setLastUsedLearningId(learning.id) (view)
  - NotificationCenter posts "ReflectionDidSave" (list refresh)
  - .badgesDidUnlock / .badgeProgressDidUpdate notifications fire
  - Editor dismisses; MainTabView's observer presents celebration if any
```

### Edit

```
User taps pencil icon in ReflectionDetailView
       ↓
.fullScreenCover presents
  ReflectionEditorView(mode: .edit(reflection))
       ↓
VM.configure(with: reflection) loads title, content, learning, createdAt,
  location, images, videos, voiceRecordings from the Reflection; captures
  existingImageIds / existingVideoIds so the use case can distinguish
  pre-existing attachments from new ones.
       ↓
viewModel.save() → UpdateReflectionUseCase.execute(input:)
       ↓
UpdateReflectionUseCase.reconcileImages / reconcileVideos / reconcileVoiceRecordings:
  for each media type, use the desired full list + existingIds to
  (a) delete anything no longer in the desired set,
  (b) update sortOrder / caption on pre-existing items,
  (c) compress + create new attachments for items not in existingIds.
Updates title, content, createdAt, location, bumps updatedAt, saves.
Runs badge evaluation just like create.
       ↓
Detail view dismisses on save (via onDismiss callback).
```

### Move (swipe action)

```
User swipes a row in ReflectionListView → Move button
       ↓
ReflectionListView sets `reflectionToMove = reflection`
       ↓
.sheet(item: $reflectionToMove) presents
  LearningPickerSheet(
    title: "Move to Learning",
    learnings: learnings.filter { $0.id != reflection.learning?.id },
    onSelect: { target in viewModel.moveReflection(reflection, to: target) }
  )
       ↓
ReflectionListViewModel.moveReflection(_:to:):
  await MoveReflectionUseCase.execute(reflectionId:, toLearningId:)
       ↓
MoveReflectionUseCase:
  1. Fetches reflection by ID (throws .notFound if missing)
  2. Fetches target learning by ID (throws .learningNotFound if missing)
  3. reflection.learning = newLearning
  4. reflection.updatedAt = Date()
  5. reflectionRepository.update(reflection)
       ↓
VM drops the reflection from the local array (since the list is filtered to
  a learning that isn't the target anymore) and regroups; haptic success.
```

### Delete (swipe action)

```
User swipes → Delete button (destructive role)
  → viewModel.deleteReflection(reflection)
  → DeleteReflectionUseCase.execute(reflection:)
  → reflectionRepository.delete(reflection)
VM removes locally, regroups, haptic success.
```

## Key files

| Role | Path |
|---|---|
| List view | [Reflect/Presentation/Features/Reflection/List/ReflectionListView.swift](../../Reflect/Presentation/Features/Reflection/List/ReflectionListView.swift) |
| List view model | [Reflect/Presentation/Features/Reflection/List/ReflectionListViewModel.swift](../../Reflect/Presentation/Features/Reflection/List/ReflectionListViewModel.swift) + `+Actions` + `+Data` extensions |
| Detail view | [Reflect/Presentation/Features/Reflection/Detail/ReflectionDetailView.swift](../../Reflect/Presentation/Features/Reflection/Detail/ReflectionDetailView.swift) |
| Editor view | [Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView.swift](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView.swift) + 6 extensions |
| Editor view model | [Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel.swift](../../Reflect/Presentation/Features/Reflection/Editor/ViewModel/ReflectionEditorViewModel.swift) + `+SaveLogic` / `+Validation` / `+MediaActions` |
| Editor header (read-only learning chip) | [Reflect/Presentation/Features/Reflection/Editor/Components/ReflectionEditorHeaderView.swift](../../Reflect/Presentation/Features/Reflection/Editor/Components/ReflectionEditorHeaderView.swift) |
| Card | [Reflect/Presentation/Components/Cards/ReflectionCard.swift](../../Reflect/Presentation/Components/Cards/ReflectionCard.swift) |
| Shared learning picker (used by Move + any future consumers) | [Reflect/Presentation/Components/LearningPickerSheet.swift](../../Reflect/Presentation/Components/LearningPickerSheet.swift) |
| Model | [Reflect/Data/Models/Reflection.swift](../../Reflect/Data/Models/Reflection.swift) |
| Attachments | [Reflect/Data/Models/ImageAttachment.swift](../../Reflect/Data/Models/ImageAttachment.swift), [VideoAttachment.swift](../../Reflect/Data/Models/VideoAttachment.swift), [VoiceRecording.swift](../../Reflect/Data/Models/VoiceRecording.swift) |
| Inputs | [Reflect/Domain/Entities/CreateReflectionInput.swift](../../Reflect/Domain/Entities/CreateReflectionInput.swift) (also contains `UpdateReflectionInput` and `CapturedLocation`) |
| Use cases | [CreateReflectionUseCase](../../Reflect/Domain/UseCases/Reflection/CreateReflectionUseCase.swift), [UpdateReflectionUseCase](../../Reflect/Domain/UseCases/Reflection/UpdateReflectionUseCase.swift), [MoveReflectionUseCase](../../Reflect/Domain/UseCases/Reflection/MoveReflectionUseCase.swift), [DeleteReflectionUseCase](../../Reflect/Domain/UseCases/Reflection/DeleteReflectionUseCase.swift), [FetchReflectionsUseCase](../../Reflect/Domain/UseCases/Reflection/FetchReflectionsUseCase.swift), [SearchReflectionsUseCase](../../Reflect/Domain/UseCases/Reflection/SearchReflectionsUseCase.swift) |
| Repository | [Reflect/Data/Repositories/Implementations/ReflectionRepository.swift](../../Reflect/Data/Repositories/Implementations/ReflectionRepository.swift) |
| DI wiring | [Reflect/App/DIContainer.swift](../../Reflect/App/DIContainer.swift) |

## Persistence

- **SwiftData.** `Reflection` is `@preconcurrency @Model final class`. Relationships to `ImageAttachment`, `VideoAttachment`, `VoiceRecording` cascade on delete (set in the Reflection model). Image / video / audio blobs use `@Attribute(.externalStorage)` so they live outside the store file.
- `Reflection.learning` is a `Learning?` relationship (nullable at the schema level, but the use cases require it non-nil via input validation).
- `promptID` is a `String?` — copied from the Prompt entity when used, but the reflection does not own a reference to a Prompt model. A Prompt deletion doesn't orphan a reflection.
- Move does not delete or recreate anything — it reassigns the `learning` relationship and bumps `updatedAt`. Attachments travel with the reflection automatically.

## Known non-obvious behaviors

- **Editor bypass of the domain layer (legacy):** the view still holds `@State` for each form field; the VM's state is only populated at save time via a copy bridge in [ReflectionEditorView+Save.swift](../../Reflect/Presentation/Features/Reflection/Editor/View/ReflectionEditorView+Save.swift). A future refactor could move form state onto the VM and bind directly via `$viewModel.title` etc. See the follow-up note in [../reviews/achievement-counter-root-cause.md](../reviews/achievement-counter-root-cause.md).
- **Widget / quick actions:** the `Quick Actions` extension creates reflections via short-lived handlers inside `ReflectionListView` (photo, video, voice) that bypass the use-case pipeline and write directly to `modelContext`. These handlers do NOT trigger badge evaluation or celebrations. Worth unifying in a follow-up.
- **Editor's isValid still gates on `selectedLearning != nil`** as a last-mile safety net even though the new flow guarantees a learning. The VM surfaces no user-facing error string for that case (unreachable under the new flow).
- **`CapturedLocation`** lives in the Domain layer ([CreateReflectionInput.swift](../../Reflect/Domain/Entities/CreateReflectionInput.swift)) so both the editor (Presentation) and the use cases (Domain) can share the type. It was previously defined in Presentation and reached into from Domain — a layer violation fixed during the Option-B editor refactor.
