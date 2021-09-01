//
//  RLink.swift
//  Zotero
//
//  Created by Michal Rentka on 09/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RLink: EmbeddedObject {
    @Persisted var type: String
    @Persisted var href: String
    @Persisted var contentType: String
    @Persisted var title: String
    @Persisted var length: Int

    var linkType: LinkType? {
        return LinkType(rawValue: self.type)
    }
}
