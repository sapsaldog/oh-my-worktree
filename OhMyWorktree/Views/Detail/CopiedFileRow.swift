import SwiftUI

/// A full-width row in the browser list: status dot · path · `+N −N`/`new`/`identical` · chevron.
struct CopiedFileRow: View {
    let file: CopiedFile
    var onSelect: () -> Void

    // Identical rows dim via color tier only and render as a non-button: a whole-row
    // opacity multiplied the already-tertiary directory/dot colors (plus the
    // disabled-button dim) into illegibility in light mode.
    @ViewBuilder
    var body: some View {
        if file.status.isClickable {
            Button { onSelect() } label: { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            PathLabel(path: file.path)
                .font(.omwMono(12.5, weight: .medium))
                .foregroundStyle(file.status.isClickable ? OMWColor.labelPrimary : OMWColor.labelSecondary)
            Spacer(minLength: 8)
            rowBadge
            if file.status.isClickable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(OMWColor.labelTertiary)
            }
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
