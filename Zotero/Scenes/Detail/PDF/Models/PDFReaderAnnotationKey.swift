//
//  PDFReaderAnnotationKey.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 10/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct PDFReaderAnnotationKey: Equatable, Hashable, Identifiable {
    enum Kind: Equatable, Hashable {
        case database
        case document
    }

    let key: String
    let sortIndex: String
    let type: Kind

    var id: String {
        return key
    }

    init(key: String, sortIndex: String = "", type: Kind) {
        self.key = key
        self.sortIndex = sortIndex
        self.type = type
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.key == rhs.key && lhs.type == rhs.type
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(type)
    }
}
