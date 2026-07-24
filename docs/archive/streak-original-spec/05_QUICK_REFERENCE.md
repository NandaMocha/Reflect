# Quick Reference Guide

---

## 🎯 The 10 Badges at a Glance

### Repeatable (5)
```
🔥           3-Day Streak         Streak >= 3 & prev < 3
🔥🔥         7-Day Streak         Streak >= 7 & prev < 7
🔥🔥🔥       14-Day Streak        Streak >= 14 & prev < 14
🔥🔥🔥🔥     30-Day Streak        Streak >= 30 & prev < 30
🌅           Monthly Start        day(submittedDate) == 1
```

### Permanent (5)
```
🌟           First Reflection     totalReflections == 1
📅           Full Month           30+ in calendar month
📅✨         Half Month           14+ in calendar month
🏆           6-Month Consistency  1+ in each of 6 consecutive months
👑           12-Month Consistency 1+ in each of 12 consecutive months
```

---

## 🔄 When Badges Unlock

| Badge | Trigger | When | Check |
|-------|---------|------|-------|
| 🔥 3-Day | Immediate | On day 3 | Streak calc |
| 🔥🔥 7-Day | Immediate | On day 7 | Streak calc |
| 🔥🔥🔥 14-Day | Immediate | On day 14 | Streak calc |
| 🔥🔥🔥🔥 30-Day | Immediate | On day 30 | Streak calc |
| 🌅 Monthly Start | Immediate | On 1st day | Day check |
| 🌟 First | Immediate | 1st reflection | Count check |
| 📅 Full Month | Daily (midnight) | When 30+ | Monthly count |
| 📅✨ Half Month | Daily (midnight) | When 14+ | Monthly count |
| 🏆 6-Month | Daily (midnight) | 6 months | Consistency |
| 👑 12-Month | Daily (midnight) | 12 months | Consistency |

---

## 📊 Streak Logic

### Calculate Streak
```
Sort reflections by date DESC
Start from today
Count backwards while consecutive (day gap <= 1)
Stop on first gap > 1 day
Return count
```

### Streak Resets
- Misses a day → Streak = 0
- Can restart and re-earn badges
- Example: 3-day → break → 3-day = earn badge twice

---

## 📅 Monthly Logic

### How It Works
1. Group reflections by calendar month (YYYY-MM)
2. Count total reflections per month
3. Check badges (30+ = full, 14+ = half)
4. Track if month has any reflection

### Consistency Check
```
Last 6 months: Mar, Feb, Jan, Dec, Nov, Oct
Must all have hasAnyReflection == true
If any month has 0: badge NOT earned
```

---

## 🎮 User Flow Example

```
Jan 1:  Create reflection → 🌟 + 🌅 (double!)
Jan 2:  Reflection → Streak: 2
Jan 3:  Reflection → Streak: 3 → 🔥 Badge
...
Jan 7:  Reflection → Streak: 7 → 🔥🔥 Badge
...
Jan 14: Reflection → Streak: 14 → 🔥🔥🔥 Badge
...
Jan 30: Reflection → Streak: 30 → 🔥🔥🔥🔥 Badge + 📅 (30 total)
Jan 31: No reflection → Streak: 0 (broken)

Feb 1:  Reflection → Streak: 1 (restart) + 🌅 (Feb's start)
...
Feb-Aug: Continue with 1+ per month
Sep:    Months 1-6 complete → 🏆 (6-month badge)
...
Mar 27: After 12 months → 👑 (12-month badge)
```

---

## 🔍 Key Checks

### Streak Badge Check
```swift
newStreak >= 3 && previousStreak < 3  // 3-day
newStreak >= 7 && previousStreak < 7  // 7-day
newStreak >= 14 && previousStreak < 14  // 14-day
newStreak >= 30 && previousStreak < 30  // 30-day
```

### First Day Check
```swift
Calendar.current.component(.day, from: date) == 1
```

### Monthly Badge Check
```swift
count >= 30 && !hasFullMonth  // Full month
count >= 14 && !hasHalfMonth  // Half month
```

### Consistency Check
```swift
// Get last 6 consecutive months
// Check that ALL have at least 1 reflection
last6Months.allSatisfy { $0.hasAnyReflection }
```

---

## 📱 UI Components

| Component | Purpose | Shows |
|-----------|---------|-------|
| StreakHeaderCard | MainTab badge | 🔥 count, longest |
| StreakProgressBar | Progress toward next | Visual meter |
| MonthlyCalendarHeatmap | Calendar view | Grid + color |
| BadgeCard | Individual badge | Icon, unlock date |
| BadgeGridView | All badges | Grid of 10 |
| CelebrationView | Animation | Confetti, sparkles |

---

## 📊 Badge Stats

```
Probability of earning (typical user):
🌟 First:     100%  (first user action)
🌅 Monthly:   ~40%  (12x/year opportunity)
🔥 3-Day:     ~70%  (easy)
🔥🔥 7-Day:   ~50%  (medium)
🔥🔥🔥 14-Day: ~30% (harder)
📅✨ Half:    ~40%  (achievable)
📅 Full:      ~20%  (rare)
🔥🔥🔥🔥 30-Day: ~15% (very rare)
🏆 6-Month:   ~10%  (dedicated user)
👑 12-Month:  ~2%   (exceptional)
```

---

## 🎯 Celebration Levels

```
No celebration:     Regular reflection
Confetti:           3-day streak, first reflection
Sparkles:           7-day streak, monthly start
Fireworks:          14-day streak
Maximum:            30-day streak, consistency badges
```

---

## 🔧 Data Model Locations

```
Badge                  → Domain/Models/Badge.swift
StreakData             → Domain/Models/StreakData.swift
MonthlyAchievement     → Domain/Models/MonthlyAchievement.swift
BadgeID                → Domain/Models/BadgeID.swift
StreakStats            → Domain/Models/StreakStats.swift (non-persistent)
MonthHeatmapData       → Domain/Models/MonthHeatmapData.swift (non-persistent)
Reflection (enhanced)  → Update existing Reflection.swift
```

---

## 📚 File Structure

```
Reflect/
├── Domain/
│   ├── Models/
│   │   ├── Badge.swift
│   │   ├── StreakData.swift
│   │   ├── MonthlyAchievement.swift
│   │   ├── BadgeID.swift
│   │   ├── StreakStats.swift
│   │   └── MonthHeatmapData.swift
│   ├── Services/
│   │   ├── StreakCalculationService.swift
│   │   └── BadgeService.swift
│   └── UseCases/
│       ├── Streak/
│       └── Badge/
│
├── Data/
│   └── Repositories/
│       ├── Protocols/
│       └── Implementations/
│
└── Presentation/
    └── Features/
        ├── Streak/
        │   ├── StreakViewModel.swift
        │   └── Views/
        └── MainTab/
            └── MainTabView.swift (update)
```

---

## 🚀 Implementation Checklist

- [ ] Create all 7 models (Badge, StreakData, MonthlyAchievement, BadgeID, StreakStats, MonthHeatmapData, update Reflection)
- [ ] Create 3 repository protocols
- [ ] Create 3 repository implementations
- [ ] Create StreakCalculationService
- [ ] Create BadgeService
- [ ] Create 6 Use Cases
- [ ] Create StreakViewModel
- [ ] Create UI components (9+)
- [ ] Update DIContainer
- [ ] Update MainTab
- [ ] Add animations
- [ ] Unit tests
- [ ] Integration tests
- [ ] Manual testing

---

## ⚡ Performance Tips

1. **Cache StreakData** in UserDefaults or memory
2. **Use @Index** on SwiftData models for dates
3. **Batch monthly updates** at midnight (not per submission)
4. **Lazy load heatmap** (only current month initially)
5. **Load badges once** per session

---

## 🧪 Critical Test Cases

```
✓ 3 consecutive days unlock 3-day badge
✓ Skip 1 day breaks streak
✓ Rebuild streak works
✓ First day of month unlocks 🌅
✓ 30 reflections in month = 📅
✓ 14 reflections in month = 📅✨
✓ 6 consecutive months = 🏆
✓ 12 consecutive months = 👑
✓ Timezone handling (day changes at local midnight)
✓ Month boundaries work (Feb 28 → Mar 1)
✓ Multiple reflections same day count as 1 for streak
✓ All calendar days show correct colors
```

---

## 💾 Database Queries Needed

```swift
// ReflectionRepository
func getSubmissionsInDateRange(_ start: Date, _ end: Date)
func getLastSubmissionDate() -> Date?
func getStreakSubmissions() -> [Reflection]

// StreakRepository
func getOrCreateStreakData() -> StreakData
func updateStreakData(_ data: StreakData)

// BadgeRepository
func getOrCreateBadge(id: String) -> Badge
func getAllBadges() -> [Badge]
func getUnlockedBadges() -> [Badge]

// MonthlyAchievementRepository
func getOrCreateAchievement(month: String) -> MonthlyAchievement
func getAchievementsForMonths(_ months: [String]) -> [MonthlyAchievement]
```

---

## 🎯 Success Criteria

When complete:
- [ ] Create daily reflection for 30 days → all 4 streak badges unlock
- [ ] Skip day → streak resets
- [ ] Calendar heatmap shows color progression
- [ ] Monthly badges unlock at 14+ and 30+
- [ ] Consistency badges track 6 and 12 months
- [ ] Celebrations trigger with correct animations
- [ ] No performance issues
- [ ] All code follows SOLID
- [ ] Full test coverage

---

**Need details?** See the full documentation files:
- 01_OVERVIEW.md - Architecture overview
- 02_BADGES.md - Badge specifications
- 03_ALGORITHMS.md - Algorithms & pseudocode
- 04_MODELS.md - Data models (copy-paste ready)
- 05_QUICK_REFERENCE.md - This file
