import Foundation
import XCTest
@testable import RainRoute

final class AppSettingsTests: XCTestCase {
    func testSegmentCountDefaultsToTwelveAndPersistsClampedValues() {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.segmentCount, 12)

        settings.setSegmentCount(60)
        XCTAssertEqual(settings.segmentCount, 60)

        settings.setSegmentCount(1)
        XCTAssertEqual(settings.segmentCount, 3)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.segmentCount, 3)

        settings.setSegmentCount(999)
        XCTAssertEqual(settings.segmentCount, 60)
    }
}
