# Oh My Worktree

> **Looking for an icon designer!** We need a macOS app icon for Oh My Worktree.

A native macOS utility for managing Git worktrees with speed and elegance.

<p align="center">
  <img src="docs/screenshots/main-window.jpg" width="500" alt="Main Window" />
</p>

## Features

- **Repository Management** - Register bare Git repositories and switch between them via dropdown menu
- **Worktree Management** - List, create, and delete worktrees with a clean interface
- **Smart Naming** - Automatic random name generation (e.g., `tokyo-lunch`, `bright-ocean`) to keep branch names organized
- **External Tool Integration** - Open worktrees directly in iTerm, Ghostty, VSCode, or Cursor with one click
- **Menu Bar Mode** - Resident NSStatusItem showing current repo and worktree with quick-access dropdown menu
- **Activity Tracking** - View relative last activity time per worktree (e.g., "2h ago", "7d ago", "just now")
- **Auto .env Copy** - Automatically copies `.env` files from the repository root when creating new worktrees, with global and per-repo settings
- **Launch at Login** - Start automatically when you log in, configurable in Settings
- **Real-Time Branch Detection** - Menu bar title updates instantly when branches change externally via git HEAD file monitoring
- **Auto-Update** - Built-in update checking and installation via Sparkle framework, configurable in Settings
- **Lightweight Design** - Compact window (500x400), runs as accessory app without Dock icon, lives in menu bar

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Git 2.30** or later
- **Xcode 15** or later (for building from source)

## Installation

### Download

Download the latest release from [GitHub Releases](https://github.com/sapsaldog/oh-my-worktree/releases). Extract the zip and move `OhMyWorktree.app` to `/Applications/`.

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/sapsaldog/oh-my-worktree.git
   cd oh-my-worktree
   ```

2. Open the Xcode project:
   ```bash
   open OhMyWorktree.xcodeproj
   ```

3. Select the `OhMyWorktree` scheme and build target (⌘B)

4. Run the app (⌘R) or find the built binary in:
   ```
   /Library/Developer/Xcode/DerivedData/OhMyWorktree-.../Build/Products/Release/OhMyWorktree.app
   ```

5. For production use, copy the app to `/Applications/`:
   ```bash
   cp -r OhMyWorktree.app /Applications/
   ```

## Usage

### 1. Register a Repository

Use the **+** button to add a bare Git repository. Select it from the dropdown to see its worktrees.

### 2. Create & Manage Worktrees

Click **+** to create a worktree with an auto-generated name (e.g., `tokyo-lunch`, `bright-ocean`). Each worktree shows its branch, path, and last activity time.

### 3. Open in Your Favorite Tool

Select a worktree and open it directly in your preferred tool:

| Tool | Description |
|------|-------------|
| **iTerm** | Opens a new terminal window at the worktree path |
| **Ghostty** | Opens Ghostty terminal at the worktree path |
| **VSCode** | Opens VS Code in the worktree directory |
| **Cursor** | Opens Cursor IDE in the worktree directory |

### 4. Menu Bar Quick Access

Access everything from the menu bar without opening the main window. The icon shows your current `{repo}/{worktree}` selection.

<p align="center">
  <img src="docs/screenshots/menubar-dropdown.jpg" width="500" alt="Menu Bar Dropdown" />
</p>

- Click the menu bar icon to see repositories and worktrees
- Hover a worktree for tool submenu (iTerm / Ghostty / VSCode / Cursor / Copy Path / Finder)
- Create new worktrees directly from the menu
- Close the main window — the app keeps running in the menu bar

### 5. Settings

Open **Settings** (`⌘,`) from the menu bar to configure global preferences. Use the **⚙** button next to the repository selector for per-repo overrides.

| Setting | Scope | Default |
|---------|-------|---------|
| **Copy .env files** | Global / Per-repo | On |
| **Launch at Login** | Global | Off |
| **Automatically check for updates** | Global | On |

## Architecture

Oh My Worktree uses a clean MVVM architecture with clear separation of concerns:

### Models
- **Repository** - Represents a registered bare Git repository with metadata (name, path, access times)
- **Worktree** - Represents a Git worktree with branch info, commit hash, and activity tracking
- **AppSettings** - Persists user preferences and registered repositories

### ViewModels
- **RepositoryListViewModel** - Manages repository selection and persistence
- **WorktreeListViewModel** - Handles worktree listing, creation, and deletion

### Views
- **ContentView** - Main application window layout
- **RepositorySelectorView** - Repository dropdown and selection UI
- **WorktreeListView** - Displays list of worktrees with actions
- **WorktreeRowView** - Individual worktree row with metadata and buttons
- **ActionButtonsView** - External tool launch buttons
- **SettingsView** - Global app settings (`.env` copy, Launch at Login, auto-update)
- **RepositorySettingsView** - Per-repo settings override popover

### Services
- **GitCommandExecutor** - Executes Git commands asynchronously via `Process`
- **WorktreeManager** - Orchestrates worktree creation and deletion via Git CLI
- **ExternalToolLauncher** - Handles opening worktrees in external tools (iTerm, Ghostty, VSCode, Cursor)
- **RandomNameGenerator** - Generates unique, memorable worktree names
- **EnvFileCopier** - Copies `.env*` files from repository root to new worktrees
- **RepositoryStore** - Persists repositories and settings to disk (JSON + UserDefaults)
- **UpdaterManager** - Sparkle auto-update controller wrapper with SwiftUI reactivity

### App Delegate
- **AppDelegate** - Manages NSStatusItem (menu bar icon) and window lifecycle

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting bugs
- Submitting features
- Code style and standards
- Testing requirements

## License

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

**Oh My Worktree** - Because managing 12 worktrees shouldn't require 12 terminal windows.
