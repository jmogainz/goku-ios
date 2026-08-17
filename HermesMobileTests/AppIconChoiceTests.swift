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
}
