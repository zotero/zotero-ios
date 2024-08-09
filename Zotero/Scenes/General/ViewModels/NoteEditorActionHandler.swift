//
//  NoteEditorActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 07.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct NoteEditorActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = NoteEditorAction
    typealias State = NoteEditorState
    typealias SaveResult = NoteEditorSaveResult
    typealias SaveCallback = NoteEditorSaveCallback

    unowned let dbStorage: DbStorage
    unowned let schemaController: SchemaController
    let saveCallback: SaveCallback
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage, schemaController: SchemaController, saveCallback: @escaping SaveCallback) {
        self.dbStorage = dbStorage
        self.schemaController = schemaController
        self.saveCallback = saveCallback
        backgroundQueue = DispatchQueue(label: "org.zotero.Zotero.NoteEditorActionHandler.queue", qos: .userInteractive)
    }

    func process(action: Action, in viewModel: ViewModel<NoteEditorActionHandler>) {
        switch action {
        case .save:
            save(viewModel: viewModel)

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
        }

        func save(viewModel: ViewModel<NoteEditorActionHandler>) {
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
}
