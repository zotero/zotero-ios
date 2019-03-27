//
//  RLibrary.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum RCustomLibraryType: Int {
    case myLibrary
}

extension RCustomLibraryType {
    var libraryName: String {
        switch self {
        case .myLibrary:
            return "My Library"
        }
    }
}

class RCustomLibrary: Object {
    @objc dynamic var rawType: Int = 0
    @objc dynamic var orderId: Int = 0
    @objc dynamic var versions: RVersions?

    var type: RCustomLibraryType {
        return RCustomLibraryType(rawValue: self.rawType) ?? .myLibrary
    }

    let collections = LinkingObjects(fromType: RCollection.self, property: "customLibrary")
    let items = LinkingObjects(fromType: RItem.self, property: "customLibrary")
    let searches = LinkingObjects(fromType: RSearch.self, property: "customLibrary")
    let tags = LinkingObjects(fromType: RTag.self, property: "customLibrary")

    override class func primaryKey() -> String? {
        return "rawType"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }
}
