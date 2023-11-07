//
//  OpenItemsController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 20/9/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import RxSwift

import CocoaLumberjackSwift

typealias OpenItem = OpenItemsController.Item
typealias ItemPresentation = OpenItemsController.Presentation

protocol OpenItemsPresenter: AnyObject {
    func showItem(with presentation: ItemPresentation)
}

final class OpenItemsController {
    // MARK: Types
    struct Item: Hashable, Equatable, Codable {
        enum Kind: Hashable, Equatable, Codable {
            case pdf(libraryId: LibraryIdentifier, key: String)
            case note(libraryId: LibraryIdentifier, key: String)

            // MARK: Properties
            var libraryId: LibraryIdentifier {
                switch self {
                case .pdf(let libraryId, _), .note(let libraryId, _):
                    return libraryId
                }
            }

            var key: String {
                switch self {
                case .pdf(_, let key), .note(_, let key):
                    return key
                }
            }

            // MARK: Codable
            enum CodingKeys: CodingKey {
                case pdfKind
                case noteKind
                case libraryId
                case key
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .pdf:
                    try container.encode(true, forKey: .pdfKind)

                case .note:
                    try container.encode(true, forKey: .noteKind)
                }

                try container.encode(libraryId, forKey: .libraryId)
                try container.encode(key, forKey: .key)
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let libraryId = try container.decode(LibraryIdentifier.self, forKey: .libraryId)
                let key = try container.decode(String.self, forKey: .key)
                if (try? container.decode(Bool.self, forKey: .pdfKind)) == true {
                    self = .pdf(libraryId: libraryId, key: key)
                } else if (try? container.decode(Bool.self, forKey: .noteKind)) == true {
                    self = .note(libraryId: libraryId, key: key)
                } else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [CodingKeys.pdfKind, CodingKeys.noteKind], debugDescription: "Item kind key not found"))
                }
            }
        }

        let kind: Kind
        var userIndex: Int
        var lastOpened: Date

        init(kind: Kind, userIndex: Int, lastOpened: Date = .now) {
            self.kind = kind
            self.userIndex = userIndex
            self.lastOpened = lastOpened
        }
    }

    enum Presentation {
        case pdf(library: Library, key: String, url: URL)
        case note(library: Library, key: String, text: String, tags: [Tag], title: NoteEditorState.TitleData?)
    }
    
    // MARK: Properties
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    // TODO: Use a better data structure, such as an ordered set
    private(set) var items: [Item] = []
    public var itemsSortedByUserOrder: [Item] {
        items.sorted(by: { $0.userIndex < $1.userIndex })
    }
    public var itemsSortedByLastOpen: [Item] {
        items.sorted(by: { $0.lastOpened > $1.lastOpened })
    }
    let observable: PublishSubject<[Item]>
    private let disposeBag: DisposeBag

    // MARK: Object Lifecycle
    init(dbStorage: DbStorage, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        observable = PublishSubject()
        disposeBag = DisposeBag()
    }
    
    // MARK: Actions
    func setItems(_ items: [Item]) {
        DDLogInfo("OpenItemsController: setting items \(items)")
        guard items != self.items else { return }
        self.items = items
        observable.on(.next(items))
    }
    
    func open(_ kind: Item.Kind) {
        DDLogInfo("OpenItemsController: opened item \(kind)")
        if let index = items.firstIndex(where: { $0.kind == kind }) {
            items[index].lastOpened = .now
            DDLogInfo("OpenItemsController: already opened item \(kind) became most recent")
        } else {
            DDLogInfo("OpenItemsController: newly opened item \(kind) set as most recent")
            let item = Item(kind: kind, userIndex: items.count)
            items.append(item)
        }
        observable.on(.next(items))
    }
    
    @discardableResult
    func restore(_ item: Item, using presenter: OpenItemsPresenter) -> Bool {
        guard let presentation = loadPresentation(for: item) else { return false }
        presentItem(with: presentation, using: presenter)
        return true
    }
    
    @discardableResult
    func restoreMostRecentlyOpenedItem(using presenter: OpenItemsPresenter) -> Item? {
        // Will restore most recent opened item still present, or none if all fail
        DDLogInfo("OpenItemsController: restoring most recently opened item using presenter \(presenter)")
        var itemsChanged: Bool = false
        defer {
            if itemsChanged {
                observable.on(.next(items))
            }
        }
        var item: Item?
        var presentation: Presentation?
        let itemsSortedByLastOpen = itemsSortedByLastOpen
        for _item in itemsSortedByLastOpen {
            if let _presentation = loadPresentation(for: _item) {
                item = _item
                presentation = _presentation
                break
            }
            DDLogWarn("OpenItemsController: removing not loaded item \(_item)")
            items.removeAll(where: { $0 == _item })
            itemsChanged = true
        }
        guard let item, let presentation else { return nil }
        presentItem(with: presentation, using: presenter)
        return item
    }
    
    func deferredOpenItemsMenuElement(disableOpenItem: Bool, itemActionCallback: @escaping (Item, UIAction) -> Void) -> UIDeferredMenuElement {
        UIDeferredMenuElement { [weak self] elementProvider in
            guard let self else {
                elementProvider([])
                return
            }
            var actions: [UIAction] = []
            let openItem: Item? = disableOpenItem ? itemsSortedByLastOpen.first : nil
            let itemsSortedByUserOrder = itemsSortedByUserOrder
            var itemTuples: [(Item, RItem)] = []
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    for item in itemsSortedByUserOrder {
                        switch item.kind {
                        case .pdf(let libraryId, let key), .note(let libraryId, let key):
                            do {
                                let rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                                itemTuples.append((item, rItem))
                            } catch let itemError {
                                DDLogError("OpenItemsController: can't load item \(item) - \(itemError)")
                            }
                        }
                    }
                }
            } catch let error {
                DDLogError("OpenItemsController: can't load multiple items - \(error)")
            }
            for (item, rItem) in itemTuples {
                var attributes: UIMenuElement.Attributes = []
                var state: UIMenuElement.State = .off
                if item == openItem {
                    attributes = [.disabled]
                    state = .on
                }
                let itemAction = UIAction(title: rItem.displayTitle, attributes: attributes, state: state) { action in
                    itemActionCallback(item, action)
                }
                actions.append(itemAction)
            }
            elementProvider(actions)
        }
    }
    
    // MARK: Helper Methods
    private func loadPresentation(for item: Item) -> Presentation? {
        switch item.kind {
        case .pdf(let libraryId, let key):
            return loadPDFPresentation(key: key, libraryId: libraryId)

        case .note(let libraryId, let key):
            return loadNotePresentation(key: key, libraryId: libraryId)
        }

        func loadPDFPresentation(key: String, libraryId: LibraryIdentifier) -> Presentation? {
            var library: Library?
            var url: URL?
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                    let rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                    guard let attachment = AttachmentCreator.attachment(for: rItem, fileStorage: fileStorage, urlDetector: nil) else { return }
                    switch attachment.type {
                    case .file(let filename, let contentType, let location, _):
                        switch location {
                        case .local, .localAndChangedRemotely:
                            let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: contentType)
                            url = file.createUrl()

                        case .remote, .remoteMissing:
                            break
                        }

                    default:
                        break
                    }
                }
            } catch let error {
                DDLogError("OpenItemsController: can't load item \(item) - \(error)")
            }
            guard let library, let url else { return nil }
            return .pdf(library: library, key: key, url: url)
        }

        func loadNotePresentation(key: String, libraryId: LibraryIdentifier) -> Presentation? {
            var library: Library?
            var note: Note?
            var title: NoteEditorState.TitleData?
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                    let rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                    note = Note(item: rItem)
                    if let parent = rItem.parent {
                        title = NoteEditorState.TitleData(type: parent.rawType, title: parent.displayTitle)
                    }
                }
            } catch let error {
                DDLogError("OpenItemsController: can't load item \(item) - \(error)")
            }
            guard let library, let note else { return nil }
            return .note(library: library, key: note.key, text: note.text, tags: note.tags, title: title)
        }
    }

    private func presentItem(with presentation: Presentation, using presenter: OpenItemsPresenter) {
        presenter.showItem(with: presentation)
        DDLogInfo("OpenItemsController: presented item with presentation \(presentation)")
    }
}
