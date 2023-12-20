//
//  RDownload.swift
//  Zotero
//
//  Created by Michal Rentka on 20.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RDownload: Object {
    @Persisted(indexed: true) var taskId: Int
    @Persisted(indexed: true) var key: String
    @Persisted var parentKey: String?
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?

    var libraryId: LibraryIdentifier? {
        get {
            guard !self.isInvalidated else { return nil }

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

