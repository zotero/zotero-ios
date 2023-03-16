//
//  TagPickerAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TagPickerAction {
    case load
    case changeLibrary(LibraryIdentifier)
    case select(String)
    case deselect(String)
    case search(String)
    case add(String)
}
