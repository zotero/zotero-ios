//
//  SetSpeechLanguageDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SetSpeechLanguageDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let language: String?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else { return }
        item.speechLanguage = language
    }
}
