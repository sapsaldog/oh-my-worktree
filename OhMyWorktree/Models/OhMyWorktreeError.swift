import Foundation

enum OhMyWorktreeError: LocalizedError, Sendable {
    case gitNotInstalled
    case invalidGitRepository(path: String)
    case worktreeAlreadyExists(branch: String)
    case worktreeNotFound(path: String)
    case externalToolNotFound(tool: String)
    case commandExecutionFailed(command: String, stderr: String)
    case permissionDenied(path: String)
    case repositoryNotFound
    case invalidPath(path: String)

    var errorDescription: String? {
        switch self {
        case .gitNotInstalled:
            return "Git is not installed."
        case .invalidGitRepository(let path):
            return "Invalid Git repository: \(path)"
        case .worktreeAlreadyExists(let branch):
            return "Worktree already exists: \(branch)"
        case .worktreeNotFound(let path):
            return "Worktree not found: \(path)"
        case .externalToolNotFound(let tool):
            return "\(tool) not found."
        case .commandExecutionFailed(let command, let stderr):
            return "Command execution failed: \(command)\n\(stderr)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .repositoryNotFound:
            return "Repository not found."
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .gitNotInstalled:
            return "Install Git using Homebrew: brew install git"
        case .externalToolNotFound(let tool):
            return "Install \(tool) and try again."
        default:
            return nil
        }
    }
}
