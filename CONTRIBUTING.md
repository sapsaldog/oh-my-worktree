# Contributing to Oh My Worktree

Thank you for your interest in contributing! This guide will help you get started with development.

## Development Environment Setup

### Requirements
- **Xcode 15+** (with Command Line Tools)
- **macOS 14+** (Sonoma or later)
- **Git 2.30+**
- **Swift 5.9+**

### Getting Started
1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd oh-my-worktree
   ```

2. Open the Xcode project:
   ```bash
   open OhMyWorktree.xcodeproj
   ```

3. Select your target device (Mac) and build.

## Building and Running

1. Open `OhMyWorktree.xcodeproj` in Xcode
2. Select **Product > Build** (or press `Cmd+B`)
3. Select **Product > Run** (or press `Cmd+R`) to launch the app
4. The app will open in a window on your Mac

## Code Style & Architecture

This project follows **MVVM architecture** with SwiftUI:

- **Models**: Data structures in `/Models` (Codable, Identifiable)
- **Views**: SwiftUI components in `/Views` (follow HIG conventions)
- **ViewModels**: State management in `/ViewModels` (use `@Published` properties)
- **Services**: Business logic in `/Services` (Git integration, external tools)

### Style Guidelines
- Use Swift naming conventions: `camelCase` for variables/functions, `PascalCase` for types
- Add doc comments to public methods and complex logic
- Keep UI code in Views, business logic in Services/ViewModels
- Follow [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos) for macOS apps

## Submitting Changes

### Branching
1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the code style above

3. Commit with clear messages:
   ```bash
   git commit -m "Add feature: description of change"
   ```

### Pull Requests
1. Push your branch:
   ```bash
   git push origin feature/your-feature-name
   ```

2. Open a PR on GitHub with:
   - Clear title describing the change
   - Description of what was changed and why
   - Any testing steps or edge cases to consider
   - Screenshots if UI changes

## Reporting Issues

Found a bug? Please open an issue with:

1. **Clear title** describing the problem
2. **Steps to reproduce**:
   - What you did
   - What happened
   - What you expected
3. **Environment**:
   - macOS version
   - Xcode version
   - Git version (run `git --version`)
4. **Logs or screenshots** if applicable

### Example Bug Report
```
Title: Worktree list doesn't refresh after deleting worktree

Steps to reproduce:
1. Create a new worktree
2. Click delete
3. Confirm deletion
4. List still shows deleted worktree

Expected: List should refresh and removed worktree should disappear
Environment: macOS 15.2, Xcode 16.2, Git 2.44
```

## Testing

- Run tests in Xcode: **Product > Test** (or press `Cmd+U`)
- Add tests for new features in appropriate test files
- Verify your changes don't break existing functionality

## Questions?

Open an issue for questions or feel free to start a discussion. We're here to help!
