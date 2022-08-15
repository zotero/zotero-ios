//
//  ReadLibraryDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 23.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadLibraryDbRequest: DbResponseRequest {
    typealias Response = Library

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Library {
        switch self.libraryId {
        case .custom(let type):
            return Library(identifier: self.libraryId, name: type.libraryName, metadataEditable: true, filesEditable: true)
        case .group(let identifier):
            guard let group = database.objects(RGroup.self).filter("identifier == %d", identifier).first else {
                throw DbError.objectNotFound
            }
            return Library(identifier: self.libraryId, name: group.name, metadataEditable: group.canEditMetadata, filesEditable: group.canEditFiles)
        }
    }
}
