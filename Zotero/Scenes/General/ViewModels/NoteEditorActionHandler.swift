//
//  NoteEditorActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct NoteEditorActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = NoteEditorAction
    typealias State = NoteEditorState

    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let schemaController: SchemaController
    unowned let attachmentDownloader: AttachmentDownloader
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, attachmentDownloader: AttachmentDownloader) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.attachmentDownloader = attachmentDownloader
        disposeBag = DisposeBag()
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.NoteEditorActionHandler.queue", qos: .userInteractive)
    }

    func process(action: Action, in viewModel: ViewModel<NoteEditorActionHandler>) {
        switch action {
        case .save:
            save(in: viewModel)

        case .saveBeforeClosing:
            update(viewModel: viewModel) { state in
                state.isClosing = true
                state.changes = .closing
            }
            save(in: viewModel)

        case .setText(let text):
            guard text != viewModel.state.text else { return }
            update(viewModel: viewModel) { state in
                state.text = text
                state.changes = .shouldSave
            }

        case .setTags(let tags):
            update(viewModel: viewModel) { state in
                state.tags = tags
                state.changes = [.tags, .shouldSave]
            }

        case .loadResource(let data):
            loadResource(data: data, in: viewModel)

        case .deleteResource(let data):
            deleteResource(data: data, in: viewModel)

        case .importImages(let data):
            backgroundQueue.async { [weak viewModel] in
                guard let viewModel else { return }
                importImages(data: data, in: viewModel)
            }
        }
    }

    private func importImages(data: [String: Any], in viewModel: ViewModel<NoteEditorActionHandler>) {
        guard !viewModel.state.kind.readOnly, let rawImages = data["images"] as? [[String: Any]] else { return }

        DDLogInfo("NoteEditorActionHandler: Import \(rawImages.count) images")

        let imageFilename = "image"
        let libraryId = viewModel.state.library.identifier
        var images: [(String, Attachment)] = []

        for imageData in rawImages {
            guard
                let nodeId = imageData["nodeID"] as? String,
                let src = imageData["src"] as? String,
                let mimeType = src.mimeTypeFromNoteEditorSrc,
                let base64EncodedData = src.base64DataFromNoteEditorSrc?.data(using: .utf8),
                let image = Data(base64Encoded: base64EncodedData)
            else { continue }

            let key = KeyGenerator.newKey
            let file = Files.attachmentFile(in: libraryId, key: key, filename: imageFilename, contentType: mimeType)

            do {
                try self.fileStorage.write(image, to: file, options: .atomic)
            } catch let error {
                DDLogError("NoteEditorActionHandler: can't write file - \(error)")
                continue
            }

            let attachment = Attachment(
                type: .file(filename: imageFilename, contentType: mimeType, location: .local, linkType: .embeddedImage, compressed: false),
                title: imageFilename,
                key: key,
                libraryId: libraryId
            )
            images.append((nodeId, attachment))
        }

        guard !images.isEmpty, let parentKey = createItemIfNeeded() else {
            return
        }

        let type = schemaController.localized(itemType: ItemTypes.attachment) ?? ""
        let request = CreateAttachmentsDbRequest(attachments: images.map({ $0.1 }), parentKey: parentKey, localizedType: type, collections: [])

        DDLogInfo("NoteEditorActionHandler: submit \(images.count) images")

        do {
            let failedKeys = try dbStorage.perform(request: request, on: backgroundQueue).map({ $0.0 })
            let successfulImages = images.filter({ !failedKeys.contains($0.1.key) }).map({ NoteEditorState.CreatedImage(nodeId: $0.0, key: $0.1.key) })
            DDLogInfo("NoteEditorActionHandler: successfully created \(successfulImages)")
            update(viewModel: viewModel) { state in
                state.createdImages = successfulImages
                state.changes = .shouldSave
            }
        } catch let error {
            DDLogError("NoteEditorActionHandler: can't create embedded images - \(error)")
            update(viewModel: viewModel) { state in
                state.error = error
            }
        }

        func createItemIfNeeded() -> String? {
            let note: Note
            let request: CreateNoteDbRequest
            switch viewModel.state.kind {
            case .itemCreation(let parentKey):
                (note, request) = createItemNote(library: viewModel.state.library, parentKey: parentKey, text: viewModel.state.text, tags: viewModel.state.tags)

            case .standaloneCreation(let collection):
                (note, request) = createStandaloneNote(library: viewModel.state.library, collection: collection, text: viewModel.state.text, tags: viewModel.state.tags)

            case .edit(let key):
                return key

            case .readOnly:
                return nil
            }

            do {
                _ = try dbStorage.perform(request: request, on: backgroundQueue)
                update(viewModel: viewModel) { state in
                    state.kind = .edit(key: note.key)
                    updateTitleIfNeeded(title: note.title, state: &state)
                    state.changes = [.kind, .saved]
                }
                return note.key
            } catch let error {
                DDLogError("NoteEditorActionHandler: can't create item note for added image: \(error)")
                update(viewModel: viewModel) { state in
                    state.error = error
                }
                return nil
            }
        }
    }

    private func loadResource(data: [String: Any], in viewModel: ViewModel<NoteEditorActionHandler>) {
        guard case .edit(let noteKey) = viewModel.state.kind,
              let identifier = data["id"] as? String,
              let type = data["type"] as? String,
              let key = (data["data"] as? [String: Any])?["attachmentKey"] as? String,
              let item = try? dbStorage.perform(request: ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: key), on: .main, refreshRealm: true),
              let attachment = AttachmentCreator.attachment(for: item, fileStorage: fileStorage, urlDetector: nil),
              let file = attachment.file
        else { return }

        guard type == "image" else {
            DDLogWarn("NoteEditorActionHandler: unknown resource type - \(type); \(key); \(viewModel.state.library.identifier)")
            return
        }

        DDLogInfo("NoteEditorActionHandler: load resource for \(identifier); \(key)")

        attachmentDownloader.downloadIfNeeded(attachment: attachment, parentKey: noteKey) { [weak viewModel] result in
            switch result {
            case .success:
                backgroundQueue.async { [weak viewModel] in
                    guard let viewModel else { return }
                    processImage(identifier: identifier, file: file, viewModel: viewModel)
                }

            case .failure(let error):
                DDLogError("NoteEditorActionHandler: could not load resource for \(identifier); \(key) - \(error)")
            }
        }

        func processImage(identifier: String, file: File, viewModel: ViewModel<NoteEditorActionHandler>) {
            do {
                let data = try fileStorage.read(file).base64EncodedData()
                guard let dataString = String(data: data, encoding: .utf8) else {
                    throw NoteEditorState.Error.cantCreateData
                }
                DDLogInfo("NoteEditorActionHandler: loaded resource \(identifier); \(file.relativeComponents.joined(separator: "; "))")
                let resource = NoteEditorState.Resource(identifier: identifier, data: ["src": "data:\(file.mimeType);base64,\(dataString)"])
                update(viewModel: viewModel) { state in
                    state.downloadedResource = resource
                }
            } catch let error {
                DDLogError("NoteEditorActionHandler: can't read resource \(identifier); \(file.relativeComponents.joined(separator: "; ")) - \(error)")
            }
        }
    }

    private func deleteResource(data: [String: Any], in viewModel: ViewModel<NoteEditorActionHandler>) {
        guard let key = data["id"] as? String else { return }
        DDLogInfo("NoteEditorActionHandler: delete resource for \(key)")
        let request = MarkObjectsAsDeletedDbRequest<RItem>(keys: [key], libraryId: viewModel.state.library.identifier)
        perform(request: request) { error in
            guard let error else { return }
            DDLogError("NoteEditorActionHandler: could not mark image as deleted \(key) - \(error)")
        }
    }

    private func save(in viewModel: ViewModel<NoteEditorActionHandler>) {
        let kind = viewModel.state.kind
        let library = viewModel.state.library
        let text = viewModel.state.text
        let tags = viewModel.state.tags

        switch kind {
        case .itemCreation(let parentKey):
            let (note, request) = createItemNote(library: library, parentKey: parentKey, text: text, tags: tags)
            create(note: note, with: request)

        case .standaloneCreation(let collection):
            let (note, request) = createStandaloneNote(library: library, collection: collection, text: text, tags: tags)
            create(note: note, with: request)

        case .edit(let key):
            updateExistingNote(library: library, key: key, text: text, tags: tags)

        case .readOnly(let key):
            let error = State.Error.cantSaveReadonlyNote
            DDLogError("NoteEditorActionHandler: can't update read only note: \(error)")
            store(error: error, key: key)
        }

        func store(error: Swift.Error, key: String) {
            update(viewModel: viewModel) { state in
                state.error = error
                if !state.isClosing {
                    state.changes = .saved
                } else {
                    state.isClosing = false
                    state.changes = [.saved, .closing]
                }
            }
        }

        func create<Request: DbResponseRequest>(note: Note, with request: Request) {
            perform(request: request, invalidateRealm: true) { result in
                switch result {
                case .success:
                    update(viewModel: viewModel) { state in
                        state.kind = .edit(key: note.key)
                        state.changes = [.kind, .saved]
                        updateTitleIfNeeded(title: note.title, state: &state)
                    }

                case .failure(let error):
                    DDLogError("NoteEditorActionHandler: can't create item note: \(error)")
                    store(error: error, key: note.key)
                }
            }
        }

        func updateExistingNote(library: Library, key: String, text: String, tags: [Tag]) {
            let note = Note(key: key, text: text, tags: tags)
            let request = EditNoteDbRequest(note: note, libraryId: library.identifier)
            perform(request: request) { error in
                if let error {
                    DDLogError("NoteEditorActionHandler: can't update existing note: \(error)")
                    store(error: error, key: key)
                } else {
                    update(viewModel: viewModel) { state in
                        state.changes = .saved
                        updateTitleIfNeeded(title: note.title, state: &state)
                    }
                }
            }
        }
    }

    private func createItemNote(library: Library, parentKey: String, text: String, tags: [Tag]) -> (Note, CreateNoteDbRequest) {
        let key = KeyGenerator.newKey
        let note = Note(key: key, text: text, tags: tags)
        let type = schemaController.localized(itemType: ItemTypes.note) ?? ItemTypes.note
        let request = CreateNoteDbRequest(note: note, localizedType: type, libraryId: library.identifier, collectionKey: nil, parentKey: parentKey)
        return (note, request)
    }

    private func createStandaloneNote(library: Library, collection: Collection, text: String, tags: [Tag]) -> (Note, CreateNoteDbRequest) {
        let key = KeyGenerator.newKey
        let note = Note(key: key, text: text, tags: tags)
        let type = schemaController.localized(itemType: ItemTypes.note) ?? ItemTypes.note
        let collectionKey = collection.isCollection ? collection.identifier.key : nil
        let request = CreateNoteDbRequest(note: note, localizedType: type, libraryId: library.identifier, collectionKey: collectionKey, parentKey: nil)
        return (note, request)
    }

    private func updateTitleIfNeeded(title: String, state: inout NoteEditorState) {
        guard title != state.title else { return }
        state.title = title
        state.changes.insert(.title)
    }
}
