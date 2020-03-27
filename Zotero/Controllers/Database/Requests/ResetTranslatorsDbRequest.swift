//
//  ResetTranslatorsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ResetTranslatorsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let metadata: [TranslatorMetadata]

    func process(in database: Realm) throws {
        database.deleteAll()

        self.metadata.forEach { data in
            let rData = RTranslatorMetadata()
            rData.id = data.id
            rData.lastUpdated = data.lastUpdated
            database.add(rData)
        }
    }
}
