//
//  RAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RAnnotation: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var rawType: Int = 0
    @objc dynamic var page: Int = 0
    @objc dynamic var pageLabel: String = ""
    @objc dynamic var author: String = ""
    @objc dynamic var isAuthor: Bool = false
    @objc dynamic var color: String = ""
    @objc dynamic var comment: String = ""
    @objc dynamic var text: String? = nil
    @objc dynamic var isLocked: Bool = false
    @objc dynamic var sortIndex: String = ""
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var item: RItem?

    let rects: List<RRect> = List()
    let tags = LinkingObjects(fromType: RTag.self, property: "annotations")

    // MARK: - Object properties

    override class func indexedProperties() -> [String] {
        return ["key"]
    }
}
