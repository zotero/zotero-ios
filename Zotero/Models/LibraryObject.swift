//
//  LibraryObject.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum LibraryIdentifier: Equatable, Hashable {
    case custom(RCustomLibraryType)
    case group(Int)
}

enum LibraryObject {
    case custom(RCustomLibrary)
    case group(RGroup)
}

extension LibraryObject {
    var identifier: LibraryIdentifier {
        switch self {
        case .custom(let object):
            return .custom(object.type)
        case .group(let object):
            return .group(object.identifier)
        }
    }
}
