//
//  AnnotationPreview.swift
//  Zotero
//
//  Created by Michal Rentka on 04.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationPreview {
    let parentKey: String
    let libraryId: LibraryIdentifier
    let pageIndex: Int
    let rects: [CGRect]
}
