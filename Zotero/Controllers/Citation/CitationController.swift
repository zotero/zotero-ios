//
//  CitationController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

fileprivate struct StyleData {
    let filename: String
    let defaultLocaleId: String?
    let supportsBibliography: Bool

    init(style: RStyle) {
        self.filename = style.dependency?.filename ?? style.filename
        self.defaultLocaleId = style.defaultLocale.isEmpty ? nil : style.defaultLocale
        self.supportsBibliography = style.supportsBibliography
    }
}

class CitationController: NSObject {
    fileprivate typealias WebViewResponseHandler = (SingleEvent<String>) -> Void

    enum Format: String {
        case html
        case text
        case rtf
    }

    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case citation = "citationHandler"
        case log = "logHandler"
        case bibliography = "bibliographyHandler"
        case csl = "cslHandler"
    }

    enum Error: Swift.Error {
        case deinitialized
        case alreadyRunning
        case cantFindBaseFile
        case missingResponse
        case styleOrLocaleMissing
        case prepareNotCalled
        case cantFindSchema
        case invalidItemTypes
    }

    static let invalidItemTypes: Set<String> = [ItemTypes.attachment, ItemTypes.note]
    private unowned let stylesController: TranslatorsAndStylesController
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let bundledDataStorage: DbStorage
    private let backgroundScheduler: SerialDispatchQueueScheduler

    // Store temporary data for citation preview so that they don't need to be reloaded for each preview generation.
    private var styleXml: String?
    private var localeId: String?
    private var localeXml: String?
    private var itemsCsl: String?
    private var supportsBibliography: Bool?

    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var responseHandlers: [String: WebViewResponseHandler]

    init(stylesController: TranslatorsAndStylesController, fileStorage: FileStorage, dbStorage: DbStorage, bundledDataStorage: DbStorage) {
        self.stylesController = stylesController
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.bundledDataStorage = bundledDataStorage
        self.backgroundScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.CitationController")
        self.responseHandlers = [:]
        super.init()
    }

    // MARK: - Actions

    /// Pre-loads given webView with appropriate index.html so that it's ready immediately for citation/bibliography generation.
    /// - parameter itemIds: Ids of items for which CSL will be generated.
    /// - parameter libraryId: Library identifier of given items.
    /// - parameter styleId: Id of style to use for citation/bibliography generation.
    /// - parameter localeId: Id of locale to use for citation/bibliography generation.
    /// - returns: Single which is called when webView is fully loaded.
    func prepare(webView: WKWebView, for itemIds: Set<String>, libraryId: LibraryIdentifier, styleId: String, localeId: String) -> Single<()> {
        webView.navigationDelegate = self
        JSHandlers.allCases.forEach { handler in
            webView.configuration.userContentController.removeScriptMessageHandler(forName: handler.rawValue)
            webView.configuration.userContentController.add(self, name: handler.rawValue)
        }

        return self.loadStyleData(for: styleId)
                   .subscribe(on: self.backgroundScheduler)
                   .observe(on: self.backgroundScheduler)
                   .flatMap({ styleData -> Single<(String, String, String, Bool)> in
                       let styleLocaleId = styleData.defaultLocaleId ?? localeId
                       return self.loadEncodedXmls(styleFilename: styleData.filename, localeId: styleLocaleId).flatMap({ Single.just(($0.0, $0.1, styleLocaleId, styleData.supportsBibliography)) })
                   })
                   .do(onSuccess: { styleXml, localeXml, localeId, supportsBibliography in
                       self.styleXml = styleXml
                       self.localeId = localeId
                       self.localeXml = localeXml
                       self.supportsBibliography = supportsBibliography
                   })
                   .flatMap({ _ -> Single<String> in
                       return self.loadSchema()
                   })
                   .flatMap({ schema -> Single<(String, String)> in
                       return self.loadItemJsons(for: itemIds, libraryId: libraryId).flatMap({ Single.just((schema, $0)) })
                   })
                   .flatMap({ schema, itemJsons -> Single<(String, URL, String, String)> in
                       return self.loadIndexHtml().flatMap({ Single.just(($0, $1, schema, itemJsons)) })
                   })
                   .observe(on: MainScheduler.instance)
                   .flatMap({ [weak webView] html, url, schema, itemJsons -> Single<(String, String)> in
                        guard let webView = webView else { return Single.error(Error.deinitialized) }
                        return self.load(html: html, baseUrl: url, in: webView).flatMap({ _ in Single.just((schema, itemJsons)) })
                   })
                   .flatMap({ [weak webView] schema, itemJsons -> Single<String> in
                       guard let webView = webView else { return Single.error(Error.deinitialized) }
                       return self.getItemsCsl(from: itemJsons, schema: schema, webView: webView)
                   })
                   .do(onSuccess: { itemsCsl in
                       self.itemsCsl = itemsCsl
                   })
                   .flatMap({ _ in return Single.just(()) })
    }

    /// Cleans up after citeproc-js is finished. Should be called when all requests are called.
    func finishCitation() {
        self.localeXml = nil
        self.localeId = nil
        self.styleXml = nil
        self.itemsCsl = nil
        self.supportsBibliography = nil
    }

    /// Generates citation preview for given item in given format. Has to be called after `prepareForCitation(styleId:localeId:in:)` finishes!
    /// - parameter itemIds: Ids of items of which citation is created.
    /// - parameter libraryId: Id of library for given items.
    /// - parameter label: Label for locator which should be used.
    /// - parameter locator: Locator value.
    /// - parameter omitAuthor: True if author should be suppressed, false otherwise.
    /// - parameter format: Format in which citation is generated.
    /// - parameter showInWebView: If true, shows generated result in webView body. If false, just returns generated result through handlers.
    /// - parameter webView: Web view which is fully loaded (`prepareForCitation(styleId:localeId:in:)` finished).
    /// - returns: Single with generated citation.
    func citation(for itemIds: Set<String>, label: String?, locator: String?, omitAuthor: Bool, format: Format, showInWebView: Bool, in webView: WKWebView) -> Single<String> {
        guard let style = self.styleXml, let localeId = self.localeId, let locale = self.localeXml, let itemsCsl = self.itemsCsl else { return Single.error(Error.prepareNotCalled) }
        let itemsData = self.itemsData(for: itemIds, label: label, locator: locator, omitAuthor: omitAuthor)
        return self.getCitation(itemsCsl: itemsCsl, itemsData: itemsData, styleXml: style, localeId: localeId, localeXml: locale,
                                format: format.rawValue, showInWebView: showInWebView, webView: webView)
                   .flatMap({ Single.just(self.format(result: $0, format: format)) })
    }

    private func itemsData(for itemIds: Set<String>, label: String?, locator: String?, omitAuthor: Bool) -> String {
        var itemsData: [[String: Any]] = []
        for key in itemIds {
            var data: [String: Any] = ["id": "https://www.zotero.org/\(key)", "suppress-author": omitAuthor]
            if let value = label {
                data["label"] = value
            }
            if let value = locator {
                data["locator"] = value
            }
            itemsData.append(data)
        }
        return WKWebView.encodeAsJSONForJavascript(itemsData)
    }

    /// Bibliography happens once for selected item(s). Appropriate style and locale xmls are loaded, webView is initialized and loaded with index.html. When everything is loaded,
    /// appropriate js function is called and result is returned. When everything is finished, webView is removed from controller.
    /// - parameter itemIds: Ids of items of which bibliography is created.
    /// - parameter libraryId: Id of library for given items.
    /// - parameter format: Bibliography format to use for generation.
    /// - parameter webView: WebView which will run the javascript.
    /// - returns: Single which returns bibliography.
    func bibliography(for itemIds: Set<String>, format: Format, in webView: WKWebView) -> Single<String> {
        guard let style = self.styleXml, let localeId = self.localeId, let locale = self.localeXml, let itemsCsl = self.itemsCsl, let supportsBibliography = self.supportsBibliography else {
            return Single.error(Error.prepareNotCalled)
        }

        if supportsBibliography {
            return self.getBibliography(itemsCsl: itemsCsl, styleXml: style, localeId: localeId, localeXml: locale, format: format.rawValue, webView: webView)
                       .flatMap({ Single.just(self.format(result: $0, format: format)) })
        }
        return self.numberedBibliography(for: itemIds, format: format, in: webView)
                   .flatMap({ Single.just(self.format(result: $0, format: format)) })
    }

    private func format(result: String, format: Format) -> String {
        switch format {
        case .rtf:
            var newResult = result
            if !result.hasPrefix("{\\rtf") {
                newResult = "{\\rtf\n" + newResult
            }
            if !result.hasSuffix("}") {
                newResult = newResult + "\n}"
            }
            return newResult

        case .html:
            var newResult = result
            if !result.hasPrefix("<!DOCTYPE") {
                newResult = "<!DOCTYPE html><html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"></head><body>" + newResult
            }
            if !result.hasSuffix("</html>") {
                newResult = newResult + "</body></html>"
            }
            return newResult

        case .text: return result
        }
    }

    private func numberedBibliography(for itemIds: Set<String>, format: Format, in webView: WKWebView) -> Single<String> {
        let actions = itemIds.map({ self.citation(for: [$0], label: nil, locator: nil, omitAuthor: false, format: format, showInWebView: false, in: webView).asObservable() })

        return Observable.concat(actions)
                         .reduce([]) { array, citation -> [String] in
                             var new = array
                             new.append(citation)
                             return new
                         }
                         .asSingle()
                         .flatMap({ citations -> Single<String> in
                             return Single.just(self.formatBibliography(from: citations, to: format))
                         })
    }

    private func formatBibliography(from citations: [String], to format: Format) -> String {
        switch format {
        case .html:
            return "<ol>\n\t<li>" + citations.joined(separator: "</li>\n\t<li>") + "</li>\n</ol>"

        case .rtf:
            let prefix = "{\\*\\listtable{\\list\\listtemplateid1\\listhybrid{\\listlevel\\levelnfc0\\levelnfcn0\\leveljc0\\leveljcn0\\levelfollow0\\levelstartat1" +
                        "\\levelspace360\\levelindent0{\\*\\levelmarker \\{decimal\\}.}{\\leveltext\\leveltemplateid1\\'02\\'00.;}{\\levelnumbers\\'01;}\\fi-360\\li720\\lin720 }" +
                        "{\\listname ;}\\listid1}}\n{\\*\\listoverridetable{\\listoverride\\listid1\\listoverridecount0\\ls1}}\n\\tx720\\li720\\fi-480\\ls1\\ilvl0\n"
            return prefix + citations.enumerated().map({ "{\\listtext \($0.offset + 1).    }\($0.element)\\\n" }).joined()

        case .text:
            return citations.enumerated().map({ "\($0.offset + 1). \($0.element)" }).joined(separator: "\r\n")
        }
    }

    private func loadEncodedXmls(styleFilename: String, localeId: String) -> Single<(String, String)> {
        return Single.create { subscriber in
            guard let localeUrl = Bundle.main.url(forResource: "locales-\(localeId)", withExtension: "xml", subdirectory: "Bundled/locales") else {
                DDLogError("CitationController: can't load locale xml")
                subscriber(.failure(Error.styleOrLocaleMissing))
                return Disposables.create()
            }

            do {
                let localeData = try Data(contentsOf: localeUrl)
                let styleData = try self.fileStorage.read(Files.style(filename: styleFilename))

                subscriber(.success((WKWebView.encodeForJavascript(styleData), WKWebView.encodeForJavascript(localeData))))

            } catch let error {
                DDLogError("CitationController: can't read locale or style - \(error)")
                subscriber(.failure(Error.styleOrLocaleMissing))
            }

            return Disposables.create()
        }
    }

    /// Loads style data.
    /// - parameter styleId: Identifier of style
    /// - returns: Style data.
    private func loadStyleData(for styleId: String) -> Single<StyleData> {
        return Single.create { subscriber in
            do {
                let style = try self.bundledDataStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: styleId))
                subscriber(.success(StyleData(style: style)))
            } catch let error {
                DDLogError("CitationController: can't load style - \(error)")
                subscriber(.failure(Error.styleOrLocaleMissing))
            }
            return Disposables.create()
        }
    }

    private func loadSchema() -> Single<String> {
        return Single.create { subscriber in
            guard let schemaPath = Bundle.main.path(forResource: "Bundled/schema", ofType: "json"),
                  let schemaData = try? Data(contentsOf: URL(fileURLWithPath: schemaPath)) else {
                subscriber(.failure(Error.cantFindSchema))
                return Disposables.create()
            }

            subscriber(.success(WKWebView.encodeForJavascript(schemaData)))

            return Disposables.create()
        }
    }

    private func loadItemJsons(for keys: Set<String>, libraryId: LibraryIdentifier) -> Single<String> {
        return Single.create { subscriber in
            do {
                let items = try self.dbStorage.createCoordinator().perform(request: ReadItemsWithKeysDbRequest(keys: keys, libraryId: libraryId))
                                                                  .filter(.item(notTypeIn: CitationController.invalidItemTypes))

                if items.isEmpty {
                    subscriber(.failure(Error.invalidItemTypes))
                    return Disposables.create()
                }

                let data = Array(items.map({ self.data(for: $0) }))
                subscriber(.success(WKWebView.encodeAsJSONForJavascript(data)))
            } catch let error {
                DDLogError("CitationController: can't read items - \(error)")
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func data(for item: RItem) -> [String: Any] {
        var data: [String: Any] = [:]

        // Add all fields
        for field in item.fields {
            data[field.key] = field.value
        }

        // Add creators
        var creators: [[String: Any]] = []
        for rCreator in item.creators.sorted(byKeyPath: "orderId") {
            var creator: [String: Any] = ["creatorType": rCreator.rawType]
            if !rCreator.name.isEmpty {
                creator["name"] = rCreator.name
            } else {
                creator["firstName"] = rCreator.firstName
                creator["lastName"] = rCreator.lastName
            }
            creators.append(creator)
        }
        data["creators"] = creators

        // Add relations
        var relations: [[String: Any]] = []
        for rRelation in item.relations {
            guard !rRelation.urlString.isEmpty else { continue }

            let urls = rRelation.urlString.components(separatedBy: ";").filter({ !$0.isEmpty })
            var relation: [String: Any] = [:]

            if urls.count == 1, let url = urls.first {
                relation[rRelation.type] = url
            } else {
                relation[rRelation.type] = urls
            }
            relations.append(relation)
        }
        data["relations"] = relations

        // Add remaining data
        data["key"] = item.key
        data["itemType"] = item.rawType
        data["version"] = item.version
        if let key = item.parent?.key {
            data["parentItem"] = key
        }
        data["dateAdded"] = Formatter.iso8601.string(from: item.dateAdded)
        data["dateModified"] = Formatter.iso8601.string(from: item.dateModified)
        data["uri"] = "https://www.zotero.org/\(item.key)"
        data["inPublications"] = item.inPublications
        data["collections"] = []
        data["tags"] = []

        return data
    }

    // MARK: - Web View

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with citation response or error.
    private func getCitation(itemsCsl: String, itemsData: String, styleXml: String, localeId: String, localeXml: String, format: String, showInWebView: Bool, webView: WKWebView) -> Single<String> {
        return self.perform(javascript: "getCit(\(itemsCsl), \(itemsData), \(styleXml), '\(localeId)', \(localeXml), '\(format)', \(showInWebView), 'msgid');", in: webView)
    }

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with bibliography response or error.
    private func getBibliography(itemsCsl: String, styleXml: String, localeId: String, localeXml: String, format: String, webView: WKWebView) -> Single<String> {
        return self.perform(javascript: "getBib(\(itemsCsl), \(styleXml), '\(localeId)', \(localeXml), '\(format)', 'msgid');", in: webView)
    }

    private func getItemsCsl(from jsons: String, schema: String, webView: WKWebView) -> Single<String> {
        return self.perform(javascript: "convertItemsToCSL(\(jsons), \(schema), 'msgid');", in: webView)
    }

    /// Performs javascript script in web view, returns `Single` with registered response handler.
    private func perform(javascript: String, in webView: WKWebView) -> Single<String> {
        return Single.create { [weak self, weak webView] subscriber -> Disposable in
            guard let `self` = self, let webView = webView else {
                subscriber(.failure(Error.deinitialized))
                return Disposables.create()
            }

            let id = UUID().uuidString
            let javascriptWithId = javascript.replacingOccurrences(of: "msgid", with: id)

            self.responseHandlers[id] = subscriber
            webView.evaluateJavaScript(javascriptWithId, completionHandler: nil)

            return Disposables.create { [weak self] in
                self?.responseHandlers[id] = nil
            }
        }
    }

    /// Loads html in given web view.
    /// - returns: Single called after index is loaded.
    private func load(html: String, baseUrl: URL, in webView: WKWebView) -> Single<()> {
        return Single.create { [weak self, weak webView] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            webView?.loadHTMLString(html, baseURL: baseUrl)

            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    private func loadIndexHtml() -> Single<(String, URL)> {
        return Single.create { subscriber in
            guard let containerUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "citation"),
                  let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
                DDLogError("CitationController: can't load citation html")
                subscriber(.failure(Error.cantFindBaseFile))
                return Disposables.create()
            }
            subscriber(.success((containerHtml, containerUrl)))
            return Disposables.create()
        }
    }
}

extension CitationController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for javascript to load
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.webDidLoad?(.success(()))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        DDLogError("CitationController: failed to load webview - \(error)")
        self.webDidLoad?(.failure(error))
    }
}

/// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
extension CitationController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let handler = JSHandlers(rawValue: message.name) else { return }

        if handler == .log {
            DDLogInfo("CitationController: \((message.body as? String) ?? "-")")
            return
        }

        guard let messageBody = message.body as? [String: Any],
              let messageId = messageBody["id"] as? String,
              let jsResult = messageBody["result"] else {
            DDLogError("CitationController: unknown message body - \(message.body)")
            return
        }

        let result: SingleEvent<String>

        switch handler {
        case .citation, .bibliography:
            if let _result = jsResult as? String {
                result = .success(_result)
            } else {
                DDLogError("CitationController: Citation/bibliography got unknown response - \(jsResult)")
                result = .failure(Error.missingResponse)
            }

        case .csl:
            if let csl = jsResult as? [[String: Any]] {
                result = .success(WKWebView.encodeAsJSONForJavascript(csl))
            } else {
                DDLogError("CitationController: CSL got unknown response - \(jsResult)")
                result = .failure(Error.missingResponse)
            }

        case .log: return
        }

        if let handler = self.responseHandlers[messageId] {
            handler(result)
        } else {
            DDLogError("CitationController: handler for \(message.name) doesn't exist anymore")
        }
    }
}
