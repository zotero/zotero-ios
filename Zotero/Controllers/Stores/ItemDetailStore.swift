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
    func creator(at index: Int) -> ItemDetailStore.StoreState.Creator?
    func field(at index: Int) -> ItemDetailStore.StoreState.Field?
    func note(at index: Int) -> ItemDetailStore.StoreState.Note?
    func attachment(at index: Int) -> ItemDetailStore.StoreState.Attachment?
    func tag(at index: Int) -> ItemDetailStore.StoreState.Tag?
}

class ItemDetailStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
        case clearAttachment(String)
        case showAttachment(StoreState.Attachment)
        case startEditing
        case stopEditing(Bool) // SaveChanges
        case updateField(String, String) // Name, Value
        case updateTitle(String)
        case updateAbstract(String)
        case updateNote(key: String, text: String)
        case createNote(String)
        case reloadLocale
        case changeType(String)
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

        struct Attachment {
            let key: String
            let title: String
            let type: AttachmentType?
            let libraryId: LibraryIdentifier

            init(key: String, title: String, type: AttachmentType?, libraryId: LibraryIdentifier) {
                self.key = key
                self.title = title
                self.type = type
                self.libraryId = libraryId
            }

            init?(item: RItem, fileStorage: FileStorage) {
                guard let libraryId = item.libraryObject?.identifier else {
                    DDLogError("Attachment: library not assigned to item (\(item.key))")
                    return nil
                }

                var type: AttachmentType?
                let contentType = item.fields.filter("key = %@", "contentType").first?.value ?? ""

                if !contentType.isEmpty { // File attachment
                    if let ext = contentType.mimeTypeExtension,
                       let libraryId = item.libraryObject?.identifier {
                        let file = Files.itemFile(libraryId: libraryId, key: item.key, ext: ext)
                        let isLocal = fileStorage.has(file)
                        type = .file(file: file, isLocal: isLocal)
                    } else {
                        DDLogError("Attachment: mimeType/extension unknown (\(contentType)) for item (\(item.key))")
                    }
                } else { // Some other attachment (url, etc.)
                    if let urlString = item.fields.filter("key = %@", "url").first?.value,
                        let url = URL(string: urlString) {
                        type = .url(url)
                    }
                }

                self.libraryId = libraryId
                self.key = item.key
                self.title = item.title
                self.type = type
            }

            func changed(isLocal: Bool) -> Attachment {
                guard let type = self.type else { return self }

                switch type {
                case .url: return self
                case .file(let file, _):
                    return Attachment(key: self.key, title: self.title,
                                      type: .file(file: file, isLocal: isLocal),
                                      libraryId: self.libraryId)
                }
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

            init(text: String) {
                self.key = KeyGenerator.newKey
                self.title = text.strippedHtml ?? text
                self.text = text
                self.changed = true
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

        struct Tag {
            let name: String
            let color: String

            var uiColor: UIColor? {
                guard !self.color.isEmpty else { return nil }
                return UIColor(hex: self.color)
            }

            init(tag: RTag) {
                self.name = tag.name
                self.color = tag.color
            }
        }

        struct Creator {
            let rawType: String
            let firstName: String
            let lastName: String
            let name: String

            init(creator: RCreator) {
                self.rawType = creator.rawType
                self.firstName = creator.firstName
                self.lastName = creator.lastName
                self.name = creator.name
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

    let userId: Int
    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let schemaController: SchemaController
    let disposeBag: DisposeBag

    var updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) throws {
        self.userId = try dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
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
        case .showAttachment(let attachment):
            self.show(attachment: attachment)
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
               let field = self.state.value.editingDataSource?.fields[index],
               field.value != value {
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
        case .createNote(let text):
            self.state.value.editingDataSource?.addNote(with: text)
            self.updater.updateState { state in
                state.changes.insert(.data)
                state.version += 1
            }
        case .reloadLocale:
            self.reloadLocale()
        case .changeType(let type):
            self.changeType(to: type)
        }
    }

    private func changeType(to type: String) {
        guard let dataSource = self.state.value.editingDataSource else { return }

        dataSource.changeType(to: type, schemaController: self.schemaController)

        var diff: [EditingSectionDiff] = []
        if let index = dataSource.sections.firstIndex(of: .title) {
            diff.append(EditingSectionDiff(type: .update, index: index))
        }
        if let index = dataSource.sections.firstIndex(of: .fields) {
            diff.append(EditingSectionDiff(type: .update, index: index))
        }

        self.updater.updateState { state in
            state.editingDiff = diff
            state.version += 1
            state.changes.insert(.data)
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }
            do {
                try self.storeChanges(from: editingDataSource, originalSource: previewDataSource,
                                      itemKey: key, libraryId: libraryId)
                previewDataSource.merge(with: editingDataSource)
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
        let type: String? = dataSource.type == originalSource.type ? nil : dataSource.type
        let title: String? = dataSource.title == originalSource.title ? nil : dataSource.title
        let abstract: String? = dataSource.abstract == originalSource.abstract ? nil : dataSource.abstract
        let request = StoreItemDetailChangesDbRequest(libraryId: libraryId,
                                                      itemKey: itemKey,
                                                      type: type,
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
            editingDataSource = try? ItemDetailEditingDataSource(item: state.item, previewDataSource: previewDataSource,
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

    private func diff(between lDataSource: ItemDetailDataSource,
                      and rDataSource: ItemDetailDataSource, isEditing: Bool) -> [EditingSectionDiff] {
        let sectionDiff = self.diff(between: rDataSource.sections, and: lDataSource.sections,
                                    sameIndicesRelativeToDifferent: !isEditing)

        var diff: [EditingSectionDiff] = []
        var sameIndex = 0

        for sectionData in rDataSource.sections.enumerated() {
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

    private func show(attachment: StoreState.Attachment) {
        guard let type = attachment.type else {
            self.reportError(.contentTypeUnknown)
            return
        }

        switch type {
        case .url(let url):
            self.showUrlAttachment(url, for: attachment.key)
        case .file(let file, let isLocal):
            if isLocal {
                self.show(localFileAttachment: file, for: attachment.key, isDownloaded: false)
            } else {
                self.fetchAndShow(fileAttachment: file, for: attachment.key, libraryId: attachment.libraryId)
            }
        }
    }

    private func fetchAndShow(fileAttachment file: File, for key: String, libraryId: LibraryIdentifier) {
        self.showProgress(0, for: key)

        let groupType: SyncController.Library
        switch libraryId {
        case .group(let groupId):
            groupType = .group(groupId)
        case .custom(let type):
            groupType = .user(self.userId, type)
        }

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
                          self?.state.value.previewDataSource?.updateAttachment(with: key, isLocal: true)
                          self?.show(localFileAttachment: file, for: key, isDownloaded: true)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func showUrlAttachment(_ url: URL, for key: String) {
        self.updater.updateState { state in
            state.attachmentStates[key] = .result(.url(url), false)
            state.changes = .download
        }
    }

    private func show(localFileAttachment file: File, for key: String, isDownloaded: Bool) {
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
                editingDataSource = try ItemDetailEditingDataSource(item: self.state.value.item,
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
    fileprivate let creators: [ItemDetailStore.StoreState.Creator]
    fileprivate var attachments: [ItemDetailStore.StoreState.Attachment]
    fileprivate var notes: [ItemDetailStore.StoreState.Note]
    fileprivate let tags: [ItemDetailStore.StoreState.Tag]
    fileprivate var fields: [ItemDetailStore.StoreState.Field]
    let sections: [ItemDetailStore.StoreState.Section]
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, previewDataSource: ItemDetailPreviewDataSource, schemaController: SchemaDataSource) throws {
        guard let sortedFields = schemaController.fields(for: item.rawType)?.map({ $0.field }) else {
            throw ItemDetailStore.StoreError.typeNotSupported
        }

        let hasAbstract = sortedFields.contains(where: { $0 == FieldKeys.abstract })

        var sections = ItemDetailStore.StoreState.allSections
        if !hasAbstract {
            if let index = sections.firstIndex(where: { $0 == .abstract }) {
                sections.remove(at: index)
            }
        }

        var fields: [ItemDetailStore.StoreState.Field] = []
        for field in sortedFields {
            if field == FieldKeys.abstract || FieldKeys.titles.contains(field) { continue }

            if let field = previewDataSource.fields.first(where: { $0.type == field }) {
                fields.append(field)
            } else {
                let localized = schemaController.localized(field: field) ?? ""
                fields.append(ItemDetailStore.StoreState.Field(type: field, name: localized, value: "", changed: false))
            }
        }

        self.sections = sections
        self.title = previewDataSource.title
        self.type = previewDataSource.type
        self.abstract = previewDataSource.abstract
        self.fields = fields
        self.creators = previewDataSource.creators
        self.attachments = previewDataSource.attachments
        self.notes = previewDataSource.notes
        self.tags = previewDataSource.tags
    }

    func addNote(with text: String) {
        // TODO: - optimise insertion
        let note = ItemDetailStore.StoreState.Note(text: text)
        self.notes.append(note)
        self.notes.sort(by: { $0.title > $1.title })
    }

    func updateNote(with key: String, to text: String) {
        // TODO: - optimise sorting - remove original note, edit, place note into correct position
        guard let index = self.notes.firstIndex(where: { $0.key == key }) else { return }
        let newNote = self.notes[index].changed(text: text)
        self.notes[index] = newNote
        self.notes.sort(by: { $0.title > $1.title })
    }

    func changeType(to type: String, schemaController: SchemaController) {
        guard let fields = schemaController.fields(for: type)?.map({ $0.field }) else { return }

        let newFields = fields.compactMap { field -> ItemDetailStore.StoreState.Field? in
            if field == FieldKeys.abstract || FieldKeys.titles.contains(field) { return nil }
            let localized = schemaController.localized(field: field) ?? ""
            let oldField = self.fields.first(where: { $0.type == field })
            return ItemDetailStore.StoreState.Field(type: field, name: localized,
                                                    value: (oldField?.value ?? ""),
                                                    changed: (oldField?.changed ?? false))
        }

        self.type = type
        self.fields = newFields
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

    func creator(at index: Int) -> ItemDetailStore.StoreState.Creator? {
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

    func attachment(at index: Int) -> ItemDetailStore.StoreState.Attachment? {
        guard index < self.attachments.count else { return nil }
        return self.attachments[index]
    }

    func tag(at index: Int) -> ItemDetailStore.StoreState.Tag? {
        guard index < self.tags.count else { return nil }
        return self.tags[index]
    }
}

class ItemDetailPreviewDataSource: ItemDetailDataSource {
    private let fileStorage: FileStorage
    fileprivate let creators: [ItemDetailStore.StoreState.Creator]
    private(set) fileprivate var attachments: [ItemDetailStore.StoreState.Attachment]
    private(set) fileprivate var notes: [ItemDetailStore.StoreState.Note]
    fileprivate let tags: [ItemDetailStore.StoreState.Tag]
    private(set) fileprivate var fields: [ItemDetailStore.StoreState.Field]
    private(set) var sections: [ItemDetailStore.StoreState.Section] = []
    fileprivate(set) var abstract: String?
    fileprivate(set) var title: String
    fileprivate(set) var type: String

    init(item: RItem, schemaController: SchemaDataSource, fileStorage: FileStorage) throws {
        guard let sortedFields = schemaController.fields(for: item.rawType)?.map({ $0.field }) else {
            throw ItemDetailStore.StoreError.typeNotSupported
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

        let fields: [ItemDetailStore.StoreState.Field] = sortedFields.compactMap { field in
            if field == FieldKeys.abstract || FieldKeys.titles.contains(field) { return nil }
            let localized = schemaController.localized(field: field) ?? ""
            return values[field].flatMap({ ItemDetailStore.StoreState.Field(type: field, name: localized,
                                                                           value: $0, changed: false) })
        }

        self.fileStorage = fileStorage
        self.title = item.title
        self.type = item.rawType
        self.abstract = abstract
        self.fields = fields
        self.creators = item.creators.sorted(byKeyPath: "orderId").map(ItemDetailStore.StoreState.Creator.init)
        self.attachments = item.children
                               .filter(Predicates.items(type: .attachment, notSyncState: .dirty, trash: false))
                               .sorted(byKeyPath: "title")
                               .compactMap({ ItemDetailStore.StoreState.Attachment(item: $0, fileStorage: fileStorage) })
        self.notes = item.children
                         .filter(Predicates.items(type: .note, notSyncState: .dirty))
                         .sorted(byKeyPath: "title")
                         .compactMap(ItemDetailStore.StoreState.Note.init)
        self.tags = item.tags.sorted(byKeyPath: "name").map(ItemDetailStore.StoreState.Tag.init)
        self.sections = self.createSections()
    }

    func updateAttachment(with key: String, isLocal: Bool) {
        guard let index = self.attachments.firstIndex(where: { $0.key == key }) else { return }
        let newAttachment = self.attachments[index].changed(isLocal: isLocal)
        self.attachments[index] = newAttachment
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

    func creator(at index: Int) -> ItemDetailStore.StoreState.Creator? {
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

    func attachment(at index: Int) -> ItemDetailStore.StoreState.Attachment? {
        guard index < self.attachments.count else { return nil }
        return self.attachments[index]
    }

    func tag(at index: Int) -> ItemDetailStore.StoreState.Tag? {
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
        self.type = dataSource.type
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
