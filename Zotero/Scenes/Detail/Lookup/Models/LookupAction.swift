//
//  LookupActions.swift
//  Zotero
//
//  Created by Michal Rentka on 17.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

enum LookupAction {
    case initialize
    case lookUp(String)
    case cancelAllLookups
}
