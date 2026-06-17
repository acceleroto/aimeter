import Foundation
import WebKit

@MainActor
final class OpenAIWebViewScraper: NSObject {
    enum Mode {
        case interactive
        case background
    }

    let webView: WKWebView

    private let mode: Mode
    private let usagePageURL: URL
    private let initialURL: URL
    private let timeoutSeconds: TimeInterval
    private let contentController: WKUserContentController

    private var continuation: CheckedContinuation<ProviderUsageSnapshot, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var popupWebView: WKWebView?
    private var hasResolved = false
    private var pendingUsageSnapshot: ProviderUsageSnapshot?
    private var usageFallbackTask: Task<Void, Never>?

    init(mode: Mode, usagePageURL: URL, dataStore: WKWebsiteDataStore) {
        self.mode = mode
        self.usagePageURL = usagePageURL
        self.initialURL = mode == .interactive
            ? URL(string: "https://chatgpt.com")!
            : usagePageURL
        self.timeoutSeconds = mode == .interactive ? 180 : 25

        let contentController = WKUserContentController()
        self.contentController = contentController

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        contentController.addUserScript(
            WKUserScript(
                source: Self.networkInterceptorScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        contentController.addUserScript(
            WKUserScript(
                source: Self.openAILoginAssistantScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        contentController.add(self, name: Self.messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() async throws -> ProviderUsageSnapshot {
        if continuation != nil {
            throw ProviderUsageError.syncFailed("OpenAI load is already running.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = URLRequest(url: initialURL)
            webView.load(request)
            scheduleTimeout()
        }
    }

    func cancel() {
        resolve(.failure(ProviderUsageError.cancelled))
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            await self.handleTimeout()
        }
    }

    private func handleTimeout() async {
        await pollDOM()
        guard !hasResolved else {
            return
        }
        if pendingUsageSnapshot != nil {
            resolvePendingUsageSnapshot()
            return
        }

        let message: String
        switch mode {
        case .interactive:
            message = "OpenAI usage did not load. Finish sign-in and try again."
        case .background:
            message = "OpenAI usage was not found."
        }
        resolve(.failure(ProviderUsageError.syncFailed(message)))
    }

    private func startPollingDOM() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollDOM()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func stopPollingDOM() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollDOM() async {
        guard !hasResolved else {
            return
        }

        let script = """
        ({
          text: (() => {
            const bodyText = document.body ? document.body.innerText : "";
            const isAnalyticsPage = window.location.pathname.replace(/\\/+$/, "").toLowerCase()
              .endsWith("codex/cloud/settings/analytics");
            const visibleNodeText = (() => {
              if (!isAnalyticsPage || !document.body) {
                return "";
              }

              const values = [];
              const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                {
                  acceptNode: (node) => {
                    const value = (node.nodeValue || "").trim();
                    if (!value) {
                      return NodeFilter.FILTER_REJECT;
                    }

                    const parent = node.parentElement;
                    if (!parent) {
                      return NodeFilter.FILTER_REJECT;
                    }

                    const style = window.getComputedStyle(parent);
                    if (style.display === "none" || style.visibility === "hidden") {
                      return NodeFilter.FILTER_REJECT;
                    }

                    return NodeFilter.FILTER_ACCEPT;
                  }
                }
              );

              let node;
              while ((node = walker.nextNode()) && values.length < 300) {
                values.push((node.nodeValue || "").trim());
              }
              return values.join("\\n");
            })();
            const progressText = Array.from(document.querySelectorAll("[role='progressbar'], progress, [aria-valuenow]"))
              .map((element) => {
                const label = element.getAttribute("aria-label") || "";
                const value = Number(element.getAttribute("aria-valuenow") || element.value || 0);
                const max = Number(element.getAttribute("aria-valuemax") || element.max || 100) || 100;
                const percent = Math.max(0, Math.min(100, max > 0 ? (value / max) * 100 : value));
                let nearby = "";
                let current = element;
                for (let depth = 0; depth < 8 && current; depth += 1) {
                  const text = (current.innerText || "").trim();
                  if (
                    text.length > 0 &&
                    text.length < 600 &&
                    /5[- ]?hour|weekly|credits|usage limit|codex/i.test(text)
                  ) {
                    nearby = text;
                    break;
                  }
                  current = current.parentElement;
                }
                return [nearby, label, `${Math.round(percent * 10) / 10}% remaining`].filter(Boolean).join("\\n");
              })
              .join("\\n");
            return [
              bodyText,
              isAnalyticsPage ? visibleNodeText : "",
              isAnalyticsPage ? progressText : ""
            ].filter(Boolean).join("\\n");
          })(),
          url: window.location.href,
          signedInAppShell: (() => {
            const text = (document.body && document.body.innerText || "").toLowerCase();
            if (text.includes("log in") || text.includes("sign up") || text.includes("continue with google")) {
              return false;
            }

            const appShellSelectors = [
              "textarea",
              "[contenteditable='true']",
              "[role='textbox']",
              "[data-testid*='composer']",
              "[data-testid*='chat']"
            ];

            if (appShellSelectors.some((selector) => {
              try {
                return document.querySelector(selector);
              } catch (_) {
                return false;
              }
            })) {
              return true;
            }

            return text.includes("new chat")
              || text.includes("chatgpt")
              || text.includes("codex");
          })()
        })
        """

        do {
            guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
                return
            }

            let text = result["text"] as? String ?? ""
            let url = result["url"] as? String ?? webView.url?.absoluteString ?? usagePageURL.absoluteString
            let signedInAppShell = result["signedInAppShell"] as? Bool ?? false

            switch OpenAIDashboardParser.parseDOMText(text, sourceURL: url) {
            case .usage(let snapshot):
                handleParsedDOMSnapshot(
                    snapshot,
                    currentPageURL: url,
                    signedInAppShell: signedInAppShell
                )
            case .authRequired where mode == .background:
                resolve(.failure(ProviderUsageError.authExpired))
            case .noMatch
                where signedInAppShell
                    && OpenAIURLValidator.isAllowedOpenAIURLString(url)
                    && !OpenAIURLValidator.isAnalyticsURLString(url):
                if mode == .interactive {
                    webView.load(URLRequest(url: usagePageURL))
                } else {
                    resolve(.success(OpenAIDashboardParser.signedInSnapshot()))
                }
            case .authRequired, .noMatch:
                break
            }
        } catch {
            if mode == .background {
                resolve(.failure(ProviderUsageError.syncFailed("Failed reading OpenAI usage.")))
            }
        }
    }

    private func handleNetworkMessage(_ payload: [String: Any]) {
        guard !hasResolved else {
            return
        }

        let body = payload["body"] as? String ?? ""
        let sourceURL = payload["url"] as? String ?? webView.url?.absoluteString ?? usagePageURL.absoluteString
        guard OpenAIURLValidator.isAllowedOpenAIURLString(sourceURL) else {
            return
        }

        switch OpenAIDashboardParser.parseResponseBody(body, sourceURL: sourceURL) {
        case .usage(let snapshot):
            handleParsedNetworkSnapshot(
                snapshot,
                currentPageURL: webView.url?.absoluteString ?? usagePageURL.absoluteString
            )
        case .authRequired where mode == .background:
            resolve(.failure(ProviderUsageError.authExpired))
        case .authRequired, .noMatch:
            break
        }
    }

    private func isSignedInOnlySnapshot(_ snapshot: ProviderUsageSnapshot) -> Bool {
        snapshot.provider == .openai
            && snapshot.progressPercent == nil
            && snapshot.primaryMetric.title == "Status"
            && snapshot.primaryMetric.value == "Signed in"
    }

    private func handleParsedDOMSnapshot(
        _ snapshot: ProviderUsageSnapshot,
        currentPageURL: String,
        signedInAppShell: Bool
    ) {
        guard mode == .interactive else {
            if hasResetDetails(snapshot) || !OpenAIURLValidator.isAnalyticsURLString(currentPageURL) {
                resolve(.success(snapshot))
            } else {
                deferUsageSnapshot(snapshot)
            }
            return
        }

        guard OpenAIURLValidator.isAnalyticsURLString(currentPageURL) else {
            if signedInAppShell || isSignedInOnlySnapshot(snapshot) {
                webView.load(URLRequest(url: usagePageURL))
            }
            return
        }

        if isSignedInOnlySnapshot(snapshot) {
            return
        }

        guard snapshot.progressPercent != nil || hasCreditsOnlySnapshot(snapshot) else {
            deferUsageSnapshot(snapshot)
            return
        }

        guard hasResetDetails(snapshot) || hasCreditsOnlySnapshot(snapshot) else {
            deferUsageSnapshot(snapshot)
            return
        }

        resolve(.success(snapshot))
    }

    private func handleParsedNetworkSnapshot(_ snapshot: ProviderUsageSnapshot, currentPageURL: String) {
        guard mode == .interactive else {
            if hasResetDetails(snapshot) || snapshot.progressPercent != nil {
                resolve(.success(snapshot))
            } else {
                deferUsageSnapshot(snapshot)
            }
            return
        }

        guard OpenAIURLValidator.isAnalyticsURLString(currentPageURL) else {
            return
        }

        if isSignedInOnlySnapshot(snapshot) {
            return
        }

        guard snapshot.progressPercent != nil || hasCreditsOnlySnapshot(snapshot) else {
            deferUsageSnapshot(snapshot)
            return
        }

        guard hasResetDetails(snapshot) || hasCreditsOnlySnapshot(snapshot) else {
            deferUsageSnapshot(snapshot)
            return
        }

        resolve(.success(snapshot))
    }

    private func hasCreditsOnlySnapshot(_ snapshot: ProviderUsageSnapshot) -> Bool {
        snapshot.secondaryMetrics.contains { $0.title.caseInsensitiveCompare("Credits") == .orderedSame }
            && snapshot.progressPercent == nil
    }

    private func deferUsageSnapshot(_ snapshot: ProviderUsageSnapshot) {
        pendingUsageSnapshot = snapshot
        guard usageFallbackTask == nil else {
            return
        }

        usageFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.resolvePendingUsageSnapshot()
        }
    }

    private func resolvePendingUsageSnapshot() {
        guard !hasResolved, let pendingUsageSnapshot else {
            return
        }

        resolve(.success(pendingUsageSnapshot))
    }

    private func hasResetDetails(_ snapshot: ProviderUsageSnapshot) -> Bool {
        let metrics = [snapshot.primaryMetric] + snapshot.secondaryMetrics
        return metrics.contains { metric in
            let title = metric.title.lowercased()
            let value = metric.value.lowercased()
            return title.contains("reset") || value.contains("reset") || value.contains("resets")
        }
    }

    private func resolve(_ result: Result<ProviderUsageSnapshot, Error>) {
        guard !hasResolved else {
            return
        }

        hasResolved = true
        stopPollingDOM()
        timeoutTask?.cancel()
        timeoutTask = nil
        usageFallbackTask?.cancel()
        usageFallbackTask = nil
        pendingUsageSnapshot = nil
        webView.stopLoading()
        popupWebView?.stopLoading()
        popupWebView?.removeFromSuperview()
        popupWebView = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        contentController.removeScriptMessageHandler(forName: Self.messageHandlerName)

        switch result {
        case .success(let snapshot):
            continuation?.resume(returning: snapshot)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        continuation = nil
    }

    private static let messageHandlerName = "openAINetworkBridge"

    nonisolated static func isBenignNavigationError(_ error: Error) -> Bool {
        CursorWebViewScraper.isBenignNavigationError(error)
    }

    private static func isBlockedOAuthURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else {
            return false
        }

        return host == "accounts.google.com" || host.hasSuffix(".accounts.google.com")
            || host == "google.com" || host.hasSuffix(".google.com")
            || host == "appleid.apple.com" || host.hasSuffix(".apple.com")
    }

    private func showEmbeddedOAuthNotice() {
        let script = """
        (() => {
          const id = "aimeter-openai-login-notice";
          let notice = document.getElementById(id);
          if (!notice) {
            notice = document.createElement("div");
            notice.id = id;
            notice.style.cssText = [
              "position:fixed",
              "left:24px",
              "right:24px",
              "top:24px",
              "z-index:2147483647",
              "padding:14px 16px",
              "border-radius:12px",
              "background:#2f2115",
              "color:#fff7ed",
              "border:1px solid #f59e0b",
              "font:14px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
              "box-shadow:0 12px 32px rgba(0,0,0,.28)"
            ].join(";");
            document.documentElement.appendChild(notice);
          }
          notice.textContent = "Google and Apple sign-in are blocked inside embedded app login windows. Use email login here, then AIMeter can read your local OpenAI session.";
        })();
        """

        webView.evaluateJavaScript(script)
    }

    private static let networkInterceptorScript = """
    (() => {
      if (window.__aimeterOpenAIHookInstalled) {
        return;
      }
      window.__aimeterOpenAIHookInstalled = true;

      const maxLength = 50000;
      const allowedHosts = new Set(["chatgpt.com", "www.chatgpt.com"]);

      const allowedURL = (value) => {
        try {
          const url = new URL(value, window.location.href);
          return url.protocol === "https:" && allowedHosts.has(url.hostname.toLowerCase());
        } catch (_) {
          return false;
        }
      };

      const post = (payload) => {
        try {
          if (!allowedURL(payload.url || "")) {
            return;
          }
          window.webkit.messageHandlers.openAINetworkBridge.postMessage(payload);
        } catch (_) {}
      };

      const clip = (value) => {
        if (typeof value !== "string") {
          return "";
        }
        return value.length > maxLength ? value.slice(0, maxLength) : value;
      };

      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        try {
          const input = args[0];
          const requestURL = typeof input === "string" ? input : (input && input.url) || "";
          const url = response.url || requestURL;
          if (!allowedURL(url)) {
            return response;
          }
          const cloned = response.clone();
          const body = await cloned.text();
          post({ url, body: clip(body) });
        } catch (_) {}
        return response;
      };

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url) {
        this.__aimeterURL = url;
        return originalOpen.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function() {
        this.addEventListener("load", function() {
          try {
            const url = this.responseURL || this.__aimeterURL || "";
            if (!allowedURL(url)) {
              return;
            }
            const body = typeof this.responseText === "string" ? this.responseText : "";
            post({ url, body: clip(body) });
          } catch (_) {}
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """

    private static let openAILoginAssistantScript = """
    (() => {
      const noticeID = "aimeter-openai-email-login-notice";
      const styleID = "aimeter-openai-login-style";

      const installNotice = () => {
        if (document.getElementById(noticeID)) {
          return;
        }
        const notice = document.createElement("div");
        notice.id = noticeID;
        notice.textContent = "AIMeter tip: use email login for ChatGPT. Google and Apple sign-in are blocked in embedded app login windows.";
        notice.style.cssText = [
          "position:fixed",
          "left:24px",
          "right:24px",
          "top:24px",
          "z-index:2147483647",
          "padding:14px 16px",
          "border-radius:12px",
          "background:#172033",
          "color:#eff6ff",
          "border:1px solid #60a5fa",
          "font:14px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
          "box-shadow:0 12px 32px rgba(0,0,0,.28)"
        ].join(";");
        document.documentElement.appendChild(notice);
      };

      const installStyle = () => {
        if (document.getElementById(styleID)) {
          return;
        }
        const style = document.createElement("style");
        style.id = styleID;
        style.textContent = `
          [data-aimeter-hidden-oauth-login="true"] {
            display: none !important;
          }
        `;
        document.documentElement.appendChild(style);
      };

      const markOAuthLoginUnavailable = () => {
        const pageText = (document.body && document.body.innerText || "").toLowerCase();
        if (
          !pageText.includes("continue with google")
            && !pageText.includes("continue with apple")
            && !pageText.includes("log in")
        ) {
          return;
        }

        installNotice();
        installStyle();

        const candidates = Array.from(document.querySelectorAll("button, a, [role='button']"));
        for (const element of candidates) {
          const label = element.innerText || element.textContent || "";
          if (!/continue\\s+with\\s+(google|apple|microsoft)/i.test(label)) {
            continue;
          }

          element.dataset.aimeterHiddenOauthLogin = "true";
          element.setAttribute("aria-disabled", "true");
          element.setAttribute("title", "Use email login in AIMeter. OAuth is blocked in embedded app login windows.");
          element.addEventListener("click", (event) => {
            event.preventDefault();
            event.stopImmediatePropagation();
          }, true);
        }
      };

      markOAuthLoginUnavailable();

      if (!window.__aimeterOpenAILoginObserverInstalled) {
        window.__aimeterOpenAILoginObserverInstalled = true;
        new MutationObserver(markOAuthLoginUnavailable).observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      }
    })();
    """
}

@MainActor
extension OpenAIWebViewScraper: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if mode == .interactive, Self.isBlockedOAuthURL(navigationAction.request.url) {
            showEmbeddedOAuthNotice()
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if mode == .interactive {
            webView.evaluateJavaScript(Self.openAILoginAssistantScript)
        }
        startPollingDOM()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isBenignNavigationError(error), mode == .background else {
            return
        }

        resolve(.failure(ProviderUsageError.syncFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !Self.isBenignNavigationError(error), mode == .background else {
            return
        }

        resolve(.failure(ProviderUsageError.syncFailed(error.localizedDescription)))
    }
}

@MainActor
extension OpenAIWebViewScraper: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        if mode == .interactive, Self.isBlockedOAuthURL(navigationAction.request.url) {
            showEmbeddedOAuthNotice()
            return nil
        }

        popupWebView?.removeFromSuperview()

        let popupWebView = WKWebView(frame: webView.bounds, configuration: configuration)
        popupWebView.autoresizingMask = [.width, .height]
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self

        if let container = webView.superview {
            container.addSubview(popupWebView, positioned: .above, relativeTo: webView)
        } else {
            webView.addSubview(popupWebView)
        }

        self.popupWebView = popupWebView
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else {
            return
        }

        popupWebView?.removeFromSuperview()
        popupWebView = nil
        self.webView.load(URLRequest(url: usagePageURL))
    }
}

@MainActor
extension OpenAIWebViewScraper: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else {
            return
        }

        guard let payload = message.body as? [String: Any] else {
            return
        }

        handleNetworkMessage(payload)
    }
}
