//
//  RLibrary.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum RCustomLibraryType: Int, Codable, PersistableEnum, _PrimaryKey {
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
    @Persisted(primaryKey: true) var type: RCustomLibraryType = .myLibrary
    @Persisted var orderId: Int = 0
    @Persisted var versions: RVersions?
    @Persisted var fileSyncType: LibraryFileSyncType = .asNeeded
}
