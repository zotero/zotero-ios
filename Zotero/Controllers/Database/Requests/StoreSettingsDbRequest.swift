//
//  StoreSettingsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreSettingsDbRequest: DbRequest {
    let response: SettingsResponse
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let colors = self.response.tagColors else { return }

        let libraryObject = try database.autocreatedLibraryObject(forPrimaryKey: self.libraryId).1

        let allTags = database.objects(RTag.self)
        
        colors.value.forEach { tagColor in
            let tag: RTag
            if let existing = allTags.filter(.name(tagColor.name, in: self.libraryId)).first {
                tag = existing
            } else {
                tag = RTag()
                database.add(tag)
                tag.name = tagColor.name
                tag.libraryObject = libraryObject
            }
            tag.color = tagColor.color
        }
    }
}
