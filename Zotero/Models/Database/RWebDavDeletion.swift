//
//  RWebDavDeletion.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RWebDavDeletion: Object {
    @Persisted var key: String
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?

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
