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

private struct StyleData {
    let filename: String
    let defaultLocaleId: String?
    let supportsBibliography: Bool

    init(style: RStyle) {
        filename = style.dependency?.filename ?? style.filename
        defaultLocaleId = style.defaultLocale.isEmpty ? nil : style.defaultLocale
        supportsBibliography = style.supportsBibliography
    }
}

class CitationController: NSObject {
    struct Session: Hashable {
        let id = UUID()
        let itemIds: Set<String>
        let libraryId: LibraryIdentifier

        let styleXML: String
        let styleLocaleId: String
        let localeXML: String
        let supportsBibliography: Bool
        var itemsCSL: String
    }

    enum Format: String {
        case html
        case text
        case rtf
    }

    enum Error: Swift.Error {
        case webViewNotProvided
        case styleOrLocaleMissing
        case invalidSession
        case cantFindFile
        case invalidItemTypes
    }

    static let invalidItemTypes: Set<String> = [ItemTypes.attachment, ItemTypes.note]
    private unowned let stylesController: TranslatorsAndStylesController
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let bundledDataStorage: DbStorage
    private let backgroundQueue: DispatchQueue
    private let backgroundScheduler: SerialDispatchQueueScheduler
    weak var webViewProvider: WebViewProvider?
    private var citationWebViewHandlerBySession: [Session: CitationWebViewHandler] = [:]

    init(stylesController: TranslatorsAndStylesController, fileStorage: FileStorage, dbStorage: DbStorage, bundledDataStorage: DbStorage) {
        let queue = DispatchQueue(label: "org.zotero.CitationController.queue", qos: .userInitiated)
        self.stylesController = stylesController
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.bundledDataStorage = bundledDataStorage
        backgroundQueue = queue
        backgroundScheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.CitationController.scheduler")
        super.init()
    }

    // MARK: - Actions

    /// Starts citation session by creating a CitationWebViewHandler, that it's ready immediately for citation/bibliography generation.
    /// - parameter itemIds: Ids of items for which CSL will be generated.
    /// - parameter libraryId: Library identifier of given items.
    /// - parameter styleId: Id of style to use for citation/bibliography generation.
    /// - parameter localeId: Id of locale to use for citation/bibliography generation.
    /// - parameter webView: Optional web view for theCitationWebViewHandler. If nil one from the web view provider is requested.
    /// - returns: Single with the session that is called when webView is fully loaded.
    func startSession(for itemIds: Set<String>, libraryId: LibraryIdentifier, styleId: String, localeId: String, webView: WKWebView? = nil) -> Single<Session> {
        guard let webView = webView ?? webViewProvider?.addWebView(configuration: nil) else {
            return .error(Error.webViewNotProvided)
        }
        let citationWebViewHandler = CitationWebViewHandler(webView: webView)
        return loadStyleData(for: styleId)
            .subscribe(on: backgroundScheduler)
            .observe(on: backgroundScheduler)
            .flatMap { styleData -> Single<(String, String, String, Bool)> in
                let styleLocaleId = styleData.defaultLocaleId ?? localeId
                return loadEncodedXmls(styleFilename: styleData.filename, localeId: styleLocaleId).flatMap { .just(($0.0, styleLocaleId, $0.1, styleData.supportsBibliography)) }
            }
            .flatMap { styleXML, styleLocaleId, localeXML, supportsBibliography -> Single<(String, String, String, Bool, String, String)> in
                return loadBundledFiles().flatMap { .just((styleXML, styleLocaleId, localeXML, supportsBibliography, $0, $1)) }
            }
            .flatMap { styleXML, styleLocaleId, localeXML, supportsBibliography, schema, dateFormats -> Single<(String, String, String, Bool, String, String, String)> in
                return loadItemJsons(for: itemIds, libraryId: libraryId)
                    .flatMap { .just((styleXML, styleLocaleId, localeXML, supportsBibliography, schema, dateFormats, $0)) }
            }
            .flatMap { styleXML, styleLocaleId, localeXML, supportsBibliography, schema, dateFormats, itemJsons -> Single<(String, String, String, Bool, String)> in
                return citationWebViewHandler.getItemsCSL(from: itemJsons, schema: schema, dateFormats: dateFormats)
                    .flatMap { .just((styleXML, styleLocaleId, localeXML, supportsBibliography, $0)) }
            }
            .flatMap { styleXML, styleLocaleId, localeXML, supportsBibliography, itemCSL -> Single<Session> in
                let session = Session(
                    itemIds: itemIds,
                    libraryId: libraryId,
                    styleXML: styleXML,
                    styleLocaleId: styleLocaleId,
                    localeXML: localeXML,
                    supportsBibliography: supportsBibliography,
                    itemsCSL: itemCSL
                )
                self.citationWebViewHandlerBySession[session] = citationWebViewHandler
                return .just(session)
            }

        /// Loads style data.
        /// - parameter styleId: Identifier of style
        /// - returns: Style data.
        func loadStyleData(for styleId: String) -> Single<StyleData> {
            return .create { subscriber in
                do {
                    let style = try self.bundledDataStorage.perform(request: ReadStyleDbRequest(identifier: styleId), on: self.backgroundQueue)
                    let data = StyleData(style: style)
                    style.realm?.invalidate()
                    subscriber(.success(data))
                } catch let error {
                    DDLogError("CitationController: can't load style - \(error)")
                    subscriber(.failure(Error.styleOrLocaleMissing))
                }
                return Disposables.create()
            }
        }

        func loadEncodedXmls(styleFilename: String, localeId: String) -> Single<(String, String)> {
            return .create { subscriber in
                guard let localeUrl = Bundle.main.url(forResource: "locales-\(localeId)", withExtension: "xml", subdirectory: "Bundled/locales") else {
                    DDLogError("CitationController: can't load locale xml")
                    subscriber(.failure(Error.styleOrLocaleMissing))
                    return Disposables.create()
                }

                do {
                    let localeData = try Data(contentsOf: localeUrl)
                    let styleData = try self.fileStorage.read(Files.style(filename: styleFilename))

                    subscriber(.success((WebViewEncoder.encodeForJavascript(styleData), WebViewEncoder.encodeForJavascript(localeData))))
                } catch let error {
                    DDLogError("CitationController: can't read locale or style - \(error)")
                    subscriber(.failure(Error.styleOrLocaleMissing))
                }

                return Disposables.create()
            }
        }

        func loadBundledFiles() -> Single<(String, String)> {
            return .create { subscriber in
                guard let schemaPath = Bundle.main.path(forResource: "citation/utilities/resource/schema/global/schema", ofType: "json"),
                      let schemaData = try? Data(contentsOf: URL(fileURLWithPath: schemaPath))
                else {
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }
                guard let dateFormatsPath = Bundle.main.path(forResource: "citation/utilities/resource/dateFormats", ofType: "json"),
                      let dateFormatsData = try? Data(contentsOf: URL(fileURLWithPath: dateFormatsPath))
                else {
                    subscriber(.failure(Error.cantFindFile))
                    return Disposables.create()
                }

                let encodedSchema = WebViewEncoder.encodeForJavascript(schemaData)
                let encodedFormats = WebViewEncoder.encodeForJavascript(dateFormatsData)
                subscriber(.success((encodedSchema, encodedFormats)))
                return Disposables.create()
            }
        }

        func loadItemJsons(for keys: Set<String>, libraryId: LibraryIdentifier) -> Single<String> {
            return .create { subscriber in
                do {
                    let items = try self.dbStorage.perform(request: ReadItemsWithKeysDbRequest(keys: keys, libraryId: libraryId), on: self.backgroundQueue)
                        .filter(.item(notTypeIn: CitationController.invalidItemTypes))

                    if items.isEmpty {
                        subscriber(.failure(Error.invalidItemTypes))
                        return Disposables.create()
                    }

                    let data = Array(items.map({ data(for: $0) }))

                    items.first?.realm?.invalidate()

                    subscriber(.success(WebViewEncoder.encodeAsJSONForJavascript(data)))
                } catch let error {
                    DDLogError("CitationController: can't read items - \(error)")
                    subscriber(.failure(error))
                }

                return Disposables.create()
            }

            func data(for item: RItem) -> [String: Any] {
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
                data["collections"] = [] as [Any]
                data["tags"] = [] as [Any]

                return data
            }
        }
    }

    /// Cleans up after citeproc-js is finished. Should be called when all requests are called.
    func endSession(_ session: Session) {
        citationWebViewHandlerBySession.removeValue(forKey: session)?.webViewHandler.removeFromSuperviewAsynchronously()
    }

    /// Generates citation preview for given citation session, in given format. Has to be called after session has started.
    /// - parameter itemIds: Ids of items of which citation is created.
    /// - parameter libraryId: Id of library for given items.
    /// - parameter label: Label for locator which should be used.
    /// - parameter locator: Locator value.
    /// - parameter omitAuthor: True if author should be suppressed, false otherwise.
    /// - parameter format: Format in which citation is generated.
    /// - parameter showInWebView: If true, shows generated result in webView body. If false, just returns generated result through handlers.
    /// - returns: Single with generated citation.
    func citation(for session: Session, itemIds: Set<String>? = nil, label: String?, locator: String?, omitAuthor: Bool, format: Format, showInWebView: Bool) -> Single<String> {
        guard let citationWebViewHandler = citationWebViewHandlerBySession[session] else { return .error(Error.invalidSession) }
        let itemIds = itemIds ?? session.itemIds
        let itemsData = itemsData(for: itemIds, label: label, locator: locator, omitAuthor: omitAuthor)
        return citationWebViewHandler
            .getCitation(
                itemsCSL: session.itemsCSL,
                itemsData: itemsData,
                styleXML: session.styleXML,
                localeId: session.styleLocaleId,
                localeXML: session.localeXML,
                format: format.rawValue,
                showInWebView: showInWebView
            )
            .flatMap({ .just(self.format(result: $0, format: format)) })

        func itemsData(for itemIds: Set<String>, label: String?, locator: String?, omitAuthor: Bool) -> String {
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
            return WebViewEncoder.encodeAsJSONForJavascript(itemsData)
        }
    }

    /// Bibliography happens once for session item(s). Seession starts, and when everything is loaded,
    /// appropriate js function is called and result is returned. When everything is finished, webView is removed from controller.
    /// - parameter itemIds: Ids of items of which bibliography is created.
    /// - parameter libraryId: Id of library for given items.
    /// - parameter format: Bibliography format to use for generation.
    /// - returns: Single which returns bibliography.
    func bibliography(for session: Session, format: Format) -> Single<String> {
        guard let citationWebViewHandler = citationWebViewHandlerBySession[session] else { return .error(Error.invalidSession) }
        if session.supportsBibliography {
            return citationWebViewHandler
                .getBibliography(
                    itemsCSL: session.itemsCSL,
                    styleXML: session.styleXML,
                    localeId: session.styleLocaleId,
                    localeXML: session.localeXML,
                    format: format.rawValue
                )
                .flatMap({ .just(self.format(result: $0, format: format)) })
        }
        return numberedBibliography(for: session.itemIds, format: format)
            .flatMap({ .just(self.format(result: $0, format: format)) })

        func numberedBibliography(for itemIds: Set<String>, format: Format) -> Single<String> {
            let actions = itemIds.map({ citation(for: session, itemIds: [$0], label: nil, locator: nil, omitAuthor: false, format: format, showInWebView: false).asObservable() })

            return Observable.concat(actions)
                .reduce([]) { array, citation -> [String] in
                    var new = array
                    new.append(citation)
                    return new
                }
                .asSingle()
                .flatMap({ citations -> Single<String> in
                    return .just(formatBibliography(from: citations, to: format))
                })

            func formatBibliography(from citations: [String], to format: Format) -> String {
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
        }
    }

    private func format(result: String, format: Format) -> String {
        switch format {
        case .rtf:
            var newResult = result
            if !result.hasPrefix("{\\rtf") {
                newResult = "{\\rtf\n" + newResult
            }
            if !result.hasSuffix("}") {
                newResult += "\n}"
            }
            return newResult

        case .html:
            var newResult = result
            if !result.hasPrefix("<!DOCTYPE") {
                newResult = "<!DOCTYPE html><html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"></head><body>" + newResult
            }
            if !result.hasSuffix("</html>") {
                newResult += "</body></html>"
            }
            return newResult

        case .text:
            return result
        }
    }
}
