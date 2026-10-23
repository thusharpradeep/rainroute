import XCTest
@testable import RainRoute

final class SegmentRangesTests: XCTestCase {
    func testCompressesConsecutiveRanges() {
        XCTAssertEqual(SegmentRanges.format([]), "")
        XCTAssertEqual(SegmentRanges.format([1]), "1")
        XCTAssertEqual(SegmentRanges.format([2, 5, 6, 7, 9]), "2, 5–7, 9")
        XCTAssertEqual(SegmentRanges.format([8, 9, 10, 11]), "8–11")
        XCTAssertEqual(SegmentRanges.format([4, 1, 3, 2, 2]), "1–4")
        XCTAssertEqual(SegmentRanges.format([0, -2, 3]), "3")
    }
}
