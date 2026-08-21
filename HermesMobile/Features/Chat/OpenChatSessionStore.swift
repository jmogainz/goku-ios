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

@MainActor
final class SessionEventStreamCoordinator {
    private let streamClient: SSEStreamingClient
    private let server: URL
    private let sessionID: String
    private let profile: String?
    private let cursorStore: SessionEventCursorStore
    private var generation = 0
    private var reconnectTask: Task<Void, Never>?
    private var lastAcceptedEventID: String?
    private var seenEventIDs: Set<String>
    private var seenEventOrder: [String]
    private var streamHighWaterMarks: [String: Int]

    var onSnapshot: (@MainActor (SessionSummary) -> Bool)?
    var onEvent: (@MainActor (SSEEvent) -> Void)?

    init(
        server: URL,
        sessionID: String,
        profile: String?,
        streamClient: SSEStreamingClient,
        userDefaults: UserDefaults = .standard
    ) {
        self.server = server
        self.sessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profile = profile
        self.streamClient = streamClient
        self.cursorStore = SessionEventCursorStore(defaults: userDefaults)
        let persistedSeenIDs = cursorStore.loadSeenEventIDs(
            server: server,
            profile: profile,
            sessionID: self.sessionID
        )
        self.seenEventIDs = Set(persistedSeenIDs)
        self.seenEventOrder = persistedSeenIDs
        self.streamHighWaterMarks = Self.highWaterMarks(for: persistedSeenIDs)
    }

    var persistedEventID: String? {
        cursorStore.load(server: server, profile: profile, sessionID: sessionID)
    }

    func start() {
        stop()
        guard !sessionID.isEmpty else { return }
        connect()
    }

    func stop() {
        generation &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        streamClient.stop()
    }

    private func connect() {
        guard !sessionID.isEmpty else { return }
        generation &+= 1
        let connectionGeneration = generation
        let url = Endpoint.sessionEvents(sessionID: sessionID).url(relativeTo: server)
        let resumeFrom = cursorStore.load(server: server, profile: profile, sessionID: sessionID)
        lastAcceptedEventID = resumeFrom
        if let resumeFrom {
            remember(eventID: resumeFrom, persist: false)
        }
        streamClient.start(url: url, resumeFrom: resumeFrom, onEventWithID: { [weak self] event, eventID in
            guard let self, self.generation == connectionGeneration else { return }

            if case let .sessionSnapshot(snapshot) = event {
                guard Self.normalizedID(snapshot.sessionId ?? snapshot.id) == Self.normalizedID(self.sessionID) else {
                    return
                }
                // A snapshot means the server could not honor the prior replay
                // cursor. It is a recovery boundary: discard the stale cursor and
                // all prior dedupe state before the next reconnect.
                self.lastAcceptedEventID = nil
                self.seenEventIDs.removeAll(keepingCapacity: true)
                self.seenEventOrder.removeAll(keepingCapacity: true)
                self.streamHighWaterMarks.removeAll(keepingCapacity: true)
                self.cursorStore.clear(
                    server: self.server,
                    profile: self.profile,
                    sessionID: self.sessionID
                )
                self.cursorStore.clearSeenEventIDs(
                    server: self.server,
                    profile: self.profile,
                    sessionID: self.sessionID
                )
                _ = self.onSnapshot?(snapshot)
            } else {
                if let eventID = Self.normalizedEventID(eventID) {
                    guard self.accepts(eventID: eventID) else { return }
                    self.lastAcceptedEventID = eventID
                    self.remember(eventID: eventID, persist: true)
                    self.cursorStore.save(
                        eventID: eventID,
                        server: self.server,
                        profile: self.profile,
                        sessionID: self.sessionID
                    )
                }
                self.onEvent?(event)
                if Self.requiresReconnect(for: event) {
                    self.scheduleReconnect(connectionGeneration: connectionGeneration)
                }
            }
        })
    }

    private func scheduleReconnect(connectionGeneration: Int) {
        guard reconnectTask == nil, generation == connectionGeneration else { return }
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled, self.generation == connectionGeneration else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    private func accepts(eventID: String) -> Bool {
        guard !seenEventIDs.contains(eventID) else { return false }
        guard let (streamID, sequence) = Self.streamSequence(from: eventID) else { return true }
        if let highWater = streamHighWaterMarks[streamID], sequence <= highWater {
            return false
        }
        return true
    }

    private func remember(eventID: String, persist: Bool) {
        guard !seenEventIDs.contains(eventID) else { return }
        seenEventIDs.insert(eventID)
        seenEventOrder.append(eventID)
        while seenEventOrder.count > 256 {
            let removed = seenEventOrder.removeFirst()
            seenEventIDs.remove(removed)
        }
        if let (streamID, sequence) = Self.streamSequence(from: eventID) {
            streamHighWaterMarks[streamID] = max(streamHighWaterMarks[streamID] ?? sequence, sequence)
        }
        if persist {
            cursorStore.saveSeenEventIDs(
                seenEventOrder,
                server: server,
                profile: profile,
                sessionID: sessionID
            )
        }
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func streamSequence(from eventID: String) -> (String, Int)? {
        let parts = eventID.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let sequence = Int(parts[1]) else { return nil }
        return (String(parts[0]), sequence)
    }

    private static func highWaterMarks(for eventIDs: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for eventID in eventIDs {
            guard let (streamID, sequence) = streamSequence(from: eventID) else { continue }
            result[streamID] = max(result[streamID] ?? sequence, sequence)
        }
        return result
    }

    private static func requiresReconnect(for event: SSEEvent) -> Bool {
        switch event {
        case .done, .streamEnd, .cancelled, .error, .lostWorkerBookkeeping, .transportError:
            return true
        default:
            return false
        }
    }

    private static func normalizedEventID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SessionEventCursorStore {
    private let defaults: UserDefaults
    private let keyPrefix = "goku.session-events.cursor.v1"
    private let seenKeyPrefix = "goku.session-events.seen.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(server: URL, profile: String?, sessionID: String) -> String? {
        guard let value = defaults.string(forKey: key(server: server, profile: profile, sessionID: sessionID)) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func save(eventID: String, server: URL, profile: String?, sessionID: String) {
        let trimmed = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: key(server: server, profile: profile, sessionID: sessionID))
    }

    func clear(server: URL, profile: String?, sessionID: String) {
        defaults.removeObject(forKey: key(server: server, profile: profile, sessionID: sessionID))
    }

    func loadSeenEventIDs(server: URL, profile: String?, sessionID: String) -> [String] {
        guard let values = defaults.array(forKey: seenKey(server: server, profile: profile, sessionID: sessionID)) as? [String] else {
            return []
        }
        return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.suffix(256)
    }

    func saveSeenEventIDs(_ eventIDs: [String], server: URL, profile: String?, sessionID: String) {
        defaults.set(Array(eventIDs.suffix(256)), forKey: seenKey(server: server, profile: profile, sessionID: sessionID))
    }

    func clearSeenEventIDs(server: URL, profile: String?, sessionID: String) {
        defaults.removeObject(forKey: seenKey(server: server, profile: profile, sessionID: sessionID))
    }

    private func seenKey(server: URL, profile: String?, sessionID: String) -> String {
        let serverKey = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let profileKey = profile?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "default"
        let sessionKey = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(seenKeyPrefix).\(serverKey).\(profileKey).\(sessionKey)"
    }

    private func key(server: URL, profile: String?, sessionID: String) -> String {
        let serverKey = server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let profileKey = profile?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "default"
        let sessionKey = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(keyPrefix).\(serverKey).\(profileKey).\(sessionKey)"
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
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
