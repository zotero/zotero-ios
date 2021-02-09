//
//  ConflictViewControllerReceiver.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol ConflictViewControllerReceiver: class {
    func willDelete(items: [String], collections: [String], in libraryId: LibraryIdentifier)
}
