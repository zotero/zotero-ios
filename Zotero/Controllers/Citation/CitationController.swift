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

@preconcurrency
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

    enum Format {
        case html(wrapped: Bool)
        case text
        case rtf(wrapped: Bool)

        var rawValue: String {
            switch self {
            case .html:
                return "html"
            case .text:
                return "text"
            case .rtf:
                return "rtf"
            }
        }

        func formatted(result: String) -> String {
            switch self {
            case .rtf(wrapped: true):
                var newResult = result
                if !result.hasPrefix("{\\rtf") {
                    newResult = "{\\rtf\n" + newResult
                }
                if !result.hasSuffix("}") {
                    newResult += "\n}"
                }
                return newResult

            case .html(wrapped: true):
                var newResult = result
                if !result.hasPrefix("<html") {
                    newResult = #"<html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head><body>"# + newResult
                }
                if !result.hasSuffix("</html>") {
                    newResult += "</body></html>"
                }
                return newResult

            default:
                return result
            }
        }
    }

    enum Error: Swift.Error {
        case webViewNotProvided
        case styleOrLocaleMissing
        case invalidSession
        case cantFindFile
        case invalidItemTypes
        case deinitialized
    }

    static let invalidItemTypes: Set<String> = [ItemTypes.attachment, ItemTypes.note]
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private unowned let bundledDataStorage: DbStorage
    private let backgroundQueue: DispatchQueue
    private let backgroundScheduler: SerialDispatchQueueScheduler
    weak var webViewProvider: WebViewProvider?
    private var citationWebViewHandlerBySession: [Session: CitationWebViewHandler] = [:]

    init(fileStorage: FileStorage, dbStorage: DbStorage, bundledDataStorage: DbStorage) {
        let queue = DispatchQueue(label: "org.zotero.CitationController.queue", qos: .userInitiated)
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
        return loadStyleData(controller: self, for: styleId)
            .subscribe(on: backgroundScheduler)
            .observe(on: backgroundScheduler)
            .flatMap { [weak self] styleData -> Single<(String, String, String, Bool)> in
                guard let self else { return .error(Error.deinitialized) }
                let styleLocaleId = styleData.defaultLocaleId ?? localeId
                return loadEncodedXmls(controller: self, styleFilename: styleData.filename, localeId: styleLocaleId).flatMap { .just(($0.0, styleLocaleId, $0.1, styleData.supportsBibliography)) }
            }
            .flatMap { styleXML, styleLocaleId, localeXML, supportsBibliography -> Single<(String, String, String, Bool, String, String)> in
                return loadBundledFiles().flatMap { .just((styleXML, styleLocaleId, localeXML, supportsBibliography, $0, $1)) }
            }
            .flatMap { [weak self] styleXML, styleLocaleId, localeXML, supportsBibliography, schema, dateFormats -> Single<(String, String, String, Bool, String, String, String)> in
                guard let self else { return .error(Error.deinitialized) }
                return loadItemJsons(controller: self, for: itemIds, libraryId: libraryId)
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
                return .just(session)
            }
            .do(onSuccess: { [weak self] session in
                self?.citationWebViewHandlerBySession[session] = citationWebViewHandler
            })

        /// Loads style data.
        /// - parameter styleId: Identifier of style
        /// - returns: Style data.
        func loadStyleData(controller: CitationController, for styleId: String) -> Single<StyleData> {
            return .create { [weak controller] subscriber in
                guard let controller else { return Disposables.create() }
                do {
                    let style = try controller.bundledDataStorage.perform(request: ReadStyleDbRequest(identifier: styleId), on: controller.backgroundQueue)
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

        func loadEncodedXmls(controller: CitationController, styleFilename: String, localeId: String) -> Single<(String, String)> {
            return .create { [weak controller] subscriber in
                guard let controller else { return Disposables.create() }
                guard let localeUrl = Bundle.main.url(forResource: "locales-\(localeId)", withExtension: "xml", subdirectory: "Bundled/locales") else {
                    DDLogError("CitationController: can't load locale xml")
                    subscriber(.failure(Error.styleOrLocaleMissing))
                    return Disposables.create()
                }

                do {
                    let localeData = try Data(contentsOf: localeUrl)
                    let styleData = try controller.fileStorage.read(Files.style(filename: styleFilename))

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

        func loadItemJsons(controller: CitationController, for keys: Set<String>, libraryId: LibraryIdentifier) -> Single<String> {
            return .create { [weak controller] subscriber in
                guard let controller else { return Disposables.create() }
                do {
                    let items = try controller.dbStorage.perform(request: ReadItemsWithKeysDbRequest(keys: keys, libraryId: libraryId), on: controller.backgroundQueue)
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
        citationWebViewHandlerBySession.removeValue(forKey: session)?.removeFromSuperviewAsynchronously()
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
        return citationWebViewHandler.getCitation(
            itemsCSL: session.itemsCSL,
            itemsData: itemsData,
            styleXML: session.styleXML,
            localeId: session.styleLocaleId,
            localeXML: session.localeXML,
            format: format.rawValue,
            showInWebView: showInWebView
        )
        .flatMap({ .just(format.formatted(result: $0)) })

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
            return citationWebViewHandler.getBibliography(
                itemsCSL: session.itemsCSL,
                styleXML: session.styleXML,
                localeId: session.styleLocaleId,
                localeXML: session.localeXML,
                format: format.rawValue
            )
            .flatMap({ .just(format.formatted(result: $0)) })
        }
        return numberedBibliography(for: session.itemIds, format: format).flatMap({ .just(format.formatted(result: $0)) })

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
}
