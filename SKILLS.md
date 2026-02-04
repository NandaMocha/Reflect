# Reflect - Project Foundation Knowledge

## Project Overview

**ReflectLearn** is an iOS learning journal app built with SwiftUI that helps users capture reflections on their learning journey. The app supports text, images, voice recordings, and videos with iCloud backup capabilities.

---

## Architecture

### Clean Architecture with MVVM

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  ┌────────────────┐    ┌─────────────────────────────────┐ │
│  │ SwiftUI Views  │◄───│ @Observable ViewModels          │ │
│  └────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────┐    ┌─────────────────────────────────┐ │
│  │   Entities     │    │      Use Cases                  │ │
│  └────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       Data Layer                             │
│  ┌────────────────┐    ┌─────────────────────────────────┐ │
│  │   Repositories │◄───│ SwiftData Models                │ │
│  └────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Service Layer                           │
│  Audio │ Speech │ Image │ Cloud                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
Reflect/
├── App/                            # App entry point
│   └── DIContainer.swift          # Dependency injection container
│
├── Core/                           # Shared utilities
│   ├── Extensions/
│   │   ├── Color+Hex.swift        # Color hex support + palette
│   │   ├── Date+Formatting.swift  # Date formatting extensions
│   │   └── View+Modifiers.swift   # SwiftUI view modifiers
│   ├── Utilities/
│   │   ├── Constants.swift        # Design tokens, enums, limits
│   │   └── HapticManager.swift    # Haptic feedback manager
│   └── Protocols/
│
├── Domain/                         # Business logic
│   ├── Entities/                  # Domain models (DTOs, results)
│   └── UseCases/                  # Business logic by feature
│       ├── Learning/
│       ├── Reflection/
│       ├── Sync/
│       └── Voice/
│
├── Data/                           # Data layer
│   ├── Models/                    # SwiftData @Model classes
│   │   ├── Learning.swift
│   │   ├── Reflection.swift
│   │   ├── ImageAttachment.swift
│   │   ├── VoiceRecording.swift
│   │   └── VideoAttachment.swift
│   ├── Repositories/
│   │   ├── Protocols/             # Repository protocols
│   │   └── Implementations/       # Repository implementations
│   ├── DataSources/               # External data sources
│   └── Mappers/                   # Data transformation
│
├── Presentation/                   # UI layer
│   ├── Components/                # Reusable UI components
│   │   ├── Buttons/               # Primary, Secondary, Icon, FAB
│   │   ├── Cards/                 # LearningCard, ReflectionCard
│   │   ├── Feedback/              # Empty, Loading, Error states
│   │   ├── Inputs/                # SearchBar, RichTextEditor
│   │   ├── Layout/                # FlowLayout, SectionHeader
│   │   ├── Media/                 # ImageGallery, VoiceRecorder
│   │   └── Universal/             # SwipeActions, DiscardSheet
│   ├── Features/                  # Feature modules
│   │   ├── Learning/              # List, Form
│   │   ├── Reflection/            # List, Detail, Editor
│   │   ├── MainTab/               # Root navigation
│   │   ├── Onboarding/            # First-run experience
│   │   └── Settings/              # App settings
│   └── Modifiers/                 # Custom view modifiers
│       ├── GlassBackground.swift
│       ├── CardStyle.swift
│       └── ShakeEffect.swift
│
└── Services/                       # Platform services
    ├── Audio/                     # Recorder, Player
    ├── Cloud/                     # CloudKit sync
    ├── Image/                     # Image processing
    └── Speech/                    # Speech recognition
```

---

## Dependency Injection Pattern

### DIContainer (Singleton)

All dependencies are centralized in `DIContainer.shared`:

```swift
// Configuration
DIContainer.shared.configure(with: modelContext)

// Creating ViewModels
let viewModel = DIContainer.shared.makeReflectionListViewModel()
```

### Protocol-Based Injection

All dependencies use protocol abstractions:

```swift
// Repository protocols
protocol LearningRepositoryProtocol { }
protocol ReflectionRepositoryProtocol { }

// Use case protocols
protocol CreateReflectionUseCaseProtocol { }
protocol SearchReflectionsUseCaseProtocol { }

// Service protocols
protocol ImageProcessingServiceProtocol { }
protocol CloudSyncServiceProtocol { }
```

---

## ViewModel Pattern

### Standard ViewModel Structure

```swift
import Observation
import Combine

@Observable
final class FeatureViewModel {
    // MARK: - State
    var items: [Item] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies
    let modelContext: ModelContext
    let useCase: SomeUseCaseProtocol

    // MARK: - Initialization
    init(
        modelContext: ModelContext,
        useCase: SomeUseCaseProtocol
    ) {
        self.modelContext = modelContext
        self.useCase = useCase
    }

    // MARK: - Actions
    func performAction() async {
        // ...
    }
}
```

### Key ViewModel Conventions

1. **Use `@Observable` macro** for state management
2. **Annotate with `@MainActor`** for UI-dependent ViewModels
3. **Organize with MARK comments**: State, Dependencies, Initialization, Actions
4. **Split complex ViewModels** into extensions (e.g., `+Actions.swift`, `+Validation.swift`)
5. **Use Combine for debouncing** search queries

---

## SwiftData Models

### Model Conventions

```swift
@preconcurrency @Model
final class Learning {
    @Attribute(.unique) var id: UUID
    var title: String
    var descriptionText: String?
    var colorHex: String
    var iconName: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Reflection.learning)
    var reflections: [Reflection] = []

    init(...) { ... }

    var computedProperty: Int {
        reflections.count
    }
}
```

### Key Model Rules

1. Use `@preconcurrency @Model` for Swift 6 compatibility
2. Always add `@Attribute(.unique)` to `id: UUID`
3. Use `@Relationship` with explicit delete rules
4. Provide default values in init
5. Store computed properties as `var` (not `let`)

---

## Use Case Pattern

### Use Case Structure

```swift
protocol CreateSomethingUseCaseProtocol {
    func execute(input: SomethingInput) async throws -> Something
}

final class CreateSomethingUseCase: CreateSomethingUseCaseProtocol {
    private let repository: SomethingRepositoryProtocol
    private let service: SomeServiceProtocol

    init(...) { ... }

    func execute(input: SomethingInput) async throws -> Something {
        // Business logic
    }
}
```

### Use Case Naming

- `Create[Entity]UseCase` - Create operations
- `Update[Entity]UseCase` - Update operations
- `Delete[Entity]UseCase` - Delete operations
- `Fetch[Entity]UseCase` - Single fetch
- `Fetch[Entity]sUseCase` - List fetch
- `Search[Entity]sUseCase` - Search operations

---

## Design System

### Spacing Tokens

```swift
Constants.Spacing.xxs    // 4pt
Constants.Spacing.xs     // 8pt
Constants.Spacing.sm     // 12pt
Constants.Spacing.md     // 16pt
Constants.Spacing.lg     // 24pt
Constants.Spacing.xl     // 32pt
Constants.Spacing.xxl    // 48pt
```

### Corner Radius

```swift
Constants.CornerRadius.small   // 8pt
Constants.CornerRadius.medium  // 12pt
Constants.CornerRadius.large   // 16pt (default for cards)
Constants.CornerRadius.xl      // 24pt
```

### Animation Durations

```swift
Constants.Animation.defaultDuration  // 0.3s
Constants.Animation.quickDuration    // 0.15s
Constants.Animation.slowDuration     // 0.5s
```

### Color Palette (Earth-Tone Theme)

```swift
// Primary (Muted Green)
Color.sageMedium      // #628141 - Primary action color
Color.sageDark        // #40513B - Dark variant

// Background
Color.beigeLight      // #E5D9B6 - Warm cream
Color.primaryLight    // Light mode backgrounds
Color.primaryDark     // Dark mode backgrounds

// Semantic
Color.success         // #7BC950
Color.warning         // #FFB74D
Color.error           // #EF6461
Color.info            // #64B5F6

// Learning Categories
Color.coral, Color.ocean, Color.lavender, Color.mint,
Color.peach, Color.sky, Color.rose, Color.sage
```

---

## UI Components

### Glass Morphism Effect

```swift
.someView()
    .glassBackground(cornerRadius: 16, opacity: 1.0)
    .glassCard()  // Alternative with padding
```

### Card Style

```swift
.someView()
    .glassCard()  // Applies padding, background, border, shadow
```

### Primary Button

```swift
PrimaryButton(
    title: "Save",
    icon: "checkmark",
    action: { ... }
)
```

### Secondary Button

```swift
SecondaryButton(
    title: "Cancel",
    action: { ... }
)
```

### Icon Button

```swift
IconButton(
    icon: "trash",
    role: .destructive,
    action: { ... }
)
```

---

## Navigation Patterns

### Sheet Presentation

```swift
.sheet(isPresented: $showSheet) {
    DestinationView(isPresented: $showSheet)
}
```

### Full Screen Cover

```swift
.fullScreenCover(isPresented: $showCover) {
    DestinationView(isPresented: $showCover)
}
```

### Programmatic Sheet in ViewModel

```swift
@Observable
class ViewModel {
    var showSheet: Bool = false
    var sheetData: SomeData?

    func openSheet(data: SomeData) {
        sheetData = data
        showSheet = true
    }
}
```

---

## Search with Debouncing

```swift
class ViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    private let searchSubject = PassthroughSubject<String, Never>()
    private var cancellable: AnyCancellable?

    init() {
        cancellable = searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.performSearch()
                }
            }
    }

    func onSearchQueryChange() {
        searchSubject.send(searchQuery)
    }
}
```

---

## Error Handling

### Domain-Specific Errors

```swift
enum ReflectionError: Error, LocalizedError {
    case invalidInput(String)
    case learningNotFound
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .learningNotFound: return "Learning not found"
        case .notFound: return "Reflection not found"
        }
    }
}
```

### ViewModel Error Handling

```swift
func deleteItem(_ item: Item) async {
    do {
        try await deleteUseCase.execute(id: item.id)
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

---

## Haptic Feedback

```swift
import UIKit

// Use HapticManager for consistent feedback
HapticManager.shared.lightImpact()
HapticManager.shared.mediumImpact()
HapticManager.shared.heavyImpact()
HapticManager.shared.success()
HapticManager.shared.warning()
HapticManager.shared.error()
```

---

## Constants and Enums

### Usage

```swift
// Type aliases for convenience
typealias SpeechLanguage = Constants.SpeechLanguage
typealias SortOption = Constants.SortOption
typealias ThemeOption = Constants.ThemeOption

// Use in code
let sortOption: SortOption = .newestFirst
let language: SpeechLanguage = .indonesian
```

### UserDefaults Keys

```swift
Constants.UserDefaults.hasCompletedOnboarding
Constants.UserDefaults.selectedTheme
Constants.UserDefaults.defaultLanguage
Constants.UserDefaults.lastSyncDate
```

### Limits

```swift
Constants.Limits.learningTitleMaxLength          // 30
Constants.Limits.learningDescriptionMaxLength    // 500
Constants.Limits.reflectionTitleMaxLength        // 200
Constants.Limits.maxImagesPerReflection          // 10
Constants.Limits.maxVideosPerReflection          // 5
Constants.Limits.maxVoiceNotesPerReflection      // 5
```

---

## Coding Conventions

### File Naming

- Views: `FeatureNameView.swift`
- ViewModels: `FeatureNameViewModel.swift`
- Use Cases: `ActionEntityUseCase.swift`
- Repositories: `EntityRepository.swift`
- Protocols: `EntityNameProtocol.swift`

### MARK Comments

```swift
// MARK: - State
// MARK: - Dependencies
// MARK: - Initialization
// MARK: - Public Properties
// MARK: - Actions
// MARK: - Private Helpers
// MARK: - Setup
```

### Async/Await

- All repository operations use `async throws`
- Use `await` in ViewModel with `Task { @MainActor in ... }`
- Use `try/catch` for error handling

### MainActor

```swift
@MainActor
final class ViewModel: ObservableObject {
    // UI-dependent ViewModels
}
```

---

## Adding a New Feature

### 1. Create Domain Layer

```
Domain/UseCases/NewFeature/
├── CreateNewEntityUseCase.swift
├── UpdateNewEntityUseCase.swift
├── DeleteNewEntityUseCase.swift
└── FetchNewEntitiesUseCase.swift
```

### 2. Create Data Layer (if new entity)

```
Data/Models/NewEntity.swift
Data/Repositories/Protocols/NewEntityRepositoryProtocol.swift
Data/Repositories/Implementations/NewEntityRepository.swift
```

### 3. Add to DIContainer

```swift
// In DIContainer.swift
func makeNewEntityRepository() -> NewEntityRepositoryProtocol { ... }
func makeCreateNewEntityUseCase() -> CreateNewEntityUseCaseProtocol { ... }
func makeNewEntityListViewModel() -> NewEntityListViewModel { ... }
```

### 4. Create UI

```
Presentation/Features/NewFeature/
├── List/
│   ├── NewFeatureListView.swift
│   └── NewFeatureListViewModel.swift
└── Form/
    ├── NewFeatureFormView.swift
    └── NewFeatureFormViewModel.swift
```

### 5. Add Navigation

Update parent view or tab navigation to include new feature.

---

## Testing Guidelines

### ViewModel Testing

```swift
@Test
func deleteItem_removesFromList() async {
    // Given
    let viewModel = makeViewModel()
    let item = Item()
    viewModel.items = [item]

    // When
    await viewModel.deleteItem(item)

    // Then
    #expect(viewModel.items.isEmpty)
}
```

### Use Case Testing

```swift
@Test
func execute_withValidInput_returnsEntity() async throws {
    // Given
    let useCase = makeUseCase()
    let input = ...

    // When
    let result = try await useCase.execute(input: input)

    // Then
    #expect(result.title == input.title)
}
```

---

## Common Patterns

### Sheet with IsPresented Binding

```swift
struct DestinationView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
        }
    }
}
```

### Confirmation Alert

```swift
.confirmationAlert(
    isPresented: $showAlert,
    title: "Delete Item",
    message: "This action cannot be undone.",
    confirmButton: .destructive("Delete"),
    onConfirm: { deleteItem() }
)
```

### Loading Overlay

```swift
.loadingOverlay(isLoading: isLoading)
```

### Empty State

```swift
EmptyStateView(
    icon: "tray",
    title: "No Items",
    message: "Create your first item to get started."
)
```

---

## App Configuration

### App Info

```swift
Constants.App.name                  // "ReflectLearn"
Constants.App.bundleIdentifier      // "com.reflectlearn.app"
Constants.App.iCloudContainerId     // "iCloud.com.reflectlearn.app"
```

### Theme Options

```swift
enum ThemeOption {
    case system
    case light
    case dark
}
```

### Speech Languages

```swift
enum SpeechLanguage {
    case indonesian   // id-ID
    case english      // en-US
    case englishUK    // en-GB
}
```

---

## Key Services

### Image Processing

```swift
let service = DIContainer.shared.makeImageProcessingService()
let compressed = await service.compressImage(image, quality: .high)
let thumbnail = await service.generateThumbnail(image, size: CGSize(width: 200, height: 200))
```

### Audio Recording

```swift
let recorder = DIContainer.shared.makeAudioRecorderService()
await recorder.startRecording()
let audioData = await recorder.stopRecording()
```

### Speech Recognition

```swift
let speech = DIContainer.shared.makeSpeechRecognitionService()
await speech.startRecognition(language: .indonesian)
```

### Cloud Sync

```swift
let cloud = DIContainer.shared.makeCloudSyncService()
let result = await cloud.backupToiCloud()
```

---

## Build Configuration

### SwiftData Container Configuration

```swift
ModelContainer(for: [Learning.self, Reflection.self, ...]) { result in
    switch result {
    case .success(let container):
        DIContainer.shared.configure(with: container.mainContext)
    case .failure(let error):
        fatalError("Failed to initialize SwiftData: \(error)")
    }
}
```

---

## Common Pitfalls to Avoid

1. **Don't use `@Published`** - Use `@Observable` instead
2. **Don't force unwrap** in production code - Use guard let or optional chaining
3. **Don't call async functions** in sync context without Task/await
4. **Don't forget to configure DIContainer** before accessing dependencies
5. **Don't use hardcoded colors** - Use Color extensions or Constants
6. **Don't skip error handling** - Always use do-catch or try?
7. **Don't mutate state from background** - Use `@MainActor` or `Task { @MainActor in }`
8. **Don't create direct dependencies** - Always inject via DIContainer

---

## Version Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 6.0+
- SwiftUI 5.0+
