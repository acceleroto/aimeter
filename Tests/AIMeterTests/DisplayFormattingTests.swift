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
        XCTAssertEqual(DisplayFormatting.openAICodexSuffix(weekly: 14.6), "14.6%")
    }

    func testMenuBarPercentRoundsToNearestWholeNumber() {
        XCTAssertEqual(DisplayFormatting.menuBarPercent(5.6), "6%")
        XCTAssertEqual(DisplayFormatting.menuBarPercent(7.4), "7%")
        XCTAssertEqual(DisplayFormatting.menuBarPercent(8.5), "9%")
    }

    func testMenuBarSuffixesUseRoundedPercents() {
        XCTAssertEqual(DisplayFormatting.menuBarCursorAutoAPISuffix(auto: 5.6, api: 7.8), "6%/8%")
        XCTAssertEqual(DisplayFormatting.menuBarOpenAICodexSuffix(weekly: 0.4), "0%")
        XCTAssertEqual(DisplayFormatting.menuBarOpenAICodexSuffix(weekly: 14.6), "15%")
    }

    func testDisplayPercentCountsDownWhenRequested() {
        XCTAssertEqual(DisplayFormatting.displayPercent(used: 17.4, countDown: false), "17.4%")
        XCTAssertEqual(DisplayFormatting.displayPercent(used: 17.4, countDown: true), "82.6%")
        XCTAssertEqual(DisplayFormatting.displayPercentValue(used: 100, countDown: true), 0)
        XCTAssertEqual(DisplayFormatting.menuBarCursorAutoAPISuffix(auto: 9, api: 100, countDown: true), "91%/0%")
        XCTAssertEqual(DisplayFormatting.menuBarOpenAICodexSuffix(weekly: 21, countDown: true), "79%")
    }

    func testResetDisplayNormalizesRelativeBillingCopy() {
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Usage resets in 12 days"), "Resets in 12 days")
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Renews in 5 days"), "Resets in 5 days")
        XCTAssertEqual(DisplayFormatting.resetDisplay(from: "Next billing date in 17 days"), "Resets in 17 days")
    }

    func testResetDateDisplayParsesMicrosecondISO8601Timestamp() {
        let display = DisplayFormatting.resetDateDisplay(
            from: "2026-10-01T08:00:32.340430+00:00"
        )

        XCTAssertTrue(display?.hasPrefix("Resets ") == true)
        XCTAssertFalse(display?.contains("T") == true)
        XCTAssertFalse(display?.contains("+00:00") == true)
    }

    func testResetInDaysUsesCalendarDayBoundaries() {
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 23, minute: 30))!
        let reset = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        XCTAssertEqual(DisplayFormatting.resetInDays(until: reset, from: reference), "Resets in 12 days")
    }

    func testRelativeResetLineFromAbsoluteDate() {
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 1, minute: 30))!
        XCTAssertEqual(
            DisplayFormatting.relativeResetLine(from: "Resets Sep 19, 2026 3:47 AM", referenceDate: reference),
            "Resets in 4 days"
        )
    }

    func testRelativeResetLineFromWeekday() {
        // Tuesday Sep 15, 2026 → next Sunday is Sep 20 (5 days).
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))!
        XCTAssertEqual(
            DisplayFormatting.relativeResetLine(from: "Resets Sunday 11:30 AM", referenceDate: reference),
            "Resets in 5 days"
        )
        XCTAssertEqual(
            DisplayFormatting.relativeResetLine(from: "Resets Sun 11:30 AM", referenceDate: reference),
            "Resets in 5 days"
        )
    }

    func testRelativeResetLineOmitsAlreadyRelativeAndShortIntervals() {
        let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        XCTAssertNil(DisplayFormatting.relativeResetLine(from: "Resets in 12 days", referenceDate: reference))
        XCTAssertNil(DisplayFormatting.relativeResetLine(from: "Resets in 2 hours", referenceDate: reference))
        XCTAssertNil(DisplayFormatting.relativeResetLine(from: "Resets in 53 min", referenceDate: reference))
    }

    func testLastSyncTimestampNeverUsesFutureTense() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let slightlyFuture = Date(timeIntervalSince1970: 1_002)

        XCTAssertEqual(
            DisplayFormatting.lastSyncTimestamp(slightlyFuture, relativeTo: reference),
            "Just now"
        )
    }

    func testRelativeTimestampUsesProvidedReferenceDate() {
        let fetchedAt = Date(timeIntervalSince1970: 0)
        let reference = Date(timeIntervalSince1970: 600)

        let formatted = DisplayFormatting.relativeTimestamp(fetchedAt, relativeTo: reference)

        XCTAssertTrue(formatted.contains("10"))
    }
}
