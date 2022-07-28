//
//  AllCollectionPickerAction.swift
//  ZShare
//
//  Created by Michal Rentka on 11.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AllCollectionPickerAction {
    case toggleLibrary(LibraryIdentifier)
    case toggleCollection(CollectionIdentifier, LibraryIdentifier)
    case loadData
    case search(String?)
}
