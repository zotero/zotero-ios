//
//  ItemDetailStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class NewItemDetailStore: ObservableObject {
    enum StoreError: Error, Equatable {
        case typeNotSupported, libraryNotAssigned,
             contentTypeUnknown, userMissing, downloadError, unknown,
             cantStoreChanges
        case fileNotCopied(String)
    }

    struct StoreState {
        enum DetailType {
            case creation(libraryId: LibraryIdentifier, collectionKey: String?, filesEditable: Bool)
            case preview(RItem)

            var item: RItem? {
                switch self {
                case .preview(let item):
                    return item
                case .creation:
                    return nil
                }
            }
        }

        struct Field: Identifiable, Equatable {
            let key: String
            var name: String {
                didSet {
                    self.changed = true
                }
            }
            var value: String {
                didSet {
                    self.changed = true
                }
            }
            let isTitle: Bool
            var changed: Bool

            var id: String { return self.key }

            // TODO: - remove after swiftui refactoring
            func changed(value: String) -> Field {
                return Field(key: self.key, name: self.name, value: value, isTitle: self.isTitle, changed: true)
            }

            func changed(name: String) -> Field {
                return Field(key: self.key, name: name, value: self.value, isTitle: self.isTitle, changed: self.changed)
            }
        }

        struct Attachment: Identifiable, Equatable {
            enum ContentType: Equatable {
                case file(file: File, isCached: Bool)
                case url(URL)

                static func == (lhs: ContentType, rhs: ContentType) -> Bool {
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

            let key: String
            let title: String
            let filename: String
            let type: ContentType
            let libraryId: LibraryIdentifier
            let changed: Bool

            var id: String { return self.key }

            init(key: String, title: String,
                 filename: String, type: ContentType,
                 libraryId: LibraryIdentifier, changed: Bool) {
                self.key = key
                self.title = title
                self.filename = filename
                self.type = type
                self.libraryId = libraryId
                self.changed = changed
            }

            init?(item: RItem, type: ContentType) {
                guard let libraryId = item.libraryObject?.identifier else {
                    DDLogError("Attachment: library not assigned to item (\(item.key))")
                    return nil
                }

                self.libraryId = libraryId
                self.key = item.key
                self.title = item.title
                self.filename = item.fields.filter(Predicates.key(FieldKeys.filename)).first?.value ?? item.title
                self.type = type
                self.changed = false
            }

            func changed(isCached: Bool) -> Attachment {
                switch type {
                case .url: return self
                case .file(let file, _):
                    return Attachment(key: self.key, title: self.title, filename: self.filename,
                                      type: .file(file: file, isCached: isCached),
                                      libraryId: self.libraryId, changed: self.changed)
                }
            }
        }

        struct Note: Identifiable, Equatable {
            let key: String
            let title: String
            let text: String
            let changed: Bool

            var id: String { return self.key }

            init(key: String, text: String, changed: Bool = true) {
                self.key = key
                self.title = text.strippedHtml ?? text
                self.text = text
                self.changed = changed
            }

            init?(item: RItem) {
                guard item.rawType == ItemTypes.note else {
                    DDLogError("Trying to create Note from RItem which is not a note!")
                    return nil
                }

                self.key = item.key
                self.title = item.title
                self.text = item.fields.filter(Predicates.key(FieldKeys.note)).first?.value ?? ""
                self.changed = false
            }
        }

        struct Creator: Identifiable, Equatable {
            enum NamePresentation: Equatable {
                case separate, full

                mutating func toggle() {
                    self = self == .full ? .separate : .full
                }
            }

            let type: String
            let localizedType: String
            var fullName: String
            var firstName: String
            var lastName: String
            var namePresentation: NamePresentation

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

            var id: UUID { return UUID() }

            init(firstName: String, lastName: String, fullName: String, type: String, localizedType: String) {
                self.type = type
                self.localizedType = localizedType
                self.fullName = fullName
                self.firstName = firstName
                self.lastName = lastName
                self.namePresentation = fullName.isEmpty ? .separate : .full
            }

            init(type: String, localizedType: String) {
                self.type = type
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
            var creators: [Creator]
            var fields: [String: Field]
            var visibleFields: [String]
            var abstract: String?
            var notes: [Note]
            var attachments: [Attachment]
            var tags: [Tag]

            fileprivate func allFields(schemaController: SchemaController) -> [Field] {
                var allFields = Array(self.fields.values)
                if let titleKey = schemaController.titleKey(for: self.type) {
                    allFields.append(StoreState.Field(key: titleKey,
                                                      name: "",
                                                      value: self.title,
                                                      isTitle: true,
                                                      changed: !self.title.isEmpty))
                }
                if let abstract = self.abstract {
                    allFields.append(StoreState.Field(key: FieldKeys.abstract,
                                                      name: "",
                                                      value: abstract,
                                                      isTitle: false,
                                                      changed: !abstract.isEmpty))
                }
                return allFields
            }
        }

        let userId: Int
        let libraryId: LibraryIdentifier
        let metadataEditable: Bool
        let filesEditable: Bool

        var type: DetailType
        var data: Data
        var snapshot: Data?
        var error: StoreError?
        var presentedNote: Note?
        var showTagPicker: Bool

        init(userId: Int, libraryId: LibraryIdentifier, type: DetailType, data: Data) {
            self.userId = userId
            self.libraryId = libraryId
            self.type = type
            self.data = data
            self.showTagPicker = false

            switch type {
            case .preview(let item):
                // Item has either grouop assigned with canEditMetadata or it's a custom library which is always editable
                self.metadataEditable = item.group?.canEditMetadata ?? true
                // Item has either grouop assigned with canEditFiles or it's a custom library which is always editable
                self.filesEditable = item.group?.canEditFiles ?? true
            case .creation(_, _, let filesEditable):
                // Since we're in creation mode editing must have beeen enabled
                self.metadataEditable = true
                self.filesEditable = filesEditable
            }
        }
    }

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let schemaController: SchemaController
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher

    var state: StoreState {
        willSet {
            self.objectWillChange.send()
        }
    }

    init(type: StoreState.DetailType, userId: Int, libraryId: LibraryIdentifier,
         apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) throws {
        let data = try NewItemDetailStore.createData(from: type,
                                                     schemaController: schemaController,
                                                     fileStorage: fileStorage)
        self.state = StoreState(userId: userId, libraryId: libraryId, type: type, data: data)
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.objectWillChange = ObservableObjectPublisher()
    }

    private static func createData(from type: StoreState.DetailType,
                                   schemaController: SchemaController,
                                   fileStorage: FileStorage) throws -> StoreState.Data {
        switch type {
        case .creation:
            guard let itemType = schemaController.itemTypes.sorted().first,
                  let fieldKeys = schemaController.fields(for: itemType)?.map({ $0.field }),
                  let localizedType = schemaController.localized(itemType: itemType) else {
                throw StoreError.typeNotSupported
            }

            // Creation has editing enabled by default, so we'll see all available fields

            let hasAbstract = fieldKeys.contains(where: { $0 == FieldKeys.abstract })
            let titleKey = schemaController.titleKey(for: itemType)
            var fields: [String: StoreState.Field] = [:]
            for key in fieldKeys {
                guard key != FieldKeys.abstract && key != titleKey else { continue }
                let name = schemaController.localized(field: key) ?? ""
                fields[key] = StoreState.Field(key: key, name: name, value: "", isTitle: false, changed: false)
            }

            return StoreState.Data(title: "",
                                   type: itemType,
                                   localizedType: localizedType,
                                   creators: [],
                                   fields: fields,
                                   visibleFields: fieldKeys,
                                   abstract: (hasAbstract ? "" : nil),
                                   notes: [],
                                   attachments: [],
                                   tags: [])

        case .preview(let item):
            guard let fieldKeys = schemaController.fields(for: item.rawType)?.map({ $0.field }),
                  let localizedType = schemaController.localized(itemType: item.rawType) else {
                throw StoreError.typeNotSupported
            }

            let titleKey = schemaController.titleKey(for: item.rawType) ?? ""
            var abstract: String?
            var fieldValues: [String: String] = [:]

            item.fields.forEach { field in
                switch field.key {
                case titleKey: break
                case FieldKeys.abstract:
                    abstract = field.value
                default:
                    fieldValues[field.key] = field.value
                }
            }

            // Preview has editing disabled by default, so we'll see only fields with some filled-in values
            var visibleFields: [String] = fieldKeys
            var fields: [String: StoreState.Field] = [:]

            for key in fieldKeys {
                let value = fieldValues[key] ?? ""
                if value.isEmpty {
                    if let index = visibleFields.firstIndex(of: key) {
                        visibleFields.remove(at: index)
                    }
                }

                guard key != titleKey && key != FieldKeys.abstract else { continue }

                let name = schemaController.localized(field: key) ?? ""
                fields[key] = StoreState.Field(key: key, name: name, value: value, isTitle: false, changed: false)
            }

            let creators = item.creators.sorted(byKeyPath: "orderId").compactMap { creator -> StoreState.Creator? in
                guard let localizedType = schemaController.localized(creator: creator.rawType) else { return nil }
                return StoreState.Creator(firstName: creator.firstName, lastName: creator.lastName,
                                          fullName: creator.name, type: creator.rawType, localizedType: localizedType)
            }
            let notes = item.children.filter(Predicates.items(type: ItemTypes.note, notSyncState: .dirty, trash: false))
                                     .sorted(byKeyPath: "title")
                                     .compactMap(StoreState.Note.init)
            let attachments = item.children.filter(Predicates.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                           .sorted(byKeyPath: "title")
                                           .compactMap({ item -> StoreState.Attachment? in
                                               return attachmentType(for: item, fileStorage: fileStorage).flatMap({ StoreState.Attachment(item: item, type: $0) })
                                           })
            let tags = item.tags.sorted(byKeyPath: "name").map(Tag.init)

            return StoreState.Data(title: item.title,
                                   type: item.rawType,
                                   localizedType: localizedType,
                                   creators: Array(creators),
                                   fields: fields,
                                   visibleFields: visibleFields,
                                   abstract: abstract,
                                   notes: Array(notes),
                                   attachments: Array(attachments),
                                   tags: Array(tags))
        }
    }

    private static func attachmentType(for item: RItem, fileStorage: FileStorage) -> StoreState.Attachment.ContentType? {
        let contentType = item.fields.filter(Predicates.key(FieldKeys.contentType)).first?.value ?? ""
        if !contentType.isEmpty { // File attachment
            if let ext = contentType.extensionFromMimeType,
               let libraryId = item.libraryObject?.identifier {
                let file = Files.objectFile(for: .item, libraryId: libraryId, key: item.key, ext: ext)
                let isCached = fileStorage.has(file)
                return .file(file: file, isCached: isCached)
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

    func addCreator() {
        // Check whether there already is an empty/new creator, add only if there is none
        guard self.state.data.creators.reversed().first(where: { $0.isEmpty }) == nil,
              let schema = self.schemaController.creators(for: self.state.data.type)?.first(where: { $0.primary }),
              let localized = self.schemaController.localized(creator: schema.creatorType) else { return }
        self.state.data.creators.append(.init(type: schema.creatorType, localizedType: localized))
    }

    func deleteCreators(at offsets: IndexSet) {
        self.state.data.creators.remove(atOffsets: offsets)
    }

    func moveCreators(from offsets: IndexSet, to index: Int) {
        self.state.data.creators.move(fromOffsets: offsets, toOffset: index)
    }

    func addNote() {
        self.state.presentedNote = StoreState.Note(key: KeyGenerator.newKey, text: "")
    }

    func deleteNotes(at offsets: IndexSet) {
        self.state.data.notes.remove(atOffsets: offsets)
    }

    func editNote(_ note: StoreState.Note) {
        self.state.presentedNote = note
    }

    func saveNote() {
        guard let note = self.state.presentedNote else { return }
        if let index = self.state.data.notes.firstIndex(where: { $0.key == note.key }) {
            self.state.data.notes[index] = note
        } else {
            self.state.data.notes.append(note)
        }
        self.state.presentedNote = nil
    }

    func deleteTags(at offsets: IndexSet) {
        self.state.data.tags.remove(atOffsets: offsets)
    }

    func startEditing() {
        self.state.snapshot = state.data
        // We need to change visibleFields from fields that only have some filled-in content to all fields
        self.state.data.visibleFields = self.schemaController.fields(for: state.data.type)?.map({ $0.field }) ?? []
    }

    func cancelChanges() {
        guard let snapshot = self.state.snapshot else { return }
        self.state.data = snapshot
        self.state.snapshot = nil
    }

    func saveChanges() {
        if self.state.snapshot != self.state.data {
            self._saveChanges()
        } else {
            self.state.snapshot = nil
        }
    }

    private func _saveChanges() {
        // TODO: - move to background thread if possible
        // SWIFTUI BUG: - sync store with environmentt .editMode so that we can switch edit mode when background task finished

        self.copyAttachmentFilesIfNeeded(for: self.state.data.attachments)

        var newType: StoreState.DetailType?

        do {
            switch self.state.type {
            case .preview(let item):
                guard let libraryId = item.libraryId else {
                    self.state.error = .libraryNotAssigned
                    return
                }
                try self.updateItem(key: item.key, libraryId: libraryId, data: self.state.data)

            case .creation(let libraryId, let collectionKey, _):
                let item = try self.createItem(with: libraryId, collectionKey: collectionKey, data: self.state.data)
                newType = .preview(item)
            }

            let titleKey = self.schemaController.titleKey(for: self.state.data.type) ?? ""
            let fieldKeys = self.schemaController.fields(for: self.state.data.type)?.map { $0.field } ?? []
            self.state.snapshot = nil
            self.state.data.visibleFields = self.nonEmptyFieldKeys(for: state.data.fields, titleKey: titleKey, allFieldKeys: fieldKeys)
            if let type = newType {
                self.state.type = type
            }
        } catch let error {
            DDLogError("ItemDetailStore: can't store changes - \(error)")
            self.state.error = (error as? StoreError) ?? .cantStoreChanges
        }
    }

    private func nonEmptyFieldKeys(for fields: [String: StoreState.Field], titleKey: String, allFieldKeys: [String]) -> [String] {
        var visibleKeys = allFieldKeys
        for key in allFieldKeys {
            let value = fields[key]?.value ?? ""
            if value.isEmpty, let index = visibleKeys.firstIndex(of: key) {
                visibleKeys.remove(at: index)
            }
        }
        return visibleKeys
    }

    private func createItem(with libraryId: LibraryIdentifier, collectionKey: String?, data: StoreState.Data) throws -> RItem {
        let request = CreateItemDbRequest(libraryId: libraryId,
                                          collectionKey: collectionKey,
                                          type: data.type,
                                          fields: data.allFields(schemaController: self.schemaController),
                                          notes: data.notes,
                                          attachments: data.attachments,
                                          tags: data.tags)
        return try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func updateItem(key: String, libraryId: LibraryIdentifier, data: StoreState.Data) throws {
        let request = StoreItemDetailChangesDbRequest(libraryId: libraryId,
                                                      itemKey: key,
                                                      type: data.type,
                                                      fields: data.allFields(schemaController: self.schemaController),
                                                      notes: data.notes,
                                                      attachments: data.attachments,
                                                      tags: data.tags)
        try self.dbStorage.createCoordinator().perform(request: request)
    }

    /// Copy attachments from file picker url (external app sandboxes) to our internal url (our app sandbox)
    /// - parameter attachments: Attachments which will be copied if needed
    private func copyAttachmentFilesIfNeeded(for attachments: [StoreState.Attachment]) {
        for attachment in attachments {
            guard attachment.changed else { continue }

            switch attachment.type {
            case .url: continue
            case .file(let originalFile, _):
                let newFile = Files.objectFile(for: .item, libraryId: attachment.libraryId,
                                               key: attachment.key, ext: originalFile.ext)
                // Make sure that the file was not already moved to our internal location before
                guard originalFile.createUrl() != newFile.createUrl() else { continue }

                // We can just try to copy the file here, if it doesn't work the user will be notified during sync
                // process and can try to remove/re-add the attachment
                try? self.fileStorage.copy(from: originalFile, to: newFile)
            }
        }
    }
}
