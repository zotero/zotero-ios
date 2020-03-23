//
//  RTranslatorMetadata.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RTranslatorMetadata: Object {
    @objc dynamic var id: String = ""
    @objc dynamic var label: String = ""
    @objc dynamic var filename: String = ""
    @objc dynamic var lastUpdated: Date = Date(timeIntervalSince1970: 0)

    // MARK: - Object properties

    override class func primaryKey() -> String? {
        return "id"
    }
}
