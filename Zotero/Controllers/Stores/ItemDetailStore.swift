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
    func note(at index: Int) -> ItemDetailStore.StoreState.Note?
    func attachment(at index: Int) -> (RItem, ItemDetailStore.StoreState.AttachmentType?)?
    func tag(at index: Int) -> RTag?
}

class ItemDetailStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
        case clearAttachment(String)
        case showAttachment(RItem)
        case startEditing
        case stopEditing(Bool) // SaveChanges
        case updateField(String, String) // Name, Value
        case updateTitle(String)
        case updateAbstract(String)
        case updateNote(key: String, text: String)
        case reloadLocale
    }

    enum StoreError: Error, Equatable {
        case typeNotSupported, libraryNotAssigned,
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
            let type: String
            let name: String
            let value: String
            let changed: Bool

            func changed(value: String) -> Field {
                return Field(type: self.type, name: self.name, value: self.value, changed: true)
            }
        }

        struct Note {
            let key: String
            let title: String
            let text: String
            let changed: Bool

            init(key: String, title: String, text: String, changed: Bool) {
                self.key = key
                self.title = title
                self.text = text
                self.changed = changed
            }

            init?(item: RItem) {
                guard item.type == .note else {
                    DDLogError("Trying to create Note from RItem which is not a note!")
                    return nil
                }

                self.key = item.key
                self.title = item.title
                self.text = item.fields.filter(Predicates.key(FieldKeys.note)).first?.value ?? ""
                self.changed = false
            }

            func changed(text: String) -> Note {
                let title = text.strippedHtml ?? text
                return Note(key: self.key, title: title, text: text, changed: true)
            }
        }

        enum AttachmentType: Equatable {
            case file(file: File, isLocal: Bool)
            case url(URL)

            var isLocal: Bool? {
                switch self {
                case .file(_, let isLocal):
                    return isLocal
                case .url:
                    return nil
                }
            }

            static func == (lhs: AttachmentType, rhs: AttachmentType) -> Bool {
                switch (lhs, rhs) {
                case (.url(let lUrl), .url(let rUrl)):
                    return lUrl == rUrl
                case (.file(let lFile, _), .file(let rFile, _)):
                    return lFile.createUrl() == rFile.createUrl()
                default:
                    return false
                }
            }
        }

        enum AttachmentState: Equatable {
            case progress(Double)
            case result(AttachmentType, Bool) // Type of attachment, Bool indicating whether attachment was downloaded
            case failure
        }

        fileprivate static let allSections: [StoreState.Section] = [.title, .creators, .fields, .abstract,
                                                                    .notes, .tags, .attachments]
        let item: RItem

        fileprivate(set) var changes: Changes
        fileprivate(set) var attachmentStates: [String: AttachmentState]
        fileprivate(set) var isEditing: Bool
        fileprivate(set) var dataSource: ItemDetailDataSource?
        fileprivate(set) var editingDiff: [EditingSectionDiff]?
        fileprivate(set) var error: StoreError?
        fileprivate var version: Int

        fileprivate var previewDataSource: ItemDetailPreviewDataSource?
        fileprivate var editingDataSource: ItemDetailEditingDataSource?

        init(item: RItem) {
            self.item = item
            self.attachmentStates = [:]
            self.changes = []
            self.isEditing = false
            self.version = 0
        }
    }

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let schemaController: SchemaController
    let disposeBag: DisposeBag

    var updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
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
        case .clearAttachment(let key):
            self.updater.updateState { state in
                state.attachmentStates[key] = nil
            }
        case .startEditing:
            self.startEditing()
        case .stopEditing(let save):
            self.stopEditing(shouldSaveChanges: save)
        case .updateField(let type, let value):
            if let index = self.state.value.editingDataSource?.fields.firstIndex(where: { $0.type == type }),
               let field = self.state.value.editingDataSource?.fields[index] {
                self.state.value.editingDataSource?.fields[index] = field.changed(value: value)
            }
        case .updateTitle(let title):
            self.state.value.editingDataSource?.title = title
        case .updateAbstract(let abstract):
            self.state.value.editingDataSource?.abstract = abstract
        case .updateNote(let key, let text):
            self.state.value.editingDataSource?.updateNote(with: key, to: text)
            self.updater.updateState { state in
                state.changes.insert(.data)
                state.version += 1
            }
        case .reloadLocale:
            self.reloadLocale()
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
                try self.storeChanges(from: editingDataSource, originalSource: previewDataSource,
                                      itemKey: key, libraryId: libraryId)
                self.setEditing(false, previewDataSource: previewDataSource, state: self.state.value)
            } catch let error {
                DDLogError("ItemDetailStore: can't store changes: \(error)")
                self.updater.updateState { state in
                    state.error = .cantStoreChanges
                }
            }
        }
    }

    private func storeChanges(from dataSource: ItemDetailEditingDataSource, originalSource: ItemDetailPreviewDataSource,
                              itemKey: String, libraryId: LibraryIdentifier) throws {
        let title: String? = dataSource.title == originalSource.title ? nil : dataSource.title
        let abstract: String? = dataSource.abstract == originalSource.abstract ? nil : dataSource.abstract
        let request = StoreItemDetailChangesDbRequest(libraryId: libraryId,
                                                      itemKey: itemKey,
                                                      title: title,
                                                      abstract: abstract,
                                                      fields: dataSource.fields,
                                                      notes: dataSource.notes)
        try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func setEditing(_ editing: Bool, previewDataSource: ItemDetailPreviewDataSource,
                            state: ItemDetailStore.StoreState) {
        var editingDataSource: ItemDetailEditingDataSource?
        if editing {
            editingDataSource = ItemDetailEditingDataSource(item: state.item, previewDataSource: previewDataSource,
                                                            schemaController: self.schemaController)
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
                                                             schemaController: self.schemaController,
                                                             fileStorage: self.fileStorage)
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
        guard let groupType = self.groupType(from: libraryId) else { return }

        if let metadata = self.state.value.previewDataSource?.attachmentMetadata[item.key] {
            switch metadata {
            case .url(let url):
                self.showUrlAttachment(url, for: item.key)
            case .file(let file, let isLocal):
                if isLocal {
                    self.showLocalFileAttachment(file, for: item.key, isDownloaded: false)
                } else {
                    self.fetchAndShowFileAttachment(for: item.key, groupType: groupType, file: file)
                }
            }
            return
        }

        let contentType = item.fields.filter("key = %@", "contentType").first?.value ?? ""
        if !contentType.isEmpty {
            guard let ext = contentType.mimeTypeExtension else {
                DDLogError("ItemDetailStore: show attachment - mimeType/extension " +
                           "unknown (\(contentType)) for item (\(item.key))")
                self.reportError(.contentTypeUnknown)
                return
            }
            self.showFileAttachment(for: item.key, libraryId: libraryId, groupType: groupType, ext: ext)
            return
        }

        if let urlString = item.fields.filter("key = %@", "url").first?.value,
           let url = URL(string: urlString) {
            let metadata = StoreState.AttachmentType.url(url)
            self.state.value.previewDataSource?.attachmentMetadata[item.key] = metadata
            self.showUrlAttachment(url, for: item.key)
            return
        }

        self.reportError(.contentTypeUnknown)
    }

    private func showFileAttachment(for key: String, libraryId: LibraryIdentifier,
                                    groupType: SyncController.Library, ext: String) {
        let file = Files.itemFile(libraryId: libraryId, key: key, ext: ext)

        if self.fileStorage.has(file) {
            let metadata = StoreState.AttachmentType.file(file: file, isLocal: true)
            self.state.value.previewDataSource?.attachmentMetadata[key] = metadata
            self.showLocalFileAttachment(file, for: key, isDownloaded: false)
            return
        }

        self.fetchAndShowFileAttachment(for: key, groupType: groupType, file: file)
    }

    private func fetchAndShowFileAttachment(for key: String, groupType: SyncController.Library, file: File) {
        self.showProgress(0, for: key)
        let request = FileRequest(groupType: groupType, key: key, destination: file)
        self.apiClient.download(request: request)
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] progress in
                          let progress = progress.totalBytes == 0 ? 0 : Double(progress.bytesWritten) / Double(progress.totalBytes)
                          self?.showProgress(progress, for: key)
                      }, onError: { [weak self] error in
                          DDLogError("ItemDetailStore: show attachment - can't download file - \(error)")
                          self?.updater.updateState { newState in
                              newState.attachmentStates[key] = .failure
                              newState.changes = .download
                          }
                      }, onCompleted: { [weak self] in
                          let metadata = StoreState.AttachmentType.file(file: file, isLocal: true)
                          self?.state.value.previewDataSource?.attachmentMetadata[key] = metadata
                          self?.showLocalFileAttachment(file, for: key, isDownloaded: true)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func showUrlAttachment(_ url: URL, for key: String) {
        self.updater.updateState { state in
            state.attachmentStates[key] = .result(.url(url), false)
            state.changes = .download
        }
    }

    private func showLocalFileAttachment(_ file: File, for key: String, isDownloaded: Bool) {
        self.updater.updateState { state in
            state.attachmentStates[key] = .result(.file(file: file, isLocal: true), isDownloaded)
            state.changes = .download
        }
    }

    private func showProgress(_ progress: Double, for key: String) {
        self.updater.updateState { newState in
            newState.attachmentStates[key] = .progress(progress)
            newState.changes = .download
        }
    }

    private func groupType(from libraryId: LibraryIdentifier) -> SyncController.Library? {
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
                return nil
            }
        }
        return groupType
    }

    private func reportError(_ error: StoreError) {
        self.updater.updateState { newState in
            newState.error = error
        }
    }

    private func reloadLocale() {
        do {
            let previewDataSource = try ItemDetailPreviewDataSource(item: self.state.value.item,
                                                                    schemaController: self.schemaController,
                                                                    fileStorage: self.fileStorage)
            var editingDataSource: ItemDetailEditingDataSource?
            if self.state.value.isEditing {
                editingDataSource = ItemDetailEditingDataSource(item: self.state.value.item,
                                                                previewDataSource: previewDataSource,
                                                                schemaController: self.schemaController)
            }

            self.updater.updateState { state in
                state.previewDataSource = previewDataSource
                state.editingDataSource = editingDataSource
                state.dataSource = state.isEditing ? editingDataSource : previewDataSource
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
}

class ItemDetailEditingDataSource: ItemDetailDataSource {
    fileprivate let creators: [RCreator]
    fileprivate let attachments: [RItem]
    fileprivate var notes: [ItemDetailStore.StoreState.Note]
    fileprivate let tags: [RTag]
    fileprivate var fields: [ItemDetailStore.StoreState.Field]
    let sections: [ItemDetailStore.StoreState.Section]
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, previewDataSource: ItemDetailPreviewDataSource, schemaController: SchemaDataSource) {
        let hasAbstract = schemaController.fields(for: item.rawType)?
                                          .contains(where: { $0.field == FieldKeys.abstract }) ?? false
        var sections = ItemDetailStore.StoreState.allSections
        if !hasAbstract {
            if let index = sections.firstIndex(where: { $0 == .abstract }) {
                sections.remove(at: index)
            }
        }

        var fields: [ItemDetailStore.StoreState.Field] = []
        previewDataSource.fieldTypes.forEach { type in
            if let field = previewDataSource.fields.first(where: { $0.type == type }) {
                fields.append(field)
            } else {
                let localized = schemaController.localized(field: type) ?? ""
                fields.append(ItemDetailStore.StoreState.Field(type: type, name: localized, value: "", changed: false))
            }
        }

        self.sections = sections
        self.title = previewDataSource.title
        self.type = previewDataSource.type
        self.abstract = previewDataSource.abstract
        self.fields = fields
        self.creators = previewDataSource.creators.map(RCreator.init)
        self.attachments = previewDataSource.attachments.map(RItem.init)
        self.notes = previewDataSource.notes
        self.tags = previewDataSource.tags.map(RTag.init)
    }

    func updateNote(with key: String, to text: String) {
        // TODO: - optimise sorting - remove original note, edit, place note into correct position
        guard let index = self.notes.firstIndex(where: { $0.key == key }) else { return }
        let newNote = self.notes[index].changed(text: text)
        self.notes[index] = newNote
        self.notes.sort(by: { $0.title > $1.title })
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

    func note(at index: Int) -> ItemDetailStore.StoreState.Note? {
        guard index < self.notes.count else { return nil }
        return self.notes[index]
    }

    func attachment(at index: Int) -> (RItem, ItemDetailStore.StoreState.AttachmentType?)? {
        guard index < self.attachments.count else { return nil }
        return (self.attachments[index], nil)
    }

    func tag(at index: Int) -> RTag? {
        guard index < self.tags.count else { return nil }
        return self.tags[index]
    }
}

class ItemDetailPreviewDataSource: ItemDetailDataSource {
    private let fileStorage: FileStorage
    fileprivate let fieldTypes: [String]
    fileprivate let creators: Results<RCreator>
    fileprivate let attachments: Results<RItem>
    fileprivate var notes: [ItemDetailStore.StoreState.Note]
    fileprivate let tags: Results<RTag>
    fileprivate var fields: [ItemDetailStore.StoreState.Field]
    private(set) var sections: [ItemDetailStore.StoreState.Section] = []
    fileprivate var attachmentMetadata: [String: ItemDetailStore.StoreState.AttachmentType]
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, schemaController: SchemaDataSource, fileStorage: FileStorage) throws {
        guard var sortedFields = schemaController.fields(for: item.rawType)?.map({ $0.field }) else {
            throw ItemDetailStore.StoreError.typeNotSupported
        }

        // We're showing title and abstract separately, outside of fields, let's just exclude them here
        let excludedKeys = FieldKeys.titles + [FieldKeys.abstract]
        sortedFields.removeAll { key -> Bool in
            return excludedKeys.contains(key)
        }
        var abstract: String?
        var values: [String: String] = [:]
        item.fields.filter("value != %@", "").forEach { field in
            if field.key ==  FieldKeys.abstract {
                abstract = field.value
            } else {
                values[field.key] = field.value
            }
        }

        let fields: [ItemDetailStore.StoreState.Field] = sortedFields.compactMap { type in
            let localized = schemaController.localized(field: type) ?? ""
            return values[type].flatMap({ ItemDetailStore.StoreState.Field(type: type, name: localized,
                                                                           value: $0, changed: false) })
        }

        self.fileStorage = fileStorage
        self.fieldTypes = sortedFields
        self.title = item.title
        self.type = item.rawType
        self.abstract = abstract
        self.fields = fields
        self.creators = item.creators.sorted(byKeyPath: "orderId")
        self.attachments = item.children
                               .filter(Predicates.items(type: .attachment, notSyncState: .dirty, trash: false))
                               .sorted(byKeyPath: "title")
        self.notes = item.children
                         .filter(Predicates.items(type: .note, notSyncState: .dirty))
                         .sorted(byKeyPath: "title")
                         .compactMap(ItemDetailStore.StoreState.Note.init)
        self.tags = item.tags.sorted(byKeyPath: "name")
        self.attachmentMetadata = [:]
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

    func note(at index: Int) -> ItemDetailStore.StoreState.Note? {
        guard index < self.notes.count else { return nil }
        return self.notes[index]
    }

    func attachment(at index: Int) -> (RItem, ItemDetailStore.StoreState.AttachmentType?)? {
        guard index < self.attachments.count else { return nil }

        let attachment = self.attachments[index]

        if let metadata = self.attachmentMetadata[attachment.key] {
            return (attachment, metadata)
        }

        var metadata: ItemDetailStore.StoreState.AttachmentType?

        let contentType = attachment.fields.filter("key = %@", "contentType").first?.value ?? ""
        if contentType.isEmpty { // Some other attachment (url, etc.)
            if let urlString = attachment.fields.filter("key = %@", "url").first?.value,
               let url = URL(string: urlString) {
                metadata = ItemDetailStore.StoreState.AttachmentType.url(url)
            }
        } else { // File attachment
            guard let ext = contentType.mimeTypeExtension,
                  let libraryId = attachment.libraryObject?.identifier else {
                DDLogError("ItemDetailStore: attachment metadata - mimeType/extension " +
                           "unknown (\(contentType)) for item (\(attachment.key))")
                return (attachment, nil)
            }

            let file = Files.itemFile(libraryId: libraryId, key: attachment.key, ext: ext)
            let isLocal = self.fileStorage.has(file)
            metadata = ItemDetailStore.StoreState.AttachmentType.file(file: file, isLocal: isLocal)
        }

        self.attachmentMetadata[attachment.key] = metadata
        return (attachment, metadata)
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
        self.notes = dataSource.notes
        self.sections = self.createSections()
    }
}

extension ItemDetailStore.StoreState: Equatable {
    static func == (lhs: ItemDetailStore.StoreState, rhs: ItemDetailStore.StoreState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error && lhs.attachmentStates == rhs.attachmentStates &&
               lhs.isEditing == rhs.isEditing
    }
}

extension ItemDetailStore.Changes {
    static let data = ItemDetailStore.Changes(rawValue: 1 << 0)
    static let download = ItemDetailStore.Changes(rawValue: 1 << 1)
}
