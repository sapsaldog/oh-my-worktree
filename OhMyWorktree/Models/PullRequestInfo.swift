import Foundation

enum PullRequestState: String, Sendable, Equatable {
    case open = "OPEN"
    case merged = "MERGED"
    case closed = "CLOSED"
}

struct PullRequestInfo: Sendable {
    let number: Int
    let url: URL
    let branch: String
    let state: PullRequestState
}
