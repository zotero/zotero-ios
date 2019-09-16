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

class ItemDetailStore: ObservableObject {
    enum Error: Swift.Error, Equatable {
        case typeNotSupported, libraryNotAssigned,
             contentTypeUnknown, userMissing, downloadError, unknown,
             cantStoreChanges
        case fileNotCopied(String)
    }

    struct State {
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
            let changed: Bool

            var id: String { return self.key }

            init(key: String, title: String, type: ContentType,
                 libraryId: LibraryIdentifier, changed: Bool) {
                self.key = key
                self.title = title
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
                self.type = type
                self.changed = false
            }

            func changed(isLocal: Bool) -> Attachment {
                switch type {
                case .url: return self
                case .file(let file, let filename, _):
                    return Attachment(key: self.key, title: self.title,
                                      type: .file(file: file, filename: filename, isLocal: isLocal),
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
                    allFields.append(State.Field(key: titleKey,
                                                      name: "",
                                                      value: self.title,
                                                      isTitle: true,
                                                      changed: !self.title.isEmpty))
                }
                if let abstract = self.abstract {
                    allFields.append(State.Field(key: FieldKeys.abstract,
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
        var downloadProgress: [String: Double]
        var downloadError: [String: ItemDetailStore.Error]
        var error: Error?
        var presentedNote: Note?

        var showTagPicker: Bool
        var webAttachment: URL?
        var pdfAttachment: URL?
        var unknownAttachment: URL?

        var isAnyAttachmentOpened: Bool {
            return self.webAttachment != nil || self.pdfAttachment != nil || self.unknownAttachment != nil
        }

        fileprivate var library: SyncController.Library {
            switch self.libraryId {
            case .custom(let type):
                return .user(self.userId, type)
            case .group(let id):
                return .group(id)
            }
        }

        init(userId: Int, libraryId: LibraryIdentifier, type: DetailType, data: Data, error: Error? = nil) {
            self.userId = userId
            self.libraryId = libraryId
            self.type = type
            self.data = data
            self.downloadProgress = [:]
            self.downloadError = [:]
            self.showTagPicker = false
            self.error = error

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

        init(userId: Int, libraryId: LibraryIdentifier, type: DetailType, error: Error) {
            self.init(userId: userId,
                      libraryId: libraryId,
                      type: type,
                      data: Data(title: "", type: "",
                                 localizedType: "", creators: [],
                                 fields: [:], visibleFields: [],
                                 abstract: nil, notes: [],
                                 attachments: [], tags: []),
                      error: error)
        }
    }

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let schemaController: SchemaController
    private let disposeBag: DisposeBag
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }

    init(type: State.DetailType, libraryId: LibraryIdentifier,
         apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
        self.objectWillChange = ObservableObjectPublisher()

        do {
            let data = try ItemDetailStore.createData(from: type,
                                                      schemaController: schemaController,
                                                      fileStorage: fileStorage)
            let userId = try dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
            self.state = State(userId: userId, libraryId: libraryId, type: type, data: data)
        } catch let error {
            self.state = State(userId: 0,
                               libraryId: libraryId,
                               type: type,
                               error: (error as? Error) ?? .typeNotSupported)
        }
    }

    private static func createData(from type: State.DetailType,
                                   schemaController: SchemaController,
                                   fileStorage: FileStorage) throws -> State.Data {
        switch type {
        case .creation:
            guard let itemType = schemaController.itemTypes.sorted().first,
                  let fieldKeys = schemaController.fields(for: itemType)?.map({ $0.field }),
                  let localizedType = schemaController.localized(itemType: itemType) else {
                throw Error.typeNotSupported
            }

            // Creation has editing enabled by default, so we'll see all available fields

            let hasAbstract = fieldKeys.contains(where: { $0 == FieldKeys.abstract })
            let titleKey = schemaController.titleKey(for: itemType)
            var fields: [String: State.Field] = [:]
            for key in fieldKeys {
                guard key != FieldKeys.abstract && key != titleKey else { continue }
                let name = schemaController.localized(field: key) ?? ""
                fields[key] = State.Field(key: key, name: name, value: "", isTitle: false, changed: false)
            }

            return State.Data(title: "",
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
                throw Error.typeNotSupported
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
            var fields: [String: State.Field] = [:]

            for key in fieldKeys {
                let value = fieldValues[key] ?? ""
                if value.isEmpty {
                    if let index = visibleFields.firstIndex(of: key) {
                        visibleFields.remove(at: index)
                    }
                }

                guard key != titleKey && key != FieldKeys.abstract else { continue }

                let name = schemaController.localized(field: key) ?? ""
                fields[key] = State.Field(key: key, name: name, value: value, isTitle: false, changed: false)
            }

            let creators = item.creators.sorted(byKeyPath: "orderId").compactMap { creator -> State.Creator? in
                guard let localizedType = schemaController.localized(creator: creator.rawType) else { return nil }
                return State.Creator(firstName: creator.firstName, lastName: creator.lastName,
                                          fullName: creator.name, type: creator.rawType, localizedType: localizedType)
            }
            let notes = item.children.filter(Predicates.items(type: ItemTypes.note, notSyncState: .dirty, trash: false))
                                     .sorted(byKeyPath: "title")
                                     .compactMap(State.Note.init)
            let attachments = item.children.filter(Predicates.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                           .sorted(byKeyPath: "title")
                                           .compactMap({ item -> State.Attachment? in
                                               return attachmentType(for: item, fileStorage: fileStorage).flatMap({ State.Attachment(item: item, type: $0) })
                                           })
            let tags = item.tags.sorted(byKeyPath: "name").map(Tag.init)

            return State.Data(title: item.title,
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

    private static func attachmentType(for item: RItem, fileStorage: FileStorage) -> State.Attachment.ContentType? {
        let contentType = item.fields.filter(Predicates.key(FieldKeys.contentType)).first?.value ?? ""
        if !contentType.isEmpty { // File attachment
            if let ext = contentType.extensionFromMimeType,
               let libraryId = item.libraryObject?.identifier {
                let filename = item.fields.filter(Predicates.key(FieldKeys.filename)).first?.value ?? (item.title + "." + ext)
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
        self.state.presentedNote = State.Note(key: KeyGenerator.newKey, text: "")
    }

    func deleteNotes(at offsets: IndexSet) {
        self.state.data.notes.remove(atOffsets: offsets)
    }

    func editNote(_ note: State.Note) {
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

    func setTags(_ tags: [Tag]) {
        self.state.data.tags = tags
        self.state.showTagPicker = false
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
            self.state.webAttachment = url
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
                if !self.state.isAnyAttachmentOpened {
                    self.openAttachment(attachment)
                }
            }
        }
    }

    private func openFile(_ file: File) {
        switch file.ext {
        case "pdf":
            #if PDFENABLED
            self.state.pdfAttachment = file.createUrl()
            #endif
        default:
            self.state.unknownAttachment = file.createUrl()
        }
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

        var newType: State.DetailType?

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
            self.state.error = (error as? Error) ?? .cantStoreChanges
        }
    }

    private func nonEmptyFieldKeys(for fields: [String: State.Field], titleKey: String, allFieldKeys: [String]) -> [String] {
        var visibleKeys = allFieldKeys
        for key in allFieldKeys {
            let value = fields[key]?.value ?? ""
            if value.isEmpty, let index = visibleKeys.firstIndex(of: key) {
                visibleKeys.remove(at: index)
            }
        }
        return visibleKeys
    }

    private func createItem(with libraryId: LibraryIdentifier, collectionKey: String?, data: State.Data) throws -> RItem {
        let request = CreateItemDbRequest(libraryId: libraryId,
                                          collectionKey: collectionKey,
                                          type: data.type,
                                          fields: data.allFields(schemaController: self.schemaController),
                                          notes: data.notes,
                                          attachments: data.attachments,
                                          tags: data.tags)
        return try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func updateItem(key: String, libraryId: LibraryIdentifier, data: State.Data) throws {
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
    private func copyAttachmentFilesIfNeeded(for attachments: [State.Attachment]) {
        for attachment in attachments {
            guard attachment.changed else { continue }

            switch attachment.type {
            case .url: continue
            case .file(let originalFile, _, _):
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
