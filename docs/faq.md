# FAQ

## General

### Where is the app? I don't see it in the Dock.

Oh My Worktree runs as a **menu bar app**. Look for the icon in the top-right area of your screen (near the clock). It only appears in the Dock when a window is open.

### How do I quit the app?

Click the menu bar icon, then select **Quit Oh My Worktree** (⌘Q). Or use the keyboard shortcut directly if a window is focused.

### Does Oh My Worktree modify my Git repositories?

Only when you explicitly ask it to (creating/removing worktrees, git pull). It never modifies branches, commits, or repository settings on its own.

## Repositories

### What is a bare repository?

A bare Git repository is a repo without a working directory. It's the recommended way to use Git worktrees, as it avoids conflicts between the "main" working directory and worktree directories.

To create one:
```bash
git clone --bare https://github.com/your/repo.git ~/repos/repo.git
```

### Can I use a regular (non-bare) repository?

Git worktrees work with regular repositories too, but bare repositories are recommended to avoid confusion about which directory is the "main" one.

### My repository disappeared from the list.

If the repository folder was moved or deleted, Oh My Worktree removes it from the list automatically. Re-add it with the **+** button.

## Worktrees

### What happens when I create a new worktree?

1. A new directory is created as a sibling of your repository (e.g., `~/repos/tokyo-lunch/`)
2. A new branch with the same name is created and checked out
3. Files matching `.worktreeinclude` patterns are copied (or `.env*` by default)

### Can I change the worktree directory location?

Worktrees are created as siblings of the bare repository. This is the standard Git worktree layout and cannot be changed.

### Why is my worktree name different from the branch name?

Oh My Worktree generates random names (e.g., `tokyo-lunch`) for worktrees. The branch name matches the worktree folder name by default.

## External Tools

### My tool doesn't appear in the menu.

Oh My Worktree auto-detects installed tools at launch. Make sure the tool is:
- Installed and accessible from the command line
- For VSCode: `code` command is available in PATH
- For Cursor: `cursor` command is available in PATH

Restart Oh My Worktree after installing a new tool.

### How do I add support for a different tool?

Currently, Oh My Worktree supports iTerm, Ghostty, cmux, VSCode, and Cursor. Feature requests for additional tools are welcome on [GitHub Issues](https://github.com/sapsaldog/oh-my-worktree/issues).

## GitHub PR Integration

### PR badges are not showing up.

Make sure:
1. [`gh` CLI](https://cli.github.com/) is installed (`brew install gh`)
2. You are authenticated (`gh auth login`)
3. The repository is hosted on GitHub

### I see "Import from GitHub PR..." but no PRs are listed.

This only shows **open** pull requests. If there are no open PRs, the list will be empty.

## Updates

### How do I check for updates?

Click the menu bar icon and select **Check for Updates...**. Automatic update checks can be enabled in **Settings > Updates**.

### Is it safe to update?

Yes. Updates are cryptographically signed with EdDSA. Oh My Worktree uses [Sparkle](https://sparkle-project.org/), the same update framework used by many popular macOS apps.

## Troubleshooting

### The menu bar icon is not responding.

Try quitting and relaunching the app. If the issue persists, check **Activity Monitor** for a stuck `OhMyWorktree` process and force-quit it.

### Worktree list is not refreshing.

Press ⌘R to manually refresh. If the problem persists, check that your Git repository is accessible and not corrupted.

### I found a bug. Where do I report it?

Please open an issue on [GitHub Issues](https://github.com/sapsaldog/oh-my-worktree/issues) with:
- macOS version
- Oh My Worktree version (shown in Settings)
- Steps to reproduce the issue
