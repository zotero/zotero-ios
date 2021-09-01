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
    @Persisted var rawType: String
    @Persisted var firstName: String
    @Persisted var lastName: String
    @Persisted var name: String
    @Persisted var orderId: Int
    @Persisted var primary: Bool
    @Persisted var item: RItem?

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
