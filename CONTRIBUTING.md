# Contributing to Weekend

Thank you for your interest in contributing to Weekend! We welcome contributions from the community and are grateful for your help in making this project better.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report, please check the [existing issues](https://github.com/zypherlabs-bit/Weekend/issues) to see if the problem has already been reported.

When creating a bug report, please include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected behavior** vs **actual behavior**
- **Screenshots** if applicable
- **Device information** (Android version, device model)
- **App version**

### Suggesting Features

Feature requests are welcome! Please provide:

- **Clear title and description**
- **Use case** — What problem does this solve?
- **Proposed solution** — How should it work?
- **Alternatives considered**

### Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
4. **Follow coding standards** (see below)
5. **Test your changes** thoroughly
6. **Commit** with clear, descriptive messages
7. **Push** to your fork
8. **Open a Pull Request** against `main`

## Coding Standards

### Dart

- Follow [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic
- Use camelCase for variables and methods
- Use PascalCase for types and classes
- Prefer const constructors where possible
- Avoid unnecessary nullable types

### Flutter

- Follow [Flutter Widget Catalog](https://docs.flutter.dev/development/ui/widgets) guidelines
- Use Material 3 components where possible
- Keep widgets small and reusable
- Extract reusable widgets
- Use Riverpod for state management
- Follow the project's folder structure (`lib/features/`, `lib/services/`, `lib/repositories/`, `lib/models/`, `lib/widgets/`)

### Git Commits

- Use present tense: "Add feature" not "Added feature"
- Use imperative mood: "Move cursor to..." not "Moves cursor to..."
- Limit the first line to 72 characters
- Reference issues and PRs where appropriate

Example:
```
Add photo verification UI

- Implement camera capture screen
- Add verification status indicator
- Update profile screen to show verification badge

Fixes #123
```

## Development Setup

1. Clone the repository
2. Open in Android Studio or VS Code with Flutter extension
3. Create `.env` from `.env.example`
4. Run `flutter pub get`
5. Run the app on an emulator or device

## Testing

Before submitting a PR:

```bash
# Run lint analysis
flutter analyze

# Run tests
flutter test

# Build the app
flutter build apk --release
```

## Code Review Process

- All submissions require review before merging
- Maintainers will review PRs within a reasonable timeframe
- Changes may be requested before approval
- Once approved, a maintainer will merge the PR

## Questions?

Feel free to open an [issue](https://github.com/zypherlabs-bit/Weekend/issues) or start a [discussion](https://github.com/zypherlabs-bit/Weekend/discussions).

Thank you for contributing to Weekend!