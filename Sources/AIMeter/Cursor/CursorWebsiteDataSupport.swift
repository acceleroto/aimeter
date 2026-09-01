import Foundation
import WebKit

enum CursorWebsiteDataSupport {
    static let legacyDefaultStoreMigrationKey = "aimeter.cursor.legacyDefaultStoreMigrated"

    static let requestHeaderTooLargeRecoveryMessage =
        "Cursor sign-in cookies were too large to load the dashboard. AIMeter cleared local Cursor cookies; try Connect again."

    static func isCursorWebsiteDataRecord(_ displayName: String) -> Bool {
        displayName.localizedCaseInsensitiveContains("cursor")
    }

    static func isCursorCookieDomain(_ domain: String) -> Bool {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        return CursorURLValidator.allowedResponseHosts.contains { host in
            normalized == host || normalized.hasSuffix(".\(host)")
        }
    }

    static func isRequestHeaderTooLargePage(_ text: String) -> Bool {
        let normalized = text.uppercased()
        return normalized.contains("REQUEST_HEADER_TOO_LARGE")
            || normalized.contains("494: REQUEST_HEADER_TOO_LARGE")
    }

    static func clearWebsiteData(in dataStore: WKWebsiteDataStore) async {
        await clearCookies(in: dataStore.httpCookieStore)

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: types) { records in
                let cursorRecords = records.filter { isCursorWebsiteDataRecord($0.displayName) }
                guard !cursorRecords.isEmpty else {
                    continuation.resume()
                    return
                }

                dataStore.removeData(ofTypes: types, for: cursorRecords) {
                    continuation.resume()
                }
            }
        }
    }

    static func migrateLegacyDefaultStoreIfNeeded(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: legacyDefaultStoreMigrationKey) else {
            return
        }

        userDefaults.set(true, forKey: legacyDefaultStoreMigrationKey)

        Task {
            await clearWebsiteData(in: WKWebsiteDataStore.default())
        }
    }

    private static func clearCookies(in cookieStore: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                let cursorCookies = cookies.filter { isCursorCookieDomain($0.domain) }
                guard !cursorCookies.isEmpty else {
                    continuation.resume()
                    return
                }

                let group = DispatchGroup()
                for cookie in cursorCookies {
                    group.enter()
                    cookieStore.delete(cookie) {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    continuation.resume()
                }
            }
        }
    }
}
