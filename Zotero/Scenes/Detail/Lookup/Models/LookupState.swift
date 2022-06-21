//
//  LookupState.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LookupState: ViewModelState {
    struct LookupData {
        enum State {
            case enqueued
            case inProgress
            case failed
            case translated(TranslatedLookupData)
        }

        let identifier: String
        let state: State
    }

    struct TranslatedLookupData {
        let response: ItemResponse
        let attachments: [(Attachment, URL)]
    }

    enum State {
        case input
        case failed(Error?)
        case lookup([LookupData])
    }

    let initialText: String?
    let collectionKeys: Set<String>
    let libraryId: LibraryIdentifier

    var state: State
    var scannedText: String?

    init(initialText: String?, collectionKeys: Set<String>, libraryId: LibraryIdentifier) {
        self.initialText = initialText
        self.collectionKeys = collectionKeys
        self.libraryId = libraryId
        self.state = initialText == nil ? .input : .lookup([])
    }

    mutating func cleanup() {
        self.scannedText = nil
    }
}
