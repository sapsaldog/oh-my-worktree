import SwiftUI

/// Renders a repo-relative path so the directory truncates with an ellipsis while
/// the filename is always fully visible. Full path shown on hover (CSS `.pl`).
/// Font/size come from the caller (`.font(...)`); only the directory is recolored
/// to tertiary — the filename inherits the surrounding foreground style.
struct PathLabel: View {
    let path: String

    var body: some View {
        let parts = CopiedPath.split(path)
        HStack(spacing: 0) {
            if !parts.dir.isEmpty {
                Text(parts.dir)
                    .foregroundStyle(OMWColor.labelTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(0)
            }
            Text(parts.base)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .help(path)
    }
}
