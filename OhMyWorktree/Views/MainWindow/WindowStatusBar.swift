import AppKit
import SwiftUI

/// Bottom window activity bar (28): worktree path (copy) + background-task status
/// (running / idle / failed) with a Background Tasks popover.
struct WindowStatusBar: View {
    @Bindable var worktreeViewModel: WorktreeListViewModel
    var pathText: String
    var repositoryID: UUID?

    @State private var showTasks = false

    private var running: [BackgroundJob] {
        worktreeViewModel.jobQueue.activeJobs.filter { repositoryID == nil || $0.repositoryID == repositoryID }
    }
    private var failed: [BackgroundJob] {
        worktreeViewModel.jobQueue.failedJobs.filter { repositoryID == nil || $0.repositoryID == repositoryID }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: copyPath) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(OMWColor.labelQuaternary)
                    Text(pathText)
                        .font(.omwMono(11))
                        .foregroundStyle(OMWColor.labelTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .buttonStyle(.plain)
            .help("Copy path")

            Spacer(minLength: 8)

            activity
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: Rectangle())
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }

    @ViewBuilder
    private var activity: some View {
        HStack(spacing: 12) {
            if !running.isEmpty {
                Button { showTasks.toggle() } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                        Text(running.count == 1 ? "1 task running…" : "\(running.count) tasks running…")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(OMWColor.labelSecondary)
                }
                .buttonStyle(.plain)
            }
            if !failed.isEmpty {
                Button { showTasks.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12))
                        Text("\(failed.count) failed (click to review)").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(OMWColor.sysRed)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(OMWColor.sysRed.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if running.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(OMWColor.sysGreen)
                    Text("All tasks complete").font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
                }
            }
        }
        .popover(isPresented: $showTasks, arrowEdge: .bottom) {
            BackgroundTasksPopover(
                running: running,
                failed: failed,
                onSelect: { job in worktreeViewModel.selectedWorktreeIDs = [job.worktreeID]; showTasks = false },
                onRetry: { job in worktreeViewModel.jobQueue.retry(job.id) },
                onClear: { worktreeViewModel.jobQueue.clearFailed(); showTasks = false }
            )
        }
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pathText, forType: .string)
    }
}

/// The popover listing running + failed background jobs, with retry and clear.
struct BackgroundTasksPopover: View {
    var running: [BackgroundJob]
    var failed: [BackgroundJob]
    var onSelect: (BackgroundJob) -> Void
    var onRetry: (BackgroundJob) -> Void
    var onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("Background Tasks")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OMWColor.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.init(top: 11, leading: 14, bottom: 8, trailing: 14))
                .overlay(alignment: .bottom) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(running) { runningRow($0) }
                    ForEach(failed) { failedRow($0) }
                    if running.isEmpty && failed.isEmpty {
                        Text("No background tasks")
                            .font(.system(size: 12))
                            .foregroundStyle(OMWColor.labelTertiary)
                            .padding(.vertical, 22)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 220)

            if !failed.isEmpty {
                Divider()
                Button("Clear Failed", action: onClear)
                    .controlSize(.small)
                    .padding(.init(top: 8, leading: 12, bottom: 12, trailing: 12))
            }
        }
        .frame(width: 280)
    }

    private func runningRow(_ job: BackgroundJob) -> some View {
        Button { onSelect(job) } label: {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16)
                rowBody(job)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func failedRow(_ job: BackgroundJob) -> some View {
        Button { onSelect(job) } label: {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(OMWColor.sysRed)
                rowBody(job)
                Spacer(minLength: 0)
                Button { onRetry(job) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Retry")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowBody(_ job: BackgroundJob) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OMWColor.labelPrimary)
                .lineLimit(1)
            Text(job.kind.displayLabel)
                .font(.system(size: 11))
                .foregroundStyle(OMWColor.labelTertiary)
        }
    }
}
