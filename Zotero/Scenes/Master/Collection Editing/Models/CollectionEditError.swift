//
//  CollectionEditError.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionEditError: Error, Identifiable, Hashable {
    case saveFailed
    case emptyName

    var id: CollectionEditError {
        return self
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .emptyName:
            hasher.combine(0)

        case .saveFailed:
            hasher.combine(1)
        }
    }

    var localizedDescription: String {
        switch self {
        case .emptyName:
            return L10n.Errors.Collections.emptyName

        case .saveFailed:
            return L10n.Errors.Collections.saveFailed
        }
    }
}
