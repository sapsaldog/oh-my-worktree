import SwiftUI

/// Detail-pane "Copied files" section: collapses to the first few chips with a
/// "+N more" affordance; expands to a scrollable list with a filter when large.
struct CopiedFilesSection: View {
    let files: [CopiedFile]

    @State private var expanded = false
    @State private var query = ""

    private let cap = 5

    var body: some View {
        let many = files.count > cap
        let searchable = files.count > 12
        let names = files.map(\.path)
        let filtered = query.isEmpty
            ? names
            : names.filter { $0.lowercased().contains(query.lowercased()) }
        let shown = (!expanded && many) ? Array(names.prefix(cap)) : filtered

        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded && searchable { searchField }
            chips(shown: shown, many: many, noMatches: expanded && !query.isEmpty && filtered.isEmpty)
            if expanded && many { showLessButton }
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
                Text("\(files.count)")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(OMWColor.labelTertiary)
            Spacer()
            Text(".worktreeinclude")
                .font(.omwMono(10))
                .foregroundStyle(OMWColor.labelQuaternary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(OMWColor.labelTertiary)
            TextField("Filter \(files.count) files…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(OMWColor.controlBg, in: Capsule())
        .overlay(Capsule().strokeBorder(OMWColor.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private func chips(shown: [String], many: Bool, noMatches: Bool) -> some View {
        let flow = FlowLayout(spacing: 6) {
            ForEach(shown, id: \.self) { CopiedFileChip(name: $0) }
            if !expanded && many { moreButton }
            if noMatches {
                Text("No files match “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
        }
        if expanded && many {
            ScrollView {
                flow.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 156)
        } else {
            flow
        }
    }

    private var moreButton: some View {
        Button { expanded = true } label: {
            Text("+\(files.count - cap) more")
                .font(.omwMono(11, weight: .semibold))
                .foregroundStyle(OMWColor.labelSecondary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(OMWColor.fillSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var showLessButton: some View {
        Button {
            expanded = false
            query = ""
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
                Text("Show less").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(OMWColor.labelSecondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(OMWColor.fillSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
