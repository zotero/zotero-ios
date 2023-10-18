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

protocol OpenItemsPresenter: AnyObject {
    func showPDF(at url: URL, key: String, library: Library)
}

final class OpenItemsController {
    // MARK: Types
    enum Item: Hashable, Equatable, Codable {
        case pdf(libraryId: LibraryIdentifier, key: String)
        
        // MARK: Types
        enum ItemType: String, Codable {
            case pdf
        }
        
        // MARK: Properties
        var key: String {
            switch self {
            case .pdf(_, let key):
                return key
            }
        }
        
        var type: ItemType {
            switch self {
            case .pdf:
                return .pdf
            }
        }
        
        // MARK: Codable
        enum CodingKeys: CodingKey {
            case type
            case libraryId
            case key
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            switch self {
            case .pdf(let libraryId, let key):
                try container.encode(libraryId, forKey: .libraryId)
                try container.encode(key, forKey: .key)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ItemType.self, forKey: .type)

            switch type {
            case .pdf:
                let libraryId = try container.decode(LibraryIdentifier.self, forKey: .libraryId)
                let key = try container.decode(String.self, forKey: .key)
                self = .pdf(libraryId: libraryId, key: key)
            }
        }
    }
    
    // MARK: Properties
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    // TODO: Use a better data structure, such as an ordered set
    // TODO: Keep track of user sorted items (for presentation), possibly in a separate list
    // Items are sorted by most recently opened
    private(set) var items: [Item] = []
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
    
    func open(_ item: Item) {
        DDLogInfo("OpenItemsController: opened item \(item)")
        guard items.last != item else { return }
        // Since item not last, will certainly need to be appended in the end
        if let index = items.firstIndex(of: item) {
            // Item already open, remove it to be appended
            items.remove(at: index)
            DDLogInfo("OpenItemsController: moving already opened item \(item) to most recent")
        } else {
            DDLogInfo("OpenItemsController: appending newly opened item \(item) as most recent")
        }
        items.append(item)
        observable.on(.next(items))
    }
    
    @discardableResult
    func restore(_ item: Item, using presenter: OpenItemsPresenter) -> Bool {
        guard let (library, url) = load(item: item) else { return false }
        presentItem(item, at: url, library: library, using: presenter)
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
        var library: Library?
        var url: URL?
        while let _item = items.last {
            if let (_library, _url) = load(item: _item) {
                item = _item
                library = _library
                url = _url
                break
            }
            DDLogWarn("OpenItemsController: removing not loaded item \(_item)")
            _ = items.removeLast()
            itemsChanged = true
        }
        guard let item, let library, let url else { return nil }
        presentItem(item, at: url, library: library, using: presenter)
        return item
    }
    
    func deferredOpenItemsMenuElement(disableOpenItem: Bool, itemActionCallback: @escaping (Item, UIAction) -> Void) -> UIDeferredMenuElement {
        UIDeferredMenuElement { [weak self] elementProvider in
            guard let self else {
                elementProvider([])
                return
            }
            var actions: [UIAction] = []
            let items = self.items
            let openItem: Item? = disableOpenItem ? items.last : nil
            var itemTuples: [(Item, RItem)] = []
            do {
                try dbStorage.perform(on: .main) { coordinator in
                    for item in items {
                        do {
                            let rItem = try coordinator.perform(request: ReadItemGloballyDbRequest(key: item.key))
                            itemTuples.append((item, rItem))
                        } catch let itemError {
                            DDLogError("OpenItemsController: can't load globally item \(item) - \(itemError)")
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
    private func load(item: Item) -> (Library, URL)? {
        switch item {
        case .pdf(let libraryId, let key):
            return loadPDFItem(key: key, libraryId: libraryId)
        }
        
        func loadPDFItem(key: String, libraryId: LibraryIdentifier) -> (Library, URL)? {
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
            return (library, url)
        }
    }
    
    private func presentItem(_ item: Item, at url: URL, library: Library, using presenter: OpenItemsPresenter) {
        switch item {
        case .pdf(_, let key):
            presenter.showPDF(at: url, key: key, library: library)
        }
        DDLogInfo("OpenItemsController: presented item \(item) at URL \(url)")
    }
}
