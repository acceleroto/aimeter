import Foundation

enum DisplayFormatting {
    static func percent(_ value: Double) -> String {
        compactPercent(value)
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

    static func openAICodexSuffix(fiveHour: Double, weekly: Double) -> String {
        "\(compactPercent(fiveHour))/\(compactPercent(weekly))"
    }

    static func menuBarPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        return "\(Int(clamped.rounded()))%"
    }

    static func menuBarCursorAutoAPISuffix(auto: Double, api: Double) -> String {
        "\(menuBarPercent(auto))/\(menuBarPercent(api))"
    }

    static func menuBarOpenAICodexSuffix(fiveHour: Double, weekly: Double) -> String {
        "\(menuBarPercent(fiveHour))/\(menuBarPercent(weekly))"
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

        if let resetDate = parseResetDate(from: trimmed) {
            return resetInDays(until: resetDate, from: referenceDate)
        }

        return nil
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

    private static func parseResetDate(from text: String) -> Date? {
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
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = format
                if let date = formatter.date(from: iso) {
                    return date
                }
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

        return nil
    }

    static func relativeTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
