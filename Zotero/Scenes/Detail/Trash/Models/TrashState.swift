//
//  TrashState.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import OrderedCollections

import RealmSwift

struct TrashState: ViewModelState {
    enum Error: Swift.Error {
        case dataLoading
    }

    var library: Library
    var libraryToken: NotificationToken?
    var itemResults: Results<RItem>?
    var itemsToken: NotificationToken?
    var collectionResults: Results<RCollection>?
    var collectionsToken: NotificationToken?
    var objects: OrderedDictionary<TrashKey, TrashObject>
    var error: Error?

    init(libraryId: LibraryIdentifier) {
        objects = [:]

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    mutating func cleanup() {
        error = nil
    }
}
