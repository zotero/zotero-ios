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
    typealias Response = (update: [String], delete: [String])

    var needsWrite: Bool { return true }

    let updateMetadata: [TranslatorMetadata]
    let deleteIndices: [String]

    func process(in database: Realm) throws -> (update: [String], delete: [String]) {
        var delete: [String] = []
        if !self.deleteIndices.isEmpty {
            let objects = database.objects(RTranslatorMetadata.self).filter("id IN %@", self.deleteIndices)
            delete = objects.map({ $0.filename })
            database.delete(objects)
        }

        var update: [String] = []
        for metadata in self.updateMetadata {
            let rMetadata: RTranslatorMetadata

            if let existing = database.object(ofType: RTranslatorMetadata.self, forPrimaryKey: metadata.id) {
                guard existing.lastUpdated.timeIntervalSince(metadata.lastUpdated) < 0 else { continue }
                rMetadata = existing
            } else {
                rMetadata = RTranslatorMetadata()
                rMetadata.id = metadata.id
            }

            rMetadata.label = metadata.label
            rMetadata.filename = metadata.filename
            rMetadata.lastUpdated = metadata.lastUpdated

            update.append(metadata.filename)
        }

        return (update, delete)
    }
}
