import Foundation
import Testing

@testable import OhMyWorktree

@MainActor
struct RepositoryListViewModelNavigationTests {

    private static let testDefaults = UserDefaults(suiteName: "RepositoryListViewModelNavigationTests")!

    private func makeViewModel(repoCount: Int) -> RepositoryListViewModel {
        Self.testDefaults.removePersistentDomain(forName: "RepositoryListViewModelNavigationTests")
        let vm = RepositoryListViewModel(userDefaults: Self.testDefaults)
        vm.repositories = (0..<repoCount).map {
            Repository(name: "repo-\($0)", path: "/tmp/repo-\($0)")
        }
        return vm
    }

    // MARK: - selectNextRepository

    @Test func selectNextRepository_noSelection_selectsFirst() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        await vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectNextRepository_firstSelected_selectsSecond() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        await vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-1")
    }

    @Test func selectNextRepository_lastSelected_staysOnLast() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[2]

        await vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-2")
    }

    @Test func selectNextRepository_emptyList_doesNothing() async {
        let vm = makeViewModel(repoCount: 0)

        await vm.selectNextRepository()

        #expect(vm.selectedRepository == nil)
    }

    // MARK: - selectPreviousRepository

    @Test func selectPreviousRepository_noSelection_selectsFirst() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        await vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_secondSelected_selectsFirst() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[1]

        await vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_firstSelected_staysOnFirst() async {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        await vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_emptyList_doesNothing() async {
        let vm = makeViewModel(repoCount: 0)

        await vm.selectPreviousRepository()

        #expect(vm.selectedRepository == nil)
    }
}
