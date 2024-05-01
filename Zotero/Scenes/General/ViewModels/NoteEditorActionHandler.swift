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
    typealias SaveResult = NoteEditorSaveResult
    typealias SaveCallback = NoteEditorSaveCallback

    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let schemaController: SchemaController
    unowned let attachmentDownloader: AttachmentDownloader
    let saveCallback: SaveCallback
    let backgroundQueue: DispatchQueue
    private let disposeBag: DisposeBag

    init(dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, attachmentDownloader: AttachmentDownloader, saveCallback: @escaping SaveCallback) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.attachmentDownloader = attachmentDownloader
        self.saveCallback = saveCallback
        disposeBag = DisposeBag()
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.NoteEditorActionHandler.queue", qos: .userInteractive)
    }

    func process(action: Action, in viewModel: ViewModel<NoteEditorActionHandler>) {
        switch action {
        case .setup:
            setup(in: viewModel)

        case .save:
            save(in: viewModel)

        case .setText(let text):
            guard text != viewModel.state.text else { return }
            update(viewModel: viewModel) { state in
                state.text = text
                state.changes = .save
            }

        case .setTags(let tags):
            update(viewModel: viewModel) { state in
                state.tags = tags
                state.changes = [.tags, .save]
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
            let file = Files.attachmentFile(in: libraryId, key: key, filename: "image", contentType: mimeType)

            do {
                try self.fileStorage.write(image, to: file, options: .atomic)
            } catch let error {
                DDLogError("NoteEditorActionHandler: can't write file - \(error)")
                continue
            }

            let attachment = Attachment(
                type: .file(filename: "image", contentType: mimeType, location: .local, linkType: .embeddedImage, compressed: false),
                title: "image",
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
                state.changes = .save
            }
        } catch let error {
            DDLogError("NoteEditorActionHandler: can't create embedded images - \(error)")
            saveCallback(parentKey, .failure(error))
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

            case .readOnly(let key):
                saveCallback(key, .failure(State.Error.cantSaveReadonlyNote))
                return nil
            }

            do {
                _ = try dbStorage.perform(request: request, on: backgroundQueue)
                update(viewModel: viewModel) { state in
                    state.kind = .edit(key: note.key)
                }
                saveCallback(note.key, .success((note: note, isCreated: true)))
                updateTitleIfNeeded(title: note.title, viewModel: viewModel)
                return note.key
            } catch let error {
                DDLogError("NoteEditorActionHandler: can't create item note for added image: \(error)")
                saveCallback(note.key, .failure(error))
                return nil
            }
        }
    }

    private func setup(in viewModel: ViewModel<NoteEditorActionHandler>) {
        attachmentDownloader.observable
            .subscribe(onNext: { [weak viewModel] update in
                guard let viewModel else { return }
                switch update.kind {
                case .ready:
                    backgroundQueue.async { [weak viewModel] in
                        guard let viewModel else { return }
                        process(key: update.key, libraryId: update.libraryId, viewModel: viewModel)
                    }

                default:
                    break
                }
            })
            .disposed(by: disposeBag)

        func process(key: String, libraryId: LibraryIdentifier, viewModel: ViewModel<NoteEditorActionHandler>) {
            guard let metadata = viewModel.state.pendingResources[key] else { return }
            switch metadata.type {
            case "image":
                processImage(identifier: metadata.identifier, key: key, filename: metadata.filename, contentType: metadata.contentType, libraryId: libraryId, viewModel: viewModel)

            default:
                DDLogWarn("NoteEditorActionHandler: unknown resource type - \(metadata.type); \(key); \(libraryId)")
            }
        }
    }

    private func processImage(identifier: String, key: String, filename: String, contentType: String, libraryId: LibraryIdentifier, viewModel: ViewModel<NoteEditorActionHandler>) {
        let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: contentType)
        do {
            let data = try fileStorage.read(file).base64EncodedData()
            guard let dataString = String(data: data, encoding: .utf8) else {
                throw NoteEditorState.Error.cantCreateData
            }
            DDLogInfo("NoteEditorActionHandler: loaded resource '\(contentType)' for \(identifier); \(key)")
            let resource = NoteEditorState.Resource(identifier: identifier, data: ["src": "data:\(contentType);base64,\(dataString)"])
            update(viewModel: viewModel) { state in
                state.pendingResources[key] = nil
                state.downloadedResource = resource
            }
        } catch let error {
            DDLogError("NoteEditorActionHandler: can't read resource for \(key) - \(error)")
        }
    }

    private func loadResource(data: [String: Any], in viewModel: ViewModel<NoteEditorActionHandler>) {
        guard case .edit(let noteKey) = viewModel.state.kind,
              let identifier = data["id"] as? String,
              let type = data["type"] as? String,
              let key = (data["data"] as? [String: Any])?["attachmentKey"] as? String,
              let item = try? dbStorage.perform(request: ReadItemDbRequest(libraryId: viewModel.state.library.identifier, key: key), on: .main, refreshRealm: true),
              let attachment = AttachmentCreator.attachment(for: item, fileStorage: fileStorage, urlDetector: nil),
              case .file(let filename, let contentType, let location, _, _) = attachment.type
        else { return }

        DDLogInfo("NoteEditorActionHandler: load resource for \(identifier); \(key)")

        if location == .local {
            processImage(identifier: identifier, key: key, filename: filename, contentType: contentType, libraryId: viewModel.state.library.identifier, viewModel: viewModel)
            return
        }

        let metadata = NoteEditorState.ResourceMetadata(identifier: identifier, type: type, filename: filename, contentType: contentType)
        update(viewModel: viewModel) { state in
            state.pendingResources[key] = metadata
        }

        attachmentDownloader.downloadIfNeeded(attachment: attachment, parentKey: noteKey)
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
            saveCallback(key, .failure(error))
        }

        func create<Request: DbResponseRequest>(note: Note, with request: Request) {
            perform(request: request, invalidateRealm: true) { result in
                switch result {
                case .success:
                    update(viewModel: viewModel) { state in
                        state.kind = .edit(key: note.key)
                        state.changes = [.kind]
                    }
                    saveCallback(note.key, .success((note: note, isCreated: true)))
                    updateTitleIfNeeded(title: note.title, viewModel: viewModel)

                case .failure(let error):
                    DDLogError("NoteEditorActionHandler: can't create item note: \(error)")
                    saveCallback(note.key, .failure(error))
                }
            }
        }

        func updateExistingNote(library: Library, key: String, text: String, tags: [Tag]) {
            let note = Note(key: key, text: text, tags: tags)
            let request = EditNoteDbRequest(note: note, libraryId: library.identifier)
            perform(request: request) { error in
                if let error {
                    DDLogError("NoteEditorActionHandler: can't update existing note: \(error)")
                    saveCallback(key, .failure(error))
                } else {
                    saveCallback(key, .success((note: note, isCreated: false)))
                    updateTitleIfNeeded(title: note.title, viewModel: viewModel)
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

    func updateTitleIfNeeded(title: String, viewModel: ViewModel<NoteEditorActionHandler>) {
        guard title != viewModel.state.title else { return }
        update(viewModel: viewModel) { state in
            state.title = title
            state.changes = [.title]
        }
    }
}
