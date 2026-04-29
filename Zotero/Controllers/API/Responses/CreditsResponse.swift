//
//  CreditsResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 13.02.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreditsResponse: Decodable {
    let standardCreditsRemaining: Int
    let premiumCreditsRemaining: Int
}
