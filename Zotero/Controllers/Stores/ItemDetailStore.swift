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

struct EditingSectionDiff {
    enum DiffType {
        case insert, delete, update
    }

    let type: DiffType
    let index: Int
}

protocol ItemDetailDataSource {
    var title: String { get }
    var type: String { get }
    var abstract: String? { get }
    var sections: [ItemDetailStore.StoreState.Section] { get }

    func rowCount(for section: ItemDetailStore.StoreState.Section) -> Int
    func creator(at index: Int) -> RCreator?
    func field(at index: Int) -> ItemDetailStore.StoreState.Field?
    func note(at index: Int) -> RItem?
    func attachment(at index: Int) -> RItem?
    func tag(at index: Int) -> RTag?
}

class ItemDetailStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
        case attachmentOpened
        case showAttachment(RItem)
        case startEditing
        case stopEditing(Bool) // SaveChanges
        case updateField(String, String) // Name, Value
        case updateTitle(String)
        case updateAbstract(String)
    }

    enum StoreError: Error, Equatable {
        case typeNotSupported, libraryNotAssigned, contentTypeMissing,
             contentTypeUnknown, userMissing, downloadError, unknown,
             cantStoreChanges
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    struct StoreState {
        enum Section: CaseIterable {
            case title, fields, abstract, notes, tags, attachments, related, creators
        }

        struct Field {
            let name: String
            let value: String
        }

        enum FileDownload {
            case progress(Double)
            case downloaded(File)
        }

        fileprivate static let allSections: [StoreState.Section] = [.title, .creators, .fields, .abstract,
                                                                    .notes, .tags, .attachments]
        let item: RItem

        fileprivate(set) var changes: Changes
        fileprivate(set) var downloadState: FileDownload?
        fileprivate(set) var isEditing: Bool
        fileprivate(set) var dataSource: ItemDetailDataSource?
        fileprivate(set) var editingDiff: [EditingSectionDiff]?
        fileprivate(set) var error: StoreError?
        fileprivate var version: Int

        fileprivate var previewDataSource: ItemDetailPreviewDataSource?
        fileprivate var editingDataSource: ItemDetailEditingDataSource?

        init(item: RItem) {
            self.item = item
            self.changes = []
            self.isEditing = false
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
            state.editingDiff = nil
        }
    }

    func handle(action: StoreAction) {
        switch action {
        case .load:
            self.loadInitialData()
        case .showAttachment(let item):
            self.showAttachment(for: item)
        case .attachmentOpened:
            self.updater.updateState { newState in
                newState.downloadState = nil
            }
        case .startEditing:
            self.startEditing()
        case .stopEditing(let save):
            self.stopEditing(shouldSaveChanges: save)
        case .updateField(let name, let value):
            if let index = self.state.value.editingDataSource?.fields.firstIndex(where: { $0.name == name }) {
                self.state.value.editingDataSource?.fields[index] = StoreState.Field(name: name, value: value)
            }
        case .updateTitle(let title):
            self.state.value.editingDataSource?.title = title
        case .updateAbstract(let abstract):
            self.state.value.editingDataSource?.abstract = abstract
        }
    }

    private func startEditing() {
        guard let dataSource = self.state.value.previewDataSource else { return }
        self.setEditing(true, previewDataSource: dataSource, state: self.state.value)
    }

    private func stopEditing(shouldSaveChanges: Bool) {
        guard let previewDataSource = self.state.value.previewDataSource else { return }

        if !shouldSaveChanges {
            self.setEditing(false, previewDataSource: previewDataSource, state: self.state.value)
            return
        }

        guard let editingDataSource = self.state.value.editingDataSource,
              let libraryId = self.state.value.item.libraryId else { return }
        let key = self.state.value.item.key
        previewDataSource.merge(with: editingDataSource)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }
            do {
                try self.storeChanges(from: editingDataSource, itemKey: key, libraryId: libraryId)
                self.setEditing(false, previewDataSource: previewDataSource, state: self.state.value)
            } catch let error {
                DDLogError("ItemDetailStore: can't store changes: \(error)")
                self.updater.updateState { state in
                    state.error = .cantStoreChanges
                }
            }
        }
    }

    private func storeChanges(from dataSource: ItemDetailEditingDataSource, itemKey: String, libraryId: LibraryIdentifier) throws {
        let request = StoreItemDetailChangesDbRequest(abstractKey: self.itemFieldsController.abstractKey,
                                                      libraryId: libraryId, itemKey: itemKey, title: dataSource.title,
                                                      abstract: dataSource.abstract,
                                                      fields: dataSource.fields)
        try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func setEditing(_ editing: Bool, previewDataSource: ItemDetailPreviewDataSource,
                            state: ItemDetailStore.StoreState) {
        var editingDataSource: ItemDetailEditingDataSource?
        if editing {
            editingDataSource = ItemDetailEditingDataSource(item: state.item ,previewDataSource: previewDataSource,
                                                            itemFieldsController: self.itemFieldsController)
        }
        let diff = (editingDataSource ?? state.editingDataSource).flatMap({ self.diff(between: previewDataSource,
                                                                                      and: $0, isEditing: editing) })

        self.updater.updateState { state in
            state.isEditing = editing
            state.editingDataSource = editingDataSource
            state.editingDiff = diff
            state.dataSource = editingDataSource ?? state.previewDataSource
            state.changes.insert(.data)
        }
    }

    private func diff(between preview: ItemDetailPreviewDataSource,
                      and editing: ItemDetailEditingDataSource, isEditing: Bool) -> [EditingSectionDiff] {
        let sectionDiff = self.diff(between: editing.sections, and: preview.sections,
                                    sameIndicesRelativeToDifferent: !isEditing)

        var diff: [EditingSectionDiff] = []
        var sameIndex = 0

        for sectionData in editing.sections.enumerated() {
            if sectionDiff.different.contains(sectionData.offset) {
                diff.append(EditingSectionDiff(type: (isEditing ? .insert : .delete), index: sectionData.offset))
            } else {
                diff.append(EditingSectionDiff(type: .update, index: sectionDiff.same[sameIndex]))
                sameIndex += 1
            }
        }

        return diff
    }

    private func diff<Object: Equatable>(between allObjects: [Object],
                                         and limitedObjects: [Object],
                                         sameIndicesRelativeToDifferent: Bool) -> (different: [Int], same: [Int]) {
        var different: [Int] = []
        var same: [Int] = []

        var index = 0
        allObjects.enumerated().forEach { data in
            if index < limitedObjects.count && data.element == limitedObjects[index] {
                same.append(sameIndicesRelativeToDifferent ? data.offset : index)
                index += 1
            } else {
                different.append(data.offset)
            }
        }

        return (different, same)
    }

    private func loadInitialData() {
        do {
            let dataSource = try ItemDetailPreviewDataSource(item: self.state.value.item,
                                                             itemFieldsController: self.itemFieldsController)
            self.updater.updateState { state in
                state.previewDataSource = dataSource
                state.dataSource = dataSource
                state.version += 1
                state.changes = .data
            }
        } catch let error as StoreError {
            self.updater.updateState { state in
                state.error = error
            }
        } catch let error {
            DDLogError("ItemDetailStore: can't load initial data - \(error)")
            self.updater.updateState { state in
                state.error = .unknown
            }
        }
    }

    private func showAttachment(for item: RItem) {
        guard let libraryId = item.libraryObject?.identifier else {
            DDLogError("ItemDetailStore: show attachment - library not assigned to item (\(item.key))")
            self.reportError(.libraryNotAssigned)
            return
        }
        guard let contentType = item.fields.filter("key = %@", "contentType").first?.value else {
            DDLogError("ItemDetailStore: show attachment - contentType field missing for item (\(item.key))")
            self.reportError(.contentTypeMissing)
            return
        }
        guard let ext = contentType.mimeTypeExtension else {
            DDLogError("ItemDetailStore: show attachment - mimeType/extension " +
                       "unknown (\(contentType)) for item (\(item.key))")
            self.reportError(.contentTypeUnknown)
            return
        }

        let file = Files.itemFile(libraryId: libraryId, key: item.key, ext: ext)

        if self.fileStorage.has(file) {
            self.updater.updateState { newState in
                newState.downloadState = .downloaded(file)
                newState.changes = .download
            }
            return
        }

        let groupType: SyncController.Library
        switch libraryId {
        case .group(let identifier):
            groupType = .group(identifier)
        case .custom(let type):
            do {
                let user = try self.dbStorage.createCoordinator().perform(request: ReadUserDbRequest())
                groupType = .user(user.identifier, type)
            } catch let error {
                DDLogError("ItemDetailStore: show attachment - can't load self user - \(error)")
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
                DDLogError("ItemDetailStore: show attachment - can't download file - \(error)")
                self?.updater.updateState { newState in
                    newState.downloadState = nil
                    newState.error = .downloadError
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

fileprivate class ItemDetailEditingDataSource: ItemDetailDataSource {
    fileprivate let creators: [RCreator]
    fileprivate let attachments: [RItem]
    fileprivate let notes: [RItem]
    fileprivate let tags: [RTag]
    fileprivate var fields: [ItemDetailStore.StoreState.Field]
    let sections: [ItemDetailStore.StoreState.Section]
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, previewDataSource: ItemDetailPreviewDataSource, itemFieldsController: ItemFieldsController) {
        let hasAbstract = itemFieldsController.fields[item.rawType]?.contains(itemFieldsController.abstractKey) ?? false
        var sections = ItemDetailStore.StoreState.allSections
        if !hasAbstract {
            if let index = sections.firstIndex(where: { $0 == .abstract }) {
                sections.remove(at: index)
            }
        }

        var fields: [ItemDetailStore.StoreState.Field] = []
        previewDataSource.fieldNames.forEach { name in
            if let field = previewDataSource.fields.first(where: { $0.name == name }) {
                fields.append(field)
            } else {
                fields.append(ItemDetailStore.StoreState.Field(name: name, value: ""))
            }
        }

        self.sections = sections
        self.title = previewDataSource.title
        self.type = previewDataSource.type
        self.abstract = previewDataSource.abstract
        self.fields = fields
        self.creators = previewDataSource.creators.map(RCreator.init)
        self.attachments = previewDataSource.attachments.map(RItem.init)
        self.notes = previewDataSource.notes.map(RItem.init)
        self.tags = previewDataSource.tags.map(RTag.init)
    }

    func rowCount(for section: ItemDetailStore.StoreState.Section) -> Int {
        switch section {
        case .title, .abstract:
            return 1
        case .creators:
            return self.creators.count
        case .fields:
            return self.fields.count
        case .attachments:
            return 1 + self.attachments.count
        case .notes:
            return 1 + self.notes.count
        case .tags:
            return 1 + self.tags.count
        case .related:
            return 0
        }
    }

    func creator(at index: Int) -> RCreator? {
        guard index < self.creators.count else { return nil }
        return self.creators[index]
    }

    func field(at index: Int) -> ItemDetailStore.StoreState.Field? {
        guard index < self.fields.count else { return nil }
        return self.fields[index]
    }

    func note(at index: Int) -> RItem? {
        guard index < self.notes.count else { return nil }
        return self.notes[index]
    }

    func attachment(at index: Int) -> RItem? {
        guard index < self.attachments.count else { return nil }
        return self.attachments[index]
    }

    func tag(at index: Int) -> RTag? {
        guard index < self.tags.count else { return nil }
        return self.tags[index]
    }
}

fileprivate class ItemDetailPreviewDataSource: ItemDetailDataSource {
    fileprivate let fieldNames: [String]
    fileprivate let creators: Results<RCreator>
    fileprivate let attachments: Results<RItem>
    fileprivate let notes: Results<RItem>
    fileprivate let tags: Results<RTag>
    fileprivate var fields: [ItemDetailStore.StoreState.Field]
    private(set) var sections: [ItemDetailStore.StoreState.Section] = []
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, itemFieldsController: ItemFieldsController) throws {
        guard var sortedFieldNames = itemFieldsController.fields[item.rawType] else {
            throw ItemDetailStore.StoreError.typeNotSupported
        }

        // We're showing title and abstract separately, outside of fields, let's just exclude them here
        let excludedKeys = RItem.titleKeys + [itemFieldsController.abstractKey]
        sortedFieldNames.removeAll { field -> Bool in
            return excludedKeys.contains(field)
        }
        var abstract: String?
        var values: [String: String] = [:]
        item.fields.filter("value != %@", "").forEach { field in
            if field.key ==  itemFieldsController.abstractKey {
                abstract = field.value
            } else {
                values[field.key] = field.value
            }
        }

        let fields: [ItemDetailStore.StoreState.Field] = sortedFieldNames.compactMap { name in
            return values[name].flatMap({ ItemDetailStore.StoreState.Field(name: name, value: $0) })
        }

        self.fieldNames = sortedFieldNames
        self.title = item.title
        self.type = item.rawType
        self.abstract = abstract
        self.fields = fields
        self.creators = item.creators.sorted(byKeyPath: "orderId")
        self.attachments = item.children
                               .filter("needsSync = false AND rawType = %@", ItemType.attachment.rawValue)
                               .sorted(byKeyPath: "title")
        self.notes = item.children
                         .filter("needsSync = false AND rawType = %@", ItemType.note.rawValue)
                         .sorted(byKeyPath: "title")
        self.tags = item.tags.sorted(byKeyPath: "name")
        self.sections = self.createSections()
    }

    func rowCount(for section: ItemDetailStore.StoreState.Section) -> Int {
        switch section {
        case .title, .abstract:
            return 1
        case .creators:
            return self.creators.count
        case .fields:
            return self.fields.count
        case .attachments:
            return 1 + self.attachments.count
        case .notes:
            return 1 + self.notes.count
        case .tags:
            return 1 + self.tags.count
        case .related:
            return 0
        }
    }

    func creator(at index: Int) -> RCreator? {
        guard index < self.creators.count else { return nil }
        return self.creators[index]
    }

    func field(at index: Int) -> ItemDetailStore.StoreState.Field? {
        guard index < self.fields.count else { return nil }
        return self.fields[index]
    }

    func note(at index: Int) -> RItem? {
        guard index < self.notes.count else { return nil }
        return self.notes[index]
    }

    func attachment(at index: Int) -> RItem? {
        guard index < self.attachments.count else { return nil }
        return self.attachments[index]
    }

    func tag(at index: Int) -> RTag? {
        guard index < self.tags.count else { return nil }
        return self.tags[index]
    }

    private func createSections() -> [ItemDetailStore.StoreState.Section] {
        return ItemDetailStore.StoreState
                              .allSections.compactMap { section -> ItemDetailStore.StoreState.Section? in
                                  switch section {
                                  case .title:
                                      return section
                                  case .abstract:
                                      return self.abstract == nil ? nil : section
                                  case .creators:
                                    return self.creators.isEmpty ? nil : section
                                  case .fields:
                                      return self.fields.isEmpty ? nil : section
                                  case .attachments:
                                      return self.attachments.isEmpty ? nil : section
                                  case .notes:
                                      return self.notes.isEmpty ? nil : section
                                  case .tags:
                                      return self.tags.isEmpty ? nil : section
                                  case .related:
                                      return nil
                                  }
                              }
    }

    func merge(with dataSource: ItemDetailEditingDataSource) {
        self.title = dataSource.title
        self.abstract = dataSource.abstract
        self.fields = dataSource.fields.compactMap({ $0.value.isEmpty ? nil : $0 })
        self.sections = self.createSections()
    }
}

extension ItemDetailStore.StoreState: Equatable {
    static func == (lhs: ItemDetailStore.StoreState, rhs: ItemDetailStore.StoreState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error && lhs.downloadState == rhs.downloadState &&
               lhs.isEditing == rhs.isEditing
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
