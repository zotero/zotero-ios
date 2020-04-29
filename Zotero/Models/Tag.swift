//
//  Tag.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct Tag: Identifiable, Equatable, Hashable {
    let name: String
    let color: String

    var id: String { return self.name }

    init(name: String, color: String) {
        self.name = name
        self.color = color
    }

    init(tag: RTag) {
        self.name = tag.name
        self.color = tag.color
    }
}
