//
//  ItemDetailActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RealmSwift
import RxSwift
import ZIPFoundation

struct ItemDetailActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias State = ItemDetailState
    typealias Action = ItemDetailAction

    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    unowned let dbStorage: DbStorage
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let urlDetector: UrlDetector
    private unowned let fileDownloader: AttachmentDownloader
    private unowned let fileCleanupController: AttachmentFileCleanupController
    let backgroundQueue: DispatchQueue
    private let backgroundScheduler: SerialDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(
        apiClient: ApiClient,
        fileStorage: FileStorage,
        dbStorage: DbStorage,
        schemaController: SchemaController,
        dateParser: DateParser,
        urlDetector: UrlDetector,
        fileDownloader: AttachmentDownloader,
        fileCleanupController: AttachmentFileCleanupController
    ) {
        let queue = DispatchQueue(label: "org.zotero.ItemDetailActionHandler.background", qos: .userInitiated)
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.urlDetector = urlDetector
        self.fileDownloader = fileDownloader
        self.fileCleanupController = fileCleanupController
        self.backgroundQueue = queue
        self.backgroundScheduler = SerialDispatchQueueScheduler(queue: queue, internalSerialQueueName: "org.zotero.ItemDetailActionHandler.backgroundScheduler")
        self.disposeBag = DisposeBag()
    }

    func process(action: ItemDetailAction, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch action {
        case .loadInitialData:
            self.loadInitialData(in: viewModel)

        case .reloadData:
            self.reloadData(isEditing: viewModel.state.isEditing, library: viewModel.state.library, in: viewModel)

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

        case .openAttachment(let key):
            self.openAttachment(with: key, in: viewModel)

        case .attachmentOpened(let key):
            guard viewModel.state.attachmentToOpen == key else { return }
            self.update(viewModel: viewModel) { state in
                state.attachmentToOpen = nil
            }

        case .saveCreator(let creator):
            self.save(creator: creator, in: viewModel)

        case .deleteCreator(let id):
            self.deleteCreator(with: id, in: viewModel)

        case .moveCreators(let diff):
            self.moveCreators(diff: diff, in: viewModel)

        case .processNoteSaveResult(let key, let result):
            self.processNoteSaveResult(key: key, result: result, in: viewModel)

        case .setTags(let tags):
            self.set(tags: tags, in: viewModel)

        case .startEditing:
            self.startEditing(in: viewModel)

        case .cancelEditing:
            self.cancelChanges(in: viewModel)

        case .endEditing:
            self.endEditing(in: viewModel)

        case .setTitle(let title):
            self.set(title: title, in: viewModel)

        case .setAbstract(let abstract):
            self.set(abstract: abstract, in: viewModel)

        case .setFieldValue(let id, let value):
            self.setField(value: value, for: id, in: viewModel)

        case .updateDownload(let update):
            self.process(downloadUpdate: update, in: viewModel)

        case .updateAttachments(let notification):
            self.updateDeletedAttachmentFiles(notification, in: viewModel)

        case .deleteAttachmentFile(let attachment):
            self.deleteFile(of: attachment, in: viewModel)

        case .toggleAbstractDetailCollapsed:
            self.update(viewModel: viewModel) { state in
                state.abstractCollapsed = !state.abstractCollapsed
                state.reload = .section(.abstract)
            }

        case .deleteTag(let tag):
            self.delete(tag: tag, in: viewModel)

        case .deleteNote(let note):
            self.delete(note: note, in: viewModel)

        case .deleteAttachment(let attachment):
            self.delete(attachment: attachment, in: viewModel)

        case .clearPreScrolledItemKey:
            self.update(viewModel: viewModel) { state in
                state.preScrolledChildKey = nil
            }

        case .moveAttachmentToStandalone(let attachment):
            self.moveToStandalone(attachment: attachment, in: viewModel)
        }
    }

    private func loadInitialData(in viewModel: ViewModel<ItemDetailActionHandler>) {
        let library: Library
        var collectionKey: String?
        var data: (data: ItemDetailState.Data, attachments: [Attachment], notes: [Note], tags: [Tag])

        do {
            let libraryToken: NotificationToken?
            (library, libraryToken) = try viewModel.state.library.identifier.observe(in: dbStorage, changes: { [weak viewModel] library in
                guard let viewModel else { return }
                reloadData(isEditing: viewModel.state.isEditing, library: library, in: viewModel)
            })

            update(viewModel: viewModel) { state in
                state.libraryToken = libraryToken
            }

            switch viewModel.state.type {
            case .creation(let itemType, let child, let _collectionKey):
                collectionKey = _collectionKey
                data = try ItemDetailDataCreator.createData(
                    from: .new(itemType: itemType, child: child),
                    schemaController: self.schemaController,
                    dateParser: self.dateParser,
                    fileStorage: self.fileStorage,
                    urlDetector: self.urlDetector,
                    doiDetector: FieldKeys.Item.isDoi
                )

            case .duplication(let itemKey, let _collectionKey):
                collectionKey = _collectionKey
                let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: library.identifier, key: itemKey), on: .main)
                data = try ItemDetailDataCreator.createData(
                    from: .existing(item: item, ignoreChildren: true),
                    schemaController: self.schemaController,
                    dateParser: self.dateParser,
                    fileStorage: self.fileStorage,
                    urlDetector: self.urlDetector,
                    doiDetector: FieldKeys.Item.isDoi
                )

            case .preview:
                self.reloadData(isEditing: viewModel.state.isEditing, library: library, in: viewModel)
                return
            }
        } catch let error {
            DDLogError("ItemDetailActionHandler: can't load initial data - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .cantCreateData
            }
            return
        }

        let request = CreateItemFromDetailDbRequest(
            key: viewModel.state.key,
            libraryId: library.identifier,
            collectionKey: collectionKey,
            data: data.data,
            attachments: data.attachments,
            notes: data.notes,
            tags: data.tags,
            schemaController: self.schemaController,
            dateParser: self.dateParser
        )

        self.perform(request: request, invalidateRealm: true) { [weak viewModel] result in
            guard let viewModel else { return }

            switch result {
            case .success:
                self.reloadData(isEditing: true, library: library, in: viewModel)

            case .failure(let error):
                DDLogError("ItemDetailActionHandler: can't create initial item - \(error)")
                self.update(viewModel: viewModel) { state in
                    state.error = .cantCreateData
                }
            }
        }
    }

    private func reloadData(isEditing: Bool, library: Library, in viewModel: ViewModel<ItemDetailActionHandler>) {
        do {
            let canEdit = isEditing && library.metadataEditable
            let item = try self.dbStorage.perform(request: ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: viewModel.state.key), on: .main, refreshRealm: true)

            let token = item.observe(keyPaths: RItem.observableKeypathsForItemDetail) { [weak viewModel] change in
                guard let viewModel = viewModel else { return }
                self.itemChanged(change, in: viewModel)
            }

            var (data, attachments, notes, tags) = try ItemDetailDataCreator.createData(
                from: .existing(item: item, ignoreChildren: false),
                schemaController: self.schemaController,
                dateParser: self.dateParser,
                fileStorage: self.fileStorage,
                urlDetector: self.urlDetector,
                doiDetector: FieldKeys.Item.isDoi
            )

            if !canEdit {
                data.fieldIds = ItemDetailDataCreator.filteredFieldKeys(from: data.fieldIds, fields: data.fields)
            }

            self.saveReloaded(data: data, attachments: attachments, notes: notes, tags: tags, isEditing: canEdit, library: library, token: token, in: viewModel)
        } catch let error {
            DDLogError("ItemDetailActionHandler: can't load data - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .cantCreateData
            }
        }
    }

    private func saveReloaded(
        data: ItemDetailState.Data,
        attachments: [Attachment],
        notes: [Note],
        tags: [Tag],
        isEditing: Bool,
        library: Library,
        token: NotificationToken,
        in viewModel: ViewModel<ItemDetailActionHandler>
    ) {
        self.update(viewModel: viewModel) { state in
            state.data = data
            if state.snapshot != nil || isEditing {
                state.snapshot = data
                state.snapshot?.fieldIds = ItemDetailDataCreator.filteredFieldKeys(from: data.fieldIds, fields: data.fields)
            }
            state.attachments = attachments
            state.notes = notes
            state.tags = tags
            state.library = library
            state.isLoadingData = false
            state.isEditing = isEditing
            state.observationToken = token
            state.changes.insert(.reloadedData)
        }
    }

    private func itemChanged(_ change: ObjectChange<ObjectBase>, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch change {
        case .change(_, let changes):
            guard self.shouldReloadData(for: changes) else { return }
            self.update(viewModel: viewModel) { state in
                state.changes = .item
            }

        // Deletion is handled by sync process, so we don't need to kick the user out here (the sync should always ask whether the user wants to delete the item or not).
        case .deleted, .error: break
        }
    }

    private func shouldReloadData(for changes: [PropertyChange]) -> Bool {
        if let versionChange = changes.first(where: { $0.name == "version" }), let oldValue = versionChange.oldValue as? Int, let newValue = versionChange.newValue as? Int {
            // If `version` has been changed, the item has been updated. Check whether it was sync change.
            if oldValue != newValue, let changeType = changes.first(where: { $0.name == "changeType" })?.oldValue as? Int, changeType != UpdatableChangeType.user.rawValue {
                return true
            }
            // Otherwise this was user change and backend only updated version based on user change.
            return false
        }

        if changes.contains(where: { $0.name == "children" }) {
            // Realm has an issue when reporting changes in children for `LinkingObjects`. The `oldValue` and `newValue` point to the same `LinkingObjects`, so we can't distinguish whether this was
            // user or sync change. To mitigate this, when updating child items version after successful backend submission, the `parent.version` is also updated. So this change is ignored by above
            // condition and other `children` changes are always made by backend.
            return true
        }

        return false
    }

    private func trashItem(key: String, reloadType: ItemDetailState.TableViewReloadType, in viewModel: ViewModel<ItemDetailActionHandler>, updateState: @escaping (inout ItemDetailState) -> Void) {
        self.update(viewModel: viewModel) { state in
            state.backgroundProcessedItems.insert(key)
            state.reload = reloadType
        }

        let request = MarkItemsAsTrashedDbRequest(keys: [key], libraryId: viewModel.state.library.identifier, trashed: true)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }

            self.update(viewModel: viewModel) { state in
                state.backgroundProcessedItems.remove(key)
                state.reload = reloadType

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't trash item \(key) - \(error)")
                    state.error = .cantTrashItem
                } else {
                    updateState(&state)
                }
            }
        }
    }

    // MARK: - Notes

    private func processNoteSaveResult(key: String?, result: NoteEditorSaveResult, in viewModel: ViewModel<ItemDetailActionHandler>) {
        var oldIndex: Int?
        var oldNote: Note?
        if let key {
            oldIndex = viewModel.state.notes.firstIndex(where: { $0.key == key })
            if let oldIndex {
                oldNote = viewModel.state.notes[oldIndex]
            }
        }
        switch result {
        case .success((let note, _)):
            update(viewModel: viewModel) { state in
                if let oldIndex {
                    state.notes[oldIndex] = note
                } else {
                    state.notes.append(note)
                }

                state.reload = .section(.notes)
            }

        case .failure(let error):
            if let key {
                DDLogError("ItemDetailActionHandler: Can't update item note \(key) - \(error)")
            } else {
                DDLogError("ItemDetailActionHandler: Can't create item note - \(error)")
            }
            update(viewModel: viewModel) { state in
                state.reload = .section(.notes)
                state.error = .cantSaveNote

                guard let oldIndex else { return }
                if let oldNote {
                    state.notes[oldIndex] = oldNote
                } else {
                    state.notes.remove(at: oldIndex)
                }
            }
        }
    }

    private func delete(note: Note, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard viewModel.state.notes.contains(note) else { return }
        self.trashItem(key: note.key, reloadType: .section(.notes), in: viewModel) { state in
            guard let index = viewModel.state.notes.firstIndex(of: note) else { return }
            state.notes.remove(at: index)
        }
    }

    // MARK: - Tags

    private func set(tags: [Tag], in viewModel: ViewModel<ItemDetailActionHandler>) {
        let oldTags = viewModel.state.tags

        self.update(viewModel: viewModel) { state in
            state.tags = tags
            state.reload = .section(.tags)

            for tag in tags {
                state.backgroundProcessedItems.insert(tag.name)
            }
        }

        let request = EditTagsForItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, tags: tags)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }

            self.update(viewModel: viewModel) { state in
                state.reload = .section(.tags)

                for tag in tags {
                    state.backgroundProcessedItems.remove(tag.name)
                }

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't set tags to item - \(error)")
                    state.tags = oldTags
                }
            }
        }
    }

    private func delete(tag: Tag, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.backgroundProcessedItems.insert(tag.name)
            state.reload = .section(.tags)
        }

        let request = DeleteTagFromItemDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, tagName: tag.name)
        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }

            self.update(viewModel: viewModel) { state in
                state.backgroundProcessedItems.remove(tag.name)
                state.reload = .section(.tags)

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't delete tag \(tag.name) - \(error)")
                    state.error = .cantSaveTags
                } else if let index = state.tags.firstIndex(of: tag) {
                    state.tags.remove(at: index)
                }
            }
        }
    }

    // MARK: - Attachments

    private func delete(attachment: Attachment, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard viewModel.state.attachments.contains(attachment) else { return }
        self.trashItem(key: attachment.key, reloadType: .section(.attachments), in: viewModel) { state in
            guard let index = viewModel.state.attachments.firstIndex(of: attachment) else { return }
            state.attachments.remove(at: index)
        }
    }

    private func deleteFile(of attachment: Attachment, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.fileCleanupController.delete(.individual(attachment: attachment, parentKey: viewModel.state.key))
    }

    private func updateDeletedAttachmentFiles(_ notification: AttachmentFileDeletedNotification, in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch notification {
        case .all:
            guard viewModel.state.attachments.contains(where: { $0.location == .local }) else { return }
            self.setAllAttachmentFilesAsDeleted(in: viewModel)

        case .library(let libraryId):
            guard libraryId == viewModel.state.library.identifier, viewModel.state.attachments.contains(where: { $0.location == .local }) else { return }
            self.setAllAttachmentFilesAsDeleted(in: viewModel)

        case .allForItems(let keys, let libraryId):
            guard libraryId == viewModel.state.library.identifier,
                  keys.contains(viewModel.state.key) && viewModel.state.attachments.contains(where: { $0.location == .local }) else { return }
            self.setAllAttachmentFilesAsDeleted(in: viewModel)

        case .individual(let key, _, let libraryId):
            guard let index = viewModel.state.attachments.firstIndex(where: { $0.key == key && $0.libraryId == libraryId }),
                  let new = viewModel.state.attachments[index].changed(location: .remote, condition: { $0 == .local }) else { return }
            self.update(viewModel: viewModel) { state in
                state.attachments[index] = new
                state.updateAttachmentKey = new.key
            }
        }
    }

    private func setAllAttachmentFilesAsDeleted(in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            for (index, attachment) in state.attachments.enumerated() {
                guard let new = attachment.changed(location: .remote, condition: { $0 == .local }) else { continue }
                state.attachments[index] = new
            }
            state.reload = .section(.attachments)
        }
    }

    private func addAttachments(from urls: [URL], in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.createAttachments(from: urls, libraryId: viewModel.state.library.identifier) { [weak viewModel] attachments, failedCopyNames in
            guard let viewModel = viewModel else { return }

            if attachments.isEmpty {
                self.update(viewModel: viewModel) { state in
                    state.error = .cantAddAttachments(.couldNotMoveFromSource(failedCopyNames))
                }
                return
            }

            self.update(viewModel: viewModel) { state in
                for attachment in attachments {
                    let index = state.attachments.index(of: attachment, sortedBy: { $0.title.caseInsensitiveCompare($1.title) == .orderedAscending })
                    state.attachments.insert(attachment, at: index)
                    state.backgroundProcessedItems.insert(attachment.key)
                }

                state.reload = .section(.attachments)

                if !failedCopyNames.isEmpty {
                    state.error = .cantAddAttachments(.couldNotMoveFromSource(failedCopyNames))
                }
            }

            let type = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ItemTypes.attachment
            let request = CreateAttachmentsDbRequest(attachments: attachments, parentKey: viewModel.state.key, localizedType: type, collections: [])

            self.perform(request: request, invalidateRealm: true) { [weak viewModel] result in
                guard let viewModel = viewModel else { return }

                self.update(viewModel: viewModel) { state in
                    for attachment in attachments {
                        state.backgroundProcessedItems.remove(attachment.key)
                    }
                    state.reload = .section(.attachments)

                    switch result {
                    case .failure(let error):
                        DDLogError("ItemDetailActionHandler: could not create attachments - \(error)")
                        state.error = .cantAddAttachments(.allFailedCreation)
                        state.attachments.removeAll(where: { attachment in return attachments.contains(where: { $0.key == attachment.key }) })

                    case .success(let failed):
                        guard !failed.isEmpty else { return }
                        state.error = .cantAddAttachments(.someFailedCreation(failed.map({ $0.1 })))
                        state.attachments.removeAll(where: { attachment in return failed.contains(where: { $0.0 == attachment.key }) })
                    }
                }
            }
        }
    }

    private func createAttachments(from urls: [URL], libraryId: LibraryIdentifier, completion: @escaping (([Attachment], [String])) -> Void) {
        self.backgroundQueue.async {
            var attachments: [Attachment] = []
            var failedNames: [String] = []

            for url in urls {
                var name = url.deletingPathExtension().lastPathComponent
                name = name.removingPercentEncoding ?? name
                let mimeType = url.pathExtension.mimeTypeFromExtension ?? "application/octet-stream"
                let key = KeyGenerator.newKey
                let nameWithExtension = name + "." + url.pathExtension
                let file = Files.attachmentFile(in: libraryId, key: key, filename: nameWithExtension, contentType: mimeType)

                do {
                    try self.fileStorage.move(from: url.path, to: file)
                    attachments.append(
                        Attachment(
                            type: .file(filename: nameWithExtension, contentType: mimeType, location: .local, linkType: .importedFile, compressed: false),
                            title: nameWithExtension,
                            key: key,
                            libraryId: libraryId
                        )
                    )
                } catch let error {
                    DDLogError("ItemDetailActionHandler: can't move attachment from source url \(url.relativePath) - \(error)")
                    failedNames.append(nameWithExtension)
                }
            }

            inMainThread {
                completion((attachments, failedNames))
            }
        }
    }

    private func openAttachment(with key: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        let (progress, _) = self.fileDownloader.data(for: key, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)

        if progress != nil {
            // If download is in progress, cancel download
            self.update(viewModel: viewModel) { state in
                if state.attachmentToOpen == key {
                    state.attachmentToOpen = nil
                }
            }

            self.fileDownloader.cancel(key: key, parentKey: viewModel.state.key, libraryId: viewModel.state.library.identifier)
            return
        }

        guard let attachment = viewModel.state.attachments.first(where: { $0.key == key }) else { return }

        // Otherwise start download

        self.update(viewModel: viewModel) { state in
            state.attachmentToOpen = key
        }

        self.fileDownloader.downloadIfNeeded(attachment: attachment, parentKey: viewModel.state.key)
    }

    private func process(downloadUpdate update: AttachmentDownloader.Update, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard viewModel.state.library.identifier == update.libraryId,
              let index = viewModel.state.attachments.firstIndex(where: { $0.key == update.key }) else { return }

        let attachment = viewModel.state.attachments[index]

        switch update.kind {
        case .cancelled, .failed, .progress:
            self.update(viewModel: viewModel) { state in
                state.updateAttachmentKey = attachment.key
            }

        case .ready(let compressed):
            guard let new = attachment.changed(location: .local, compressed: compressed) else { return }
            self.update(viewModel: viewModel) { state in
                state.attachments[index] = new
                state.updateAttachmentKey = new.key
            }
        }
    }

    private func moveToStandalone(attachment: Attachment, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.backgroundProcessedItems.insert(attachment.key)
            state.reload = .section(.attachments)
        }

        self.perform(request: RemoveItemFromParentDbRequest(key: attachment.key, libraryId: attachment.libraryId)) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }

            self.update(viewModel: viewModel) { state in
                state.backgroundProcessedItems.remove(attachment.key)
                state.reload = .section(.attachments)

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't move attachment to standalone - \(error)")
                    state.error = .cantRemoveParent
                } else {
                    guard let index = viewModel.state.attachments.firstIndex(of: attachment) else { return }
                    state.attachments.remove(at: index)
                }
            }
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

    private func endEditing(in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard viewModel.state.snapshot != viewModel.state.data else { return }

        self.update(viewModel: viewModel) { state in
            state.isSaving = true
        }

        endEditing(state: viewModel.state, queue: self.backgroundQueue)
            .subscribe(on: self.backgroundScheduler)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak viewModel] newState in
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state = newState
                    state.isSaving = false
                }
            }, onFailure: { [weak viewModel] error in
                DDLogError("ItemDetailStore: can't store changes - \(error)")
                guard let viewModel = viewModel else { return }
                self.update(viewModel: viewModel) { state in
                    state.error = (error as? ItemDetailError) ?? .cantStoreChanges
                    state.isSaving = false
                }
            })
            .disposed(by: self.disposeBag)

        func endEditing(state: ItemDetailState, queue: DispatchQueue) -> Single<ItemDetailState> {
            return Single.create { subscriber -> Disposable in
                do {
                    var newState = state

                    var updatedFields: [KeyBaseKeyPair: String] = [:]
                    if let field = state.data.fields[FieldKeys.Item.accessDate] {
                        let updated = updated(accessDateField: field, originalField: state.snapshot?.fields[FieldKeys.Item.accessDate])
                        if updated.value != field.value {
                            updatedFields[KeyBaseKeyPair(key: updated.key, baseKey: updated.baseField)] = updated.value
                            newState.data.fields[updated.key] = updated
                        }
                    }
                    if let field = state.data.fields.values.first(where: { $0.baseField == FieldKeys.Item.date || $0.key == FieldKeys.Item.date }),
                        let updated = updated(dateField: field),
                        updated.value != field.value {
                        updatedFields[KeyBaseKeyPair(key: updated.key, baseKey: updated.baseField)] = updated.value
                        newState.data.fields[updated.key] = updated
                    }

                    var requests: [DbRequest] = [EndItemDetailEditingDbRequest(libraryId: state.library.identifier, itemKey: state.key)]
                    if !updatedFields.isEmpty {
                        requests.insert(EditItemFieldsDbRequest(key: state.key, libraryId: state.library.identifier, fieldValues: updatedFields, dateParser: dateParser), at: 0)
                    }
                    try self.dbStorage.perform(writeRequests: requests, on: queue)

                    newState.data.dateModified = Date()
                    newState.snapshot = nil
                    newState.data.fieldIds = ItemDetailDataCreator.filteredFieldKeys(from: newState.data.fieldIds, fields: newState.data.fields)
                    newState.isEditing = false
                    newState.type = .preview(key: newState.key)
                    newState.changes.insert(.editing)

                    subscriber(.success(newState))
                } catch let error {
                    subscriber(.failure(error))
                }
                return Disposables.create()
            }
        }

        func updated(accessDateField: ItemDetailState.Field, originalField: ItemDetailState.Field?) -> ItemDetailState.Field {
            var field = accessDateField

            var date: Date?
            if let _date = parseDateSpecialValue(from: field.value) {
                date = _date
            } else if let _date = Formatter.sqlFormat.date(from: field.value) {
                date = _date
            }

            if let date = date {
                field.value = Formatter.iso8601.string(from: date)
                field.additionalInfo = [.formattedDate: Formatter.dateAndTime.string(from: date), .formattedEditDate: Formatter.sqlFormat.string(from: date)]
            } else {
                if let originalField {
                    field = originalField
                } else {
                    field.value = ""
                    field.additionalInfo = [:]
                }
            }

            return field
        }

        func updated(dateField: ItemDetailState.Field) -> ItemDetailState.Field? {
            guard let date = parseDateSpecialValue(from: dateField.value) else { return nil }
            var field = dateField
            field.value = Formatter.dateWithDashes.string(from: date)
            if let order = self.dateParser.parse(string: field.value)?.orderWithSpaces {
                field.additionalInfo?[.dateOrder] = order
            }
            return field
        }

        func parseDateSpecialValue(from value: String) -> Date? {
            // TODO: - check for current localization
            switch value.lowercased() {
            case "tomorrow":
                return Calendar.current.date(byAdding: .day, value: 1, to: Date())
            case "today":
                return Date()
            case "yesterday":
                return Calendar.current.date(byAdding: .day, value: -1, to: Date())

            default:
                return nil
            }
        }
    }

    private func cancelChanges(in viewModel: ViewModel<ItemDetailActionHandler>) {
        switch viewModel.state.type {
        case .duplication:
            self.perform(request: DeleteObjectsDbRequest<RItem>(keys: [viewModel.state.key], libraryId: viewModel.state.library.identifier)) { [weak viewModel] error in
                guard let viewModel = viewModel else { return }

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't remove duplicated and cancelled item - \(error)")

                    self.update(viewModel: viewModel) { state in
                        state.error = .cantRemoveItem
                    }
                    return
                }

                self.update(viewModel: viewModel) { state in
                    state.hideController = true
                }
            }

        case .creation(_, let child, _):
            var actions: [DbRequest] = [DeleteObjectsDbRequest<RItem>(keys: [viewModel.state.key], libraryId: viewModel.state.library.identifier)]
            if let child {
                actions.insert(CancelParentCreationDbRequest(key: child.key, libraryId: child.libraryId), at: 0)
            }
            self.perform(writeRequests: actions) { [weak viewModel] error in
                guard let viewModel = viewModel else { return }

                if let error = error {
                    DDLogError("ItemDetailActionHandler: can't remove created and cancelled item - \(error)")

                    self.update(viewModel: viewModel) { state in
                        state.error = .cantRemoveItem
                    }
                    return
                }

                self.update(viewModel: viewModel) { state in
                    state.hideController = true
                }
            }

        case .preview: break
        }
    }

    private func changeType(to newType: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        let itemData: ItemDetailState.Data
        do {
            itemData = try data(for: newType, from: viewModel.state.data)
        } catch let error {
            self.update(viewModel: viewModel) { state in
                state.error = (error as? ItemDetailError) ?? .typeNotSupported(newType)
            }
            return
        }

        let droppedFields = droppedFields(from: viewModel.state.data, to: itemData)
        self.update(viewModel: viewModel) { state in
            if droppedFields.isEmpty {
                state.data = itemData
                state.changes.insert(.type)
            } else {
                // Notify the user, that some fields with values will be dropped
                state.promptSnapshot = itemData
                state.error = .droppedFields(droppedFields)
            }
        }

        if droppedFields.isEmpty {
            self.changeTypeInDb(viewModel: viewModel)
        }

        func droppedFields(from fromData: ItemDetailState.Data, to toData: ItemDetailState.Data) -> [String] {
            let newFields = Set(toData.fields.values)
            var subtracted = Set(fromData.fields.values.filter({ !$0.value.isEmpty }))
            for field in newFields {
                guard let oldField = subtracted.first(where: { ($0.baseField ?? $0.name) == (field.baseField ?? field.name) }) else { continue }
                subtracted.remove(oldField)
            }
            return subtracted.map({ $0.name }).sorted()
        }

        func data(for type: String, from originalData: ItemDetailState.Data) throws -> ItemDetailState.Data {
            guard let localizedType = self.schemaController.localized(itemType: type) else {
                throw ItemDetailError.typeNotSupported(type)
            }

            let (fieldIds, fields, hasAbstract) = try ItemDetailDataCreator.fieldData(
                for: type,
                schemaController: self.schemaController,
                dateParser: self.dateParser,
                urlDetector: self.urlDetector,
                doiDetector: FieldKeys.Item.isDoi,
                getExistingData: { key, baseField -> (String?, String?) in
                    if let field = originalData.fields[key] {
                        return (field.name, field.value)
                    } else if let base = baseField, let field = originalData.fields.values.first(where: { $0.baseField == base }) {
                        // We don't return existing name, because fields that are matching just by baseField will most likely have different names
                        return (nil, field.value)
                    }
                    return (nil, nil)
                }
            )

            var data = originalData
            data.type = type
            data.isAttachment = type == ItemTypes.attachment
            data.localizedType = localizedType
            data.fields = fields
            data.fieldIds = fieldIds
            data.abstract = hasAbstract ? (originalData.abstract ?? "") : nil
            data.creators = try creators(for: type, from: originalData.creators)
            data.creatorIds = originalData.creatorIds
            return data
        }

        func creators(for type: String, from originalData: [String: ItemDetailState.Creator]) throws -> [String: ItemDetailState.Creator] {
            guard let schemas = self.schemaController.creators(for: type), let primary = schemas.first(where: { $0.primary }) else { throw ItemDetailError.typeNotSupported(type) }

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
    }

    private func acceptPrompt(in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            guard let snapshot = state.promptSnapshot else { return }
            state.data = snapshot
            state.changes.insert(.type)
            state.promptSnapshot = nil
        }

        self.changeTypeInDb(viewModel: viewModel)
    }

    private func changeTypeInDb(viewModel: ViewModel<ItemDetailActionHandler>) {
        let request = EditTypeItemDetailDbRequest(
            key: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            type: viewModel.state.data.type,
            fields: viewModel.state.data.databaseFields(schemaController: schemaController),
            creatorIds: viewModel.state.data.creatorIds,
            creators: viewModel.state.data.creators,
            dateParser: dateParser
        )
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't change type - \(error)")
        }
    }

    private func set(title: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard let key = self.schemaController.titleKey(for: viewModel.state.data.type) else {
            DDLogError("ItemDetailActionHandler: schema controller doesn't contain title key for item type \(viewModel.state.data.type)")
            return
        }

        self.update(viewModel: viewModel) { state in
            state.data.title = title
            state.reload = .row(.title)
        }

        let keyPair = KeyBaseKeyPair(key: key, baseKey: (key != FieldKeys.Item.title ? FieldKeys.Item.title : nil))
        let request = EditItemFieldsDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, fieldValues: [keyPair: title], dateParser: dateParser)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't store title - \(error)")
        }
    }

    private func set(abstract: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.data.abstract = abstract
            state.reload = .row(.abstract)
        }

        let request = EditItemFieldsDbRequest(
            key: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            fieldValues: [KeyBaseKeyPair(key: FieldKeys.Item.abstract, baseKey: nil): abstract],
            dateParser: dateParser
        )
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't store abstract - \(error)")
        }
    }

    private func setField(value: String, for id: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard var field = viewModel.state.data.fields[id] else { return }

        field.value = value
        field.isTappable = ItemDetailDataCreator.isTappable(key: field.key, value: field.value, urlDetector: self.urlDetector, doiDetector: FieldKeys.Item.isDoi)

        if field.key == FieldKeys.Item.date || field.baseField == FieldKeys.Item.date, let order = self.dateParser.parse(string: value)?.orderWithSpaces {
            var info = field.additionalInfo ?? [:]
            info[.dateOrder] = order
            field.additionalInfo = info
        } else if field.additionalInfo != nil {
            field.additionalInfo = nil
        }

        self.update(viewModel: viewModel) { state in
            state.data.fields[id] = field
            state.reload = .row(.field(key: field.key, multiline: (field.id == FieldKeys.Item.extra)))
        }

        let request = EditItemFieldsDbRequest(
            key: viewModel.state.key,
            libraryId: viewModel.state.library.identifier,
            fieldValues: [KeyBaseKeyPair(key: field.key, baseKey: field.baseField): field.value],
            dateParser: dateParser
        )
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't store field \(error)")
        }
    }

    private func deleteCreator(with id: String, in viewModel: ViewModel<ItemDetailActionHandler>) {
        guard let index = viewModel.state.data.creatorIds.firstIndex(of: id) else { return }
        
        self.update(viewModel: viewModel) { state in
            state.data.creatorIds.remove(at: index)
            state.data.creators[id] = nil
            state.reload = .section(.creators)
        }

        let request = DeleteCreatorItemDetailDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, creatorId: id)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't delete creator \(error)")
        }
    }

    private func save(creator: State.Creator, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if !state.data.creatorIds.contains(creator.id) {
                state.data.creatorIds.append(creator.id)
            }
            state.data.creators[creator.id] = creator
            state.reload = .section(.creators)
        }

        guard let orderId = viewModel.state.data.creatorIds.firstIndex(of: creator.id) else { return }
        let request = EditCreatorItemDetailDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, creator: creator, orderId: orderId)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't create creator \(error)")
        }
    }

    private func moveCreators(diff: CollectionDifference<String>, in viewModel: ViewModel<ItemDetailActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.data.creatorIds = state.data.creatorIds.applying(diff) ?? []
        }
        
        let request = ReorderCreatorsItemDetailDbRequest(key: viewModel.state.key, libraryId: viewModel.state.library.identifier, ids: viewModel.state.data.creatorIds)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("ItemDetailActionHandler: can't reorder creators \(error)")
        }
    }
}
