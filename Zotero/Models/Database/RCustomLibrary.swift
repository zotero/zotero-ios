//
//  RLibrary.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum RCustomLibraryType: Int, Codable {
    case myLibrary
}

extension RCustomLibraryType {
    var libraryName: String {
        switch self {
        case .myLibrary:
            return L10n.Libraries.myLibrary
        }
    }
}

final class RCustomLibrary: Object {
    @objc dynamic var rawType: Int = 0
    @objc dynamic var orderId: Int = 0
    @objc dynamic var versions: RVersions?

    override class func primaryKey() -> String? {
        return "rawType"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }

    var type: RCustomLibraryType {
        return RCustomLibraryType(rawValue: self.rawType) ?? .myLibrary
    }
}
