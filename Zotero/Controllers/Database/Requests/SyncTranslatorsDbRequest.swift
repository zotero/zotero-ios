//
//  SyncTranslatorsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncTranslatorsDbRequest: DbResponseRequest {
    typealias Response = (updated: [String], deleted: [String])

    var needsWrite: Bool { return true }

    let metadata: [TranslatorMetadata]

    func process(in database: Realm) throws -> (updated: [String], deleted: [String]) {
        let toDelete = database.objects(RTranslatorMetadata.self).filter("id NOT IN %@", self.metadata.map({ $0.id }))
        var toDeleteFilenames = Array(toDelete.map({ $0.filename }))
        database.delete(toDelete)

        var toUpdateFilenames: [String] = []
        for metadata in self.metadata {
            let rMetadata: RTranslatorMetadata

            if let existing = database.object(ofType: RTranslatorMetadata.self, forPrimaryKey: metadata.id) {
                guard existing.lastUpdated.timeIntervalSince(metadata.lastUpdated) < 0 else { continue }
                rMetadata = existing
            } else {
                rMetadata = RTranslatorMetadata()
                rMetadata.id = metadata.id
            }

            rMetadata.label = metadata.label
            if !rMetadata.filename.isEmpty && rMetadata.filename != metadata.filename {
                // If this is not a new record and a file name of translator changed, delete the old file with old name.
                toDeleteFilenames.append(rMetadata.filename)
            }
            rMetadata.filename = metadata.filename
            rMetadata.lastUpdated = metadata.lastUpdated

            toUpdateFilenames.append(metadata.filename)
        }

        return (toUpdateFilenames, toDeleteFilenames)
    }
}
