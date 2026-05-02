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

    /// Per-host descriptor for a bot-protection challenge that can be cleared in a hidden web view.
    /// Subclasses return one from `browserChallenge(for:statusCode:headers:responseText:)` to opt-in.
    struct BrowserChallenge {
        struct Cookie {
            let host: String
            let name: String
        }

        /// Substring used to dedupe attempts within a translation/lookup operation.
        let match: String
        /// Cookie that signals successful clearance (e.g., `turnstile_passed` on `search.worldcat.org`).
        let successCookie: Cookie
        /// Optional URL transform from the failing request URL to the URL that runs the challenge
        /// (e.g., WorldCat's `/api/search` → `/search` because the API endpoint can't run Turnstile).
        let challengeURL: (URL) -> URL
        /// Whether the hidden web view and retry must use the plain Safari UA. Required for challenges
        /// whose cookie is HMAC-signed against the UA (Cloudflare Turnstile).
        let shouldUsePlainUserAgent: Bool
    }

    /// Lightweight `WKHTTPCookieStoreObserver` shim that forwards `cookiesDidChange(in:)` to a closure.
    /// Apple's protocol is `NSObjectProtocol`, so we need a class to subclass `NSObject`.
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

    /// Per-clearance state, keyed by messageId in `activeChallenges`. Owns the hidden web view, the cookie
    /// store observer, and Rx disposables for the timeout + backup poll so `finish(...)` can tear them all
    /// down atomically.
    private struct ClearanceContext {
        let webView: WKWebView
        let observer: ChallengeCookieStoreObserver
        let cookieStore: WKHTTPCookieStore
        let clearanceDisposeBag: DisposeBag
        let startTime: Date
    }

    private let session: URLSession

    private weak var webView: WKWebView?
    /// Source for hidden challenge web views. Set externally after init by code that already holds a provider
    /// (e.g., `IdentifierLookupController`). When nil, `clear(...)` fails fast — we don't fall back to a
    /// detached `WKWebView` since out-of-hierarchy web views can have their JS runtime deprioritized.
    weak var webViewProvider: WebViewProvider?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    var receivedMessageHandler: ((String, Any) -> Void)?
    // Cookies, User-Agent and Referrer from original website are stored and added to requests in `sendRequest(with:)`.
    private(set) var cookies: String?
    private(set) var userAgent: String?
    private(set) var referer: String?
    /// Plain Safari/WebKit UA without the `Zotero_iOS/...` suffix. Used for hidden challenge web views
    /// and for outgoing requests when `shouldUsePlainUserAgent(for:)` returns true.
    private(set) var browserUserAgent: String?
    private var initializationState: BehaviorRelay<InitializationState>
    private let disposeBag: DisposeBag
    private var activeChallenges: [Int: ClearanceContext]
    private var attemptedChallenges: Set<String>
    private static let webKitPrefix = "AppleWebKit/"
    private static let safariVersionPrefix = "Mobile Safari/"
    /// Budget for clearing a bot-protection challenge in a hidden web view. Decoupled from individual
    /// request timeouts because (a) translator-supplied timeouts are sized for "how long should the API
    /// call take," not "how long should challenge clearance take," and (b) cold first-visit Cloudflare +
    /// Turnstile + redirects can routinely run 10-20s. Once the success cookie is in the jar, follow-up
    /// requests bypass clearance entirely, so this budget only applies to the first session-cold hit.
    private static let challengeClearanceTimeout: RxTimeInterval = .seconds(60)
    /// Backup polling cadence during clearance. `WKHTTPCookieStoreObserver.cookiesDidChange(in:)` doesn't
    /// always fire for cookies set via HTTP `Set-Cookie` headers (e.g., WorldCat's Turnstile flow), so the
    /// observer alone can leave us waiting for the full timeout even after the cookie has landed. A slow
    /// background poll catches that case without making the happy path (observer fires) any noisier.
    private static let challengeCookiePollInterval: RxTimeInterval = .seconds(5)

    // MARK: - Lifecycle

    init(webView: WKWebView, javascriptHandlers: [String]?) {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        storage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always

        session = URLSession(configuration: configuration)
        self.webView = webView
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
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        let request = URLRequest(url: webUrl)
        // Share extension started crashing when `load()` was called immediately, a little delay fixed the crash (##616)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            webView.load(request)
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
            guard let self, let webView else { return }
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.removeFromSuperview()
        }
    }

    // MARK: - Browser Challenges

    /// Decide whether a non-success response is a bot challenge that can be cleared in a hidden web view.
    /// Subclasses override per-site; default returns nil so `sendRequest` behaves as before.
    func browserChallenge(for url: URL, statusCode: Int, headers: [AnyHashable: Any], responseText: String) -> BrowserChallenge? {
        return nil
    }

    /// Notification hook fired on the main thread when a challenge is detected, before clearance starts.
    /// Default no-op.
    func didDetect(browserChallenge: BrowserChallenge, url: URL?) {}

    /// Whether outgoing requests to `url` should send the plain Safari UA instead of the Zotero-tagged one.
    /// Required for hosts whose challenge cookie is HMAC-signed against the UA, where every request to that
    /// host (not just the retry) must use the same UA the cookie was earned under.
    /// Default returns false; subclasses override to register per-host opt-ins.
    func shouldUsePlainUserAgent(for url: URL) -> Bool {
        return false
    }

    /// Cookie names that should be bridged from the WK cookie store into outgoing URLSession requests for `url`.
    /// `WKHTTPCookieStore` and `URLSession`'s `HTTPCookieStorage` are separate jars, so once a challenge web
    /// view has earned a cookie like `turnstile_passed` we have to manually inject it on every translator HTTP
    /// call to that host. Otherwise a returning user with the cookie still in the WK store would still get a 403
    /// because the URLSession request never carries it. `cf_clearance` is bridged unconditionally and doesn't
    /// need to be listed here. Default returns empty.
    func additionalCookieNames(for url: URL) -> Set<String> {
        return []
    }

    /// Clears the per-handler dedupe set so subsequent requests can re-attempt clearance.
    /// Call at the start of each translation/lookup operation.
    func resetBrowserChallenges() {
        attemptedChallenges = []
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

        DDLogInfo("WebViewHandler: send request to \(url.absoluteString)")

        let host = url.host(percentEncoded: false) ?? ""
        session.set(cookies: cookies, domain: host)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body?.data(using: .utf8)
        request.timeoutInterval = timeout

        addCloudflareCookie(host: host, existingHeaders: originalHeaders) { [weak self] cfHeaders in
            guard let self else { return }
            addAdditionalCookies(for: url, host: host, existingHeaders: cfHeaders) { [weak self] mergedHeaders in
                guard let self else { return }
                applyHeaders(to: &request, headers: mergedHeaders, url: url)

                let task = session.dataTask(with: request) { [weak self] data, response, error in
                    guard let self else { return }
                    if let response = response as? HTTPURLResponse {
                        handleResponse(data: data, response: response, request: request, successCodes: successCodes, messageId: messageId)
                    } else if let error {
                        sendHttpResponse(data: error.localizedDescription.data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
                    } else {
                        sendHttpResponse(data: "unknown error".data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
                    }
                }
                task.resume()
            }
        }

        func applyHeaders(to request: inout URLRequest, headers: [String: String], url: URL?) {
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

        func handleResponse(data: Data?, response: HTTPURLResponse, request: URLRequest, successCodes: [Int], messageId: Int) {
            let statusCode = response.statusCode
            let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
            let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

            guard !isSuccess,
                  let responseURL = response.url,
                  let challenge = browserChallenge(for: responseURL, statusCode: statusCode, headers: response.allHeaderFields, responseText: responseText)
            else {
                sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
                return
            }

            // Move dedupe + clearance onto the main thread so `attemptedChallenges` and `activeChallengeWebViews`
            // are only touched there. Cookie store callbacks also fire on main.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !attemptedChallenges.contains(challenge.match) else {
                    sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
                    return
                }
                attemptedChallenges.insert(challenge.match)
                let challengeURL = challenge.challengeURL(responseURL)
                DDLogWarn("WebViewHandler: detected browser challenge at \(responseURL.absoluteString); clearing at \(challengeURL.absoluteString)")
                didDetect(browserChallenge: challenge, url: challengeURL)
                clear(challenge: challenge, at: challengeURL, for: messageId) { [weak self] success in
                    guard let self else { return }
                    guard success else {
                        DDLogWarn("WebViewHandler: browser challenge not cleared at \(challengeURL.absoluteString)")
                        sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
                        return
                    }
                    DDLogInfo("WebViewHandler: browser challenge cleared, retrying \(responseURL.absoluteString)")
                    var retryRequest = request
                    retryRequest.setValue(nil, forHTTPHeaderField: "Cookie")
                    addBrowserChallengeCookie(challenge.successCookie, host: host, existingHeaders: originalHeaders) { [weak self] retryHeaders in
                        guard let self else { return }
                        applyHeaders(to: &retryRequest, headers: retryHeaders, url: retryRequest.url)
                        let retryTask = session.dataTask(with: retryRequest) { [weak self] data, response, error in
                            guard let self else { return }
                            if let response = response as? HTTPURLResponse {
                                sendHttpResponse(data: data, statusCode: response.statusCode, url: response.url, successCodes: successCodes, headers: response.allHeaderFields, for: messageId)
                            } else if let error {
                                sendHttpResponse(data: error.localizedDescription.data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
                            } else {
                                sendHttpResponse(data: "unknown error".data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
                            }
                        }
                        retryTask.resume()
                    }
                }
            }
        }

        func addCloudflareCookie(host: String, existingHeaders: [String: String], completion: @escaping ([String: String]) -> Void) {
            guard let webView else { return completion(existingHeaders) }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getCloudflareCookies(host: host) { cloudflareCookies in
                guard !cloudflareCookies.isEmpty else { return completion(existingHeaders) }
                var cookieString = cloudflareCookies.map({ "\($0.name)=\($0.value)" }).joined(separator: "; ")
                var headers = existingHeaders
                if let existingCookie = headers["Cookie"], !existingCookie.isEmpty {
                    cookieString = existingCookie + "; " + cookieString
                }
                headers["Cookie"] = cookieString
                completion(headers)
            }
        }
    }

    /// Loads `url` in a hidden web view (provided by `webViewProvider`) that shares the default cookie jar
    /// with the main web view, observes the cookie store for changes, and calls `completion` once the
    /// `challenge.successCookie` appears with a value distinct from the one observed at start (a stale signed
    /// cookie wouldn't validate server-side), or with `false` after `Self.challengeClearanceTimeout` seconds elapse.
    /// Caller must be on the main thread.
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
        let challengeWebView = webViewProvider.addWebView(configuration: nil)
        challengeWebView.customUserAgent = challenge.shouldUsePlainUserAgent ? browserUserAgent : webView.customUserAgent
#if DEBUG
        challengeWebView.isInspectable = true
#endif
        let cookieStore = challengeWebView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getCookie(host: challenge.successCookie.host, name: challenge.successCookie.name) { [weak self] initialCookie in
            guard let self else { return }
            let initialValue = initialCookie?.value
            let startTime = Date()
            DDLogInfo("WebViewHandler: challenge clearance started messageId=\(messageId) url=\(url.absoluteString)")

            let observer = ChallengeCookieStoreObserver { [weak self] in
                self?.evaluateChallengeCookie(challenge: challenge, initialValue: initialValue, messageId: messageId, completion: completion)
            }
            cookieStore.add(observer)

            let clearanceDisposeBag = DisposeBag()
            Single<Int>.timer(Self.challengeClearanceTimeout, scheduler: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] _ in
                    DDLogWarn("WebViewHandler: challenge clearance timeout fired messageId=\(messageId)")
                    self?.evaluateChallengeCookie(challenge: challenge, initialValue: initialValue, messageId: messageId, completion: completion, isFinalCheck: true)
                })
                .disposed(by: clearanceDisposeBag)
            Observable<Int>.interval(Self.challengeCookiePollInterval, scheduler: MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    DDLogWarn("WebViewHandler: challenge clearance backup polling fired messageId=\(messageId)")
                    self?.evaluateChallengeCookie(challenge: challenge, initialValue: initialValue, messageId: messageId, completion: completion)
                })
                .disposed(by: clearanceDisposeBag)

            activeChallenges[messageId] = ClearanceContext(
                webView: challengeWebView,
                observer: observer,
                cookieStore: cookieStore,
                clearanceDisposeBag: clearanceDisposeBag,
                startTime: startTime
            )

            challengeWebView.load(URLRequest(url: url))
            // Catch the race where the cookie was set between the snapshot above and observer registration.
            evaluateChallengeCookie(challenge: challenge, initialValue: initialValue, messageId: messageId, completion: completion)
        }
    }

    /// Query the cookie store for `challenge.successCookie`. If present with a value different from
    /// `initialValue`, finish the clearance as success. If `isFinalCheck` is true (timeout fired) and the
    /// cookie still hasn't appeared, finish as failure. Otherwise no-op (wait for the next observer fire).
    private func evaluateChallengeCookie(challenge: BrowserChallenge, initialValue: String?, messageId: Int, completion: @escaping (Bool) -> Void, isFinalCheck: Bool = false) {
        guard let context = activeChallenges[messageId] else { return }
        let startTime = context.startTime
        context.cookieStore.getCookie(host: challenge.successCookie.host, name: challenge.successCookie.name) { [weak self] cookie in
            guard let self else { return }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startTime))
            if let cookie, cookie.value != initialValue {
                DDLogInfo("WebViewHandler: challenge cookie present messageId=\(messageId) elapsed=\(elapsed)s — succeeding")
                finishClearance(messageId: messageId, success: true, completion: completion)
            } else if isFinalCheck {
                let presence = cookie == nil ? "absent" : "value unchanged"
                DDLogWarn("WebViewHandler: challenge cookie \(presence) on final check messageId=\(messageId) elapsed=\(elapsed)s — failing")
                finishClearance(messageId: messageId, success: false, completion: completion)
            } else {
                let presence = cookie == nil ? "absent" : "value unchanged"
                DDLogInfo("WebViewHandler: challenge cookie check messageId=\(messageId) elapsed=\(elapsed)s presence=\(presence) — waiting")
            }
        }
    }

    /// Atomic completion: removes the context from `activeChallenges` (so subsequent observer fires no-op),
    /// removes the observer, cancels the timeout, and tears down the hidden web view.
    private func finishClearance(messageId: Int, success: Bool, completion: @escaping (Bool) -> Void) {
        guard let context = activeChallenges.removeValue(forKey: messageId) else { return }
        let elapsed = String(format: "%.2f", Date().timeIntervalSince(context.startTime))
        DDLogInfo("WebViewHandler: challenge clearance finished messageId=\(messageId) success=\(success) elapsed=\(elapsed)s")
        context.cookieStore.remove(context.observer)
        completion(success)
        DispatchQueue.main.async { [weak webView = context.webView] in
            webView?.removeFromSuperview()
        }
    }

    private func addBrowserChallengeCookie(_ cookie: BrowserChallenge.Cookie, host: String, existingHeaders: [String: String], completion: @escaping ([String: String]) -> Void) {
        guard let webView else { return completion(existingHeaders) }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getCookies(host: host, names: [cookie.name]) { matchingCookies in
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
}

extension WebViewHandler: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for javascript to load
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.webDidLoad?(.success(()))
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
