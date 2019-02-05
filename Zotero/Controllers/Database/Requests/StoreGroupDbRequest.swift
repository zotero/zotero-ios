//
//  StoreGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreGroupDbRequest: DbRequest {
    let response: GroupResponse

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let group = try database.autocreatedObject(ofType: RGroup.self, forPrimaryKey: self.response.identifier)
        group.name = self.response.data.name
        group.desc = self.response.data.description
        group.owner = self.response.data.owner
        group.type = self.response.data.type
        group.libraryReading = self.response.data.libraryReading
        group.libraryEditing = self.response.data.libraryEditing
        group.fileEditing = self.response.data.fileEditing
        group.version = self.response.version
    }
}
