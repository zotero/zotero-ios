//
//  ReadVersionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadVersionDbRequest: DbResponseRequest {
    typealias Response = Int

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Int {
        switch self.libraryId {
        case .custom(let type):
            guard let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue) else {
                throw DbError.objectNotFound
            }
            return Versions(versions: library.versions).max

        case .group(let identifier):
            guard let library = database.object(ofType: RGroup.self, forPrimaryKey: identifier) else {
                throw DbError.objectNotFound
            }
            return Versions(versions: library.versions).max
        }
    }
}
