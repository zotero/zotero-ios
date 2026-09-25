//
//  ItemsCollectionViewObject.swift
//  Zotero
//
//  Created by Michal Rentka on 19.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol ItemsCollectionViewObject: AnyObject {
    var key: String { get }
    var isNote: Bool { get }
    var isAttachment: Bool { get }
    var libraryIdentifier: LibraryIdentifier { get }
}
