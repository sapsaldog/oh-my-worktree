import XCTest

@testable import OhMyWorktree

@MainActor
final class RepositoryListViewModelNavigationTests: XCTestCase {

    private func makeViewModel(repoCount: Int) -> RepositoryListViewModel {
        let vm = RepositoryListViewModel()
        vm.repositories = (0..<repoCount).map {
            Repository(name: "repo-\($0)", path: "/tmp/repo-\($0)")
        }
        return vm
    }

    // MARK: - selectNextRepository

    func testSelectNextRepository_noSelection_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        vm.selectNextRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-0")
    }

    func testSelectNextRepository_firstSelected_selectsSecond() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        vm.selectNextRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-1")
    }

    func testSelectNextRepository_lastSelected_staysOnLast() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[2]

        vm.selectNextRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-2")
    }

    func testSelectNextRepository_emptyList_doesNothing() {
        let vm = makeViewModel(repoCount: 0)

        vm.selectNextRepository()

        XCTAssertNil(vm.selectedRepository)
    }

    // MARK: - selectPreviousRepository

    func testSelectPreviousRepository_noSelection_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        vm.selectPreviousRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-0")
    }

    func testSelectPreviousRepository_secondSelected_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[1]

        vm.selectPreviousRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-0")
    }

    func testSelectPreviousRepository_firstSelected_staysOnFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        vm.selectPreviousRepository()

        XCTAssertEqual(vm.selectedRepository?.name, "repo-0")
    }

    func testSelectPreviousRepository_emptyList_doesNothing() {
        let vm = makeViewModel(repoCount: 0)

        vm.selectPreviousRepository()

        XCTAssertNil(vm.selectedRepository)
    }
}
