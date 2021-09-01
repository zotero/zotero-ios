//
//  RTranslatorMetadata.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RTranslatorMetadata: Object {
    @Persisted(primaryKey: true) var id: String
    @Persisted var lastUpdated: Date
}
