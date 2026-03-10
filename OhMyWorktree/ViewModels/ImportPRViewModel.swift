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
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            // Defer to avoid "publishing during view update" warning:
            // @Published willChange fires synchronously inside the SwiftUI binding
            // setter; posting a second change there is undefined behaviour.
            Task { @MainActor [weak self] in
                self?.selectedPR = nil
            }
        }
    }
    @Published var selectedTab: PRTab = .open

    var repositoryPath: String = ""
    var repositoryName: String = ""

    private let pullRequestService: any PullRequestFetching
    private var loadTask: Task<Void, Never>?

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
        loadTask?.cancel()
        isLoading = true
        loadFailed = false
        errorMessage = nil
        defer { isLoading = false }
        if let prs = await pullRequestService.fetchPullRequestList(repositoryPath: repositoryPath) {
            guard !Task.isCancelled else { return }
            allPRs = prs
        } else {
            guard !Task.isCancelled else { return }
            loadFailed = true
            allPRs = []
        }
    }

    func retry() {
        loadTask?.cancel()
        loadTask = Task { await loadPRs() }
    }
}

// MARK: - Date Relative Time

extension Date {
    var relativeTimeString: String {
        let seconds = Int(-timeIntervalSinceNow)
        guard seconds >= 0 else { return "just now" }
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        return "\(days / 30)M ago"
    }
}
