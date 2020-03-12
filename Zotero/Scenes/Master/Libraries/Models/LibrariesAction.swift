//
//  LibrariesAction.swift
//  Zotero
//
//  Created by Michal Rentka on 27/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum LibrariesAction {
    case loadData
    case setCustomLibraries(Results<RCustomLibrary>)
    case setGroupLibraries(Results<RGroup>)
}
