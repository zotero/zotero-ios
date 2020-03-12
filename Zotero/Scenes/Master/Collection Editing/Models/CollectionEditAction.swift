//
//  CollectionEditAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionEditAction {
    case setName(String)
    case setError(CollectionEditError?)
    case setParent(Collection?)
    case save
    case delete
    case deleteWithItems
}
