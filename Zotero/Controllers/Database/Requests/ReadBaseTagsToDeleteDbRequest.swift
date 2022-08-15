//
//  ReadBaseTagsToDeleteDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadBaseTagsToDeleteDbRequest<Collection: RealmCollection>: DbResponseRequest where Collection.Element == RTypedTag {
    typealias Response = [String]

    var needsWrite: Bool { return false }

    let fromTags: Collection

    func process(in database: Realm) throws -> [String] {
        return Array(self.fromTags.filter(.baseTagsToDelete).compactMap({ $0.tag?.name }))
    }
}
