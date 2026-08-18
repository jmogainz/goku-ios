import XCTest
@testable import HermesMobile

@MainActor
final class OpenChatSessionStoreTests: XCTestCase {
    override func tearDown() {
        OpenChatSessionStore.shared.resetForTesting()
        ChatViewModel.resetActiveStreamSnapshotsForTesting()
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testStoreReusesTheSameViewModelForTheSameServerAndSession() throws {
        let first = try makeViewModel(sessionID: "session-abc")
        let reused = OpenChatSessionStore.shared.adoptedViewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: try XCTUnwrap(URL(string: "https://example.test")),
            creating: first
        )
        let second = OpenChatSessionStore.shared.viewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: try XCTUnwrap(URL(string: "https://example.test"))
        )

        XCTAssertTrue(reused === first)
        XCTAssertTrue(second === first)
        XCTAssertTrue(second.wasReusedFromOpenSessionStore)
    }

    @MainActor
    func testStoreKeepsDistinctViewModelsForDifferentSessions() throws {
        let alpha = try makeViewModel(sessionID: "session-alpha")
        let beta = try makeViewModel(sessionID: "session-beta")
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        _ = OpenChatSessionStore.shared.adoptedViewModel(
            session: SessionSummary(sessionId: "session-alpha"),
            server: server,
            creating: alpha
        )
        _ = OpenChatSessionStore.shared.adoptedViewModel(
            session: SessionSummary(sessionId: "session-beta"),
            server: server,
            creating: beta
        )

        XCTAssertFalse(alpha === beta)
        XCTAssertEqual(
            OpenChatSessionStore.shared.viewModel(
                session: SessionSummary(sessionId: "session-alpha"),
                server: server
            ) === alpha,
            true
        )
    }

    @MainActor
    func testLeaveDoesNotSuspendALiveRunAndReopenDoesNotNeedSessionFetch() async throws {
        let streamClient = SpySSEStreamingClient()
        var sessionFetchCount = 0
        let viewModel = try makeViewModel(sessionID: "session-abc", streamClient: streamClient) { request in
            switch request.url?.path {
            case "/api/chat/start":
                return apiTestJSONResponse("""
                {
                  "session_id": "session-abc",
                  "stream_id": "stream-123"
                }
                """, for: request)
            case "/api/session":
                sessionFetchCount += 1
                XCTFail("Warm reopen must not wait on /api/session to know the run is live.")
                return apiTestJSONResponse("{}", for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        _ = OpenChatSessionStore.shared.adoptedViewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: server,
            creating: viewModel
        )

        let didStart = await viewModel.sendMessage("Keep working")
        XCTAssertTrue(didStart)
        streamClient.emit(.token("Partial live answer."), lastEventID: "session-abc:4")
        streamClient.emit(
            .toolStarted(ToolStreamEvent(
                eventType: "tool.started",
                name: "search_files",
                preview: "searching",
                args: nil,
                duration: nil,
                isError: nil,
                stableID: "tool-1"
            )),
            lastEventID: "session-abc:5"
        )
        viewModel.flushPendingStreamingContent()

        XCTAssertEqual(viewModel.activeStreamID, "stream-123")
        XCTAssertFalse(viewModel.liveToolCalls.isEmpty)

        ChatNavigationLifecycle.applyViewDisappear(to: viewModel)
        XCTAssertEqual(streamClient.stopCount, 0)
        XCTAssertEqual(viewModel.activeStreamID, "stream-123")
        XCTAssertFalse(viewModel.isActiveStreamConnectionSuspended)

        let reopened = OpenChatSessionStore.shared.viewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: server
        )
        XCTAssertTrue(reopened === viewModel)
        XCTAssertTrue(reopened.hasPreservedLiveRun)
        XCTAssertFalse(
            ChatInitialAppearancePolicy.shouldReloadTranscriptOnAppear(
                hasPreservedLiveRun: reopened.hasPreservedLiveRun
            )
        )
        XCTAssertEqual(reopened.activeStreamID, "stream-123")
        XCTAssertEqual(reopened.liveToolCalls.first?.id, "tool-1")
        XCTAssertEqual(sessionFetchCount, 0)
    }

    @MainActor
    func testSidebarPulseUsesLiveOwnerEvenWhenListPayloadIsIdle() async throws {
        let streamClient = SpySSEStreamingClient()
        let viewModel = try makeViewModel(sessionID: "session-abc", streamClient: streamClient) { request in
            XCTAssertEqual(request.url?.path, "/api/chat/start")
            return apiTestJSONResponse("""
            {
              "session_id": "session-abc",
              "stream_id": "stream-123"
            }
            """, for: request)
        }
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        _ = OpenChatSessionStore.shared.adoptedViewModel(
            session: SessionSummary(sessionId: "session-abc"),
            server: server,
            creating: viewModel
        )

        let didStart = await viewModel.sendMessage("Keep working")
        XCTAssertTrue(didStart)
        let idleListRow = SessionSummary(sessionId: "session-abc", isStreaming: false)
        XCTAssertTrue(
            SessionRowView.isActiveStreaming(
                idleListRow,
                liveOwnerSessionIDs: OpenChatSessionStore.shared.liveSessionIDs(for: server)
            )
        )
        XCTAssertEqual(
            OpenChatSessionStore.shared.liveStreamIDs(for: server),
            ["stream-123"]
        )
    }

    func testColdOpenAdoptsListStreamIDBeforeSessionFetch() throws {
        let viewModel = try makeViewModel(
            sessionID: "session-abc",
            activeStreamID: "stream-from-list"
        )

        XCTAssertEqual(viewModel.activeStreamID, "stream-from-list")
        XCTAssertTrue(viewModel.isActiveStreamConnectionSuspended)
        XCTAssertTrue(viewModel.hasPreservedLiveRun)
        XCTAssertFalse(viewModel.isEstablishingConnection)
    }

    func testColdOpenWithoutKnownStreamReportsEstablishingConnection() throws {
        let viewModel = try makeViewModel(sessionID: "session-abc")
        viewModel.markConversationConnectionInProgress()

        XCTAssertNil(viewModel.activeStreamID)
        XCTAssertTrue(viewModel.isEstablishingConnection)
        XCTAssertTrue(viewModel.isLoading)
    }

    func testKnownListStreamReconnectsWithoutWaitingOnSessionFetch() async throws {
        let streamClient = SpySSEStreamingClient()
        var sessionFetchCount = 0
        var statusFetchCount = 0
        let viewModel = try makeViewModel(
            sessionID: "session-abc",
            activeStreamID: "stream-from-list",
            streamClient: streamClient
        ) { request in
            switch request.url?.path {
            case "/api/chat/stream/status":
                statusFetchCount += 1
                return apiTestJSONResponse("""
                {
                  "active": true,
                  "replay_available": true
                }
                """, for: request)
            case "/api/session":
                sessionFetchCount += 1
                XCTFail("Known list stream must attach before /api/session.")
                return apiTestJSONResponse("{}", for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        await viewModel.reconnectStreamIfNeeded()

        XCTAssertEqual(statusFetchCount, 1)
        XCTAssertEqual(sessionFetchCount, 0)
        XCTAssertEqual(streamClient.startedURLs.count, 1)
        XCTAssertEqual(viewModel.activeStreamID, "stream-from-list")
        XCTAssertFalse(viewModel.isActiveStreamConnectionSuspended)
    }

    @MainActor
    func makeViewModel(
        sessionID: String,
        activeStreamID: String? = nil,
        streamClient: SSEStreamingClient? = nil,
        handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? = nil
    ) throws -> ChatViewModel {
        if let handler {
            MockURLProtocol.requestHandler = handler
        } else {
            MockURLProtocol.requestHandler = { request in
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        let client = APIClient(baseURL: server, session: urlSession)
        let resolvedStreamClient = streamClient ?? SpySSEStreamingClient()
        let viewModel = ChatViewModel(
            session: SessionSummary(sessionId: sessionID, activeStreamId: activeStreamID),
            server: server,
            client: client,
            streamClient: resolvedStreamClient,
            approvalStreamClient: SpySSEStreamingClient(),
            clarifyStreamClient: SpySSEStreamingClient(),
            listenAudioSession: SpyListenAudioSession(),
            listenRemoteControlCenter: SpyListenRemoteControlCenter()
        )
        if let spy = resolvedStreamClient as? SpySSEStreamingClient {
            spy.flushPendingStreamingContent = { [weak viewModel] in
                viewModel?.flushPendingStreamingContent()
            }
        }
        return viewModel
    }
}

private final class SpySSEStreamingClient: SSEStreamingClient {
    private(set) var startedURLs: [URL] = []
    private(set) var stopCount = 0
    private(set) var lastEventID: String?
    private var onEvent: (@MainActor (SSEEvent) -> Void)?
    var automaticallyFlushPendingStreamingContent = true
    var flushPendingStreamingContent: (() -> Void)?

    func start(url: URL, onEvent: @escaping @MainActor (SSEEvent) -> Void) {
        startedURLs.append(url)
        lastEventID = nil
        self.onEvent = onEvent
    }

    func stop() {
        stopCount += 1
    }

    @MainActor
    func emit(_ event: SSEEvent, lastEventID: String? = nil) {
        self.lastEventID = lastEventID
        onEvent?(event)
        if automaticallyFlushPendingStreamingContent {
            flushPendingStreamingContent?()
        }
    }
}

private final class SpyListenAudioSession: ListenAudioSessionControlling {
    func activate() {}
    func deactivate() {}
}

@MainActor
private final class SpyListenRemoteControlCenter: ListenRemoteControlControlling {
    func configure(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        togglePlayPause: @escaping @MainActor () -> Void,
        changePlaybackPosition: @escaping @MainActor (TimeInterval) -> Void
    ) {}

    func update(_ snapshot: ListenNowPlayingSnapshot) {}
    func clear() {}
}
