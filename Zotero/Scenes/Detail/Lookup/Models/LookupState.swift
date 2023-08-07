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
        case waitingInput
        case loadingIdentifiers
        case lookup([LookupData])
    }

    enum Error: Swift.Error, LocalizedError {
        case noIdentifiersDetectedAndNoLookupData
        case noIdentifiersDetectedWithLookupData
        
        var errorDescription: String? {
            switch self {
            case .noIdentifiersDetectedAndNoLookupData:
                return L10n.Errors.Lookup.noIdentifiersAndNoLookupData
                
            case .noIdentifiersDetectedWithLookupData:
                return L10n.Errors.Lookup.noIdentifiersWithLookupData
            }
        }
    }

    let collectionKeys: Set<String>
    let libraryId: LibraryIdentifier
    let restoreLookupState: Bool
    let hasDarkBackground: Bool

    var lookupState: State

    init(restoreLookupState: Bool, hasDarkBackground: Bool, collectionKeys: Set<String>, libraryId: LibraryIdentifier) {
        self.restoreLookupState = restoreLookupState
        self.collectionKeys = collectionKeys
        self.libraryId = libraryId
        self.lookupState = .waitingInput
        self.hasDarkBackground = hasDarkBackground
    }

    func cleanup() {}
}
