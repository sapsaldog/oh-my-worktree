import SwiftUI

struct ImportPRView: View {
    var worktreeViewModel: WorktreeListViewModel
    @State private var viewModel = ImportPRViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: Int?

    var body: some View {
        VStack(spacing: 0) {
            headerArea
            Divider()
            contentArea
            Divider()
            footerArea
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            viewModel.repositoryPath = worktreeViewModel.repository?.path ?? ""
            viewModel.repositoryName = worktreeViewModel.repository?.name ?? ""
            Task { await viewModel.loadPRs() }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var headerArea: some View {
        HeaderAreaView(viewModel: viewModel, selectedID: $selectedID)
    }

    private var contentArea: some View {
        ContentAreaView(viewModel: viewModel, selectedID: $selectedID)
    }

    private var footerArea: some View {
        FooterAreaView(
            viewModel: viewModel,
            worktreeViewModel: worktreeViewModel,
            dismiss: dismiss
        )
    }
}

// MARK: - Subviews

private struct HeaderAreaView: View {
    @Bindable var viewModel: ImportPRViewModel
    @Binding var selectedID: Int?

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(ImportPRViewModel.PRTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTab) { _, _ in
                viewModel.selectedPR = nil
                selectedID = nil
            }
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.selectedPR = nil
                selectedID = nil
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search by title, number, or branch…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

private struct ContentAreaView: View {
    var viewModel: ImportPRViewModel
    @Binding var selectedID: Int?

    @ViewBuilder
    var body: some View {
        if viewModel.isLoading {
            ProgressView("Loading pull requests…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.loadFailed {
            VStack(spacing: 8) {
                ContentUnavailableView(
                    "Could Not Load Pull Requests",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Make sure `gh` is installed, authenticated, and this repository is on GitHub.")
                )
                Button("Retry") { viewModel.retry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredPRs.isEmpty {
            if viewModel.allPRs.isEmpty {
                ContentUnavailableView(
                    "No Pull Requests",
                    systemImage: "arrow.triangle.pull",
                    description: Text("There are no pull requests in this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.searchText.isEmpty {
                let tabName = viewModel.selectedTab.rawValue.lowercased()
                ContentUnavailableView(
                    "No \(viewModel.selectedTab.rawValue) Pull Requests",
                    systemImage: "arrow.triangle.pull",
                    description: Text("There are no \(tabName) pull requests in this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No \(viewModel.selectedTab.rawValue.lowercased()) pull requests match your search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            List(viewModel.filteredPRs, id: \.number, selection: $selectedID) { pr in
                ImportPRRowView(pr: pr)
                    .tag(pr.number)
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)
            .onChange(of: selectedID) { _, id in
                let vm = viewModel
                Task { @MainActor in
                    vm.selectedPR = id.flatMap { num in vm.filteredPRs.first { $0.number == num } }
                }
            }
            .onChange(of: viewModel.selectedPR) { _, pr in
                if pr?.number != selectedID { selectedID = pr?.number }
            }
        }
    }
}

private struct FooterAreaView: View {
    var viewModel: ImportPRViewModel
    var worktreeViewModel: WorktreeListViewModel
    let dismiss: DismissAction

    var body: some View {
        HStack {
            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Import Worktree") {
                guard let pr = viewModel.selectedPR else { return }
                if let error = worktreeViewModel.addWorktreeFromPR(pr) {
                    viewModel.errorMessage = error
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedPR == nil)
        }
        .padding(16)
    }
}

// MARK: - PR Row

private struct ImportPRRowView: View {
    let pr: PullRequestInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PullRequestStateIcon(state: pr.state, size: 14)

                Text("#\(pr.number)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(pr.title.isEmpty ? pr.branch : pr.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.2))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                Text(pr.branch)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !pr.author.isEmpty {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("@\(pr.author)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let updatedAt = pr.updatedAt {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(updatedAt.relativeTimeString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
