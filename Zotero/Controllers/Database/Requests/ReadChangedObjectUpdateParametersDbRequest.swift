//
//  ReadChangedObjectUpdateParametersDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadChangedSearchUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> [[String : Any]] {
        let predicate = Predicates.changesInLibrary(libraryId: self.libraryId)
        return database.objects(RSearch.self).filter(predicate).compactMap({ $0.updateParameters })
    }
}

struct ReadChangedItemUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> [[String : Any]] {
        let predicate = Predicates.changesInLibrary(libraryId: self.libraryId)
        return database.objects(RItem.self).filter(predicate)
                                           .sorted(byKeyPath: "parent.rawChangedFields", ascending: false) // parents first, children later
                                           .compactMap({ $0.updateParameters })
    }
}

struct ReadChangedCollectionUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> [[String : Any]] {
        let predicate = Predicates.changesInLibrary(libraryId: self.libraryId)
        let objects = database.objects(RCollection.self).filter(predicate)

        if objects.count == 1 {
            return objects[0].updateParameters.flatMap({ [$0] }) ?? []
        }

        var levels: [Int: [[String: Any]]] = [:]

        for object in objects {
            guard let parameters = object.updateParameters else { continue }
            let level = object.level
            if var array = levels[level] {
                array.append(parameters)
                levels[level] = array
            } else {
                levels[level] = [parameters]
            }
        }

        var results: [[String: Any]] = []
        levels.keys.sorted().forEach { level in
            if let parameters = levels[level] {
                results.append(contentsOf: parameters)
            }
        }
        return results
    }
}

extension RCollection {
    fileprivate var level: Int {
        var level = 0
        var object: RCollection? = self
        while object?.parent != nil {
            object = object?.parent
            level += 1
        }
        return level
    }
}
