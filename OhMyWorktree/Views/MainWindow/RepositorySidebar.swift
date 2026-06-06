import SwiftUI

/// Left column (220): REPOSITORIES header + repo rows + footer
/// (Settings / Check for Updates). Sits on the window's glass as a vibrant panel.
struct RepositorySidebar: View {
    var repoVM: RepositoryListViewModel
    var width: CGFloat
    var selectedWorktreeCount: Int
    var onSelect: (Repository) -> Void
    var onAddRepo: () -> Void
    var onSettings: () -> Void
    var onCheckUpdates: () -> Void

    @Environment(\.omwAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(repoVM.repositories) { repo in
                        row(repo)
                    }
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(width: width)
        .background(OMWColor.sidebar)
    }

    private var header: some View {
        HStack {
            Text("Repositories")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.33)
                .foregroundStyle(OMWColor.labelTertiary)
            Spacer()
            Button(action: onAddRepo) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
            .buttonStyle(.plain)
            .help("Add repository")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
    }

    private func row(_ repo: Repository) -> some View {
        let isSelected = repoVM.selectedRepository?.id == repo.id
        return Button {
            onSelect(repo)
        } label: {
            HStack(spacing: 9) {
                Image("FolderGit2")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isSelected ? OMWColor.onAccent : accent)
                Text(repo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? OMWColor.onAccent : OMWColor.labelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Text("\(selectedWorktreeCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OMWColor.onAccent.opacity(0.75))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: OMWRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            footerRow("Settings", icon: "gearshape", action: onSettings)
            footerRow("Check for Updates", icon: "arrow.up.circle", action: onCheckUpdates)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(OMWColor.separator).frame(height: 0.5)
        }
    }

    private func footerRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 16)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(OMWColor.labelSecondary)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
