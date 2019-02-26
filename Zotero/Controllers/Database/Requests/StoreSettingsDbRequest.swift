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
    let libraryId: Int

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let colors = self.response.tagColors else { return }
        let library = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: self.libraryId).1
        let allTags = database.objects(RTag.self)
        
        colors.value.forEach { tagColor in
            let tag: RTag
            if let existing = allTags.filter("library.identifier = %d AND name = %@", self.libraryId,
                                                                                      tagColor.name).first {
                tag = existing
            } else {
                tag = RTag()
                database.add(tag)
                tag.name = tagColor.name
                tag.library = library
            }
            tag.color = tagColor.color
        }
    }
}
