# Session recap: 2026-09-27

Read-only investigation session. No app code was changed. This file records what was checked, what was found, and which decisions are still open.

All code references point to `origin/multica-task` at `da80c93`, not to `main`.

---

## 1. Latest update in the repo

The newest work is on `multica-task`, dated 2026-09-25. It has not reached `develop` or `main`.

| Commit | Change | Files |
|---|---|---|
| `38a1e83` | Add "Running under Multica" section to CLAUDE.md | `CLAUDE.md` (+16) |
| `3849d91` | GAR-3: fix Swift 6.4 `MemberImportVisibility` error | `OnboardingView.swift` (+1 import) |
| `da80c93` | GAR-6: ignore `.multica/` runtime folder | `.gitignore` (+3) |

Before that, the last activity on `develop` was 2026-08-05 and was mostly docs and verification:

- App Clip CloudKit write path proven end to end (#84), cPanel/AASA hosting verified (#83)
- H2 two-device runbook added (#85), H2 / H3 / TASK-014 recorded as passed (#86). Next action points at H4.
- Session handoff archived as `docs/features/handoff-2026-08-05.md` (#87)

---

## 2. Which branch is complete

**Answer: `origin/multica-task`.** No other branch has work that is missing from it.

```
main           2026-07-30  (#24 merge)
  └─ develop   2026-08-05  120 commits ahead of main
       └─ multica-task  2026-09-25  3 commits ahead of develop
```

### How it was checked

A plain commit count made 31 branches look like they had "missing" commits. That is misleading because most PRs were squash-merged, so the original commit SHAs never appear on `develop`.

Instead, every remote branch was trial-merged into `multica-task` with `git merge-tree --write-tree`:

| Result | Count | Meaning |
|---|---|---|
| Tree unchanged | 13 | Fully included (incl. `main`, `develop`, both `multica/*`) |
| "New" content | 2 | False positive: the merge duplicates code that already exists (`feat/47` createAnswer, `docs/h2-runbook` link text) |
| Conflict | 17 | Squash-merged, then edited again later |

Conflicting branches were spot-checked by commit subject and all landed: `worktree-fix-spacestore-crash` (#63), `fix/task-011-ownership` (#78), `feat/44-export-menu` (#69), `feat/task-001-split-spacethreadview` (#66), `feat/loop-parallel-lanes` + `docs/multi-answer-ui-plan` (#65), `fix/section-title-shared` (#18). The Journaling Suggestions code from `feature/add-journaling-suggestion` is present in `ReflectionEditorView+Journaling.swift`.

`main` has 19 commits not in `multica-task` by SHA, but they are merge commits only. `git diff multica-task...main` is empty.

---

## 3. Starting new work from `multica-task`

Owner decision: **do not merge `multica-task` yet.**

Branching from it is allowed and is not a merge. The trade-off:

- Branch from `multica-task`: you get the Swift 6.4 build fix, but a later PR into `develop` also carries the 3 Multica commits.
- Branch from `develop`: `develop` stays free of Multica work. If Swift 6.4 breaks the build, cherry-pick only `3849d91`.

Per CLAUDE.md, merging `multica-task` into `develop` or above needs the owner.

No branch choice was made in this session.

---

## 4. Tutorial sheet (first-open intro) analysis

The app has 7 tutorial surfaces. 6 are in use.

### Where each one appears

```
App launch
└── Onboarding (4 swipe pages)                  once, until "Get Started"

Tab: Chapters
├── Reflection list / Editor
│   └── Camera intro (2 steps)                  first camera use
├── Voice recorder
│   └── Voice intro                             first time in record mode
├── Achievements sheet
│   └── Badges intro                            first open
└── Settings → iCloud Sync
    └── Cloud Sync intro                        first open

Tab: Insights                                   (none)

Tab: Spaces
├── Space list                                  (none)
└── Space detail
    └── Space intro                             first open of any Space

Not used
└── Reflection list swipe → Move hint           removed 2026-07-24 (a0d9b2f)
```

### Status

| Sheet | Presented from | Flag (`Constants.UserDefaults`) | Marked seen on | Status |
|---|---|---|---|---|
| Onboarding | `MainTabView.swift:95` | `hasCompletedOnboarding` | Get Started / Restore / Start Fresh only | OK |
| Camera | `ReflectionListView.swift:93`, `ReflectionEditorView.swift:134` | `hasSeenCameraIntro` | Continue only. X shows it again next time. | OK |
| Voice | `VoiceAudioView.swift:114` | `hasSeenVoiceIntro` | Any dismiss | OK, stale comments |
| Badges | `LearningListView.swift:345` | `hasSeenBadgesIntro` | Any dismiss | OK |
| Cloud Sync | `CloudSyncView.swift:52` | `hasSeenCloudSyncIntro` | Any dismiss | OK |
| Space | `SpaceDetailView.swift:70` | `hasSeenSpaceIntro` | Any dismiss | **Copy does not match app** |
| List hint | none | `hasSeenReflectionListHint` | none | Dead key |

Shared building block: `FeatureIntroView` + `View.firstOpenIntro(_:flagKey:)` in `Presentation/Components/Universal/FeatureIntroView.swift`. Onboarding pages live in `OnboardingModels.swift:26`. Onboarding copy was checked against code; the "widget or Siri" claim for Insights is real (`AppIntents/CreateInsightIntent.swift`).

### Findings

**F1. Space intro promises a rule the app does not enforce.** (Needs owner decision)

`FeatureIntroView.swift:30` says:

> `Share your own feedback first — then you can see everyone else's.`

But `SpaceThreadView.swift:39` always opens `SpaceAllResponsesView` from the "View all feedback" toolbar button. There is no check on whether the viewer has answered. Options:

- Change the copy to match current behavior.
- Build the gating: lock "View all feedback" until the viewer has answered.

**F2. `hasSeenReflectionListHint` is a dead key.** The banner was removed in `a0d9b2f` because of UI bugs, but the key stayed in `Constants.swift`. The swipe → Move gesture, the only way to reassign a reflection, now has no hint at all.

**F3. Voice intro comments are stale.** `Constants.swift:130` and `FeatureIntroView.swift:62` still say the intro primes Microphone + Speech permissions. `a0d9b2f` removed that; permissions are requested on the first record tap. The CTA still reads "Continue →" as if a permission step follows.

**F4. Onboarding has dead code and bypasses DI.**

- `MainTabViewModel` is never used. `MainTabView` has its own copy of the onboarding check.
- `DIContainer.makeOnboardingViewModel()` is never called. `OnboardingView.swift:45` builds `OnboardingViewModel(modelContext:)` directly, which breaks the "DIContainer is the only wiring point" convention.

**F5. No debug reset for feature intros.** `SettingsView.swift:90` has "Always show onboarding", but Camera / Voice / Badges / Cloud Sync / Space intros can only be seen again by deleting the app.

**F6. Coverage gaps (for awareness).** Insights and the Space list have no intro. Onboarding already covers both, so this may be intentional.

---

## Open decisions

1. F1: change the Space intro copy, or build the blind-feedback gating?
2. F2 to F5: which cleanups to do, and on which base branch (`multica-task` or `develop`)?
3. When to merge `multica-task` into `develop`.
