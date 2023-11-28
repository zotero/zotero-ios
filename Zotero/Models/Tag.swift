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
    let emojiGroup: String?
    let type: RTypedTag.Kind

    var id: String { return self.name }

    init(name: String, color: String) {
        self.name = name
        self.color = color
        self.emojiGroup = EmojiExtractor.extractFirstContiguousGroup(from: name)
        self.type = .manual
    }

    init(tag: RTag) {
        self.name = tag.name
        self.color = tag.color
        self.emojiGroup = tag.emojiGroup
        self.type = .manual
    }

    init(tag: RTypedTag) {
        self.name = tag.tag?.name ?? ""
        self.color = tag.tag?.color ?? ""
        self.emojiGroup = tag.tag?.emojiGroup
        self.type = tag.type
    }
}
