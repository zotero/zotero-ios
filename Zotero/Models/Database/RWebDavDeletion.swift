//
//  RWebDavDeletion.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RWebDavDeletion: Object, LibraryScoped {
    @Persisted var key: String
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?
}
