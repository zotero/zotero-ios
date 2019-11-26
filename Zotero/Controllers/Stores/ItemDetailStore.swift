//
//  ItemDetailStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation
import UIKit

import CocoaLumberjack
import RealmSwift
import RxSwift

class ItemDetailStore: ObservableObject {
    enum Error: Swift.Error, Equatable, Identifiable, Hashable {
        case typeNotSupported, libraryNotAssigned,
             contentTypeUnknown, userMissing, downloadError, unknown,
             cantStoreChanges
        case fileNotCopied(Int)
        case droppedFields([String])

        var id: Int {
            return self.hashValue
        }
    }

    struct State {
        enum DetailType {
            case creation(libraryId: LibraryIdentifier, collectionKey: String?, filesEditable: Bool)
            case duplication(RItem, collectionKey: String?)
            case preview(RItem)

            var isCreation: Bool {
                switch self {
                case .preview:
                    return false
                case .creation, .duplication:
                    return true
                }
            }
        }

        struct Field: Identifiable, Equatable {
            let key: String
            let baseField: String?
            var name: String
            var value: String
            let isTitle: Bool

            var id: String { return self.key }
        }

        struct Attachment: Identifiable, Equatable {
            enum ContentType: Equatable {
                case file(file: File, filename: String, isLocal: Bool)
                case url(URL)

                static func == (lhs: ContentType, rhs: ContentType) -> Bool {
                    switch (lhs, rhs) {
                    case (.url(let lUrl), .url(let rUrl)):
                        return lUrl == rUrl
                    case (.file(let lFile, _, _), .file(let rFile, _, _)):
                        return lFile.createUrl() == rFile.createUrl()
                    default:
                        return false
                    }
                }
            }

            let key: String
            let title: String
            let type: ContentType
            let libraryId: LibraryIdentifier

            var iconName: String {
                switch self.type {
                case .file(let file, _, _):
                    switch file.ext {
                    case "pdf":
                        return "pdf"
                    default:
                        return "document"
                    }
                case .url:
                    return "web-page"
                }
            }

            var id: String { return self.key }

            init(key: String, title: String, type: ContentType,
                 libraryId: LibraryIdentifier) {
                self.key = key
                self.title = title
                self.type = type
                self.libraryId = libraryId
            }

            init?(item: RItem, type: ContentType) {
                guard let libraryId = item.libraryObject?.identifier else {
                    DDLogError("Attachment: library not assigned to item (\(item.key))")
                    return nil
                }

                self.libraryId = libraryId
                self.key = item.key
                self.title = item.displayTitle
                self.type = type
            }

            func changed(isLocal: Bool) -> Attachment {
                switch type {
                case .url: return self
                case .file(let file, let filename, _):
                    return Attachment(key: self.key,
                                      title: self.title,
                                      type: .file(file: file, filename: filename, isLocal: isLocal),
                                      libraryId: self.libraryId)
                }
            }
        }

        struct Note: Identifiable, Equatable {
            let key: String
            var title: String
            var text: String

            var id: String { return self.key }

            init(key: String, text: String) {
                self.key = key
                self.title = text.strippedHtml ?? text
                self.text = text
            }

            init?(item: RItem) {
                guard item.rawType == ItemTypes.note else {
                    DDLogError("Trying to create Note from RItem which is not a note!")
                    return nil
                }

                self.key = item.key
                self.title = item.displayTitle
                self.text = item.fields.filter(.key(FieldKeys.note)).first?.value ?? ""
            }
        }

        struct Creator: Identifiable, Equatable {
            enum NamePresentation: Equatable {
                case separate, full

                mutating func toggle() {
                    self = self == .full ? .separate : .full
                }
            }

            var type: String
            var primary: Bool
            var localizedType: String
            var fullName: String
            var firstName: String
            var lastName: String
            var namePresentation: NamePresentation {
                willSet {
                    self.change(namePresentation: newValue)
                }
            }

            var name: String {
                if !self.fullName.isEmpty {
                    return self.fullName
                }

                guard !self.firstName.isEmpty || !self.lastName.isEmpty else { return "" }

                var name = self.lastName
                if !self.lastName.isEmpty {
                    name += ", "
                }
                return name + self.firstName
            }

            var isEmpty: Bool {
                return self.fullName.isEmpty && self.firstName.isEmpty && self.lastName.isEmpty
            }

            let id: UUID

            init(firstName: String, lastName: String, fullName: String, type: String, primary: Bool, localizedType: String) {
                self.id = UUID()
                self.type = type
                self.primary = primary
                self.localizedType = localizedType
                self.fullName = fullName
                self.firstName = firstName
                self.lastName = lastName
                self.namePresentation = fullName.isEmpty ? .separate : .full
            }

            init(type: String, primary: Bool, localizedType: String) {
                self.id = UUID()
                self.type = type
                self.primary = primary
                self.localizedType = localizedType
                self.fullName = ""
                self.firstName = ""
                self.lastName = ""
                self.namePresentation = .full
            }

            mutating func change(namePresentation: NamePresentation) {
                guard namePresentation != self.namePresentation else { return }

                switch namePresentation {
                case .full:
                    self.fullName = self.firstName + (self.firstName.isEmpty ? "" : " ") + self.lastName
                    self.firstName = ""
                    self.lastName = ""
                case .separate:
                    if self.fullName.isEmpty {
                        self.firstName = ""
                        self.lastName = ""
                        return
                    }

                    if !self.fullName.contains(" ") {
                        self.lastName = self.fullName
                        self.firstName = ""
                        return
                    }

                    let components = self.fullName.components(separatedBy: " ")
                    self.firstName = components.dropLast().joined(separator: " ")
                    self.lastName = components.last ?? ""
                }
            }
        }

        struct Data: Equatable {
            var title: String
            var type: String
            var localizedType: String
            var creators: [UUID: Creator]
            var creatorIds: [UUID]
            var fields: [String: Field]
            var fieldIds: [String]
            var abstract: String?
            var notes: [Note]
            var attachments: [Attachment]
            var tags: [Tag]

            var dateModified: Date
            let dateAdded: Date

            var maxFieldTitleWidth: CGFloat = 0
            var maxNonemptyFieldTitleWidth: CGFloat = 0

            func databaseFields(schemaController: SchemaController) -> [Field] {
                var allFields = Array(self.fields.values)

                if let titleKey = schemaController.titleKey(for: self.type) {
                    allFields.append(State.Field(key: titleKey,
                                                 baseField: (titleKey != FieldKeys.title ? FieldKeys.title : nil),
                                                 name: "",
                                                 value: self.title,
                                                 isTitle: true))
                }

                if let abstract = self.abstract {
                    allFields.append(State.Field(key: FieldKeys.abstract,
                                                 baseField: nil,
                                                 name: "",
                                                 value: abstract,
                                                 isTitle: false))
                }


                return allFields
            }

            mutating func recalculateMaxTitleWidth() {
                var maxTitle = ""
                var maxNonEmptyTitle = ""

                self.fields.values.forEach { field in
                    if field.name.count > maxTitle.count {
                        maxTitle = field.name
                    }

                    if !field.value.isEmpty && field.name.count > maxNonEmptyTitle.count {
                        maxNonEmptyTitle = field.name
                    }
                }

                // TODO: - localize
                let extraFields = ["Item Type", "Date Modified", "Date Added", "Abstract"] + self.creators.values.map({ $0.localizedType })
                extraFields.forEach { name in
                    if name.count > maxTitle.count {
                        maxTitle = name
                    }
                    if name.count > maxNonEmptyTitle.count {
                        maxNonEmptyTitle = name
                    }
                }

                self.maxFieldTitleWidth = ceil(maxTitle.size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]).width)
                self.maxNonemptyFieldTitleWidth = ceil(maxNonEmptyTitle.size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]).width)
            }
        }

        let libraryId: LibraryIdentifier
        let metadataEditable: Bool
        let filesEditable: Bool

        var type: DetailType
        var data: Data
        var snapshot: Data?
        var promptSnapshot: Data?
        var downloadProgress: [String: Double]
        var downloadError: [String: ItemDetailStore.Error]
        var error: Error?
        var presentedNote: Note
        var metadataTitleMaxWidth: CGFloat

        fileprivate var library: SyncController.Library {
            switch self.libraryId {
            case .custom(let type):
                return .user(Defaults.shared.userId, type)
            case .group(let id):
                return .group(id)
            }
        }

        init(type: DetailType, data: Data, error: Error? = nil) {
            self.type = type
            self.data = data
            self.downloadProgress = [:]
            self.downloadError = [:]
            self.metadataTitleMaxWidth = 0
            self.error = error
            self.presentedNote = Note(key: KeyGenerator.newKey, text: "")

            switch type {
            case .preview(let item), .duplication(let item, _):
                self.libraryId = item.libraryObject?.identifier ?? .custom(.myLibrary)
                self.snapshot = nil
                // Item has either grouop assigned with canEditMetadata or it's a custom library which is always editable
                self.metadataEditable = item.group?.canEditMetadata ?? true
                // Item has either grouop assigned with canEditFiles or it's a custom library which is always editable
                self.filesEditable = item.group?.canEditFiles ?? true
            case .creation(let libraryId, _, let filesEditable):
                self.libraryId = libraryId
                self.snapshot = data
                // Since we're in creation mode editing must have beeen enabled
                self.metadataEditable = true
                self.filesEditable = filesEditable
            }
        }

        init(type: DetailType, error: Error) {
            self.init(type: type,
                      data: Data(title: "", type: "", localizedType: "",
                                 creators: [:], creatorIds: [],
                                 fields: [:], fieldIds: [],
                                 abstract: nil, notes: [],
                                 attachments: [], tags: [],
                                 dateModified: Date(), dateAdded: Date()),
                      error: error)
        }
    }

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let dbStorage: DbStorage
    private let schemaController: SchemaController
    private let disposeBag: DisposeBag

    @Published var state: State

    init(type: State.DetailType,
         apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()

        do {
            var data = try ItemDetailStore.createData(from: type,
                                                      schemaController: schemaController,
                                                      fileStorage: fileStorage)
            data.recalculateMaxTitleWidth()
            self.state = State(type: type, data: data)
        } catch let error {
            self.state = State(type: type,
                               error: (error as? Error) ?? .typeNotSupported)
        }
    }

    private static func fieldData(for itemType: String, schemaController: SchemaController,
                                  getExistingData: ((String, String?) -> (String?, String?))? = nil) throws -> ([String], [String: State.Field], Bool) {
        guard var fieldSchemas = schemaController.fields(for: itemType) else {
            throw Error.typeNotSupported
        }

        var fieldKeys = fieldSchemas.map({ $0.field })
        let abstractIndex = fieldKeys.firstIndex(of: FieldKeys.abstract)

        // Remove title and abstract keys, those 2 are used separately in Data struct
        if let index = abstractIndex {
            fieldKeys.remove(at: index)
            fieldSchemas.remove(at: index)
        }
        if let key = schemaController.titleKey(for: itemType), let index = fieldKeys.firstIndex(of: key) {
            fieldKeys.remove(at: index)
            fieldSchemas.remove(at: index)
        }

        var fields: [String: State.Field] = [:]
        for (offset, key) in fieldKeys.enumerated() {
            let baseField = fieldSchemas[offset].baseField
            let (existingName, existingValue) = (getExistingData?(key, baseField) ?? (nil, nil))

            let name = existingName ?? schemaController.localized(field: key) ?? ""
            let value = existingValue ?? ""

            fields[key] = State.Field(key: key,
                                      baseField: baseField,
                                      name: name,
                                      value: value,
                                      isTitle: false)
        }

        return (fieldKeys, fields, (abstractIndex != nil))
    }

    static func createData(from type: State.DetailType,
                           schemaController: SchemaController,
                           fileStorage: FileStorage) throws -> State.Data {
        switch type {
        case .creation:
            guard let itemType = schemaController.itemTypes.sorted().first,
                  let localizedType = schemaController.localized(itemType: itemType) else {
                throw Error.typeNotSupported
            }
            let (fieldIds, fields, hasAbstract) = try ItemDetailStore.fieldData(for: itemType, schemaController: schemaController)
            let date = Date()

            return State.Data(title: "",
                              type: itemType,
                              localizedType: localizedType,
                              creators: [:],
                              creatorIds: [],
                              fields: fields,
                              fieldIds: fieldIds,
                              abstract: (hasAbstract ? "" : nil),
                              notes: [],
                              attachments: [],
                              tags: [],
                              dateModified: date,
                              dateAdded: date)

        case .preview(let item), .duplication(let item, _):
            guard let localizedType = schemaController.localized(itemType: item.rawType) else {
                throw Error.typeNotSupported
            }

            var abstract: String?
            var values: [String: String] = [:]

            item.fields.forEach { field in
                switch field.key {
                case FieldKeys.abstract:
                    abstract = field.value
                default:
                    values[field.key] = field.value
                }
            }

            let (fieldIds, fields, _) = try ItemDetailStore.fieldData(for: item.rawType,
                                                                      schemaController: schemaController,
                                                                      getExistingData: { key, _ -> (String?, String?) in
                return (nil, values[key])
            })

            var creatorIds: [UUID] = []
            var creators: [UUID: State.Creator] = [:]
            for creator in item.creators.sorted(byKeyPath: "orderId") {
                guard let localizedType = schemaController.localized(creator: creator.rawType) else { continue }

                let creator = State.Creator(firstName: creator.firstName,
                                            lastName: creator.lastName,
                                            fullName: creator.name,
                                            type: creator.rawType,
                                            primary: schemaController.creatorIsPrimary(creator.rawType, itemType: item.rawType),
                                            localizedType: localizedType)
                creatorIds.append(creator.id)
                creators[creator.id] = creator
            }

            let notes = item.children.filter(.items(type: ItemTypes.note, notSyncState: .dirty, trash: false))
                                     .sorted(byKeyPath: "displayTitle")
                                     .compactMap(State.Note.init)
            let attachments: [State.Attachment]
            if item.rawType == ItemTypes.attachment {
                let attachment = attachmentType(for: item, fileStorage: fileStorage).flatMap({ State.Attachment(item: item, type: $0) })
                attachments = attachment.flatMap { [$0] } ?? []
            } else {
                let mappedAttachments = item.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                                     .sorted(byKeyPath: "displayTitle")
                                                     .compactMap({ item -> State.Attachment? in
                                                         return attachmentType(for: item, fileStorage: fileStorage)
                                                                            .flatMap({ State.Attachment(item: item, type: $0) })
                                                     })
                attachments = Array(mappedAttachments)
            }

            let tags = item.tags.sorted(byKeyPath: "name").map(Tag.init)

            return State.Data(title: item.baseTitle,
                              type: item.rawType,
                              localizedType: localizedType,
                              creators: creators,
                              creatorIds: creatorIds,
                              fields: fields,
                              fieldIds: fieldIds,
                              abstract: abstract,
                              notes: Array(notes),
                              attachments: attachments,
                              tags: Array(tags),
                              dateModified: item.dateModified,
                              dateAdded: item.dateAdded)
        }
    }

    private static func attachmentType(for item: RItem, fileStorage: FileStorage) -> State.Attachment.ContentType? {
        let contentType = item.fields.filter(.key(FieldKeys.contentType)).first?.value ?? ""
        if !contentType.isEmpty { // File attachment
            if let ext = contentType.extensionFromMimeType,
               let libraryId = item.libraryObject?.identifier {
                let filename = item.fields.filter(.key(FieldKeys.filename)).first?.value ?? (item.displayTitle + "." + ext)
                let file = Files.objectFile(for: .item, libraryId: libraryId, key: item.key, ext: ext)
                let isLocal = fileStorage.has(file)
                return .file(file: file, filename: filename, isLocal: isLocal)
            } else {
                DDLogError("Attachment: mimeType/extension unknown (\(contentType)) for item (\(item.key))")
                return nil
            }
        } else { // Some other attachment (url, etc.)
            if let urlString = item.fields.filter("key = %@", "url").first?.value,
               let url = URL(string: urlString) {
                return .url(url)
            } else {
                DDLogError("Attachment: unknown attachment, fields: \(item.fields.map({ $0.key }))")
                return nil
            }
        }
    }

    func acceptPromptSnapshot() {
        guard let snapshot = self.state.promptSnapshot else { return }
        self.state.promptSnapshot = nil
        self.state.data = snapshot
    }

    func cancelPromptSnapshot() {
        self.state.promptSnapshot = nil
    }

    func changeType(to newType: String) {
        do {
            let data = try self.data(for: newType, from: self.state.data)
            try self.set(data: data)
        } catch let error {
            self.state.error = (error as? Error) ?? .typeNotSupported
        }
    }

    private func set(data: State.Data) throws {
        let newFieldNames = Set(data.fields.values.map({ $0.name }))
        let oldFieldNames = Set(self.state.data.fields.values.filter({ !$0.value.isEmpty }).map({ $0.name }))
        let droppedNames = oldFieldNames.subtracting(newFieldNames).sorted()

        guard droppedNames.isEmpty else {
            self.state.promptSnapshot = data
            throw ItemDetailStore.Error.droppedFields(droppedNames)
        }

        self.state.data = data
    }

    private func data(for type: String, from originalData: State.Data) throws -> State.Data {
        guard let localizedType = self.schemaController.localized(itemType: type) else {
            throw Error.typeNotSupported
        }

        let (fieldIds, fields, hasAbstract) = try ItemDetailStore.fieldData(for: type,
                                                                            schemaController: self.schemaController,
                                                                            getExistingData: { key, baseField -> (String?, String?) in
            if let field = originalData.fields[key] {
                return (field.name, field.value)
            } else if let base = baseField, let field = originalData.fields.values.first(where: { $0.baseField == base }) {
                // We don't return existing name, because fields that are matching just by baseField will most likely have different names
                return (nil, field.value)
            }
            return (nil, nil)
        })

        var data = originalData
        data.type = type
        data.localizedType = localizedType
        data.fields = fields
        data.fieldIds = fieldIds
        data.abstract = hasAbstract ? (originalData.abstract ?? "") : nil
        data.creators = try self.creators(for: type, from: originalData.creators)
        data.creatorIds = originalData.creatorIds
        data.recalculateMaxTitleWidth()

        return data
    }

    private func creators(for type: String, from originalData: [UUID: State.Creator]) throws -> [UUID: State.Creator] {
        guard let schemas = self.schemaController.creators(for: type),
              let primary = schemas.first(where: { $0.primary }) else { throw Error.typeNotSupported }

        var creators = originalData
        for (key, originalCreator) in originalData {
            guard !schemas.contains(where: { $0.creatorType == originalCreator.type }) else { continue }

            var creator = originalCreator

            if originalCreator.primary {
                creator.type = primary.creatorType
            } else {
                creator.type = "contributor"
            }
            creator.localizedType = self.schemaController.localized(creator: creator.type) ?? ""

            creators[key] = creator
        }

        return creators
    }

    func addAttachments(from urls: [URL]) {
        var errors = 0

        for url in urls {
            let originalFile = Files.file(from: url)
            let key = KeyGenerator.newKey
            let file = Files.objectFile(for: .item,
                                        libraryId: self.state.libraryId,
                                        key: key,
                                        ext: originalFile.ext)
            let attachment = State.Attachment(key: key,
                                              title: originalFile.name,
                                              type: .file(file: file, filename: originalFile.name, isLocal: true),
                                              libraryId: self.state.libraryId)

            do {
                try self.fileStorage.move(from: originalFile, to: file)

                let index = self.state.data.attachments.index(of: attachment, sortedBy: { $0.title.caseInsensitiveCompare($1.title) == .orderedAscending })
                self.state.data.attachments.insert(attachment, at: index)
            } catch let error {
                DDLogError("ItemDertailStore: can't copy attachment - \(error)")
                errors += 1
            }
        }

        if errors > 0 {
            self.state.error = .fileNotCopied(errors)
        }
    }

    func addCreator() {
        // Check whether there already is an empty/new creator, add only if there is none
        guard self.state.data.creators.values.first(where: { $0.isEmpty }) == nil,
              let schema = self.schemaController.creators(for: self.state.data.type)?.first(where: { $0.primary }),
              let localized = self.schemaController.localized(creator: schema.creatorType) else { return }

        let creator = State.Creator(type: schema.creatorType, primary: schema.primary, localizedType: localized)
        self.state.data.creatorIds.append(creator.id)
        self.state.data.creators[creator.id] = creator
    }

    func deleteCreators(at offsets: IndexSet) {
        let keys = offsets.map({ self.state.data.creatorIds[$0] })
        self.state.data.creatorIds.remove(atOffsets: offsets)
        keys.forEach({ self.state.data.creators[$0] = nil })
    }

    func moveCreators(from offsets: IndexSet, to index: Int) {
        self.state.data.creatorIds.move(fromOffsets: offsets, toOffset: index)
    }

    func addNote() {
        self.state.presentedNote = State.Note(key: KeyGenerator.newKey, text: "")
    }

    func deleteNotes(at offsets: IndexSet) {
        self.state.data.notes.remove(atOffsets: offsets)
    }

    func saveNote() {
        let note = self.state.presentedNote
        if let index = self.state.data.notes.firstIndex(where: { $0.key == note.key }) {
            self.state.data.notes[index] = note
            // we edit notes outside of editing mode, so we need to save the change immediately
            self.saveNoteChanges(note)
        } else {
            self.state.data.notes.append(note)
        }
    }

    private func saveNoteChanges(_ note: State.Note) {
        do {
            let request = StoreNoteDbRequest(note: note, libraryId: self.state.libraryId)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("ItemDetailStore: can't store note - \(error)")
            self.state.error = .cantStoreChanges
        }
    }

    func setTags(_ tags: [Tag]) {
        self.state.data.tags = tags
    }

    func deleteTags(at offsets: IndexSet) {
        self.state.data.tags.remove(atOffsets: offsets)
    }

    func deleteAttachments(at offsets: IndexSet) {
        self.state.data.attachments.remove(atOffsets: offsets)
    }

    func openAttachment(_ attachment: State.Attachment) {
        switch attachment.type {
        case .url(let url):
            NotificationCenter.default.post(name: .presentWeb, object: url)
        case .file(let file, _, let isCached):
            if isCached {
                self.openFile(file)
            } else {
                self.cacheFile(file, key: attachment.key)
            }
        }
    }

    private func cacheFile(_ file: File, key: String) {
        let request = FileRequest(library: self.state.library, key: key, destination: file)
        self.apiClient.download(request: request)
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] progress in
                          let progress = progress.totalBytes == 0 ? 0 : Double(progress.bytesWritten) / Double(progress.totalBytes)
                          self?.state.downloadProgress[key] = progress
                      }, onError: { [weak self] error in
                          self?.finishCachingFile(for: key, result: .failure(error))
                      }, onCompleted: { [weak self] in
                          self?.finishCachingFile(for: key, result: .success(()))
                      })
                      .disposed(by: self.disposeBag)
    }

    private func finishCachingFile(for key: String, result: Result<(), Swift.Error>) {
        switch result {
        case .failure(let error):
            DDLogError("ItemDetailStore: show attachment - can't download file - \(error)")
            self.state.downloadError[key] = .downloadError

        case .success:
            self.state.downloadProgress[key] = nil
            if let (index, attachment) = self.state.data.attachments.enumerated().first(where: { $1.key == key }) {
                self.state.data.attachments[index] = attachment.changed(isLocal: true)
                self.openAttachment(attachment)
            }
        }
    }

    private func openFile(_ file: File) {
        switch file.ext {
        case "pdf":
            #if PDFENABLED
            NotificationCenter.default.post(name: .presentPdf, object: file.createUrl())
            #endif
        default:
            NotificationCenter.default.post(name: .presentUnknownAttachment, object: file.createUrl())
        }
    }

    func startEditing() {
        self.state.snapshot = self.state.data
    }

    func cancelChanges() {
        guard let snapshot = self.state.snapshot else { return }
        self.state.data = snapshot
        self.state.snapshot = nil
    }

    @discardableResult func saveChanges() -> Bool {
        let didChange = self.state.snapshot != self.state.data
        if didChange {
            self._saveChanges()
        }
        return didChange
    }

    private func _saveChanges() {
        // TODO: - move to background thread if possible
        // SWIFTUI BUG: - sync store with environment .editMode so that we can switch edit mode when background task finished

        var newType: State.DetailType?

        let originalModifiedDate = self.state.data.dateModified

        do {
            try self.fileStorage.copyAttachmentFilesIfNeeded(for: self.state.data.attachments)

            self.updateDateFieldIfNeeded()
            self.state.data.dateModified = Date()

            switch self.state.type {
            case .preview(let item):
                if let snapshot = self.state.snapshot {
                    try self.updateItem(key: item.key, libraryId: self.state.libraryId, data: self.state.data, snapshot: snapshot)
                }

            case .creation(_, let collectionKey, _), .duplication(_, let collectionKey):
                let item = try self.createItem(with: self.state.libraryId, collectionKey: collectionKey, data: self.state.data)
                newType = .preview(item)
            }

            self.state.snapshot = nil
            if let type = newType {
                self.state.type = type
            }
        } catch let error {
            DDLogError("ItemDetailStore: can't store changes - \(error)")
            self.state.data.dateModified = originalModifiedDate
            self.state.error = (error as? Error) ?? .cantStoreChanges
        }
    }

    private func updateDateFieldIfNeeded() {
        guard var field = self.state.data.fields.values.first(where: { $0.baseField == FieldKeys.date }) else { return }

        let date: Date?

        // TODO: - check for current localization
        switch field.value.lowercased() {
        case "tomorrow":
            date = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        case "today":
            date = Date()
        case "yesterday":
            date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        default:
            date = nil
        }

        if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            field.value = formatter.string(from: date)
            self.state.data.fields[field.key] = field
        }
    }

    private func createItem(with libraryId: LibraryIdentifier, collectionKey: String?, data: State.Data) throws -> RItem {
        let request = CreateItemDbRequest(libraryId: libraryId,
                                          collectionKey: collectionKey,
                                          data: data,
                                          schemaController: self.schemaController)
        return try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func updateItem(key: String, libraryId: LibraryIdentifier, data: State.Data, snapshot: State.Data) throws {
        let request = StoreItemDetailChangesDbRequest(libraryId: libraryId,
                                                      itemKey: key,
                                                      data: data,
                                                      snapshot: snapshot,
                                                      schemaController: self.schemaController)
        try self.dbStorage.createCoordinator().perform(request: request)
    }
}

extension FileStorage {
    /// Copy attachments from file picker url (external app sandboxes) to our internal url (our app sandbox)
    /// - parameter attachments: Attachments which will be copied if needed
    func copyAttachmentFilesIfNeeded(for attachments: [ItemDetailStore.State.Attachment]) throws {
        for attachment in attachments {
            switch attachment.type {
            case .url: continue
            case .file(let originalFile, _, _):
                let newFile = Files.objectFile(for: .item, libraryId: attachment.libraryId,
                                               key: attachment.key, ext: originalFile.ext)
                // Make sure that the file was not already moved to our internal location before
                guard originalFile.createUrl() != newFile.createUrl() else { continue }

                try self.copy(from: originalFile, to: newFile)
            }
        }
    }
}
