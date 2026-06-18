import SwiftUI

/// Detail-pane "Copied files" section: a compact one-line header with a changed
/// count, status chips (modified `+N −N` / `new` / dimmed identical), and a
/// "View all" button that opens the searchable browser sheet.
struct CopiedFilesSection: View {
    let files: [CopiedFile]
    var availableDiffTools: [DiffTool] = []
    var onOpenInDiffTool: (CopiedFile) -> Void = { _ in }
    var onBrowseAll: () -> Void = {}

    private let cap = 5

    private var sorted: [CopiedFile] {
        files.sorted { lhs, rhs in
            lhs.status.sortRank != rhs.status.sortRank
                ? lhs.status.sortRank < rhs.status.sortRank
                : lhs.path < rhs.path
        }
    }
    private var changedCount: Int { files.filter { $0.status.isChanged }.count }

    var body: some View {
        let many = files.count > cap
        let shown = many ? Array(sorted.prefix(cap)) : sorted

        VStack(alignment: .leading, spacing: 10) {
            header
            FlowLayout(spacing: 6) {
                ForEach(shown) { chip($0) }
            }
            if many { viewAllButton }
        }
        .padding(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(OMWColor.separator).frame(height: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("Copied files")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.3)
                    .foregroundStyle(OMWColor.labelTertiary)
                Text("\(files.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OMWColor.labelTertiary)
                if changedCount > 0 {
                    Text("· \(changedCount) changed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OMWColor.sysOrange)
                }
            }
            Spacer()
            DiffToolMenu(available: availableDiffTools)
        }
    }

    // Every copied file opens in the external diff tool (identical included), so the
    // chip is always a button. Identical chips dim via color tier only (secondary text
    // on a plain fill) — never a whole-chip opacity, which stacked with the tertiary
    // directory text into illegibility in light mode.
    private func chip(_ file: CopiedFile) -> some View {
        Button { onOpenInDiffTool(file) } label: { chipLabel(file) }
            .buttonStyle(.plain)
            .help(file.status.isChanged
                ? "\(file.path) — open in your diff tool"
                : "\(file.path) — identical to main; open in your diff tool")
    }

    private func chipLabel(_ file: CopiedFile) -> some View {
        HStack(spacing: 5) {
            switch file.status {
            case .modified: Circle().fill(OMWColor.sysOrange).frame(width: 6, height: 6)
            case .new: Circle().fill(OMWColor.sysGreen).frame(width: 6, height: 6)
            case .missing: Circle().fill(OMWColor.sysRed).frame(width: 6, height: 6)
            case .identical: Image(systemName: "doc").font(.system(size: 11))
            }
            PathLabel(path: file.path)
                .font(.omwMono(11, weight: .medium))
            if file.status == .modified {
                HStack(spacing: 4) {
                    Text("+\(file.added)").foregroundStyle(OMWColor.sysGreen)
                    Text("−\(file.removed)").foregroundStyle(OMWColor.sysRed)
                }
                .font(.omwMono(11, weight: .bold))
            } else if file.status == .new {
                Text("new")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(OMWColor.sysGreen)
            } else if file.status == .missing {
                Text("missing")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(OMWColor.sysRed)
            }
        }
        .foregroundStyle(file.status == .identical ? OMWColor.labelSecondary : OMWColor.labelPrimary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(chipBackground(file.status), in: Capsule())
    }

    private func chipBackground(_ status: CopiedFileStatus) -> Color {
        switch status {
        case .modified: OMWColor.sysOrange.opacity(0.15)
        case .new: OMWColor.sysGreen.opacity(0.15)
        case .missing: OMWColor.sysRed.opacity(0.15)
        case .identical: OMWColor.fillTertiary
        }
    }

    private var viewAllButton: some View {
        Button(action: onBrowseAll) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet").font(.system(size: 13))
                Text("View all \(files.count) files").font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
            }
            .foregroundStyle(OMWColor.labelSecondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(OMWColor.fillTertiary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
        }
        .buttonStyle(.plain)
    }
}
