import Foundation

enum OhMyWorktreeError: LocalizedError {
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
            return "Git이 설치되지 않았습니다."
        case .invalidGitRepository(let path):
            return "유효하지 않은 Git 저장소: \(path)"
        case .worktreeAlreadyExists(let branch):
            return "Worktree가 이미 존재합니다: \(branch)"
        case .worktreeNotFound(let path):
            return "Worktree를 찾을 수 없습니다: \(path)"
        case .externalToolNotFound(let tool):
            return "\(tool)을(를) 찾을 수 없습니다."
        case .commandExecutionFailed(let command, let stderr):
            return "명령어 실행 실패: \(command)\n\(stderr)"
        case .permissionDenied(let path):
            return "접근 권한이 없습니다: \(path)"
        case .repositoryNotFound:
            return "Repository를 찾을 수 없습니다."
        case .invalidPath(let path):
            return "유효하지 않은 경로입니다: \(path)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .gitNotInstalled:
            return "Homebrew로 Git을 설치하세요: brew install git"
        case .externalToolNotFound(let tool):
            return "\(tool)을(를) 설치하고 다시 시도하세요."
        default:
            return nil
        }
    }
}
