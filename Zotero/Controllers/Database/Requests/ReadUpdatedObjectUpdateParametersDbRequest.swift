//
//  ReadChangedObjectUpdateParametersDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadUpdatedParametersResponse {
    let parameters: [[String: Any]]
    let changeUuids: [String: [String]]
}

struct ReadUpdatedSettingsUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = ReadUpdatedParametersResponse

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ReadUpdatedParametersResponse {
        switch self.libraryId {
        case .group:
            return ReadUpdatedParametersResponse(parameters: [], changeUuids: [:])

        case .custom:
            // Page indices are submitted only for user library, even though they are assigned to groups also.
            var parameters: [[String: Any]] = []
            var uuids: [String: [String]] = [:]
            let changed = database.objects(RPageIndex.self).filter(.changed)

            for object in changed {
                guard let _parameters = object.updateParameters else { continue }
                parameters.append(_parameters)
                uuids[object.key] = object.changes.map({ $0.identifier })
            }

            return ReadUpdatedParametersResponse(parameters: parameters, changeUuids: uuids)
        }
    }
}

struct ReadUpdatedSearchUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = ReadUpdatedParametersResponse

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ReadUpdatedParametersResponse {
        var parameters: [[String: Any]] = []
        var uuids: [String: [String]] = [:]
        let changed = database.objects(RSearch.self).filter(.changesWithoutDeletions(in: self.libraryId))

        for object in changed {
            guard let _parameters = object.updateParameters else { continue }
            parameters.append(_parameters)
            uuids[object.key] = object.changes.map({ $0.identifier })
        }

        return ReadUpdatedParametersResponse(parameters: parameters, changeUuids: uuids)
    }
}

struct ReadUpdatedItemUpdateParametersDbRequest: DbResponseRequest {
    typealias Response = (ReadUpdatedParametersResponse, Bool)

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> (ReadUpdatedParametersResponse, Bool) {
        let objects =  database.objects(RItem.self).filter(.itemChangesWithoutDeletions(in: self.libraryId))

        if objects.count == 1, let item = objects.first, let parameters = item.updateParameters {
            let uuids = Array(item.changes.map({ $0.identifier }))
            return (ReadUpdatedParametersResponse(parameters: [parameters], changeUuids: [item.key: uuids]), item.attachmentNeedsSync)
        }

        // Sort an array of collections or items from top-level to deepest, grouped by level
        //
        // This is used to sort higher-level objects first in upload JSON, since otherwise the API would reject lower-level objects for having missing parents.

        var hasUpload = false
        var keyToLevel: [String: Int] = [:]
        var levels: [Int: [[String: Any]]] = [:]
        var uuids: [String: [String]] = [:]

        for item in objects {
            if item.attachmentNeedsSync {
                hasUpload = true
            }

            guard let parameters = item.updateParameters else { continue }

            let level = self.level(for: item, levelCache: keyToLevel)
            keyToLevel[item.key] = level
            uuids[item.key] = item.changes.map({ $0.identifier })

            if var array = levels[level] {
                array.append(parameters)
                levels[level] = array
            } else {
                levels[level] = [parameters]
            }
        }

        var results: [[String: Any]] = []
        for level in levels.keys.sorted() {
            guard let parameters = levels[level] else { continue }
            results.append(contentsOf: parameters)
        }
        return (ReadUpdatedParametersResponse(parameters: results, changeUuids: uuids), hasUpload)
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
    typealias Response = ReadUpdatedParametersResponse

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> ReadUpdatedParametersResponse {
        let objects = database.objects(RCollection.self).filter(.changesWithoutDeletions(in: self.libraryId))

        if objects.count == 1, let collection = objects.first, let parameters = collection.updateParameters {
            let uuids = Array(collection.changes.map({ $0.identifier }))
            return ReadUpdatedParametersResponse(parameters: [parameters], changeUuids: [collection.key: uuids])
        }

        var levels: [Int: [[String: Any]]] = [:]
        var uuids: [String: [String]] = [:]

        for object in objects {
            guard let parameters = object.updateParameters else { continue }

            uuids[object.key] = object.changes.map({ $0.identifier })

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
        return ReadUpdatedParametersResponse(parameters: results, changeUuids: uuids)
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
