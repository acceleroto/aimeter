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

    func testMenuBarPercentRoundsToNearestWholeNumber() {
        XCTAssertEqual(DisplayFormatting.menuBarPercent(5.6), "6%")
        XCTAssertEqual(DisplayFormatting.menuBarPercent(7.4), "7%")
        XCTAssertEqual(DisplayFormatting.menuBarPercent(8.5), "9%")
    }

    func testMenuBarSuffixesUseRoundedPercents() {
        XCTAssertEqual(DisplayFormatting.menuBarCursorAutoAPISuffix(auto: 5.6, api: 7.8), "6%/8%")
        XCTAssertEqual(DisplayFormatting.menuBarOpenAICodexSuffix(fiveHour: 2.4, weekly: 0.4), "2%/0%")
    }

    func testResetDisplayNormalizesRelativeBillingCopy() {
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Usage resets in 12 days"), "Resets in 12 days")
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Renews in 5 days"), "Resets in 5 days")
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Next billing date in 17 days"), "Resets in 17 days")
    }

    func testResetInDaysUsesCalendarDayBoundaries() {
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23, minute: 30))!
        let reset = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        XCTAssertEqual(DisplayFormatting.resetInDays(until: reset, from: reference), "Resets in 12 days")
    }
}
