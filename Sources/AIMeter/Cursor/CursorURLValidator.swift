import Foundation

enum CursorURLValidator {
    static let allowedHosts: Set<String> = [
        "cursor.com",
        "www.cursor.com"
    ]

    static let allowedResponseHosts: Set<String> = allowedHosts.union([
        "api2.cursor.sh"
    ])

    static func validatedUsageURL(from rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isAllowedCursorURL(url) else {
            throw CursorUsageError.invalidConfiguration("Cursor usage page URL must be an HTTPS cursor.com URL.")
        }

        return url
    }

    static func sanitizedUsageURL(_ rawURL: String) -> String {
        guard let url = try? validatedUsageURL(from: rawURL) else {
            return CursorSettings.default.usagePageURL
        }

        return url.absoluteString
    }

    static func isAllowedCursorURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }

        return isAllowedCursorURL(url)
    }

    static func isAllowedCursorResponseURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }

        return isAllowedCursorResponseURL(url)
    }

    static func isAllowedCursorURL(_ url: URL) -> Bool {
        isAllowedHTTPSURL(url, hosts: allowedHosts)
    }

    static func isAllowedCursorResponseURL(_ url: URL) -> Bool {
        isAllowedHTTPSURL(url, hosts: allowedResponseHosts)
    }

    private static func isAllowedHTTPSURL(_ url: URL, hosts: Set<String>) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            return false
        }

        guard url.user == nil, url.password == nil else {
            return false
        }

        guard url.port == nil else {
            return false
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        return hosts.contains(host)
    }
}
