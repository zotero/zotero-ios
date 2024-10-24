//
//  TrashKey.swift
//  Zotero
//
//  Created by Michal Rentka on 21.10.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

struct TrashKey: Hashable {
    enum Kind: Hashable {
        case collection
        case item
    }

    let type: Kind
    let key: String
}
