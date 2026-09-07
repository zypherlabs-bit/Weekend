# Weekend - Modern Dating App

A modern, safe, intelligent dating application built with Kotlin, Jetpack Compose, and Clean Architecture.

## Features

- **Swipe & Match**: Tinder-style discovery with smooth swipe interactions
- **Nearby Discovery**: happn-inspired proximity-based encounters
- **Real-time Chat**: Messaging with typing indicators and read receipts
- **Profile Verification**: Photo verification for trusted connections
- **Safety Center**: Block, report, and safety tools
- **Weekend Plans**: Date planning and activity suggestions
- **Crossed Paths**: Privacy-first real-world encounter discovery
- **Premium Features**: Advanced filters, boosts, and more

## Tech Stack

### Android
- Kotlin + Jetpack Compose + Material 3
- Clean Architecture + MVVM/MVI
- Hilt Dependency Injection
- Room Database
- DataStore Preferences
- Firebase Auth & Firestore
- WebSockets for realtime
- Kotlin Coroutines & Flow

### Architecture
- Domain layer with use cases and repository interfaces
- Data layer with remote and local data sources
- Core modules: common, designsystem, network, database, datastore, security, analytics, location, notifications
- Feature modules: auth, onboarding, profile, discovery, matches, chat, encounters, dates, settings, subscription, safety

## Project Structure

```
weekend/
├── app/                    # Application module
├── core/                   # Core modules
│   ├── common/            # Common utilities, constants, extensions
│   ├── designsystem/      # Material 3 theme, colors, typography, components
│   ├── network/           # Retrofit, OkHttp, WebSocket, API definitions
│   ├── database/          # Room database, entities, DAOs, converters
│   ├── datastore/         # DataStore preferences manager
│   ├── security/          # Secure storage, encryption utilities
│   ├── analytics/         # Analytics tracking and events
│   ├── location/          # Location client and manager
│   └── notifications/     # FCM, notification channels
├── domain/                 # Domain layer (pure Kotlin)
│   ├── model/             # Domain models and enums
│   ├── repository/        # Repository interfaces
│   ├── usecase/           # Use cases
│   └── common/            # Result, AppException
├── data/                   # Data layer
│   ├── repository/        # Repository implementations
│   ├── remote/            # Remote data sources (Firebase, Supabase)
│   ├── local/             # Local data source (Room)
│   ├── mapper/            # Entity <-> Domain mappers
│   └── di/                # Hilt data module
└── feature/                # Feature modules
    ├── auth/              # Authentication
    ├── onboarding/        # Onboarding flow
    ├── profile/           # Profile management
    ├── discovery/         # Swipe discovery
    ├── matches/           # Matches list
    ├── chat/              # Messaging
    ├── encounters/        # Crossed paths / nearby
    ├── dates/             # Date planning
    ├── settings/          # App settings
    ├── subscription/      # Premium subscriptions
    └── safety/            # Safety center
```

## Prerequisites

- Android Studio Iguana or newer
- JDK 17
- Android SDK 36
- Gradle 8.11+

## Setup

1. Clone the repository
2. Copy `.env.example` to `.env` and fill in your API keys
3. Open project in Android Studio
4. Sync Gradle
5. Run on emulator or physical device

## Environment Variables

Create a `.env` file in the project root:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-anon-key
GEMINI_API_KEY=your-gemini-api-key
```

## Building

```bash
./gradlew assembleDebug    # Debug build
./gradlew assembleRelease  # Release build
./gradlew test             # Run tests
```

## Testing

- Unit tests: `./gradlew testDebugUnitTest`
- Integration tests: `./gradlew connectedAndroidTest`
- Screenshot tests: `./gradlew recordRoborazziDebug`

## CI/CD

GitHub Actions workflows run on every PR:
- Lint & static analysis
- Unit tests
- Debug APK build
- Security scan

## Security

- Tokens stored in EncryptedSharedPreferences (Android Keystore)
- No secrets in source control
- Certificate pinning for API calls
- ProGuard/R8 obfuscation for release builds

## License

MIT License

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)
