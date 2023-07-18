//
//  LookupState.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LookupState: ViewModelState {
    typealias LookupData = IdentifierLookupController.LookupData
    typealias TranslatedLookupData = LookupData.State.TranslatedLookupData

    enum State {
        case failed(Swift.Error)
        case loadingIdentifiers
        case lookup([LookupData])
    }

    enum Error: Swift.Error {
        case noIdentifiersDetected
    }

    let collectionKeys: Set<String>
    let libraryId: LibraryIdentifier
    // If enabled, when `lookup(identifier:)` is called, previous identifiers won't be removed.
    let multiLookupEnabled: Bool
    let hasDarkBackground: Bool

    var lookupState: State

    init(multiLookupEnabled: Bool, hasDarkBackground: Bool, collectionKeys: Set<String>, libraryId: LibraryIdentifier) {
        self.multiLookupEnabled = multiLookupEnabled
        self.collectionKeys = collectionKeys
        self.libraryId = libraryId
        self.lookupState = .loadingIdentifiers
        self.hasDarkBackground = hasDarkBackground
    }

    func cleanup() {}
}
