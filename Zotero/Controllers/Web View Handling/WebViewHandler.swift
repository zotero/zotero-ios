//
//  WebViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

protocol WebViewProvider: AnyObject {
    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView
}

protocol WebViewChallengePresenter: AnyObject {
    func showBrowserChallenge(in webView: WKWebView, cancelled: @escaping () -> Void, finished: @escaping () -> Void, presented: @escaping () -> Void)
    func dismissBrowserChallenge(in webView: WKWebView, completion: @escaping () -> Void)
}

class WebViewHandler: NSObject {
    enum Error: Swift.Error {
        case webViewMissing
        case urlMissingTranslators
    }

    private enum InitializationState {
        case initialized
        case inProgress
        case failed(Swift.Error)
    }

    struct BrowserChallenge {
        struct Cookie {
            let host: String
            let name: String
        }

        let match: String
        let successCookie: Cookie
        let challengeURL: (URL) -> URL
        let shouldUsePlainUserAgent: Bool
    }

    /// Matches desktop's default HTTP retry budget, including Retry-After waits.
    struct HTTPRetryState {
        private var totalDelay: TimeInterval = 0
        private var backoffDelay: TimeInterval = 2.5

        mutating func nextDelay(statusCode: Int, retryAfter: String?) -> TimeInterval? {
            guard statusCode == 429 || (500..<600).contains(statusCode) else { return nil }
            let delay: TimeInterval
            if statusCode == 429 || statusCode == 503,
               let retryAfter,
               let seconds = Int(retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)) {
                delay = TimeInterval(max(seconds, 1))
            } else {
                delay = backoffDelay
                backoffDelay *= 2
            }
            guard totalDelay + delay <= 7.5 else {
                DDLogInfo("WebViewHandler: HTTP retry skipped status=\(statusCode) requestedWait=\(delay)s accumulatedWait=\(totalDelay)s budget=7.5s")
                return nil
            }
            totalDelay += delay
            return delay
        }
    }

    /// Waits used by HTTP retries and browser challenges.
    struct Timing {
        var challengeClearanceTimeout: RxTimeInterval = .seconds(60)
        var challengeSettleTimeout: RxTimeInterval = .seconds(3)
        var challengeCookiePollInterval: RxTimeInterval = .milliseconds(250)
        /// Scales HTTP retry waits without changing the retry budget.
        var httpRetryDelayScale: Double = 1

        static let mainApp = Timing()
        /// The cookie store observer is the primary clearance signal, so the share extension polls only as an infrequent backup.
        static let shareExtension = Timing(challengeCookiePollInterval: .seconds(5))
    }

    private final class HTTPRequestContext {
        let request: URLRequest
        let headers: [String: String]
        let successCodes: [Int]
        let retriesServerErrors: Bool
        var retryState = HTTPRetryState()
        var attemptCount = 0
        var task: URLSessionDataTask?
        var retryTimer: Disposable?

        init(request: URLRequest, headers: [String: String], successCodes: [Int], retriesServerErrors: Bool) {
            self.request = request
            self.headers = headers
            self.successCodes = successCodes
            self.retriesServerErrors = retriesServerErrors
        }

        deinit {
            task?.cancel()
            retryTimer?.dispose()
        }
    }

    final class ChallengeCookieStoreObserver: NSObject, WKHTTPCookieStoreObserver {
        private let onChange: () -> Void

        init(onChange: @escaping () -> Void) {
            self.onChange = onChange
            super.init()
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            onChange()
        }
    }

    private final class ClearanceContext: NSObject, WKNavigationDelegate {
        enum Phase {
            case hidden
            case awaitingPresentation
            case visible
        }

        let webView: WKWebView
        let cookieStore: WKHTTPCookieStore
        let challenge: BrowserChallenge
        let url: URL
        let completion: (Bool) -> Void
        let startTime = Date()
        var presenter: WebViewChallengePresenter?
        var phase: Phase = .hidden
        var initialCookieValue: String?
        var observer: ChallengeCookieStoreObserver?
        var urlObservation: NSKeyValueObservation?
        var settleTimer: Disposable?
        var timeoutTimer: Disposable?
        var cookiePollTimer: Disposable?
        var hasCommittedPage = false
        /// Whether the current page has committed, with no newer navigation in progress.
        var didCommitNavigation = false
        var restartSettleTimer: (() -> Void)?
        var navigationFailed: (() -> Void)?

        init(webView: WKWebView, challenge: BrowserChallenge, url: URL, completion: @escaping (Bool) -> Void) {
            self.webView = webView
            cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            self.challenge = challenge
            self.url = url
            self.completion = completion
            super.init()
        }

        func stopObserving() {
            if let observer {
                cookieStore.remove(observer)
            }
            observer = nil
            urlObservation = nil
            settleTimer?.dispose()
            timeoutTimer?.dispose()
            cookiePollTimer?.dispose()
            webView.navigationDelegate = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // The page is about to change, so wait for the next page to commit before settling.
            didCommitNavigation = false
            settleTimer?.dispose()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            hasCommittedPage = true
            didCommitNavigation = true
            restartSettleTimer?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            navigationFailed?()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Swift.Error) {
            guard (error as NSError).code != NSURLErrorCancelled else {
                // A cancelled navigation that nothing replaced leaves the previous page in place, so let that page settle again.
                if hasCommittedPage, !webView.isLoading {
                    didCommitNavigation = true
                    restartSettleTimer?()
                }
                return
            }
            navigationFailed?()
        }
    }

    private let session: URLSession

    private weak var webView: WKWebView?
    weak var webViewProvider: WebViewProvider?
    var challengePresenter: WebViewChallengePresenter?
    let timing: Timing
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    var receivedMessageHandler: ((String, Any) -> Void)?
    // Cookies, User-Agent and Referrer from original website are stored and added to requests in `sendRequest(with:)`.
    private(set) var cookies: String?
    private(set) var userAgent: String?
    private(set) var referer: String?
    private(set) var browserUserAgent: String?
    private var initializationState: BehaviorRelay<InitializationState>
    private let disposeBag: DisposeBag
    private var activeRequests: [Int: HTTPRequestContext] = [:]
    private var activeChallenges: [Int: ClearanceContext]
    private var attemptedChallenges: Set<String>
    private static let webKitPrefix = "AppleWebKit/"
    private static let safariVersionPrefix = "Mobile Safari/"

    // MARK: - Lifecycle

    init(webView: WKWebView, javascriptHandlers: [String]?, timing: Timing = .mainApp) {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        storage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always

        session = URLSession(configuration: configuration)
        self.webView = webView
        self.timing = timing
        initializationState = BehaviorRelay(value: .inProgress)
        disposeBag = DisposeBag()
        activeChallenges = [:]
        attemptedChallenges = []

        super.init()

        webView.navigationDelegate = self
        var userAgent = ""
        if let webViewUserAgent = webView.value(forKey: "userAgent") as? String {
            userAgent = webViewUserAgent + " Version/" + UIDevice.current.systemVersion
            if let safariVersion = webViewUserAgent.components(separatedBy: " ")
                .first(where: { $0.starts(with: Self.webKitPrefix) })?
                .replacingOccurrences(of: Self.webKitPrefix, with: Self.safariVersionPrefix) {
                userAgent += " " + safariVersion
            }
        }
        browserUserAgent = userAgent.isEmpty ? nil : userAgent
        webView.customUserAgent = "\(userAgent) Zotero_iOS/\(DeviceInfoProvider.versionString ?? "")-\(DeviceInfoProvider.buildString ?? "")"

        javascriptHandlers?.forEach { handler in
            webView.configuration.userContentController.removeScriptMessageHandler(forName: handler)
            webView.configuration.userContentController.add(self, name: handler)
        }

#if DEBUG
        webView.isInspectable = true
#endif
        initializeWebView()
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                DDLogInfo("WebViewHandler: initialization succeeded")
                self?.initializationState.accept(.initialized)
            }, onFailure: { [weak self] error in
                DDLogInfo("WebViewHandler: initialization failed - \(error)")
                self?.initializationState.accept(.failed(error))
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Actions

    /// Method to be overriden by subclasses. Default implementation just assumes web view is already initialized.
    func initializeWebView() -> Single<()> {
        return .just(())
    }

    func performAfterInitialization() -> Single<()> {
        return initializationState.filter { state in
            switch state {
            case .inProgress:
                return false

            case .initialized, .failed:
                return true
            }
        }
        .first()
        .flatMap { state -> Single<()> in
            switch state {
            case .failed(let error):
                return .error(error)

            case .initialized:
                return .just(())

            case .inProgress, .none:
                // Should never happen.
                return .never()
            }
        }
    }

    func set(cookies: String?, userAgent: String?, referrer: String?) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.referer = referrer
    }

    func load(fileUrl: URL) -> Single<()> {
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
        return createWebLoadedSingle()
    }

    func load(webUrl: URL) -> Single<()> {
        guard webView != nil else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        let request = URLRequest(url: webUrl)
        // Share extension started crashing when `load()` was called immediately, a little delay fixed the crash (##616)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.webView?.load(request)
        }
        return createWebLoadedSingle()
    }

    func call(javascript: String) -> Single<Any> {
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        return webView.call(javascript: javascript)
    }

    func sendMessaging(response payload: [String: Any], for messageId: Int) {
        let script = "Zotero.Messaging.receiveResponse('\(messageId)', \(WebViewEncoder.encodeAsJSONForJavascript(payload)));"
        inMainThread { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func sendHttpResponse(data: Data?, statusCode: Int, url: URL?, successCodes: [Int], headers: [AnyHashable: Any], for messageId: Int) {
        let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""
        sendHttpResponse(responseText: responseText, statusCode: statusCode, url: url, isSuccess: isSuccess, headers: headers, for: messageId)
    }

    func sendHttpResponse(responseText: String, statusCode: Int, url: URL?, isSuccess: Bool, headers: [AnyHashable: Any], for messageId: Int) {
        var payload: [String: Any]
        if isSuccess {
            payload = ["status": statusCode, "responseText": responseText, "headers": headers, "url": url?.absoluteString ?? ""]
        } else {
            payload = ["error": ["status": statusCode, "responseText": responseText] as [String: Any]]
        }

        sendMessaging(response: payload, for: messageId)
    }

    func sendMessaging(error: String, for messageId: Int) {
        sendMessaging(response: ["error": ["message": error]], for: messageId)
    }

    /// Create single which is fired when webview loads a resource or fails.
    private func createWebLoadedSingle() -> Single<()> {
        return .create { [weak self] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    func removeFromSuperviewAsynchronously() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            activeRequests.removeAll()
            session.invalidateAndCancel()
            tearDownActiveChallenges(completePendingRequests: false)
            webDidLoad = nil
            guard let webView else { return }
            webView.navigationDelegate = nil
            webView.stopLoading()
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.removeFromSuperview()
            self.webView = nil
        }
    }

    // MARK: - Browser Challenges

    func browserChallenge(for url: URL, statusCode: Int, headers: [AnyHashable: Any], responseText: String) -> BrowserChallenge? {
        return nil
    }

    func didDetect(browserChallenge: BrowserChallenge, url: URL?) {}

    func shouldUsePlainUserAgent(for url: URL) -> Bool {
        return false
    }

    func additionalCookieNames(for url: URL) -> Set<String> {
        return ["cf_clearance"]
    }

    func resetBrowserChallenges() {
        attemptedChallenges = []
        tearDownActiveChallenges(completePendingRequests: true)
    }

    // MARK: - HTTP Requests

    /// Sends HTTP request based on options. Sends back response with HTTP response to `webView`.
    /// - parameter options: Options for HTTP request.
    func sendRequest(with options: [String: Any], for messageId: Int) throws {
        guard let urlString = options["url"] as? String,
              let url = URL(string: urlString) ?? urlString.removingPercentEncoding.flatMap({ $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init) }),
              let method = options["method"] as? String else {
            DDLogInfo("Incorrect URL request from javascript")
            DDLogInfo("\(options)")

            let data = "Incorrect URL request from javascript".data(using: .utf8)
            sendHttpResponse(data: data, statusCode: -1, url: nil, successCodes: [200], headers: [:], for: messageId)
            return
        }

        guard !urlString.contains("repo/code/undefined") else {
            DDLogError("WebViewHandler: Undefined call, translator missing.")

            // Received undefined translator repo call, which happens only when translation doesn't have proper translator available and just gets stuck, so we just force this error here.
            throw Error.urlMissingTranslators
        }

        let originalHeaders = (options["headers"] as? [String: String]) ?? [:]
        let body = options["body"] as? String
        let timeout = (options["timeout"] as? Double).flatMap({ $0 / 1000 }) ?? 60
        let successCodes = (options["successCodes"] as? [Int]) ?? []
        // Like desktop's `errorDelayMax: 0`, which disables retrying 429 and 5xx responses.
        let retriesServerErrors = (options["errorDelayMax"] as? Double) != 0

        DDLogInfo("WebViewHandler: send request to \(url.absoluteString)")

        let host = url.host(percentEncoded: false) ?? ""
        session.set(cookies: cookies, domain: host)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body?.data(using: .utf8)
        request.timeoutInterval = timeout

        let context = HTTPRequestContext(request: request, headers: originalHeaders, successCodes: successCodes, retriesServerErrors: retriesServerErrors)
        activeRequests[messageId] = context
        sendRequest(context: context, messageId: messageId)
    }

    private func sendRequest(context: HTTPRequestContext, messageId: Int) {
        guard activeRequests[messageId] === context, let url = context.request.url else { return }
        let host = url.host(percentEncoded: false) ?? ""
        addAdditionalCookies(for: url, host: host, existingHeaders: context.headers) { [weak self, weak context] headers in
            guard let self, let context, activeRequests[messageId] === context else { return }
            var request = context.request
            applyHeaders(to: &request, headers: headers, url: url)
            context.attemptCount += 1
            let hasTurnstileCookie = request.value(forHTTPHeaderField: "Cookie")?.contains("turnstile_passed=") == true
            DDLogInfo("WebViewHandler: HTTP attempt messageId=\(messageId) attempt=\(context.attemptCount) hasTurnstileCookie=\(hasTurnstileCookie) url=\(url.absoluteString)")
            context.task = session.dataTask(with: request) { [weak self, weak context] data, response, error in
                DispatchQueue.main.async { [weak self, weak context] in
                    guard let self, let context, activeRequests[messageId] === context else { return }
                    context.task = nil
                    if let response = response as? HTTPURLResponse {
                        handleResponse(data: data, response: response, context: context, messageId: messageId)
                    } else {
                        DDLogWarn("WebViewHandler: HTTP request failed messageId=\(messageId) attempt=\(context.attemptCount) error=\(error?.localizedDescription ?? "unknown error")")
                        activeRequests.removeValue(forKey: messageId)
                        sendHttpResponse(data: (error?.localizedDescription ?? "unknown error").data(using: .utf8), statusCode: -1, url: nil, successCodes: context.successCodes, headers: [:], for: messageId)
                    }
                }
            }
            context.task?.resume()
        }
    }

    private func applyHeaders(to request: inout URLRequest, headers: [String: String], url: URL?) {
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        if headers["User-Agent"] == nil {
            if let url, shouldUsePlainUserAgent(for: url), let browserUserAgent {
                request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            } else if let userAgent {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
        }
        if headers["Referer"] == nil, let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
    }

    private func handleResponse(data: Data?, response: HTTPURLResponse, context: HTTPRequestContext, messageId: Int) {
        let statusCode = response.statusCode
        let isSuccess = context.successCodes.isEmpty ? 200..<300 ~= statusCode : context.successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        DDLogInfo("WebViewHandler: HTTP response messageId=\(messageId) attempt=\(context.attemptCount) status=\(statusCode) accepted=\(isSuccess) retryAfter=\(retryAfter ?? "none")")
        if !isSuccess, context.retriesServerErrors, let delay = context.retryState.nextDelay(statusCode: statusCode, retryAfter: retryAfter) {
            DDLogInfo("WebViewHandler: HTTP retry scheduled messageId=\(messageId) status=\(statusCode) delay=\(delay)s url=\(context.request.url?.absoluteString ?? "-")")
            context.retryTimer = Single<Int>.timer(.milliseconds(Int(delay * timing.httpRetryDelayScale * 1000)), scheduler: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self, weak context] _ in
                    guard let self, let context else { return }
                    context.retryTimer = nil
                    sendRequest(context: context, messageId: messageId)
                })
            return
        }

        guard !isSuccess,
              let responseURL = response.url,
              let challenge = browserChallenge(for: responseURL, statusCode: statusCode, headers: response.allHeaderFields, responseText: responseText) else {
            activeRequests.removeValue(forKey: messageId)
            sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
            return
        }

        guard !attemptedChallenges.contains(challenge.match) else {
            DDLogInfo("WebViewHandler: browser fallback already attempted messageId=\(messageId) status=\(statusCode) match=\(challenge.match); returning HTTP response")
            activeRequests.removeValue(forKey: messageId)
            sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
            return
        }
        attemptedChallenges.insert(challenge.match)
        let challengeURL = challenge.challengeURL(responseURL)
        DDLogInfo("WebViewHandler: detected browser fallback messageId=\(messageId) status=\(statusCode) match=\(challenge.match) url=\(challengeURL.absoluteString)")
        didDetect(browserChallenge: challenge, url: challengeURL)
        clear(challenge: challenge, at: challengeURL, for: messageId) { [weak self, weak context] retry in
            guard let self, let context, activeRequests[messageId] === context else { return }
            guard retry else {
                DDLogWarn("WebViewHandler: browser fallback ended without retry messageId=\(messageId) match=\(challenge.match)")
                activeRequests.removeValue(forKey: messageId)
                sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
                return
            }
            DDLogInfo("WebViewHandler: retrying after browser fallback messageId=\(messageId) match=\(challenge.match); resetting HTTP retry budget")
            // Desktop starts a new HTTP request, with its own retry budget, after browser clearance.
            context.retryState = HTTPRetryState()
            sendRequest(context: context, messageId: messageId)
        }
    }

    private func clear(challenge: BrowserChallenge, at url: URL, for messageId: Int, completion: @escaping (Bool) -> Void) {
        guard let webView else {
            DDLogWarn("WebViewHandler: cannot clear challenge — main web view is gone")
            completion(false)
            return
        }
        guard let webViewProvider else {
            DDLogWarn("WebViewHandler: cannot clear challenge — no webViewProvider set")
            completion(false)
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = webView.configuration.websiteDataStore
        let challengeWebView = webViewProvider.addWebView(configuration: configuration)
        challengeWebView.customUserAgent = challenge.shouldUsePlainUserAgent ? browserUserAgent : webView.customUserAgent
#if DEBUG
        challengeWebView.isInspectable = true
#endif
        let context = ClearanceContext(webView: challengeWebView, challenge: challenge, url: url, completion: completion)
        activeChallenges[messageId] = context
        let successCookie = challenge.successCookie
        context.cookieStore.getCookie(host: successCookie.host, name: successCookie.name) { [weak self, weak context] initialCookie in
            guard let self, let context, activeChallenges[messageId] === context else { return }
            context.initialCookieValue = initialCookie?.value
            DDLogInfo("WebViewHandler: challenge clearance started messageId=\(messageId) url=\(url.absoluteString)")

            let observer = ChallengeCookieStoreObserver { [weak self] in
                self?.checkHiddenChallengeCookie(messageId: messageId)
            }
            context.observer = observer
            context.cookieStore.add(observer)
            startHiddenChallengeTimeout(messageId: messageId, context: context)
            context.cookiePollTimer = Observable<Int>.interval(timing.challengeCookiePollInterval, scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    self?.checkHiddenChallengeCookie(messageId: messageId)
                })

            // Match desktop: give each location change three seconds to settle before showing the browser. Like desktop, count from
            // when a page commits, since the URL changes as soon as a navigation starts, before the page has loaded.
            context.restartSettleTimer = { [weak self, weak context] in
                guard let self, let context else { return }
                restartChallengeSettleTimer(messageId: messageId, context: context)
            }
            // Same-document URL changes (e.g. pushState) don't commit a new page, so they restart the wait while the committed page
            // is current. A URL change from a navigation that hasn't committed yet is ignored.
            context.urlObservation = challengeWebView.observe(\.url, options: [.new]) { [weak self, weak context] webView, _ in
                guard let self, let context, context.didCommitNavigation, webView.url != nil else { return }
                restartChallengeSettleTimer(messageId: messageId, context: context)
            }
            context.navigationFailed = { [weak self] in
                self?.finishHiddenChallenge(messageId: messageId)
            }
            challengeWebView.navigationDelegate = context
            challengeWebView.load(URLRequest(url: url))
        }
    }

    private func restartChallengeSettleTimer(messageId: Int, context: ClearanceContext) {
        guard context.phase == .hidden, challengePresenter != nil else { return }
        context.settleTimer?.dispose()
        context.settleTimer = Single<Int>.timer(timing.challengeSettleTimeout, scheduler: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.finishHiddenChallenge(messageId: messageId)
            })
    }

    private func startHiddenChallengeTimeout(messageId: Int, context: ClearanceContext) {
        context.timeoutTimer?.dispose()
        context.timeoutTimer = Single<Int>.timer(timing.challengeClearanceTimeout, scheduler: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                DDLogWarn("WebViewHandler: challenge clearance timeout fired messageId=\(messageId)")
                self?.finishHiddenChallenge(messageId: messageId)
            })
    }

    private func checkHiddenChallengeCookie(messageId: Int) {
        readChallengeClearance(messageId: messageId, expectedPhase: .hidden) { [weak self] _, cleared in
            guard cleared else { return }
            self?.finishClearance(messageId: messageId, success: true)
        }
    }

    private func finishHiddenChallenge(messageId: Int) {
        readChallengeClearance(messageId: messageId, expectedPhase: .hidden) { [weak self] context, cleared in
            guard let self else { return }
            if cleared {
                finishClearance(messageId: messageId, success: true)
            } else {
                showChallenge(messageId: messageId, context: context)
            }
        }
    }

    private func finishVisibleChallenge(messageId: Int) {
        readChallengeClearance(messageId: messageId, expectedPhase: .visible) { [weak self] _, cleared in
            if !cleared {
                DDLogWarn("WebViewHandler: challenge cookie absent or unchanged after visible challenge messageId=\(messageId)")
            }
            self?.finishClearance(messageId: messageId, success: cleared)
        }
    }

    private func readChallengeClearance(messageId: Int, expectedPhase: ClearanceContext.Phase, completion: @escaping (ClearanceContext, Bool) -> Void) {
        guard let context = activeChallenges[messageId], context.phase == expectedPhase else { return }
        let successCookie = context.challenge.successCookie
        context.cookieStore.getCookie(host: successCookie.host, name: successCookie.name) { [weak self, weak context] cookie in
            // Ignore cookie reads from a challenge or phase that has already ended.
            guard let self, let context, activeChallenges[messageId] === context, context.phase == expectedPhase else { return }
            let cleared = cookie.map({ !$0.value.isEmpty && $0.value != context.initialCookieValue }) ?? false
            if cleared {
                DDLogInfo("WebViewHandler: challenge cookie changed messageId=\(messageId)")
            }
            completion(context, cleared)
        }
    }

    private func showChallenge(messageId: Int, context: ClearanceContext) {
        guard let challengePresenter else {
            finishClearance(messageId: messageId, success: false)
            return
        }
        DDLogInfo("WebViewHandler: showing browser challenge messageId=\(messageId) match=\(context.challenge.match)")
        context.presenter = challengePresenter
        context.phase = .awaitingPresentation
        context.stopObserving()
        challengePresenter.showBrowserChallenge(in: context.webView, cancelled: { [weak self] in
            self?.finishClearance(messageId: messageId, success: false)
        }, finished: { [weak self] in
            self?.finishVisibleChallenge(messageId: messageId)
        }, presented: { [weak self, weak context] in
            guard let self, let context, activeChallenges[messageId] === context else { return }
            context.phase = .visible
            // Load in the visible browser, retaining its cookies and user agent.
            context.webView.load(URLRequest(url: context.url))
        })
    }

    private func finishClearance(messageId: Int, success: Bool) {
        guard let context = activeChallenges.removeValue(forKey: messageId) else { return }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(context.startTime))
        DDLogInfo("WebViewHandler: browser fallback finished messageId=\(messageId) match=\(context.challenge.match) shouldRetry=\(success) elapsed=\(elapsed)s")
        disposeChallenge(context) {
            context.completion(success)
        }
    }

    private func disposeChallenge(_ context: ClearanceContext, completion: @escaping () -> Void) {
        context.stopObserving()
        context.webView.stopLoading()
        let removeWebView = {
            DispatchQueue.main.async {
                context.webView.removeFromSuperview()
                completion()
            }
        }
        if context.phase != .hidden, let presenter = context.presenter {
            presenter.dismissBrowserChallenge(in: context.webView, completion: removeWebView)
        } else {
            removeWebView()
        }
    }

    private func addAdditionalCookies(for url: URL, host: String, existingHeaders: [String: String], completion: @escaping ([String: String]) -> Void) {
        let names = additionalCookieNames(for: url)
        guard !names.isEmpty, let webView else { return completion(existingHeaders) }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getCookies(host: host, names: names) { matchingCookies in
            guard !matchingCookies.isEmpty else { return completion(existingHeaders) }
            var cookieString = matchingCookies.map({ "\($0.name)=\($0.value)" }).joined(separator: "; ")
            var headers = existingHeaders
            if let existingCookie = headers["Cookie"], !existingCookie.isEmpty {
                cookieString = existingCookie + "; " + cookieString
            }
            headers["Cookie"] = cookieString
            completion(headers)
        }
    }

    private func tearDownActiveChallenges(completePendingRequests: Bool) {
        let contexts = Array(activeChallenges.values)
        activeChallenges.removeAll()
        for context in contexts {
            disposeChallenge(context) {
                if completePendingRequests {
                    context.completion(false)
                }
            }
        }
    }
}

extension WebViewHandler: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for javascript to load
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.webDidLoad?(.success(()))
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        DDLogError("WebViewHandler: did fail - \(error)")
        webDidLoad?(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Swift.Error) {
        DDLogError("WebViewHandler: did fail provisional navigation - \(error)")
        webDidLoad?(.failure(error))
    }
}

/// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
/// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
extension WebViewHandler: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        inMainThread {
            self.receivedMessageHandler?(message.name, message.body)
        }
    }
}
