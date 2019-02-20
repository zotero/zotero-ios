//
//  ItemDetailStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

enum ItemDetailAction {
    case load
    case attachmentOpened
    case showAttachment(RItem)
}

enum ItemDetailStoreError {
    case typeNotSupported, libraryNotAssigned, contentTypeMissing, contentTypeUnknown, userMissing
    case downloadError(Error)
}

extension ItemDetailStoreError: Equatable {
    static func == (lhs: ItemDetailStoreError, rhs: ItemDetailStoreError) -> Bool {
        switch (lhs, rhs) {
            case (.typeNotSupported, .typeNotSupported),
                 (.libraryNotAssigned, .libraryNotAssigned),
                 (.contentTypeMissing, .contentTypeMissing),
                 (.contentTypeUnknown, .contentTypeUnknown),
                 (.userMissing, .userMissing),
                 (.downloadError, .downloadError):
            return true
        default:
            return false
        }
    }
}

struct ItemDetailField {
    let name: String
    let value: String
}

enum ItemDetailChange {
    case data, download, error
}

struct ItemDetailState {
    enum FileDownload {
        case progress(Double)
        case downloaded(File)
    }

    let item: RItem

    fileprivate(set) var changes: Set<ItemDetailChange>
    fileprivate(set) var downloadState: FileDownload?
    fileprivate(set) var fields: [ItemDetailField]
    fileprivate(set) var attachments: Results<RItem>?
    fileprivate(set) var error: ItemDetailStoreError?

    fileprivate var version: Int

    init(item: RItem) {
        self.item = item
        self.fields = []
        self.changes = []
        self.attachments = nil
        self.version = 0
    }
}

extension ItemDetailState: Equatable {
    static func == (lhs: ItemDetailState, rhs: ItemDetailState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error && lhs.downloadState == rhs.downloadState
    }
}

extension ItemDetailState.FileDownload: Equatable {
    static func == (lhs: ItemDetailState.FileDownload, rhs: ItemDetailState.FileDownload) -> Bool {
        switch (lhs, rhs) {
        case (.progress(let lProgress), .progress(let rProgress)):
            return lProgress == rProgress
        case (.downloaded(let lFile), .downloaded(let rFile)):
            return lFile.createUrl() == rFile.createUrl()
        default:
            return false
        }
    }
}

class ItemDetailStore: Store {
    typealias Action = ItemDetailAction
    typealias State = ItemDetailState

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let itemFieldsController: ItemFieldsController
    let disposeBag: DisposeBag

    var updater: StoreStateUpdater<ItemDetailState>

    init(initialState: ItemDetailState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, itemFieldsController: ItemFieldsController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.itemFieldsController = itemFieldsController
        self.disposeBag = DisposeBag()
        self.updater = StoreStateUpdater(initialState: initialState)
        self.updater.stateCleanupAction = { state in
            state.changes = []
        }
    }

    func handle(action: ItemDetailAction) {
        switch action {
        case .load:
            self.loadData()
        case .showAttachment(let item):
            self.showAttachment(for: item)
        case .attachmentOpened:
            self.updater.updateState { newState in
                newState.downloadState = nil
            }
        }
    }

    private func loadData() {
        guard let sortedFieldNames = self.itemFieldsController.fields[self.state.value.item.rawType] else {
            self.reportError(.typeNotSupported)
            return
        }

        var values: [String: String] = [:]
        self.state.value.item.fields.forEach { field in
            values[field.key] = field.value
        }
        let fields = sortedFieldNames.map { name -> ItemDetailField in
            let value = values[name] ?? ""
            return ItemDetailField(name: name, value: value)
        }
        let attachments = self.state.value.item.children.sorted(byKeyPath: "title")

        self.updater.updateState { newState in
            newState.attachments = attachments
            newState.fields = fields
            newState.version += 1
            newState.changes = [.data]
        }
    }

    private func showAttachment(for item: RItem) {
        guard let library = item.library else {
            self.reportError(.libraryNotAssigned)
            return
        }
        guard let contentType = item.fields.filter("key = %@", "contentType").first?.value else {
            self.reportError(.contentTypeMissing)
            return
        }
        guard let ext = contentType.mimeTypeExtension else {
            self.reportError(.contentTypeUnknown)
            return
        }


        let file = Files.itemFile(libraryId: library.identifier, key: item.key, ext: ext)

        if self.fileStorage.has(file) {
            self.updater.updateState { newState in
                newState.downloadState = .downloaded(file)
                newState.changes = [.download]
            }
            return
        }

        let groupType: SyncGroupType
        switch library.libraryType {
        case .group:
            groupType = .group(library.identifier)
        case .user:
            do {
                let user = try self.dbStorage.createCoordinator().perform(request: ReadUserDbRequest())
                groupType = .user(user.identifier)
            } catch let error {
                DDLogError("ItemDetailStore: can't load self user - \(error)")
                self.reportError(.userMissing)
                return
            }
        }

        let request = FileRequest(groupType: groupType, key: item.key, destination: file)
        self.apiClient.download(request: request)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] progress in
                self?.updater.updateState { newState in
                    newState.downloadState = .progress(Double(progress.bytesWritten) / Double(progress.totalBytes))
                    newState.changes = [.download]
                }
            }, onError: { [weak self] error in
                DDLogError("ItemDetailStore: can't download file - \(error)")
                self?.updater.updateState { newState in
                    newState.downloadState = nil
                    newState.error = .downloadError(error)
                    newState.changes = [.download, .error]
                }
            }, onCompleted: { [weak self] in
                self?.updater.updateState { newState in
                    newState.downloadState = .downloaded(file)
                    newState.changes = [.download]
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func reportError(_ error: ItemDetailStoreError) {
        self.updater.updateState { newState in
            newState.error = error
            newState.changes = [.error]
        }
    }
}
