import Foundation

struct PullRequestInfo: Sendable {
    let number: Int
    let url: URL
    let branch: String
}
