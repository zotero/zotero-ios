//
//  TranslationWebViewHandler.swift
//  ZShare
//
//  Created by Michal Rentka on 05/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class TranslationWebViewHandler {
    /// Actions that can be returned by this handler.
    /// - loadedItems: Items have been translated.
    /// - selectItem: Multiple items have been found on this website and the user needs to choose one.
    /// - reportProgress: Reports progress of translation.
    /// - saveAsWeb: Translation failed. Save as webpage item.
    enum Action {
        case loadedItems(data: [[String: Any]], cookies: String?, userAgent: String?, referrer: String?)
        case selectItem([(key: String, value: String)])
        case reportProgress(String)
    }

    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case request = "requestHandler"
        /// Handler used for passing translated items.
        case item = "itemResponseHandler"
        /// Handler used for item selection. Expects response (selected item).
        case itemSelection = "itemSelectionHandler"
        /// Handler used to indicate that all translators failed to save and should be saved as web page
        case saveAsWeb = "saveAsWebHandler"
        /// Handler used to report progress of translation
        case progress = "translationProgressHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindFile
        case incompatibleItem
        case javascriptCallMissingResult
        case noSuccessfulTranslators
        case webExtractionMissingJs
        case webExtractionMissingData
    }

    private let webViewHandler: WebViewHandler
    private let translatorsController: TranslatorsAndStylesController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Action>

    private var itemSelectionMessageId: Int?

    // MARK: - Lifecycle

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
        webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        disposeBag = DisposeBag()
        self.translatorsController = translatorsController
        observable = PublishSubject()

        webViewHandler.receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    // MARK: - Actions

    func loadWebData(from url: URL) -> Single<ExtensionViewModel.State.RawAttachment> {
        DDLogInfo("TranslationWebViewHandler: load web data")
        return webViewHandler.load(webUrl: url)
            .flatMap { _ -> Single<Any> in
                guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"), let script = try? String(contentsOf: url) else {
                    DDLogError("TranslationWebViewHandler: can't load extraction javascript")
                    return .error(Error.webExtractionMissingJs)
                }
                DDLogInfo("TranslationWebViewHandler: call data extraction js")
                return self.webViewHandler.call(javascript: script)
            }
            .flatMap { data -> Single<ExtensionViewModel.State.RawAttachment> in
                guard let payload = data as? [String: Any],
                      let isFile = payload["isFile"] as? Bool,
                      let cookies = payload["cookies"] as? String,
                      let userAgent = payload["userAgent"] as? String,
                      let referrer = payload["referrer"] as? String else {
                    DDLogError("TranslationWebViewHandler: extracted data missing response")
                    DDLogError("\(String(describing: data as? [String: Any]))")
                    return .error(Error.webExtractionMissingData)
                }

                if isFile, let contentType = payload["contentType"] as? String {
                    DDLogInfo("TranslationWebViewHandler: extracted file")
                    return .just(.remoteFileUrl(url: url, contentType: contentType, cookies: cookies, userAgent: userAgent, referrer: referrer))
                } else if let title = payload["title"] as? String, let html = payload["html"] as? String, let frames = payload["frames"] as? [String] {
                    DDLogInfo("TranslationWebViewHandler: extracted html")
                    return .just(.web(title: title, url: url, html: html, cookies: cookies, frames: frames, userAgent: userAgent, referrer: referrer))
                } else {
                    DDLogError("TranslationWebViewHandler: extracted data incompatible")
                    DDLogError("\(payload)")
                    return .error(Error.webExtractionMissingData)
                }
            }
    }

    /// Runs translation server against html content with cookies. Results are then provided through observable publisher.
    /// - parameter url: Original URL of shared website.
    /// - parameter title: Title of the shared website.
    /// - parameter html: HTML content of the shared website. Equals to javascript "document.documentElement.innerHTML".
    /// - parameter cookies: Cookies string from shared website. Equals to javacsript "document.cookie".
    /// - parameter frames: HTML content of frames contained in initial HTML document.
    func translate(url: URL, title: String, html: String, cookies: String, frames: [String], userAgent: String, referrer: String) {
        DDLogInfo("TranslationWebViewHandler: translate")
        webViewHandler.set(cookies: cookies, userAgent: userAgent, referrer: referrer)
        return loadIndex()
            .flatMap { _ -> Single<(String, String)> in
                return loadBundledFiles()
            }
            .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                return self.webViewHandler.call(javascript: "initSchemaAndDateFormats(\(encodedSchema), \(encodedDateFormats));")
            }
            .flatMap { _ -> Single<[RawTranslator]> in
                DDLogInfo("TranslationWebViewHandler: load translators")
                return self.translatorsController.translators(matching: url.absoluteString)
            }
            .flatMap { translators -> Single<Any> in
                DDLogInfo("TranslationWebViewHandler: encode translators")
                let encodedTranslators = WebViewEncoder.encodeAsJSONForJavascript(translators)
                return self.webViewHandler.call(javascript: "initTranslators(\(encodedTranslators));")
            }
            .flatMap({ _ -> Single<Any> in
                DDLogInfo("TranslationWebViewHandler: call translate js")
                let encodedHtml = WebViewEncoder.encodeForJavascript(html.data(using: .utf8))
                let jsonFramesData = try? JSONSerialization.data(withJSONObject: frames, options: .fragmentsAllowed)
                let encodedFrames = jsonFramesData.flatMap({ WebViewEncoder.encodeForJavascript($0) }) ?? "''"
                return self.webViewHandler.call(javascript: "translate('\(url.absoluteString)', \(encodedHtml), \(encodedFrames));")
            })
            .subscribe(onFailure: { [weak self] error in
                DDLogError("TranslationWebViewHandler: translation failed - \(error)")
                self?.observable.on(.error(error))
            })
            .disposed(by: disposeBag)

        func loadIndex() -> Single<()> {
            guard let indexUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "translation") else {
                return .error(Error.cantFindFile)
            }
            return webViewHandler.load(fileUrl: indexUrl)
        }

        func loadBundledFiles() -> Single<(String, String)> {
            return .create { subscriber in
                guard let schemaUrl = Bundle.main.url(forResource: "schema", withExtension: "json", subdirectory: "Bundled"), let schemaData = try? Data(contentsOf: schemaUrl) else {
                    DDLogError("TranslationWebViewHandler: can't load schema json")
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }

                guard let dateFormatsUrl = Bundle.main.url(forResource: "dateFormats", withExtension: "json", subdirectory: "translation/translate/modules/utilities/resource"),
                      let dateFormatData = try? Data(contentsOf: dateFormatsUrl)
                else {
                    DDLogError("TranslationWebViewHandler: can't load dateFormats json")
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }

                let encodedSchema = WebViewEncoder.encodeForJavascript(schemaData)
                let encodedFormats = WebViewEncoder.encodeForJavascript(dateFormatData)

                DDLogInfo("TranslationWebViewHandler: loaded bundled files")

                subscriber(.success((encodedSchema, encodedFormats)))

                return Disposables.create()
            }
        }
    }

    /// Sends selected item back to `webView`.
    /// - parameter item: Selected item by the user.
    func selectItem(_ item: (String, String)) {
        guard let messageId = itemSelectionMessageId else { return }
        let (key, value) = item
        webViewHandler.sendMessaging(response: [key: value], for: messageId)
        itemSelectionMessageId = nil
    }

    // MARK: - Messaging

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .request:
            guard let body = body as? [String: Any], let messageId = body["messageId"] as? Int else {
                DDLogError("TranslationWebViewHandler: request missing body - \(body)")
                return
            }

            if let options = body["payload"] as? [String: Any] {
                do {
                    try webViewHandler.sendRequest(with: options, for: messageId)
                } catch let error {
                    DDLogError("TranslationWebViewHandler: send request error \(error)")
                    observable.on(.error(Error.noSuccessfulTranslators))
                }
            } else {
                DDLogError("TranslationWebViewHandler: request missing payload - \(body)")
                webViewHandler.sendMessaging(error: "HTTP request missing payload", for: messageId)
            }

        case .itemSelection:
            guard let body = body as? [String: Any], let messageId = body["messageId"] as? Int else {
                DDLogError("TranslationWebViewHandler: item selection missing body - \(body)")
                return
            }

            if let payload = body["payload"] as? [[String]] {
                itemSelectionMessageId = messageId

                var sortedDictionary: [(String, String)] = []
                for data in payload {
                    guard data.count == 2 else { continue }
                    sortedDictionary.append((data[0], data[1]))
                }

                observable.on(.next(.selectItem(sortedDictionary)))
            } else {
                DDLogError("TranslationWebViewHandler: item selection missing payload - \(body)")
                webViewHandler.sendMessaging(error: "Item selection missing payload", for: messageId)
            }

        case .item:
            if let info = body as? [[String: Any]] {
                observable.on(.next(.loadedItems(data: info, cookies: webViewHandler.cookies, userAgent: webViewHandler.userAgent, referrer: webViewHandler.referer)))
            } else {
                DDLogError("TranslationWebViewHandler: got incompatible body - \(body)")
                observable.on(.error(Error.incompatibleItem))
            }

        case .progress:
            if let progress = body as? String {
                if progress == "item_selection" {
                    observable.on(.next(.reportProgress(L10n.Shareext.Translation.itemSelection)))
                } else if progress.starts(with: "translating_with_") {
                    let name = progress[progress.index(progress.startIndex, offsetBy: 17)..<progress.endIndex]
                    observable.on(.next(.reportProgress(L10n.Shareext.Translation.translatingWith(name))))
                } else {
                    observable.on(.next(.reportProgress(progress)))
                }
            }

        case .saveAsWeb:
            observable.on(.error(Error.noSuccessfulTranslators))

        case .log:
            DDLogInfo("TranslationWebViewHandler: JSLOG - \(body)")
        }
    }
}
