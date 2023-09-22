//
//  OpenItemsController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 20/9/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
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
            case html(libraryId: LibraryIdentifier, key: String)
            case epub(libraryId: LibraryIdentifier, key: String)
            case note(libraryId: LibraryIdentifier, key: String)

            // MARK: Properties
            var libraryId: LibraryIdentifier {
                switch self {
                case .pdf(let libraryId, _), .note(let libraryId, _), .html(let libraryId, _), .epub(let libraryId, _):
                    return libraryId
                }
            }

            var key: String {
                switch self {
                case .pdf(_, let key), .note(_, let key), .html(_, let key), .epub(_, let key):
                    return key
                }
            }

            var icon: UIImage {
                switch self {
                case .pdf:
                    return Asset.Images.ItemTypes.pdf.image

                case .html:
                    return Asset.Images.ItemTypes.webPageSnapshot.image

                case .epub:
                    return Asset.Images.ItemTypes.epub.image

                case .note:
                    return Asset.Images.ItemTypes.note.image
                }
            }

            // MARK: Codable
            enum CodingKeys: CodingKey {
                case pdfKind
                case noteKind
                case epubKind
                case htmlKind
                case libraryId
                case key
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .pdf:
                    try container.encode(true, forKey: .pdfKind)

                case .epub:
                    try container.encode(true, forKey: .epubKind)

                case .html:
                    try container.encode(true, forKey: .htmlKind)

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
                } else if (try? container.decode(Bool.self, forKey: .epubKind)) == true {
                    self = .epub(libraryId: libraryId, key: key)
                } else if (try? container.decode(Bool.self, forKey: .htmlKind)) == true {
                    self = .html(libraryId: libraryId, key: key)
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
        case pdf(library: Library, key: String, parentKey: String?, url: URL, page: Int?, preselectedAnnotationKey: String?, previewRects: [CGRect]?)
        case html(library: Library, key: String, parentKey: String?, url: URL, preselectedAnnotationKey: String?)
        case epub(library: Library, key: String, parentKey: String?, url: URL, preselectedAnnotationKey: String?)
        case note(library: Library, key: String, text: String, tags: [Tag], parentTitleData: NoteEditorState.TitleData?, title: String)

        // MARK: Properties
        var isFileBased: Bool {
            switch self {
            case .pdf, .html, .epub:
                return true

            case .note:
                return false
            }
        }

        var library: Library {
            switch self {
            case .pdf(let library, _, _, _, _, _, _), .html(let library, _, _, _, _), .epub(let library, _, _, _, _), .note(let library, _, _, _, _, _):
                return library
            }
        }

        var key: String {
            switch self {
            case .pdf(_, let key, _, _, _, _, _), .html(_, let key, _, _, _), .epub(_, let key, _, _, _), .note(_, let key, _, _, _, _):
                return key
            }
        }

        var parentKey: String? {
            switch self {
            case .pdf(_, _, let parentKey, _, _, _, _), .html(_, _, let parentKey, _, _), .epub(_, _, let parentKey, _, _):
                return parentKey

            case .note:
                return nil
            }
        }

        var kind: Item.Kind {
            switch self {
            case .pdf:
                return .pdf(libraryId: library.identifier, key: key)
                
            case .html:
                return .html(libraryId: library.identifier, key: key)
                
            case .epub:
                return .epub(libraryId: library.identifier, key: key)
                
            case .note:
                return .note(libraryId: library.identifier, key: key)
            }
        }
    }

    // MARK: Properties
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let attachmentDownloader: AttachmentDownloader
    // TODO: Use a better data structure, such as an ordered set
    private var itemsBySessionIdentifier: [String: [Item]] = [:]
    private var sessionIdentifierByItemKind: [Item.Kind: String] = [:]
    private var itemsTokenBySessionIdentifier: [String: NotificationToken] = [:]
    private var observableBySessionIdentifier: [String: PublishSubject<[Item]>] = [:]
    private let disposeBag: DisposeBag
    private var downloadDisposeBag: DisposeBag?

    // MARK: Object Lifecycle
    init(dbStorage: DbStorage, fileStorage: FileStorage, attachmentDownloader: AttachmentDownloader) {
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.attachmentDownloader = attachmentDownloader
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

    func set(items: [Item], for sessionIdentifier: String, validate: Bool) {
        DDLogInfo("OpenItemsController: setting items \(items) for \(sessionIdentifier)")
        let existingItems = getItems(for: sessionIdentifier)
        var newItems = validate ? filterValidItems(items) : items
        if !FeatureGates.enabled.contains(.multipleOpenItems), newItems.count > 1 {
            newItems = Array(newItems[0..<1])
        }
        guard newItems != existingItems else { return }
        // Invalidate previous observer first.
        itemsTokenBySessionIdentifier[sessionIdentifier]?.invalidate()
        itemsTokenBySessionIdentifier[sessionIdentifier] = nil
        // Update itemsBySessionIdentifier.
        itemsBySessionIdentifier[sessionIdentifier] = newItems
        // Update sessionIdentifierByItemKind. Recompute for all session identifier, to remove any closed items.
        var newSessionIdentifierByItemKind: [Item.Kind: String] = [:]
        itemsBySessionIdentifier.forEach { (sessionIdentifier, items) in
            items.forEach { item in
                newSessionIdentifierByItemKind[item.kind] = sessionIdentifier
            }
        }
        sessionIdentifierByItemKind = newSessionIdentifierByItemKind
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
                let objects = try dbStorage.perform(request: ReadItemsWithKeysFromMultipleLibrariesDbRequest(keysByLibraryIdentifier: keysByLibraryIdentifier), on: .main)
                token = objects.observe { [weak self] changes in
                    switch changes {
                    case .initial:
                        break

                    case .update(_, let deletions, _, _):
                        if !deletions.isEmpty, let self {
                            // Observed items have been deleted, call setItems to validate and register new observer.
                            let existingItems = getItems(for: sessionIdentifier)
                            set(items: existingItems, for: sessionIdentifier, validate: true)
                        }

                    case .error(let error):
                        DDLogError("OpenItemsController: register observer error - \(error)")
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
        set(items: newItems, for: sessionIdentifier, validate: validate)
    }

    func sessionIdentifier(for kind: Item.Kind) -> String? {
        sessionIdentifierByItemKind[kind]
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
            set(items: newItems, for: sessionIdentifier, validate: false)
        }
    }

    func close(_ kind: Item.Kind, for sessionIdentifier: String) {
        DDLogInfo("OpenItemsController: closed open item \(kind) for \(sessionIdentifier)")
        var existingItems = itemsSortedByUserOrder(for: sessionIdentifier)
        guard let index = existingItems.firstIndex(where: { $0.kind == kind }) else {
            DDLogWarn("OpenItemsController: item was already closed")
            return
        }
        existingItems.remove(at: index)
        setItemsSortedByUserIndex(existingItems, for: sessionIdentifier, validate: false)
    }

    func move(_ kind: Item.Kind, to userIndex: Int, for sessionIdentifier: String) {
        DDLogInfo("OpenItemsController: moved open item \(kind) to user index \(userIndex) for \(sessionIdentifier)")
        var existingItems = itemsSortedByUserOrder(for: sessionIdentifier)
        let userIndex = min(existingItems.count, max(0, userIndex))
        guard let index = existingItems.firstIndex(where: { $0.kind == kind }) else {
            DDLogWarn("OpenItemsController: item was not open")
            return
        }
        existingItems.move(fromOffsets: IndexSet(integer: index), toOffset: userIndex)
        setItemsSortedByUserIndex(existingItems, for: sessionIdentifier, validate: false)
    }

    func restore(_ item: Item, using presenter: OpenItemsPresenter, completion: @escaping (Bool) -> Void) {
        loadPresentation(for: item.kind) { [weak presenter] presentation in
            guard let presenter, let presentation else {
                completion(false)
                return
            }
            presenter.showItem(with: presentation)
            DDLogInfo("OpenItemsController: presenter \(presenter) presented item with presentation \(presentation)")
            completion(true)
        }
    }
    
    func restoreMostRecentlyOpenedItem(using presenter: OpenItemsPresenter, sessionIdentifier: String, completion: @escaping (Item?) -> Void) {
        // Will restore most recent opened item still present, or none if all fail
        var existingItems = getItems(for: sessionIdentifier)
        DDLogInfo("OpenItemsController: restoring most recently opened item using presenter \(presenter) for \(sessionIdentifier)")
        let existingItemsSortedByLastOpen = itemsSortedByLastOpen(for: sessionIdentifier)
        loadFirstAvailablePresentation(from: existingItemsSortedByLastOpen, indexOffset: 0) { [weak self, weak presenter] item, presentation, foundIndex in
            if let self, foundIndex > 0 {
                for item in existingItemsSortedByLastOpen[0..<foundIndex] {
                    DDLogWarn("OpenItemsController: removing not loaded item \(item) for \(sessionIdentifier)")
                    existingItems.removeAll(where: { $0 == item })
                }
                // setItems will produce next observable event
                set(items: existingItems, for: sessionIdentifier, validate: false)
            }
            if let presenter {
                presenter.showItem(with: presentation)
                DDLogInfo("OpenItemsController: presenter \(presenter) presented item with presentation \(presentation ?? "<nil>")")
            }
            completion(item)
        }

        func loadFirstAvailablePresentation(from items: [Item], indexOffset: Int, completion: @escaping (Item?, Presentation?, Int) -> Void ) {
            guard !items.isEmpty else {
                completion(nil, nil, indexOffset)
                return
            }

            var remainingItems = items
            let currentItem = remainingItems.removeFirst()

            loadPresentation(for: currentItem.kind) { presentation in
                if let presentation {
                    completion(currentItem, presentation, indexOffset)
                } else {
                    loadFirstAvailablePresentation(from: remainingItems, indexOffset: indexOffset + 1, completion: completion)
                }
            }
        }
    }
    
    func deferredOpenItemsMenuElement(
        for sessionIdentifier: String,
        showMenuForCurrentItem: Bool,
        openItemPresenterProvider: @escaping () -> OpenItemsPresenter?,
        completion: @escaping (_ changedCurrentItem: Bool, _ openItemsChanged: Bool) -> Void
    ) -> UIDeferredMenuElement {
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
                        restoreMostRecentlyOpenedItem(using: presenter, sessionIdentifier: sessionIdentifier) { item in
                            if item == nil {
                                DDLogInfo("OpenItemsController: no open item to restore after close")
                            }
                            completion(true, true)
                        }
                    }
                    currentItemActions.append(closeAction)
                    if index > 0 {
                        let moveToTopAction = UIAction(title: L10n.Accessibility.Pdf.currentItemMoveToStart, image: .init(systemName: "arrowshape.up.circle")) { [weak self] _ in
                            guard let self else { return }
                            move(item.kind, to: 0, for: sessionIdentifier)
                            completion(false, true)
                        }
                        currentItemActions.append(moveToTopAction)
                    }
                    if index < itemsCount - 1 {
                        let moveToBottomAction = UIAction(title: L10n.Accessibility.Pdf.currentItemMoveToEnd, image: .init(systemName: "arrowshape.down.circle")) { [weak self] _ in
                            guard let self else { return }
                            move(item.kind, to: itemsCount, for: sessionIdentifier)
                            completion(false, true)
                        }
                        currentItemActions.append(moveToBottomAction)
                    }
                    if itemsCount > 1 {
                        let closeOtherAction = UIAction(title: L10n.Accessibility.Pdf.closeOtherOpenItems, image: .init(systemName: "checkmark.circle.badge.xmark")) { [weak self] _ in
                            guard let self else { return }
                            set(items: [item], for: sessionIdentifier, validate: false)
                            completion(false, true)
                        }
                        currentItemActions.append(closeOtherAction)
                    }
                    let currentItemMenu = UIMenu(title: L10n.Accessibility.Pdf.currentItem, options: [.displayInline], children: currentItemActions)
                    let currentItemElement = UIMenu(title: rItem.displayTitle, image: item.kind.icon, children: [currentItemMenu])
                    elements.append(currentItemElement)
                } else {
                    let itemAction = UIAction(title: rItem.displayTitle, image: item.kind.icon) { [weak self] _ in
                        guard let self, let presenter = openItemPresenterProvider() else { return }
                        restore(item, using: presenter) { restored in
                            completion(restored, false)
                        }
                    }
                    elements.append(itemAction)
                }
            }

            let closeAllAction = UIAction(title: L10n.Accessibility.Pdf.closeAllOpenItems, image: .init(systemName: "xmark.square")) { [weak self] _ in
                guard let self else { return }
                set(items: [], for: sessionIdentifier, validate: false)
                openItemPresenterProvider()?.showItem(with: nil)
                completion(true, true)
            }
            let closeAllElement = UIMenu(options: [.displayInline], children: [closeAllAction])
            elements.append(closeAllElement)

            elementProvider(elements)
        }
    }

    func loadPresentation(for key: String, libraryId: LibraryIdentifier, page: Int?, preselectedAnnotationKey: String?, previewRects: [CGRect]?, completion: @escaping (Presentation?) -> Void) {
        var library: Library?
        var rItem: RItem?
        do {
            try dbStorage.perform(on: .main) { coordinator in
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
                rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))
            }
        } catch let error {
            DDLogError("OpenItemsController: library (\(libraryId)) or item (\(key)) not found - \(error)")
        }
        guard let library, let rItem else {
            completion(nil)
            return
        }
        if let note = Note(item: rItem) {
            completion(createNotePresentation(library: library, rItem: rItem, note: note))
            return
        }
        guard let attachment = AttachmentCreator.attachment(for: rItem, fileStorage: fileStorage, urlDetector: nil) else {
            DDLogInfo("OpenItemsController: trying to create attachment for incorrect item type - \(rItem.rawType)")
            completion(nil)
            return
        }
        guard case .file(_, let contentType, _, _, _) = attachment.type else {
            DDLogInfo("OpenItemsController: trying to open invalid attachment type - \(attachment.type)")
            completion(nil)
            return
        }
        switch contentType {
        case "application/pdf":
            loadPresentation(
                for: .pdf(libraryId: libraryId, key: key),
                library: library,
                rItem: rItem,
                attachment: attachment,
                page: page,
                preselectedAnnotationKey: preselectedAnnotationKey,
                previewRects: previewRects,
                completion: completion
            )
            return

        case "text/html":
            if FeatureGates.enabled.contains(.htmlEpubReader) {
                loadPresentation(
                    for: .html(libraryId: libraryId, key: key),
                    library: library,
                    rItem: rItem,
                    attachment: attachment,
                    page: page,
                    preselectedAnnotationKey: preselectedAnnotationKey,
                    previewRects: previewRects,
                    completion: completion
                )
                return
            }

        case "application/epub+zip":
            if FeatureGates.enabled.contains(.htmlEpubReader) {
                loadPresentation(
                    for: .epub(libraryId: libraryId, key: key),
                    library: library,
                    rItem: rItem,
                    attachment: attachment,
                    page: page,
                    preselectedAnnotationKey: preselectedAnnotationKey,
                    previewRects: previewRects,
                    completion: completion
                )
                return
            }

        default:
            break
        }
        completion(nil)
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
                    case .pdf(let libraryId, let key), .html(let libraryId, let key), .epub(let libraryId, let key), .note(let libraryId, let key):
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

    private func loadPresentation(for itemKind: Item.Kind, completion: @escaping (Presentation?) -> Void) {
        var library: Library?
        var rItem: RItem?
        do {
            try dbStorage.perform(on: .main) { coordinator in
                library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: itemKind.libraryId))
                rItem = try coordinator.perform(request: ReadItemDbRequest(libraryId: itemKind.libraryId, key: itemKind.key))
            }
        } catch let error {
            DDLogError("OpenItemsController: item kind \(itemKind) not found - \(error)")
        }
        guard let library, let rItem else {
            completion(nil)
            return
        }
        loadPresentation(for: itemKind, library: library, rItem: rItem, attachment: nil, page: nil, preselectedAnnotationKey: nil, previewRects: nil, completion: completion)
    }

    private func loadPresentation(
        for itemKind: Item.Kind,
        library: Library,
        rItem: RItem,
        attachment: Attachment?,
        page: Int?,
        preselectedAnnotationKey: String?,
        previewRects: [CGRect]?,
        completion: @escaping (Presentation?) -> Void
    ) {
        switch itemKind {
        case .pdf, .html, .epub:
            guard let attachment = attachment ?? AttachmentCreator.attachment(for: rItem, fileStorage: fileStorage, urlDetector: nil) else {
                completion(nil)
                return
            }
            loadItemPresentation(
                kind: itemKind,
                library: library,
                rItem: rItem,
                attachment: attachment,
                page: page,
                preselectedAnnotationKey: preselectedAnnotationKey,
                previewRects: previewRects,
                completion: completion
            )

        case .note:
            completion(createNotePresentation(library: library, rItem: rItem))
        }

        func loadItemPresentation(
            kind: Item.Kind,
            library: Library,
            rItem: RItem,
            attachment: Attachment,
            page: Int?,
            preselectedAnnotationKey: String?,
            previewRects: [CGRect]?,
            completion: @escaping (Presentation?) -> Void
        ) {
            let libraryId = kind.libraryId
            let key = kind.key
            let parentKey = rItem.parent?.key
            switch attachment.type {
            case .file(let filename, let contentType, let location, _, _):
                switch location {
                case .local:
                    completion(createItemPresentation(
                        kind: kind,
                        parentKey: parentKey,
                        library: library,
                        filename: filename,
                        contentType: contentType,
                        page: page,
                        preselectedAnnotationKey: preselectedAnnotationKey,
                        previewRects: previewRects
                    ))

                case .localAndChangedRemotely, .remote:
                    let disposeBag = DisposeBag()
                    attachmentDownloader.observable
                        .observe(on: MainScheduler.instance)
                        .subscribe(onNext: { [weak self] update in
                            guard let self, update.libraryId == attachment.libraryId, update.key == attachment.key else { return }
                            switch update.kind {
                            case .ready:
                                completion(createItemPresentation(
                                    kind: kind,
                                    parentKey: parentKey,
                                    library: library,
                                    filename: filename,
                                    contentType: contentType,
                                    page: page,
                                    preselectedAnnotationKey: preselectedAnnotationKey,
                                    previewRects: previewRects
                                ))
                                downloadDisposeBag = nil

                            case .cancelled, .failed:
                                completion(nil)
                                downloadDisposeBag = nil

                            case .progress:
                                break
                            }
                        })
                        .disposed(by: disposeBag)
                    downloadDisposeBag = disposeBag
                    attachmentDownloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)

                case .remoteMissing:
                    DDLogError("OpenItemsController: can't load item (key: \(key), library: \(libraryId)) - remote missing")
                    completion(nil)
                }

            case .url:
                DDLogError("OpenItemsController: can't load item (key: \(key), library: \(libraryId)) - not a file attachment")
                completion(nil)
            }

            func createItemPresentation(
                kind: Item.Kind,
                parentKey: String?,
                library: Library,
                filename: String,
                contentType: String,
                page: Int?,
                preselectedAnnotationKey: String?,
                previewRects: [CGRect]?
            ) -> Presentation? {
                let file = Files.attachmentFile(in: library.identifier, key: kind.key, filename: filename, contentType: contentType)
                let url = file.createUrl()
                switch kind {
                case .pdf(_, let key):
                    return .pdf(library: library, key: key, parentKey: parentKey, url: url, page: page, preselectedAnnotationKey: preselectedAnnotationKey, previewRects: previewRects)

                case .html(_, let key):
                    return .html(library: library, key: key, parentKey: parentKey, url: url, preselectedAnnotationKey: preselectedAnnotationKey)

                case .epub(_, let key):
                    return .epub(library: library, key: key, parentKey: parentKey, url: url, preselectedAnnotationKey: preselectedAnnotationKey)

                case .note:
                    return nil
                }
            }
        }
    }

    private func createNotePresentation(library: Library, rItem: RItem, note: Note) -> Presentation? {
        let parentTitleData: NoteEditorState.TitleData? = rItem.parent.flatMap { .init(type: $0.rawType, title: $0.displayTitle) }
        return .note(library: library, key: note.key, text: note.text, tags: note.tags, parentTitleData: parentTitleData, title: note.title)
    }

    private func createNotePresentation(library: Library, rItem: RItem) -> Presentation? {
        return Note(item: rItem).flatMap { createNotePresentation(library: library, rItem: rItem, note: $0) }
    }
}

extension OpenItemsController {
    func openItemsUserActivity(for sessionIdentifier: String?, libraryId: LibraryIdentifier, collectionId: CollectionIdentifier? = nil) -> NSUserActivity {
        let items = sessionIdentifier.flatMap({ getItems(for: $0) }) ?? []
        return items.isEmpty ? .mainActivity(with: []) : .contentActivity(with: items, libraryId: libraryId, collectionId: collectionId ?? Defaults.shared.selectedCollectionId)
    }

    func setOpenItemsUserActivity(from viewController: UIViewController, libraryId: LibraryIdentifier, collectionId: CollectionIdentifier? = nil, title: String? = nil) {
        let activity = openItemsUserActivity(for: viewController.sessionIdentifier, libraryId: libraryId, collectionId: collectionId).set(title: title)
        viewController.set(userActivity: activity)
    }
}

extension UIImage {
    static func openItemsImage(count: Int) -> UIImage? {
        let count = max(0, count)
        return count <= 50 ? UIImage(systemName: "\(count).square") : UIImage(systemName: "square.grid.3x3.square")
    }
}

extension UIBarButtonItem {
    static func openItemsBarButtonItem() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(image: .openItemsImage(count: 0), style: .plain, target: nil, action: nil)
        barButtonItem.isEnabled = true
        barButtonItem.accessibilityLabel = L10n.Accessibility.Pdf.openItems
        barButtonItem.title = L10n.Accessibility.Pdf.openItems
        return barButtonItem
    }
}
