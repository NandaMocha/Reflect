# Complete Badge Specification

---

## 🔥 REPEATABLE BADGES

### 3-Day Streak `🔥`
- **Unlock**: When `currentStreak >= 3` and was `< 3`
- **Repeatable**: Yes (after streak breaks and rebuilds)
- **Trigger**: Automatic on day 3
- **Celebration**: Confetti

```swift
func check3DayStreak(previousStreak: Int, currentStreak: Int) -> Bool {
    previousStreak < 3 && currentStreak >= 3
}
```

---

### 7-Day Streak `🔥🔥`
- **Unlock**: When `currentStreak >= 7` and was `< 7`
- **Repeatable**: Yes
- **Trigger**: Automatic on day 7
- **Celebration**: Sparkles

```swift
func check7DayStreak(previousStreak: Int, currentStreak: Int) -> Bool {
    previousStreak < 7 && currentStreak >= 7
}
```

---

### 14-Day Streak `🔥🔥🔥`
- **Unlock**: When `currentStreak >= 14` and was `< 14`
- **Repeatable**: Yes
- **Trigger**: Automatic on day 14
- **Celebration**: Fireworks

```swift
func check14DayStreak(previousStreak: Int, currentStreak: Int) -> Bool {
    previousStreak < 14 && currentStreak >= 14
}
```

---

### 30-Day Streak `🔥🔥🔥🔥`
- **Unlock**: When `currentStreak >= 30` and was `< 30`
- **Repeatable**: Yes (can earn multiple times with month-long streaks)
- **Trigger**: Automatic on day 30
- **Celebration**: Maximum (fireworks + confetti)
- **Rarity**: Moderate (requires dedication)

```swift
func check30DayStreak(previousStreak: Int, currentStreak: Int) -> Bool {
    previousStreak < 30 && currentStreak >= 30
}
```

---

### Monthly Start `🌅`
- **Unlock**: Reflection on 1st day of any month
- **Repeatable**: Yes (up to 12 times per year)
- **Trigger**: Automatic on submission if `day == 1`
- **Celebration**: Soft sparkles
- **Frequency**: Once per month opportunity

```swift
func checkFirstDayOfMonth(submittedDate: Date) -> Bool {
    Calendar.current.component(.day, from: submittedDate) == 1
}
```

**Special**: If first reflection ever on Jan 1st, unlocks both 🌟 + 🌅 simultaneously

---

## ⭐ PERMANENT BADGES

### First Reflection `🌟`
- **Unlock**: On very first reflection (when `totalReflections == 1`)
- **Permanent**: Yes (one-time only)
- **Trigger**: Automatic on 1st submission
- **Celebration**: Confetti
- **Uniqueness**: Everyone gets this

```swift
func checkFirstReflection(totalReflections: Int, alreadyUnlocked: Bool) -> Bool {
    totalReflections == 1 && !alreadyUnlocked
}
```

---

### Full Month `📅`
- **Unlock**: 30+ reflections in a calendar month
- **Permanent**: Yes, per month (can earn multiple times in different months)
- **Trigger**: Daily recalculation
- **Celebration**: Yes
- **Important**: NOT about consecutive days, just 30 reflections anytime in month

```swift
func checkFullMonth(month: MonthlyAchievement) -> Bool {
    month.reflectionCount >= 30 && !month.hasFullMonth
}
```

**Example**:
- Mar 1: 1 reflection
- Mar 5: 2 reflections
- Mar 10: 3 reflections
- ...continuing...
- Mar 31: Total reaches 30+
- Result: ✓ Full Month badge for March

---

### Half Month `📅✨`
- **Unlock**: 14+ reflections in a calendar month
- **Permanent**: Yes, per month (can earn multiple times)
- **Trigger**: Daily recalculation
- **Celebration**: Yes
- **Lower bar**: For when full month isn't possible

```swift
func checkHalfMonth(month: MonthlyAchievement) -> Bool {
    month.reflectionCount >= 14 && !month.hasHalfMonth
}
```

**Example**:
- Feb 1-14: One reflection each day = 14 total
- Result: ✓ Half Month badge for February

---

### 6-Month Consistency `🏆`
- **Unlock**: 1+ reflection in each of last 6 CONSECUTIVE calendar months
- **Permanent**: Yes (one-time only)
- **Trigger**: Monthly consistency check
- **Celebration**: Major celebration
- **Strictness**: Must be 6 consecutive months (no gaps)

```swift
func check6MonthConsistency(achievements: [MonthlyAchievement]) -> Bool {
    let last6Months = getLast6ConsecutiveMonths()
    return last6Months.allSatisfy { month in
        achievements.first(where: { $0.yearMonthString == month.yearMonthString })?.hasAnyReflection ?? false
    }
}
```

**Example**:
```
Current: March 2026
Required: Mar, Feb, Jan, Dec, Nov, Oct (all must have 1+ reflection)

✓ March 2026: Has reflection
✓ February 2026: Has reflection
✓ January 2026: Has reflection
✓ December 2025: Has reflection
✓ November 2025: Has reflection
✓ October 2025: Has reflection
Result: 🏆 Unlocked!

If November had 0 reflections:
✗ Badge NOT unlocked (must be consecutive)
```

---

### 12-Month Consistency `👑`
- **Unlock**: 1+ reflection in each of last 12 CONSECUTIVE calendar months
- **Permanent**: Yes (one-time only, legendary)
- **Trigger**: Monthly consistency check
- **Celebration**: MAXIMUM celebration
- **Rarity**: Very rare (requires 1 year of consistency)
- **Strictness**: Must be 12 consecutive months (no gaps)

```swift
func check12MonthConsistency(achievements: [MonthlyAchievement]) -> Bool {
    let last12Months = getLast12ConsecutiveMonths()
    return last12Months.allSatisfy { month in
        achievements.first(where: { $0.yearMonthString == month.yearMonthString })?.hasAnyReflection ?? false
    }
}
```

**Example**:
```
Current: March 2027
Required: Mar 2026 through Mar 2027 (all must have 1+ reflection)

✓ All 12 months have reflections
Result: 👑 Unlocked! (Legendary achievement!)

If any single month had 0 reflections:
✗ Badge NOT unlocked
```

---

## 📊 Badge Summary Table

| Badge | Type | Repeats | Trigger | Celebration |
|-------|------|---------|---------|------------|
| 🔥 3-Day | Repeatable | Yes* | Day 3 of streak | Confetti |
| 🔥🔥 7-Day | Repeatable | Yes* | Day 7 of streak | Sparkles |
| 🔥🔥🔥 14-Day | Repeatable | Yes* | Day 14 of streak | Fireworks |
| 🔥🔥🔥🔥 30-Day | Repeatable | Yes* | Day 30 of streak | Maximum |
| 🌅 Monthly Start | Repeatable | 12x/year | On 1st of month | Soft sparkles |
| 🌟 First | Permanent | Never | 1st reflection | Confetti |
| 📅 Full Month | Permanent | Monthly | 30+ reflections | Yes |
| 📅✨ Half Month | Permanent | Monthly | 14+ reflections | Yes |
| 🏆 6-Month | Permanent | Never | 6 months consistency | Major |
| 👑 12-Month | Permanent | Never | 12 months consistency | Maximum |

*Repeatable after streak breaks and rebuilds

---

## 🎮 Earning Examples

### January 1, 2026 (First Reflection Ever)
```
User creates first reflection on Jan 1st

Unlocks:
1. 🌟 First Reflection (very first ever)
2. 🌅 Monthly Start (day == 1)
3. Streak: Day 1

Celebration: MAJOR (double badge!)
```

### January 1-30 (30-Day Streak)
```
Day 1: Reflection → Streak: 1
Day 2: Reflection → Streak: 2
Day 3: Reflection → Streak: 3 → 🔥 Badge
Day 7: Reflection → Streak: 7 → 🔥🔥 Badge
Day 14: Reflection → Streak: 14 → 🔥🔥🔥 Badge
Day 30: Reflection → Streak: 30 → 🔥🔥🔥🔥 Badge
Month end: 30 reflections → 📅 Full Month Badge

Result: 5 badges in one month!
```

### January 31 (Break Streak)
```
No reflection submitted on Jan 31
Streak: 0 (broken)
```

### February 1 (Restart)
```
Create reflection on Feb 1
Streak: Day 1 (new cycle)
🌅 Monthly Start (Feb's first-day)

Can earn 3-day badge again if streak reaches 3
```

### January 2026 - August 2026 (6 Months)
```
Create 1+ reflection each month:
✓ Jan 2026
✓ Feb 2026
✓ Mar 2026
✓ Apr 2026
✓ May 2026
✓ Jun 2026

Result: 🏆 6-Month Consistency Badge!
```

---

## 🎯 Key Rules

1. **Streak resets**: When user misses a day
2. **Monthly badges independent**: From streak (can have both in same month)
3. **Consistency requires no gaps**: 6 or 12 months must be consecutive
4. **First-day bonus**: Can unlock twice if also first reflection
5. **Repeatable badges**: Can be earned again after streak breaks
6. **One reflection per day**: Only counts once for streak, but all count for monthly total

---

## 💡 Badge Difficulty Ranking

**Easy**:
- 🌅 Monthly Start (just remember 1st)
- 🌟 First Reflection (automatic)

**Medium**:
- 🔥 3-Day Streak
- 📅✨ Half Month

**Hard**:
- 🔥🔥 7-Day Streak
- 🔥🔥🔥 14-Day Streak
- 📅 Full Month

**Expert**:
- 🔥🔥🔥🔥 30-Day Streak
- 🏆 6-Month Consistency
- 👑 12-Month Consistency

---

Ready for algorithms? See **03_ALGORITHMS.md**
