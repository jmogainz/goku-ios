import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AppIconChoice: String, CaseIterable, Identifiable {
    case system

    var id: String { rawValue }

    var title: String {
        String(localized: "Goku")
    }

    var subtitle: String {
        "Canonical Goku icon"
    }

    var alternateIconName: String? { nil }

    var previewImageName: String? { "GokuAppIcon" }

    static func resolved(from alternateIconName: String?) -> AppIconChoice {
        .system
    }

    #if canImport(UIKit)
    @MainActor
    static var current: AppIconChoice { .system }
    #endif
}
