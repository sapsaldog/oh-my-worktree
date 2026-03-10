import Foundation

@MainActor
final class ImportPRViewModel: ObservableObject {

    enum PRTab: String, CaseIterable {
        case open = "Open"
        case draft = "Draft"
        case closed = "Closed"
    }

    @Published var allPRs: [PullRequestInfo] = []
    @Published var isLoading = false
    @Published var loadFailed = false
    @Published var errorMessage: String?
    @Published var selectedPR: PullRequestInfo?
    @Published var searchText = ""
    @Published var selectedTab: PRTab = .open

    var repositoryPath: String = ""
    var repositoryName: String = ""

    private let pullRequestService: any PullRequestFetching
    private var loadTask: Task<Void, Never>?
    /// Generation counter to invalidate stale results when loadPRs is called
    /// concurrently (e.g. rapid sheet open/close cycles).
    private var loadGeneration = UUID()

    init(pullRequestService: any PullRequestFetching = PullRequestService()) {
        self.pullRequestService = pullRequestService
    }

    var filteredPRs: [PullRequestInfo] {
        let tabFiltered = allPRs.filter { pr in
            switch selectedTab {
            case .open:   return pr.state == .open && !pr.isDraft
            case .draft:  return pr.state == .open && pr.isDraft
            case .closed: return pr.state == .merged || pr.state == .closed
            }
        }
        guard !searchText.isEmpty else { return tabFiltered }
        let query = searchText.lowercased()
        return tabFiltered.filter { pr in
            pr.title.lowercased().contains(query) ||
            String(pr.number).contains(query) ||
            pr.branch.lowercased().contains(query)
        }
    }

    func loadPRs() async {
        guard !repositoryPath.isEmpty else { return }
        let myGeneration = UUID()
        loadGeneration = myGeneration
        isLoading = true
        loadFailed = false
        errorMessage = nil
        if let prs = await pullRequestService.fetchPullRequestList(repositoryPath: repositoryPath) {
            guard loadGeneration == myGeneration else { return }
            allPRs = prs
        } else {
            guard loadGeneration == myGeneration else { return }
            loadFailed = true
            allPRs = []
        }
        // Only reset isLoading when this call's generation is still current.
        // A stale call (generation mismatch) must not clear isLoading — the
        // newer call owns the loading state.
        isLoading = false
    }

    func retry() {
        loadTask?.cancel()
        loadTask = Task { await loadPRs() }
    }
}
