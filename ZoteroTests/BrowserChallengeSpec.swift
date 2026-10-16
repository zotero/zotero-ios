//
//  BrowserChallengeSpec.swift
//  ZoteroTests
//
//  Created by Miltiadis Vasilakis on 13/10/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

@testable import Zotero

import UIKit
import WebKit

import Nimble
import OHHTTPStubs
import OHHTTPStubsSwift
import Quick

final class BrowserChallengeSpec: QuickSpec {
    override class func spec() {
        describe("HTTP retry budget") {
            it("backs off for 429 and server errors, stopping after 7.5 seconds of waits") {
                for status in [429, 500, 503] {
                    var retries = WebViewHandler.HTTPRetryState()
                    expect(retries.nextDelay(statusCode: status, retryAfter: nil)).to(equal(2.5))
                    expect(retries.nextDelay(statusCode: status, retryAfter: nil)).to(equal(5))
                    expect(retries.nextDelay(statusCode: status, retryAfter: nil)).to(beNil())
                }
            }

            it("shares the budget between Retry-After and backoff") {
                var retries = WebViewHandler.HTTPRetryState()
                expect(retries.nextDelay(statusCode: 429, retryAfter: "3")).to(equal(3))
                expect(retries.nextDelay(statusCode: 503, retryAfter: nil)).to(equal(2.5))
                expect(retries.nextDelay(statusCode: 429, retryAfter: "2")).to(equal(2))
                expect(retries.nextDelay(statusCode: 429, retryAfter: "1")).to(beNil())
            }

            it("bounds repeated zero Retry-After values and rejects waits beyond the budget") {
                var retries = WebViewHandler.HTTPRetryState()
                for _ in 0..<7 {
                    expect(retries.nextDelay(statusCode: 429, retryAfter: "0")).to(equal(1))
                }
                expect(retries.nextDelay(statusCode: 429, retryAfter: "0")).to(beNil())
                retries = WebViewHandler.HTTPRetryState()
                expect(retries.nextDelay(statusCode: 429, retryAfter: "8")).to(beNil())
            }

            it("uses backoff for invalid Retry-After and ignores the header on other server errors") {
                var retries = WebViewHandler.HTTPRetryState()
                expect(retries.nextDelay(statusCode: 429, retryAfter: "invalid")).to(equal(2.5))
                expect(retries.nextDelay(statusCode: 500, retryAfter: "1")).to(equal(5))
            }

            it("does not retry other HTTP statuses") {
                for status in [200, 400, 403, 404] {
                    var retries = WebViewHandler.HTTPRetryState()
                    expect(retries.nextDelay(statusCode: status, retryAfter: "1")).to(beNil())
                }
            }
        }

        describe("WorldCat challenge detection") {
            let apiURL = URL(string: "https://search.worldcat.org/api/search?q=bn%3A9780262033848")!

            it("detects a Turnstile block on the WorldCat search API") {
                let challenge = LookupWebViewHandler.turnstileChallenge(for: apiURL, statusCode: 403, responseText: "{\"turnstile_required\":true}")
                expect(challenge?.match).to(equal("search.worldcat.org"))
                expect(challenge?.successCookie.host).to(equal("search.worldcat.org"))
                expect(challenge?.successCookie.name).to(equal("turnstile_passed"))
                expect(challenge?.shouldUsePlainUserAgent).to(beTrue())
            }

            it("clears the challenge on the user-facing search page with the same query") {
                let challenge = LookupWebViewHandler.turnstileChallenge(for: apiURL, statusCode: 403, responseText: "{\"turnstile_required\":true}")
                expect(challenge?.challengeURL(apiURL).absoluteString).to(equal("https://search.worldcat.org/search?q=bn%3A9780262033848"))
                let otherURL = URL(string: "https://search.worldcat.org/title/123")!
                expect(challenge?.challengeURL(otherURL)).to(equal(otherURL))
            }

            it("matches the host and the block marker case-insensitively") {
                let url = URL(string: "https://Search.WorldCat.org/api/search?q=isbn")!
                let challenge = LookupWebViewHandler.turnstileChallenge(for: url, statusCode: 403, responseText: "TURNSTILE_REQUIRED")
                expect(challenge?.match).to(equal("search.worldcat.org"))
            }

            it("ignores other statuses, responses and hosts") {
                expect(LookupWebViewHandler.turnstileChallenge(for: apiURL, statusCode: 429, responseText: "turnstile_required")).to(beNil())
                expect(LookupWebViewHandler.turnstileChallenge(for: apiURL, statusCode: 403, responseText: "Forbidden")).to(beNil())
                let otherHost = URL(string: "https://www.worldcat.org/api/search?q=isbn")!
                expect(LookupWebViewHandler.turnstileChallenge(for: otherHost, statusCode: 403, responseText: "turnstile_required")).to(beNil())
            }
        }

        describe("browser challenge clearance") {
            var provider: ChallengeTestWebViewProvider!
            var handler: ChallengeTestWebViewHandler!
            let cookie = HTTPCookie(properties: [.domain: "challenge.example", .path: "/", .name: "turnstile_passed", .value: "cleared"])!
            let options: [String: Any] = ["url": "https://challenge.example/api/search", "method": "GET", "headers": ["Cookie": "wc_tkn=original"]]

            beforeEach {
                provider = ChallengeTestWebViewProvider()
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                let webView = provider.addWebView(configuration: configuration)
                // Shorter waits keep the suite fast. The settle wait still leaves room for a hidden page to set its cookie first.
                let timing = WebViewHandler.Timing(challengeSettleTimeout: .milliseconds(500), challengeCookiePollInterval: .milliseconds(20), httpRetryDelayScale: 0.1)
                handler = ChallengeTestWebViewHandler(webView: webView, javascriptHandlers: [], timing: timing)
                handler.webViewProvider = provider
                handler.challengePresenter = provider
                stub(condition: isHost("challenge.example")) { request in
                    let cleared = request.value(forHTTPHeaderField: "Cookie")?.contains("turnstile_passed=cleared") == true
                    return HTTPStubsResponse(data: Data((cleared ? "success" : "turnstile_required").utf8), statusCode: cleared ? 200 : 403, headers: nil)
                }
            }

            afterEach {
                handler?.resetBrowserChallenges()
                provider.webViews.forEach { $0.stopLoading() }
                provider.webViews = []
                handler = nil
                provider = nil
                HTTPStubs.removeAllStubs()
            }

            it("retries a transient rate limit without opening a browser") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    let count = recorder.record(request)
                    return HTTPStubsResponse(data: Data(), statusCode: count == 1 ? 429 : 200, headers: ["Retry-After": "1"])
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { _, _, _, _ in fail("A transient rate limit should resolve without a browser") }
                    handler.onResponse = { status in
                        expect(status).to(equal(200))
                        expect(recorder.count).to(equal(2))
                        expect(recorder.requests.last?.value(forHTTPHeaderField: "Cookie")).to(contain("wc_tkn=original"))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("also retries a rate limit after hidden challenge clearance") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    let count = recorder.record(request)
                    let status: Int32 = count == 1 ? 403 : (count == 2 ? 429 : 200)
                    return HTTPStubsResponse(data: Data(), statusCode: status, headers: ["Retry-After": "1"])
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onPageLoad = { webView in
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                    }
                    provider.onShow = { _, _, _, _ in fail("A transient post-challenge rate limit should resolve without a browser") }
                    handler.onResponse = { status in
                        expect(status).to(equal(200))
                        expect(recorder.count).to(equal(3))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("returns a rate limit beyond the retry budget without opening a browser") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    recorder.record(request)
                    return HTTPStubsResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "300"])
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { _, _, _, _ in fail("A rate limit must not open a challenge browser") }
                    handler.onResponse = { status in
                        expect(status).to(equal(429))
                        expect(recorder.count).to(equal(1))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("does not reopen the browser when a resolved challenge is followed by a rate limit") {
                let recorder = RequestRecorder()
                var presentationCount = 0
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    let count = recorder.record(request)
                    return HTTPStubsResponse(data: Data(), statusCode: count == 1 ? 403 : 429, headers: ["Retry-After": "300"])
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { webView, cancelled, finished, presented in
                        presentationCount += 1
                        guard presentationCount == 1 else {
                            fail("A rate limit after challenge clearance must not reopen the browser")
                            cancelled()
                            return
                        }
                        presented()
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie, completionHandler: finished)
                    }
                    handler.onResponse = { status in
                        expect(status).to(equal(429))
                        expect(recorder.count).to(equal(2))
                        expect(presentationCount).to(equal(1))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("cancels pending retries on permanent removal") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                waitUntil(timeout: .seconds(5)) { done in
                    stub(condition: isHost("challenge.example")) { request in
                        let count = recorder.record(request)
                        if count == 1 {
                            // Remove well before the scaled 500ms retry wait ends, then check after it would have fired.
                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                                handler.removeFromSuperviewAsynchronously()
                                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(900)) {
                                    expect(recorder.count).to(equal(1))
                                    done()
                                }
                            }
                        }
                        return HTTPStubsResponse(data: Data(), statusCode: 429, headers: ["Retry-After": "5"])
                    }
                    handler.onResponse = { _ in fail("A removed request must not deliver a response") }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("returns a rate limit immediately when errorDelayMax is 0") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    let count = recorder.record(request)
                    return HTTPStubsResponse(data: Data(), statusCode: count == 1 ? 429 : 200, headers: ["Retry-After": "1"])
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { _, _, _, _ in fail("A rate limit must not open a challenge browser") }
                    handler.onResponse = { status in
                        expect(status).to(equal(429))
                        expect(recorder.count).to(equal(1))
                        done()
                    }
                    var noRetryOptions = options
                    // JS numbers arrive as NSNumber, which casts to Double. A Swift Int literal wouldn't.
                    noRetryOptions["errorDelayMax"] = 0.0
                    try! handler.sendRequest(with: noRetryOptions, for: 1)
                }
            }

            it("respects explicit success codes instead of retrying or presenting") {
                let recorder = RequestRecorder()
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    recorder.record(request)
                    return HTTPStubsResponse(data: Data(), statusCode: 429, headers: nil)
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { _, _, _, _ in fail("An accepted status should not open a browser") }
                    handler.onResponse = { status in
                        expect(status).to(equal(429))
                        expect(recorder.count).to(equal(1))
                        done()
                    }
                    var acceptedOptions = options
                    acceptedOptions["successCodes"] = [429]
                    try! handler.sendRequest(with: acceptedOptions, for: 1)
                }
            }

            it("retries when the hidden page clears the challenge without a presenter") {
                handler.challengePresenter = nil
                waitUntil(timeout: .seconds(10)) { done in
                    provider.onPageLoad = { webView in
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                    }
                    provider.onShow = { _, _, _, _ in
                        fail("An automatically cleared challenge should stay hidden")
                    }
                    handler.onResponse = { status in
                        expect(status).to(equal(200))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("waits for Finish and dismissal before retrying with the new cookie and original headers") {
                let recorder = RequestRecorder()
                var dismissed = false
                HTTPStubs.removeAllStubs()
                stub(condition: isHost("challenge.example")) { request in
                    let count = recorder.record(request)
                    return HTTPStubsResponse(data: Data("response".utf8), statusCode: count == 1 ? 403 : 200, headers: nil)
                }
                waitUntil(timeout: .seconds(5)) { done in
                    provider.onShow = { webView, _, finished, presented in
                        presented()
                        // An active challenge must dismiss through the presenter that opened it.
                        handler.challengePresenter = nil
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                            // Give a hidden-phase cookie check time to run, which must not retry while the browser is visible.
                            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                                expect(recorder.count).to(equal(1))
                                expect(dismissed).to(beFalse())
                                finished()
                            }
                        }
                    }
                    provider.onDismiss = { completion in
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                            expect(recorder.count).to(equal(1))
                            dismissed = true
                            completion()
                        }
                    }
                    handler.onResponse = { status in
                        expect(status).to(equal(200))
                        expect(dismissed).to(beTrue())
                        expect(recorder.count).to(equal(2))
                        expect(recorder.requests.last?.value(forHTTPHeaderField: "Cookie")).to(contain("wc_tkn=original", "turnstile_passed=cleared"))
                        expect(recorder.requests.last?.value(forHTTPHeaderField: "User-Agent")).to(equal(provider.webViews.last?.customUserAgent))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("rejects a stale cookie and completes cancellation only once") {
                var responseCount = 0
                waitUntil(timeout: .seconds(10)) { done in
                    provider.onShow = { _, cancelled, _, presented in
                        presented()
                        cancelled()
                        cancelled()
                    }
                    handler.onResponse = { status in
                        responseCount += 1
                        expect(status).to(equal(403))
                        done()
                    }
                    // A pre-existing cookie must not be treated as a newly cleared challenge.
                    let staleCookie = HTTPCookie(properties: [.domain: "challenge.example", .path: "/", .name: "turnstile_passed", .value: "stale"])!
                    provider.webViews[0].configuration.websiteDataStore.httpCookieStore.setCookie(staleCookie) {
                        try! handler.sendRequest(with: options, for: 1)
                    }
                }
                expect(responseCount).to(equal(1))
            }

            it("dismisses a pending presentation on reset and ignores its late callback") {
                waitUntil(timeout: .seconds(10)) { done in
                    provider.onShow = { _, _, _, presented in
                        handler.resetBrowserChallenges()
                        presented()
                    }
                    handler.onResponse = { status in
                        expect(status).to(equal(403))
                        done()
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }

            it("does not retain the handler through pending request callbacks") {
                weak var releasedHandler = handler
                try! handler.sendRequest(with: options, for: 1)
                handler = nil
                expect(releasedHandler).to(beNil())
            }

            it("discards the pending response on permanent removal even while the handler is retained") {
                var responseCount = 0
                waitUntil(timeout: .seconds(10)) { done in
                    handler.onResponse = { _ in responseCount += 1 }
                    provider.onShow = { _, cancelled, _, presented in
                        handler.removeFromSuperviewAsynchronously()
                        DispatchQueue.main.async {
                            presented()
                            cancelled()
                        }
                    }
                    provider.onDismiss = { completion in
                        completion()
                        DispatchQueue.main.async {
                            expect(responseCount).to(equal(0))
                            done()
                        }
                    }
                    try! handler.sendRequest(with: options, for: 1)
                }
            }
        }

        describe("challenge presentation lifetime") {
            it("does not present after the lookup has ended") {
                let lookupController = UIViewController()
                let presenter = WebViewChallengePresentationController(lookupViewController: lookupController) { completion in
                    completion(false)
                }
                let webView = WKWebView()
                var cancelled = false
                presenter.showBrowserChallenge(in: webView, cancelled: { cancelled = true }, finished: {}, presented: {
                    fail("A completed lookup must not present a challenge")
                })
                expect(cancelled).to(beTrue())
                presenter.dismissBrowserChallenge(in: webView, completion: {})
            }

            it("ignores a deferred presentation after the challenge has been removed") {
                let lookupController = UIViewController()
                var reply: ((Bool) -> Void)?
                let presenter = WebViewChallengePresentationController(lookupViewController: lookupController) { completion in
                    reply = completion
                }
                let webView = WKWebView()
                var dismissed = false
                presenter.showBrowserChallenge(in: webView, cancelled: {
                    fail("A removed challenge must not deliver a late cancellation")
                }, finished: {}, presented: {
                    fail("A removed challenge must not be presented")
                })
                presenter.dismissBrowserChallenge(in: webView) { dismissed = true }
                expect(dismissed).to(beTrue())
                expect(reply).toNot(beNil())
                reply?(true)
                expect(lookupController.presentedViewController).to(beNil())
            }
        }
    }
}

/// Stub responses are built on a background queue, while expectations read the requests on the main queue.
private final class RequestRecorder {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int {
        return requests.count
    }

    /// Records the request and returns how many requests have been made, including this one.
    @discardableResult
    func record(_ request: URLRequest) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage.append(request)
        return storage.count
    }
}

private final class ChallengeTestWebViewHandler: WebViewHandler {
    var onResponse: ((Int) -> Void)?

    override func browserChallenge(for url: URL, statusCode: Int, headers: [AnyHashable: Any], responseText: String) -> BrowserChallenge? {
        guard statusCode == 403 else { return nil }
        return BrowserChallenge(match: "challenge.example", successCookie: .init(host: "challenge.example", name: "turnstile_passed"),
                                challengeURL: { _ in URL(string: "challenge-test://challenge.example/search")! }, shouldUsePlainUserAgent: true)
    }

    override func additionalCookieNames(for url: URL) -> Set<String> { ["turnstile_passed"] }
    override func shouldUsePlainUserAgent(for url: URL) -> Bool { true }

    override func sendHttpResponse(responseText: String, statusCode: Int, url: URL?, isSuccess: Bool, headers: [AnyHashable: Any], for messageId: Int) {
        DispatchQueue.main.async { [weak self] in self?.onResponse?(statusCode) }
    }
}

private final class ChallengeTestWebViewProvider: NSObject, WebViewProvider, WebViewChallengePresenter, WKURLSchemeHandler {
    var webViews: [WKWebView] = []
    var onShow: ((WKWebView, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> Void)?
    var onDismiss: ((@escaping () -> Void) -> Void)?
    var onPageLoad: ((WKWebView) -> Void)?

    func addWebView(configuration: WKWebViewConfiguration?) -> WKWebView {
        let configuration = configuration ?? WKWebViewConfiguration()
        configuration.setURLSchemeHandler(self, forURLScheme: "challenge-test")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webViews.append(webView)
        return webView
    }

    func showBrowserChallenge(in webView: WKWebView, cancelled: @escaping () -> Void, finished: @escaping () -> Void, presented: @escaping () -> Void) {
        onShow?(webView, cancelled, finished, presented)
    }

    func dismissBrowserChallenge(in webView: WKWebView, completion: @escaping () -> Void) {
        if let onDismiss {
            onDismiss(completion)
        } else {
            completion()
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let data = Data("<html><body>Challenge</body></html>".utf8)
        urlSchemeTask.didReceive(URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
        onPageLoad?(webView)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
