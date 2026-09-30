# Quick Actions widget

Home screen widget (extension target `Quick ActionsExtension`) that opens Reflect straight into a capture flow, and on the medium size shows a daily quote.

## Families

Only `systemSmall` and `systemMedium` ship. Large and Lock Screen accessory families are not planned until the owner confirms them.

| Family | Default text sizes | Accessibility text sizes |
|---|---|---|
| Small | Labelled Write tile on top, Photo, Voice and Insight as icon tiles below | 2 x 2 icon grid, no labels |
| Medium | 2 x 2 grid of labelled action tiles, daily quote on the right | Icon-only grid, quote without the quote mark |

Text uses text styles (`.headline`, `.footnote`, `.caption2`) with `lineLimit` and `minimumScaleFactor`, so it scales with Dynamic Type and shrinks instead of overflowing. Icons stop growing at `xxxLarge` so four tiles always fit.

## Actions and deep links

| Action | URL | VoiceOver label |
|---|---|---|
| Write | `reflect://write` | Write a reflection |
| Photo | `reflect://camera` | Photo reflection |
| Voice | `reflect://voice` | Voice reflection |
| Insight | `reflect://insight` | Add an insight |

URLs come from `WidgetDeepLink` (`Shared/Widget/WidgetDeepLink.swift`), which both the widget and the app use, so they can't drift. The app parses them in `ReflectApp.handleWidgetURL`. Actions are defined in `Shared/Widget/QuickAction.swift`.

The quote comes from `DailyQuote.forDate(_:)` and follows the time of day. There are three pools with their own tone: morning (05:00 to 11:59, a fresh start), afternoon (12:00 to 17:59, keep going) and evening (18:00 to 04:59, reflect on today and look toward tomorrow). Each pool rotates one quote per day, so the quote is stable within a slot and changes at 05:00, 12:00 and 18:00. The hours after midnight still belong to the previous evening. `QuickActionsTimeline.nextRefreshDate(after:)` schedules the widget refresh at the next slot boundary.

## Code layout

- `Quick Actions/Quick_Actions.swift`: `Widget` configuration and `QuickActionsProvider` only.
- `Shared/Widget/QuickActionsWidgetView.swift`: `QuickActionsWidgetView` picks `SmallQuickActionsView` or `MediumQuickActionsView` from `widgetFamily`. The two views live in `Shared/` so the app's `ReflectTests` target can render them.
- `Shared/Widget/WidgetPalette.swift` and `Shared/Widget/WidgetColors.xcassets`: colour tokens.

## Colour tokens

All widget colours are in `WidgetColors.xcassets` with light and dark variants. No hex values in the views.

| Token | Use | Minimum contrast |
|---|---|---|
| `WidgetBackground` | Widget container background | Surface |
| `WidgetCardSurface` | Action tiles | Surface |
| `WidgetTextPrimary` | Action labels, quote | 4.5:1 |
| `WidgetTextSecondary` | Quote author | 4.5:1 |
| `WidgetActionWrite`, `WidgetActionPhoto`, `WidgetActionVoice`, `WidgetActionInsight` | Action icons, quote mark | 3:1 |

`WidgetContrastTests` checks every text and icon token against both surfaces in light and dark. In tinted and clear modes (iOS 18+) the tiles switch to a faint `.quaternary` fill, text switches to `.primary` / `.secondary`, and icons are `.widgetAccentable()`.

## Tests

- `ReflectTests/Widget/WidgetContrastTests.swift`: WCAG helper and token contrast.
- `ReflectTests/Widget/WidgetRenderTests.swift`: both families x light/dark x `.large`/`.accessibility3` x shortest/longest quote. Checks the fitted size stays inside the content area and attaches an `ImageRenderer` PNG per case to the test result.

## Owner device checklist

Needs a real device. Tick each one in light and in dark appearance.

- [ ] Add the small widget and the medium widget to the home screen. Nothing overlaps, clips or runs off a tile.
- [ ] Settings > Accessibility > Display & Text Size > Larger Text, set the largest accessibility size. Both widgets switch to the icon grid, the quote still fits and the author line is readable.
- [ ] VoiceOver on: swipe through each widget. Order is Write, Photo, Voice, Insight, then the quote. Each action reads its label and hint ("Write a reflection", "Opens Reflect to write a new reflection."). The quote reads as one element ("Daily quote: ..., by ..."). No SF Symbol names are read.
- [ ] iOS 18+: long press the home screen > Edit > Customize, try Tinted and Clear. Icons stay visible and tiles don't turn into solid blocks.
- [ ] Tap Write: the reflection editor opens.
- [ ] Tap Photo: the camera capture flow opens.
- [ ] Tap Voice: the voice recording flow opens.
- [ ] Tap Insight: the add insight flow opens.
- [ ] Check the medium widget after 05:00, 12:00 and 18:00: the quote has changed and its tone matches the time of day.
