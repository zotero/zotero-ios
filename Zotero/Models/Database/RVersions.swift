//
//  RVersions.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RVersions: Object {
    @Persisted var collections: Int
    @Persisted var items: Int
    @Persisted var trash: Int
    @Persisted var searches: Int
    @Persisted var deletions: Int
    @Persisted var settings: Int
}
