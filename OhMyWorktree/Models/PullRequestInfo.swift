import Foundation

enum PullRequestState: String, Sendable, Equatable {
    case open = "OPEN"
    case merged = "MERGED"
    case closed = "CLOSED"
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

    init(
        number: Int,
        url: URL,
        branch: String,
        state: PullRequestState,
        title: String = "",
        author: String = "",
        updatedAt: Date? = nil,
        isDraft: Bool = false
    ) {
        self.number = number
        self.url = url
        self.branch = branch
        self.state = state
        self.title = title
        self.author = author
        self.updatedAt = updatedAt
        self.isDraft = isDraft
    }
}
