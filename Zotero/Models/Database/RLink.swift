//
//  RLink.swift
//  Zotero
//
//  Created by Michal Rentka on 09/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RLink: Object {
    @objc dynamic var type: String = ""
    @objc dynamic var href: String = ""
    @objc dynamic var contentType: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var length: Int = 0
    @objc dynamic var item: RItem?

    var linkType: LinkType? {
        return LinkType(rawValue: self.type)
    }
}
