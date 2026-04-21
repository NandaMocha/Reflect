# Badge System v2 - Complete Specification

**Updated**: March 2026
**Version**: 2.0 - Monthly Streak Badges + Lifetime Achievement Badges

---

## 🎯 System Overview

The badge system has two distinct categories:

1. **🔥 Streak Badges** - Per-month, repeatable badges that track consecutive day streaks
2. **🏆 Achievement Badges** - Lifetime milestones that are earned once and kept forever

### Key Design Principles

- **Clarity**: No confusion about month boundaries or lost badges
- **Motivation**: Short-term (monthly) and long-term (lifetime) goals
- **Fairness**: Streak badges reset each month, achievements are permanent
- **Progressive**: Clear path from easy to challenging

---

## 🔥 STREAK BADGES (Per Month)

### Overview
- **Repeatable**: Every month starts fresh
- **Month-specific**: Users can navigate between months to see past achievements
- **Independent**: March streaks don't affect April streaks
- **UI**: Month selector `< March 2025 >` shows that month's streak badges

### Badge List

#### 1. 3-Day Streak 🔥
- **Icon**: `flame.fill`
- **Unlock**: 3 consecutive days of reflections
- **Repeatable**: Yes (each month)
- **Celebration**: Confetti
- **Difficulty**: Easy

```swift
// Check if current month has 3-day streak
func check3DayStreak(monthlyData: MonthlyStreakData) -> Bool {
    monthlyData.currentStreak >= 3
}
```

#### 2. 7-Day Streak 🔥🔥
- **Icon**: `flame.fill`
- **Unlock**: 7 consecutive days of reflections
- **Repeatable**: Yes (each month)
- **Celebration**: Sparkles
- **Difficulty**: Medium

#### 3. 14-Day Streak 🔥🔥🔥
- **Icon**: `flame.fill`
- **Unlock**: 14 consecutive days of reflections
- **Repeatable**: Yes (each month)
- **Celebration**: Fireworks
- **Difficulty**: Hard

#### 4. 30-Day Streak 🔥🔥🔥🔥
- **Icon**: `flame.fill`
- **Unlock**: 30 consecutive days of reflections
- **Repeatable**: Yes (each month)
- **Celebration**: Maximum (fireworks + confetti)
- **Difficulty**: Expert
- **Prestige**: Legendary achievement

---

## 🏆 ACHIEVEMENT BADGES (Lifetime)

### Overview
- **Permanent**: Once earned, never lost
- **Cumulative**: Based on lifetime totals
- **Categories**: Reflections, Media, Prompts, Special

---

### 📚 Category 1: Reflection Milestones

#### 1. Curious Mind (5 Reflections) ⭐
- **Icon**: `star.fill`
- **Unlock**: 5 total reflections in lifetime
- **Type**: Permanent
- **Difficulty**: Easy
- **Description**: "Every journey begins with a single step. You've started yours!"

#### 2. Dedicated Learner (10 Reflections) ⭐⭐
- **Icon**: `star.circle.fill`
- **Unlock**: 10 total reflections
- **Type**: Permanent
- **Difficulty**: Easy
- **Description**: "Building momentum, one reflection at a time"

#### 3. Consistent Creator (25 Reflections) 💫
- **Icon**: `sparkles`
- **Unlock**: 25 total reflections
- **Type**: Permanent
- **Difficulty**: Medium
- **Description**: "Making reflection your daily superpower"

#### 4. Wisdom Seeker (50 Reflections) 📖
- **Icon**: "book.fill"
- **Unlock**: 50 total reflections
- **Type**: Permanent
- **Difficulty**: Medium
- **Description**: "A growing collection of insights and discoveries"

#### 5. Reflection Master (100 Reflections) 🎓
- **Icon**: "graduationcap.fill"
- **Unlock**: 100 total reflections
- **Type**: Permanent
- **Difficulty**: Hard
- **Description**: "A century of learning - impressive dedication!"

#### 6. Seasoned Sage (250 Reflections) 🦉
- **Icon**: "lightbulb.max.fill"
- **Unlock**: 250 total reflections
- **Type**: Permanent
- **Difficulty**: Expert
- **Description**: "Your journal holds a wealth of wisdom"

#### 7. Knowledge Keeper (500 Reflections) 📚
- **Icon**: "books.vertical.fill"
- **Unlock**: 500 total reflections
- **Type**: Permanent
- **Difficulty**: Expert
- **Description**: "An extraordinary milestone of personal growth"

#### 8. Legendary Learner (1000 Reflections) 👑
- **Icon**: "crown.fill"
- **Unlock**: 1000 total reflections
- **Type**: Permanent
- **Difficulty**: Legendary
- **Description**: "You've achieved the impossible - truly remarkable!"

---

### 📸 Category 2: Media Master

#### 9. Visual Storyteller (10 with Media) 📷
- **Icon**: "camera.fill"
- **Unlock**: 10 reflections with images/videos
- **Type**: Permanent
- **Difficulty**: Easy
- **Description**: "Capturing life's moments, one memory at a time"

#### 10. Memory Maker (50 with Media) 🎞️
- **Icon**: "photo.stack"
- **Unlock**: 50 reflections with images/videos
- **Type**: Permanent
- **Difficulty**: Hard
- **Description**: "Your visual journal tells a beautiful story"

#### 11. Content Creator (100 with Media) 🎬
- **Icon**: "video.fill"
- **Unlock**: 100 reflections with images/videos
- **Type**: Permanent
- **Difficulty**: Expert
- **Description**: "A masterpiece of photos and videos"

---

### 💡 Category 3: Prompt Explorer

#### 12. Guided Path (10 with Prompts) 💡
- **Icon**: "lightbulb"
- **Unlock**: 10 reflections with guided prompts
- **Type**: Permanent
- **Difficulty**: Easy
- **Description**: "Following questions to deeper understanding"

#### 13. Deep Thinker (50 with Prompts) 🧠
- **Icon**: "brain.head.profile"
- **Unlock**: 50 reflections with guided prompts
- **Type**: Permanent
- **Difficulty**: Hard
- **Description**: "Every prompt unlocks new insights"

#### 14. Philosopher's Path (100 with Prompts) 🏛️
- **Icon**: "building.columns.fill"
- **Unlock**: 100 reflections with guided prompts
- **Type**: Permanent
- **Difficulty**: Expert
- **Description**: "Mastering the art of self-discovery"

---

### 🌟 Category 4: Special Achievements

#### 15. Monthly Champion (First Month Complete) 🏆
- **Icon**: "trophy.fill"
- **Unlock**: Complete first full month of journaling
- **Repeatable**: No (one-time only)
- **Description**: "Completed your first full month of journaling"

#### 16. Quarterly Champion (3-Month Consistency) 🎖️
- **Icon**: "medal.fill"
- **Unlock**: 90 consecutive days of reflections
- **Repeatable**: No (one-time only)
- **Description**: "90 days of unwavering consistency"

#### 17. Half-Year Hero (6-Month Consistency) 🦸
- **Icon**: "figure.run"
- **Unlock**: 180 consecutive days of reflections
- **Repeatable**: No (one-time only)
- **Description**: "180 days of dedication - extraordinary!"

#### 18. Perfectionist (Perfect Month) 💎
- **Icon**: "diamond.fill"
- **Unlock**: Reflected every single day for a full month (30/30 days)
- **Repeatable**: Yes (each month)
- **Description**: "Flawless consistency - 30 days in a row"

---

## 📊 Badge Summary Table

| Badge | Category | Type | Difficulty |
|-------|----------|------|------------|
| **Streak Badges** (Per Month) |
| 🔥 3-Day | Streak | Monthly | Easy |
| 🔥🔥 7-Day | Streak | Monthly | Medium |
| 🔥🔥🔥 14-Day | Streak | Monthly | Hard |
| 🔥🔥🔥🔥 30-Day | Streak | Monthly | Expert |
| **Achievement Badges** (Lifetime) |
| ⭐ Curious Mind | Reflections | Permanent | Easy |
| ⭐⭐ Dedicated Learner | Reflections | Permanent | Easy |
| 💫 Consistent Creator | Reflections | Permanent | Medium |
| 📖 Wisdom Seeker | Reflections | Permanent | Medium |
| 🎓 Reflection Master | Reflections | Permanent | Hard |
| 🦉 Seasoned Sage | Reflections | Permanent | Expert |
| 📚 Knowledge Keeper | Reflections | Permanent | Expert |
| 👑 Legendary Learner | Reflections | Permanent | Legendary |
| 📷 Visual Storyteller | Media | Permanent | Easy |
| 🎞️ Memory Maker | Media | Permanent | Hard |
| 🎬 Content Creator | Media | Permanent | Expert |
| 💡 Guided Path | Prompts | Permanent | Easy |
| 🧠 Deep Thinker | Prompts | Permanent | Hard |
| 🏛️ Philosopher's Path | Prompts | Permanent | Expert |
| 🏆 Monthly Champion | Special | Permanent | Medium |
| 🎖️ Quarterly Champion | Special | Permanent | Expert |
| 🦸 Half-Year Hero | Special | Permanent | Legendary |
| 💎 Perfectionist | Special | Monthly | Hard |

---

## 🎮 Usage Examples

### Example 1: January 2025 - Perfect Month
```
Jan 1: Reflection → Streak Day 1, unlocks 🌅 Monthly Start
Jan 2: Reflection → Streak Day 2
Jan 3: Reflection → Streak Day 3 → 🔥 3-Day Badge
...
Jan 7: Reflection → Streak Day 7 → 🔥🔥 7-Day Badge
Jan 14: Reflection → Streak Day 14 → 🔥🔥🔥 14-Day Badge
Jan 30: Reflection → Streak Day 30 → 🔥🔥🔥🔥 30-Day Badge
Jan 31: Reflection → Streak Day 31 (31/31 days) → 💎 Perfectionist Badge!

Total: 6 streak badges for January
Lifetime: Now has 31 total reflections (→ ⭐ Curious Mind)
```

### Example 2: February 2025 - Fresh Start
```
Feb 1: Reflection → Streak Day 1 (new month, fresh start!)
Feb 2: No reflection
Feb 3: Reflection → Streak Day 1 (counter reset)
...
Feb 28: End of month with 15-day streak

January badges: Still visible in January view (not lost!)
February badges: Shows 14-day badge earned
```

### Example 3: Media Milestones
```
Reflection #1: Just text
Reflection #2: With photo → Media Count: 1
Reflection #3: With video → Media Count: 2
...
Reflection #12: With photo → Media Count: 10 → 📷 Visual Storyteller
Reflection #53: With video → Media Count: 50 → 🎞️ Memory Maker
```

---

## 🔧 Implementation Notes

### Data Model Changes
- Each badge needs: `id`, `name`, `description`, `icon`, `category`, `badgeType`, `isUnlocked`, `unlockedAt`, `unlockedCount`
- Streak badges need: `month`, `year` for per-month tracking
- Achievement badges track: `totalCount`, `mediaCount`, `promptCount`

### UI Structure
```
Streak Detail View:
├─ Month Selector: "< January 2025 >"
├─ Streak Badges Grid (shows January's 4 badges)
└─ Achievement Badges Grid (shows all lifetime badges)

Badge Card:
├─ Icon
├─ Name
├─ Description
└─ Earned badge indicator (for achievements)
```

### Evaluation Logic
- **Streak Badges**: Evaluated each month, stored with month/year metadata
- **Reflection Milestones**: Check on every reflection save
- **Media Milestones**: Count reflections with ImageAttachment or VideoAttachment
- **Prompt Milestones**: Count reflections where prompt/guided field is not empty

---

## 💡 Key Differences from v1

| Aspect | Old System | New System |
|--------|------------|------------|
| Streak badges | One global streak | Per-month streaks |
| Month boundaries | Confusing | Clear separation |
| Lost badges | Possible? | Never! |
| Achievement types | Mixed (streaks + monthly) | Clear categories |
| Progress tracking | Unclear | Very clear |
| Motivation | Short-term only | Both short & long-term |

---

## 🎯 Design Philosophy

1. **Monthly Fresh Start**: Each month is a clean slate for streaks
2. **Historical Preservation**: Past achievements are never lost
3. **Multiple Paths**: Users can excel at streaks, media, or prompts
4. **Clear Goals**: Always know what to aim for next
5. **Fair Play**: Missing a day doesn't lose lifetime achievements

---

Ready to implement? See **IMPLEMENTATION_STATUS.md**
