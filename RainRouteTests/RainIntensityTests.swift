import XCTest
@testable import RainRoute

final class RainIntensityTests: XCTestCase {
    func testBandsUsePhysicalRatesButRespectTheWetThreshold() {
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 0.19, threshold: 0.2), .dry)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 0.2, threshold: 0.2), .light)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 2.49, threshold: 0.2), .light)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 2.5, threshold: 0.2), .moderate)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 7.59, threshold: 0.2), .moderate)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 7.6, threshold: 0.2), .heavy)
        XCTAssertEqual(RainIntensity.classify(precipitationMM: 4.0, threshold: 5.0), .dry)
    }

    func testLabels() {
        XCTAssertEqual(RainIntensity.dry.label, "Dry")
        XCTAssertEqual(RainIntensity.light.label, "Light")
        XCTAssertEqual(RainIntensity.moderate.label, "Moderate")
        XCTAssertEqual(RainIntensity.heavy.label, "Heavy")
    }
}
