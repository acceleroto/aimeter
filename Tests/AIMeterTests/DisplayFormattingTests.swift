import XCTest
@testable import AIMeter

final class DisplayFormattingTests: XCTestCase {
    func testCompactPercentUsesOneDecimalForFractionalValues() {
        XCTAssertEqual(DisplayFormatting.compactPercent(5.6), "5.6%")
        XCTAssertEqual(DisplayFormatting.compactPercent(7.8), "7.8%")
    }

    func testCompactPercentUsesWholeNumberForNearIntegerValues() {
        XCTAssertEqual(DisplayFormatting.compactPercent(6), "6%")
        XCTAssertEqual(DisplayFormatting.compactPercent(8), "8%")
    }

    func testCursorAutoAPISuffixJoinsCompactPercents() {
        XCTAssertEqual(DisplayFormatting.cursorAutoAPISuffix(auto: 5.6, api: 7.8), "5.6%/7.8%")
        XCTAssertEqual(DisplayFormatting.cursorAutoAPISuffix(auto: 6, api: 8), "6%/8%")
    }
}
