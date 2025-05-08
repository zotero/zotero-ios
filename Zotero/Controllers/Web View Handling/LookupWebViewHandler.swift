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

final class LookupWebViewHandler: WebViewHandler {
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

    private let translatorsController: TranslatorsAndStylesController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<LookupData, Swift.Error>>

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
        self.translatorsController = translatorsController
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))

        receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    override func initializeWebView() -> Single<()> {
        DDLogInfo("LookupWebViewHandler: initialize web view")
        return loadIndex()
            .flatMap { _ -> Single<(String, String)> in
                DDLogInfo("LookupWebViewHandler: load bundled files")
                return loadBundledFiles()
            }
            .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                DDLogInfo("LookupWebViewHandler: init schema and date formats")
                return self.call(javascript: "initSchemaAndDateFormats(\(encodedSchema), \(encodedDateFormats));")
            }
            .flatMap { _ -> Single<[RawTranslator]> in
                DDLogInfo("LookupWebViewHandler: load translators")
                return self.translatorsController.translators()
            }
            .flatMap { translators -> Single<Any> in
                DDLogInfo("LookupWebViewHandler: encode translators")
                var encodedTranslators: String = ""
                autoreleasepool {
                    encodedTranslators = WebViewEncoder.encodeAsJSONForJavascript(translators)
                }
                return self.call(javascript: "initTranslators(\(encodedTranslators));")
            }
            .flatMap { _ -> Single<()> in
                return .just(())
            }

        func loadIndex() -> Single<()> {
            guard let indexUrl = Bundle.main.url(forResource: "lookup", withExtension: "html", subdirectory: "translation") else {
                return .error(Error.cantFindFile)
            }
            return load(fileUrl: indexUrl)
        }

        func loadBundledFiles() -> Single<(String, String)> {
            return .create { subscriber in
                guard let schemaUrl = Bundle.main.url(forResource: "schema", withExtension: "json", subdirectory: "Bundled"), let schemaData = try? Data(contentsOf: schemaUrl) else {
                    DDLogError("LookupWebViewHandler: can't load schema json")
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }

                guard let dateFormatsUrl = Bundle.main.url(forResource: "dateFormats", withExtension: "json", subdirectory: "translation/translate/modules/utilities/resource"),
                      let dateFormatData = try? Data(contentsOf: dateFormatsUrl)
                else {
                    DDLogError("LookupWebViewHandler: can't load dateFormats json")
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }

                let encodedSchema = WebViewEncoder.encodeForJavascript(schemaData)
                let encodedFormats = WebViewEncoder.encodeForJavascript(dateFormatData)

                DDLogInfo("LookupWebViewHandler: loaded bundled files")

                subscriber(.success((encodedSchema, encodedFormats)))

                return Disposables.create()
            }
        }
    }

    func lookUp(identifier: String, saveAttachments: Bool) {
        performAfterInitialization()
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                DDLogInfo("LookupWebViewHandler: call translate js")
                let encodedIdentifiers = WebViewEncoder.encodeForJavascript(identifier.data(using: .utf8))
                return call(javascript: "lookup(\(encodedIdentifiers), \(saveAttachments ? "true" : "false"));")
            }
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onFailure: { [weak self] error in
                DDLogError("LookupWebViewHandler: translation failed - \(error)")
                self?.observable.on(.next(.failure(error)))
            })
            .disposed(by: disposeBag)
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
                observable.on(.next(.failure(Error.invalidIdentifiers)))

            case 1:
                observable.on(.next(.failure(Error.noSuccessfulTranslators)))

            default:
                observable.on(.next(.failure(Error.lookupFailed)))
            }

        case .items:
            guard let rawData = body as? [String: Any] else { return }
            observable.on(.next(.success(.item(rawData))))

        case .identifiers:
            guard let rawData = body as? [[String: String]] else { return }
            observable.on(.next(.success(.identifiers(rawData))))

        case .log:
            DDLogInfo("LookupWebViewHandler: JSLOG - \(body)")

        case .request:
            guard let body = body as? [String: Any], let messageId = body["messageId"] as? Int else {
                DDLogError("LookupWebViewHandler: request missing body - \(body)")
                return
            }

            if let options = body["payload"] as? [String: Any] {
                do {
                    try sendRequest(with: options, for: messageId)
                } catch let error {
                    DDLogError("LookupWebViewHandler: send request error \(error)")
                    sendMessaging(error: "Could not create request", for: messageId)
                }
            } else {
                DDLogError("LookupWebViewHandler: request missing payload - \(body)")
                sendMessaging(error: "HTTP request missing payload", for: messageId)
            }
        }
    }
}
