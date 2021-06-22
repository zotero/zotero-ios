//
//  CiteAction.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CiteAction {
    case add(RemoteStyle)
    case load
    case remove(Int)
}
