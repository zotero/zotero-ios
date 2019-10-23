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

extension Notification.Name {
    static let presentPdf = Notification.Name(rawValue: "org.zotero.PresentPdfAttachment")
    static let presentWeb = Notification.Name(rawValue: "org.zotero.PresentWebAttachment")
}

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
                self.title = item.title
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
                self.title = item.title
                self.text = item.fields.filter(Predicates.key(FieldKeys.note)).first?.value ?? ""
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
            var fields: [Field]
            var abstract: String?
            var notes: [Note]
            var attachments: [Attachment]
            var tags: [Tag]

            func allFields(schemaController: SchemaController) -> [Field] {
                var allFields = self.fields
                if let titleKey = schemaController.titleKey(for: self.type) {
                    allFields.append(State.Field(key: titleKey,
                                                 name: "",
                                                 value: self.title,
                                                 isTitle: true))
                }
                if let abstract = self.abstract {
                    allFields.append(State.Field(key: FieldKeys.abstract,
                                                 name: "",
                                                 value: abstract,
                                                 isTitle: false))
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
        var presentedNote: Note
        var metadataTitleMaxWidth: CGFloat

        var showTagPicker: Bool
        var unknownAttachment: URL?

        fileprivate var library: SyncController.Library {
            switch self.libraryId {
            case .custom(let type):
                return .user(self.userId, type)
            case .group(let id):
                return .group(id)
            }
        }

        init(userId: Int, type: DetailType, data: Data, error: Error? = nil) {
            self.userId = userId
            self.type = type
            self.data = data
            self.downloadProgress = [:]
            self.downloadError = [:]
            self.showTagPicker = false
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

        init(userId: Int, type: DetailType, error: Error) {
            self.init(userId: userId,
                      type: type,
                      data: Data(title: "", type: "",
                                 localizedType: "", creators: [],
                                 fields: [], abstract: nil, notes: [],
                                 attachments: [], tags: []),
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
            let data = try ItemDetailStore.createData(from: type,
                                                      schemaController: schemaController,
                                                      fileStorage: fileStorage)
            let userId = try dbStorage.createCoordinator().perform(request: ReadUserDbRequest()).identifier
            self.state = State(userId: userId, type: type, data: data)
        } catch let error {
            self.state = State(userId: 0,
                               type: type,
                               error: (error as? Error) ?? .typeNotSupported)
        }
    }

    static func createData(from type: State.DetailType,
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
            let fields = fieldKeys.compactMap({ key -> State.Field? in
                guard key != FieldKeys.abstract && key != titleKey else { return nil }
                let name = schemaController.localized(field: key) ?? ""
                return State.Field(key: key, name: name, value: "", isTitle: false)
            })

            return State.Data(title: "",
                              type: itemType,
                              localizedType: localizedType,
                              creators: [],
                              fields: fields,
                              abstract: (hasAbstract ? "" : nil),
                              notes: [],
                              attachments: [],
                              tags: [])

        case .preview(let item), .duplication(let item, _):
            guard let fieldKeys = schemaController.fields(for: item.rawType)?.map({ $0.field }),
                  let localizedType = schemaController.localized(itemType: item.rawType) else {
                throw Error.typeNotSupported
            }

            let titleKey = schemaController.titleKey(for: item.rawType) ?? ""
            var abstract: String?
            var values: [String: String] = [:]

            item.fields.forEach { field in
                switch field.key {
                case titleKey: break
                case FieldKeys.abstract:
                    abstract = field.value
                default:
                    values[field.key] = field.value
                }
            }

            let fields = fieldKeys.compactMap { key -> State.Field? in
                guard key != FieldKeys.abstract && key != titleKey else { return nil }
                let name = schemaController.localized(field: key) ?? ""
                let value = values[key] ?? ""
                return State.Field(key: key, name: name, value: value, isTitle: false)
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

    func addAttachments(from urls: [URL]) {
        let attachments = urls.map({ Files.file(from: $0) })
                              .map({
                                  State.Attachment(key: KeyGenerator.newKey,
                                                   title: $0.name,
                                                   type: .file(file: $0, filename: $0.name, isLocal: true),
                                                   libraryId: self.state.libraryId)
                              })
        attachments.forEach { attachment in
            let index = self.state.data.attachments.index(of: attachment, sortedBy: { $0.title.caseInsensitiveCompare($1.title) == .orderedAscending })
            self.state.data.attachments.insert(attachment, at: index)
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
            self.state.unknownAttachment = file.createUrl()
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

        self.copyAttachmentFilesIfNeeded(for: self.state.data.attachments)

        var newType: State.DetailType?

        do {
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
            self.state.error = (error as? Error) ?? .cantStoreChanges
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

    /// Copy attachments from file picker url (external app sandboxes) to our internal url (our app sandbox)
    /// - parameter attachments: Attachments which will be copied if needed
    private func copyAttachmentFilesIfNeeded(for attachments: [State.Attachment]) {
        for attachment in attachments {
            switch attachment.type {
            case .url: continue
            case .file(let originalFile, _, _):
                let newFile = Files.objectFile(for: .item, libraryId: attachment.libraryId,
                                               key: attachment.key, ext: originalFile.ext)
                // Make sure that the file was not already moved to our internal location before
                guard originalFile.createUrl() != newFile.createUrl() else { continue }

                // We can just "try?" to copy the file here, if it doesn't work the user will be notified during sync
                // process and can try to remove/re-add the attachment
                try? self.fileStorage.copy(from: originalFile, to: newFile)
            }
        }
    }
}
