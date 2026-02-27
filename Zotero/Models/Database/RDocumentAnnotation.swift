//
//  RDocumentAnnotation.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 26/01/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import UIKit

import RealmSwift

final class RDocumentAnnotation: Object, LibraryScoped {
    @Persisted(indexed: true) var key: String
    @Persisted(indexed: true) var attachmentKey: String
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?

    @Persisted var type: String
    @Persisted(indexed: true) var page: Int
    @Persisted var pageLabel: String
    @Persisted var rects: List<RRect>
    @Persisted var paths: List<RPath>
    @Persisted var lineWidth: Double?
    @Persisted var author: String
    @Persisted(indexed: true) var color: String
    @Persisted var comment: String
    @Persisted var text: String?
    @Persisted var fontSize: Double?
    @Persisted var rotation: Int?
    @Persisted var sortIndex: String
    @Persisted var dateAdded: Date
    @Persisted var dateModified: Date
    @Persisted var cacheInfo: RDocumentAnnotationCacheInfo?
}
