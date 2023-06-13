//
//  ExtensionViewModel.swift
//  ZShare
//
//  Created by Michal Rentka on 25/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation
import MobileCoreServices
import WebKit

import Alamofire
import CocoaLumberjackSwift
import RxSwift

/// `ExtensionViewModel` performs fetching of basic website data, runs the translation server which translates the web data, downloads item data with
/// pdf attachment if available and uploads new item to Zotero.
///
/// These steps are performed for each share:
/// 1. Website data (url, title, cookies and full HTML) are loaded from `NSExtensionItem`,
/// 2. Translation server is run in a hidden WebView (handled by `TranslationWebViewHandler`). It loads item data and attachment if available,
/// 3. If there are multiple items available a picker is shown to the user and after picking an item, translation is finished for that item,
/// 4. If available, pdf attachment is downloaded,
/// 5. The item (with attachment) is stored to DB and necessary API requests are made to submit the item (and prepare for upload),
/// 6. A background upload of the pdf attachment is enqueued,
/// 7. The share extension is closed.
///
/// If there was an upload, it is finished in the main app. The main app marks the attachment item as synced
/// and sends additional request to Zotero API to register the upload.
///
/// Sync is also run in background so that the user can see a current list of collections and pick a Collection where the item should be stored.
final class ExtensionViewModel {
    struct State {
        enum CollectionPickerState {
            case loading, failed
            case picked(Library, Collection?)
        }

        struct ItemPickerState {
            let items: [(key: String, value: String)]
            var picked: String?
        }

        /// State for loading and processing attachment.
        /// - decoding: Decoding attachment and deciding what to do with it. This is the initial state.
        /// - translating: Translation is in progress. `String` is progress report from javascript code.
        /// - downloading: Translation has ended. The item has an attachment which is being downloaded.
        /// - processed: Processing of attachment has ended (either loading of URL or translation of web). Waiting for submission.
        /// - submitting: Submitting processed attachment to backend.
        /// - done: Sharing was successful, extension should close.
        /// - failed: The attachment decoding, translation process or attachment download failed.
        enum AttachmentState {
            enum Error: Swift.Error {
                case apiFailure
                case cantLoadSchema
                case cantLoadWebData
                case downloadFailed
                case itemsNotFound
                case expired
                case unknown
                case fileMissing
                case downloadedFileNotPdf
                case webViewError(TranslationWebViewHandler.Error)
                case parseError(Parsing.Error)
                case schemaError(SchemaError)
                case quotaLimit(LibraryIdentifier)
                case webDavNotVerified
                case webDavFailure
                case md5Missing
                case mtimeMissing

                var isFatal: Bool {
                    switch self {
                    case .cantLoadWebData, .cantLoadSchema: return true
                    default: return false
                    }
                }

                var isFatalOrQuota: Bool {
                    switch self {
                    case .cantLoadWebData, .cantLoadSchema, .quotaLimit: return true
                    default: return false
                    }
                }
            }

            case decoding
            case translating(String)
            case downloading(Double)
            case processed
            case failed(Error)

            var error: Error? {
                switch self {
                case .failed(let error):
                    return error

                default:
                    return nil
                }
            }

            var translationInProgress: Bool {
                switch self {
                case .decoding, .translating, .downloading:
                    return true

                default:
                    return false
                }
            }

            var isSubmittable: Bool {
                switch self {
                case .processed: return true

                case .failed(let error):
                    if error.isFatal {
                        return false
                    }
                    
                    switch error {
                    case .apiFailure, .quotaLimit:
                        return false

                    default:
                        return true
                    }
                default: return false
                }
            }
        }

        /// Raw attachment received from NSItemProvider.
        /// - web: Web content received from browser. Web content should be translated.
        /// - remoteUrl: `URL` instance which is not a local file. This `URL` should be opened in a browser and transformed to `.web(...)` or `.fileUrl(...)`.
        /// - fileUrl: `URL` pointing to a local file.
        /// - remoteFileUrl: `URL` pointing to a remote file.
        /// - string: `String` on which we'll try to run lookup and see if it contains usable identifiers
        enum RawAttachment {
            case web(title: String, url: URL, html: String, cookies: String, frames: [String], userAgent: String, referrer: String)
            case remoteUrl(URL)
            case fileUrl(URL)
            case remoteFileUrl(url: URL, contentType: String, cookies: String, userAgent: String, referrer: String)
        }

        /// Attachment which has been loaded and translated processed/translated.
        /// - item: Translated item which doesn't have an attachment.
        /// - itemWithAttachment: Translated item with attachment data.
        /// - file: `URL` pointing to a local file.
        /// - remoteFile: `URL` pointing to a remote file.
        enum ProcessedAttachment {
            case item(ItemResponse)
            case itemWithAttachment(item: ItemResponse, attachment: [String: Any], attachmentFile: File)
            case file(file: File, filename: String)
        }

        fileprivate struct UploadData {
            enum Kind {
                case file(location: File, collections: Set<String>, tags: [TagResponse])
                case translated(item: ItemResponse, location: File)
            }

            let type: Kind
            let attachment: Attachment
            let file: File
            let filename: String
            let libraryId: LibraryIdentifier
            let userId: Int

            init(item: ItemResponse, attachmentKey: String, attachmentData: [String: Any], attachmentFile: File, linkType: Attachment.FileLinkType, defaultTitle: String, libraryId: LibraryIdentifier,
                 userId: Int, dateParser: DateParser) {
                let url = attachmentData[FieldKeys.Item.url] as? String
                let filename = FilenameFormatter.filename(from: item, defaultTitle: defaultTitle, ext: attachmentFile.ext, dateParser: dateParser)
                let file = Files.attachmentFile(in: libraryId, key: attachmentKey, filename: filename, contentType: attachmentFile.mimeType)
                let attachment = Attachment(type: .file(filename: filename, contentType: attachmentFile.mimeType, location: .local, linkType: linkType),
                                            title: filename,
                                            url: url,
                                            key: attachmentKey,
                                            libraryId: libraryId)

                self.type = .translated(item: item, location: attachmentFile)
                self.attachment = attachment
                self.file = file
                self.filename = filename
                self.libraryId = libraryId
                self.userId = userId
            }

            init(file: File, filename: String, attachmentKey: String, linkType: Attachment.FileLinkType, remoteUrl: String?, collections: Set<String>, tags: [TagResponse], libraryId: LibraryIdentifier,
                 userId: Int) {
                let newFile = Files.attachmentFile(in: libraryId, key: attachmentKey, filename: filename, contentType: file.mimeType)
                let attachment = Attachment(type: .file(filename: filename, contentType: file.mimeType, location: .local, linkType: linkType),
                                            title: filename,
                                            url: remoteUrl,
                                            key: attachmentKey,
                                            libraryId: libraryId)

                self.type = .file(location: file, collections: collections, tags: tags)
                self.attachment = attachment
                self.file = newFile
                self.filename = filename
                self.libraryId = libraryId
                self.userId = userId
            }
        }

        // Newly generated key for attachment (used to store attachment file at correct location)
        let attachmentKey: String
        // Title of website where share extension is visible
        var title: String?
        // URL of website where share extension is visible
        var url: String?
        // Selected collection in collection picker
        var selectedCollectionId: CollectionIdentifier
        // Library id of selected collection in collection picker
        var selectedLibraryId: LibraryIdentifier
        // State of collection picker
        var collectionPickerState: CollectionPickerState
        // Recently picked collections in collection picker
        var recents: [RecentData]
        // Item picker state
        var itemPickerState: ItemPickerState?
        // State of attachment
        var attachmentState: AttachmentState
        // Item that was decoded and is expected to be saved by share extension (shown in UI)
        var expectedItem: ItemResponse?
        // Attachment that was decoded and is expected to be saved by share extension (shown in UI)
        var expectedAttachment: (String, File)?
        // Actually processed item/attachment/both which were successfully decoded, downloaded and are ready for submission.
        var processedAttachment: ProcessedAttachment?
        // Tags decoded with item
        var tags: [Tag]
        // `true` when share extension is submitting item/attachment/both, `false` otherwise
        var isSubmitting: Bool
        // `true` when share extension should close
        var isDone: Bool
        // Count of retries on download failure
        var retryCount: Int

        init() {
            self.attachmentKey = KeyGenerator.newKey
            self.selectedCollectionId = Defaults.shared.selectedCollectionId
            self.selectedLibraryId = Defaults.shared.selectedLibrary
            self.collectionPickerState = .loading
            self.attachmentState = .decoding
            self.recents = []
            self.tags = []
            self.isSubmitting = false
            self.isDone = false
            self.retryCount = 0
        }
    }

    @Published var state: State
    // Optional handler to deal with webs that provide PDFs through redirection
    private var redirectHandler: RedirectWebViewHandler?
    private weak var webView: WKWebView?

    private static let defaultLibraryId: LibraryIdentifier = .custom(.myLibrary)
    private static let defaultExtension = "pdf"
    private static let defaultMimetype = "application/pdf"
    private static let zipMimetype = "application/zip"

    private let syncController: SyncController
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let webDavController: WebDavController
    private let dateParser: DateParser
    private let translationHandler: TranslationWebViewHandler
    private let backgroundUploader: BackgroundUploader
    private let backgroundUploadObserver: BackgroundUploadObserver
    private let backgroundQueue: DispatchQueue
    private let backgroundScheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag
    // Custom `URLSession` has to be used for downloading, instead of existing `apiClient`, so that we can include original cookies in download requests.
    private let downloadUrlSession: URLSession

    private struct SubmissionData {
        let filesize: UInt64
        let md5: String
        let mtime: Int
    }

    init(webView: WKWebView, apiClient: ApiClient, backgroundUploader: BackgroundUploader, backgroundUploadObserver: BackgroundUploadObserver, dbStorage: DbStorage, schemaController: SchemaController,
         webDavController: WebDavController, dateParser: DateParser, fileStorage: FileStorage, syncController: SyncController, translatorsController: TranslatorsAndStylesController) {
        let queue = DispatchQueue(label: "org.zotero.ZShare.BackgroundQueue", qos: .userInteractive)

        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        storage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always

        let sessionOperationQueue = OperationQueue()
        sessionOperationQueue.underlyingQueue = queue

        self.downloadUrlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: sessionOperationQueue)
        self.webView = webView
        self.syncController = syncController
        self.apiClient = apiClient
        self.backgroundUploader = backgroundUploader
        self.backgroundUploadObserver = backgroundUploadObserver
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.webDavController = webDavController
        self.dateParser = dateParser
        self.translationHandler = TranslationWebViewHandler(webView: webView, translatorsController: translatorsController)
        self.backgroundQueue = queue
        self.backgroundScheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.ZShare.BackgroundScheduler")
        self.state = State()
        self.disposeBag = DisposeBag()

        self.setupSyncObserving()
        self.setupWebHandlerObserving()
    }

    // MARK: - Actions

    func start(with extensionItem: NSExtensionItem) {
        // Start sync in background, so that collections are available for user to pick
        DDLogInfo("ExtensionViewModel: start sync")
        self.syncController.start(type: .collectionsOnly, libraries: .all)
        DDLogInfo("ExtensionViewModel: load extension item")
        self.loadAttachment(from: extensionItem)
            .subscribe(onSuccess: { [weak self] attachment in
                self?.process(attachment: attachment)
            }, onFailure: { [weak self] error in
                guard let self = self else { return }
                DDLogError("ExtensionViewModel: could not load attachment - \(error)")
                self.state.attachmentState = .failed(self.attachmentError(from: error, libraryId: nil))
            })
            .disposed(by: self.disposeBag)
    }

    func cancel() {
        guard let attachment = self.state.processedAttachment else { return }
        switch attachment {
        case .itemWithAttachment(_, _, let file), .file(let file, _):
            // Remove temporary local file if it exists
            try? self.fileStorage.remove(file)
        case .item: break
        }
    }

    // MARK: - Processing attachments

    private func loadAttachment(from extensionItem: NSExtensionItem) -> Single<State.RawAttachment> {
        let observables = (extensionItem.attachments ?? []).map({ self.loadProviderData(from: $0) })
        return Observable.concat(observables)
                         .filter({ value in
                             switch value {
                             case .success: return true
                             case .failure: return false
                             }
                         })
                        .first()
                        .flatMap { value in
                            guard let value = value else {
                                return Single.error(State.AttachmentState.Error.cantLoadWebData)
                            }

                            switch value {
                            case .success(let attachment): return Single.just(attachment)
                            case .failure(let error): return Single.error(error)
                            }
                        }
    }

    private func loadProviderData(from itemProvider: NSItemProvider) -> Observable<Result<State.RawAttachment, State.AttachmentState.Error>> {
        if itemProvider.hasItemConformingToTypeIdentifier(kUTTypePropertyList as String) {
            DDLogInfo("ExtensionViewModel: item provider for property list")
            return self.loadWebData(from: itemProvider)
        } else if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            DDLogInfo("ExtensionViewModel: item provider for URL")
            return self.loadUrl(from: itemProvider)
        } else if itemProvider.hasItemConformingToTypeIdentifier(kUTTypePlainText as String) {
            DDLogInfo("ExtensionViewModel: item provider for plain text")
            return self.loadPlainText(from: itemProvider)
        }

        return Observable.just(.failure(.cantLoadWebData))
    }

    private func process(attachment: State.RawAttachment) {
        switch attachment {
        case .web(let title, let url, let html, let cookies, let frames, let userAgent, let referrer):
            self.processWeb(title: title, url: url, html: html, cookies: cookies, frames: frames, userAgent: userAgent, referrer: referrer)

        case .remoteUrl(let url):
            self.process(remoteUrl: url)

        case .fileUrl(let url):
            self.process(fileUrl: url)

        case .remoteFileUrl(let url, let contentType, let cookies, let userAgent, let referrer):
            self.process(remoteFileUrl: url, contentType: contentType, cookies: cookies, userAgent: userAgent, referrer: referrer)
        }
    }

    private func processWeb(title: String, url: URL, html: String, cookies: String, frames: [String], userAgent: String, referrer: String) {
        var state = self.state
        state.title = title
        state.url = url.absoluteString
        self.state = state

        DDLogInfo("ExtensionViewModel: start translation")

        self.translationHandler.translate(url: url, title: title, html: html, cookies: cookies, frames: frames, userAgent: userAgent, referrer: referrer)
    }

    private func process(remoteUrl url: URL) {
        DDLogInfo("ExtensionViewModel: load web")

        self.translationHandler.loadWebData(from: url)
                               .subscribe(onSuccess: { [weak self] attachment in
                                   self?.process(attachment: attachment)
                               }, onFailure: { [weak self] error in
                                   guard let self = self else { return }
                                   DDLogError("ExtensionViewModel: webview could not load data - \(error)")
                                   self.state.attachmentState = .failed(self.attachmentError(from: error, libraryId: nil))
                               })
                               .disposed(by: self.disposeBag)
    }

    private func process(fileUrl url: URL) {
        let filename = url.lastPathComponent
        let tmpFile = Files.temporaryFile(ext: url.pathExtension)

        self.copyFile(from: url.path, to: tmpFile)
            .subscribe(with: self, onSuccess: { `self`, _ in
                var state = self.state
                state.processedAttachment = .file(file: tmpFile, filename: filename)
                state.expectedAttachment = (filename, tmpFile)
                state.attachmentState = .processed
                self.state = state
            }, onFailure: { `self`, _ in
                self.state.attachmentState = .failed(.fileMissing)
            })
            .disposed(by: self.disposeBag)
    }

    private func process(remoteFileUrl url: URL, contentType: String, cookies: String, userAgent: String, referrer: String) {
        let filename = url.lastPathComponent
        let file = Files.shareExtensionDownload(key: self.state.attachmentKey, contentType: contentType)

        var state = self.state
        state.url = url.absoluteString
        state.title = url.absoluteString
        state.attachmentState = .downloading(0)
        state.expectedAttachment = (filename, file)
        self.state = state

        DDLogInfo("ExtensionViewModel: download file")
        self.download(url: url, to: file, cookies: cookies, userAgent: userAgent, referrer: referrer)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                guard let self = self else { return }

                var state = self.state
                if self.fileStorage.isPdf(file: file) {
                    DDLogInfo("ExtensionViewModel: downloaded pdf")
                    state.processedAttachment = .file(file: file, filename: filename)
                    state.attachmentState = .processed
                } else {
                    DDLogInfo("ExtensionViewModel: downloaded unsupported file")
                    state.processedAttachment = nil
                    state.attachmentState = .failed(.downloadedFileNotPdf)
                    state.expectedAttachment = nil
                    // Remove downloaded file, it won't be used anymore
                    try? self.fileStorage.remove(file)
                }
                self.state = state
            }, onFailure: { [weak self] error in
                DDLogError("ExtensionViewModel: could not download shared file - \(url.absoluteString) - \(error)")
                self?.state.attachmentState = .failed(.downloadFailed)
                try? self?.fileStorage.remove(file)
            })
            .disposed(by: self.disposeBag)
    }

    private func loadUrl(from itemProvider: NSItemProvider) -> Observable<Result<State.RawAttachment, State.AttachmentState.Error>> {
        return Observable.create { [weak itemProvider] subscriber in
            guard let itemProvider = itemProvider else {
                subscriber.on(.next(.failure(.cantLoadWebData)))
                subscriber.on(.completed)
                return Disposables.create()
            }

            DDLogInfo("ExtensionViewModel: load item provider")

            itemProvider.loadItem(forTypeIdentifier: (kUTTypeURL as String), options: nil, completionHandler: { item, error -> Void in
                DDLogInfo("ExtensionViewModel: loaded item provider")
                if let error = error {
                    DDLogError("ExtensionViewModel: url load error - \(error)")
                }

                if let url = item as? URL {
                    DDLogInfo("ExtensionViewModel: loaded url")
                    let attachment = url.isFileURL ? State.RawAttachment.fileUrl(url) : State.RawAttachment.remoteUrl(url)
                    subscriber.on(.next(.success(attachment)))
                } else {
                    DDLogError("ExtensionViewModel: can't load URL")
                    subscriber.on(.next(.failure(.cantLoadWebData)))
                }

                subscriber.on(.completed)
            })

            return Disposables.create()
        }
    }

    /// Creates an Observable for NSExtensionItem to load web data.
    /// - parameter extensionItem: `NSExtensionItem` passed from `NSExtensionContext` from share extension view controller.
    /// - returns: Observable for loading: title, url, full HTML, cookies, iframes content.
    private func loadWebData(from itemProvider: NSItemProvider) -> Observable<Result<State.RawAttachment, State.AttachmentState.Error>> {
        return Observable.create { [weak itemProvider] subscriber in
            guard let itemProvider = itemProvider else {
                subscriber.on(.next(.failure(.cantLoadWebData)))
                subscriber.on(.completed)
                return Disposables.create()
            }

            DDLogInfo("ExtensionViewModel: load item provider")

            itemProvider.loadItem(forTypeIdentifier: (kUTTypePropertyList as String), options: nil, completionHandler: { item, error -> Void in
                DDLogInfo("ExtensionViewModel: loaded item provider")
                if let error = error {
                    DDLogError("ExtensionViewModel: web data load error - \(error)")
                }

                guard let scriptData = item as? [String: Any],
                      let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
                      let isFile = data["isFile"] as? Bool,
                      let url = (data["url"] as? String).flatMap(URL.init),
                      let cookies = data["cookies"] as? String,
                      let userAgent = data["userAgent"] as? String,
                      let referrer = data["referrer"] as? String else {
                    DDLogError("ExtensionViewModel: can't read script data")
                    subscriber.on(.next(.failure(.cantLoadWebData)))
                    subscriber.on(.completed)
                    return
                }

                if isFile, let contentType = data["contentType"] as? String {
                    DDLogInfo("ExtensionViewModel: loaded remote file")
                    subscriber.on(.next(.success(.remoteFileUrl(url: url, contentType: contentType, cookies: cookies, userAgent: userAgent, referrer: referrer))))
                } else if let title = data["title"] as? String,
                          let html = data["html"] as? String,
                          let frames = data["frames"] as? [String] {
                    DDLogInfo("ExtensionViewModel: loaded web")
                    subscriber.on(.next(.success(.web(title: title, url: url, html: html, cookies: cookies, frames: frames, userAgent: userAgent, referrer: referrer))))
                } else {
                    DDLogError("ExtensionViewModel: script data don't contain required info")
                    DDLogError("\(data)")
                    subscriber.on(.next(.failure(.cantLoadWebData)))
                }

                subscriber.on(.completed)
            })

            return Disposables.create()
        }
    }

    private func loadPlainText(from itemProvider: NSItemProvider) -> Observable<Result<State.RawAttachment, State.AttachmentState.Error>> {
        return Observable.create { [weak itemProvider] subscriber in
            guard let itemProvider = itemProvider else {
                subscriber.on(.next(.failure(.cantLoadWebData)))
                subscriber.on(.completed)
                return Disposables.create()
            }

            DDLogInfo("ExtensionViewModel: load item provider")

            itemProvider.loadItem(forTypeIdentifier: (kUTTypePlainText as String), options: nil, completionHandler: { item, error -> Void in
                DDLogInfo("ExtensionViewModel: loaded item provider")
                if let error = error {
                    DDLogError("ExtensionViewModel: url plaintext error - \(error)")
                }

                if let string = item as? String {
                    DDLogInfo("ExtensionViewModel: loaded plaintext")

                    if let url = URL(string: string), !url.isFileURL {
                        DDLogInfo("ExtensionViewModel: plaintext was url - \(string)")
                        subscriber.on(.next(.success(.remoteUrl(url))))
                    } else {
                        DDLogInfo("ExtensionViewModel: plaintext not url - \(string)")
                        subscriber.on(.next(.failure(.cantLoadWebData)))
                    }
                } else {
                    DDLogError("ExtensionViewModel: can't load plaintext")
                    subscriber.on(.next(.failure(.cantLoadWebData)))
                }

                subscriber.on(.completed)
            })

            return Disposables.create()
        }
    }

    // MARK: - Translation

    /// Observes `WebViewHandler` translation process and acts accordingly.
    private func setupWebHandlerObserving() {
        self.translationHandler.observable
                               .observe(on: MainScheduler.instance)
                               .subscribe(onNext: { [weak self] action in
                                   switch action {
                                   case .loadedItems(let data, let cookies, let userAgent, let referrer):
                                       DDLogInfo("ExtensionViewModel: webview action - loaded \(data.count) zotero items")
                                       self?.processItems(data, cookies: cookies, userAgent: userAgent, referrer: referrer)

                                   case .selectItem(let data):
                                       DDLogInfo("ExtensionViewModel: webview action - loaded \(data.count) list items")
                                       self?.state.itemPickerState = State.ItemPickerState(items: data, picked: nil)

                                   case .reportProgress(let progress):
                                       DDLogInfo("ExtensionViewModel: webview action - progress \(progress)")
                                       self?.state.attachmentState = .translating(progress)
                                   }
                               }, onError: { [weak self] error in
                                   guard let self = self else { return }
                                   DDLogError("ExtensionViewModel: web view error - \(error)")
                                   self.state.attachmentState = .failed(self.attachmentError(from: error, libraryId: nil))
                               })
                               .disposed(by: self.disposeBag)
    }

    /// Parses item from translation response, starts attachment download if available.
    private func processItems(_ data: [[String: Any]], cookies: String?, userAgent: String?, referrer: String?) {
        let item: ItemResponse
        let attachment: [String: Any]?

        do {
            DDLogInfo("ExtensionViewModel: parse zotero items")
            let (_item, _attachment) = try self.parse(data, schemaController: self.schemaController)
            item = _item
            attachment = _attachment
        } catch let error {
            DDLogError("ExtensionViewModel: could not process item - \(error)")
            self.state.attachmentState = .failed(self.attachmentError(from: error, libraryId: nil))
            return
        }

        guard let attachment = attachment, let urlString = attachment["url"] as? String, let url = URL(string: urlString) else {
            DDLogInfo("ExtensionViewModel: parsed item without attachment")
            var state = self.state
            state.processedAttachment = .item(item)
            state.expectedItem = item
            state.attachmentState = .processed
            self.state = state
            return
        }

        DDLogInfo("ExtensionViewModel: parsed item with attachment, download attachment")

        let file = Files.shareExtensionDownload(key: self.state.attachmentKey, ext: ExtensionViewModel.defaultExtension)
        self.download(item: item, attachment: attachment, attachmentUrl: url, to: file, cookies: cookies, userAgent: userAgent, referrer: referrer)
    }

    private func download(item: ItemResponse, attachment: [String: Any], attachmentUrl url: URL, to file: File, cookies: String?, userAgent: String?, referrer: String?) {
        let attachmentTitle = ((attachment["title"] as? String) ?? self.state.title) ?? ""

        var state = self.state
        state.attachmentState = .downloading(0)
        state.expectedItem = item
        state.expectedAttachment = (attachmentTitle, file)
        state.processedAttachment = .item(item)
        self.state = state

        self.download(url: url, to: file, cookies: cookies, userAgent: userAgent, referrer: referrer)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.processDownload(of: attachment, url: url, file: file, item: item, cookies: cookies, userAgent: userAgent, referrer: referrer)
            }, onFailure: { [weak self] error in
                DDLogError("ExtensionViewModel: could not download translated file - \(url.absoluteString) - \(error)")
                self?.state.attachmentState = .failed(.downloadFailed)
            })
            .disposed(by: self.disposeBag)
    }

    private func processDownload(of attachment: [String: Any], url: URL, file: File, item: ItemResponse, cookies: String?, userAgent: String?, referrer: String?) {
        if self.fileStorage.isPdf(file: file) {
            DDLogInfo("ExtensionViewModel: downloaded pdf")
            var state = self.state
            state.attachmentState = .processed
            state.processedAttachment = .itemWithAttachment(item: item, attachment: attachment, attachmentFile: file)
            self.state = state
            return
        }

        DDLogInfo("ExtensionViewModel: downloaded unsupported attachment")

        // Remove downloaded file, it won't be used anymore
        try? self.fileStorage.remove(file)

        guard (url.host ?? "").contains("sciencedirect") else {
            self.state.attachmentState = .failed(.downloadedFileNotPdf)
            return
        }

        // Try loading the url in webview to bypass redirects

        DDLogInfo("ExtensionViewModel: detected sciencedirect, trying redirect")

        self.state.attachmentState = .downloading(0)
        self.state.retryCount += 1

        self.getRedirectedPdfUrl(from: url) { [weak self] newUrl, newCookies, newUserAgent, newReferrer in
            guard let self = self else { return }

            if let newUrl = newUrl, newUrl != url && self.state.retryCount < 3 {
                self.download(item: item, attachment: attachment, attachmentUrl: newUrl, to: file, cookies: newCookies, userAgent: newUserAgent, referrer: newReferrer)
                return
            }

            // Didn't help, report failed PDF download
            self.state.attachmentState = .failed(.downloadedFileNotPdf)
        }
    }

    private func getRedirectedPdfUrl(from url: URL, completion: @escaping (URL?, String?, String?, String?) -> Void) {
        guard let webView = self.webView else {
            completion(nil, nil, nil, nil)
            return
        }

        let handler = RedirectWebViewHandler(url: url, timeoutPerRedirect: .seconds(2), webView: webView)
        handler.getPdfUrl(completion: completion)
        self.redirectHandler = handler
    }

    /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
    /// - parameter data: Data to parse
    /// - parameter schemaController: SchemaController which is used for validating item type and field types
    /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
    private func parse(_ data: [[String: Any]], schemaController: SchemaController) throws -> (ItemResponse, [String: Any]?) {
        // Sort items so that the first item will have a PDF attachment (if available)
        let sortedData = data.sorted { left, right -> Bool in
            let leftAttachments = (left["attachments"] as? [[String: String]]) ?? []
            let leftHasPdf = leftAttachments.contains(where: { $0["mimeType"] == ExtensionViewModel.defaultMimetype })
            let rightAttachments = (right["attachments"] as? [[String: String]]) ?? []
            let rightHasPdf = rightAttachments.contains(where: { $0["mimeType"] == ExtensionViewModel.defaultMimetype })
            return leftHasPdf || !rightHasPdf
        }

        guard let itemData = sortedData.first else {
            throw State.AttachmentState.Error.itemsNotFound
        }

        var item = try ItemResponse(translatorResponse: itemData, schemaController: self.schemaController)
        if !item.tags.isEmpty {
            item = item.copyWithAutomaticTags
        }
        var attachment: [String: Any]?
        if Defaults.shared.shareExtensionIncludeAttachment {
            attachment = (itemData["attachments"] as? [[String: Any]])?.first(where: { ($0["mimeType"] as? String) == ExtensionViewModel.defaultMimetype })
        }

        return (item, attachment)
    }

    /// Sets picked item if multiple items were found.
    func pickItem(_ data: (String, String)) {
        self.state.itemPickerState?.picked = data.1
        self.translationHandler.selectItem(data)
    }

    // MARK: - Attachment Download

    /// Starts download of PDF attachment. Downloads it to temporary folder.
    /// - parameter url: URL of file to download.
    /// - parameter file: File path where the file should be stored.
    /// - parameter cookies: Cookies to include in the request.
    private func download(url: URL, to file: File, cookies: String?, userAgent: String?, referrer: String?) -> Single<()> {
        return Single.create { [weak self] subscriber in
            guard let self = self else {
                subscriber(.failure(State.AttachmentState.Error.expired))
                return Disposables.create()
            }

            do {
                var request = try URLRequest(url: url, method: .get)
                if let value = userAgent {
                    request.setValue(value, forHTTPHeaderField: "User-Agent")
                }
                if let value = referrer {
                    request.setValue(value, forHTTPHeaderField: "Referer")
                }

                self.downloadUrlSession.set(cookies: cookies, domain: url.host ?? "")

                let task = self.downloadUrlSession.downloadTask(with: request) { [weak self] location, _, error in
                    guard let self = self else {
                        subscriber(.failure(State.AttachmentState.Error.expired))
                        return
                    }

                    guard let location = location else {
                        DDLogError("ExtensionViewModel: could not download \(url.absoluteString) - \(String(describing: error))")
                        subscriber(.failure(error ?? State.AttachmentState.Error.unknown))
                        return
                    }

                    do {
                        try self.fileStorage.move(from: location.path, to: file)
                    } catch let error {
                        DDLogError("ExtensionViewModel: can't move downloaded file - \(error)")
                        subscriber(.failure(error))
                        return
                    }

                    subscriber(.success(()))
                }

                self.observe(downloadProgress: task.progress)

                task.resume()
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func observe(downloadProgress: Progress) {
        downloadProgress.observable
                       .observe(on: MainScheduler.instance)
                       .subscribe(onNext: { [weak self] progress in
                           guard let self = self else { return }
                           switch self.state.attachmentState {
                           case .downloading:
                               self.state.attachmentState = .downloading(progress.fractionCompleted)
                           default: break
                           }
                       })
                       .disposed(by: self.disposeBag)
    }

    // MARK: - Submission

    /// Submits translated item (and attachment) to Zotero API. Enqueues background upload if needed.
    func submit() {
        guard self.state.attachmentState.isSubmittable else {
            DDLogError("ExtensionViewModel: tried to submit unsubmittable state")
            return
        }

        self.state.isSubmitting = true

        let tags = self.state.tags.map({ TagResponse(tag: $0.name, type: $0.type) })
        let libraryId: LibraryIdentifier
        let collectionKeys: Set<String>
        let userId = Defaults.shared.userId

        switch self.state.collectionPickerState {
        case .picked(let library, let collection):
            libraryId = library.identifier
            collectionKeys = collection?.identifier.key.flatMap({ [$0] }) ?? []

        default:
            libraryId = ExtensionViewModel.defaultLibraryId
            collectionKeys = []
        }

        if var attachment = self.state.processedAttachment {
            // Update item based on settings
            switch attachment {
            case .item(let item):
                attachment = .item(item.copy(libraryId: libraryId, collectionKeys: collectionKeys, tags: (Defaults.shared.shareExtensionIncludeTags ? item.tags + tags : tags)))

            case .itemWithAttachment(let item, let attachmentData, let attachmentFile):
                let newTags = (Defaults.shared.shareExtensionIncludeTags ? item.tags + tags : tags)
                attachment = .itemWithAttachment(item: item.copy(libraryId: libraryId, collectionKeys: collectionKeys, tags: newTags), attachment: attachmentData, attachmentFile: attachmentFile)

            case .file: break
            }

            switch attachment {
            case .item(let item):
                DDLogInfo("ExtensionViewModel: submit item")
                self.submit(item: item, libraryId: libraryId, userId: userId, apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage,
                            schemaController: self.schemaController, dateParser: self.dateParser)

            case .itemWithAttachment(let item, let attachmentData, let attachmentFile):
                DDLogInfo("ExtensionViewModel: submit item with attachment")
                let data = State.UploadData(item: item, attachmentKey: self.state.attachmentKey, attachmentData: attachmentData, attachmentFile: attachmentFile, linkType: .importedUrl,
                                            defaultTitle: (self.state.title ?? "Unknown"), libraryId: libraryId, userId: userId, dateParser: self.dateParser)
                self.upload(data: data, apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage, webDavController: self.webDavController)

            case .file(let file, let filename):
                DDLogInfo("ExtensionViewModel: upload local file")
                let data = State.UploadData(file: file, filename: filename, attachmentKey: self.state.attachmentKey, linkType: (self.state.url == nil ? .importedFile : .importedUrl),
                                            remoteUrl: self.state.url, collections: collectionKeys, tags: tags, libraryId: libraryId, userId: userId)
                self.upload(data: data, apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage, webDavController: self.webDavController)
            }
        } else if let url = self.state.url {
            DDLogInfo("ExtensionViewModel: submit webpage")

            let date = Date()
            let fields: [KeyBaseKeyPair: String] = [KeyBaseKeyPair(key: FieldKeys.Item.Attachment.url, baseKey: nil): url,
                                                    KeyBaseKeyPair(key: FieldKeys.Item.title, baseKey: nil): (self.state.title ?? "Unknown"),
                                                    KeyBaseKeyPair(key: FieldKeys.Item.accessDate, baseKey: nil): Formatter.iso8601.string(from: date)]

            let webItem = ItemResponse(rawType: ItemTypes.webpage, key: KeyGenerator.newKey, library: LibraryResponse(libraryId: libraryId),
                                       parentKey: nil, collectionKeys: collectionKeys, links: nil, parsedDate: nil, isTrash: false, version: 0,
                                       dateModified: date, dateAdded: date, fields: fields, tags: tags, creators: [], relations: [:], createdBy: nil,
                                       lastModifiedBy: nil, rects: nil, paths: nil)

            self.submit(item: webItem, libraryId: libraryId, userId: userId, apiClient: self.apiClient, dbStorage: self.dbStorage,
                        fileStorage: self.fileStorage, schemaController: self.schemaController, dateParser: self.dateParser)
        } else {
            DDLogInfo("ExtensionViewModel: nothing to submit")
        }
    }

    /// Used for item without attachment. Creates a DB model of item and submits it to Zotero API.
    /// - parameter item: Parsed item to submit.
    /// - parameter libraryId: Identifier of library to which the item will be submitted.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage
    /// - parameter schemaController: Schema controller for validating item type and field types.
    /// - parameter dateParser: Date parser for item creation
    private func submit(item: ItemResponse, libraryId: LibraryIdentifier, userId: Int, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController,
                        dateParser: DateParser) {
        self.createItem(item, libraryId: libraryId, schemaController: schemaController, dateParser: dateParser, queue: self.backgroundQueue)
            .subscribe(on: self.backgroundScheduler)
            .flatMap { parameters, changeUuids in
                return SubmitUpdateSyncAction(parameters: [parameters], changeUuids: changeUuids, sinceVersion: nil, object: .item, libraryId: libraryId, userId: userId, updateLibraryVersion: false,
                                              apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, schemaController: self.schemaController, dateParser: self.dateParser,
                                              queue: self.backgroundQueue, scheduler: self.backgroundScheduler).result
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                self?.state.isDone = true
            }, onFailure: { [weak self] error in
                guard let self = self else { return }

                DDLogError("ExtensionViewModel: could not submit standalone item - \(error)")

                var state = self.state
                state.attachmentState = .failed(self.attachmentError(from: error, libraryId: libraryId))
                state.isSubmitting = false
                self.state = state
            })
            .disposed(by: self.disposeBag)
    }

    private func attachmentError(from error: Error, libraryId: LibraryIdentifier?) -> State.AttachmentState.Error {
        if let error = error as? State.AttachmentState.Error {
            return error
        }
        if let error = error as? Parsing.Error {
            DDLogError("ExtensionViewModel: could not parse item - \(error)")
            return .parseError(error)
        }
        if let error = error as? SchemaError {
            DDLogError("ExtensionViewModel: schema failed - \(error)")
            return .schemaError(error)
        }
        if let error = error as? TranslationWebViewHandler.Error {
            return .webViewError(error)
        }
        if let responseError = error as? AFResponseError {
            return self.alamoErrorRequiresAbort(responseError.error, url: responseError.url, libraryId: libraryId)
        }
        if let alamoError = error as? AFError {
            return self.alamoErrorRequiresAbort(alamoError, url: nil, libraryId: libraryId)
        }
        return .unknown
    }

    private func alamoErrorRequiresAbort(_ error: AFError, url: URL?, libraryId: LibraryIdentifier?) -> State.AttachmentState.Error {
        let defaultError: State.AttachmentState.Error = (url?.absoluteString ?? "").contains(ApiConstants.baseUrlString) ? .apiFailure : .webDavFailure
        switch error {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                if code == 413, let libraryId = libraryId {
                    return .quotaLimit(libraryId)
                }
                return defaultError

            default:
                return defaultError
            }

        default:
            return defaultError
        }
    }

    /// Creates an `RItem` instance in DB.
    /// - parameter item: Parsed item to be created.
    /// - parameter schemaController: Schema controller for validating item type and field types.
    /// - returns: `Single` with `updateParameters` of created `RItem`.
    private func createItem(_ item: ItemResponse, libraryId: LibraryIdentifier, schemaController: SchemaController, dateParser: DateParser, queue: DispatchQueue) -> Single<([String: Any], [String: [String]])> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("ExtensionViewModel: create db item")

            do {
                var changeUuids: [String: [String]] = [:]
                var parameters: [String: Any] = [:]

                try self.dbStorage.perform(on: queue, with: { coordinator in
                    if let collectionKey = item.collectionKeys.first {
                        try coordinator.perform(request: UpdateCollectionLastUsedDbRequest(key: collectionKey, libraryId: libraryId))
                    }

                    let request = CreateBackendItemDbRequest(item: item, schemaController: schemaController, dateParser: dateParser)
                    let item = try coordinator.perform(request: request)
                    parameters = item.updateParameters ?? [:]
                    changeUuids = [item.key: Array(item.changes.map({ $0.identifier }))]

                    coordinator.invalidate()
                })

                subscriber(.success((parameters, changeUuids)))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    /// Used for file uploads. Prepares the item(s) for upload and enqueues a background upload.
    /// - parameter data: Data for upload.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage
    private func upload(data: State.UploadData, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, webDavController: WebDavController) {
        if Defaults.shared.webDavEnabled {
            self.uploadToWebDav(data: data, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, webDavController: webDavController)
        } else {
            self.uploadToZotero(data: data, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
        }
    }

    private func uploadToZotero(data: State.UploadData, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) {
        let authorize = self.submit(data: data, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
                            .flatMap { submissionData -> Single<(AuthorizeUploadResponse, String)> in
                                return AuthorizeUploadSyncAction(key: data.attachment.key, filename: data.filename, filesize: submissionData.filesize, md5: submissionData.md5,
                                                                 mtime: submissionData.mtime, libraryId: data.libraryId, userId: data.userId, oldMd5: nil, apiClient: apiClient,
                                                                 queue: self.backgroundQueue, scheduler: self.backgroundScheduler).result
                                            .flatMap({ return Single.just(($0, submissionData.md5)) })
                            }

        authorize.flatMap { [weak self] response, md5 -> Single<()> in
            guard let self = self else { return Single.error(State.AttachmentState.Error.expired) }
            
            switch response {
            case .exists(let version):
                DDLogInfo("ExtensionViewModel: file exists remotely")
                
                do {
                    let request = MarkAttachmentUploadedDbRequest(libraryId: data.libraryId, key: data.attachment.key, version: version)
                    let request2 = UpdateVersionsDbRequest(version: version, libraryId: data.libraryId, type: .object(.item))
                    try dbStorage.perform(writeRequests: [request, request2], on: self.backgroundQueue)
                    return Single.just(())
                } catch let error {
                    return Single.error(error)
                }
                
            case .new(let response):
                DDLogInfo("ExtensionViewModel: upload authorized")
                
                // sessionId and size are set by background uploader.
                let upload = BackgroundUpload(type: .zotero(uploadKey: response.uploadKey), key: self.state.attachmentKey, libraryId: data.libraryId, userId: data.userId,
                                              remoteUrl: response.url, fileUrl: data.file.createUrl(), md5: md5, date: Date())
                return self.backgroundUploader.start(upload: upload, filename: data.filename, mimeType: ExtensionViewModel.defaultMimetype, parameters: response.params,
                                                     headers: ["If-None-Match": "*"], delegate: self.backgroundUploadObserver)
                .flatMap({ session in
                    self.backgroundUploadObserver.startObservingInShareExtension(session: session)
                    return Single.just(())
                })
            }
        }
        .observe(on: MainScheduler.instance)
        .subscribe(onSuccess: { [weak self] _ in
            self?.state.isDone = true
        }, onFailure: { [weak self] error in
            guard let self = self else { return }
            
            DDLogError("ExtensionViewModel: could not submit item or attachment - \(error)")
            
            var state = self.state
            state.attachmentState = .failed(self.attachmentError(from: error, libraryId: data.libraryId))
            state.isSubmitting = false
            self.state = state
        })
        .disposed(by: self.disposeBag)
    }

    private func uploadToWebDav(data: State.UploadData, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, webDavController: WebDavController) {
        let prepare = self.submit(data: data, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
                          .flatMap { submissionData -> Single<(WebDavUploadResult, SubmissionData)> in
                              return webDavController.prepareForUpload(key: data.attachment.key, mtime: submissionData.mtime, hash: submissionData.md5, file: data.file, queue: self.backgroundQueue)
                                                     .flatMap({ return Single.just(($0, submissionData)) })
                          }

        prepare.flatMap { [weak self] response, submissionData -> Single<()> in
            guard let self = self else { return Single.error(State.AttachmentState.Error.expired) }

            switch response {
            case .exists:
                DDLogInfo("ExtensionViewModel: file exists remotely")

                do {
                    let request = MarkAttachmentUploadedDbRequest(libraryId: data.libraryId, key: data.attachment.key, version: nil)
                    try dbStorage.perform(request: request, on: self.backgroundQueue)
                    return Single.just(())
                } catch let error {
                    return Single.error(error)
                }

            case .new(let url, let file):
                DDLogInfo("ExtensionViewModel: upload authorized")

                let upload = BackgroundUpload(type: .webdav(mtime: submissionData.mtime), key: self.state.attachmentKey, libraryId: data.libraryId, userId: data.userId,
                                              remoteUrl: url, fileUrl: file.createUrl(), md5: submissionData.md5, date: Date())
                return self.backgroundUploader.start(upload: upload, filename: (data.attachment.key + ".zip"), mimeType: ExtensionViewModel.zipMimetype, parameters: [:], headers: [:],
                                                     delegate: self.backgroundUploadObserver)
                           .flatMap({ session in
                               self.backgroundUploadObserver.startObservingInShareExtension(session: session)
                               return Single.just(())
                           })
            }
        }
        .observe(on: MainScheduler.instance)
        .subscribe(onSuccess: { [weak self] _ in
            self?.state.isDone = true
        }, onFailure: { [weak self] error in
            guard let self = self else { return }

            DDLogError("ExtensionViewModel: could not submit item or attachment - \(error)")

            var state = self.state
            state.attachmentState = .failed(self.attachmentError(from: error, libraryId: data.libraryId))
            state.isSubmitting = false
            self.state = state
        })
        .disposed(by: self.disposeBag)
    }

    private func submit(data: State.UploadData, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) -> Single<SubmissionData> {
        switch data.type {
        case .file(let location, let collections, let tags):
            DDLogInfo("ExtensionViewModel: prepare upload for local file")
            return self.prepareAndSubmit(attachment: data.attachment, collections: collections, tags: tags, file: data.file, tmpFile: location, libraryId: data.libraryId, userId: data.userId,
                                         apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)

        case .translated(let item, let location):
            DDLogInfo("ExtensionViewModel: prepare upload for local file")
            return self.prepareAndSubmit(item: item, attachment: data.attachment, file: data.file, tmpFile: location, libraryId: data.libraryId, userId: data.userId, apiClient: apiClient,
                                         dbStorage: dbStorage, fileStorage: fileStorage)
        }
    }

    /// Prepares for file upload. Copies local file to new location appropriate for new item. Creates `RItem` instance in DB for attachment. Submits new `RItem`s to Zotero API.
    /// - parameter attachment: Attachment to be created and submitted.
    /// - parameter collections: Collections to which the attachment is assigned.
    /// - parameter tags: Tags picked by user.
    /// - parameter file: File to upload.
    /// - parameter tmpFile: Original file.
    /// - parameter filename: Filename of file to upload.
    /// - parameter libraryId: Identifier of library to which items will be submitted.
    /// - parameter userId: Id of current user.
    /// - parameter apiClient: API client.
    /// - parameter dbStorage: Database storage.
    /// - parameter fileStorage: File storage.
    /// - parameter webDavController: WebDAV controller.
    /// - returns: `Single` with Authorization response and md5 hash of file.
    private func prepareAndSubmit(attachment: Attachment, collections: Set<String>, tags: [TagResponse], file: File, tmpFile: File, libraryId: LibraryIdentifier, userId: Int,
                                  apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) -> Single<SubmissionData> {
        return self.moveFile(from: tmpFile, to: file)
                   .subscribe(on: self.backgroundScheduler)
                   .flatMap { [weak self] filesize -> Single<([String: Any], [String: [String]], SubmissionData)> in
                       guard let self = self else { return Single.error(State.AttachmentState.Error.expired) }
                       return self.create(attachment: attachment, collections: collections, tags: tags, queue: self.backgroundQueue)
                                  .flatMap({ Single.just(($0, $1, SubmissionData(filesize: filesize, md5: $2, mtime: $3))) })
                                  .do(onError: { [weak self] _ in
                                      // If attachment item couldn't be created in DB, remove the moved file if possible, it won't be processed even from the main app
                                      try? self?.fileStorage.remove(file)
                                  })
                   }
                   .flatMap { parameters, changeUuids, data -> Single<SubmissionData> in
                       return SubmitUpdateSyncAction(parameters: [parameters], changeUuids: changeUuids, sinceVersion: nil, object: .item, libraryId: libraryId, userId: userId,
                                                     updateLibraryVersion: false, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, schemaController: self.schemaController,
                                                     dateParser: self.dateParser, queue: self.backgroundQueue, scheduler: self.backgroundScheduler).result
                                    .flatMap({ _ in Single.just(data) })
                   }
    }

    /// Prepares for file upload. Moves file to new location appropriate for new item. Creates `RItem` instances in DB for item and attachment. Submits new `RItem`s to Zotero API.
    /// - parameter item: Item to be created and submitted.
    /// - parameter attachment: Attachment to be created and submitted.
    /// - parameter file: File to upload.
    /// - parameter tmpFile: Original file.
    /// - parameter filename: Filename of file to upload.
    /// - parameter libraryId: Identifier of library to which items will be submitted.
    /// - parameter userId: Id of current user.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage
    /// - returns: `Single` with Authorization response and md5 hash of file.
    private func prepareAndSubmit(item: ItemResponse, attachment: Attachment, file: File, tmpFile: File, libraryId: LibraryIdentifier, userId: Int,
                                  apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) -> Single<SubmissionData> {
        return self.moveFile(from: tmpFile, to: file)
                   .subscribe(on: self.backgroundScheduler)
                   .flatMap { [weak self] filesize -> Single<([[String: Any]], [String: [String]], SubmissionData)> in
                       guard let self = self else { return Single.error(State.AttachmentState.Error.expired) }
                       return self.createItems(item: item, attachment: attachment, queue: self.backgroundQueue)
                                  .flatMap({ Single.just(($0, $1, SubmissionData(filesize: filesize, md5: $2, mtime: $3))) })
                                  .do(onError: { [weak self] _ in
                                      // If attachment item couldn't be created in DB, remove the moved file if possible, it won't be processed even from the main app
                                      try? self?.fileStorage.remove(file)
                                  })
                   }
                   .flatMap { parameters, changeUuids, data -> Single<SubmissionData> in
                       return SubmitUpdateSyncAction(parameters: parameters, changeUuids: changeUuids, sinceVersion: nil, object: .item, libraryId: libraryId, userId: userId,
                                                     updateLibraryVersion: false, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage, schemaController: self.schemaController,
                                                     dateParser: self.dateParser, queue: self.backgroundQueue, scheduler: self.backgroundScheduler).result
                                    .flatMap({ _ in Single.just(data) })
                   }
    }

    /// Moves downloaded file from temporary folder to file appropriate for given attachment item.
    /// - parameter from: `File` where from the file is being moved.
    /// - parameter to: `File` where the file needs to be moved.
    /// - returns: `Single` with size of file.
    private func moveFile(from fromFile: File, to toFile: File) -> Single<UInt64> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("ExtensionViewModel: move file to attachment folder")

            do {
                let size = self.fileStorage.size(of: fromFile)
                if size == 0 {
                    subscriber(.failure(State.AttachmentState.Error.fileMissing))
                    return Disposables.create()
                }
                try self.fileStorage.move(from: fromFile, to: toFile)
                subscriber(.success(size))
            } catch let error {
                DDLogError("ExtensionViewModel: can't move file: \(error)")
                // If tmp file couldn't be moved, remove it if it's there
                try? self.fileStorage.remove(fromFile)
                subscriber(.failure(State.AttachmentState.Error.fileMissing))
            }

            return Disposables.create()
        }
    }

    /// Copies local file from temporary folder to file appropriate for given attachment item.
    /// - parameter from: `File` where from the file is being moved.
    /// - parameter to: `File` where the file needs to be moved.
    /// - returns: `Single` with size of file.
    private func copyFile(from path: String, to toFile: File) -> Single<UInt64> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("ExtensionViewModel: copy file to attachment folder")

            do {
                let size = self.fileStorage.size(of: path)
                if size == 0 {
                    subscriber(.failure(State.AttachmentState.Error.fileMissing))
                    return Disposables.create()
                }
                try self.fileStorage.copy(from: path, to: toFile)
                subscriber(.success(size))
            } catch let error {
                DDLogError("ExtensionViewModel: can't copy file: \(error)")
                subscriber(.failure(State.AttachmentState.Error.fileMissing))
            }

            return Disposables.create()
        }
    }

    /// Creates `RItem` instances in DB from parsed item and attachement.
    /// - parameter item: Parsed item to be created.
    /// - parameter attachment: Parsed attachment to be created.
    /// - returns: `Single` with `updateParameters` of both new items, md5 and mtime of attachment.
    private func createItems(item: ItemResponse, attachment: Attachment, queue: DispatchQueue) -> Single<([[String: Any]], [String: [String]], String, Int)> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("ExtensionViewModel: create item and attachment db items")

            do {
                var parameters: [[String: Any]] = []
                var changeUuids: [String: [String]] = [:]
                var mtime: Int?
                var md5: String?

                try self.dbStorage.perform(on: queue, with: { coordinator in
                    if let collectionKey = item.collectionKeys.first {
                        try coordinator.perform(request: UpdateCollectionLastUsedDbRequest(key: collectionKey, libraryId: attachment.libraryId))
                    }

                    let request = CreateItemWithAttachmentDbRequest(item: item, attachment: attachment, schemaController: self.schemaController, dateParser: self.dateParser)
                    let (item, attachment) = try coordinator.perform(request: request)

                    if let updateParameters = item.updateParameters {
                        parameters.append(updateParameters)
                    }
                    if let updateParameters = attachment.updateParameters {
                        parameters.append(updateParameters)
                    }
                    changeUuids = [item.key: Array(item.changes.map({ $0.identifier })), attachment.key: Array(attachment.changes.map({ $0.identifier }))]

                    mtime = attachment.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first.flatMap({ Int($0.value) })
                    md5 = attachment.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value

                    coordinator.invalidate()
                })

                guard let mtime = mtime else { throw State.AttachmentState.Error.mtimeMissing }
                guard let md5 = md5 else { throw State.AttachmentState.Error.md5Missing }

                subscriber(.success((parameters, changeUuids, md5, mtime)))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    /// Creates `RItem` instance in DB from parsed attachement.
    /// - parameter attachment: Parsed attachment to be created.
    /// - parameter collections: Set of collections to which the attachment is assigned.
    /// - parameter tags: Tags picked by user.
    /// - returns: `Single` with `updateParameters` of both new items, md5 and mtime of attachment.
    private func create(attachment: Attachment, collections: Set<String>, tags: [TagResponse], queue: DispatchQueue) -> Single<([String: Any], [String: [String]], String, Int)> {
        return Single.create { subscriber -> Disposable in
            DDLogInfo("ExtensionViewModel: create attachment db item")

            let localizedType = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""

            do {
                var updateParameters: [String: Any]?
                var changeUuids: [String: [String]]?
                var md5: String?
                var mtime: Int?

                try self.dbStorage.perform(on: queue, with: { coordinator in
                    if let collectionKey = collections.first {
                        try coordinator.perform(request: UpdateCollectionLastUsedDbRequest(key: collectionKey, libraryId: attachment.libraryId))
                    }

                    let request = CreateAttachmentDbRequest(attachment: attachment, parentKey: nil, localizedType: localizedType, includeAccessDate: attachment.hasUrl, collections: collections, tags: tags)
                    let attachment = try coordinator.perform(request: request)

                    updateParameters = attachment.updateParameters
                    changeUuids = [attachment.key: Array(attachment.changes.map({ $0.identifier }))]
                    mtime = attachment.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first.flatMap({ Int($0.value) })
                    md5 = attachment.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value

                    coordinator.invalidate()
                })

                guard let mtime = mtime else { throw State.AttachmentState.Error.mtimeMissing }
                guard let md5 = md5 else { throw State.AttachmentState.Error.md5Missing }

                subscriber(.success(((updateParameters ?? [:]), (changeUuids ?? [:]), md5, mtime)))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    // MARK: - Collection picker

    func set(collection: Collection?, library: Library) {
        self.updateSelected(collection: collection, library: library) { state in
            if let new = state.recents.first(where: { $0.collection?.identifier == collection?.identifier && $0.library.identifier == library.identifier }) {
                if new.isRecent && !state.recents[0].isRecent {
                    state.recents.removeFirst()
                }
            } else {
                if !state.recents[0].isRecent {
                    state.recents[0] = RecentData(collection: collection, library: library, isRecent: false)
                } else {
                    state.recents.insert(RecentData(collection: collection, library: library, isRecent: false), at: 0)
                }
            }
        }
    }

    func setFromRecent(collection: Collection?, library: Library) {
        self.updateSelected(collection: collection, library: library)
    }

    private func updateSelected(collection: Collection?, library: Library, additionalStateChange: ((inout State) -> Void)? = nil) {
        var state = self.state
        state.selectedLibraryId = library.identifier
        state.selectedCollectionId = collection?.identifier ?? Collection(custom: .all).identifier
        state.collectionPickerState = .picked(library, collection)
        if let change = additionalStateChange {
            change(&state)
        }
        self.state = state

        Defaults.shared.selectedCollectionId = state.selectedCollectionId
        Defaults.shared.selectedLibrary = state.selectedLibraryId
    }

    // MARK: - Tag picker

    func set(tags: [Tag]) {
        self.state.tags = tags
    }

    // MARK: - Sync

    private func setupSyncObserving() {
        self.syncController.observable
                           .observe(on: MainScheduler.instance)
                           .subscribe(onNext: { [weak self] data in
                               self?.finishSync(successful: (data == nil))
                           }, onError: { [weak self] _ in
                               self?.finishSync(successful: false)
                           })
                           .disposed(by: self.disposeBag)
    }

    private func finishSync(successful: Bool) {
        guard successful else {
            self.state.collectionPickerState = .failed
            return
        }

        do {
            var library: Library?
            var collection: Collection?
            var recents: [RecentData] = []

            try self.dbStorage.perform(on: .main, with: { coordinator in
                let request = ReadCollectionAndLibraryDbRequest(collectionId: self.state.selectedCollectionId, libraryId: self.state.selectedLibraryId)
                let (_collection, _library) = try coordinator.perform(request: request)

                let recentCollections = try coordinator.perform(request: ReadRecentCollections(excluding: nil))

                recents = recentCollections
                library = _library
                collection = _collection
            })

            guard let library = library else { return }

            if !recents.contains(where: { $0.collection?.identifier == collection?.identifier && $0.library.identifier == library.identifier }) {
                recents.insert(RecentData(collection: collection, library: library, isRecent: false), at: 0)
            }

            var state = self.state
            state.collectionPickerState = .picked(library, collection)
            state.recents = recents
            self.state = state
        } catch let error {
            DDLogError("ExtensionViewModel: can't load collections - \(error)")
            let library = Library(identifier: ExtensionViewModel.defaultLibraryId, name: RCustomLibraryType.myLibrary.libraryName, metadataEditable: true, filesEditable: true)
            self.state.collectionPickerState = .picked(library, nil)
        }
    }
}
