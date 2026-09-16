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

    private struct ClearanceContext {
        let webView: WKWebView
        let observer: ChallengeCookieStoreObserver
        let cookieStore: WKHTTPCookieStore
        let clearanceDisposeBag: DisposeBag
        let startTime: Date
    }

    private let session: URLSession

    private weak var webView: WKWebView?
    weak var webViewProvider: WebViewProvider?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    var receivedMessageHandler: ((String, Any) -> Void)?
    // Cookies, User-Agent and Referrer from original website are stored and added to requests in `sendRequest(with:)`.
    private(set) var cookies: String?
    private(set) var userAgent: String?
    private(set) var referer: String?
    private(set) var browserUserAgent: String?
    private var initializationState: BehaviorRelay<InitializationState>
    private let disposeBag: DisposeBag
    private var activeChallenges: [Int: ClearanceContext]
    private var attemptedChallenges: Set<String>
    private static let webKitPrefix = "AppleWebKit/"
    private static let safariVersionPrefix = "Mobile Safari/"
    private static let challengeClearanceTimeout: RxTimeInterval = .seconds(60)
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
            guard let self else { return }
            tearDownActiveChallenges()
            guard let webView else { return }
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.removeFromSuperview()
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
        tearDownActiveChallenges()
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

        addAdditionalCookies(for: url, host: host, existingHeaders: originalHeaders) { [weak self] mergedHeaders in
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

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !attemptedChallenges.contains(challenge.match) else {
                    sendHttpResponse(responseText: responseText, statusCode: statusCode, url: response.url, isSuccess: isSuccess, headers: response.allHeaderFields, for: messageId)
                    return
                }
                attemptedChallenges.insert(challenge.match)
                let challengeURL = challenge.challengeURL(responseURL)
                DDLogInfo("WebViewHandler: detected browser challenge at \(responseURL.absoluteString); clearing at \(challengeURL.absoluteString)")
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
                    addAdditionalCookies(for: responseURL, host: host, existingHeaders: originalHeaders) { [weak self] retryHeaders in
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
                    DDLogInfo("WebViewHandler: challenge clearance backup polling fired messageId=\(messageId)")
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
        }
    }

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

    private func tearDownActiveChallenges() {
        let contexts = Array(activeChallenges.values)
        activeChallenges.removeAll()
        DispatchQueue.main.async {
            for context in contexts {
                context.cookieStore.remove(context.observer)
                context.webView.stopLoading()
                context.webView.removeFromSuperview()
            }
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
