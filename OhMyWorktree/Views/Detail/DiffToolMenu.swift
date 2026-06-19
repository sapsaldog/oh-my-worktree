import SwiftUI

/// "Open diffs in [tool ▾]" picker. Lists all five tools; tools not present in
/// `available` are disabled with a "Not installed" hint. The selection persists in
/// `@AppStorage("diffToolID")` and is shared by every placement (detail header,
/// browser header, Settings). Coverage-excluded (Views/**).
struct DiffToolMenu: View {
    /// The installed tools (from `DiffToolLauncher.installedTools()`).
    let available: [DiffTool]

    @AppStorage("diffToolID") private var diffToolID: String = ""

    private var effective: DiffTool? {
        DiffTool.effective(storedID: diffToolID.isEmpty ? nil : diffToolID, installed: available)
    }

    var body: some View {
        Menu {
            ForEach(DiffTool.all) { tool in
                let installed = available.contains(tool)
                Button {
                    diffToolID = tool.id
                } label: {
                    Label {
                        Text(installed ? tool.name : "\(tool.name) — Not installed")
                    } icon: {
                        Image(systemName: tool.sfSymbol)
                    }
                    if tool.id == effective?.id { Image(systemName: "checkmark") }
                }
                .disabled(!installed)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: effective?.sfSymbol ?? "arrow.left.arrow.right")
                    .font(.system(size: 12))
                Text(effective?.name ?? "No diff tool")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .foregroundStyle(OMWColor.labelSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(available.isEmpty)
        .help("Choose the diff tool to open copied files in")
    }
}
