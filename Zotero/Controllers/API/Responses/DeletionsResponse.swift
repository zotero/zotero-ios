//
//  DeletionsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct DeletionsResponse: Decodable {
    let collections: [String]
    let searches: [String]
    let items: [String]
    let tags: [String]
    let settings: [String]
}
