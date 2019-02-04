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
    typealias Response = RUser?

    func process(in database: Realm) -> RUser? {
        return database.objects(RUser.self).first
    }
}
