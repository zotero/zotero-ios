//
//  CollectionFieldKeys.swift
//  Zotero
//
//  Created by Michal Rentka on 04/09/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionFieldKeys {
    #if TESTING
    static let knownDataKeys: [String] = ["name"]
    #else
    static let knownDataKeys: [String] = ["key", "version", "name", "parentCollection", "relations"]
    #endif
}
