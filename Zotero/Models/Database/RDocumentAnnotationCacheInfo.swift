//
//  RDocumentAnnotationCacheInfo.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RDocumentAnnotationCacheInfo: Object, LibraryScoped {
    @Persisted(indexed: true) var attachmentKey: String
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?

    @Persisted var md5: String
    @Persisted var pageCount: Int
    @Persisted var annotationCount: Int
    @Persisted var uniqueBaseColors: List<String>
    @Persisted var updatedAt: Date

    @Persisted(originProperty: "cacheInfo") var annotations: LinkingObjects<RDocumentAnnotation>
}
