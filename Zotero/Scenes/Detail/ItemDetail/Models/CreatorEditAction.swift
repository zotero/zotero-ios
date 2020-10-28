//
//  CreatorEditAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CreatorEditAction {
    case setNamePresentation(ItemDetailState.Creator.NamePresentation)
    case setFirstName(String)
    case setLastName(String)
    case setFullName(String)
    case setType(String)
}
