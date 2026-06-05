# Getting Started

## Requirements

- **macOS 15.0** (Sequoia) or later
- **Git 2.30** or later
- A [bare Git repository](https://git-scm.com/docs/git-clone#Documentation/git-clone.txt---bare) for worktree management

### Optional

- [**`gh` CLI**](https://cli.github.com/) — enables GitHub PR integration (badges, one-click PR links)
- **iTerm**, **Ghostty**, **cmux**, **VSCode**, or **Cursor** — for "Open in..." integration

## Installation

### Download (Recommended)

1. Go to [GitHub Releases](https://github.com/sapsaldog/oh-my-worktree/releases)
2. Download the latest `.dmg` or `.zip`
3. Move `OhMyWorktree.app` to `/Applications/`
4. Launch the app — it appears in your **menu bar** (not in the Dock)

### Build from Source

```bash
git clone https://github.com/sapsaldog/oh-my-worktree.git
cd oh-my-worktree
brew install xcodegen   # generates the Xcode project from project.yml
xcodegen generate
open OhMyWorktree.xcodeproj
```

Select the `OhMyWorktree` scheme, then **Build & Run** (⌘R). Requires **Xcode 16** and [**XcodeGen**](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml`, not committed.

## First Launch

1. **Look for the menu bar icon** — Oh My Worktree runs in the menu bar (top-right of your screen). There is no Dock icon.

2. **Register a repository** — Click the menu bar icon, then open the Main Window (⌘O). Use the **+** button next to the repository selector to add a bare Git repository.

   > **Tip**: If you don't have a bare repository yet, create one:
   > ```bash
   > git clone --bare https://github.com/your/repo.git ~/repos/repo.git
   > ```

3. **Select the repository** — It appears in the dropdown at the top. Select it to see its worktrees.

4. **Create your first worktree** — Click **+ New Worktree** (⌘N). A worktree with a random name (e.g., `tokyo-lunch`) is created automatically.

5. **Open in your tool** — Hover over the worktree in the menu bar dropdown to see available tools (iTerm, VSCode, etc.), or use keyboard shortcuts from the main window.

## What's Next

- Read the [User Guide](user-guide.md) for a full walkthrough of all features
- Check [Keyboard Shortcuts](keyboard-shortcuts.md) for faster navigation
- See [FAQ](faq.md) if you run into issues
