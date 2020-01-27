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

import RxSwift
import RxAlamofire

class ExtensionStore {
    struct State {
        enum CollectionPickerState {
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

        enum TranslationState {
            case translating
            case translated(ItemResponse)
            case downloading(ItemResponse, [String: String], Float)
            case downloaded(ItemResponse, [String: String])
            case failed(TranslationError)
        }

        enum SubmissionState: Equatable {
            case preparing
            case ready
            case error(SubmissionError)
        }

        struct ItemPickerState {
            let items: [String: String]
            var picked: String?
        }

        let attachmentKey: String
        var title: String?
        var collectionPickerState: CollectionPickerState
        var translationState: TranslationState
        var downloadProgress: Float?
        var submissionState: SubmissionState?
        var itemPickerState: ItemPickerState?

        init() {
            self.attachmentKey = KeyGenerator.newKey
            self.collectionPickerState = .loading
            self.translationState = .translating
            self.itemPickerState = nil
        }
    }

    enum TranslationError: Swift.Error {
        case cantLoadSchema, cantLoadWebData, downloadFailed, itemsNotFound, expired, unknown
        case webViewError(WebViewHandler.Error)
        case parseError(ItemResponse.Error)
    }

    enum SubmissionError: Swift.Error, Equatable {
        case expired, fileMissing, unknown
    }

    @Published var state: State
    // The background uploader is optional because it needs to be deinitialized after starting the upload. See more in comment where the uploader is nilled.
    private var backgroundUploader: BackgroundUploader?

    private static let defaultLibraryId: LibraryIdentifier = .custom(.myLibrary)
    private static let defaultExtension = "pdf"
    private static let defaultMimetype = "application/pdf"

    private let syncController: SyncController
    private let syncHandler: SyncActionHandler
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let webViewHandler: WebViewHandler
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(webView: WKWebView, apiClient: ApiClient, backgroundUploader: BackgroundUploader, dbStorage: DbStorage,
         schemaController: SchemaController, fileStorage: FileStorage, syncController: SyncController, syncActionHandler: SyncActionHandler) {
        self.syncController = syncController
        self.apiClient = apiClient
        self.backgroundUploader = backgroundUploader
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.syncHandler = syncActionHandler
        self.webViewHandler = WebViewHandler(webView: webView, apiClient: apiClient, fileStorage: fileStorage)
        self.state = State()
        self.disposeBag = DisposeBag()

        self.setupSyncObserving()
        self.setupWebHandlerObserving()
    }

    func cancel() {
        // Remove temporary downloaded file if it exists
        let file = Files.shareExtensionTmpItem(key: self.state.attachmentKey, ext: ExtensionStore.defaultExtension)
        try? self.fileStorage.remove(file)
    }

    // MARK: - Setup

    func setup(with extensionItem: NSExtensionItem) {
        self.syncController.start(type: .normal, libraries: .all)
        self.loadDocument(with: extensionItem)
    }

    private func finishSync(successful: Bool) {
        if successful {
            self.state.collectionPickerState = .picked(Library(identifier: ExtensionStore.defaultLibraryId,
                                                               name: RCustomLibraryType.myLibrary.libraryName,
                                                               metadataEditable: true,
                                                               filesEditable: true),
                                                       nil)
        } else {
            self.state.collectionPickerState = .failed
        }
    }

    func set(collection: Collection, library: Library) {
        self.state.collectionPickerState = .picked(library, (collection.type.isCustom ? nil : collection))
    }

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

    // MARK: - Translation & Attachment download

    func pickItem(_ data: (String, String)) {
        self.state.itemPickerState?.picked = data.1
        self.webViewHandler.selectItem(data)
    }

    private func loadDocument(with extensionItem: NSExtensionItem) {
        self.loadWebData(extensionItem: extensionItem)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] title, url, html, cookies in
                self?.state.title = title
                self?.webViewHandler.translate(url: url, title: title, html: html, cookies: cookies)
            }, onError: { [weak self] error in
                self?.state.translationState = .failed((error as? TranslationError) ?? .unknown)
            })
            .disposed(by: self.disposeBag)
    }

    private func loadWebData(extensionItem: NSExtensionItem) -> Observable<(String, URL, String, String)> {
        let propertyList = kUTTypePropertyList as String

        guard let itemProvider = extensionItem.attachments?.first,
              itemProvider.hasItemConformingToTypeIdentifier(propertyList) else {
            return Observable.error(TranslationError.cantLoadWebData)
        }

        return Observable.create { [weak itemProvider] subscriber in
            guard let itemProvider = itemProvider else { return Disposables.create() }

            itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { item, error -> Void in
                guard let scriptData = item as? [String: Any],
                      let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else {
                    subscriber.onError(TranslationError.cantLoadWebData)
                    return
                }

                if let url = (data["url"] as? String).flatMap(URL.init),
                   let title = data["title"] as? String,
                   let html = data["html"] as? String,
                   let cookies = data["cookies"] as? String {
                    subscriber.onNext((title, url, html, cookies))
                    subscriber.onCompleted()
                } else {
                    subscriber.onError(TranslationError.cantLoadWebData)
                }
            })

            return Disposables.create()
        }
    }

    private func prepareItemSelector(with data: [String: String]) {
        self.state.itemPickerState = State.ItemPickerState(items: data, picked: nil)
    }

    private func processItems(_ data: [[String: Any]]) {
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
            self.state.translationState = .failed(.itemsNotFound)
            return
        }

        do {
            let item = try ItemResponse(response: itemData, schemaController: self.schemaController)
            if let attachmentData = (itemData["attachments"] as? [[String: String]])?.first(where: { $0["mimeType"] == ExtensionStore.defaultMimetype }),
               let urlString = attachmentData["url"],
               let url = URL(string: urlString) {
                self.state.translationState = .downloading(item, attachmentData, 0)
                self.startDownload(for: url)
            } else {
                self.state.translationState = .translated(item)
            }
        } catch let error {
            let downloadError: TranslationError = (error as? ItemResponse.Error).flatMap({ TranslationError.parseError($0) }) ?? .unknown
            self.state.translationState = .failed(downloadError)
        }
    }

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
                          self?.state.translationState = .failed(.downloadFailed)
                      }, onCompleted: { [weak self] in
                          self?.finishDownload()
                      })
                      .disposed(by: self.disposeBag)
    }

    private func setDownloadProgress(_ progress: Float) {
        switch self.state.translationState {
        case .downloading(let response, let attachment, _):
            self.state.translationState = .downloading(response, attachment, progress)
        default: break
        }
    }

    private func finishDownload() {
        switch self.state.translationState {
        case .downloading(let response, let attachment, _):
            self.state.translationState = .downloaded(response, attachment)
        default: break
        }
    }

    private func  setupWebHandlerObserving() {
        self.webViewHandler.observable
                           .observeOn(MainScheduler.instance)
                           .subscribe(onNext: { [weak self] action in
                               switch action {
                               case .loadedItems(let data):
                                   self?.processItems(data)
                               case .selectItem(let data):
                                   self?.prepareItemSelector(with: data)
                               }
                           }, onError: { [weak self] error in
                               self?.state.translationState = .failed((error as? WebViewHandler.Error).flatMap({ .webViewError($0) }) ?? .unknown)
                           })
                           .disposed(by: self.disposeBag)

    }

    // MARK: - Items submission & Attachment upload

    func submit() {
        let attachmentKey = self.state.attachmentKey
        let libraryId: LibraryIdentifier
        let collectionKeys: Set<String>
        let userId = Defaults.shared.userId

        switch self.state.collectionPickerState {
        case .picked(let library, let collection):
            libraryId = library.identifier
            collectionKeys = collection.flatMap({ [$0.key] }) ?? []
        default:
            libraryId = ExtensionStore.defaultLibraryId
            collectionKeys = []
        }

        self.state.submissionState = .preparing

        switch self.state.translationState {
        case .translated(let item):
            self.submit(item: item.copy(libraryId: libraryId, collectionKeys: collectionKeys),
                        libraryId: libraryId, userId: userId, schemaController: self.schemaController)

        case .downloaded(let item, let attachmentData):
            let newItem = item.copy(libraryId: libraryId, collectionKeys: collectionKeys)
            let filename = attachmentData["title"] ?? self.state.title ?? "Unknown"
            let file = Files.objectFile(for: .item, libraryId: libraryId, key: attachmentKey, ext: ExtensionStore.defaultExtension)
            let attachment = Attachment(key: attachmentKey, title: filename, type: .file(file: file, filename: filename, isLocal: true), libraryId: libraryId)
            self.upload(item: newItem, attachment: attachment, file: file, filename: filename, libraryId: libraryId, userId: userId)

        default: break
        }
    }

    private func submit(item: ItemResponse, libraryId: LibraryIdentifier, userId: Int, schemaController: SchemaController) {
        self.createItem(item, schemaController: schemaController)
            .flatMap { [weak self] parameters -> Single<()> in
                guard let `self` = self else { return Single.error(SubmissionError.expired) }
                return self.syncHandler.submitUpdate(for: libraryId,
                                                     userId: userId,
                                                     object: .item,
                                                     since: nil,
                                                     parameters: [parameters])
                                       .flatMap({ _ in Single.just(()) })
            }
            .subscribe(onSuccess: { [weak self] _ in
                self?.state.submissionState = .ready
            }, onError: { [weak self] error in
                let error = (error as? SubmissionError) ?? .unknown
                self?.state.submissionState = .error(error)
            })
            .disposed(by: self.disposeBag)
    }

    private func createItem(_ item: ItemResponse, schemaController: SchemaController) -> Single<[String: Any]> {
        let request = CreateBackendItemDbRequest(item: item, schemaController: schemaController)
        do {
            let item = try self.dbStorage.createCoordinator().perform(request: request)
            return Single.just(item.updateParameters ?? [:])
        } catch let error {
            return Single.error(error)
        }
    }

    private func upload(item: ItemResponse, attachment: Attachment, file: File, filename: String, libraryId: LibraryIdentifier, userId: Int) {
        self.prepareUpload(itemResponse: item, attachment: attachment, file: file, filename: filename,
                       libraryId: libraryId, userId: userId)
            .subscribe(onSuccess: { [weak self] response, md5 in
                guard let `self` = self else { return }

                switch response {
                case .exists:
                    self.state.submissionState = .ready

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
                let error = (error as? SubmissionError) ?? .unknown
                self?.state.submissionState = .error(error)
            })
            .disposed(by: self.disposeBag)
    }

    private func prepareUpload(itemResponse: ItemResponse, attachment: Attachment, file: File, filename: String,
                               libraryId: LibraryIdentifier, userId: Int) -> Single<(AuthorizeUploadResponse, String)> {
        return self.moveTmpFile(with: attachment.key, to: file, libraryId: libraryId)
                   .flatMap { [weak self] filesize -> Single<(UInt64, [[String: Any]], String, Int)> in
                       guard let `self` = self else { return Single.error(SubmissionError.expired) }
                       return self.createItems(response: itemResponse, attachment: attachment)
                                  .flatMap({ Single.just((filesize, $0, $1, $2)) })
                                  .do(onError: { [weak self] _ in
                                      // If attachment item couldn't be created in DB, remove the moved file if possible,
                                      // it won't be processed even from the main app
                                      try? self?.fileStorage.remove(file)
                                  })
                   }
                   .flatMap { [weak self] filesize, parameters, md5, mtime -> Single<(UInt64, String, Int)> in
                       guard let `self` = self else { return Single.error(SubmissionError.expired) }
                       return self.syncHandler.submitUpdate(for: libraryId,
                                                            userId: userId,
                                                            object: .item,
                                                            since: nil,
                                                            parameters: parameters)
                                              .flatMap({ _ in Single.just((filesize, md5, mtime)) })
                   }
                   .flatMap { [weak self] filesize, md5, mtime -> Single<(AuthorizeUploadResponse, String)> in
                       guard let `self` = self else { return Single.error(SubmissionError.expired) }
                       return self.syncHandler.authorizeUpload(key: attachment.key,
                                                               filename: filename,
                                                               filesize: filesize,
                                                               md5: md5,
                                                               mtime: mtime,
                                                               libraryId: libraryId,
                                                               userId: userId)
                                              .flatMap({ return Single.just(($0, md5)) })
                   }
    }

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
                                          // TODO: - Log error
                                          self?.state.submissionState = .error(.unknown)
                                      } else {
                                          // The uploader is set to nil so that the URLSession delegate no longer exists for the share extension. This
                                          // way the URLSession delegate will always be called in the main (container) app, where additional upload
                                          // processing is performed.
                                          self?.backgroundUploader = nil
                                          self?.state.submissionState = .ready
                                      }
                                  }
    }

    private func moveTmpFile(with key: String, to file: File, libraryId: LibraryIdentifier) -> Single<UInt64> {
        let tmpFile = Files.shareExtensionTmpItem(key: key, ext: ExtensionStore.defaultExtension)

        do {
            let size = self.fileStorage.size(of: tmpFile)
            if size == 0 {
                return Single.error(SubmissionError.fileMissing)
            }
            try self.fileStorage.move(from: tmpFile, to: file)
            return Single.just(size)
        } catch {
            // If tmp file couldn't be moved, remove it if it's there
            try? self.fileStorage.remove(tmpFile)
            return Single.error(SubmissionError.fileMissing)
        }
    }

    private func createItems(response: ItemResponse, attachment: Attachment) -> Single<([[String: Any]], String, Int)> {
        let request = CreateItemWithAttachmentDbRequest(item: response, attachment: attachment, schemaController: self.schemaController)
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
}
