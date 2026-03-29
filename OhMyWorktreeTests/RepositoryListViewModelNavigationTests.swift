import Testing

@testable import OhMyWorktree

@MainActor
struct RepositoryListViewModelNavigationTests {

    private func makeViewModel(repoCount: Int) -> RepositoryListViewModel {
        let vm = RepositoryListViewModel()
        vm.repositories = (0..<repoCount).map {
            Repository(name: "repo-\($0)", path: "/tmp/repo-\($0)")
        }
        return vm
    }

    // MARK: - selectNextRepository

    @Test func selectNextRepository_noSelection_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectNextRepository_firstSelected_selectsSecond() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-1")
    }

    @Test func selectNextRepository_lastSelected_staysOnLast() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[2]

        vm.selectNextRepository()

        #expect(vm.selectedRepository?.name == "repo-2")
    }

    @Test func selectNextRepository_emptyList_doesNothing() {
        let vm = makeViewModel(repoCount: 0)

        vm.selectNextRepository()

        #expect(vm.selectedRepository == nil)
    }

    // MARK: - selectPreviousRepository

    @Test func selectPreviousRepository_noSelection_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = nil

        vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_secondSelected_selectsFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[1]

        vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_firstSelected_staysOnFirst() {
        let vm = makeViewModel(repoCount: 3)
        vm.selectedRepository = vm.repositories[0]

        vm.selectPreviousRepository()

        #expect(vm.selectedRepository?.name == "repo-0")
    }

    @Test func selectPreviousRepository_emptyList_doesNothing() {
        let vm = makeViewModel(repoCount: 0)

        vm.selectPreviousRepository()

        #expect(vm.selectedRepository == nil)
    }
}
