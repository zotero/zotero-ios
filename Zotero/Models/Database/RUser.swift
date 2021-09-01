//
//  RUser.swift
//  Zotero
//
//  Created by Michal Rentka on 22/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RUser: Object {
    @Persisted(primaryKey: true) var identifier: Int
    @Persisted var name: String
    @Persisted var username: String
    @Persisted(originProperty: "createdBy") var createdBy: LinkingObjects<RItem>
    @Persisted(originProperty: "lastModifiedBy") var modifiedBy: LinkingObjects<RItem>
}
