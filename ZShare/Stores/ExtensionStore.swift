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

        struct DownloadState {
            var progress: Float?
            var item: ItemResponse?
            var attachmentData: [String: String]?
            var error: DownloadError?
        }

        enum UploadState: Equatable {
            case preparing
            case ready
            case error(UploadError)
        }

        struct ItemPickerState {
            let items: [String: String]
            var picked: String?
        }

        let key: String
        var title: String?
        var collectionPickerState: CollectionPickerState
        var downloadState: DownloadState
        var uploadState: UploadState?
        var itemPickerState: ItemPickerState?

        init() {
            self.key = KeyGenerator.newKey
            self.collectionPickerState = .loading
            self.downloadState = DownloadState(progress: 0, item: nil, attachmentData: nil, error: nil)
            self.itemPickerState = nil
        }
    }

    enum DownloadError: Swift.Error {
        case cantLoadWebData, downloadFailed, expired, unknown, attachmentNotFound
        case parseError(ItemResponse.Error)
    }

    enum UploadError: Swift.Error, Equatable {
        case expired, fileMissing, unknown
    }

    @Published var state: State

    private static let defaultLibraryId: LibraryIdentifier = .custom(.myLibrary)
    private static let defaultExtension = "pdf"
    private static let defaultMimetype = "application/pdf"

    private let syncController: SyncController
    private let apiClient: ApiClient
    private let backgroundApi: BackgroundApi
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let webViewHandler: WebViewHandler
    private let disposeBag: DisposeBag

    // MARK: - Lifecycle

    init(webView: WKWebView, apiClient: ApiClient, backgroundApi: BackgroundApi, dbStorage: DbStorage,
         schemaController: SchemaController, fileStorage: FileStorage, syncController: SyncController) {
        self.syncController = syncController
        self.apiClient = apiClient
        self.backgroundApi = backgroundApi
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.webViewHandler = WebViewHandler(webView: webView, apiClient: apiClient, fileStorage: fileStorage)
        self.state = State()
        self.disposeBag = DisposeBag()

        self.setupSyncObserving()
        self.setupWebHandlerObserving()
    }

    // MARK: - Setup

    func setup(with extensionItem: NSExtensionItem) {
        // TODO: - when SchemaController stores schemas correctly add it as Observable, so that we wait for remote schema update if needed
        self.schemaController.reloadSchemaIfNeeded()
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
                self?.state.downloadState.error = (error as? DownloadError) ?? .unknown
            })
            .disposed(by: self.disposeBag)
    }

    private func loadWebData(extensionItem: NSExtensionItem) -> Observable<(String, URL, String, String)> {
        let propertyList = kUTTypePropertyList as String

        guard let itemProvider = extensionItem.attachments?.first,
              itemProvider.hasItemConformingToTypeIdentifier(propertyList) else {
            return Observable.error(DownloadError.cantLoadWebData)
        }

        return Observable.create { subscriber in
            itemProvider.loadItem(forTypeIdentifier: propertyList, options: nil, completionHandler: { item, error -> Void in
                guard let scriptData = item as? [String: Any],
                      let data = scriptData[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] else {
                    subscriber.onError(DownloadError.cantLoadWebData)
                    return
                }

                if let url = (data["url"] as? String).flatMap(URL.init),
                   let title = data["title"] as? String,
                   let html = data["html"] as? String,
                   let cookies = data["cookies"] as? String {
                    subscriber.onNext((title, url, html, cookies))
                    subscriber.onCompleted()
                } else {
                    subscriber.onError(DownloadError.cantLoadWebData)
                }
            })
            return Disposables.create()
        }
    }

    private func prepareItemSelector(with data: [String: String]) {
        self.state.itemPickerState = State.ItemPickerState(items: data, picked: nil)
    }

    private func processItems(_ data: [[String: Any]]) {
        guard let itemData = data.first(where: { data -> Bool in
                  guard let attachmentData = data["attachments"] as? [[String: String]] else { return false }
                  return attachmentData.contains(where: { $0["mimeType"] == ExtensionStore.defaultMimetype })
              }),
              let attachmentData = (itemData["attachments"] as? [[String: String]])?.first(where: { $0["mimeType"] == ExtensionStore.defaultMimetype }),
              let urlString = attachmentData["url"],
              let url = URL(string: urlString) else {
            self.state.downloadState.error = .attachmentNotFound
            return
        }

        do {
            let item = try ItemResponse(response: itemData, schemaController: self.schemaController)
            self.state.downloadState.item = item
            self.state.downloadState.attachmentData = attachmentData
            self.startDownload(for: url)
        } catch let error {
            self.state.downloadState.error = (error as? ItemResponse.Error).flatMap({ DownloadError.parseError($0) }) ?? .unknown
        }
    }

    private func startDownload(for url: URL) {
        let file = Files.shareExtensionTmpItem(key: self.state.key, ext: ExtensionStore.defaultExtension)
        let request = FileRequest(data: .external(url), destination: file)
        self.apiClient.download(request: request)
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] progress in
                          self?.state.downloadState.progress = progress.completed
                      }, onError: { [weak self] error in
                          self?.state.downloadState.error = .downloadFailed
                      }, onCompleted: { [weak self] in
                          self?.state.downloadState.progress = 1
                      })
                      .disposed(by: self.disposeBag)
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
                               self?.state.downloadState.error = (error as? DownloadError) ?? .unknown
                           })
                           .disposed(by: self.disposeBag)

    }

    // MARK: - Items submission & Attachment upload

    func upload() {
        guard let item = self.state.downloadState.item,
              let filename = self.state.downloadState.attachmentData?["title"] else { return }

        let key = self.state.key
        let libraryId: LibraryIdentifier
        let collectionKey: String?
        let userId = Defaults.shared.userId

        switch self.state.collectionPickerState {
        case .picked(let library, let collection):
            libraryId = library.identifier
            collectionKey = collection?.key
        default:
            libraryId = ExtensionStore.defaultLibraryId
            collectionKey = nil
        }

        let file = Files.objectFile(for: .item, libraryId: libraryId, key: self.state.key, ext: ExtensionStore.defaultExtension)
        let attachment = Attachment(key: key, title: filename, type: .file(file: file, filename: filename, isLocal: true), libraryId: libraryId)

        self.state.uploadState = .preparing

        self.prepareUpload(itemResponse: item, attachment: attachment, file: file, libraryId: libraryId, collectionKey: collectionKey, userId: userId)
            .subscribe(onSuccess: { [weak self] filename, response in
                guard let `self` = self else { return }

                switch response {
                case .exists:
                    self.state.uploadState = .ready

                case .new(let response):
                    self.startBackgroundUpload(to: response.url,
                                               filename: filename,
                                               file: file,
                                               params: response.params,
                                               key: key,
                                               uploadKey: response.uploadKey,
                                               libraryId: libraryId,
                                               userId: userId)
                    self.state.uploadState = .ready
                }
            }, onError: { [weak self] error in
                let error = (error as? UploadError) ?? .unknown
                self?.state.uploadState = .error(error)
            })
            .disposed(by: self.disposeBag)
    }

    private func prepareUpload(itemResponse: ItemResponse, attachment: Attachment, file: File,
                               libraryId: LibraryIdentifier, collectionKey: String?, userId: Int) -> Single<(String, AuthorizeUploadResponse)> {
        return self.moveTmpFile(with: attachment.key, to: file, libraryId: libraryId)
                    .do(onError: { [weak self] _ in
                        // If file couldn't be moved from original tmp location for some reason, remove the tmp file if it's there
                        let file = Files.shareExtensionTmpItem(key: attachment.key, ext: ExtensionStore.defaultExtension)
                        try? self?.fileStorage.remove(file)
                    })
                    .flatMap { [weak self] filesize -> Single<(UInt64, RItem, RItem)> in
                        guard let `self` = self else { return Single.error(UploadError.expired) }
                        let collectionKeys = collectionKey.flatMap({ Set(arrayLiteral: $0) }) ?? []
                        return self.createItems(response: itemResponse.copy(libraryId: libraryId, collectionKeys: collectionKeys), attachment: attachment)
                                   .flatMap({ Single.just((filesize, $0, $1)) })
                                   .do(onError: { [weak self] _ in
                                       // If attachment item couldn't be created in DB, remove the moved file if possible,
                                       // it won't be processed even from the main app
                                       try? self?.fileStorage.remove(file)
                                   })
                    }
                    .flatMap { [weak self] filesize, item, attachment -> Single<(UInt64, RItem)> in
                        guard let `self` = self else { return Single.error(UploadError.expired) }
                        var parameters: [[String: Any]] = []
                        if let updateParameters = item.updateParameters {
                            parameters.append(updateParameters)
                        }
                        if let updateParameters = attachment.updateParameters {
                            parameters.append(updateParameters)
                        }
                        let request = UpdatesRequest(libraryId: libraryId, userId: userId, objectType: .item, params: parameters, version: nil)
                        return self.apiClient.send(request: request).flatMap({ _ in Single.just((filesize, attachment)) })
                    }
                    .flatMap { [weak self] filesize, attachment -> Single<(String, Data, ResponseHeaders)> in
                        guard let `self` = self else { return Single.error(UploadError.expired) }
                        let request = self.createAuthorizeRequest(from: attachment, libraryId: libraryId, userId: userId, filesize: filesize)
                        return self.apiClient.send(request: request).flatMap({ Single.just((request.filename, $0.0, $0.1)) })
                    }
                    .flatMap { filename, data, _ -> Single<(String, AuthorizeUploadResponse)> in
                       do {
                           let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                           let response = try AuthorizeUploadResponse(from: jsonObject)
                           return Single.just((filename, response))
                       } catch {
                           return Single.error(error)
                       }
                    }
    }

    private func startBackgroundUpload(to url: URL, filename: String, file: File, params: [String: String],
                                       key: String, uploadKey: String, libraryId: LibraryIdentifier, userId: Int) {
        let request = AttachmentUploadRequest(url: url)
        self.backgroundApi.client.upload(request: request) { data in
                                     params.forEach { (key, value) in
                                         if let stringData = value.data(using: .utf8) {
                                             data.append(stringData, withName: key)
                                         }
                                     }
                                     data.append(file.createUrl(), withName: "file", fileName: filename, mimeType: ExtensionStore.defaultMimetype)
                                 }
                                 .flatMap { request -> Single<Data> in
                                     return request.rx.data().asSingle()
                                 }
                                 .flatMap { _ -> Single<(Data, ResponseHeaders)> in
                                     let request = RegisterUploadRequest(libraryId: libraryId,
                                                                         userId: userId,
                                                                         key: key,
                                                                         uploadKey: uploadKey)
                                     return self.apiClient.send(request: request)
                                 }
                                 .flatMap { _ -> Single<()> in
                                     return self.markAttachmentUploaded(with: key, libraryId: libraryId)
                                 }
                                 .subscribe(onSuccess: nil, onError: { error in
                                     // TODO: - add logging
                                 })
                                 .disposed(by: self.backgroundApi.disposeBag)
    }

    private func markAttachmentUploaded(with key: String, libraryId: LibraryIdentifier) -> Single<()> {
        do {
            let request = MarkAttachmentUploadedDbRequest(libraryId: libraryId, key: key)
            try self.dbStorage.createCoordinator().perform(request: request)
            return Single.just(())
        } catch let error {
            return Single.error(error)
        }
    }

    private func createAuthorizeRequest(from item: RItem, libraryId: LibraryIdentifier, userId: Int, filesize: UInt64) -> AuthorizeUploadRequest {
        let filename = item.fields.filter(.key(FieldKeys.filename)).first?.value ?? ""
        let mtime = item.fields.filter(.key(FieldKeys.mtime)).first.flatMap({ Int($0.value) }) ?? 0
        let md5 = item.fields.filter(.key(FieldKeys.md5)).first?.value ?? ""
        return AuthorizeUploadRequest(libraryId: libraryId, userId: userId, key: item.key,
                                      filename: filename, filesize: filesize,
                                      md5: md5, mtime: mtime)
    }

    private func createItems(response: ItemResponse, attachment: Attachment) -> Single<(RItem, RItem)> {
        // TODO: - add main item with attachment linked
        let request = CreateItemWithAttachmentDbRequest(item: response, attachment: attachment, schemaController: self.schemaController)
        do {
            let items = try self.dbStorage.createCoordinator().perform(request: request)
            return Single.just(items)
        } catch let error {
            return Single.error(error)
        }
    }

    private func moveTmpFile(with key: String, to file: File, libraryId: LibraryIdentifier) -> Single<UInt64> {
        let tmpFile = Files.shareExtensionTmpItem(key: key, ext: ExtensionStore.defaultExtension)

        do {
            let size = self.fileStorage.size(of: tmpFile)
            if size == 0 {
                return Single.error(UploadError.fileMissing)
            }
            try self.fileStorage.move(from: tmpFile, to: file)
            return Single.just(size)
        } catch {
            return Single.error(UploadError.fileMissing)
        }
    }
}
