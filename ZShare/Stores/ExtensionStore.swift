//
//  ExtensionStore.swift
//  ZShare
//
//  Created by Michal Rentka on 25/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation
import MobileCoreServices
import WebKit

import CocoaLumberjack
import RxSwift
import RxAlamofire

/// `ExtensionStore` performs fetching of basic website data, runs the translation server which translates the web data, downloads item data with
/// pdf attachment if available and uploads new item to Zotero.
///
/// These steps are performed for each share:
/// 1. Website data (url, title, cookies and full HTML) are loaded from `NSExtensionItem`,
/// 2. Translation server is run in a hidden WebView (handled by `WebViewHandler`). It loads item data and attachment if available,
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
class ExtensionStore {
    struct State {
        enum CollectionPicker {
            case loading, failed
            case picked(Library, Collection?)

            var library: Library? {
                switch self {
                case .picked(let library, _):
                    return library
                default:
                    return nil
                }
            }
        }

        struct ItemPicker {
            let items: [String: String]
            var picked: String?
        }

        /// State for translation process.
        /// - translating: Translation is in progress. This is the initial state.
        /// - translated: Translation has ended. The item doesn't have an attachment.
        /// - downloading: Translation has ended. The item has an attachment which is being downloaded.
        /// - downloaded: Translation has ended. The item has an attachment which has been successfully downloaded.
        /// - failed: The translation process or attachment download failed.
        enum Translation {
            enum Error: Swift.Error {
                case cantLoadSchema, cantLoadWebData, downloadFailed, itemsNotFound, expired, unknown
                case webViewError(WebViewHandler.Error)
                case parseError(ItemResponse.Error)
            }

            case translating
            case translated(ItemResponse)
            case downloading(ItemResponse, [String: String], Float)
            case downloaded(ItemResponse, [String: String])
            case failed(Error)
        }

        /// State for submission of translated item (and attachment).
        /// - preparing: Preparing the submission. Item submission request is sent. If the Item has an attachment, it is prepared for upload and
        ///              another request is sent to authorize the upload.
        /// - ready: The item has been submitted. If attachment was available, it's ready for background upload. The extension can be closed.
        /// - error: The submission process failed.
        enum Submission: Equatable {
            enum Error: Swift.Error, Equatable {
                case expired, fileMissing, unknown
            }

            case preparing
            case ready
            case error(Error)
        }

        let attachmentKey: String
        var title: String?
        var collectionPicker: CollectionPicker
        var translation: Translation
        var submission: Submission?
        var itemPicker: ItemPicker?

        init() {
            self.attachmentKey = KeyGenerator.newKey
            self.collectionPicker = .loading
            self.translation = .translating
        }
    }

    @Published var state: State
    // The background uploader is optional because it needs to be deinitialized after starting the upload. See more in comment where the uploader is nilled.
    private var backgroundUploader: BackgroundUploader?

    private static let defaultLibraryId: LibraryIdentifier = .custom(.myLibrary)
    private static let defaultExtension = "pdf"
    private static let defaultMimetype = "application/pdf"

    private let syncController: SyncController
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let dateParser: DateParser
    private let webViewHandler: WebViewHandler
    private let disposeBag: DisposeBag

    init(webView: WKWebView, apiClient: ApiClient, backgroundUploader: BackgroundUploader,
         dbStorage: DbStorage, schemaController: SchemaController, dateParser: DateParser, fileStorage: FileStorage,
         syncController: SyncController, translatorsController: TranslatorsController) {
        self.syncController = syncController
        self.apiClient = apiClient
        self.backgroundUploader = backgroundUploader
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.webViewHandler = WebViewHandler(webView: webView, translatorsController: translatorsController)
        self.state = State()
        self.disposeBag = DisposeBag()

        self.setupSyncObserving()
        self.setupWebHandlerObserving()
    }

    // MARK: - Actions

    func start(with extensionItem: NSExtensionItem) {
        // Start sync in background, so that collections are available for user to pick
        self.syncController.start(type: .normal, libraries: .all)
        // Start the translation process
        self.loadDocument(with: extensionItem)
    }

    func cancel() {
        // Remove temporary downloaded file if it exists
        let file = Files.shareExtensionTmpItem(key: self.state.attachmentKey, ext: ExtensionStore.defaultExtension)
        try? self.fileStorage.remove(file)
    }

    // MARK: - Web data loading

    /// Loads document data and starts translation process if successful.
    private func loadDocument(with extensionItem: NSExtensionItem) {
        self.loadWebData(extensionItem: extensionItem)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] title, url, html, cookies in
                self?.state.title = title
                self?.webViewHandler.translate(url: url, title: title, html: html, cookies: cookies)
            }, onError: { [weak self] error in
                self?.state.translation = .failed((error as? State.Translation.Error) ?? .unknown)
            })
            .disposed(by: self.disposeBag)
    }

    /// Creates an Observable for NSExtensionItem to load web data.
    /// - parameter extensionItem: `NSExtensionItem` passed from `NSExtensionContext` from share extension view controller.
    /// - returns: Observable for loading: title, url, full HTML, cookies.
    private func loadWebData(extensionItem: NSExtensionItem) -> Observable<(String, URL, String, String)> {
        let propertyList = kUTTypePropertyList as String

        guard let itemProvider = extensionItem.attachments?.first,
              itemProvider.hasItemConformingToTypeIdentifier(propertyList) else {
            return Observable.error(State.Translation.Error.cantLoadWebData)
        }

        return Observable.create { [weak itemProvider] subscriber in
            guard let itemProvider = itemProvider else { return Disposables.create() }

            itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { item, error -> Void in
                guard let scriptData = item as? [String: Any],
                      let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else {
                    subscriber.onError(State.Translation.Error.cantLoadWebData)
                    return
                }

                if let url = (data["url"] as? String).flatMap(URL.init),
                   let title = data["title"] as? String,
                   let html = data["html"] as? String,
                   let cookies = data["cookies"] as? String {
                    subscriber.onNext((title, url, html, cookies))
                    subscriber.onCompleted()
                } else {
                    subscriber.onError(State.Translation.Error.cantLoadWebData)
                }
            })

            return Disposables.create()
        }
    }

    // MARK: - Translation

    /// Observes `WebViewHandler` translation process and acts accordingly.
    private func  setupWebHandlerObserving() {
        self.webViewHandler.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] action in
                               switch action {
                               case .loadedItems(let data):
                                   self?.processItems(data)
                               case .selectItem(let data):
                                    self?.state.itemPicker = State.ItemPicker(items: data, picked: nil)
                               }
                           }, onError: { [weak self] error in
                               self?.state.translation = .failed((error as? WebViewHandler.Error).flatMap({ .webViewError($0) }) ?? .unknown)
                           })
                           .disposed(by: self.disposeBag)

    }

    /// Parses item from translation response, starts attachment download if available.
    private func processItems(_ data: [[String: Any]]) {
        do {
            let (item, attachment) = try self.parse(data, schemaController: self.schemaController)
            if let attachment = attachment,
               let urlString = attachment["url"],
               let url = URL(string: urlString) {
                self.state.translation = .downloading(item, attachment, 0)
                self.startDownload(for: url)
            } else {
                self.state.translation = .translated(item)
            }
        } catch let error as ItemResponse.Error {
            self.state.translation = .failed(.parseError(error))
        } catch let error as State.Translation.Error {
            self.state.translation = .failed(error)
        } catch {
            self.state.translation = .failed(.unknown)
        }
    }

    /// Tries to parse `ItemResponse` from data returned by translation server. It prioritizes items with attachments if there are multiple items.
    /// - parameter data: Data to parse
    /// - parameter schemaController: SchemaController which is used for validating item type and field types
    /// - returns: `ItemResponse` of parsed item and optional attachment dictionary with title and url.
    private func parse(_ data: [[String: Any]], schemaController: SchemaController) throws -> (ItemResponse, [String: String]?) {
        // Sort items so that the first item will have a PDF attachment (if available)
        let sortedData = data.sorted { left, right -> Bool in
            let leftAttachments = (left["attachments"] as? [[String: String]]) ?? []
            let leftHasPdf = leftAttachments.contains(where: { $0["mimeType"] == ExtensionStore.defaultMimetype })
            let rightAttachments = (right["attachments"] as? [[String: String]]) ?? []
            let rightHasPdf = rightAttachments.contains(where: { $0["mimeType"] == ExtensionStore.defaultMimetype })

            if !leftHasPdf && rightHasPdf {
                return false
            }
            return true
        }

        guard let itemData = sortedData.first else {
            throw State.Translation.Error.itemsNotFound
        }

        let item = try ItemResponse(response: itemData, schemaController: self.schemaController)
        let attachment = (itemData["attachments"] as? [[String: String]])?.first(where: { $0["mimeType"] == ExtensionStore.defaultMimetype })

        return (item, attachment)
    }

    /// Sets picked item if multiple items were found.
    func pickItem(_ data: (String, String)) {
        self.state.itemPicker?.picked = data.1
        self.webViewHandler.selectItem(data)
    }

    // MARK: - Attachment Download

    /// Starts download of PDF attachment. Downloads it to temporary folder.
    /// - parameter url: URL of file to download
    private func startDownload(for url: URL) {
        let file = Files.shareExtensionTmpItem(key: self.state.attachmentKey, ext: ExtensionStore.defaultExtension)
        let request = FileRequest(data: .external(url), destination: file)
        self.apiClient.download(request: request)
                      .flatMap { request in
                          return request.rx.progress()
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] progress in
                          self?.setDownloadProgress(progress.completed)
                      }, onError: { [weak self] error in
                          self?.state.translation = .failed(.downloadFailed)
                      }, onCompleted: { [weak self] in
                          self?.finishDownload()
                      })
                      .disposed(by: self.disposeBag)
    }

    /// Sets current download progress if downloading has started.
    /// - parameter progress: Progress
    private func setDownloadProgress(_ progress: Float) {
        switch self.state.translation {
        case .downloading(let response, let attachment, _):
            self.state.translation = .downloading(response, attachment, progress)
        default: break
        }
    }

    private func finishDownload() {
        switch self.state.translation {
        case .downloading(let response, let attachment, _):
            self.state.translation = .downloaded(response, attachment)
        default: break
        }
    }

    // MARK: - Submission

    /// Submits translated item (and attachment) to Zotero API. Enqueues background upload if needed.
    func submit() {
        let libraryId: LibraryIdentifier
        let collectionKeys: Set<String>
        let userId = Defaults.shared.userId

        switch self.state.collectionPicker {
        case .picked(let library, let collection):
            libraryId = library.identifier
            collectionKeys = collection.flatMap({ [$0.key] }) ?? []
        default:
            libraryId = ExtensionStore.defaultLibraryId
            collectionKeys = []
        }

        self.state.submission = .preparing

        switch self.state.translation {
        case .translated(let item):
            self.submit(item: item.copy(libraryId: libraryId, collectionKeys: collectionKeys), libraryId: libraryId, userId: userId,
                        apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage, schemaController: self.schemaController)

        case .downloaded(let item, let attachmentData):
            let newItem = item.copy(libraryId: libraryId, collectionKeys: collectionKeys)
            let filename = attachmentData["title"] ?? self.state.title ?? "Unknown"
            let file = Files.attachmentFile(in: libraryId, key: self.state.attachmentKey, ext: ExtensionStore.defaultExtension)
            let attachment = Attachment(key: self.state.attachmentKey,
                                        title: filename,
                                        type: .file(file: file, filename: filename, location: .local),
                                        libraryId: libraryId)
            self.upload(item: newItem, attachment: attachment, file: file, filename: filename, libraryId: libraryId, userId: userId,
                        apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage)

        default: break
        }
    }

    /// Used for item without attachment. Creates a DB model of item and submits it to Zotero API.
    /// - parameter item: Parsed item to submit.
    /// - parameter libraryId: Identifier of library to which the item will be submitted.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage
    /// - parameter schemaController: Schema controller for validating item type and field types.
    private func submit(item: ItemResponse, libraryId: LibraryIdentifier, userId: Int,
                        apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController) {
        self.createItem(item, schemaController: schemaController)
            .flatMap { parameters in
                return SubmitUpdateSyncAction(parameters: [parameters], sinceVersion: nil, object: .item, libraryId: libraryId,
                                              userId: userId, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage,
                                              queue: .main, scheduler: MainScheduler.instance).result
            }
            .subscribe(onSuccess: { [weak self] _ in
                self?.state.submission = .ready
            }, onError: { [weak self] error in
                let error = (error as? State.Submission.Error) ?? .unknown
                self?.state.submission = .error(error)
            })
            .disposed(by: self.disposeBag)
    }

    /// Creates an `RItem` instance in DB.
    /// - parameter item: Parsed item to be created.
    /// - parameter schemaController: Schema controller for validating item type and field types.
    /// - returns: `Single` with `updateParameters` of created `RItem`.
    private func createItem(_ item: ItemResponse, schemaController: SchemaController) -> Single<[String: Any]> {
        let request = CreateBackendItemDbRequest(item: item, schemaController: schemaController, dateParser: self.dateParser)
        do {
            let item = try self.dbStorage.createCoordinator().perform(request: request)
            return Single.just(item.updateParameters ?? [:])
        } catch let error {
            return Single.error(error)
        }
    }

    /// Used for item with attachment. Prepares the item for upload and enqueues a background upload.
    /// - parameter item: Parsed item to submit.
    /// - parameter attachment: Parsed attachment to submit.
    /// - parameter file: File to upload.
    /// - parameter filename: Filename of file to upload.
    /// - parameter libraryId: Identifier of library to which items will be submitted.
    /// - parameter userId: Id of current user.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage
    private func upload(item: ItemResponse, attachment: Attachment, file: File, filename: String, libraryId: LibraryIdentifier, userId: Int,
                        apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) {
        self.prepareUpload(item: item, attachment: attachment, file: file, filename: filename,
                       libraryId: libraryId, userId: userId, apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage)
            .subscribe(onSuccess: { [weak self] response, md5 in
                guard let `self` = self else { return }

                switch response {
                case .exists:
                    self.state.submission = .ready

                case .new(let response):
                    self.startBackgroundUpload(to: response.url,
                                               filename: filename,
                                               file: file,
                                               params: response.params,
                                               key: attachment.key,
                                               uploadKey: response.uploadKey,
                                               md5: md5,
                                               libraryId: libraryId,
                                               userId: userId)
                }
            }, onError: { [weak self] error in
                let error = (error as? State.Submission.Error) ?? .unknown
                self?.state.submission = .error(error)
            })
            .disposed(by: self.disposeBag)
    }

    /// Prepares for file upload. Moves file to new location appropriate for new item. Creates `RItem` instances in DB for item and attachment.
    /// Submits new `RItem`s to Zotero API. Authorizes new upload to Zotero API.
    /// - parameter item: Item to be created and submitted.
    /// - parameter attachment: Attachment to be created and submitted.
    /// - parameter file: File to upload.
    /// - parameter filename: Filename of file to upload.
    /// - parameter libraryId: Identifier of library to which items will be submitted.
    /// - parameter userId: Id of current user.
    /// - parameter apiClient: API client
    /// - parameter dbStorage: Database storage
    /// - parameter fileStorage: File storage 
    /// - returns: `Single` with Authorization response and md5 hash of file.
    private func prepareUpload(item: ItemResponse, attachment: Attachment, file: File, filename: String, libraryId: LibraryIdentifier, userId: Int,
                               apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) -> Single<(AuthorizeUploadResponse, String)> {
        return self.moveTmpFile(with: attachment.key, to: file, libraryId: libraryId)
                   .flatMap { [weak self] filesize -> Single<(UInt64, [[String: Any]], String, Int)> in
                       guard let `self` = self else { return Single.error(State.Submission.Error.expired) }
                       return self.createItems(item: item, attachment: attachment)
                                  .flatMap({ Single.just((filesize, $0, $1, $2)) })
                                  .do(onError: { [weak self] _ in
                                      // If attachment item couldn't be created in DB, remove the moved file if possible,
                                      // it won't be processed even from the main app
                                      try? self?.fileStorage.remove(file)
                                  })
                   }
                   .flatMap { filesize, parameters, md5, mtime -> Single<(UInt64, String, Int)> in
                    return SubmitUpdateSyncAction(parameters: parameters, sinceVersion: nil, object: .item, libraryId: libraryId, userId: userId,
                                                  apiClient: apiClient, dbStorage: dbStorage, fileStorage: fileStorage,
                                                  queue: .main, scheduler: MainScheduler.instance).result
                                    .flatMap({ _ in Single.just((filesize, md5, mtime)) })
                   }
                   .flatMap { filesize, md5, mtime -> Single<(AuthorizeUploadResponse, String)> in
                       return AuthorizeUploadSyncAction(key: attachment.key, filename: filename, filesize: filesize, md5: md5, mtime: mtime,
                                                        libraryId: libraryId, userId: userId, apiClient: apiClient,
                                                        queue: .main, scheduler: MainScheduler.instance).result
                                    .flatMap({ return Single.just(($0, md5)) })
                   }
    }

    /// Enqueues a `BackgroundUpload` in `BackgroundUploader`.
    /// - parameter url: `URL` of file to upload.
    /// - parameter filename: Filename of file to upload.
    /// - parameter file: File to upload.
    /// - parameter params: Parameters returned by Zotero API which need to be included in the upload request.
    /// - parameter key: Attachment key in Zotero API.
    /// - parameter uploadKey: Upload key returned by authorization request.
    /// - parameter md5: MD5 hash of file.
    /// - parameter libraryId: Id of library of attachment.
    /// - parameter userId: Id of current user.
    private func startBackgroundUpload(to url: URL, filename: String, file: File, params: [String: String],
                                       key: String, uploadKey: String, md5: String, libraryId: LibraryIdentifier, userId: Int) {
        guard let backgroundUploader = self.backgroundUploader else { return }
        let upload = BackgroundUpload(key: key,
                                      libraryId: libraryId,
                                      userId: userId,
                                      remoteUrl: url,
                                      fileUrl: file.createUrl(),
                                      uploadKey: uploadKey,
                                      md5: md5)
        backgroundUploader.upload(upload,
                                  filename: filename,
                                  mimeType: ExtensionStore.defaultMimetype,
                                  parameters: params,
                                  headers: ["If-None-Match": "*"]) { [weak self] error in
                                      if let error = error {
                                          DDLogError("ExtensionStore: can't start upload - \(error)")
                                          self?.state.submission = .error(.unknown)
                                      } else {
                                          // The uploader is set to nil so that the URLSession delegate no longer exists for the share extension. This
                                          // way the URLSession delegate will always be called in the main (container) app, where additional upload
                                          // processing is performed.
                                          self?.backgroundUploader = nil
                                          self?.state.submission = .ready
                                      }
                                  }
    }

    /// Moves downloaded file from temporary folder to file appropriate for given attachment item.
    /// - parameter key: Key of attachment in Zotero API.
    /// - parameter file: `File` where the temporary file needs to be moved.
    /// - parameter libraryId: Id of library of new attachment.
    /// - returns: `Single` with size of file.
    private func moveTmpFile(with key: String, to file: File, libraryId: LibraryIdentifier) -> Single<UInt64> {
        let tmpFile = Files.shareExtensionTmpItem(key: key, ext: ExtensionStore.defaultExtension)

        do {
            let size = self.fileStorage.size(of: tmpFile)
            if size == 0 {
                return Single.error(State.Submission.Error.fileMissing)
            }
            try self.fileStorage.move(from: tmpFile, to: file)
            return Single.just(size)
        } catch {
            // If tmp file couldn't be moved, remove it if it's there
            try? self.fileStorage.remove(tmpFile)
            return Single.error(State.Submission.Error.fileMissing)
        }
    }

    /// Creates `RItem` instances in DB from parsed item and attachement.
    /// - parameter item: Parsed item to be created.
    /// - parameter attachment: Parsed attachment to be created.
    /// - returns: `Single` with `updateParameters` of both new items, md5 and mtime of attachment.
    private func createItems(item: ItemResponse, attachment: Attachment) -> Single<([[String: Any]], String, Int)> {
        let request = CreateItemWithAttachmentDbRequest(item: item, attachment: attachment,
                                                        schemaController: self.schemaController, dateParser: self.dateParser)
        do {
            let (item, attachment) = try self.dbStorage.createCoordinator().perform(request: request)

            let mtime = attachment.fields.filter(.key(FieldKeys.mtime)).first.flatMap({ Int($0.value) }) ?? 0
            let md5 = attachment.fields.filter(.key(FieldKeys.md5)).first?.value ?? ""

            var parameters: [[String: Any]] = []
            if let updateParameters = item.updateParameters {
                parameters.append(updateParameters)
            }
            if let updateParameters = attachment.updateParameters {
                parameters.append(updateParameters)
            }

            return Single.just((parameters, md5, mtime))
        } catch let error {
            return Single.error(error)
        }
    }

    // MARK: - Collection picker

    func set(collection: Collection, library: Library) {
        self.state.collectionPicker = .picked(library, (collection.type.isCustom ? nil : collection))
    }

    // MARK: - Sync

    private func setupSyncObserving() {
        self.syncController.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] data in
                               self?.finishSync(successful: (data == nil))
                           }, onError: { [weak self] _ in
                               self?.finishSync(successful: false)
                           })
                           .disposed(by: self.disposeBag)
    }

    private func finishSync(successful: Bool) {
        if successful {
            self.state.collectionPicker = .picked(Library(identifier: ExtensionStore.defaultLibraryId,
                                                               name: RCustomLibraryType.myLibrary.libraryName,
                                                               metadataEditable: true,
                                                               filesEditable: true),
                                                       nil)
        } else {
            self.state.collectionPicker = .failed
        }
    }
}
