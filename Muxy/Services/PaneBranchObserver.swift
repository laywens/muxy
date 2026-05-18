import Foundation

@MainActor
@Observable
final class PaneBranchObserver {
    typealias BranchResolver = @Sendable (String) async -> String?

    private(set) var branch: String?

    @ObservationIgnored private var repoPath: String?
    @ObservationIgnored private var subscriberID: UUID?
    @ObservationIgnored private let service: RepoBranchService

    init(service: RepoBranchService = .shared) {
        self.service = service
    }

    convenience init(
        refreshInterval: TimeInterval = 5,
        resolver: @escaping BranchResolver = PaneBranchObserver.defaultResolver
    ) {
        self.init(service: RepoBranchService(pollInterval: refreshInterval, resolver: resolver))
    }

    func update(repoPath path: String?, refresh: Bool = true) {
        guard repoPath != path || subscriberID == nil else { return }
        detach()
        repoPath = path
        guard let path else {
            branch = nil
            return
        }
        branch = service.currentBranch(for: path)
        guard refresh else { return }
        attach(path)
    }

    func start() {
        guard let path = repoPath, subscriberID == nil else { return }
        attach(path)
    }

    func stop() {
        detach()
    }

    func refresh() {
        guard let path = repoPath else { return }
        service.refresh(path: path)
    }

    private func attach(_ path: String) {
        let id = UUID()
        subscriberID = id
        service.subscribe(path: path, id: id) { [weak self] resolved in
            guard let self else { return }
            if self.branch != resolved {
                self.branch = resolved
            }
        }
        branch = service.currentBranch(for: path)
    }

    private func detach() {
        guard let path = repoPath, let id = subscriberID else { return }
        service.unsubscribe(path: path, id: id)
        subscriberID = nil
    }

    static let defaultResolver: BranchResolver = RepoBranchService.defaultResolver
}
