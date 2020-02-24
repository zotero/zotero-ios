//
//  CollectionsError.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionsError: Error, Equatable {
    case dataLoading
    case collectionNotFound
    case collectionAssignment
    case deletion
}
