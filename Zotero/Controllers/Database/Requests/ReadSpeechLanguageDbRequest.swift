//
//  ReadSpeechLanguageDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadSpeechLanguageDbRequest: DbResponseRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> String? {
        if let language = database.objects(RItem.self).filter(.key(key, in: libraryId)).first?.speechLanguage, !language.isEmpty {
            return language
        }
        return nil
    }
}
