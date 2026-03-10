import SwiftUI

struct QueueStatusBarView: View {
    @ObservedObject var viewModel: WorktreeListViewModel
    @State private var showingQueueDetail = false

    var body: some View {
        queueBar
    }

    // MARK: - Queue Bar

    private var queueBar: some View {
        let queue = viewModel.jobQueue
        return HStack(spacing: 8) {
            Button(action: {
                guard queue.hasActiveJobs || queue.hasFailedJobs else { return }
                showingQueueDetail.toggle()
            }) {
                HStack(spacing: 8) {
                    if queue.hasActiveJobs {
                        ProgressView(value: queue.progressFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 72)
                            .tint(.blue)

                        if let desc = queue.currentJobDescription {
                            Text(desc)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else if queue.hasFailedJobs {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text("\(queue.failedJobCount) failed (click to review)")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    } else {
                        Text("No active tasks")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!queue.hasActiveJobs && !queue.hasFailedJobs)

            Spacer()

            if viewModel.repository != nil {
                addSplitButton
            }
        }
        .popover(isPresented: $showingQueueDetail, arrowEdge: .bottom) {
            QueueDetailPopoverView(queue: queue)
        }
    }
    // MARK: - Add Split Button

    private var addSplitButton: some View {
        HStack(spacing: 0) {
            Button(action: { Task { await viewModel.addWorktree() } }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help("New Worktree")
            .accessibilityLabel("New Worktree")

            Menu {
                Button("Import from GitHub PR…") {
                    viewModel.isShowingImportPR = true
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options")
            .accessibilityLabel("More options")
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Queue Detail Popover

struct QueueDetailPopoverView: View {
    @ObservedObject var queue: BackgroundTaskQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(queue.hasFailedJobs && !queue.hasActiveJobs ? "Failed Tasks" : "Active Tasks")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            if queue.jobs.isEmpty {
                Text("No active tasks")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(queue.jobs) { job in
                            QueueJobRowView(job: job) {
                                queue.cancel(job.id)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)

                if queue.hasActiveJobs {
                    Divider()
                    Button("Cancel Pending", role: .destructive) {
                        queue.cancelPending()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if queue.hasFailedJobs {
                    Divider()
                    Button("Clear Failed") {
                        queue.clearFailed()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 280)
    }
}

// MARK: - Queue Job Row

private struct QueueJobRowView: View {
    let job: BackgroundJob
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            stateIcon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(job.kind.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .pending = job.state {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            if case .failed(let msg) = job.state {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help(msg)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(job.state == .cancelled ? 0.4 : 1.0)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch job.state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.tertiary)
        }
    }
}
