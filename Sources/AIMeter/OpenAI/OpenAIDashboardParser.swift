import Foundation

enum OpenAIDashboardParser {
    private static let maximumStatusLineLength = 140

    /// Codex analytics reports capacity remaining; AIMeter displays usage consumed.
    private static func usedPercent(fromReportedRemaining reported: Double) -> Double {
        min(max(100 - reported, 0), 100)
    }

    private static func usageMetric(title: String, reportedRemainingPercent: Double) -> UsageMetric {
        let used = usedPercent(fromReportedRemaining: reportedRemainingPercent)
        return UsageMetric(
            title: title,
            value: DisplayFormatting.percent(used),
            percent: used
        )
    }

    enum ParseResult: Equatable {
        case usage(ProviderUsageSnapshot)
        case authRequired
        case noMatch
    }

    static func parseDOMText(_ text: String, sourceURL: String) -> ParseResult {
        parseText(text, sourceURL: sourceURL, allowAuthDetection: true)
    }

    static func parseResponseBody(_ body: String, sourceURL: String) -> ParseResult {
        guard OpenAIURLValidator.isAllowedOpenAIURLString(sourceURL) else {
            return .noMatch
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return .noMatch
        }

        if
            let data = trimmedBody.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        {
            if let snapshot = snapshotFromJSONObject(object) {
                return .usage(snapshot)
            }

            let leafText = DashboardParserSupport.jsonLeafStrings(from: object).joined(separator: "\n")
            return parseText(
                leafText,
                sourceURL: sourceURL,
                allowAuthDetection: false,
                requireUsagePercent: true
            )
        }

        return parseText(
            DashboardParserSupport.stripHTML(from: trimmedBody),
            sourceURL: sourceURL,
            allowAuthDetection: false,
            requireUsagePercent: true
        )
    }

    static func signedInSnapshot() -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: .openai,
            planLabel: "OpenAI",
            primaryMetric: UsageMetric(title: "Status", value: "Signed in"),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )
    }

    private static func parseText(
        _ text: String,
        sourceURL: String,
        allowAuthDetection: Bool,
        requireUsagePercent: Bool = false
    ) -> ParseResult {
        guard OpenAIURLValidator.isAllowedOpenAIURLString(sourceURL) else {
            return .noMatch
        }

        let normalized = DashboardParserSupport.normalizeWhitespace(text)
        guard !normalized.isEmpty else {
            return .noMatch
        }

        if allowAuthDetection && looksLikeAuthPage(normalized) {
            return .authRequired
        }

        if
            allowAuthDetection,
            !OpenAIURLValidator.isAnalyticsURLString(sourceURL),
            let signedInSnapshot = signedInAppSnapshot(from: normalized)
        {
            return .usage(signedInSnapshot)
        }

        return parseUsageText(text, sourceURL: sourceURL, requireUsagePercent: requireUsagePercent)
    }

    private static func parseUsageText(_ text: String, sourceURL: String, requireUsagePercent: Bool) -> ParseResult {
        let lines = DashboardParserSupport.normalizedLines(from: text)
        let lowercased = text.lowercased()

        guard
            lowercased.contains("codex")
                || lowercased.contains("chatgpt")
                || lowercased.contains("usage")
                || lowercased.contains("limit")
                || lowercased.contains("credits")
        else {
            return .noMatch
        }

        let planLabel = planLabel(from: lines, text: text)
        let usageMetrics = usageMetrics(from: lines, sourceURL: sourceURL)
        let fiveHourMetric = usageMetrics.first { $0.title.caseInsensitiveCompare("5-hour") == .orderedSame }
        let primaryMetric = fiveHourMetric
            ?? usageMetrics.first
            ?? primaryMetricFromText(text)
        let usagePercent = primaryMetric?.percent

        guard usagePercent != nil || !usageMetrics.isEmpty || hasCreditsMetric(in: lines) else {
            return .noMatch
        }

        if requireUsagePercent && usagePercent == nil && fiveHourMetric == nil {
            return .noMatch
        }

        let resolvedPrimary: UsageMetric
        if let primaryMetric {
            resolvedPrimary = primaryMetric
        } else if let reported = reportedRemainingPercent(from: text) {
            resolvedPrimary = usageMetric(title: "5-hour", reportedRemainingPercent: reported)
        } else {
            resolvedPrimary = UsageMetric(title: "5-hour", value: "Available")
        }

        let secondaryMetrics = usageMetrics
            .filter { $0.title.caseInsensitiveCompare(resolvedPrimary.title) != .orderedSame }
            .removingDuplicateMetrics()

        return .usage(
            ProviderUsageSnapshot(
                provider: .openai,
                planLabel: planLabel,
                primaryMetric: resolvedPrimary,
                secondaryMetrics: secondaryMetrics,
                fetchedAt: Date(),
                connectionState: .connected
            )
        )
    }

    private static func primaryMetricFromText(_ text: String) -> UsageMetric? {
        guard
            let reported = reportedRemainingPercent(from: text, near: "5-hour")
                ?? reportedRemainingPercent(from: text, near: "5 hour")
        else {
            return nil
        }

        return usageMetric(title: "5-hour", reportedRemainingPercent: reported)
    }

    private static func usageMetrics(from lines: [String], sourceURL: String) -> [UsageMetric] {
        var metrics: [UsageMetric] = []

        for (index, line) in lines.enumerated() {
            if let creditsMetric = creditsMetric(at: index, in: lines) {
                metrics.append(creditsMetric)
                continue
            }

            guard let reported = reportedRemainingPercent(in: line, at: index, in: lines) else {
                continue
            }

            let title = titleForUsageMetric(before: index, in: lines)
            let resetLine = resetLineForUsageMetric(near: index, in: lines)
            metrics.append(usageMetric(title: title, reportedRemainingPercent: reported))
            if let resetLine {
                metrics.append(UsageMetric(title: resetMetricTitle(for: title), value: resetLine))
            }
        }

        if !OpenAIURLValidator.isAnalyticsURLString(sourceURL) {
            return metrics.removingDuplicateMetrics()
        }

        return metrics
            .normalizedAnalyticsMetrics()
            .removingDuplicateMetrics()
    }

    private static func creditsMetric(at index: Int, in lines: [String]) -> UsageMetric? {
        let line = lines[index]
        let lowercased = line.lowercased()
        guard lowercased.contains("credit") else {
            return nil
        }

        if let value = creditValue(in: line) {
            return UsageMetric(title: "Credits", value: value)
        }

        let lowerBound = max(0, index - 3)
        let upperBound = min(lines.count - 1, index + 3)
        for candidateIndex in lowerBound...upperBound where candidateIndex != index {
            if let value = creditValue(in: lines[candidateIndex]) {
                return UsageMetric(title: "Credits", value: value)
            }
        }

        return nil
    }

    private static func creditValue(in line: String) -> String? {
        if let amount = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"(?i)\$\s*(\d+(?:\.\d{2})?)\s*(?:remaining|left|balance)?"#
        ) {
            return "$\(amount)"
        }

        if let percent = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:used|remaining|left)"#
        ), line.lowercased().contains("credit"), let reported = Double(percent) {
            return DisplayFormatting.percent(usedPercent(fromReportedRemaining: reported))
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "credits" {
            return nil
        }

        if line.lowercased().contains("credit") && !line.contains("%") {
            return DashboardParserSupport.normalizeWhitespace(line)
        }

        return nil
    }

    private static func hasCreditsMetric(in lines: [String]) -> Bool {
        lines.contains { $0.lowercased().contains("credit") }
    }

    /// Parses the remaining-capacity percentage shown on Codex analytics (not usage used).
    private static func reportedRemainingPercent(in line: String, at index: Int, in lines: [String]) -> Double? {
        if let value = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:remaining|left)"#
        ) {
            return Double(value).map { min(max($0, 0), 100) }
        }

        if let value = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:used|usage)"#
        ) {
            return Double(value).map { min(max($0, 0), 100) }
        }

        guard let bareValue = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"^\s*(\d{1,3}(?:\.\d+)?)\s*%\s*$"#
        ) else {
            return nil
        }

        guard isNearUsageMetricContext(index: index, in: lines) else {
            return nil
        }

        return Double(bareValue).map { min(max($0, 0), 100) }
    }

    private static func isNearUsageMetricContext(index: Int, in lines: [String]) -> Bool {
        let lowerBound = max(0, index - 8)
        let upperBound = min(lines.count - 1, index + 4)
        for candidateIndex in lowerBound...upperBound {
            let lowercased = lines[candidateIndex].lowercased()
            if lowercased.contains("usage limit")
                || lowercased.contains("5-hour")
                || lowercased.contains("5 hour")
                || lowercased.contains("weekly")
                || lowercased.contains("codex")
            {
                return true
            }
        }
        return false
    }

    private static func titleForUsageMetric(before index: Int, in lines: [String]) -> String {
        let lowerBound = max(0, index - 10)
        for candidateIndex in stride(from: index - 1, through: lowerBound, by: -1) {
            if let knownTitle = knownUsageMetricTitle(from: lines[candidateIndex]) {
                return knownTitle
            }
        }

        return "Usage"
    }

    private static func knownUsageMetricTitle(from line: String) -> String? {
        let lowercased = line.lowercased()
        if lowercased.contains("5-hour") || lowercased.contains("5 hour") {
            return "5-hour"
        }
        if lowercased.contains("weekly") {
            return "Weekly"
        }
        if lowercased.contains("credit") {
            return "Credits"
        }
        return nil
    }

    private static func resetLineForUsageMetric(near index: Int, in lines: [String]) -> String? {
        let lowerBound = max(0, index - 6)
        let upperBound = min(lines.count - 1, index + 4)

        if index + 1 <= upperBound {
            for candidateIndex in (index + 1)...upperBound {
                let line = lines[candidateIndex]
                if isResetLine(line) {
                    return line
                }
            }
        }

        for candidateIndex in stride(from: index - 1, through: lowerBound, by: -1) {
            let line = lines[candidateIndex]
            if isResetLine(line), !crossesOtherUsageSection(from: candidateIndex, to: index, in: lines) {
                return line
            }
        }

        return nil
    }

    private static func crossesOtherUsageSection(from startIndex: Int, to endIndex: Int, in lines: [String]) -> Bool {
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        for candidateIndex in range {
            if knownUsageMetricTitle(from: lines[candidateIndex]) != nil {
                return true
            }
        }
        return false
    }

    private static func resetMetricTitle(for title: String) -> String {
        "\(title) reset"
    }

    private static func isResetLine(_ line: String) -> Bool {
        guard isReasonableStatusLine(line) else {
            return false
        }

        let lowercased = line.lowercased()
        return lowercased.contains("reset") || lowercased.contains("resets")
    }

    private static func isReasonableStatusLine(_ line: String) -> Bool {
        !line.isEmpty && line.count <= maximumStatusLineLength
    }

    private static func reportedRemainingPercent(from text: String, near keyword: String) -> Double? {
        guard let range = text.range(of: keyword, options: .caseInsensitive) else {
            return nil
        }

        let start = text.index(range.lowerBound, offsetBy: -120, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
        let window = String(text[start..<end])
        return reportedRemainingPercent(from: window)
    }

    private static func reportedRemainingPercent(from text: String) -> Double? {
        if let remaining = percent(in: text, pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:remaining|left)"#) {
            return remaining
        }

        if let reported = percent(in: text, pattern: #"(?i)(?:usage|used|limit)[^%\n]{0,80}?(\d{1,3}(?:\.\d+)?)\s*%"#) {
            return reported
        }

        return nil
    }

    private static func percent(in text: String, pattern: String) -> Double? {
        guard let value = DashboardParserSupport.firstMatch(in: text, pattern: pattern) else {
            return nil
        }
        return Double(value).map { min(max($0, 0), 100) }
    }

    private static func planLabel(from lines: [String], text: String) -> String {
        for line in lines {
            if let label = planLabel(from: line) {
                return label
            }
        }

        if text.localizedCaseInsensitiveContains("chatgpt plus") {
            return "ChatGPT Plus"
        }

        return "OpenAI"
    }

    private static func planLabel(from line: String) -> String? {
        let patterns = [
            ("ChatGPT Plus", #"(?i)chatgpt\s+plus"#),
            ("ChatGPT Pro", #"(?i)chatgpt\s+pro"#),
            ("ChatGPT Go", #"(?i)chatgpt\s+go"#),
            ("ChatGPT Free", #"(?i)chatgpt\s+free"#),
            ("ChatGPT Business", #"(?i)chatgpt\s+business"#),
            ("ChatGPT Enterprise", #"(?i)chatgpt\s+enterprise"#)
        ]

        for (label, pattern) in patterns {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return label
            }
        }

        return nil
    }

    private static func signedInAppSnapshot(from text: String) -> ProviderUsageSnapshot? {
        let lowercased = text.lowercased()
        guard
            lowercased.contains("chatgpt")
                || lowercased.contains("codex")
                || lowercased.contains("new chat")
        else {
            return nil
        }

        if looksLikeAuthPage(text) {
            return nil
        }

        return signedInSnapshot()
    }

    private static func snapshotFromJSONObject(_ object: Any) -> ProviderUsageSnapshot? {
        let leaves = DashboardParserSupport.numericLeaves(from: object)
        let fiveHourPercent = percentFromJSONLeaves(leaves, keywords: ["five", "hour"])
        let weeklyPercent = percentFromJSONLeaves(leaves, keywords: ["week"])
        let leafText = DashboardParserSupport.jsonLeafStrings(from: object).joined(separator: "\n")
        let planLabel = planLabel(from: DashboardParserSupport.normalizedLines(from: leafText), text: leafText)

        guard fiveHourPercent != nil || weeklyPercent != nil else {
            return nil
        }

        let primaryReported = fiveHourPercent ?? weeklyPercent!
        let primaryTitle = fiveHourPercent != nil ? "5-hour" : "Weekly"
        var secondaryMetrics: [UsageMetric] = []

        if let weeklyPercent, fiveHourPercent != nil {
            secondaryMetrics.append(usageMetric(title: "Weekly", reportedRemainingPercent: weeklyPercent))
        }

        if leafText.localizedCaseInsensitiveContains("credit") {
            if let creditValue = DashboardParserSupport.firstMatch(
                in: leafText,
                pattern: #"(?i)\$\s*(\d+(?:\.\d{2})?)"#
            ) {
                secondaryMetrics.append(UsageMetric(title: "Credits", value: "$\(creditValue)"))
            }
        }

        return ProviderUsageSnapshot(
            provider: .openai,
            planLabel: planLabel,
            primaryMetric: usageMetric(title: primaryTitle, reportedRemainingPercent: primaryReported),
            secondaryMetrics: secondaryMetrics,
            fetchedAt: Date(),
            connectionState: .connected
        )
    }

    private static func percentFromJSONLeaves(
        _ leaves: [(path: [String], value: Double)],
        keywords: [String]
    ) -> Double? {
        for leaf in leaves {
            let pathLowercased = leaf.path.map { $0.lowercased() }
            guard keywords.allSatisfy({ keyword in
                pathLowercased.contains(where: { $0.contains(keyword) })
            }) else {
                continue
            }

            if DashboardParserSupport.looksLikePercentPath(leaf.path) || leaf.value <= 100 {
                return DashboardParserSupport.normalizePercent(leaf.value)
            }
        }

        return nil
    }

    private static func looksLikeAuthPage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("log in")
            || lowercased.contains("login")
            || lowercased.contains("sign up")
            || lowercased.contains("sign in")
            || lowercased.contains("create your account")
            || lowercased.contains("continue with google")
            || lowercased.contains("continue with apple")
            || lowercased.contains("continue with microsoft")
    }
}

private extension Array where Element == UsageMetric {
    func removingDuplicateMetrics() -> [UsageMetric] {
        var seen: Set<String> = []
        return filter { metric in
            let key = "\(metric.title.lowercased())|\(metric.value.lowercased())"
            return seen.insert(key).inserted
        }
    }

    func normalizedAnalyticsMetrics() -> [UsageMetric] {
        var result: [UsageMetric] = []
        var hasFiveHour = false
        var hasWeekly = false

        for metric in self {
            switch metric.title.lowercased() {
            case "5-hour", "usage":
                if !hasFiveHour, metric.percent != nil {
                    result.append(
                        UsageMetric(
                            title: "5-hour",
                            value: metric.value,
                            percent: metric.percent
                        )
                    )
                    hasFiveHour = true
                } else {
                    result.append(metric)
                }
            case "weekly":
                hasWeekly = true
                result.append(metric)
            default:
                result.append(metric)
            }
        }

        let percentMetrics = filter { $0.percent != nil }
        if !hasFiveHour,
           let first = percentMetrics.first,
           first.title.caseInsensitiveCompare("Usage") == .orderedSame
        {
            result.insert(
                UsageMetric(title: "5-hour", value: first.value, percent: first.percent),
                at: 0
            )
        }
        if !hasWeekly,
           percentMetrics.count > 1,
           let second = percentMetrics.dropFirst().first,
           second.title.caseInsensitiveCompare("Usage") == .orderedSame
        {
            result.append(
                UsageMetric(title: "Weekly", value: second.value, percent: second.percent)
            )
        }

        return result
    }
}
