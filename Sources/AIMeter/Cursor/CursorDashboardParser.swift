import Foundation

enum CursorDashboardParser {
    static let billingPageURL = "https://cursor.com/dashboard/billing"

    enum ParseResult: Equatable {
        case usage(CursorUsageSnapshot)
        case authRequired
        case noMatch
    }

    /// Parses billing-cycle reset copy from the dashboard billing page (DOM or API).
    static func parseBillingReset(from text: String, sourceURL: String, referenceDate: Date = Date()) -> String? {
        guard isBillingSource(sourceURL) else {
            return nil
        }

        return bestBillingResetDisplay(in: text, referenceDate: referenceDate)
    }

    static func parseBillingReset(fromResponseBody body: String, sourceURL: String, referenceDate: Date = Date()) -> String? {
        guard isBillingSource(sourceURL) else {
            return nil
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return nil
        }

        if let data = trimmedBody.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data)
        {
            if let resetDate = bestBillingResetDate(fromJSONObject: jsonObject, referenceDate: referenceDate) {
                return DisplayFormatting.resetInDays(until: resetDate, from: referenceDate)
            }

            let leafText = DashboardParserSupport.jsonLeafStrings(from: jsonObject).joined(separator: "\n")
            if let display = bestBillingResetDisplay(in: leafText, referenceDate: referenceDate) {
                return display
            }
        }

        return bestBillingResetDisplay(
            in: DashboardParserSupport.stripHTML(from: trimmedBody),
            referenceDate: referenceDate
        )
    }

    static func parseResponseBody(_ body: String, sourceURL: String) -> ParseResult {
        guard CursorURLValidator.isAllowedCursorURLString(sourceURL) else {
            return .noMatch
        }

        return parseResponseBody(body, sourceURL: sourceURL, allowAuthDetection: false)
    }

    static func parseDOMText(_ text: String, sourceURL: String) -> ParseResult {
        parseText(text, sourceURL: sourceURL, allowAuthDetection: true)
    }

    private static func parseResponseBody(_ body: String, sourceURL: String, allowAuthDetection: Bool) -> ParseResult {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return .noMatch
        }

        if let data = trimmedBody.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data)
        {
            if let snapshot = parseJSONObject(jsonObject, sourceURL: sourceURL) {
                return .usage(snapshot)
            }

            let text = DashboardParserSupport.jsonLeafStrings(from: jsonObject).joined(separator: " ")
            let textResult = parseText(text, sourceURL: sourceURL, allowAuthDetection: allowAuthDetection)
            if textResult != .noMatch {
                return textResult
            }
        }

        return parseText(
            DashboardParserSupport.stripHTML(from: trimmedBody),
            sourceURL: sourceURL,
            allowAuthDetection: allowAuthDetection
        )
    }

    private static func parseJSONObject(_ object: Any, sourceURL: String) -> CursorUsageSnapshot? {
        let leaves = DashboardParserSupport.numericLeaves(from: object)
        guard !leaves.isEmpty else {
            return nil
        }

        let total = bestPercent(
            in: leaves,
            preferredKeys: [["total"], ["overall"], ["aggregate"]]
        )

        let auto = bestPercent(
            in: leaves,
            preferredKeys: [["auto"]]
        )

        let api = bestPercent(
            in: leaves,
            preferredKeys: [["api"]]
        )

        guard let total, let auto, let api else {
            return nil
        }

        let planLabel = DashboardParserSupport.jsonLeafStrings(from: object)
            .first(where: isPlanLabel) ?? "Cursor Plan"

        let resetDisplay: String?
        if isBillingSource(sourceURL) {
            let leafText = DashboardParserSupport.jsonLeafStrings(from: object).joined(separator: "\n")
            resetDisplay = bestBillingResetDate(fromJSONObject: object).map {
                DisplayFormatting.resetInDays(until: $0)
            } ?? bestBillingResetDisplay(in: leafText)
        } else {
            resetDisplay = nil
        }

        return makeSnapshot(
            planLabel: planLabel,
            totalUsedPercent: total,
            autoUsedPercent: auto,
            apiUsedPercent: api,
            resetDisplay: resetDisplay
        )
    }

    private static func bestPercent(
        in leaves: [(path: [String], value: Double)],
        preferredKeys: [[String]]
    ) -> Double? {
        for preferred in preferredKeys {
            if let match = leaves.first(where: {
                DashboardParserSupport.containsAllKeywords($0.path, preferred)
                    && DashboardParserSupport.looksLikePercentPath($0.path)
            }) {
                return DashboardParserSupport.normalizePercent(match.value)
            }
        }

        for preferred in preferredKeys {
            if let match = leaves.first(where: {
                DashboardParserSupport.containsAllKeywords($0.path, preferred)
            }) {
                return DashboardParserSupport.normalizePercent(match.value)
            }
        }

        return nil
    }

    private static func parseText(_ rawText: String, sourceURL: String, allowAuthDetection: Bool) -> ParseResult {
        let text = DashboardParserSupport.normalizeWhitespace(rawText)
        guard !text.isEmpty else {
            return .noMatch
        }

        if allowAuthDetection && indicatesAuthentication(text: text, sourceURL: sourceURL) {
            return .authRequired
        }

        guard
            let planLabel = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(Included in\\s+(?:Free|Hobby|Pro\\+?|Ultra(?:\\s+[A-Za-z0-9+]+)?))"
            ),
            let totalPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "Total\\s+(\\d+(?:\\.\\d+)?)%"
            ),
            let autoPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+Auto"
            ),
            let apiPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+API"
            ),
            let total = Double(totalPercent),
            let auto = Double(autoPercent),
            let api = Double(apiPercent)
        else {
            return .noMatch
        }

        let resetDisplay = isBillingSource(sourceURL)
            ? bestBillingResetDisplay(in: rawText)
            : nil

        return .usage(
            makeSnapshot(
                planLabel: planLabel,
                totalUsedPercent: total,
                autoUsedPercent: auto,
                apiUsedPercent: api,
                resetDisplay: resetDisplay
            )
        )
    }

    private static func makeSnapshot(
        planLabel: String,
        totalUsedPercent: Double,
        autoUsedPercent: Double,
        apiUsedPercent: Double,
        resetDisplay: String?
    ) -> CursorUsageSnapshot {
        CursorUsageSnapshot(
            planLabel: planLabel,
            totalUsedPercent: totalUsedPercent,
            autoUsedPercent: autoUsedPercent,
            apiUsedPercent: apiUsedPercent,
            resetDisplay: resetDisplay,
            fetchedAt: Date(),
            connectionState: .connected
        )
    }

    private static func isBillingSource(_ sourceURL: String) -> Bool {
        guard let path = URL(string: sourceURL)?.path.lowercased() else {
            return false
        }

        return path.contains("/billing")
    }

    private static func bestBillingResetDisplay(in text: String, referenceDate: Date = Date()) -> String? {
        let lines = DashboardParserSupport.normalizedLines(from: text)
        var best: (dayCount: Int, display: String)?

        for line in lines where isBillingCycleResetLine(line) {
            guard let display = DisplayFormatting.resetDisplay(from: line, referenceDate: referenceDate) else {
                continue
            }

            let dayCount = dayCount(forResetDisplay: display, referenceDate: referenceDate)
            if best == nil || dayCount > best!.dayCount {
                best = (dayCount, display)
            }
        }

        if let best {
            return best.display
        }

        guard isBillingCycleResetLine(text),
              let display = DisplayFormatting.resetDisplay(from: text, referenceDate: referenceDate)
        else {
            return nil
        }

        return display
    }

    private static func isBillingCycleResetLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if DisplayFormatting.resetDisplay(from: line) == nil {
            return false
        }

        if lower.range(of: #"\d+\s*(?:hour|minute|second)s?"#, options: .regularExpression) != nil {
            return false
        }

        return lower.contains("billing")
            || lower.contains("renew")
            || lower.contains("subscription")
            || lower.contains("invoice")
            || lower.contains("next payment")
            || lower.range(of: #"(?:reset|resets|renew).{0,40}\d+\s+days?"#, options: .regularExpression) != nil
            || lower.range(
                of: #"(?:next )?(?:billing|payment).{0,20}[A-Za-z]{3,9}\s+\d{1,2}"#,
                options: .regularExpression
            ) != nil
    }

    private static func dayCount(forResetDisplay display: String, referenceDate: Date) -> Int {
        if let match = DashboardParserSupport.firstMatch(in: display, pattern: #"Resets in (\d+) days"#),
           let days = Int(match)
        {
            return days
        }

        switch display {
        case "Resets tomorrow":
            return 1
        case "Resets today":
            return 0
        default:
            return -1
        }
    }

    private static func bestBillingResetDate(fromJSONObject object: Any, referenceDate: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)

        let rankedDates = jsonStringLeaves(from: object).compactMap { leaf -> (score: Int, date: Date)? in
            guard let date = parseISO8601Date(leaf.value) else {
                return nil
            }

            let score = billingResetPathScore(leaf.path)
            guard score > 0 else {
                return nil
            }

            guard calendar.startOfDay(for: date) >= startOfToday else {
                return nil
            }

            return (score, date)
        }

        return rankedDates
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.date > $1.date
            }
            .first?
            .date
    }

    private static func billingResetPathScore(_ path: [String]) -> Int {
        let joined = path.joined(separator: ".").lowercased()

        if joined.contains("periodstart")
            || joined.contains("cyclestart")
            || joined.contains("startdate")
            || joined.contains("startedat")
            || joined.contains("createdat")
            || joined.contains("updatedat")
            || joined.contains("fetchedat")
        {
            return -100
        }

        if joined.contains("periodend")
            || joined.contains("cycleend")
            || joined.contains("currentperiodend")
            || joined.contains("nextbilling")
            || joined.contains("next_billing")
            || joined.contains("renewaldate")
            || joined.contains("billingdate")
        {
            return 100
        }

        if joined.contains("end") && !joined.contains("start") {
            return 80
        }

        if joined.contains("renew") || joined.contains("next") {
            return 70
        }

        if joined.contains("billing") || joined.contains("subscription") {
            return 50
        }

        if joined.contains("reset") || joined.contains("cycle") {
            return 20
        }

        return 0
    }

    private static func jsonStringLeaves(
        from object: Any,
        path: [String] = []
    ) -> [(path: [String], value: String)] {
        if let string = object as? String {
            let normalized = DashboardParserSupport.normalizeWhitespace(string)
            guard !normalized.isEmpty else {
                return []
            }
            return [(path, normalized)]
        }

        if let dictionary = object as? [String: Any] {
            return dictionary.flatMap { key, value in
                jsonStringLeaves(from: value, path: path + [key])
            }
        }

        if let array = object as? [Any] {
            return array.enumerated().flatMap { index, value in
                jsonStringLeaves(from: value, path: path + ["\(index)"])
            }
        }

        return []
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        if let timestamp = Double(trimmed), timestamp > 1_000_000_000 {
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = dateFormatter.date(from: trimmed) {
            return date
        }

        dateFormatter.formatOptions = [.withFullDate]
        return dateFormatter.date(from: String(trimmed.prefix(10)))
    }

    private static func indicatesAuthentication(text: String, sourceURL: String) -> Bool {
        let loweredText = text.lowercased()
        if let url = URL(string: sourceURL) {
            let host = (url.host ?? "").lowercased()
            let path = url.path.lowercased()

            if host.hasPrefix("auth.") {
                return true
            }

            let authPaths = ["/login", "/signin", "/sign-in", "/authorize"]
            if authPaths.contains(where: { path.contains($0) }) {
                return true
            }
        }

        let authPhrases = [
            "sign in to cursor",
            "log in to cursor",
            "continue with google",
            "continue with github",
            "enter your email"
        ]

        return authPhrases.contains(where: loweredText.contains)
    }

    private static func isPlanLabel(_ value: String) -> Bool {
        value.range(
            of: "Included in\\s+(?:Free|Hobby|Pro\\+?|Ultra(?:\\s+[A-Za-z0-9+]+)?)",
            options: .regularExpression
        ) != nil
    }
}
