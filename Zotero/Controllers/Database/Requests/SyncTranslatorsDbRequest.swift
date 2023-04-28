//
//  SyncTranslatorsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 23/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct SyncTranslatorsDbRequest: DbResponseRequest {
    typealias Response = [(String, String)]

    let updateMetadata: [TranslatorMetadata]
    let deleteIndices: [String]
    let forceUpdate: Bool
    unowned let fileStorage: FileStorage

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [(String, String)] {
        if !self.deleteIndices.isEmpty {
            DDLogInfo("SyncTranslatorsDbRequest: delete \(self.deleteIndices.count) translators")
            let objects = database.objects(RTranslatorMetadata.self).filter("id IN %@", self.deleteIndices)
            database.delete(objects)
        }

        var update: [(String, String)] = []
        DDLogInfo("SyncTranslatorsDbRequest: update \(self.updateMetadata.count) translators")
        for metadata in self.updateMetadata {
            let rMetadata: RTranslatorMetadata

            if let existing = database.object(ofType: RTranslatorMetadata.self, forPrimaryKey: metadata.id) {
                guard self.forceUpdate || existing.lastUpdated.timeIntervalSince(metadata.lastUpdated) < 0 || !self.fileStorage.has(Files.translator(filename: metadata.id)) else { continue }
                rMetadata = existing
            } else {
                rMetadata = RTranslatorMetadata()
                rMetadata.id = metadata.id
                database.add(rMetadata)
            }

            rMetadata.lastUpdated = metadata.lastUpdated
            update.append((metadata.id, metadata.filename))
        }

        return update
    }
}
