import XCTest

@testable import OhMyWorktree

// MARK: - Mock

final class MockCrashReporter: CrashReporter {
    private(set) var startedWithDSN: String?
    private(set) var capturedErrors: [(error: Error, context: [String: Any])] = []
    private(set) var breadcrumbs: [(message: String, category: String)] = []

    func start(dsn: String) {
        startedWithDSN = dsn
    }

    func capture(error: Error, context: [String: Any]) {
        capturedErrors.append((error: error, context: context))
    }

    func addBreadcrumb(message: String, category: String) {
        breadcrumbs.append((message: message, category: category))
    }
}

// MARK: - CrashReporter Protocol Tests

final class CrashReporterTests: XCTestCase {

    private var sut: MockCrashReporter!

    override func setUp() {
        super.setUp()
        sut = MockCrashReporter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testStartSetsCorrectDSN() {
        let dsn = "https://examplePublicKey@o0.ingest.sentry.io/0"
        sut.start(dsn: dsn)
        XCTAssertEqual(sut.startedWithDSN, dsn)
    }

    func testStartCanBeCalledMultipleTimes() {
        sut.start(dsn: "dsn1")
        sut.start(dsn: "dsn2")
        XCTAssertEqual(sut.startedWithDSN, "dsn2")
    }

    // MARK: - Error Capture

    func testCaptureErrorRecordsError() {
        let error = OhMyWorktreeError.repositoryNotFound
        sut.capture(error: error, context: ["operation": "load"])

        XCTAssertEqual(sut.capturedErrors.count, 1)
        XCTAssertEqual(
            sut.capturedErrors.first?.error.localizedDescription,
            error.localizedDescription
        )
    }

    func testCaptureErrorPreservesContext() {
        let error = OhMyWorktreeError.invalidPath(path: "/tmp/test")
        let context: [String: Any] = ["file": "repositories.json", "operation": "save"]
        sut.capture(error: error, context: context)

        XCTAssertEqual(sut.capturedErrors.first?.context["file"] as? String, "repositories.json")
        XCTAssertEqual(sut.capturedErrors.first?.context["operation"] as? String, "save")
    }

    func testCaptureMultipleErrors() {
        sut.capture(error: OhMyWorktreeError.repositoryNotFound, context: [:])
        sut.capture(error: OhMyWorktreeError.gitNotInstalled, context: [:])
        sut.capture(
            error: OhMyWorktreeError.permissionDenied(path: "/test"),
            context: ["severity": "high"]
        )

        XCTAssertEqual(sut.capturedErrors.count, 3)
    }

    // MARK: - Breadcrumbs

    func testAddBreadcrumbRecordsMessage() {
        sut.addBreadcrumb(message: "Loading repositories", category: "persistence")

        XCTAssertEqual(sut.breadcrumbs.count, 1)
        XCTAssertEqual(sut.breadcrumbs.first?.message, "Loading repositories")
        XCTAssertEqual(sut.breadcrumbs.first?.category, "persistence")
    }

    func testAddMultipleBreadcrumbs() {
        sut.addBreadcrumb(message: "Started save", category: "persistence")
        sut.addBreadcrumb(message: "Encoded data", category: "persistence")
        sut.addBreadcrumb(message: "Wrote to disk", category: "io")

        XCTAssertEqual(sut.breadcrumbs.count, 3)
        XCTAssertEqual(sut.breadcrumbs[0].message, "Started save")
        XCTAssertEqual(sut.breadcrumbs[1].message, "Encoded data")
        XCTAssertEqual(sut.breadcrumbs[2].category, "io")
    }

    // MARK: - CrashReporterConfiguration

    func testConfigurationDefaultDSN() {
        let config = CrashReporterConfiguration.default
        XCTAssertFalse(config.dsn.isEmpty, "Default DSN should not be empty")
    }

    func testConfigurationCustomDSN() {
        let customDSN = "https://custom@sentry.io/123"
        let config = CrashReporterConfiguration(dsn: customDSN)
        XCTAssertEqual(config.dsn, customDSN)
    }

    func testConfigurationEnvironmentVariable() {
        let envDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"]
        let config = CrashReporterConfiguration.fromEnvironment()
        if let envDSN {
            XCTAssertEqual(config.dsn, envDSN)
        } else {
            XCTAssertEqual(config.dsn, CrashReporterConfiguration.default.dsn)
        }
    }

    // MARK: - SentryCrashReporter Initialization

    func testSentryCrashReporterConformsToProtocol() {
        let reporter: CrashReporter = SentryCrashReporter()
        // Verify type conformance — the compiler enforces this, but it's
        // good to have an explicit runtime check.
        XCTAssertTrue(reporter is SentryCrashReporter)
    }

    // MARK: - Protocol Conformance as Dependency

    func testMockCanBeUsedAsDependency() {
        let mock = MockCrashReporter()
        let reporter: CrashReporter = mock

        reporter.start(dsn: "test-dsn")
        reporter.addBreadcrumb(message: "test", category: "test")
        reporter.capture(error: OhMyWorktreeError.gitNotInstalled, context: [:])

        XCTAssertEqual(mock.startedWithDSN, "test-dsn")
        XCTAssertEqual(mock.breadcrumbs.count, 1)
        XCTAssertEqual(mock.capturedErrors.count, 1)
    }

    // MARK: - NoOpCrashReporter

    func testNoOpReporterDoesNotCrash() {
        let reporter = NoOpCrashReporter()
        reporter.start(dsn: "anything")
        reporter.addBreadcrumb(message: "ignored", category: "test")
        reporter.capture(error: OhMyWorktreeError.gitNotInstalled, context: ["key": "value"])
        // If we get here without crashing, the test passes
    }

    // MARK: - CrashReporterProvider

    func testProviderReturnsReporter() {
        let reporter = CrashReporterProvider.shared
        XCTAssertTrue(reporter is SentryCrashReporter)
    }

    func testProviderCanBeOverridden() {
        let original = CrashReporterProvider.shared
        let mock = MockCrashReporter()
        CrashReporterProvider.shared = mock

        XCTAssertTrue(CrashReporterProvider.shared is MockCrashReporter)

        // Restore original
        CrashReporterProvider.shared = original
    }
}
