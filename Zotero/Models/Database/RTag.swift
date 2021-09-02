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
    enum Kind: Int, PersistableEnum {
        case automatic = 1
        case manual = 0
    }

    @Persisted var type: Kind
    @Persisted var tag: RTag?
    @Persisted var item: RItem?
}

final class RTag: Object {
    @Persisted(indexed: true) var name: String
    @Persisted var color: String
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?
    @Persisted(originProperty: "tag") var tags: LinkingObjects<RTypedTag>

    // MARK: - Sync properties

    var libraryId: LibraryIdentifier? {
        get {
            if let key = self.customLibraryKey {
                return .custom(key)
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
                self.customLibraryKey = type
            case .group(let id):
                self.groupKey = id
            }
        }
    }
}
