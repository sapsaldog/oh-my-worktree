import Foundation

enum PullRequestState: String, Sendable, Equatable {
    case open = "OPEN"
    case merged = "MERGED"
    case closed = "CLOSED"
}

/// GitHub review decision for a PR (drives the detail card's review summary).
enum ReviewDecision: String, Sendable, Equatable {
    case approved
    case changesRequested
    case reviewRequired
    case none
}

/// Rolled-up CI check status for a PR (drives the detail card's "checks …" line).
enum CheckStatus: String, Sendable, Equatable {
    case passing
    case failing
    case pending
    case none
}

struct PullRequestInfo: Sendable, Equatable, Hashable {
    let number: Int
    let url: URL
    let branch: String
    let state: PullRequestState
    let title: String
    let author: String
    let updatedAt: Date?
    let isDraft: Bool
    let reviewDecision: ReviewDecision
    let checkStatus: CheckStatus

    init(
        number: Int,
        url: URL,
        branch: String,
        state: PullRequestState,
        title: String = "",
        author: String = "",
        updatedAt: Date? = nil,
        isDraft: Bool = false,
        reviewDecision: ReviewDecision = .none,
        checkStatus: CheckStatus = .none
    ) {
        self.number = number
        self.url = url
        self.branch = branch
        self.state = state
        self.title = title
        self.author = author
        self.updatedAt = updatedAt
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.checkStatus = checkStatus
    }
}
