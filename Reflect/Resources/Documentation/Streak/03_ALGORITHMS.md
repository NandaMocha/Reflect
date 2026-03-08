# Badge Evaluation Algorithms

---

## 🔄 Streak Calculation Algorithm

### Input
Array of Reflection objects with `submittedDate` and `isStreakSubmission` flag

### Process

```pseudocode
func calculateCurrentStreak(reflections: [Reflection]) -> Int {
    1. Filter reflections where isStreakSubmission == true
    2. Sort by submittedDate descending (newest first)
    3. Start from today's date
    4. Count consecutive days backwards:
       - If reflection exists on today: count++, move to yesterday
       - If reflection exists on yesterday: count++, move to yesterday
       - If gap > 1 day: break (streak is broken)
       - If no reflection on today: streak might start from yesterday
    5. Return count
}
```

### Swift Implementation

```swift
func calculateCurrentStreak(reflections: [Reflection]) -> Int {
    let streakSubmissions = reflections
        .filter { $0.isStreakSubmission }
        .sorted { $0.submittedDate ?? Date() > $1.submittedDate ?? Date() }

    var streak = 0
    var checkDate = Calendar.current.startOfDay(for: .now)

    for reflection in streakSubmissions {
        guard let reflectionDay = reflection.submittedDate else { continue }
        let reflectionStartOfDay = Calendar.current.startOfDay(for: reflectionDay)

        // Check if dates match (same day)
        if checkDate == reflectionStartOfDay {
            streak += 1
            checkDate = Calendar.current.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        // Check if one day gap (consecutive)
        else if Calendar.current.dateComponents([.day], from: reflectionStartOfDay, to: checkDate).day == 1 {
            streak += 1
            checkDate = reflectionStartOfDay
        }
        // Gap > 1 day, streak is broken
        else {
            break
        }
    }

    return streak
}
```

---

## 🔍 Streak Badges Evaluation

### On Submission

```pseudocode
func evaluateStreakBadges(newStreak: Int, previousStreak: Int) -> [Badge] {
    var unlockedBadges: [Badge] = []

    if previousStreak < 3 AND newStreak >= 3:
        unlockedBadges.append(badgeFor("3day-streak"))
    if previousStreak < 7 AND newStreak >= 7:
        unlockedBadges.append(badgeFor("7day-streak"))
    if previousStreak < 14 AND newStreak >= 14:
        unlockedBadges.append(badgeFor("14day-streak"))
    if previousStreak < 30 AND newStreak >= 30:
        unlockedBadges.append(badgeFor("30day-streak"))

    return unlockedBadges
}
```

### Celebration Logic

```swift
func getCelebrationForStreak(_ newStreak: Int, previousStreak: Int) -> Celebration {
    if previousStreak < 30 && newStreak >= 30 {
        return .maximum  // Fireworks + confetti
    } else if previousStreak < 14 && newStreak >= 14 {
        return .fireworks
    } else if previousStreak < 7 && newStreak >= 7 {
        return .sparkles
    } else if previousStreak < 3 && newStreak >= 3 {
        return .confetti
    }
    return .none
}
```

---

## 📅 Monthly Achievement Calculation

### Daily Update (Nightly at Midnight)

```pseudocode
func updateMonthlyAchievements() {
    for month in lastNMonths(12):
        reflections = getReflectionsForMonth(month)
        count = reflections.count
        hasFirstDay = any(reflections where day == 1)

        achievement = getOrCreateMonthlyAchievement(month)
        achievement.reflectionCount = count
        achievement.hasAnyReflection = count > 0
        achievement.hasFullMonth = count >= 30
        achievement.hasHalfMonth = count >= 14
        achievement.hasFirstDayReflection = hasFirstDay

        save(achievement)
}
```

### Swift Implementation

```swift
func updateMonthlyAchievements(reflectionRepository: ReflectionRepositoryProtocol) async throws {
    for monthOffset in 0..<12 {
        let targetDate = Calendar.current.date(byAdding: .month, value: -monthOffset, to: .now)!
        let year = Calendar.current.component(.year, from: targetDate)
        let month = Calendar.current.component(.month, from: targetDate)
        let yearMonth = String(format: "%04d-%02d", year, month)

        let monthStart = Calendar.current.date(from:
            DateComponents(year: year, month: month, day: 1)
        )!
        let monthEnd = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)!

        let reflections = try await reflectionRepository.getSubmissionsInDateRange(monthStart, monthEnd)
        let count = reflections.count

        let hasFirstDay = reflections.contains { reflection in
            guard let submittedDate = reflection.submittedDate else { return false }
            return Calendar.current.component(.day, from: submittedDate) == 1
        }

        var achievement = try await repository.getOrCreate(id: yearMonth)
        achievement.reflectionCount = count
        achievement.hasAnyReflection = count > 0
        achievement.hasFullMonth = count >= 30
        achievement.hasHalfMonth = count >= 14
        achievement.hasFirstDayReflection = hasFirstDay

        try await repository.update(achievement)
    }
}
```

---

## 🌅 First-Day Badge Evaluation

### On Submission

```pseudocode
func evaluateFirstDayBadge(submittedDate: Date, monthlyAchievement: MonthlyAchievement) -> Badge? {
    day = component(.day, from: submittedDate)

    if day == 1 AND NOT monthlyAchievement.hasFirstDayReflection:
        badge = badgeFor("first-day-month")
        badge.unlockedCount += 1
        return badge

    return nil
}
```

### Check Logic

```swift
func checkFirstDayOfMonth(submittedDate: Date) -> Bool {
    Calendar.current.component(.day, from: submittedDate) == 1
}

func getMonthYearString(from date: Date) -> String {
    let year = Calendar.current.component(.year, from: date)
    let month = Calendar.current.component(.month, from: date)
    return String(format: "%04d-%02d", year, month)
}
```

---

## 📊 Full & Half Month Badges

### Evaluation Trigger
Daily midnight update (automatic)

### Check Logic

```pseudocode
func checkFullMonth(achievement: MonthlyAchievement) -> Bool {
    return achievement.reflectionCount >= 30 AND NOT achievement.hasFullMonth
}

func checkHalfMonth(achievement: MonthlyAchievement) -> Bool {
    return achievement.reflectionCount >= 14 AND NOT achievement.hasHalfMonth
}
```

### Swift

```swift
func evaluateMonthlyBadges(achievement: MonthlyAchievement) -> [Badge] {
    var badges: [Badge] = []

    if achievement.reflectionCount >= 30 && !achievement.hasFullMonth {
        badges.append(badgeFor("full-month"))
        achievement.hasFullMonth = true
    }

    if achievement.reflectionCount >= 14 && !achievement.hasHalfMonth {
        badges.append(badgeFor("half-month"))
        achievement.hasHalfMonth = true
    }

    return badges
}
```

---

## 🏆 Consistency Badges (6 & 12 Month)

### Get Last N Consecutive Months

```pseudocode
func getLastNConsecutiveMonths(n: Int) -> [String] {
    result = []
    current = today
    repeat n times:
        year = component(.year, from: current)
        month = component(.month, from: current)
        result.append(format("%04d-%02d", year, month))
        current = date(byAdding: .month, value: -1, to: current)
    return result
}
```

### 6-Month Check

```pseudocode
func check6MonthConsistency(achievements: [MonthlyAchievement]) -> Bool {
    last6Months = getLastNConsecutiveMonths(6)

    for month in last6Months:
        achievement = find achievement where id == month
        if achievement == nil OR NOT achievement.hasAnyReflection:
            return false

    return true
}
```

### 12-Month Check

```pseudocode
func check12MonthConsistency(achievements: [MonthlyAchievement]) -> Bool {
    last12Months = getLastNConsecutiveMonths(12)

    for month in last12Months:
        achievement = find achievement where id == month
        if achievement == nil OR NOT achievement.hasAnyReflection:
            return false

    return true
}
```

### Swift Implementation

```swift
func checkConsistency(_ achievements: [MonthlyAchievement], months: Int) -> Bool {
    var requiredMonths = Set<String>()
    var current = Calendar.current.startOfDay(for: .now)

    for _ in 0..<months {
        let year = Calendar.current.component(.year, from: current)
        let month = Calendar.current.component(.month, from: current)
        requiredMonths.insert(String(format: "%04d-%02d", year, month))
        current = Calendar.current.date(byAdding: .month, value: -1, to: current) ?? current
    }

    let achievementDict = Dictionary(grouping: achievements, by: { $0.id })

    for monthStr in requiredMonths {
        guard let achievement = achievementDict[monthStr]?.first,
              achievement.hasAnyReflection else {
            return false
        }
    }

    return true
}

func check6MonthConsistency(_ achievements: [MonthlyAchievement]) -> Bool {
    checkConsistency(achievements, months: 6)
}

func check12MonthConsistency(_ achievements: [MonthlyAchievement]) -> Bool {
    checkConsistency(achievements, months: 12)
}
```

---

## 🔔 Badge Unlock Flow

### On Reflection Submission

```pseudocode
func handleReflectionSubmission(reflection: Reflection) {
    // 1. Mark as streak submission
    reflection.submittedDate = now
    reflection.isStreakSubmission = true
    save(reflection)

    // 2. Calculate streak
    allReflections = fetchAllReflections()
    newStreak = calculateCurrentStreak(allReflections)
    previousStreak = getStreakData().currentStreak

    // 3. Evaluate streak badges
    unlockedBadges = evaluateStreakBadges(newStreak, previousStreak)

    // 4. Evaluate first-day badge
    monthlyAchievement = getMonthlyAchievement(now)
    if badge = evaluateFirstDayBadge(now, monthlyAchievement):
        unlockedBadges.append(badge)

    // 5. Evaluate first reflection badge
    if reflection.totalCount == 1:
        unlockedBadges.append(badgeFor("first-reflection"))

    // 6. Update streak data
    streakData.currentStreak = newStreak
    streakData.lastSubmissionDate = now
    if newStreak > streakData.longestStreak:
        streakData.longestStreak = newStreak
    save(streakData)

    // 7. Show celebrations
    for badge in unlockedBadges:
        showCelebration(badge)

    // 8. Schedule nightly update
    scheduleMonthlyRecalculation()
}
```

### Nightly Recalculation

```pseudocode
func nightly_recalculateAchievements() {
    // Update all monthly achievements
    updateMonthlyAchievements()

    // Check consistency badges
    achievements = fetchAllMonthlyAchievements()
    newBadges = []

    if check6MonthConsistency(achievements) AND NOT has6MonthBadge():
        newBadges.append(badgeFor("6month-consistency"))

    if check12MonthConsistency(achievements) AND NOT has12MonthBadge():
        newBadges.append(badgeFor("12month-consistency"))

    // Notify user
    for badge in newBadges:
        sendNotification(badge)
}
```

---

## 🧪 Test Cases

### Streak Calculation
```
Test: 3 consecutive days
Input: [Mar 7, Mar 6, Mar 5]
Expected: 3

Test: 2 days, gap, 2 days
Input: [Mar 7, Mar 6, Mar 4, Mar 3]
Expected: 2 (only recent consecutive)

Test: Empty
Input: []
Expected: 0
```

### First Day Badge
```
Test: Reflection on 1st
Input: submittedDate = Mar 1, 2026
Expected: Badge unlocked

Test: Reflection on 2nd
Input: submittedDate = Mar 2, 2026
Expected: Badge NOT unlocked
```

### Full Month
```
Test: 30 reflections
Input: reflections = [30 different dates in March]
Expected: Badge unlocked

Test: 29 reflections
Input: reflections = [29 different dates in March]
Expected: Badge NOT unlocked (needs 30)
```

### Consistency
```
Test: 6 consecutive months
Input: Jan, Feb, Mar, Apr, May, Jun (all with 1+)
Expected: 6-Month badge unlocked

Test: 6 months with one gap
Input: Jan, Feb, Mar, GAP, May, Jun
Expected: NOT unlocked (must be consecutive)
```

---

Ready for implementation? See **04_MODELS.md** for copy-paste code.
