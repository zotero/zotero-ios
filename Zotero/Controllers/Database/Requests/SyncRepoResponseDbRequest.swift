//
//  SyncRepoResponseDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 09.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncRepoResponseDbRequest: DbRequest {
    let styles: [Style]
    let translators: [TranslatorMetadata]
    let deleteTranslators: [TranslatorMetadata]
    unowned let fileStorage: FileStorage

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        if !self.translators.isEmpty || !self.deleteTranslators.isEmpty {
            _ = try SyncTranslatorsDbRequest(updateMetadata: self.translators, deleteIndices: self.deleteTranslators.map({ $0.id }), forceUpdate: false, fileStorage: self.fileStorage).process(in: database)
        }
        if !self.styles.isEmpty {
            _ = try SyncStylesDbRequest(styles: self.styles).process(in: database)
        }
    }
}


