//
//  TableOfContentsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TableOfContentsAction<O: Outline> {
    case load
    case search(String)
    case setCurrentOutline(UUID?)
    case setOutlines([O])
}
