//
//  ReadChangedObjectUpdateParametersDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadUpdatedSettingsUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [[String : Any]] {
        // Page indices are sent only for user library, even though they are assigned to groups also.
        switch self.libraryId {
        case .group:
            return []
        case .custom:
            return database.objects(RPageIndex.self).filter(.changed).compactMap({ $0.updateParameters })
        }
    }
}

struct ReadUpdatedSearchUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [[String : Any]] {
        return database.objects(RSearch.self)
                       .filter(.changesWithoutDeletions(in: self.libraryId))
                       .compactMap({ $0.updateParameters })
    }
}

struct ReadUpdatedItemUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = ([[String: Any]], Bool)

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ([[String: Any]], Bool) {
        let items =  database.objects(RItem.self).filter(.itemChangesWithoutDeletions(in: self.libraryId))

        // Sort an array of collections or items from top-level to deepest, grouped by level
        //
        // This is used to sort higher-level objects first in upload JSON, since otherwise the API would reject lower-level objects for
        // having missing parents.

        var hasUpload = false
        var keyToLevel: [String: Int] = [:]
        var levels: [Int: [[String: Any]]] = [:]

        for item in items {
            if item.attachmentNeedsSync {
                hasUpload = true
            }

            guard let parameters = item.updateParameters else { continue }

            let level = self.level(for: item, levelCache: keyToLevel)
            keyToLevel[item.key] = level

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
        return (results, hasUpload)
    }

    private func level(for item: RItem, levelCache: [String: Int]) -> Int {
        var level = 0
        var parent: RItem? = item.parent

        while let current = parent {
            if let currentLevel = levelCache[current.key] {
                level += currentLevel + 1
                break
            }

            parent = current.parent
            level += 1
        }

        return level
    }
}

struct ReadUpdatedCollectionUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = [[String: Any]]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [[String : Any]] {
        let objects = database.objects(RCollection.self).filter(.changesWithoutDeletions(in: self.libraryId))

        if objects.count == 1 {
            return objects[0].updateParameters.flatMap({ [$0] }) ?? []
        }

        var levels: [Int: [[String: Any]]] = [:]

        for object in objects {
            guard let parameters = object.updateParameters else { continue }
            let level = object.level(in: database)
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
    fileprivate func level(in database: Realm) -> Int {
        guard let libraryId = self.libraryId else { return 0 }

        var level = 0
        var object: RCollection? = self
        while let parentKey = object?.parentKey {
            object = database.objects(RCollection.self).filter(.key(parentKey, in: libraryId)).first
            level += 1
        }
        return level
    }
}
