//
//  ApiEndpoint.swift
//  Zotero
//
//  Created by Michal Rentka on 19.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ApiEndpoint {
    case zotero(path: String)
    case webDav(URL)
    case other(URL)
}
