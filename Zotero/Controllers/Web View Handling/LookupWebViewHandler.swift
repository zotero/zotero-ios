//
//  LookupWebViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class LookupWebViewHandler {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for reporting new items.
        case items = "itemsHandler"
        /// Handler used for reporting failure - when no items were detected.
        case lookupFailed = "failureHandler"
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case request = "requestHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindFile
        case noSuccessfulTranslators
        case lookupFailed
    }

    private let webViewHandler: WebViewHandler
    private let translatorsController: TranslatorsAndStylesController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<[[String: Any]], Swift.Error>>

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
        self.translatorsController = translatorsController
        self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()

        self.webViewHandler.receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    func lookUp(identifier: String) {
        DDLogInfo("LookupWebViewHandler: translate")

        return self.loadIndex()
                   .flatMap { _ -> Single<(String, String)> in
                       return self.loadBundledFiles()
                   }
                   .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                       return self.webViewHandler.call(javascript: "initSchemaAndDateFormats(\(encodedSchema), \(encodedDateFormats));")
                   }
                   .flatMap { _ -> Single<[RawTranslator]> in
                       DDLogInfo("LookupWebViewHandler: load translators")
                       return self.translatorsController.translators()
                   }
                   .flatMap { translators -> Single<Any> in
                       DDLogInfo("LookupWebViewHandler: encode translators")
                       let encodedTranslators = WKWebView.encodeAsJSONForJavascript(translators)
                       return self.webViewHandler.call(javascript: "initTranslators(\(encodedTranslators));")
                   }
                   .flatMap({ _ -> Single<Any> in
                       DDLogInfo("LookupWebViewHandler: call translate js")
                       let encodedIdentifiers = WKWebView.encodeForJavascript(identifier.data(using: .utf8))
                       return self.webViewHandler.call(javascript: "lookup(\(encodedIdentifiers));")
                   })
                   .subscribe(onFailure: { [weak self] error in
                       DDLogError("WebViewHandler: translation failed - \(error)")
                       self?.observable.on(.next(.failure(error)))
                   })
                   .disposed(by: self.disposeBag)
    }

    private func loadIndex() -> Single<()> {
        guard let indexUrl = Bundle.main.url(forResource: "lookup", withExtension: "html", subdirectory: "translation") else {
            return Single.error(Error.cantFindFile)
        }
        return self.webViewHandler.load(fileUrl: indexUrl)
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

    private func process(body: Any) {
        guard let rawData = body as? [[String: Any]] else {
            self.observable.on(.next(.failure(Error.lookupFailed)))
            return
        }
        self.observable.on(.next(.success(rawData)))
    }

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .lookupFailed:
            self.observable.on(.next(.failure(Error.lookupFailed)))

        case .items:
            self.process(body: body)

        case .log:
            DDLogInfo("JSLOG: \(body)")

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
                    self.observable.on(.next(.failure(Error.noSuccessfulTranslators)))
                }
            } else {
                DDLogError("TranslationWebViewHandler: request missing payload - \(body)")
                self.webViewHandler.sendMessaging(error: "HTTP request missing payload", for: messageId)
            }
        }
    }
}
