//
//  ReadAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        let supportedTypes = AnnotationType.allCases.filter({ AnnotationsConfig.supported.contains($0.kind) }).map({ $0.rawValue })
        return database.objects(RItem.self).filter(.parent(self.attachmentKey, in: self.libraryId))
                                           .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
                                           .filter(.deleted(false))
                                           .filter("annotationType in %@", supportedTypes)
                                           .sorted(byKeyPath: "annotationSortIndex", ascending: true)
    }
}
