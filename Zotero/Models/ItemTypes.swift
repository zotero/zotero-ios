//
//  ItemTypes.swift
//  Zotero
//
//  Created by Michal Rentka on 07/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct ItemTypes {
    static let note = "note"
    static let attachment = "attachment"
    static let `case` = "case"
    static let letter = "letter"
    static let interview = "interview"
    static let webpage = "webpage"
    static let annotation = "annotation"
}

struct AnnotationTypes {
    static let note = "note"
    static let highlight = "highlight"
    static let image = "image"

    static func isValid(type: String) -> Bool {
        switch type {
        case AnnotationTypes.note, AnnotationTypes.highlight, AnnotationTypes.image:
            return true
        default:
            return false
        }
    }
}
