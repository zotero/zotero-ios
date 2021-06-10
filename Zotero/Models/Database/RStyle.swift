//
//  RStyle.swift
//  Zotero
//
//  Created by Michal Rentka on 18.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RStyle: Object {
    @objc dynamic var identifier: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var href: String = ""
    @objc dynamic var updated: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var filename: String = ""
    @objc dynamic var dependency: RStyle?
    @objc dynamic var installed: Bool = false

    let dependent = LinkingObjects(fromType: RStyle.self, property: "dependency")

    // MARK: - Object properties

    override class func primaryKey() -> String? {
        return "identifier"
    }
}

extension RStyle: Identifiable {
    var id: String { return self.identifier }
}
