//
//  RDownload.swift
//  Zotero
//
//  Created by Michal Rentka on 20.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RDownload: Object, LibraryScoped {
    @Persisted(indexed: true) var taskId: Int?
    @Persisted(indexed: true) var key: String
    @Persisted var parentKey: String?
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?
}
