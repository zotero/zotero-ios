//
//  RTag.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RTypedTag: Object {
    enum Kind: Int {
        case automatic = 1
        case manual = 0
    }

    @Persisted var rawType: Int
    @Persisted var tag: RTag?
    @Persisted var item: RItem?

    var type: Kind {
        get {
            return Kind(rawValue: self.rawType) ?? .manual
        }

        set {
            self.rawType = newValue.rawValue
        }
    }
}

final class RTag: Object {
    @Persisted(indexed: true) var name: String
    @Persisted var color: String
    @Persisted var customLibraryKey: Int?
    @Persisted var groupKey: Int?
    @Persisted(originProperty: "tag") var tags: LinkingObjects<RTypedTag>

    // MARK: - Sync properties

    var libraryId: LibraryIdentifier? {
        get {
            if let key = self.customLibraryKey, let type = RCustomLibraryType(rawValue: key) {
                return .custom(type)
            }
            if let key = self.groupKey {
                return .group(key)
            }
            return nil
        }

        set {
            guard let identifier = newValue else {
                self.groupKey = nil
                self.customLibraryKey = nil
                return
            }

            switch identifier {
            case .custom(let type):
                self.customLibraryKey = type.rawValue
            case .group(let id):
                self.groupKey = id
            }
        }
    }
}
