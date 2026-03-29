import AppKit

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        menuRefreshTask?.cancel()
        menuRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.repoViewModel?.repositories.isEmpty == true {
                await self.repoViewModel?.loadRepositories()
            }
            let before = self.worktreeViewModel?.worktrees
            await self.worktreeViewModel?.loadWorktrees(debounce: true)
            if before != self.worktreeViewModel?.worktrees {
                self.rebuildMenu()
                self.updateStatusItemTitle()
            }
        }
    }
}

// MARK: - Menu Construction

extension AppDelegate {

    func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        addRepositorySection(to: menu)
        addWorktreeSection(to: menu)
        addSystemMenuItems(to: menu)
    }

    // MARK: - Repository Section

    private func addRepositorySection(to menu: NSMenu) {
        let repositories = repoViewModel?.repositories ?? []
        let selectedRepo = repoViewModel?.selectedRepository
        for repo in repositories {
            let item = NSMenuItem(
                title: repo.name,
                action: #selector(repositorySelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = repo.id
            if let selectedRepo, selectedRepo.id == repo.id { item.state = .on }
            menu.addItem(item)
        }
        if !repositories.isEmpty { menu.addItem(.separator()) }
    }

    // MARK: - Worktree Section

    private func addWorktreeSection(to menu: NSMenu) {
        let worktrees = worktreeViewModel?.worktrees ?? []
        let pullRequests = worktreeViewModel?.pullRequests ?? [:]
        let deletingIDs = Set((worktreeViewModel?.jobQueue.jobs ?? [])
            .filter { job in
                job.state.isActive && {
                    switch job.kind {
                    case .removeWorktree, .quickRemove: return true
                    default: return false
                    }
                }()
            }
            .map { $0.worktreeID })

        for worktree in worktrees {
            guard !worktree.isBare else { continue }
            if deletingIDs.contains(worktree.id) { continue }
            let isSelected = worktreeViewModel?.selectedWorktree?.id == worktree.id
            let bullet = isSelected ? "\u{25CF} " : "   "
            let pr = worktree.branch.flatMap { pullRequests[$0] }
                ?? worktree.prRemoteBranch.flatMap { pullRequests[$0] }
            let prLabel = pr.map { " #\($0.number)" } ?? ""
            let activity = worktree.relativeLastActivity.map { "  \($0)" } ?? ""
            let item = NSMenuItem(
                title: "\(bullet)\(worktree.displayName)\(prLabel)\(activity)",
                action: #selector(worktreeSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = WorktreeRef(id: worktree.id, path: worktree.path, prURL: pr?.url)
            item.submenu = buildWorktreeSubmenu(for: worktree, pullRequest: pr)
            menu.addItem(item)
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
    }

    // MARK: - System Menu Items

    private func addSystemMenuItems(to menu: NSMenu) {
        let addItem = NSMenuItem(
            title: "+ New Worktree",
            action: #selector(newWorktreeClicked(_:)),
            keyEquivalent: "n"
        )
        addItem.target = self
        addItem.isEnabled = repoViewModel?.selectedRepository != nil
        menu.addItem(addItem)

        if repoViewModel?.selectedRepository != nil && worktreeViewModel?.isGitHubRepo == true {
            let importItem = NSMenuItem(
                title: "Import from GitHub PR…",
                action: #selector(importFromGitHubPRClicked(_:)),
                keyEquivalent: ""
            )
            importItem.target = self
            menu.addItem(importItem)
        }

        menu.addItem(.separator())

        let openWindowItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(openMainWindowClicked(_:)),
            keyEquivalent: "o"
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(settingsClicked(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesClicked(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = self
        updatesItem.isEnabled = updaterManager?.canCheckForUpdates ?? false
        menu.addItem(updatesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Oh My Worktree",
            action: #selector(quitClicked(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Worktree Submenu

    private func buildWorktreeSubmenu(for worktree: Worktree, pullRequest: PullRequestInfo? = nil) -> NSMenu {
        let submenu = NSMenu()
        let ref = WorktreeRef(id: worktree.id, path: worktree.path)

        addExternalToolItems(to: submenu, ref: ref)

        if let pr = pullRequest {
            if submenu.numberOfItems > 0 { submenu.addItem(.separator()) }
            let prItem = NSMenuItem(
                title: "Open Pull Request #\(pr.number)",
                action: #selector(openPullRequestClicked(_:)),
                keyEquivalent: ""
            )
            prItem.target = self
            prItem.representedObject = WorktreeRef(id: worktree.id, path: worktree.path, prURL: pr.url)
            submenu.addItem(prItem)
        }

        if submenu.numberOfItems > 0 { submenu.addItem(.separator()) }

        if !worktree.isBare {
            let pullItem = NSMenuItem(title: "Git Pull", action: #selector(gitPullClicked(_:)), keyEquivalent: "")
            pullItem.target = self
            pullItem.representedObject = ref
            submenu.addItem(pullItem)
            submenu.addItem(.separator())
        }

        let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathClicked(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = ref
        submenu.addItem(copyItem)

        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinderClicked(_:)), keyEquivalent: "")
        finderItem.target = self
        finderItem.representedObject = ref
        submenu.addItem(finderItem)

        return submenu
    }

    private func addExternalToolItems(to submenu: NSMenu, ref: WorktreeRef) {
        let tools: [(available: Bool, title: String, action: Selector)] = [
            (worktreeViewModel?.isITermAvailable == true, "Open in iTerm", #selector(openInITermClicked(_:))),
            (worktreeViewModel?.isGhosttyAvailable == true, "Open in Ghostty", #selector(openInGhosttyClicked(_:))),
            (worktreeViewModel?.isVSCodeAvailable == true, "Open in VSCode", #selector(openInVSCodeClicked(_:))),
            (worktreeViewModel?.isCursorAvailable == true, "Open in Cursor", #selector(openInCursorClicked(_:))),
            (worktreeViewModel?.isCmuxAvailable == true, "Open in cmux", #selector(openInCmuxClicked(_:)))
        ]
        for (available, title, action) in tools where available {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = ref
            submenu.addItem(item)
        }
    }
}
