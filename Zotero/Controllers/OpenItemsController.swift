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
    enum Item: Hashable, Equatable {
        case pdf(library: Library, key: String)
    }
    
    // MARK: Properties
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    // TODO: Use a better data structure, such as an ordered set
    // TODO: Keep track of user sorted items (for presentation), possibly in a separate list
    // Items are sorted by most recently opened
    private(set) var items: [Item] = []
    private var collection: Collection?
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
    func open(_ item: Item, in collection: Collection) {
        DDLogInfo("OpenItemsController: opened item \(item) in collection \(collection)")
        self.collection = collection
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
        DDLogInfo("OpenItemsController: opened item \(item) in collection \(collection)")
        observable.on(.next(items))
    }
    
    func restoreMostRecentlyOpenedItem(using presenter: OpenItemsPresenter) {
        // Will restore most recent opened item still present, or none if all fail
        DDLogInfo("OpenItemsController: restoring last opened item using presenter \(presenter)")
        var itemsChanged: Bool = false
        defer {
            if itemsChanged {
                observable.on(.next(items))
            }
        }
        var item: Item?
        var url: URL?
        while let _item = items.last {
            if let _url = load(item: _item) {
                item = _item
                url = _url
                break
            }
            DDLogWarn("OpenItemsController: removing not loaded item \(_item)")
            _ = items.removeLast()
            itemsChanged = true
        }
        guard let item, let url else { return }
        switch item {
        case .pdf(let library, let key):
            presenter.showPDF(at: url, key: key, library: library)
        }
        DDLogInfo("OpenItemsController: restored item \(item) with URL \(url)")
    }
    
    // MARK: Helper Methods
    private func load(item: Item) -> URL? {
        var url: URL?
        
        switch item {
        case .pdf(let library, let key):
            url = loadPDFItem(key: key, libraryId: library.identifier)
        }
        
        return url
        
        func loadPDFItem(key: String, libraryId: LibraryIdentifier) -> URL? {
            var url: URL?
            do {
                try dbStorage.perform(on: .main) { coordinator in
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
            return url
        }
    }
}
