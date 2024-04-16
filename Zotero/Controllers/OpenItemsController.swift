//
//  OpenItemsController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 20/9/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import RxSwift
import RealmSwift
import CocoaLumberjackSwift

typealias OpenItem = OpenItemsController.Item
typealias ItemPresentation = OpenItemsController.Presentation

protocol OpenItemsPresenter: AnyObject {
    func showItem(with presentation: ItemPresentation?)
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

            var icon: UIImage {
                switch self {
                case .pdf:
                    return Asset.Images.ItemTypes.pdf.image

                case .note:
                    return Asset.Images.ItemTypes.note.image
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
        case pdf(library: Library, key: String, parentKey: String?, url: URL)
        case note(library: Library, key: String, text: String, tags: [Tag], title: NoteEditorState.TitleData?)
    }
    
    // MARK: Properties
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    // TODO: Use a better data structure, such as an ordered set
    private var itemsBySessionIdentifier: [String: [Item]] = [:]
    private var itemsTokenBySessionIdentifier: [String: NotificationToken] = [:]
    private var observableBySessionIdentifier: [String: PublishSubject<[Item]>] = [:]
    private let disposeBag: DisposeBag

    // MARK: Object Lifecycle
    init(dbStorage: DbStorage, fileStorage: FileStorage) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        disposeBag = DisposeBag()
    }
    
    // MARK: Actions
    func observable(for sessionIdentifier: String) -> PublishSubject<[Item]> {
        if let observable = observableBySessionIdentifier[sessionIdentifier] {
            return observable
        }
        let observable = PublishSubject<[Item]>()
        observableBySessionIdentifier[sessionIdentifier] = observable
        return observable
    }

    func getItems(for sessionIdentifier: String) -> [Item] {
        itemsBySessionIdentifier[sessionIdentifier, default: []]
    }

    func setItems(_ items: [Item], for sessionIdentifier: String, validate: Bool) {
        DDLogInfo("OpenItemsController: setting items \(items) for \(sessionIdentifier)")
        let existingItems = getItems(for: sessionIdentifier)
        let newItems = validate ? filterValidItems(items) : items
        guard newItems != existingItems else { return }
        // Invalidate previous observer first.
        itemsTokenBySessionIdentifier[sessionIdentifier]?.invalidate()
        itemsTokenBySessionIdentifier[sessionIdentifier] = nil
        itemsBySessionIdentifier[sessionIdentifier] = newItems
        // Register observer for newly set items.
        itemsTokenBySessionIdentifier[sessionIdentifier] = registerObserver(for: newItems)
        observable(for: sessionIdentifier).on(.next(newItems))

        func registerObserver(for items: [Item]) -> NotificationToken? {
            var token: NotificationToken?
            var keysByLibraryIdentifier: [LibraryIdentifier: Set<String>] = [:]
            for item in items {
                let libraryId = item.kind.libraryId
                let key = item.kind.key
                var keys = keysByLibraryIdentifier[libraryId, default: .init()]
                keys.insert(key)
                keysByLibraryIdentifier[libraryId] = keys
            }
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    let objects = try coordinator.perform(request: ReadItemsWithKeysFromMultipleLibrariesDbRequest(keysByLibraryIdentifier: keysByLibraryIdentifier))
                    token = objects.observe { [weak self] changes in
                        switch changes {
                        case .initial:
                            break

                        case .update(_, let deletions, _, _):
                            if !deletions.isEmpty, let self {
                                // Observed items have been deleted, call setItems to validate and register new observer.
                                let existingItems = getItems(for: sessionIdentifier)
                                setItems(existingItems, for: sessionIdentifier, validate: true)
                            }

                        case .error(let error):
                            DDLogError("OpenItemsController: register observer error - \(error)")
                        }
                    }
                }
            } catch let error {
                DDLogError("OpenItemsController: can't register items observer - \(error)")
            }
            return token
        }
    }

    private func setItemsSortedByUserIndex(_ items: [Item], for sessionIdentifier: String, validate: Bool) {
        var newItems = items
        for i in 0..<newItems.count {
            newItems[i].userIndex = i
        }
        setItems(newItems, for: sessionIdentifier, validate: validate)
    }

    func open(_ kind: Item.Kind, for sessionIdentifier: String) {
        DDLogInfo("OpenItemsController: opened item \(kind) for \(sessionIdentifier)")
        var existingItems = getItems(for: sessionIdentifier)
        if let index = existingItems.firstIndex(where: { $0.kind == kind }) {
            existingItems[index].lastOpened = .now
            // No need to call setItems, to register a new items observer, as only items metadata were updated.
            itemsBySessionIdentifier[sessionIdentifier] = existingItems
            DDLogInfo("OpenItemsController: already opened item \(kind) became most recent for \(sessionIdentifier)")
            observable(for: sessionIdentifier).on(.next(existingItems))
        } else {
            DDLogInfo("OpenItemsController: newly opened item \(kind) set as most recent for \(sessionIdentifier)")
            let item = Item(kind: kind, userIndex: existingItems.count)
            let newItems = existingItems + [item]
            // setItems will produce next observable event
            setItems(newItems, for: sessionIdentifier, validate: false)
        }
    }

    func close(_ kind: Item.Kind, for sessionIdentifier: String) {
        DDLogInfo("OpenItemsController: closed open item \(kind) for \(sessionIdentifier)")
        var existingItems = itemsSortedByUserOrder(for: sessionIdentifier)
        if let index = existingItems.firstIndex(where: { $0.kind == kind }) {
            existingItems.remove(at: index)
            setItemsSortedByUserIndex(existingItems, for: sessionIdentifier, validate: false)
        } else {
            DDLogWarn("OpenItemsController: item was already closed")
        }
    }

    func move(_ kind: Item.Kind, to userIndex: Int, for sessionIdentifier: String) {
        DDLogInfo("OpenItemsController: moved open item \(kind) to user index \(userIndex) for \(sessionIdentifier)")
        var existingItems = itemsSortedByUserOrder(for: sessionIdentifier)
        let userIndex = min(existingItems.count, max(0, userIndex))
        if let index = existingItems.firstIndex(where: { $0.kind == kind }) {
            existingItems.move(fromOffsets: IndexSet(integer: index), toOffset: userIndex)
            setItemsSortedByUserIndex(existingItems, for: sessionIdentifier, validate: false)
        } else {
            DDLogWarn("OpenItemsController: item was not open")
        }
    }

    @discardableResult
    func restore(_ item: Item, using presenter: OpenItemsPresenter) -> Bool {
        guard let presentation = loadPresentation(for: item) else { return false }
        presentItem(with: presentation, using: presenter)
        return true
    }
    
    @discardableResult
    func restoreMostRecentlyOpenedItem(using presenter: OpenItemsPresenter, sessionIdentifier: String) -> Item? {
        // Will restore most recent opened item still present, or none if all fail
        var existingItems = getItems(for: sessionIdentifier)
        DDLogInfo("OpenItemsController: restoring most recently opened item using presenter \(presenter) for \(sessionIdentifier)")
        var itemsChanged: Bool = false
        defer {
            if itemsChanged {
                // setItems will produce next observable event
                setItems(existingItems, for: sessionIdentifier, validate: false)
            }
        }
        var item: Item?
        var presentation: Presentation?
        let existingItemsSortedByLastOpen = itemsSortedByLastOpen(for: sessionIdentifier)
        for _item in existingItemsSortedByLastOpen {
            if let _presentation = loadPresentation(for: _item) {
                item = _item
                presentation = _presentation
                break
            }
            DDLogWarn("OpenItemsController: removing not loaded item \(_item) for \(sessionIdentifier)")
            existingItems.removeAll(where: { $0 == _item })
            itemsChanged = true
        }
        guard let item, let presentation else { return nil }
        presentItem(with: presentation, using: presenter)
        return item
    }
    
    func deferredOpenItemsMenuElement(for sessionIdentifier: String, showMenuForCurrentItem: Bool, openItemPresenterProvider: @escaping () -> OpenItemsPresenter?) -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { [weak self] elementProvider in
            guard let self else {
                elementProvider([])
                return
            }
            var elements: [UIMenuElement] = []
            let openItem: Item? = showMenuForCurrentItem ? itemsSortedByLastOpen(for: sessionIdentifier).first : nil
            let existingItemsSortedByLastOpen = itemsSortedByUserOrder(for: sessionIdentifier)
            let itemTuples: [(Item, RItem)] = filterValidItemsWithRItem(existingItemsSortedByLastOpen)
            let itemsCount = itemTuples.count
            for (index, (item, rItem)) in itemTuples.enumerated() {
                if item == openItem {
                    var currentItemActions: [UIAction] = []
                    let closeAction = UIAction(title: L10n.Accessibility.Pdf.currentItemClose, image: .init(systemName: "xmark.circle")) { [weak self] _ in
                        guard let self else { return }
                        close(item.kind, for: sessionIdentifier)
                        guard let presenter = openItemPresenterProvider() else { return }
                        if restoreMostRecentlyOpenedItem(using: presenter, sessionIdentifier: sessionIdentifier) == nil {
                            DDLogInfo("OpenItemsController: no open item to restore after close")
                            presenter.showItem(with: nil)
                        }
                    }
                    currentItemActions.append(closeAction)
                    if index > 0 {
                        let moveToTopAction = UIAction(title: L10n.Accessibility.Pdf.currentItemMoveFirst, image: .init(systemName: "arrowshape.up.circle")) { [weak self] _ in
                            guard let self else { return }
                            move(item.kind, to: 0, for: sessionIdentifier)
                        }
                        currentItemActions.append(moveToTopAction)
                    }
                    if index < itemsCount - 1 {
                        let moveToBottomAction = UIAction(title: L10n.Accessibility.Pdf.currentItemMoveLast, image: .init(systemName: "arrowshape.down.circle")) { [weak self] _ in
                            guard let self else { return }
                            move(item.kind, to: itemsCount, for: sessionIdentifier)
                        }
                        currentItemActions.append(moveToBottomAction)
                    }
                    if itemsCount > 1 {
                        let closeOtherAction = UIAction(title: L10n.Accessibility.Pdf.closeOtherOpenItems, image: .init(systemName: "checkmark.circle.badge.xmark")) { [weak self] _ in
                            self?.setItems([item], for: sessionIdentifier, validate: false)
                        }
                        currentItemActions.append(closeOtherAction)
                    }
                    let currentItemMenu = UIMenu(title: L10n.Accessibility.Pdf.currentItem, options: [.displayInline], children: currentItemActions)
                    let currentItemElement = UIMenu(title: rItem.displayTitle, image: item.kind.icon, children: [currentItemMenu])
                    elements.append(currentItemElement)
                } else {
                    let itemAction = UIAction(title: rItem.displayTitle, image: item.kind.icon) { [weak self] _ in
                        guard let self, let presenter = openItemPresenterProvider() else { return }
                        restore(item, using: presenter)
                    }
                    elements.append(itemAction)
                }
            }

            let closeAllAction = UIAction(title: L10n.Accessibility.Pdf.closeAllOpenItems, image: .init(systemName: "xmark.square")) { [weak self] _ in
                guard let self else { return }
                setItems([], for: sessionIdentifier, validate: false)
                openItemPresenterProvider()?.showItem(with: nil)
            }
            let closeAllElement = UIMenu(options: [.displayInline], children: [closeAllAction])
            elements.append(closeAllElement)

            elementProvider(elements)
        }
    }
    
    // MARK: Helper Methods
    private func itemsSortedByUserOrder(for sessionIdentifier: String) -> [Item] {
        getItems(for: sessionIdentifier).sorted(by: { $0.userIndex < $1.userIndex })
    }

    private func itemsSortedByLastOpen(for sessionIdentifier: String) -> [Item] {
        getItems(for: sessionIdentifier).sorted(by: { $0.lastOpened > $1.lastOpened })
    }

    private func filterValidItemsWithRItem(_ items: [Item]) -> [(Item, RItem)] {
        var itemTuples: [(Item, RItem)] = []
        do {
            try dbStorage.perform(on: .main) { coordinator in
                for item in items {
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
        return itemTuples
    }

    private func filterValidItems(_ items: [Item]) -> [Item] {
        filterValidItemsWithRItem(items).map { $0.0 }
    }

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
            var parentKey: String?
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                    let rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
                    parentKey = rItem.parent?.key
                    guard let attachment = AttachmentCreator.attachment(for: rItem, fileStorage: fileStorage, urlDetector: nil) else { return }
                    switch attachment.type {
                    case .file(let filename, let contentType, let location, _, _):
                        switch location {
                        case .local, .localAndChangedRemotely:
                            let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: contentType)
                            url = file.createUrl()

                        case .remote, .remoteMissing:
                            break
                        }

                    case .url:
                        break
                    }
                }
            } catch let error {
                DDLogError("OpenItemsController: can't load item \(item) - \(error)")
            }
            guard let library, let url else { return nil }
            return .pdf(library: library, key: key, parentKey: parentKey, url: url)
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

extension OpenItemsController {
    func setOpenItemsUserActivity(from viewController: UIViewController, libraryId: LibraryIdentifier, collectionId: CollectionIdentifier? = nil, title: String? = nil) {
        guard let sessionIdentifier = viewController.view.scene?.session.persistentIdentifier else { return }
        let activity: NSUserActivity = .pdfActivity(with: getItems(for: sessionIdentifier), libraryId: libraryId, collectionId: collectionId ?? Defaults.shared.selectedCollectionId).set(title: title)
        viewController.set(userActivity: activity)
    }
}
