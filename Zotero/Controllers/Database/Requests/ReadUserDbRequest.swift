//
//  ReadUserDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadUserDbRequest: DbResponseRequest {
    typealias Response = RUser

    func process(in database: Realm) throws -> RUser {
        guard let user = database.objects(RUser.self).first else {
            throw DbError.objectNotFound
        }
        return user
    }
}
