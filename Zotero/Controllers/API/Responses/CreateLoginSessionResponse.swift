//
//  CreateLoginSessionResponse.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 21/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreateLoginSessionResponse: Decodable {
    let sessionToken: String
    let loginURL: URL
}
