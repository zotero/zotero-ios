//
//  ItemDetailActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

struct ItemDetailActionHandler: ViewModelActionHandler {
    typealias State = ItemDetailState
    typealias Action = ItemDetailAction

    private let apiClient: ApiClient
    private let fileStorage: FileStorage
    private let dbStorage: DbStorage
    private let schemaController: SchemaController
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, schemaController: SchemaController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.disposeBag = DisposeBag()
    }

    func process(action: ItemDetailAction, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch action {
        case .changeType(let type):
            self.changeType(to: type, in: viewModel)

        case .acceptPrompt:
            self.acceptPrompt(in: viewModel)

        case .cancelPrompt:
            self.update(viewModel: viewModel) { state in
                state.promptSnapshot = nil
            }

        case .addAttachments(let urls):
            self.addAttachments(from: urls, in: viewModel)

        case .deleteAttachments(let offsets):
            self.update(viewModel: viewModel) { state in
                state.data.attachments.remove(atOffsets: offsets)
                state.diff = .attachments(insertions: [], deletions: Array(offsets), reloads: [])
            }

        case .openAttachment(let attachment):
            self.openAttachment(attachment, in: viewModel)

        case .addCreator:
            self.addCreator(in: viewModel)

        case .deleteCreators(let offsets):
            self.deleteCreators(at: offsets, in: viewModel)

        case .moveCreators(let from, let to):
            self.update(viewModel: viewModel) { state in
                state.data.creatorIds.move(fromOffsets: from, toOffset: to)
            }

        case .deleteNotes(let offsets):
            self.update(viewModel: viewModel) { state in
                state.data.notes.remove(atOffsets: offsets)
                state.diff = .notes(insertions: [], deletions: Array(offsets), reloads: [])
            }

        case .saveNote(let key, let text):
            self.saveNote(key: key, text: text, in: viewModel)

        case .setTags(let tags):
            self.set(tags: tags, in: viewModel)

        case .deleteTags(let offsets):
            self.update(viewModel: viewModel) { state in
                state.data.tags.remove(atOffsets: offsets)
                state.diff = .tags(insertions: [], deletions: Array(offsets), reloads: [])
            }

        case .startEditing:
            self.startEditing(in: viewModel)

        case .cancelEditing:
            self.cancelChanges(in: viewModel)

        case .save:
            self.saveChanges(in: viewModel)

        case .setTitle(let title):
            self.update(viewModel: viewModel) { state in
                state.data.title = title
            }

        case .updateCreator(let id, let update):
            self.updateCreator(with: id, update: update, in: viewModel)

        case .setFieldValue(let id, let value):
            self.update(viewModel: viewModel) { state in
                state.data.fields[id]?.value = value
            }
        }
    }

    // MARK: - Type

    private func changeType(to newType: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        let data: ItemDetailState.Data
        do {
            data = try self.data(for: newType, from: viewModel.state.data)
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = (error as? ItemDetailError) ?? .typeNotSupported
            }
            return
        }

        let droppedFields = self.droppedFields(from: viewModel.state.data, to: data)
        self.update(viewModel: viewModel) { state in
            if droppedFields.isEmpty {
                state.data = data
                state.changes.insert(.type)
            } else {
                // Notify the user, that some fields with values will be dropped
                state.promptSnapshot = data
                state.error = .droppedFields(droppedFields)
            }
        }
    }

    private func droppedFields(from fromData: ItemDetailState.Data, to toData: ItemDetailState.Data) -> [String] {
        let newFieldNames = Set(toData.fields.values.map({ $0.name }))
        let oldFieldNames = Set(fromData.fields.values.filter({ !$0.value.isEmpty }).map({ $0.name }))
        return oldFieldNames.subtracting(newFieldNames).sorted()
    }

    private func data(for type: String, from originalData: ItemDetailState.Data) throws -> ItemDetailState.Data {
        guard let localizedType = self.schemaController.localized(itemType: type) else {
            throw ItemDetailError.typeNotSupported
        }

        let (fieldIds, fields, hasAbstract) = try ItemDetailDataCreator.fieldData(for: type,
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
        return data
    }

    private func creators(for type: String, from originalData: [UUID: ItemDetailState.Creator]) throws -> [UUID: ItemDetailState.Creator] {
        guard let schemas = self.schemaController.creators(for: type),
              let primary = schemas.first(where: { $0.primary }) else { throw ItemDetailError.typeNotSupported }

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

    private func acceptPrompt(in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            guard let snapshot = state.promptSnapshot else { return }
            state.data = snapshot
            state.changes.insert(.type)
            state.promptSnapshot = nil
        }
    }

    // MARK: - Creators

    private func addCreator(in viewModel: ViewModel<ItemDetailActionHandler>) {
        // Check whether there already is an empty/new creator, add only if there is none
        guard viewModel.state.data.creators.values.first(where: { $0.isEmpty }) == nil,
              let schema = self.schemaController.creators(for: viewModel.state.data.type)?.first(where: { $0.primary }),
              let localized = self.schemaController.localized(creator: schema.creatorType) else { return }

        let creator = State.Creator(type: schema.creatorType, primary: schema.primary, localizedType: localized)
        self.update(viewModel: viewModel) { state in
            state.diff = .creators(insertions: [state.data.creatorIds.count], deletions: [], reloads: [])
            state.data.creatorIds.append(creator.id)
            state.data.creators[creator.id] = creator
        }
    }

    private func deleteCreators(at offsets: IndexSet, in viewModel: ViewModel<ItemDetailActionHandler>) {
        let keys = offsets.map({ viewModel.state.data.creatorIds[$0] })
        self.update(viewModel: viewModel) { state in
            state.diff = .creators(insertions: [], deletions: Array(offsets), reloads: [])
            state.data.creatorIds.remove(atOffsets: offsets)
            keys.forEach({ state.data.creators[$0] = nil })
        }
    }

    private func updateCreator(with identifier: UUID, update: ItemDetailAction.CreatorUpdate, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            guard var creator = state.data.creators[identifier] else { return }
            var needsReload = false

            switch update {
            case .type(let value):
                creator.type = value
                creator.localizedType = self.schemaController.localized(creator: value) ?? ""
                needsReload = true
            case .firstName(let value):
                creator.firstName = value
            case .lastName(let value):
                creator.lastName = value
            case .fullName(let value):
                creator.fullName = value
            case .namePresentation(let value):
                creator.namePresentation = value
                needsReload = true
            }

            if needsReload, let index = state.data.creatorIds.firstIndex(of: identifier) {
                state.diff = .creators(insertions: [], deletions: [], reloads: [index])
            }

            state.data.creators[identifier] = creator
        }
    }

    // MARK: - Notes

    private func saveNote(key: String?, text: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            var note = key.flatMap({ key in state.data.notes.first(where: { $0.key == key }) }) ??
                       ItemDetailState.Note(key: KeyGenerator.newKey, text: "")
            note.text = text
            note.title = text.strippedHtml ?? ""

            if !state.isEditing {
                // Note was edited outside of editing mode, so it needs to be saved immediately
                do {
                    try self.saveNoteChanges(note, libraryId: state.libraryId)
                } catch let error {
                    DDLogError("ItemDetailStore: can't store note - \(error)")
                    state.error = .cantStoreChanges
                    return
                }
            }

            if let index = state.data.notes.firstIndex(where: { $0.key == note.key }) {
                state.data.notes[index] = note
                state.diff = .notes(insertions: [], deletions: [], reloads: [index])
            } else {
                state.diff = .notes(insertions: [state.data.notes.count], deletions: [], reloads: [])
                state.data.notes.append(note)
            }
        }
    }

    private func saveNoteChanges(_ note: ItemDetailState.Note, libraryId: LibraryIdentifier) throws {
        let request = StoreNoteDbRequest(note: note, libraryId: libraryId)
        try self.dbStorage.createCoordinator().perform(request: request)
    }

    // MARK: - Tags

    private func set(tags: [Tag], in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            let diff = tags.difference(from: state.data.tags).separated
            state.data.tags = tags
            state.diff = .tags(insertions: diff.insertions, deletions: diff.deletions, reloads: [])
        }
    }

    // MARK: - Attachments

    private func addAttachments(from urls: [URL], in viewModel: ViewModel<ItemDetailActionHandler>) {
        var attachments: [Attachment] = []
        var errors = 0

        for url in urls {
            let originalFile = Files.file(from: url)
            let key = KeyGenerator.newKey
            let file = Files.objectFile(for: .item,
                                        libraryId: viewModel.state.libraryId,
                                        key: key,
                                        ext: originalFile.ext)
            let attachment = Attachment(key: key,
                                        title: originalFile.name,
                                        type: .file(file: file, filename: originalFile.name, isLocal: true),
                                        libraryId: viewModel.state.libraryId)

            do {
                try self.fileStorage.move(from: originalFile, to: file)
                attachments.append(attachment)
            } catch let error {
                DDLogError("ItemDertailStore: can't copy attachment - \(error)")
                errors += 1
            }
        }

        if !attachments.isEmpty {
            self.update(viewModel: viewModel) { state in
                var insertions: [Int] = []
                attachments.forEach { attachment in
                    let index = state.data.attachments.index(of: attachment, sortedBy: { $0.title.caseInsensitiveCompare($1.title) == .orderedAscending })
                    state.data.attachments.insert(attachment, at: index)
                    insertions.append(index)
                }
                state.diff = .attachments(insertions: insertions, deletions: [], reloads: [])
                if errors > 0 {
                    state.error = .fileNotCopied(errors)
                }
            }
        } else if errors > 0 {
            self.update(viewModel: viewModel) { state in
                state.error = .fileNotCopied(errors)
            }
        }
    }

    private func openAttachment(_ attachment: Attachment, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch attachment.type {
        case .url(let url):
            NotificationCenter.default.post(name: .presentWeb, object: url)
        case .file(let file, _, let isCached):
            if isCached {
                self.openFile(file)
            } else {
                self.cacheFile(file, key: attachment.key, in: viewModel)
            }
        }
    }

    private func cacheFile(_ file: File, key: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        let request = FileRequest(data: .internal(viewModel.state.libraryId, viewModel.state.userId, key), destination: file)
        self.apiClient.download(request: request)
                      .flatMap { request in
                          return request.rx.progress()
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak viewModel] progress in
                          guard let viewModel = viewModel else { return }
                          let progress = progress.totalBytes == 0 ? 0 : Double(progress.bytesWritten) / Double(progress.totalBytes)
                          self.update(viewModel: viewModel) { state in
                              state.downloadProgress[key] = progress
                              state.changes.insert(.downloadProgress)
                          }
                      }, onError: { [weak viewModel] error in
                          guard let viewModel = viewModel else { return }
                          self.finishCachingFile(for: key, result: .failure(error), in: viewModel)
                      }, onCompleted: { [weak viewModel] in
                          guard let viewModel = viewModel else { return }
                          self.finishCachingFile(for: key, result: .success(()), in: viewModel)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func finishCachingFile(for key: String, result: Result<(), Swift.Error>, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch result {
        case .failure(let error):
            DDLogError("ItemDetailStore: show attachment - can't download file - \(error)")
            self.update(viewModel: viewModel) { state in
                state.downloadError[key] = .downloadError
                state.changes.insert(.downloadProgress)
            }

        case .success:
            self.update(viewModel: viewModel) { state in
                state.downloadProgress[key] = nil
                state.changes.insert(.downloadProgress)
                if let (index, attachment) = state.data.attachments.enumerated().first(where: { $1.key == key }) {
                    state.data.attachments[index] = attachment.changed(isLocal: true)
                    self.openAttachment(attachment, in: viewModel)
                }
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

    // MARK: - Editing

    private func startEditing(in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.snapshot = state.data
            state.data.fieldIds = ItemDetailDataCreator.allFieldKeys(for: state.data.type, schemaController: self.schemaController)
            state.isEditing = true
            state.changes.insert(.editing)
        }
    }

    func cancelChanges(in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard let snapshot = viewModel.state.snapshot else { return }
        self.update(viewModel: viewModel) { state in
            state.data = snapshot
            state.snapshot = nil
            state.isEditing = false
            state.changes.insert(.editing)
        }
    }

    func saveChanges(in viewModel: ViewModel<ItemDetailActionHandler>) {
        if viewModel.state.snapshot != viewModel.state.data {
            self._saveChanges(in: viewModel)
        }
    }

    private func _saveChanges(in viewModel: ViewModel<ItemDetailActionHandler>) {
        // TODO: - move to background thread if possible
        // SWIFTUI BUG: - sync store with environment .editMode so that we can switch edit mode when background task finished

        // TODO: - add loading indicator for saving

        self.save(state: viewModel.state)
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak viewModel] newState in
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state = newState
                }
            }, onError: { [weak viewModel] error in
                DDLogError("ItemDetailStore: can't store changes - \(error)")
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = (error as? ItemDetailError) ?? .cantStoreChanges
                }
            })
            .disposed(by: self.disposeBag)
    }

    private func save(state: ItemDetailState) -> Single<ItemDetailState> {
        return Single.create { subscriber -> Disposable in
            do {
                try self.fileStorage.copyAttachmentFilesIfNeeded(for: state.data.attachments)

                var newState = state
                var newType: State.DetailType?

                self.updateDateFieldIfNeeded(in: &newState)
                newState.data.dateModified = Date()

                switch state.type {
                case .preview(let item):
                    if let snapshot = state.snapshot {
                        try self.updateItem(key: item.key, libraryId: state.libraryId, data: state.data, snapshot: snapshot)
                    }

                case .creation(_, let collectionKey, _), .duplication(_, let collectionKey):
                    let item = try self.createItem(with: state.libraryId, collectionKey: collectionKey, data: state.data)
                    newType = .preview(item)
                }

                newState.snapshot = nil
                if let type = newType {
                    newState.type = type
                }
                newState.isEditing = false
                newState.changes.insert(.editing)
                newState.data.fieldIds = ItemDetailDataCreator.filteredFieldKeys(from: newState.data.fieldIds, fields: newState.data.fields)

                subscriber(.success(newState))
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        }
    }

    private func updateDateFieldIfNeeded(in state: inout State) {
        guard var field = state.data.fields.values.first(where: { $0.baseField == FieldKeys.date }) else { return }

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
            state.data.fields[field.key] = field
        }
    }

    private func createItem(with libraryId: LibraryIdentifier, collectionKey: String?, data: ItemDetailState.Data) throws -> RItem {
        let request = CreateItemDbRequest(libraryId: libraryId,
                                          collectionKey: collectionKey,
                                          data: data,
                                          schemaController: self.schemaController)
        return try self.dbStorage.createCoordinator().perform(request: request)
    }

    private func updateItem(key: String, libraryId: LibraryIdentifier, data: ItemDetailState.Data, snapshot: ItemDetailState.Data) throws {
        let request = StoreItemDetailChangesDbRequest(libraryId: libraryId,
                                                      itemKey: key,
                                                      data: data,
                                                      snapshot: snapshot,
                                                      schemaController: self.schemaController)
        try self.dbStorage.createCoordinator().perform(request: request)
    }
}
