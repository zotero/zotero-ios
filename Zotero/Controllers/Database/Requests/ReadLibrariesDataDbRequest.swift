//
//  ReadLibrariesDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadLibrariesDataDbRequest: DbResponseRequest {
    typealias Response = [LibraryData]

    let identifiers: [LibraryIdentifier]?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [LibraryData] {
        var allLibraryData: [LibraryData] = []

        let separatedIds = self.identifiers.flatMap { self.separateTypes(in: $0) }

        var customLibraries = database.objects(RCustomLibrary.self)
        if let types = separatedIds?.custom {
            customLibraries = customLibraries.filter("rawType IN %@", types.map({ $0.rawValue }))
        }
        allLibraryData.append(contentsOf: customLibraries.map(LibraryData.init))

        var groups = database.objects(RGroup.self).filter("isLocalOnly = false")
        if let groupIds = separatedIds?.group {
            groups = groups.filter("identifier IN %@", groupIds)
        }
        allLibraryData.append(contentsOf: groups.map(LibraryData.init))

        return allLibraryData
    }

    private func separateTypes(in identifiers: [LibraryIdentifier]) -> (custom: [RCustomLibraryType], group: [Int]) {
        var custom: [RCustomLibraryType] = []
        var group: [Int] = []
        identifiers.forEach { identifier in
            switch identifier {
            case .custom(let type):
                custom.append(type)
            case .group(let groupId):
                group.append(groupId)
            }
        }
        return (custom, group)
    }
}
