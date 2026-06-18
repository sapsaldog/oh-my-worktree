import SwiftUI

/// A glass sheet that browses a worktree's copied files: searchable, filterable
/// list. Clicking a changed file hands it off to the selected external diff tool.
struct CopiedFilesBrowser: View {
    let files: [CopiedFile]
    let availableDiffTools: [DiffTool]
    var onOpenInDiffTool: (CopiedFile) -> Void
    var onClose: () -> Void

    @Environment(\.omwAccent) private var accent
    @State private var query = ""
    @State private var changedOnly = false

    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    private var sorted: [CopiedFile] {
        files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }

    private var filtered: [CopiedFile] {
        sorted.filter { file in
            (!changedOnly || file.status.isChanged)
                && (query.isEmpty || file.path.lowercased().contains(query.lowercased()))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
                .padding(.init(top: 16, leading: 18, bottom: 0, trailing: 18))
            listControls
                .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))
            fileList
            footer
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .glassSheet()
        .tint(accent)
        .onExitCommand { onClose() }
    }

    private var listHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 7) {
                Text("Copied files").font(.system(size: 14, weight: .bold))
                Text("\(files.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(OMWColor.labelTertiary)
                if changedCount > 0 {
                    Text("· \(changedCount) changed vs. main")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OMWColor.sysOrange)
                }
            }
            Spacer()
            DiffToolMenu(available: availableDiffTools)
        }
    }

    private var listControls: some View {
        HStack(spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
                TextField("Filter files…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(OMWColor.controlBg, in: Capsule())
            .overlay(Capsule().strokeBorder(OMWColor.separator, lineWidth: 0.5))

            if changedCount > 0 {
                Button { changedOnly.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: changedOnly ? "checkmark" : "arrow.left.arrow.right").font(.system(size: 12))
                        Text("Changed only").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(changedOnly ? OMWColor.onAccent : OMWColor.labelSecondary)
                    .padding(.horizontal, 11).frame(height: 28)
                    .background(changedOnly ? AnyShapeStyle(accent) : AnyShapeStyle(OMWColor.fillTertiary), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { file in
                    CopiedFileRow(file: file) { onOpenInDiffTool(file) }
                }
                if filtered.isEmpty {
                    Text("No files match \u{201C}\(query)\u{201D}.")
                        .font(.system(size: 13)).foregroundStyle(OMWColor.labelTertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                }
            }
            .padding(.init(top: 6, leading: 12, bottom: 12, trailing: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("Click a changed file to open it in your diff tool — edits there touch disk only, never Git.")
                .font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Done", action: onClose)
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.init(top: 12, leading: 18, bottom: 14, trailing: 18))
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }
}
