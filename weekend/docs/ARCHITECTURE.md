# Architecture Documentation

## Overview

Weekend follows Clean Architecture with MVVM/MVI patterns, ensuring separation of concerns and testability.

## Layers

### Domain Layer (`:domain`)
Pure Kotlin module containing business logic independent of Android framework.

- **Models**: Domain entities (`UserProfile`, `MatchItem`, `ChatMessage`, etc.)
- **Repository Interfaces**: Contracts for data operations
- **Use Cases**: Single-responsibility business operations
- **Common**: `Result<T>`, `AppException`

### Data Layer (`:data`)
Implements repository interfaces, handling data from remote and local sources.

- **Repository Implementations**: Bridge between domain and data sources
- **Remote Data Sources**: Firebase, Supabase, API calls
- **Local Data Source**: Room DAOs and entities
- **Mapper**: Converts between domain models and entities/DTOs
- **DI**: Hilt module providing data dependencies

### Core Modules (`:core:*`)
Shared libraries used across features.

- **common**: Constants, extensions, dispatchers, UI state
- **designsystem**: Material 3 theme, colors, typography, reusable components
- **network**: Retrofit, OkHttp, WebSocket, API service interfaces
- **database**: Room database, entities, DAOs, type converters
- **datastore**: DataStore preferences manager
- **security**: Encrypted storage, crypto utilities
- **analytics**: Firebase Analytics, event tracking
- **location**: FusedLocationProviderClient wrapper
- **notifications**: FCM, notification channels

### Feature Modules (`:feature:*`)
Self-contained features with their own UI, ViewModel, and DI.

Each feature module:
- Depends on `:domain`, `:data`, and required `:core` modules
- Contains `ui/` for Compose screens
- Contains `di/` for Hilt modules
- Exports only necessary public APIs

### App Module (`:app`)
Application entry point, Hilt application class, navigation, and feature composition.

## Dependency Flow

```
:app
  └─ :feature:*
      └─ :domain
      └─ :data
          └─ :core:*
```

Features depend on domain and data, never the other way around. Core modules have no feature dependencies.

## State Management

- **ViewModel** holds UI state as `StateFlow`
- **Use Cases** return `Flow<T>` or `Result<T>`
- **UI** collects state with `collectAsState()`
- **Events** handled via callbacks or one-off events

## Navigation

- Navigation Compose with bottom nav for main tabs
- Nested navigation for auth vs main app
- Type-safe arguments with sealed classes

## Dependency Injection

- Hilt for dependency injection
- Singleton for repositories, data sources
- ViewModelScoped for ViewModels
- Constructor injection everywhere
