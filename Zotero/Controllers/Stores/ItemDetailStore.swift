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

class ItemDetailStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
        case attachmentOpened
        case showAttachment(RItem)
    }

    enum StoreError {
        case typeNotSupported, libraryNotAssigned, contentTypeMissing, contentTypeUnknown, userMissing
        case downloadError(Error)
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    struct StoreState {
        struct Field {
            let name: String
            let value: String
        }

        enum FileDownload {
            case progress(Double)
            case downloaded(File)
        }

        let item: RItem

        fileprivate(set) var changes: Changes
        fileprivate(set) var downloadState: FileDownload?
        fileprivate(set) var fields: [Field]
        fileprivate(set) var attachments: Results<RItem>?
        fileprivate(set) var notes: Results<RItem>?
        fileprivate(set) var tags: Results<RTag>?
        fileprivate(set) var error: StoreError?

        fileprivate var version: Int

        init(item: RItem) {
            self.item = item
            self.fields = []
            self.changes = []
            self.attachments = nil
            self.version = 0
        }
    }

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let itemFieldsController: ItemFieldsController
    let disposeBag: DisposeBag

    var updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, itemFieldsController: ItemFieldsController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.itemFieldsController = itemFieldsController
        self.disposeBag = DisposeBag()
        self.updater = StoreStateUpdater(initialState: initialState)
        self.updater.stateCleanupAction = { state in
            state.error = nil
            state.changes = []
        }
    }

    func handle(action: StoreAction) {
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
        self.state.value.item.fields.filter("value != %@", "").forEach { field in
            values[field.key] = field.value
        }
        let fields: [StoreState.Field] = sortedFieldNames.compactMap { name in
            return values[name].flatMap({ StoreState.Field(name: name, value: $0) })
        }
        let attachments = self.state.value.item.children
                                               .filter("rawType = %@", ItemType.attachment.rawValue)
                                               .sorted(byKeyPath: "title")
        let notes = self.state.value.item.children
                                         .filter("rawType = %@", ItemType.note.rawValue)
                                         .sorted(byKeyPath: "title")
        let tags = self.state.value.item.tags.sorted(byKeyPath: "name")

        self.updater.updateState { newState in
            newState.attachments = attachments
            newState.notes = notes
            newState.fields = fields
            newState.tags = tags
            newState.version += 1
            newState.changes = .data
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
                newState.changes = .download
            }
            return
        }

        let groupType: SyncController.Library
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
                    newState.changes = .download
                }
            }, onError: { [weak self] error in
                DDLogError("ItemDetailStore: can't download file - \(error)")
                self?.updater.updateState { newState in
                    newState.downloadState = nil
                    newState.error = .downloadError(error)
                    newState.changes = .download
                }
            }, onCompleted: { [weak self] in
                self?.updater.updateState { newState in
                    newState.downloadState = .downloaded(file)
                    newState.changes = .download
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func reportError(_ error: StoreError) {
        self.updater.updateState { newState in
            newState.error = error
        }
    }
}

extension ItemDetailStore.StoreError: Equatable {
    static func == (lhs: ItemDetailStore.StoreError, rhs: ItemDetailStore.StoreError) -> Bool {
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

extension ItemDetailStore.StoreState: Equatable {
    static func == (lhs: ItemDetailStore.StoreState, rhs: ItemDetailStore.StoreState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error && lhs.downloadState == rhs.downloadState
    }
}

extension ItemDetailStore.StoreState.FileDownload: Equatable {
    static func == (lhs: ItemDetailStore.StoreState.FileDownload, rhs: ItemDetailStore.StoreState.FileDownload) -> Bool {
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

extension ItemDetailStore.Changes {
    static let data = ItemDetailStore.Changes(rawValue: 1 << 0)
    static let download = ItemDetailStore.Changes(rawValue: 1 << 1)
}
