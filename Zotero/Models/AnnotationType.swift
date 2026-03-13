//
//  AnnotationType.swift
//  Zotero
//
//  Created by Michal Rentka on 16/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AnnotationType: String, CaseIterable {
    case note
    case highlight
    case image
    case ink
    case underline
    case freeText = "text"

    #if MAINAPP
    var colors: [String] {
        return AnnotationsConfig.colors(for: self)
    }
    #endif
}
