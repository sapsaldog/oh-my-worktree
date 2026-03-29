import Foundation
import Observation

@Observable
@MainActor
final class ImportPRViewModel {

    enum PRTab: String, CaseIterable {
        case open = "Open"
        case draft = "Draft"
        case closed = "Closed"
    }

    var allPRs: [PullRequestInfo] = []
    var isLoading = false
    var loadFailed = false
    var errorMessage: String?
    var selectedPR: PullRequestInfo?
    var searchText = ""
    var selectedTab: PRTab = .open

    var repositoryPath: String = ""
    var repositoryName: String = ""

    private let pullRequestService: any PullRequestFetching
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = UUID()

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
