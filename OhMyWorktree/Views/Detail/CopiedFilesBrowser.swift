import SwiftUI

/// One glass sheet that browses a worktree's copied files and drills into a
/// unified diff vs. main. `focusedPath` (re-resolved against `files` each render so
/// it reflects applied changes) opens straight to that file's diff.
struct CopiedFilesBrowser: View {
    let files: [CopiedFile]
    @Binding var focusedPath: String?
    var onApply: (CopiedFile) -> Void
    var onClose: () -> Void

    @Environment(\.omwAccent) private var accent
    @State private var query = ""
    @State private var changedOnly = false

    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    private var active: CopiedFile? {
        guard let focusedPath else { return nil }
        return files.first { $0.path == focusedPath }
    }

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
            if let active {
                diffView(active)
            } else {
                listView
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 560)
        .glassSheet()
        .tint(accent)
        .onExitCommand {
            if focusedPath != nil {
                focusedPath = nil
            } else {
                onClose()
            }
        }
    }

    // MARK: List

    private var listView: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
                .padding(.init(top: 16, leading: 18, bottom: 0, trailing: 18))
            listControls
                .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))
            fileList
            footer(hint: "Click a changed file to view its diff and apply it back to main.") {
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
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
            Text(".worktreeinclude").font(.omwMono(11)).foregroundStyle(OMWColor.labelQuaternary)
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
                    CopiedFileRow(file: file) { focusedPath = file.path }
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

    // MARK: Diff drill-in

    private func diffView(_ file: CopiedFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            diffHeader(file)
            PathLabel(path: file.path)
                .font(.omwMono(14, weight: .bold))
                .foregroundStyle(OMWColor.labelPrimary)
                .padding(.init(top: 8, leading: 18, bottom: 0, trailing: 18))
            UnifiedDiffView(file: file)
                .padding(.init(top: 12, leading: 18, bottom: 4, trailing: 18))
            footer(hint: "Updates main's local copy only — nothing is committed to Git.") {
                Button { onApply(file) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.to.line").font(.system(size: 13))
                        Text(file.status == .new ? "Copy to main" : "Apply to main")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
            }
        }
    }

    private func diffHeader(_ file: CopiedFile) -> some View {
        HStack {
            Button { focusedPath = nil } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("All files").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(accent)
                .padding(.init(top: 4, leading: 4, bottom: 4, trailing: 8))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(file.status == .new ? "new file — not in main" : "comparing vs. main")
                .font(.omwMono(11)).foregroundStyle(OMWColor.labelQuaternary)
        }
        .padding(.init(top: 12, leading: 14, bottom: 0, trailing: 14))
    }

    // MARK: Footer

    private func footer(hint: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            Text(hint).font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.init(top: 12, leading: 18, bottom: 14, trailing: 18))
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }
}
