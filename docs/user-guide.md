# User Guide

## Overview

Oh My Worktree is a macOS menu bar app for managing Git worktrees. It provides a fast, visual way to create, switch between, and open worktrees in your favorite tools — all without leaving the menu bar.

## Repository Management

### Registering a Repository

Oh My Worktree works with **bare Git repositories**. To register one:

1. Open the main window (⌘O from the menu bar)
2. Click the **+** button next to the repository selector
3. Choose your bare repository folder in the file picker

> **Why bare repositories?** Bare repos have no working directory of their own, making them the ideal parent for managing multiple worktrees. Learn more in the [Git documentation](https://git-scm.com/docs/git-worktree).

### Switching Repositories

- **Menu bar**: Click the menu bar icon and select a repository from the top of the dropdown
- **Main window**: Use the repository dropdown at the top of the window

Your last selected repository is remembered across app launches.

### Removing a Repository

Click the **-** button next to the repository selector in the main window. This only removes it from Oh My Worktree — your files are not affected.

## Worktree Management

### Creating a Worktree

1. Click **+ New Worktree** (⌘N) from the menu bar or main window
2. A new worktree is created with an auto-generated name (e.g., `tokyo-lunch`, `bright-ocean`)
3. A new branch with the same name is created and checked out automatically

### Viewing Worktrees

Each worktree entry shows:
- **Name** — the folder/branch name
- **PR badge** — colored badge with PR number if a pull request exists (green = open, purple = merged, red = closed)
- **Last activity** — relative time since last activity (e.g., "2h ago", "7d ago")

### Renaming a Worktree

Select a worktree in the main window and press **Return** (⏎) to edit its name.

### Removing a Worktree

Three removal options, from safest to fastest:

| Action | Shortcut | Behavior |
|--------|----------|----------|
| **Remove** | ⌫ (Delete) | Refuses if there are uncommitted changes |
| **Force Remove** | ⌘⌫ | Removes even with uncommitted changes |
| **Quick Remove** | ⇧⌘⌫ | Moves to Trash immediately without checks |

### Git Pull

Right-click a worktree (or use the submenu) and select **Git Pull** to pull the latest changes. A summary notification shows the result, including any merge conflicts.

## External Tool Integration

Open any worktree directly in your preferred tool. Only installed tools appear in the menu.

| Tool | Shortcut | Description |
|------|----------|-------------|
| **iTerm** | ⌘⇧I | Opens a new iTerm window at the worktree path |
| **Ghostty** | ⌘⇧G | Opens Ghostty terminal at the worktree path |
| **cmux** | ⌘⇧M | Opens a cmux workspace at the worktree path |
| **VSCode** | ⌘⇧V | Opens VS Code in the worktree directory |
| **Cursor** | ⌘⇧C | Opens Cursor IDE in the worktree directory |

Tools are auto-detected at launch. Install a supported tool and restart Oh My Worktree to see it appear.

## GitHub PR Integration

If [`gh` CLI](https://cli.github.com/) is installed and authenticated:

- PR badges appear automatically next to worktree branch names
- Badge colors indicate status: **green** (open), **purple** (merged), **red** (closed)
- Click the badge or use the submenu to open the PR in your browser
- Import worktrees directly from open PRs via **Import from GitHub PR...**

No configuration needed. If `gh` is not installed, PR features are hidden gracefully.

### Import from GitHub PR

1. Click **Import from GitHub PR...** in the menu bar dropdown
2. Select an open PR from the list
3. A new worktree is created and checked out to the PR's branch

## File Copying with `.worktreeinclude`

When creating a new worktree, Oh My Worktree can automatically copy files from your repository root. This is useful for environment files, local configs, etc.

### Setup

Create a `.worktreeinclude` file in your repository root:

```
# Copy environment files
.env*
*.local

# Copy specific config paths
config/local/**
**/settings.local.json
```

### Pattern Rules

- One glob pattern per line
- `#` comments and blank lines are ignored
- Simple patterns (e.g., `.env*`) match filenames anywhere in the tree
- Path patterns (e.g., `config/local/**`) match against relative paths
- `**/` prefix patterns match any path suffix

### Defaults

- **No `.worktreeinclude` file**: all `.env*` files are copied
- **Empty `.worktreeinclude` file**: nothing is copied

### Claude Code Compatibility

The `.worktreeinclude` format is compatible with [Claude Code](https://claude.ai/code) worktree patterns, so a single file works for both tools.

## Menu Bar

### Status Bar Title

The menu bar shows your current selection as `{repository}/{worktree}`. It updates in real-time when branches change externally (e.g., via `git checkout` in a terminal).

### Menu Bar Dropdown

Click the menu bar icon to access:
- Repository selection (top section)
- Worktree list with PR badges and activity times
- Hover a worktree to see the tool submenu
- Quick actions: New Worktree, Import PR, Settings, etc.

## Settings

Open Settings via ⌘, from the menu bar or main window.

### General

| Setting | Scope | Default | Description |
|---------|-------|---------|-------------|
| **Copy files to new worktrees** | Global / Per-repo | On | Copy files matching `.worktreeinclude` patterns when creating worktrees |
| **Launch at Login** | Global | Off | Start Oh My Worktree when you log in |

### Shortcuts

Customize all keyboard shortcuts, including the global hotkey. See [Keyboard Shortcuts](keyboard-shortcuts.md) for the full list.

### Advanced

Per-repository settings overrides. Click the **gear icon** next to the repository selector.

### Updates

| Setting | Default | Description |
|---------|---------|-------------|
| **Automatically check for updates** | On | Check for new versions on launch |

Oh My Worktree uses the [Sparkle](https://sparkle-project.org/) framework for secure auto-updates.
