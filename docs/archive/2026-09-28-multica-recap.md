# Multica recap: Reflect

Snapshot: 2026-09-28 19:40 WIB. Source: Multica issues GAR-1 to GAR-54, their final review/closing comments, and `git` refs read at that time. Read this before planning new work so you do not redo or undo it.

## Branch state (verified)

| Ref | SHA | Relation |
|---|---|---|
| `origin/multica-task` | `4163e23` | Integration branch for Multica agents. Contains every Multica change below. |
| `origin/develop` | `9cbe10c` | Active line and loop branch. 67 commits not yet in `multica-task`. `multica-task` has 17 commits not in `develop`. |

`develop` now includes `feature/space-public-invite-link` (rebase-merged by the owner): public Space invite links, "Copy Invite Link" in the Space members sheet, new Spaces invite-only until a link is requested, export compliance in `Info.plist`, build number bumped to 12.

## Pending sync of `develop` into `multica-task` (owner chose to delay it)

A trial merge (`git merge-tree`) conflicts in two files:

- `Reflect/Presentation/Features/Space/Detail/SpaceDetailView.swift`: take develop's invite link changes, but drop `.firstOpenIntro(.space, flagKey: Constants.UserDefaults.hasSeenSpaceIntro)`. GAR-28 removed the Space intro on `multica-task`, and GAR-30 deleted `FeatureIntroView` and the intro flags.
- `Reflect.xcodeproj/project.pbxproj`: keep the GAR-9 test targets and develop's build number. Assumption, not checked line by line: develop's side of the conflict is the build number bumps.

Rules for the sync:
- Use a `--no-ff` merge commit, like `sync-multica-task.sh`. Do not use `merge-to-multica-task.sh`: it rebases and would flatten develop's 67 commits.
- Run `gate.sh`, then `gate.sh --ios-unit`, before pushing. Afterwards `sync-multica-task.sh` must print `RESULT: up-to-date`.
- Still open: who resolves (owner manually, or a new Release Steward path), and whether to pause the "Reflect · daily sync + graph" autopilot. Until paused, that autopilot hits exit 3 daily at 07:00 WIB and files a conflict issue for Tech Lead.

Merging `multica-task` into `develop` is a human gate.

## What landed on `multica-task`

All cards were reviewed MERGE-READY, merged with `merge-to-multica-task.sh`, and the merge gate was green.

### Repo setup and build
- GAR-3 (`3849d91`): builds on Xcode 27 / Swift 6.4 (`import SwiftData` in `OnboardingView.swift`, MemberImportVisibility).
- GAR-5 / GAR-6 (`da80c93`): `.multica/` added to `.gitignore`.
- `38a1e83`: CLAUDE.md "Running under Multica" section.

### Widget (GAR-8)
- GAR-9 (`b5f3458`): `ReflectTests` (Swift Testing) and `ReflectUITests` targets with smoke tests.
- GAR-10 (`7904238`): widget deep links, daily quote and timeline logic moved into `Shared/Widget/`, with unit tests.
- GAR-11 (`58fd265`): widget layout, colour tokens, contrast and accessibility fixes, with render and contrast tests. Owner checklist in `docs/features/widget.md`.
- GAR-12 (`0947528`): XCUITests for every `reflect://` link and an unknown URL. Tabs are tapped by label via `tapTab`.
- GAR-13 (`4796a53`): write, camera and voice links opened from the Chapters list now work, and insight compose opens.

### Voice recording (GAR-22, GAR-23)
- GAR-24 (`e1f8a22`): speech service keeps the final transcript on stop, classifies errors, adds file transcription.
- GAR-25 (`9ac60ff`): voice note falls back to file transcription and shows a clear transcript status.
- GAR-26 (`ed7acd9`): live waveform scrolls one bar per update with smoothing (`LiveWaveformBuffer`).
- GAR-31 (`eef93d8`): waveform drops audio levels that arrive after stop or cancel.
- GAR-53 (`4163e23`): `VoiceRecorderWaveformUITests` finds the record button by `identifier == 'voice.record' AND label == 'Start recording'`.

### Onboarding and permission intros (GAR-27)
- GAR-28 (`1ba7885`): onboarding has 5 pages (new Achievements page). Space, Achievements and iCloud Sync full-screen intros removed. Restore warning moved to the `CloudSyncView` footer.
- GAR-29 (`6672966`): camera intro replaced by a small primer sheet, shown only when camera permission is `notDetermined` (`PermissionPrimer`, `PermissionPrimerView`).
- GAR-30 (`16ae8ba`): voice intro replaced by an inline primer in the recorder (`VoicePermission`). `FeatureIntroView`, `hasSeenVoiceIntro`, `hasSeenCameraIntro` and related intro code deleted.

### Insight tags (GAR-46)
- GAR-47 (`30c4b47`): `InsightType.colorHex` became `colorHex(for: ColorScheme)` with a light/dark pair. Question light `#065F8F` / dark `#C7EBFF`, Note light `#854806` / dark `#FFE0BD`, all at least 4.5:1 on the `glassCard` surface. Test: `ReflectTests/Insight/InsightTypeContrastTests.swift`.

## Tooling outside the repo (live, not in git)

Path: `/Users/nandamochammad/Dev-Project/Tes/multica-team/`.

- `scripts/gate.sh`: plain gate is an `xcodebuild` Debug build for the iPhone 17 simulator (no boot). `--ios-unit` runs `ReflectTests`, `--ui-run ReflectUITests/<Class>` runs one UI test, each on a simulator clone per worktree. Reflect uses Xcode compilation cache with a shared CAS dir (GAR-45). Global build slots: 3 for agents (via `guard/settings.json`), simulator slots: 3.
- `guard/xcodebuild_guard.py` (GAR-51): agents cannot run raw `xcodebuild test` or `simctl boot`. Use `gate.sh`.

## Open items for the owner

- Human gate: merge `multica-task` into `develop`, after the pending sync above.
- Device checks not yet run: GAR-25 (10 manual recordings for transcript), GAR-26 (waveform smoothness with real voice), GAR-28 (onboarding, incl. iPhone SE fit), GAR-29 (camera primer), GAR-30 (voice primer, speech prompt order), GAR-47 (dark mode tag hue looks faint).
- Open decision from GAR-23: `transcribeFile` in `SpeechRecognitionEngine.swift` ignores task cancellation, so the file recognizer can run up to 60 s after the sheet closes. Bug card or known issue.
- GAR-54 (backlog, unassigned): remove dead `-hasSeenVoiceIntro YES` launch args from `VoiceNoteUITests.swift`, `VoiceRecorderWaveformUITests.swift`, `CameraPermissionPrimerUITests.swift`. Cosmetic, can go after the sync.
- Follow-ups from reviews (low, not carded):
  - `CLAUDE.md:85` still says tests are not wired up.
  - `ReflectTests` scheme is `parallelizable = YES`, which clones extra simulators.
  - UI tests launch against the real SwiftData/CloudKit store (no in-memory flag).
  - `widgetAction` reset uses a 0.5 s `asyncAfter` in `LearningListView` and `ReflectionListView`.
  - `SpaceListView.swift:80` uses an onChange-only pattern for `openSpace`.
  - `UITestingSpeechRecognitionService` lives inside `VoiceAudioView.swift`.
  - Camera primer `.medium` detent leaves a large gap.
  - `preferredCameraPosition` is no longer written.
