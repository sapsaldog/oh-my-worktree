import Testing

@testable import OhMyWorktree

@Suite
struct DiffToolTests {

    @Test func catalogHasTheFiveDesignTools() {
        #expect(DiffTool.all.map(\.id) == ["araxis", "kaleidoscope", "bcompare", "vscode", "filemerge"])
        #expect(DiffTool.all.map(\.name) == [
            "Araxis Merge", "Kaleidoscope", "Beyond Compare", "VS Code", "FileMerge"
        ])
    }

    @Test func findReturnsToolByIDOrNil() {
        #expect(DiffTool.find(id: "vscode")?.name == "VS Code")
        #expect(DiffTool.find(id: "nope") == nil)
    }

    @Test func vscodeArgsIncludeDiffFlagOthersDoNot() {
        let vscode = DiffTool.find(id: "vscode")!
        #expect(vscode.launchArguments(mainPath: "/m", worktreePath: "/w") == ["--diff", "/m", "/w"])
        let araxis = DiffTool.find(id: "araxis")!
        #expect(araxis.launchArguments(mainPath: "/m", worktreePath: "/w") == ["/m", "/w"])
    }

    @Test func everyToolHasAtLeastOneCommandCandidate() {
        for tool in DiffTool.all {
            #expect(!tool.commandCandidates.isEmpty)
            #expect(!tool.sfSymbol.isEmpty)
        }
    }

    @Test func araxisPrefersBundledCompareOverPathToAvoidImageMagickClash() {
        // ImageMagick also ships a `compare`; the in-bundle path must come first.
        #expect(DiffTool.find(id: "araxis")!.commandCandidates.first
            == "/Applications/Araxis Merge.app/Contents/Utilities/compare")
    }

    @Test func installedFiltersByProbe() {
        let installed = DiffTool.installed { $0.id == "vscode" || $0.id == "filemerge" }
        #expect(installed.map(\.id) == ["vscode", "filemerge"])
    }

    @Test func effectiveUsesStoredWhenInstalled() {
        let installed = DiffTool.all
        #expect(DiffTool.effective(storedID: "bcompare", installed: installed)?.id == "bcompare")
    }

    @Test func effectiveFallsBackToFirstInstalledWhenStoredMissingOrNil() {
        let installed = [DiffTool.find(id: "vscode")!, DiffTool.find(id: "filemerge")!]
        #expect(DiffTool.effective(storedID: "araxis", installed: installed)?.id == "vscode")
        #expect(DiffTool.effective(storedID: nil, installed: installed)?.id == "vscode")
    }

    @Test func effectiveIsNilWhenNothingInstalled() {
        #expect(DiffTool.effective(storedID: "vscode", installed: []) == nil)
    }
}
