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
        case loadedItems([[String: Any]])
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

    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var itemSelectionMessageId: Int?

    // MARK: - Lifecycle

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
        self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        self.disposeBag = DisposeBag()
        self.translatorsController = translatorsController
        self.observable = PublishSubject()

        self.webViewHandler.receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    // MARK: - Actions

    func loadWebData(from url: URL) -> Single<ExtensionViewModel.State.RawAttachment> {
        DDLogInfo("WebViewHandler: load web data")

        return self.webViewHandler.load(webUrl: url)
                   .flatMap({ _ -> Single<Any> in
                       guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"),
                             let script = try? String(contentsOf: url) else {
                           DDLogError("WebViewHandler: can't load extraction javascript")
                           return Single.error(Error.webExtractionMissingJs)
                       }
                       DDLogInfo("WebViewHandler: call data extraction js")
                       return self.webViewHandler.call(javascript: script)
                   })
                   .flatMap({ data -> Single<ExtensionViewModel.State.RawAttachment> in
                       guard let payload = data as? [String: Any],
                             let isFile = payload["isFile"] as? Bool else {
                           DDLogError("WebViewHandler: extracted data missing response")
                           DDLogError("\(data as? [String: Any])")
                           return Single.error(Error.webExtractionMissingData)
                       }

                       if isFile, let contentType = payload["contentType"] as? String {
                           DDLogInfo("WebViewHandler: extracted file")
                           return Single.just(.remoteFileUrl(url: url, contentType: contentType))
                       } else if let title = payload["title"] as? String,
                                 let html = payload["html"] as? String,
                                 let cookies = payload["cookies"] as? String,
                                 let frames = payload["frames"] as? [String] {
                           DDLogInfo("WebViewHandler: extracted html")
                           return Single.just(.web(title: title, url: url, html: html, cookies: cookies, frames: frames))
                       } else {
                           DDLogError("WebViewHandler: extracted data incompatible")
                           DDLogError("\(payload)")
                           return Single.error(Error.webExtractionMissingData)
                       }
                   })
    }

    /// Runs translation server against html content with cookies. Results are then provided through observable publisher.
    /// - parameter url: Original URL of shared website.
    /// - parameter title: Title of the shared website.
    /// - parameter html: HTML content of the shared website. Equals to javascript "document.documentElement.innerHTML".
    /// - parameter cookies: Cookies string from shared website. Equals to javacsript "document.cookie".
    /// - parameter frames: HTML content of frames contained in initial HTML document.
    func translate(url: URL, title: String, html: String, cookies: String, frames: [String]) {
        DDLogInfo("WebViewHandler: translate")

        self.webViewHandler.set(cookies: cookies)

        return self.loadIndex()
                   .flatMap { _ -> Single<(String, String)> in
                       return self.loadBundledFiles()
                   }
                   .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                       return self.webViewHandler.call(javascript: "initSchemaAndDateFormats(\(encodedSchema), \(encodedDateFormats));")
                   }
                   .flatMap { _ -> Single<[RawTranslator]> in
                       DDLogInfo("WebViewHandler: load translators")
                       return self.translatorsController.translators(matching: url.absoluteString)
                   }
                   .flatMap { translators -> Single<Any> in
                       DDLogInfo("WebViewHandler: encode translators")
                       let encodedTranslators = WKWebView.encodeAsJSONForJavascript(translators)
                       return self.webViewHandler.call(javascript: "initTranslators(\(encodedTranslators));")
                   }
                   .flatMap({ _ -> Single<Any> in
                       DDLogInfo("WebViewHandler: call translate js")
                       let encodedHtml = WKWebView.encodeForJavascript(html.data(using: .utf8))
                       let jsonFramesData = try? JSONSerialization.data(withJSONObject: frames, options: .fragmentsAllowed)
                       let encodedFrames = jsonFramesData.flatMap({ WKWebView.encodeForJavascript($0) }) ?? "''"
                       return self.webViewHandler.call(javascript: "translate('\(url.absoluteString)', \(encodedHtml), \(encodedFrames));")
                   })
                   .subscribe(onFailure: { [weak self] error in
                       DDLogError("WebViewHandler: translation failed - \(error)")
                       self?.observable.on(.error(error))
                   })
                   .disposed(by: self.disposeBag)
    }

    private func loadBundledFiles() -> Single<(String, String)> {
        return Single.create { subscriber in
            guard let schemaUrl = Bundle.main.url(forResource: "schema", withExtension: "json", subdirectory: "Bundled"),
                  let schemaData = try? Data(contentsOf: schemaUrl) else {
                DDLogError("WebViewHandler: can't load schema json")
                subscriber(.failure(Error.cantFindFile))
                return Disposables.create()
            }

            guard let dateFormatsUrl = Bundle.main.url(forResource: "dateFormats", withExtension: "json", subdirectory: "translation/translate/modules/utilities/resource"),
                  let dateFormatData = try? Data(contentsOf: dateFormatsUrl) else {
                DDLogError("WebViewHandler: can't load dateFormats json")
                subscriber(.failure(Error.cantFindFile))
                return Disposables.create()
            }

            let encodedSchema = WKWebView.encodeForJavascript(schemaData)
            let encodedFormats = WKWebView.encodeForJavascript(dateFormatData)

            DDLogInfo("WebViewHandler: loaded bundled files")

            subscriber(.success((encodedSchema, encodedFormats)))

            return Disposables.create()
        }
    }

    /// Sends selected item back to `webView`.
    /// - parameter item: Selected item by the user.
    func selectItem(_ item: (String, String)) {
        guard let messageId = self.itemSelectionMessageId else { return }
        let (key, value) = item
        self.webViewHandler.sendMessaging(response: [key: value], for: messageId)
        self.itemSelectionMessageId = nil
    }

    private func loadIndex() -> Single<()> {
        guard let indexUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "translation") else {
            return Single.error(Error.cantFindFile)
        }
        return self.webViewHandler.load(fileUrl: indexUrl)
    }

    // MARK: - Messaging

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .request:
            guard let body = body as? [String: Any],
                  let messageId = body["messageId"] as? Int else {
                DDLogError("TranslationWebViewHandler: request missing body - \(body)")
                return
            }

            if let options = body["payload"] as? [String: Any] {
                do {
                    try self.webViewHandler.sendRequest(with: options, for: messageId)
                } catch let error {
                    DDLogError("TranslationWebViewHandler: send request error \(error)")
                    self.observable.on(.error(Error.noSuccessfulTranslators))
                }
            } else {
                DDLogError("TranslationWebViewHandler: request missing payload - \(body)")
                self.webViewHandler.sendMessaging(error: "HTTP request missing payload", for: messageId)
            }

        case .itemSelection:
            guard let body = body as? [String: Any],
                  let messageId = body["messageId"] as? Int else {
                DDLogError("TranslationWebViewHandler: item selection missing body - \(body)")
                return
            }

            if let payload = body["payload"] as? [[String]] {
                self.itemSelectionMessageId = messageId

                var sortedDictionary: [(String, String)] = []
                for data in payload {
                    guard data.count == 2 else { continue }
                    sortedDictionary.append((data[0], data[1]))
                }

                self.observable.on(.next(.selectItem(sortedDictionary)))
            } else {
                DDLogError("TranslationWebViewHandler: item selection missing payload - \(body)")
                self.webViewHandler.sendMessaging(error: "Item selection missing payload", for: messageId)
            }

        case .item:
            if let info = body as? [[String: Any]] {
                self.observable.on(.next(.loadedItems(info)))
            } else {
                DDLogError("TranslationWebViewHandler: got incompatible body - \(body)")
                self.observable.on(.error(Error.incompatibleItem))
            }

        case .progress:
            if let progress = body as? String {
                if progress == "item_selection" {
                    self.observable.on(.next(.reportProgress(L10n.Shareext.Translation.itemSelection)))
                } else if progress.starts(with: "translating_with_") {
                    let name = progress[progress.index(progress.startIndex, offsetBy: 17)..<progress.endIndex]
                    self.observable.on(.next(.reportProgress(L10n.Shareext.Translation.translatingWith(name))))
                } else {
                    self.observable.on(.next(.reportProgress(progress)))
                }
            }

        case .saveAsWeb:
            self.observable.on(.error(Error.noSuccessfulTranslators))

        case .log:
            DDLogInfo("JSLOG: \(body)")
        }
    }
}
