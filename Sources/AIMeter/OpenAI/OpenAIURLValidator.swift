import Foundation

enum OpenAIURLValidator {
    static let allowedHosts: Set<String> = [
        "chatgpt.com",
        "www.chatgpt.com"
    ]

    static func validatedUsageURL(from rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isAllowedOpenAIURL(url) else {
            throw ProviderUsageError.invalidConfiguration("OpenAI usage page URL must be an HTTPS chatgpt.com URL.")
        }

        return url
    }

    static func sanitizedUsageURL(_ rawURL: String) -> String {
        guard let url = try? validatedUsageURL(from: rawURL) else {
            return OpenAISettings.default.usagePageURL
        }

        if isAnalyticsURL(url) {
            return url.absoluteString
        }

        return OpenAISettings.default.usagePageURL
    }

    static func isAllowedOpenAIURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }

        return isAllowedOpenAIURL(url)
    }

    static func isAnalyticsURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL), isAllowedOpenAIURL(url) else {
            return false
        }

        return isAnalyticsURL(url)
    }

    static func isAllowedOpenAIURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            return false
        }

        guard url.user(percentEncoded: false) == nil, url.password(percentEncoded: false) == nil else {
            return false
        }

        guard url.port == nil else {
            return false
        }

        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return false
        }

        return allowedHosts.contains(host)
    }

    private static func isAnalyticsURL(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return path == "codex/cloud/settings/analytics"
    }
}
