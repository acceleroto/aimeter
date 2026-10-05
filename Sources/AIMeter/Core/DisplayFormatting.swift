import Foundation

enum DisplayFormatting {
    static func percent(_ value: Double) -> String {
        compactPercent(value)
    }

    /// Converts a usage-used percentage into the value shown in the UI.
    static func displayPercentValue(used usedPercent: Double, countDown: Bool) -> Double {
        let clamped = min(max(usedPercent, 0), 100)
        return countDown ? 100 - clamped : clamped
    }

    static func displayPercent(used usedPercent: Double, countDown: Bool) -> String {
        compactPercent(displayPercentValue(used: usedPercent, countDown: countDown))
    }

    static func compactPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)

        if abs(clamped.rounded() - clamped) < 0.05 {
            return "\(Int(clamped.rounded()))%"
        }

        return String(format: "%.1f%%", clamped)
    }

    static func cursorAutoAPISuffix(auto: Double, api: Double) -> String {
        "\(compactPercent(auto))/\(compactPercent(api))"
    }

    static func openAICodexSuffix(weekly: Double) -> String {
        compactPercent(weekly)
    }

    static func menuBarPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        return "\(Int(clamped.rounded()))%"
    }

    static func menuBarCursorAutoAPISuffix(auto: Double, api: Double, countDown: Bool = false) -> String {
        "\(menuBarPercent(displayPercentValue(used: auto, countDown: countDown)))/\(menuBarPercent(displayPercentValue(used: api, countDown: countDown)))"
    }

    static func menuBarOpenAICodexSuffix(weekly: Double, countDown: Bool = false) -> String {
        menuBarPercent(displayPercentValue(used: weekly, countDown: countDown))
    }

    static func menuBarClaudeUsageSuffix(
        fiveHour: Double?,
        weekly: Double?,
        countDown: Bool = false
    ) -> String {
        let fiveHourText = fiveHour.map {
            menuBarPercent(displayPercentValue(used: $0, countDown: countDown))
        } ?? "--"
        let weeklyText = weekly.map {
            menuBarPercent(displayPercentValue(used: $0, countDown: countDown))
        } ?? "--"
        return "\(fiveHourText)/\(weeklyText)"
    }

    static func resetInDays(until resetDate: Date, from referenceDate: Date = Date()) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: resetDate)
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        switch dayCount {
        case ..<0:
            return "Resets today"
        case 0:
            return "Resets today"
        case 1:
            return "Resets tomorrow"
        default:
            return "Resets in \(dayCount) days"
        }
    }

    /// Normalizes billing-cycle copy from provider pages into header-friendly reset text.
    static func resetDisplay(from text: String, referenceDate: Date = Date()) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        guard
            lowercased.contains("reset")
                || lowercased.contains("renew")
                || lowercased.contains("billing")
                || lowercased.contains("cycle")
        else {
            return nil
        }

        if let days = daysFromRelativeResetPhrase(in: trimmed) {
            return relativeResetLabel(days: days)
        }

        if containsShortIntervalReset(lower: lowercased) {
            return nil
        }

        if let resetDate = parseResetDate(from: trimmed, referenceDate: referenceDate) {
            return resetInDays(until: resetDate, from: referenceDate)
        }

        return nil
    }

    /// Formats an absolute reset timestamp in the same style used by provider reset captions.
    static func resetDateDisplay(from text: String) -> String? {
        guard let resetDate = parseResetDate(from: text) else {
            return nil
        }

        return resetDateDisplay(from: resetDate)
    }

    /// Formats an absolute reset date in the same style used by provider reset captions.
    static func resetDateDisplay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Resets \(formatter.string(from: date))"
    }

    /// Relative "Resets in X days" line to show beneath an absolute "Resets <date>" value.
    /// Returns nil when the text is already relative, a short interval, or cannot be parsed.
    static func relativeResetLine(from text: String, referenceDate: Date = Date()) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if daysFromRelativeResetPhrase(in: trimmed) != nil {
            return nil
        }

        guard let relative = resetDisplay(from: trimmed, referenceDate: referenceDate) else {
            return nil
        }

        if trimmed.caseInsensitiveCompare(relative) == .orderedSame {
            return nil
        }

        return relative
    }

    private static func containsShortIntervalReset(lower: String) -> Bool {
        lower.range(
            of: #"\d+\s*(?:hour|minute|second|sec)s?"#,
            options: .regularExpression
        ) != nil
    }

    private static func daysFromRelativeResetPhrase(in text: String) -> Int? {
        let patterns = [
            #"(?i)(?:reset|resets|renew|renews|billing cycle|usage)\s+in\s+(\d+)\s+days?"#,
            #"(?i)(?:next )?billing(?: date)?\s+in\s+(\d+)\s+days?"#,
            #"(?i)in\s+(\d+)\s+days?\s+(?:until|before)?\s*(?:reset|resets|renew|renews|billing)"#
        ]

        for pattern in patterns {
            if let value = DashboardParserSupport.firstMatch(in: text, pattern: pattern),
               let days = Int(value)
            {
                return max(0, days)
            }
        }

        return nil
    }

    private static func relativeResetLabel(days: Int) -> String {
        switch days {
        case 0:
            return "Resets today"
        case 1:
            return "Resets tomorrow"
        default:
            return "Resets in \(days) days"
        }
    }

    private static func parseResetDate(from text: String, referenceDate: Date = Date()) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d yyyy",
            "MMMM d yyyy"
        ]

        if let iso = DashboardParserSupport.firstMatch(
            in: text,
            pattern: #"(\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?)"#
        ) {
            if let date = parseISO8601Date(iso) {
                return date
            }
        }

        let naturalPatterns = [
            #"(?i)(?:reset|resets|renew|renews|billing)\s+(?:on|at)?\s*([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4})"#,
            #"(?i)(?:next (?:billing|payment|invoice)(?: date)?|billing date|renews?(?: on)?)\s*:?\s*([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4})"#
        ]

        for pattern in naturalPatterns {
            guard let capture = DashboardParserSupport.firstMatch(in: text, pattern: pattern) else {
                continue
            }

            for format in formats where !format.contains("'T'") {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = format
                if let date = formatter.date(from: capture) {
                    return date
                }
            }
        }

        if let weekdayDate = parseWeekdayResetDate(from: text, referenceDate: referenceDate) {
            return weekdayDate
        }

        return nil
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = normalizedISO8601Fraction(in: trimmed)
        let candidates = normalized == trimmed ? [trimmed] : [normalized, trimmed]

        for candidate in candidates {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: candidate) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: candidate) {
                return date
            }
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        return dateFormatter.date(from: String(trimmed.prefix(10)))
    }

    private static func normalizedISO8601Fraction(in value: String) -> String {
        guard let range = value.range(of: #"\.\d+"#, options: .regularExpression) else {
            return value
        }

        let fraction = String(value[range])
        guard fraction.count > 4 else {
            return value
        }

        return value.replacingCharacters(in: range, with: String(fraction.prefix(4)))
    }

    private static func parseWeekdayResetDate(from text: String, referenceDate: Date) -> Date? {
        let pattern =
            #"(?i)resets?\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday|sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)\b(?:\s+(\d{1,2}:\d{2}\s*[ap]m))?"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let weekdayRange = Range(match.range(at: 1), in: text),
            let weekday = calendarWeekday(from: String(text[weekdayRange]))
        else {
            return nil
        }

        var timeComponents: DateComponents?
        if match.numberOfRanges > 2,
           match.range(at: 2).location != NSNotFound,
           let timeRange = Range(match.range(at: 2), in: text)
        {
            timeComponents = parseClockTime(String(text[timeRange]))
        }

        return nextDate(matchingWeekday: weekday, time: timeComponents, from: referenceDate)
    }

    private static func calendarWeekday(from token: String) -> Int? {
        switch token.lowercased() {
        case "sun", "sunday":
            return 1
        case "mon", "monday":
            return 2
        case "tue", "tues", "tuesday":
            return 3
        case "wed", "wednesday":
            return 4
        case "thu", "thur", "thurs", "thursday":
            return 5
        case "fri", "friday":
            return 6
        case "sat", "saturday":
            return 7
        default:
            return nil
        }
    }

    private static func parseClockTime(_ text: String) -> DateComponents? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return Calendar.current.dateComponents([.hour, .minute], from: date)
    }

    private static func nextDate(
        matchingWeekday targetWeekday: Int,
        time: DateComponents?,
        from referenceDate: Date
    ) -> Date? {
        let calendar = Calendar.current
        let referenceWeekday = calendar.component(.weekday, from: referenceDate)
        var daysToAdd = (targetWeekday - referenceWeekday + 7) % 7

        if daysToAdd == 0, let time {
            var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            components.hour = time.hour
            components.minute = time.minute
            if let todayAtTime = calendar.date(from: components), todayAtTime <= referenceDate {
                daysToAdd = 7
            }
        }

        guard let startOfDay = calendar.date(
            from: calendar.dateComponents([.year, .month, .day], from: referenceDate)
        ) else {
            return nil
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: startOfDay)
    }

    static func relativeTimestamp(_ date: Date?, relativeTo referenceDate: Date = Date()) -> String {
        guard let date else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let comparisonDate = min(date, referenceDate)
        return formatter.localizedString(for: comparisonDate, relativeTo: referenceDate)
    }

    static func lastSyncTimestamp(_ date: Date?, relativeTo referenceDate: Date = Date()) -> String {
        guard let date else {
            return "Never"
        }

        if date.timeIntervalSince(referenceDate) > 1 {
            return "Just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}
