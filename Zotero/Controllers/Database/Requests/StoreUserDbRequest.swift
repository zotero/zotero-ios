//
//  StoreUserDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreUserDbRequest: DbRequest {
    let identifier: Int
    let name: String

    var needsWrite: Bool { return true }

    init(loginResponse: LoginResponse) {
        self.identifier = loginResponse.userId
        self.name = loginResponse.name
    }

    func process(in database: Realm) throws {
        let user = RUser()
        user.identifier = self.identifier
        user.name = self.name
        database.add(user, update: true)
    }
}
