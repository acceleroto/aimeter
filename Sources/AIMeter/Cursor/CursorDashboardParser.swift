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
        guard CursorURLValidator.isAllowedCursorResponseURLString(sourceURL) else {
            return .noMatch
        }

        return parseResponseBody(body, sourceURL: sourceURL, allowAuthDetection: false)
    }

    static func parsePlanInfoLabel(fromResponseBody body: String, sourceURL: String) -> String? {
        guard isSupplementalPlanInfoResponseURL(sourceURL) else {
            return nil
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmedBody.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let dictionary = jsonObject as? [String: Any]
        else {
            return nil
        }

        return resolvedPlanLabel(from: dictionary)
    }

    static func isAuthoritativeUsageResponseURL(_ sourceURL: String) -> Bool {
        let lowercased = sourceURL.lowercased()
        return lowercased.contains("get-current-period-usage")
            || lowercased.contains("getcurrentperiodusage")
    }

    static func isSupplementalPlanInfoResponseURL(_ sourceURL: String) -> Bool {
        let lowercased = sourceURL.lowercased()
        return lowercased.contains("get-plan-info")
            || lowercased.contains("getplaninfo")
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
            if let dictionary = jsonObject as? [String: Any],
               let snapshot = parseStructuredUsagePayload(dictionary, sourceURL: sourceURL)
            {
                return .usage(snapshot)
            }

            if isAuthoritativeUsageResponseURL(sourceURL) || isSupplementalPlanInfoResponseURL(sourceURL) {
                return .noMatch
            }

            if let dictionary = jsonObject as? [String: Any],
               let snapshot = parseLegacyUsagePayload(dictionary, sourceURL: sourceURL)
            {
                return .usage(snapshot)
            }
        }

        return .noMatch
    }

    private static func parseJSONObject(_ object: Any, sourceURL: String) -> CursorUsageSnapshot? {
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        return parseStructuredUsagePayload(dictionary, sourceURL: sourceURL)
            ?? parseLegacyUsagePayload(dictionary, sourceURL: sourceURL)
    }

    private static func parseLegacyUsagePayload(
        _ object: [String: Any],
        sourceURL: String
    ) -> CursorUsageSnapshot? {
        guard let usage = object["usage"] as? [String: Any] else {
            return nil
        }

        let breakdown = usage["breakdown"] as? [String: Any] ?? usage

        guard let total = usagePercent(from: usage["totalUsedPercent"])
            ?? usagePercent(from: usage["totalPercentUsed"])
        else {
            return nil
        }

        guard let auto = usagePercent(from: breakdown["autoUsedPercent"])
            ?? usagePercent(from: breakdown["autoPercentUsed"])
        else {
            return nil
        }

        guard let api = usagePercent(from: breakdown["apiUsedPercent"])
            ?? usagePercent(from: breakdown["apiPercentUsed"])
        else {
            return nil
        }

        return makeSnapshot(
            planLabel: resolvedPlanLabel(from: object) ?? "Cursor Plan",
            totalUsedPercent: total,
            autoUsedPercent: auto,
            apiUsedPercent: api,
            resetDisplay: billingResetDisplay(from: object, sourceURL: sourceURL)
        )
    }

    private static func parseStructuredUsagePayload(
        _ object: [String: Any],
        sourceURL: String
    ) -> CursorUsageSnapshot? {
        guard let planUsage = object["planUsage"] as? [String: Any] else {
            return nil
        }

        guard let total = planUsagePercent(from: planUsage["totalPercentUsed"])
            ?? computedTotalPercent(from: planUsage)
        else {
            return nil
        }

        let auto = planUsagePercent(from: planUsage["autoPercentUsed"])
        let api = planUsagePercent(from: planUsage["apiPercentUsed"])

        guard auto != nil || api != nil else {
            return nil
        }

        return makeSnapshot(
            planLabel: resolvedPlanLabel(from: object) ?? "Cursor Plan",
            totalUsedPercent: planUsagePercent(from: planUsage["totalPercentUsed"]) ?? total,
            autoUsedPercent: auto ?? 0,
            apiUsedPercent: api ?? 0,
            resetDisplay: billingResetDisplay(from: object, sourceURL: sourceURL)
        )
    }

    private static func planUsagePercent(from value: Any?) -> Double? {
        guard let number = value as? NSNumber else {
            return nil
        }

        let double = number.doubleValue
        guard double.isFinite else {
            return nil
        }

        return min(max(double, 0), 100)
    }

    private static func usagePercent(from value: Any?) -> Double? {
        guard let number = value as? NSNumber else {
            return nil
        }

        let double = number.doubleValue
        guard double.isFinite else {
            return nil
        }

        return DashboardParserSupport.normalizePercent(double)
    }

    private static func computedTotalPercent(from planUsage: [String: Any]) -> Double? {
        guard let limit = numericValue(from: planUsage["limit"]), limit > 0 else {
            return nil
        }

        let remaining = numericValue(from: planUsage["remaining"]) ?? 0
        let used = max(limit - remaining, 0)
        return min((used / limit) * 100, 100)
    }

    private static func numericValue(from value: Any?) -> Double? {
        guard let number = value as? NSNumber else {
            return nil
        }

        let double = number.doubleValue
        guard double.isFinite else {
            return nil
        }

        return double
    }

    private static func resolvedPlanLabel(from object: [String: Any]) -> String? {
        if let planInfo = object["planInfo"] as? [String: Any],
           let planName = planInfo["planName"] as? String
        {
            return formattedPlanLabel(planName)
        }

        if let plan = object["plan"] as? [String: Any],
           let label = plan["label"] as? String,
           isPlanLabel(label)
        {
            return label
        }

        if let planName = object["planName"] as? String {
            return formattedPlanLabel(planName)
        }

        return DashboardParserSupport.jsonLeafStrings(from: object).first(where: isPlanLabel)
    }

    private static func formattedPlanLabel(_ planName: String) -> String {
        let trimmed = DashboardParserSupport.normalizeWhitespace(planName)
        guard !trimmed.isEmpty else {
            return "Cursor Plan"
        }

        if isPlanLabel(trimmed) {
            return trimmed
        }

        if trimmed.range(
            of: "^(?:Free|Hobby|Pro\\+?|Ultra|Team|Enterprise)\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return "Included in \(trimmed)"
        }

        return trimmed
    }

    private static func billingResetDisplay(
        from object: [String: Any],
        sourceURL: String,
        referenceDate: Date = Date()
    ) -> String? {
        if let date = billingCycleEndDate(from: object, referenceDate: referenceDate) {
            return DisplayFormatting.resetInDays(until: date, from: referenceDate)
        }

        if isBillingSource(sourceURL) {
            let leafText = DashboardParserSupport.jsonLeafStrings(from: object).joined(separator: "\n")
            return bestBillingResetDisplay(in: leafText, referenceDate: referenceDate)
        }

        return nil
    }

    private static func billingCycleEndDate(
        from object: [String: Any],
        referenceDate: Date = Date()
    ) -> Date? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)

        for key in ["billingCycleEnd", "cycleEnd"] {
            if let date = parseBillingTimestamp(object[key]), calendar.startOfDay(for: date) >= startOfToday {
                return date
            }
        }

        if let planInfo = object["planInfo"] as? [String: Any],
           let date = parseBillingTimestamp(planInfo["billingCycleEnd"]),
           calendar.startOfDay(for: date) >= startOfToday
        {
            return date
        }

        return bestBillingResetDate(fromJSONObject: object, referenceDate: referenceDate)
    }

    private static func parseBillingTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            return parseISO8601Date(string)
        }

        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            guard timestamp > 0 else {
                return nil
            }

            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
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

        guard let sectionText = includedUsageSection(from: rawText) else {
            return .noMatch
        }

        let section = DashboardParserSupport.normalizeWhitespace(sectionText)

        guard
            let planLabel = DashboardParserSupport.firstMatch(
                in: section,
                pattern: "(Included in\\s+(?:Free|Hobby|Pro\\+?|Ultra(?:\\s+[A-Za-z0-9+]+)?))"
            ) ?? DashboardParserSupport.firstMatch(
                in: section,
                pattern: "((?:Free|Hobby|Pro\\+?|Ultra|Team|Enterprise)\\s+plan)"
            ),
            let totalPercent = DashboardParserSupport.firstMatch(
                in: section,
                pattern: "Total\\s+(\\d+(?:\\.\\d+)?)%"
            ),
            let breakdown = parseUsageBreakdownPercents(in: section),
            let total = Double(totalPercent)
        else {
            return .noMatch
        }

        let normalizedPlanLabel: String
        if planLabel.lowercased().hasSuffix("plan") {
            let trimmedPlan = planLabel.replacingOccurrences(
                of: "\\s+plan$",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            normalizedPlanLabel = "Included in \(trimmedPlan)"
        } else {
            normalizedPlanLabel = planLabel
        }

        let resetDisplay = isBillingSource(sourceURL)
            ? bestBillingResetDisplay(in: rawText)
            : nil

        return .usage(
            makeSnapshot(
                planLabel: normalizedPlanLabel,
                totalUsedPercent: total,
                autoUsedPercent: breakdown.auto,
                apiUsedPercent: breakdown.api,
                resetDisplay: resetDisplay
            )
        )
    }

    private static func includedUsageSection(from text: String) -> String? {
        guard let range = text.range(of: "Included", options: .caseInsensitive) else {
            return nil
        }

        return String(text[range.lowerBound...].prefix(800))
    }

    private static func parseUsageBreakdownPercents(in section: String) -> (auto: Double, api: Double)? {
        let combinedPattern = "(\\d+(?:\\.\\d+)?)%\\s+Auto(?:\\s*\\+\\s*Composer)?\\s+and\\s+(\\d+(?:\\.\\d+)?)%\\s+API"
        if let regex = try? NSRegularExpression(pattern: combinedPattern),
           let match = regex.firstMatch(in: section, range: NSRange(section.startIndex..., in: section)),
           match.numberOfRanges >= 3,
           let autoRange = Range(match.range(at: 1), in: section),
           let apiRange = Range(match.range(at: 2), in: section),
           let auto = Double(section[autoRange]),
           let api = Double(section[apiRange])
        {
            return (auto, api)
        }

        guard
            let autoPercent = DashboardParserSupport.firstMatch(
                in: section,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+Auto(?:\\s*\\+\\s*Composer)?"
            ) ?? DashboardParserSupport.firstMatch(
                in: section,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+Auto"
            ),
            let apiPercent = DashboardParserSupport.firstMatch(
                in: section,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+API"
            ),
            let auto = Double(autoPercent),
            let api = Double(apiPercent)
        else {
            return nil
        }

        return (auto, api)
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
