# Getting Started

## Requirements

| | Minimum |
|---|---|
| macOS | 14 (Sonoma) |
| Xcode | 15.0 |
| Swift | 6.0 |
| iOS deployment target | 17.0 |

Xcode 15+ is required for the Swift 6 toolchain, Observation framework, and SwiftData.

## Clone & open

```bash
git clone <repo-url>
cd Reflect
open Reflect.xcodeproj
```

No package manager setup needed — there are no external SPM or CocoaPods dependencies at this time.

## Schemes

- **Reflect** — main iOS app
- **Quick Actions** — app extension (widget / Lock Screen quick actions)

Select **Reflect**, pick a simulator (or a connected device signed into iCloud if you want to test sync), and press **Cmd+R**.

## First launch

On first launch the app:

1. Initializes a `ModelContainer` for SwiftData with all `@Model` classes (`Learning`, `Reflection`, `Badge`, `MonthlyAchievement`, etc.).
2. Configures `DIContainer.shared` with the main `ModelContext`.
3. Shows the onboarding flow (`Presentation/Features/Onboarding/`).

If you're testing with an empty database and want badge unlock celebrations to fire, create reflections in quick succession until you hit a milestone (5, 10, 25, …). See [features/achievement.md](features/achievement.md) for the full list.

## Testing

**There is no test target yet.** Adding one is a planned follow-up — see [reviews/achievement-counter-review.md](reviews/achievement-counter-review.md). When it lands, expected framework is **Swift Testing** (not XCTest) and the target will live alongside `Reflect.xcodeproj`.

## iCloud / CloudKit

The app uses CloudKit for cross-device backup. In Xcode:

- Signing & Capabilities → CloudKit capability is already enabled
- Your Apple ID must be signed into iCloud on the simulator/device for sync to work
- Container identifier: `iCloud.com.reflectlearn.app` (see `Constants.App.iCloudContainerId`)

## Troubleshooting

**"ModelContext not configured"** — `DIContainer.shared.configure(with:)` wasn't called before a factory method. This should be impossible in the normal app lifecycle; if it happens during previews, inject a context manually in the `#Preview` block.

**Build fails on `@preconcurrency @Model`** — You're on Swift < 6. Upgrade Xcode.

**Badges don't unlock on reflection save** — Check `CreateReflectionUseCase.execute` posts `.badgesDidUnlock` / `.badgeProgressDidUpdate`, and `BadgeGridView` is mounted to receive. Known review items in [reviews/achievement-counter-review.md](reviews/achievement-counter-review.md).
