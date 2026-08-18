import XCTest
@testable import HermesMobile

final class AppIconChoiceTests: XCTestCase {
    func testGokuUsesOneCanonicalIcon() {
        XCTAssertEqual(AppIconChoice.allCases, [.system])
        XCTAssertEqual(AppIconChoice.system.title, "Goku")
        XCTAssertEqual(AppIconChoice.system.subtitle, "Canonical Goku icon")
        XCTAssertNil(AppIconChoice.system.alternateIconName)
        XCTAssertEqual(AppIconChoice.system.previewImageName, "GokuAppIcon")
        XCTAssertEqual(AppIconChoice.resolved(from: nil), .system)
        XCTAssertEqual(AppIconChoice.resolved(from: "LegacyAlternateIcon"), .system)
    }

    func testSidebarBrandUsesCanonicalPortraitMedallion() {
        XCTAssertEqual(GokuHeaderLogo.portraitImageName, "GokuAppIcon")
        XCTAssertEqual(GokuHeaderLogo.productName, "Goku")
        XCTAssertEqual(GokuHeaderLogo.productDescriptor, "MOBILE AGENT")
        XCTAssertEqual(GokuHeaderLogo.accessibilityLabelText, "Goku Mobile Agent")
    }

    func testPrivacyPolicyUsesGokuControlledPublicURL() {
        XCTAssertEqual(
            AppConfig.privacyPolicyURL.absoluteString,
            "https://github.com/jmogainz/goku-ios/blob/master/PRIVACY.md"
        )
    }

    func testSupportUsesGokuRepositoryIssues() {
        XCTAssertEqual(
            AppConfig.supportURL.absoluteString,
            "https://github.com/jmogainz/goku-ios/issues"
        )
    }

    func testForegroundRefreshTasksAreSceneOwnedAndCancelled() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("HermesMobile/Features/Chat/ChatView.swift"),
            encoding: .utf8
        )
        let sessionListSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("HermesMobile/Features/SessionList/SessionListView.swift"),
            encoding: .utf8
        )

        for source in [chatSource, sessionListSource] {
            XCTAssertTrue(source.contains("@State private var foregroundRefreshTask: Task<Void, Never>?"))
            XCTAssertTrue(source.contains("foregroundRefreshTask?.cancel()"))
            XCTAssertTrue(source.contains("scenePhase == .active"))
        }
        XCTAssertTrue(chatSource.contains(".onAppear {\n                foregroundRefreshTask?.cancel()\n                viewModel.cancelOwnedStreamStatusWatch()\n                foregroundRefreshTask = Task { @MainActor in\n                    guard !Task.isCancelled, scenePhase == .active else { return }\n                    await viewModel.reconnectStreamIfNeeded(modelContext: modelContext)"))
        XCTAssertTrue(chatSource.contains("ChatNavigationLifecycle.applyViewDisappear(to: viewModel)"))
        XCTAssertFalse(chatSource.contains("viewModel.suspendStreamForNavigation()"))
        XCTAssertTrue(chatSource.contains("ChatInitialAppearancePolicy.shouldReloadTranscriptOnAppear"))
    }
}
