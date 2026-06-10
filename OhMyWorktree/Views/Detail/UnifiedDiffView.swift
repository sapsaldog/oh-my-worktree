import SwiftUI

/// GitHub-style unified diff: line-number gutters · +/− sign · code, red/green tinted.
/// Binary files (no line preview) show a placeholder instead.
struct UnifiedDiffView: View {
    let file: CopiedFile

    var body: some View {
        if file.isBinary {
            binaryPlaceholder
        } else {
            diffScroll
        }
    }

    private var binaryPlaceholder: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.badge.gearshape").font(.system(size: 13))
            Text("Binary file — no preview").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(OMWColor.labelTertiary)
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .background(OMWColor.fillQuaternary, in: RoundedRectangle(cornerRadius: OMWRadius.md))
    }

    private var diffScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(file.lines) { line in row(line) }
            }
        }
        .frame(maxHeight: 380)
        .overlay(RoundedRectangle(cornerRadius: OMWRadius.md).strokeBorder(OMWColor.separator, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: OMWRadius.md))
    }

    private func row(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            gutter(line.lineA)
            gutter(line.lineB).overlay(alignment: .trailing) {
                Rectangle().fill(OMWColor.separator).frame(width: 0.5)
            }
            Text(sign(line.kind)).frame(width: 16).foregroundStyle(signColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(OMWColor.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 10).padding(.leading, 5)
        }
        .font(.omwMono(11))
        .padding(.vertical, 1)
        .background(rowBackground(line.kind))
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.omwMono(10)).foregroundStyle(OMWColor.labelQuaternary)
            .frame(width: 34, alignment: .trailing).padding(.trailing, 6)
    }

    private func sign(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .add: "+"
        case .del: "−"
        case .context: ""
        }
    }

    private func signColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .add: OMWColor.sysGreen
        case .del: OMWColor.sysRed
        case .context: OMWColor.labelTertiary
        }
    }

    private func rowBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .add: OMWColor.sysGreen.opacity(0.13)
        case .del: OMWColor.sysRed.opacity(0.12)
        case .context: Color.clear
        }
    }
}
