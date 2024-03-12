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
                processImage(identifier: metadata.identifier, key: key, libraryId: libraryId, viewModel: viewModel)

            default:
                DDLogWarn("NoteEditorActionHandler: unknown resource type - \(metadata.type); \(key); \(libraryId)")
            }
        }
    }

    private func processImage(identifier: String, key: String, libraryId: LibraryIdentifier, viewModel: ViewModel<NoteEditorActionHandler>) {
        let file = Files.attachmentFile(in: libraryId, key: key, filename: "image", contentType: "image/png")
        do {
            let data = try fileStorage.read(file).base64EncodedData()
            guard let dataString = String(data: data, encoding: .utf8) else {
                throw NoteEditorState.Error.cantCreateData
            }
            let resource = NoteEditorState.Resource(identifier: identifier, data: ["src": "data:image/png;base64,\(dataString)"])
            update(viewModel: viewModel) { state in
                state.pendingResources[key] = nil
                state.downloadedResource = resource
            }
        } catch let error {
            DDLogError("NoteEditorActionHandler: can't read downloaded file - \(error)")
        }
    }

    private func loadResource(data: [String: Any], in viewModel: ViewModel<NoteEditorActionHandler>) {
        guard case .edit(let noteKey) = viewModel.state.kind,
              let identifier = data["id"] as? String,
              let type = data["type"] as? String,
              let key = (data["data"] as? [String: Any])?["attachmentKey"] as? String
        else { return }

        let file = Files.attachmentFile(in: viewModel.state.library.identifier, key: key, filename: "image", contentType: "image/png")

        if fileStorage.has(file) {
            processImage(identifier: identifier, key: key, libraryId: viewModel.state.library.identifier, viewModel: viewModel)
            return
        }

        let metadata = NoteEditorState.ResourceMetadata(identifier: identifier, type: type)
        update(viewModel: viewModel) { state in
            state.pendingResources[key] = metadata
        }

        let attachment = Attachment(
            type: .file(filename: "image", contentType: "image/png", location: .remote, linkType: .embeddedImage, compressed: false),
            title: "image",
            key: key,
            libraryId: viewModel.state.library.identifier
        )
        attachmentDownloader.downloadIfNeeded(attachment: attachment, parentKey: noteKey)
    }

    private func save(in viewModel: ViewModel<NoteEditorActionHandler>) {
        let kind = viewModel.state.kind
        let library = viewModel.state.library
        let text = viewModel.state.text
        let tags = viewModel.state.tags

        switch kind {
        case .itemCreation(let parentKey):
            createItemNote(library: library, parentKey: parentKey, text: text, tags: tags)

        case .standaloneCreation(let collection):
            createStandaloneNote(library: library, collection: collection, text: text, tags: tags)

        case .edit(let key):
            updateExistingNote(library: library, key: key, text: text, tags: tags)

        case .readOnly(let key):
            let error = State.Error.cantSaveReadonlyNote
            DDLogError("NoteEditorActionHandler: can't update read only note: \(error)")
            saveCallback(key, .failure(error))
        }

        func createItemNote(library: Library, parentKey: String, text: String, tags: [Tag]) {
            let key = KeyGenerator.newKey
            let note = Note(key: key, text: text, tags: tags)
            let type = schemaController.localized(itemType: ItemTypes.note) ?? ItemTypes.note
            let request = CreateNoteDbRequest(note: note, localizedType: type, libraryId: library.identifier, collectionKey: nil, parentKey: parentKey)
            createNote(note, with: request)
        }

        func createStandaloneNote(library: Library, collection: Collection, text: String, tags: [Tag]) {
            let key = KeyGenerator.newKey
            let note = Note(key: key, text: text, tags: tags)
            let type = schemaController.localized(itemType: ItemTypes.note) ?? ItemTypes.note
            let collectionKey = collection.isCollection ? collection.identifier.key : nil
            let request = CreateNoteDbRequest(note: note, localizedType: type, libraryId: library.identifier, collectionKey: collectionKey, parentKey: nil)
            createNote(note, with: request)
        }

        func createNote<Request: DbResponseRequest>(_ note: Note, with request: Request) {
            perform(request: request, invalidateRealm: true) { result in
                switch result {
                case .success:
                    update(viewModel: viewModel) { state in
                        state.kind = .edit(key: note.key)
                        state.changes = [.kind]
                    }
                    saveCallback(note.key, .success((note: note, isCreated: true)))
                    updateTitleIfNeeded(title: note.title)

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
                    updateTitleIfNeeded(title: note.title)
                }
            }
        }

        func updateTitleIfNeeded(title: String) {
            guard title != viewModel.state.title else { return }
            update(viewModel: viewModel) { state in
                state.title = title
                state.changes = [.title]
            }
        }
    }
}
