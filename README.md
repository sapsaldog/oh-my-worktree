# Oh My Worktree

A native macOS utility for managing Git worktrees with speed and elegance.

<!-- screenshot -->

## Features

- **Repository Management** - Register bare Git repositories and switch between them via dropdown menu
- **Worktree Management** - List, create, and delete worktrees with a clean interface
- **Smart Naming** - Automatic random name generation (e.g., `tokyo-lunch`, `bright-ocean`) to keep branch names organized
- **External Tool Integration** - Open worktrees directly in iTerm, Ghostty, VSCode, or Cursor with one click
- **Menu Bar Mode** - Resident NSStatusItem showing current repo and worktree with quick-access dropdown menu
- **Activity Tracking** - View relative last activity time per worktree (e.g., "2h ago", "7d ago", "just now")
- **Lightweight Design** - Compact window (500x400), runs as accessory app without Dock icon, lives in menu bar

## Requirements

- **macOS 14.0** (Sonoma) or later
- **Git 2.30** or later
- **Xcode 15** or later (for building from source)

## Installation

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

### Basic Workflow

1. **Register a Repository**
   - Launch Oh My Worktree
   - Use the "Add Repository" button to register a bare Git repository
   - Select the repository path on your filesystem

2. **Create a Worktree**
   - Select a repository from the dropdown
   - Click "New Worktree"
   - Choose a base branch or commit
   - The app generates a unique name (e.g., `golden-sunset`) automatically
   - Worktree is created and ready to use

3. **Open in Your Tool**
   - From the worktree list, select your preferred tool:
     - **iTerm** - Opens a new iTerm window at the worktree path
     - **Ghostty** - Opens Ghostty terminal at the worktree path
     - **VSCode** - Opens VS Code in the worktree directory
     - **Cursor** - Opens Cursor IDE in the worktree directory

4. **Monitor Activity**
   - Each worktree shows its last activity time
   - Quickly identify stale or active worktrees at a glance

5. **Delete Worktrees**
   - Select a worktree and click "Delete" to remove it
   - Confirmation dialog prevents accidental deletion

### Menu Bar Usage

- Click the menu bar icon to see your current repository and worktree
- Use the dropdown menu for quick navigation between worktrees
- Open the main window by selecting "Show Window"
- Close the main window but keep the app running in the menu bar

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

### Services
- **GitCommandExecutor** - Executes Git commands asynchronously via `Process`
- **WorktreeManager** - Orchestrates worktree creation and deletion via Git CLI
- **ExternalToolLauncher** - Handles opening worktrees in external tools (iTerm, Ghostty, VSCode, Cursor)
- **RandomNameGenerator** - Generates unique, memorable worktree names
- **RepositoryStore** - Persists repositories to disk (UserDefaults)

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
