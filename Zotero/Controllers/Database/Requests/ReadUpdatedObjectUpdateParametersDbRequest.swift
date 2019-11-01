//
//  ReadChangedObjectUpdateParametersDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadUpdatedSearchUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> [[String : Any]] {
        return database.objects(RSearch.self)
                       .filter(.changesWithoutDeletions(in: self.libraryId))
                       .compactMap({ $0.updateParameters })
    }
}

struct ReadUpdatedItemUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = ([[String: Any]], Bool)

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> ([[String: Any]], Bool) {
        let items =  database.objects(RItem.self).filter(.itemChangesWithoutDeletions(in: self.libraryId))
                                                 .sorted(byKeyPath: "parent.rawChangedFields", ascending: false) // parents first, children later

        var hasUpload = false
        var parameters: [[String: Any]] = []
        items.forEach { item in
            if item.attachmentNeedsSync {
                hasUpload = true
            }
            if let itemParams = item.updateParameters {
                parameters.append(itemParams)
            }
        }
        return (parameters, hasUpload)
    }
}

struct ReadUpdatedCollectionUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> [[String : Any]] {
        let objects = database.objects(RCollection.self).filter(.changesWithoutDeletions(in: self.libraryId))

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
