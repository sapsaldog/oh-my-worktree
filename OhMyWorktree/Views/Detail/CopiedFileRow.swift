import SwiftUI

/// A full-width row in the browser list: status dot · path · `+N −N`/`new`/`identical` · chevron.
struct CopiedFileRow: View {
    let file: CopiedFile
    var onSelect: () -> Void

    // Every copied file opens in the external diff tool (identical included), so the
    // row is always a button. Identical rows dim via color tier only — never a whole-row
    // opacity, which stacked with the tertiary text into illegibility in light mode.
    var body: some View {
        Button { onSelect() } label: { rowContent }
            .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            PathLabel(path: file.path)
                .font(.omwMono(12.5, weight: .medium))
                .foregroundStyle(file.status.isChanged ? OMWColor.labelPrimary : OMWColor.labelSecondary)
            Spacer(minLength: 8)
            rowBadge
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12))
                .foregroundStyle(OMWColor.labelTertiary)
        }
        .padding(.horizontal, 11).frame(height: 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OMWColor.fillTertiary.opacity(0.0001))   // hit area
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowBadge: some View {
        switch file.status {
        case .modified:
            HStack(spacing: 4) {
                Text("+\(file.added)").foregroundStyle(OMWColor.sysGreen)
                Text("−\(file.removed)").foregroundStyle(OMWColor.sysRed)
            }
            .font(.omwMono(12, weight: .bold))
        case .new:
            Text("new").font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                .tracking(0.4).foregroundStyle(OMWColor.sysGreen)
        case .missing:
            Text("missing").font(.system(size: 10, weight: .bold)).textCase(.uppercase)
                .tracking(0.4).foregroundStyle(OMWColor.sysRed)
        case .identical:
            Text("identical").font(.system(size: 10, weight: .medium))
                .foregroundStyle(OMWColor.labelTertiary)
        }
    }

    private var dotColor: Color {
        switch file.status {
        case .modified: OMWColor.sysOrange
        case .new: OMWColor.sysGreen
        case .missing: OMWColor.sysRed
        case .identical: OMWColor.labelTertiary
        }
    }
}
