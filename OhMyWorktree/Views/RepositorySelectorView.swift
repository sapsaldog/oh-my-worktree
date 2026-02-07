import SwiftUI

struct RepositorySelectorView: View {
    @ObservedObject var viewModel: RepositoryListViewModel
    @State private var showingFileDialog = false
    @State private var showingRepoSettings = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            if viewModel.repositories.isEmpty {
                Text("No repositories added")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Repository", selection: Binding<UUID?>(
                    get: { viewModel.selectedRepository?.id },
                    set: { newID in
                        if let id = newID,
                           let repo = viewModel.repositories.first(where: { $0.id == id }) {
                            Task {
                                await viewModel.selectRepository(repo)
                            }
                        }
                    }
                )) {
                    ForEach(viewModel.repositories) { repo in
                        HStack {
                            Text(repo.name)
                            if !repo.isValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .tag(Optional(repo.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Button(action: {
                showingFileDialog = true
            }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add Repository")

            if viewModel.selectedRepository != nil {
                Button(action: {
                    Task {
                        await viewModel.removeSelectedRepository()
                    }
                }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .help("Remove Repository")

                Button(action: {
                    showingRepoSettings = true
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Repository Settings")
                .popover(isPresented: $showingRepoSettings) {
                    if let repo = viewModel.selectedRepository {
                        RepositorySettingsView(
                            repository: repo,
                            store: viewModel.store
                        )
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileDialog,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let path = url.path(percentEncoded: false)
                Task {
                    await viewModel.addRepository(at: path)
                }
            case .failure(let error):
                Task { @MainActor in
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
