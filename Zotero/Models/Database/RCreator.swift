//
//  RCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RCreator: Object {
    @objc dynamic var rawType: String = ""
    @objc dynamic var firstName: String = ""
    @objc dynamic var lastName: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var orderId: Int = 0
    @objc dynamic var primary: Bool = false
    @objc dynamic var item: RItem?

    var summaryName: String {
        if !self.name.isEmpty {
            return self.name
        }

        if !self.lastName.isEmpty {
            return self.lastName
        }

        return self.firstName
    }
}
