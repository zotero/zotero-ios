//
//  LibraryScoped.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol LibraryScoped: AnyObject {
    var customLibraryKey: RCustomLibraryType? { get set }
    var groupKey: Int? { get set }
}

extension LibraryScoped where Self: Object {
    var libraryId: LibraryIdentifier? {
        get {
            guard !isInvalidated else { return nil }

            if let key = customLibraryKey {
                return .custom(key)
            }
            if let key = groupKey {
                return .group(key)
            }
            return nil
        }

        set {
            guard let identifier = newValue else {
                groupKey = nil
                customLibraryKey = nil
                return
            }

            switch identifier {
            case .custom(let type):
                customLibraryKey = type

            case .group(let id):
                groupKey = id
            }
        }
    }
}
