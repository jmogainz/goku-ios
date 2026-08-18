import Foundation
import Observation

@MainActor
@Observable
final class OpenChatSessionStore {
    static let shared = OpenChatSessionStore()

    private var viewModels: [OpenChatSessionKey: ChatViewModel] = [:]
    private(set) var liveOwnershipGeneration = 0

    private init() {}

    func viewModel(
        session: SessionSummary,
        server: URL,
        showsLiveActivityResponseExcerpts: Bool = false
    ) -> ChatViewModel {
        let key = OpenChatSessionKey(server: server, sessionID: Self.normalizedSessionID(session))
        if let existing = viewModels[key] {
            existing.markReusedFromOpenSessionStore()
            return existing
        }

        let created = ChatViewModel(
            session: session,
            server: server,
            showsLiveActivityResponseExcerpts: showsLiveActivityResponseExcerpts
        )
        viewModels[key] = created
        return created
    }

    @discardableResult
    func adoptedViewModel(
        session: SessionSummary,
        server: URL,
        creating viewModel: ChatViewModel
    ) -> ChatViewModel {
        let key = OpenChatSessionKey(server: server, sessionID: Self.normalizedSessionID(session))
        viewModels[key] = viewModel
        noteStreamingStateChanged()
        return viewModel
    }

    func liveSessionIDs(for server: URL) -> Set<String> {
        _ = liveOwnershipGeneration
        let serverKey = OpenChatSessionKey.normalizedServer(server)
        return Set(
            viewModels.compactMap { key, viewModel in
                guard key.server == serverKey, viewModel.activeStreamID != nil else { return nil }
                return key.sessionID
            }
        )
    }

    var allLiveSessionIDs: Set<String> {
        _ = liveOwnershipGeneration
        return Set(
            viewModels.compactMap { key, viewModel in
                guard viewModel.activeStreamID != nil else { return nil }
                return key.sessionID
            }
        )
    }

    func liveStreamIDs(for server: URL) -> [String] {
        _ = liveOwnershipGeneration
        let serverKey = OpenChatSessionKey.normalizedServer(server)
        return viewModels
            .compactMap { key, viewModel in
                guard key.server == serverKey else { return nil }
                return viewModel.activeStreamID?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func noteStreamingStateChanged() {
        liveOwnershipGeneration &+= 1
    }

    func resetForTesting() {
        viewModels.removeAll()
        liveOwnershipGeneration = 0
    }

    private static func normalizedSessionID(_ session: SessionSummary) -> String {
        let raw = session.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty {
            return raw
        }
        return session.id
    }
}

private struct OpenChatSessionKey: Hashable {
    let server: String
    let sessionID: String

    init(server: URL, sessionID: String) {
        self.server = Self.normalizedServer(server)
        self.sessionID = sessionID
    }

    static func normalizedServer(_ server: URL) -> String {
        server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum ChatNavigationLifecyclePolicy {
    static var shouldKeepLiveStreamOnDisappear: Bool { true }
}

@MainActor
enum ChatNavigationLifecycle {
    static func applyViewDisappear(to viewModel: ChatViewModel) {
        viewModel.stopListening()
        guard ChatNavigationLifecyclePolicy.shouldKeepLiveStreamOnDisappear else {
            viewModel.cancelStreamReconnectRetry()
            viewModel.suspendStreamForNavigation()
            viewModel.cleanupPollingTasks()
            return
        }
        viewModel.ensureOwnedStreamStatusWatch()
    }
}
