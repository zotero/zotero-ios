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
import RxCocoa
import RxSwift

final class LookupWebViewHandler {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for reporting new items.
        case items = "itemsHandler"
        /// Handler used for reporting extracted identifiers.
        case identifiers = "identifiersHandler"
        /// Handler used for reporting failure - when no items were detected.
        case lookupFailed = "failureHandler"
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case request = "requestHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindFile
        case invalidIdentifiers
        case noSuccessfulTranslators
        case lookupFailed
    }

    enum LookupData {
        case identifiers([[String: String]])
        case item([String: Any])
    }

    private enum InitializationResult {
        case initialized
        case inProgress
        case failed(Swift.Error)
    }

    private let webViewHandler: WebViewHandler
    private let translatorsController: TranslatorsAndStylesController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<LookupData, Swift.Error>>

    private var isLoading: BehaviorRelay<InitializationResult>

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
        self.translatorsController = translatorsController
        self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        self.observable = PublishSubject()
        self.disposeBag = DisposeBag()
        self.isLoading = BehaviorRelay(value: .inProgress)

        self.webViewHandler.receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }

        self.initialize()
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onSuccess: { `self`, _ in
                DDLogInfo("LookupWebViewHandler: initialization succeeded")
                self.isLoading.accept(.initialized)
            }, onFailure: { `self`, error in
                DDLogInfo("LookupWebViewHandler: initialization failed - \(error)")
                self.isLoading.accept(.failed(error))
            })
            .disposed(by: self.disposeBag)
    }

    func lookUp(identifier: String) {
        switch self.isLoading.value {
        case .failed(let error):
            self.observable.on(.next(.failure(error)))

        case .initialized:
            self._lookUp(identifier: identifier)

        case .inProgress:
            self.isLoading.filter { result in
                switch result {
                case .inProgress: return false
                case .initialized, .failed: return true
                }
            }
            .first()
            .subscribe(with: self, onSuccess: { `self`, result in
                guard let result = result else { return }
                switch result {
                case .failed(let error):
                    self.observable.on(.next(.failure(error)))

                case .initialized:
                    self._lookUp(identifier: identifier)

                case .inProgress: break
                }
            })
            .disposed(by: self.disposeBag)
        }
    }

    private func _lookUp(identifier: String) {
        DDLogInfo("LookupWebViewHandler: call translate js")
        let encodedIdentifiers = WKWebView.encodeForJavascript(identifier.data(using: .utf8))
        return self.webViewHandler.call(javascript: "lookup(\(encodedIdentifiers));")
                   .subscribe(on: MainScheduler.instance)
                   .observe(on: MainScheduler.instance)
                   .subscribe(onFailure: { [weak self] error in
                       DDLogError("WebViewHandler: translation failed - \(error)")
                       self?.observable.on(.next(.failure(error)))
                   })
                   .disposed(by: self.disposeBag)
    }

    private func initialize() -> Single<Any> {
        DDLogInfo("LookupWebViewHandler: initialize web view")
        return self.loadIndex()
                   .flatMap { _ -> Single<(String, String)> in
                       DDLogInfo("LookupWebViewHandler: load bundled files")
                       return self.loadBundledFiles()
                   }
                   .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                       DDLogInfo("LookupWebViewHandler: init schema and date formats")
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

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .lookupFailed:
            guard let errorNumber = body as? Int else { return }
            switch errorNumber {
            case 0:
                self.observable.on(.next(.failure(Error.invalidIdentifiers)))
            case 1:
                self.observable.on(.next(.failure(Error.noSuccessfulTranslators)))
            default:
                self.observable.on(.next(.failure(Error.lookupFailed)))
            }

        case .items:
            guard let rawData = body as? [String: Any] else { return }
            self.observable.on(.next(.success(.item(rawData))))

        case .identifiers:
            guard let rawData = body as? [[String: String]] else { return }
            self.observable.on(.next(.success(.identifiers(rawData))))

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
                    self.webViewHandler.sendMessaging(error: "Could not create request", for: messageId)
                }
            } else {
                DDLogError("TranslationWebViewHandler: request missing payload - \(body)")
                self.webViewHandler.sendMessaging(error: "HTTP request missing payload", for: messageId)
            }
        }
    }
}
