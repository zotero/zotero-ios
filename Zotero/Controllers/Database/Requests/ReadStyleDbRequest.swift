//
//  ReadStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadStyleDbRequest: DbResponseRequest {
    typealias Response = RStyle

    let identifier: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RStyle {
        guard let style = database.object(ofType: RStyle.self, forPrimaryKey: self.identifier) else {
            throw DbError.objectNotFound
        }
        return style
    }
}
