//
//  CitationStyle.swift
//  Zotero
//
//  Created by Michal Rentka on 03.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationStyle: Identifiable {
    let identifier: String
    let title: String
    let updated: Date
    let href: String

    var id: String {
        return self.identifier
    }
}
