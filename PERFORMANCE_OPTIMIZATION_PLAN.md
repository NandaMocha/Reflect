# Performance Optimization Plan

## Overview
This plan outlines 10 performance optimizations to be implemented one-by-one. Each change is designed to be testable independently before moving to the next.

---

## 1. Fix Inefficient Search (PRIORITY: HIGH)

**File:** `Reflect/Data/Repositories/Implementations/ReflectionRepository.swift`

**Problem:**
- Currently fetches ALL reflections then filters in-memory
- For 1000+ reflections, this causes noticeable lag

**Change:**
Replace in-memory filtering with SwiftData `#Predicate` for server-side filtering.

**Before:**
```swift
func search(query: String) async throws -> [Reflection] {
    let descriptor = FetchDescriptor<Reflection>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    let allReflections = try modelContext.fetch(descriptor)
    return allReflections.filter { reflection in
        reflection.title.lowercased().contains(lowercasedQuery) ||
        reflection.plainTextContent.lowercased().contains(lowercasedQuery)
    }
}
```

**After:**
```swift
func search(query: String) async throws -> [Reflection] {
    let descriptor = FetchDescriptor<Reflection>(
        predicate: #Predicate<Reflection> { reflection in
            reflection.title.contains(query) ||
            reflection.plainTextContent.contains(query)
        },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    return try modelContext.fetch(descriptor)
}
```

**Testing:**
1. Build and run the app
2. Create 50+ test reflections
3. Search in ReflectionList
4. Verify results appear quickly (<500ms)

**Risk:** Low - SwiftData handles contains() efficiently

---

## 2. Add Pagination (PRIORITY: HIGH)

**Files:**
- `Reflect/Domain/Entities/SearchFilters.swift`
- `Reflect/Data/Repositories/Implementations/ReflectionRepository.swift`

**Problem:**
- No limit on query results
- Large datasets slow down the UI

**Change:**
Add `limit` and `offset` to SearchFilters and apply in all fetch operations.

**Changes to SearchFilters.swift:**
```swift
struct SearchFilters {
    var query: String = ""
    var learningId: UUID?
    var favoritesOnly: Bool = false
    var dateRange: DateRange?
    var sortOption: Constants.SortOption = .newestFirst
    var limit: Int = 50
    var offset: Int = 0
    // ...
}
```

**Changes to ReflectionRepository.swift:**
```swift
func fetchAll(limit: Int = 50, offset: Int = 0) async throws -> [Reflection] {
    let descriptor = FetchDescriptor<Reflection>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = offset
    return try modelContext.fetch(descriptor)
}
```

**Testing:**
1. Create 100+ reflections
2. Verify only 50 load initially
3. Implement "Load More" functionality (if needed)

**Risk:** Low - just limits results

---

## 3. Async Image Compression (PRIORITY: HIGH)

**File:** `Reflect/Services/Image/ImageProcessingService.swift`

**Problem:**
- Image compression blocks the main thread
- User sees UI freeze during save

**Change:**
Make compression functions async using `Task.detached`.

**Before:**
```swift
func compressImage(_ image: UIImage, quality: CompressionQuality) -> Data? {
    // Synchronous processing
}
```

**After:**
```swift
func compressImage(_ image: UIImage, quality: CompressionQuality) async -> Data? {
    await Task.detached(priority: .userInitiated) {
        let maxDimension: CGFloat = quality == .low ? 800 : (quality == .medium ? 1200 : 1600)
        guard let resized = self.resizeImage(image, maxDimension: maxDimension) else {
            return image.jpegData(compressionQuality: quality.jpegQuality)
        }
        return resized.jpegData(compressionQuality: quality.jpegQuality)
    }.value
}
```

**Required Updates:**
- Update all call sites to use `await`
- `ReflectionEditorView+SaveLogic.swift`
- `ReflectionEditorView+DataManagement.swift`

**Testing:**
1. Add a large image (5MB+) to a reflection
2. Save and verify UI remains responsive
3. Verify image is properly compressed

**Risk:** Medium - requires updating multiple call sites

---

## 4. Thumbnail Caching (PRIORITY: MEDIUM)

**File:** `Reflect/Services/Image/ImageProcessingService.swift`

**Problem:**
- Thumbnails regenerated every time
- Wastes CPU cycles

**Change:**
Add in-memory cache using `NSCache`.

**Add to ImageProcessingService:**
```swift
private var thumbnailCache: NSCache<NSString, NSData> = []

init() {
    thumbnailCache.countLimit = 100
    thumbnailCache.totalCostLimit = 50 * 1024 * 1024  // 50MB
}

func generateThumbnail(_ image: UIImage, size: CGSize) async -> Data? {
    let cacheKey = "\(Int(size.width))x\(Int(size.height))-\(image.hashValue)" as NSString

    if let cached = thumbnailCache.object(forKey: cacheKey) {
        return cached as Data
    }

    let thumbnail = await Task.detached {
        // ... existing thumbnail generation
    }.value

    if let data = thumbnail {
        thumbnailCache.setObject(data as NSData, forKey: cacheKey)
    }
    return thumbnail
}
```

**Testing:**
1. Load same reflection detail multiple times
2. Verify thumbnails load instantly on subsequent loads
3. Monitor memory usage (should stay under 50MB for cache)

**Risk:** Low - cache is self-contained

---

## 5. Concurrent Image Processing (PRIORITY: HIGH)

**File:** `Reflect/Presentation/Features/Reflection/Editor/ReflectionEditorView+SaveLogic.swift`

**Problem:**
- Images processed sequentially during save
- 5 images = 5x time

**Change:**
Use `TaskGroup` for concurrent processing with progress updates.

**Before:**
```swift
for (index, imageInput) in images.enumerated() {
    if let imageData = imageService.compressImage(...),
       let thumbnailData = imageService.generateThumbnail(...) {
        // ... save
    }
}
```

**After:**
```swift
// Add state variable
@State private var processingProgress: Double = 0

// Process concurrently
func processImagesConcurrently() async throws -> [(index: Int, data: Data?, thumbnail: Data?)] {
    return try await withThrowingTaskGroup(of: (Int, Data?, Data?).self) { group in
        for (index, imageInput) in images.enumerated() {
            group.addTask {
                let data = await imageService.compressImage(imageInput.image, quality: .high)
                let thumbnail = await imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200))
                return (index, data, thumbnail)
            }
        }

        var results: [(Int, Data?, Data?)] = []
        for try await result in group {
            results.append(result)
            let progress = Double(results.count) / Double(images.count)
            await MainActor.run { processingProgress = progress }
        }
        return results.sorted { $0.index < $1.index }
    }
}
```

**Testing:**
1. Add 5+ images to a reflection
2. Save and verify progress indicator updates
3. Verify save time is significantly reduced

**Risk:** Medium - requires refactoring save logic

---

## 6. Concurrent iCloud Uploads (PRIORITY: MEDIUM)

**File:** `Reflect/Services/Cloud/CloudSyncService.swift`

**Problem:**
- Items uploaded sequentially
- 100 items = slow sync

**Change:**
Use `TaskGroup` for concurrent uploads (batch of 5 at a time).

**Before:**
```swift
for (index, learning) in learnings.enumerated() {
    try await uploadLearning(learning)
}
```

**After:**
```swift
// Upload in batches of 5 to avoid overwhelming the network
let batchSize = 5
for batchStart in stride(from: 0, to: learnings.count, by: batchSize) {
    let batch = Array(learnings[batchStart..<min(batchStart + batchSize, learnings.count)])

    await withTaskGroup(of: (String, Bool).self) { group in
        for learning in batch {
            group.addTask {
                do {
                    try await self.uploadLearning(learning)
                    return (learning.title, true)
                } catch {
                    return (learning.title, false)
                }
            }
        }

        for await (title, success) in group {
            if !success {
                errors.append(.uploadFailed("Learning: \(title)"))
            }
            itemsSynced += 1
            let progress = Double(itemsSynced) / Double(totalItems)
            syncStatusSubject.send(.syncing(progress: progress))
        }
    }
}
```

**Testing:**
1. Create 20+ learnings and reflections
2. Trigger iCloud backup
3. Verify progress updates smoothly
4. Verify all items are uploaded

**Risk:** Medium - concurrent operations may need rate limiting

---

## 7. Retry Logic with Exponential Backoff (PRIORITY: MEDIUM)

**File:** `Reflect/Services/Cloud/CloudSyncService.swift`

**Problem:**
- Network failures cause permanent sync failure
- No retry mechanism

**Change:**
Add retry logic with exponential backoff.

**Add to CloudSyncService:**
```swift
private func uploadWithRetry<T>(
    _ operation: @escaping () async throws -> T,
    maxRetries: Int = 3,
    baseDelay: TimeInterval = 1.0
) async throws -> T {
    var lastError: Error?

    for attempt in 0..<maxRetries {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt < maxRetries - 1 {
                let delay = baseDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    throw lastError ?? URLError(.unknown)
}

// Usage:
try await uploadWithRetry {
    try await uploadLearning(learning)
}
```

**Testing:**
1. Enable airplane mode during sync
2. Disable airplane mode
3. Verify sync retries and succeeds

**Risk:** Low - internal change, isolated to sync service

---

## 8. Throttle Voice UI Updates (PRIORITY: LOW)

**File:** `Reflect/Services/Speech/SpeechRecognitionService.swift`

**Problem:**
- UI updates every 100ms during recording
- Unnecessary overhead

**Change:**
Update UI only every 500ms.

**Before:**
```swift
while isRecording {
    let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
    await MainActor.run {
        recordingStateSubject.send(.recording(duration: duration))
    }
    try? await Task.sleep(nanoseconds: 100_000_000)
}
```

**After:**
```swift
private var lastUpdateTime: Date?

func startDurationTimer() {
    Task {
        while isRecording {
            let now = Date()

            if lastUpdateTime == nil || now.timeIntervalSince(lastUpdateTime!) >= 0.5 {
                let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
                await MainActor.run {
                    recordingStateSubject.send(.recording(duration: duration))
                }
                lastUpdateTime = now
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
```

**Testing:**
1. Start a voice recording
2. Verify timer updates smoothly but not excessively
3. Verify no performance impact

**Risk:** Low - internal timing change

---

## 9. Timeout-Based Continuation (PRIORITY: LOW)

**File:** `Reflect/Services/Speech/SpeechRecognitionService.swift`

**Problem:**
- Fixed 500ms delay for final transcription
- May wait too long or not enough

**Change:**
Use timeout-based continuation instead.

**Add helper:**
```swift
private struct TimeoutError: Error {}

@MainActor
private func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async -> T? {
    try? await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        for try await result in group {
            group.cancelAll()
            return result
        }
        return nil
    }
}
```

**Update stopRecording:**
```swift
func stopRecording() async throws -> SpeechRecognitionResult {
    // ... existing stop logic

    let finalTranscription = await withTimeout(seconds: 2) {
        await observeFinalTranscription()
    } ?? self.transcriptionText

    // ... rest of logic
}
```

**Testing:**
1. Record voice and stop
2. Verify transcription appears quickly
3. Test with both short and long recordings

**Risk:** Low - better than fixed delay

---

## 10. Background Date Grouping (PRIORITY: MEDIUM)

**File:** `Reflect/Presentation/Features/Reflection/List/ReflectionListViewModel+Grouping.swift`

**Problem:**
- Date grouping runs on main thread
- Can block UI with many reflections

**Change:**
Move grouping to background thread.

**Before:**
```swift
func groupReflectionsByDate() {
    var groups: [ReflectionDateGroup: [Reflection]] = [:]
    // ... grouping logic on main thread
    groupedReflections = groups
}
```

**After:**
```swift
func groupReflectionsByDate() async {
    let grouped = await Task.detached(priority: .userInitiated) {
        self.groupReflections(self.reflections)
    }.value

    await MainActor.run {
        self.groupedReflections = grouped
    }
}

private func groupReflections(_ reflections: [Reflection]) -> [ReflectionDateGroup: [Reflection]] {
    // Move existing grouping logic here
    var groups: [ReflectionDateGroup: [Reflection]] = [:]
    // ... existing logic
    return groups
}
```

**Update call site:**
```swift
// In ReflectionListViewModel+DataLoading.swift
func loadReflections() async {
    // ... existing code
    reflections = try await searchUseCase.execute(filters: filters)
    await groupReflectionsByDate()  // Add await
    // ...
}
```

**Testing:**
1. Load 100+ reflections
2. Verify UI remains responsive
3. Verify grouping is correct

**Risk:** Medium - requires async/await propagation

---

## Implementation Order

| Step | Optimization | Estimated Time | Dependencies |
|------|-------------|----------------|--------------|
| 1 | Fix inefficient search | 30 min | None |
| 2 | Add pagination | 45 min | None |
| 3 | Async image compression | 1 hour | None |
| 4 | Thumbnail caching | 45 min | Step 3 |
| 5 | Concurrent image processing | 1.5 hours | Step 3 |
| 6 | Concurrent iCloud uploads | 1 hour | None |
| 7 | Retry logic | 45 min | None |
| 8 | Throttle voice UI | 30 min | None |
| 9 | Timeout continuation | 45 min | None |
| 10 | Background grouping | 1 hour | None |

**Total Estimated Time:** ~8.5 hours

---

## Testing Checklist for Each Change

- [ ] Build succeeds without errors
- [ ] App launches successfully
- [ ] Feature works as expected
- [ ] No UI freezes or lag
- [ ] Memory usage is reasonable
- [ ] Test with small dataset (10 items)
- [ ] Test with large dataset (100+ items)
- [ ] Test edge cases (empty data, network errors)

---

## Rollback Plan

Each change will be committed separately. If any issue arises:
1. Revert the specific commit: `git revert <commit-hash>`
2. Test the revert
3. Document the issue and skip to next optimization

---

## Notes

- SwiftData predicates may have limitations with `contains()` - test thoroughly
- Concurrent operations need proper error handling
- Always monitor memory usage when adding caching
- Consider using Instruments for profiling before/after
