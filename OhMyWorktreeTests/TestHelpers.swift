import Foundation

/// Polls a condition at short intervals until it becomes `true` or the timeout expires.
/// Useful for waiting on async side-effects in tests (e.g. observation-triggered reloads).
@MainActor
func pollUntil(
    timeout: Duration = .seconds(5),
    interval: Duration = .milliseconds(50),
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            struct PollTimeoutError: Error, CustomStringConvertible {
                var description: String { "pollUntil timed out" }
            }
            throw PollTimeoutError()
        }
        // swiftlint:disable:next no_arbitrary_delay
        try await Task.sleep(for: interval)
    }
}
