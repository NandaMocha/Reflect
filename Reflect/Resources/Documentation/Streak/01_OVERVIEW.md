# Streak & Badge System - Implementation Overview

**Last Updated**: March 7, 2026
**Status**: Complete specification, ready for implementation
**Difficulty**: Moderate
**Timeline**: 4 weeks

---

## 🎯 Feature Summary

A complete offline-first gamification system featuring:
- **10 unique badges** (5 repeatable + 5 permanent)
- **1-month calendar heatmap** (GitHub-style visualization)
- **Streak tracking** (current + longest streak)
- **Monthly achievements** (full/half month badges)
- **Consistency tracking** (6 & 12-month badges)
- **Celebration animations** (confetti, sparkles, fireworks)

---

## 📋 The 10 Badges

### Repeatable Badges (5)
| Badge | Icon | Criteria |
|-------|------|----------|
| 3-Day Streak | 🔥 | 3 consecutive days with reflections |
| 7-Day Streak | 🔥🔥 | 7 consecutive days with reflections |
| 14-Day Streak | 🔥🔥🔥 | 14 consecutive days with reflections |
| 30-Day Streak | 🔥🔥🔥🔥 | 30 consecutive days with reflections |
| Monthly Start | 🌅 | Reflection on 1st day of any month |

### Permanent Badges (5)
| Badge | Icon | Criteria |
|-------|------|----------|
| First Reflection | 🌟 | Create your first reflection ever |
| Full Month | 📅 | 30+ reflections in a calendar month |
| Half Month | 📅✨ | 14+ reflections in a calendar month |
| 6-Month Consistency | 🏆 | 1+ reflection in each of 6 consecutive months |
| 12-Month Consistency | 👑 | 1+ reflection in each of 12 consecutive months |

---

## 🏗️ Architecture Overview

### Data Models (4 total)
- **Badge** - Badge state, unlock count, unlock dates
- **StreakData** - Current/longest streak, total reflections
- **MonthlyAchievement** - Monthly reflection count, achievement flags
- **Reflection** (enhanced) - Add `submittedDate` and `isStreakSubmission`

### Services & Business Logic
- **StreakCalculationService** - Calculate streaks from reflection dates
- **BadgeService** - Evaluate badge unlock criteria

### Use Cases (6)
- CalculateStreakUseCase
- GetStreakStatsUseCase
- EvaluateBadgesUseCase
- GetUnlockedBadgesUseCase
- RecalculateMonthlyAchievementsUseCase
- GetStreakSubmissionsUseCase

### Repositories (3)
- StreakRepository
- BadgeRepository
- MonthlyAchievementRepository

### ViewModels (2)
- StreakViewModel (@Observable)
- BadgeGridViewModel

### UI Components (9+)
- StreakHeaderCard
- MonthlyCalendarHeatmap
- BadgeCard
- BadgeGridView
- StreakProgressBar
- HeatmapDayCell
- FlameAnimation
- ConfettiView
- CelebrationView

---

## 📊 Implementation Phases

### Phase 1: Data Models (Week 1) - ~460 lines
- Create Badge, StreakData, MonthlyAchievement models
- Create repository protocols
- Create repository implementations
- Update DIContainer

### Phase 2: Business Logic (Week 2) - ~730 lines
- Create StreakCalculationService
- Create BadgeService
- Create 6 Use Cases
- Write unit tests

### Phase 3: Repositories (Week 2) - ~260 lines
- Implement all 3 repositories
- Efficient date-range queries
- Indexed models for performance

### Phase 4: ViewModel (Week 3) - ~210 lines
- StreakViewModel with @Observable
- State management for badges
- Celebration trigger logic

### Phase 5: UI & Integration (Week 3-4) - ~850 lines
- Calendar heatmap component
- Badge display components
- Animations and celebrations
- MainTab integration

### Phase 6: Testing & Polish (Week 4)
- Unit tests for all logic
- Integration tests
- Manual testing
- Bug fixes

---

## 🔄 Badge Evaluation Triggers

### On Reflection Submission (Immediate)
1. Calculate current streak
2. Check 3, 7, 14, 30-day badges
3. Check first-day-of-month badge
4. Check first reflection badge
5. Show celebration if badge unlocked

### Nightly (Midnight)
1. Recalculate monthly reflection counts
2. Check full/half month badges
3. Check 6 & 12-month consistency badges
4. Notify user of new badges

---

## 💾 Database Schema

### Reflection (Enhanced)
```swift
@Model
final class Reflection {
    // Existing...
    var submittedDate: Date?       // When user submitted
    var isStreakSubmission: Bool    // For streak counting
}
```

### Badge (New)
```swift
@Model
final class Badge {
    @Attribute(.unique) var id: String
    var type: BadgeType  // repeatedStreak or permanent
    var name: String
    var description: String
    var icon: String
    var isUnlocked: Bool = false
    var unlockedAt: Date?
    var unlockedCount: Int = 0
}
```

### StreakData (New)
```swift
@Model
final class StreakData {
    @Attribute(.unique) var id: UUID = UUID()
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastSubmissionDate: Date?
    var streakStartDate: Date?
    var totalReflections: Int = 0
}
```

### MonthlyAchievement (New)
```swift
@Model
final class MonthlyAchievement {
    @Attribute(.unique) var id: String  // "YYYY-MM"
    var year: Int
    var month: Int
    var reflectionCount: Int = 0
    var hasFullMonth: Bool = false      // 30+
    var hasHalfMonth: Bool = false      // 14+
    var hasAnyReflection: Bool = false  // 1+
    var hasFirstDayReflection: Bool = false
}
```

---

## 🎨 UI Layout

### MainTab with Streak Card
```
┌─────────────────────────────┐
│ 🔥 5-Day Streak             │
│ Longest: 14 days            │
│ [View Calendar]             │
└─────────────────────────────┘
```

### Modal with Calendar + Badges
```
┌──────────────────────────────────┐
│ March 2026                       │
│ Mo Tu We Th Fr Sa Su             │
│ 🟩🟩🟩🟩🟩🟩⬜ (dark = more days)│
│ 🟩🟩🟩🟩🟩⬜⬜                  │
│ 🟩🟩🟩🟩⬜⬜⬜                  │
│                                  │
│ [🔥] [🔥🔥] [🔥🔥🔥]         │
│ [🌅] [🌟] [📅] [🏆]         │
└──────────────────────────────────┘
```

---

## ✨ Key Features

✅ **Offline-First**: All calculations local
✅ **MVVM Architecture**: Clean code structure
✅ **No Dependencies**: Uses only built-in frameworks
✅ **Efficient Queries**: Indexed by date
✅ **Celebrations**: Confetti, sparkles, fireworks
✅ **Progress Tracking**: Toward next badge
✅ **Edge Cases Handled**: Timezone, month boundaries

---

## 📈 Statistics

| Metric | Count |
|--------|-------|
| Total Badges | 10 |
| Repeatable | 5 |
| Permanent | 5 |
| Data Models | 4 |
| Repositories | 3 |
| Services | 2 |
| Use Cases | 6 |
| UI Components | 9+ |
| Total New Code | ~2,500 lines |
| Implementation Files | ~40 |
| Timeline | 4 weeks |

---

## 🚀 Next Steps

1. **Review documentation** in this folder
2. **Understand all 10 badges** (see BADGES.md)
3. **Study algorithms** (see ALGORITHMS.md)
4. **Follow implementation guide** (see IMPLEMENTATION.md)
5. **Use models** (see MODELS.swift)

---

## 📚 Documentation Files

- **01_OVERVIEW.md** - This file (high-level overview)
- **02_BADGES.md** - Complete badge specifications
- **03_ALGORITHMS.md** - Badge evaluation logic and pseudocode
- **04_MODELS.md** - Data model code (copy-paste ready)
- **05_IMPLEMENTATION.md** - Week-by-week implementation guide
- **06_QUICK_REFERENCE.md** - Quick lookup tables

---

## 💡 Implementation Tips

1. **Start with data models** - Everything else depends on them
2. **Test calculations separately** - Unit test all badge logic before UI
3. **Build UI on solid foundation** - Don't build UI until logic is complete
4. **Use UserDefaults for cache** - Cache streak stats between submissions
5. **Celebrate appropriately** - Different celebrations for different badges

---

Ready to start? Begin with **02_BADGES.md** to understand all 10 badges in detail.
