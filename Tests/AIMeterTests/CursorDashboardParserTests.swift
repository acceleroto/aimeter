import XCTest
@testable import AIMeter

final class CursorDashboardParserTests: XCTestCase {
    func testParsesNaturalLanguageBillingDateFromDOMText() {
        let calendar = Calendar.current
        let reference = Date()
        let resetDate = calendar.date(byAdding: .day, value: 12, to: reference)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        let formattedDate = formatter.string(from: resetDate)

        let text = """
        Included in Pro+
        Total
        13%
        4% Auto and 48% API used
        Next billing date: \(formattedDate)
        """

        let result = CursorDashboardParser.parseDOMText(
            text,
            sourceURL: CursorDashboardParser.billingPageURL
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        let reset = snapshot.secondaryMetrics.first { $0.title == "Reset" }
        XCTAssertEqual(reset?.value, DisplayFormatting.resetInDays(until: resetDate, from: reference))
    }

    func testParsesBillingResetFromDOMText() {
        let text = """
        Included in Pro+
        Total
        13%
        4% Auto and 48% API used
        Usage resets in 12 days
        """

        let result = CursorDashboardParser.parseDOMText(
            text,
            sourceURL: CursorDashboardParser.billingPageURL
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        let reset = snapshot.secondaryMetrics.first { $0.title == "Reset" }
        XCTAssertEqual(reset?.value, "Resets in 12 days")
    }

    func testParsesBillingResetFromJSONPayload() {
        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          },
          "billing": {
            "renewalMessage": "Renews in 5 days"
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://www.cursor.com/api/dashboard/billing"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        let reset = snapshot.secondaryMetrics.first { $0.title == "Reset" }
        XCTAssertEqual(reset?.value, "Resets in 5 days")
    }

    func testParsesBillingPeriodEndFromJSONPayload() {
        let endDate = Calendar.current.date(byAdding: .day, value: 9, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let endISO = formatter.string(from: endDate)

        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          },
          "billing": {
            "currentPeriodEnd": "\(endISO)"
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://www.cursor.com/api/dashboard/billing"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        let reset = snapshot.secondaryMetrics.first { $0.title == "Reset" }
        XCTAssertEqual(reset?.value, "Resets in 9 days")
    }

    func testPrefersBillingPeriodEndOverPeriodStart() {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 20, to: startDate)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startISO = formatter.string(from: startDate)
        let endISO = formatter.string(from: endDate)

        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          },
          "billing": {
            "currentPeriodStart": "\(startISO)",
            "currentPeriodEnd": "\(endISO)"
          }
        }
        """

        let reset = CursorDashboardParser.parseBillingReset(
            fromResponseBody: payload,
            sourceURL: CursorDashboardParser.billingPageURL
        )

        XCTAssertEqual(reset, "Resets in 20 days")
    }

    func testSettingsUsagePayloadDoesNotInferBillingReset() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startISO = formatter.string(from: Date())

        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          },
          "billing": {
            "currentPeriodStart": "\(startISO)"
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(payload, sourceURL: "https://www.cursor.com/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertNil(snapshot.resetDisplayValue)
    }

    func testParsesBillingResetOnlyFromBillingPageText() {
        let calendar = Calendar.current
        let resetDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17))!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 28))!
        let text = """
        Billing
        Pro+
        Next billing date
        June 17, 2026
        """

        let reset = CursorDashboardParser.parseBillingReset(
            from: text,
            sourceURL: CursorDashboardParser.billingPageURL,
            referenceDate: reference
        )

        XCTAssertEqual(reset, DisplayFormatting.resetInDays(until: resetDate, from: reference))
    }

    func testParsesConnectAPIUsagePayload() {
        let endDate = Calendar.current.date(byAdding: .day, value: 9, to: Date())!
        let endMs = String(Int(endDate.timeIntervalSince1970 * 1000))

        let payload = """
        {
          "billingCycleEnd": "\(endMs)",
          "planUsage": {
            "totalPercentUsed": 15.48,
            "autoPercentUsed": 5.6,
            "apiPercentUsed": 46.44,
            "limit": 40000,
            "remaining": 16778
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Cursor Plan")
        XCTAssertEqual(snapshot.totalUsedPercent, 15.48, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 5.6, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 46.44, accuracy: 0.01)

        let reset = snapshot.secondaryMetrics.first { $0.title == "Reset" }
        XCTAssertEqual(reset?.value, "Resets in 9 days")
    }

    func testParsesConnectAPIPlanInfoPayload() {
        let payload = """
        {
          "planInfo": {
            "planName": "Pro+",
            "billingCycleEnd": "1771077734000"
          },
          "planUsage": {
            "totalPercentUsed": 13,
            "autoPercentUsed": 4,
            "apiPercentUsed": 48
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Included in Pro+")
    }

    func testParsesSpendingDashboardDOMWithAutoComposerLabels() {
        let text = """
        Included in Pro+
        Total
        13%
        4% Auto + Composer and 48% API used
        """

        let result = CursorDashboardParser.parseDOMText(
            text,
            sourceURL: "https://cursor.com/dashboard/spending"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 4, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 48, accuracy: 0.01)
    }

    func testParsesCursorDashboardProxyUsagePayload() {
        let payload = """
        {
          "billingCycleEnd": "1771077734000",
          "planUsage": {
            "totalPercentUsed": 15.48,
            "autoPercentUsed": 58.0,
            "apiPercentUsed": 1.0
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://cursor.com/api/dashboard/get-current-period-usage"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.totalUsedPercent, 15.48, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 58, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 1, accuracy: 0.01)
    }

    func testIgnoresMisleadingAPIPercentagesOutsideIncludedSection() {
        let text = """
        On-demand usage
        59% API
        Included in Pro+
        Total
        13%
        58% Auto + Composer and 1% API used
        """

        let result = CursorDashboardParser.parseDOMText(
            text,
            sourceURL: "https://cursor.com/dashboard/spending"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.autoUsedPercent, 58, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 1, accuracy: 0.01)
    }

    func testRejectsUnrelatedJSONWithoutPlanUsage() {
        let payload = """
        {
          "usageEventsDisplay": [
            { "model": "gpt-4", "apiPercentUsed": 59, "totalCents": 1234 }
          ]
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://cursor.com/api/dashboard/get-aggregated-usage-events"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testParsesDOMTextFixture() {
        let text = """
        Included in Pro+
        Total
        13%
        4% Auto and 48% API used
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://www.cursor.com/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 4, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 48, accuracy: 0.01)
        XCTAssertEqual(snapshot.connectionState, .connected)
    }

    func testParsesJSONPayloadFixture() {
        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(payload, sourceURL: "https://www.cursor.com/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 4, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 48, accuracy: 0.01)
    }

    func testRejectsPartialDashboardData() {
        let text = """
        Included in Pro+
        Total
        13%
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://www.cursor.com/settings")

        XCTAssertEqual(result, .noMatch)
    }

    func testDetectsAuthenticationPage() {
        let text = """
        Sign in to Cursor
        Continue with GitHub
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://auth.cursor.com/login")

        XCTAssertEqual(result, .authRequired)
    }

    func testDoesNotTreatAuthSubrequestPayloadAsExpiredSession() {
        let payload = """
        {
          "provider": "auth0",
          "screen_hint": "continue with github"
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://www.cursor.com/api/auth/session"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testRejectsUsageShapedPayloadsFromNonCursorHosts() {
        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "autoUsedPercent": 0.04,
            "apiUsedPercent": 0.48
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://example.com/api/usage"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testTreatsNormalAuthRedirectNavigationErrorsAsBenign() {
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let frameLoadInterrupted = NSError(domain: "WebKitErrorDomain", code: 102)
        let hostFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)

        XCTAssertTrue(CursorWebViewScraper.isBenignNavigationError(cancelled))
        XCTAssertTrue(CursorWebViewScraper.isBenignNavigationError(frameLoadInterrupted))
        XCTAssertFalse(CursorWebViewScraper.isBenignNavigationError(hostFailure))
    }
}
