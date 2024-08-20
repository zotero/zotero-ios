//
//  LibraryIdentifier.swift
//  Zotero
//
//  Created by Michal Rentka on 04.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import RxSwift

enum LibraryIdentifier: Equatable, Hashable {
    case custom(RCustomLibraryType)
    case group(Int)
}

extension LibraryIdentifier {
    var isGroupLibrary: Bool {
        switch self {
        case .custom: return false
        case .group: return true
        }
    }
}

extension LibraryIdentifier: Codable {
    enum CodingKeys: CodingKey {
        case custom
        case group
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .custom(let type):
            try container.encode(type, forKey: .custom)

        case .group(let id):
            try container.encode(id, forKey: .group)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let customType = try container.decode(RCustomLibraryType.self, forKey: .custom)
            self = .custom(customType)
        } catch {
            let groupId = try container.decode(Int.self, forKey: .group)
            self = .group(groupId)
        }
    }
}

extension LibraryIdentifier {
    func apiPath(userId: Int) -> String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
            
        case .custom:
            return "users/\(userId)"
        }
    }

    static func from(apiPath: String) -> LibraryIdentifier? {
        if apiPath.contains("users") {
            return .custom(.myLibrary)
        }

        guard apiPath.contains("groups"),
              let lastSeparator = apiPath.lastIndex(of: "/"),
              let groupId = Int(apiPath[apiPath.index(after: lastSeparator)..<apiPath.endIndex]) else { return nil }
        return .group(groupId)
    }

    var debugName: String {
        switch self {
        case .group(let groupId):
            return "Group (\(groupId))"

        case .custom(let type):
            switch type {
            case .myLibrary:
                return "My Library"
            }
        }
    }
}

extension LibraryIdentifier {
    func observe(in dbStorage: DbStorage, changes changed: @escaping (Library) -> Void) throws -> (Library, NotificationToken?) {
        return try observe(changes: changed) { groupId in
            return try dbStorage.perform(request: ReadGroupDbRequest(identifier: groupId), on: .main)
        }
    }

    func observe(in coordinator: DbCoordinator, changes changed: @escaping (Library) -> Void) throws -> (Library, NotificationToken?) {
        return try observe(changes: changed) { groupId in
            return try coordinator.perform(request: ReadGroupDbRequest(identifier: groupId))
        }
    }

    private func observe(changes changed: @escaping (Library) -> Void, getGroup: (Int) throws -> RGroup) throws -> (Library, NotificationToken?) {
        switch self {
        case .custom(let type):
            return (Library(identifier: self, name: type.libraryName, metadataEditable: true, filesEditable: true), nil)

        case .group(let groupId):
            let group = try getGroup(groupId)
            let token = group.observe(keyPaths: RGroup.observableKeypathsForAccessRights, on: .main) { (change: ObjectChange<RGroup>) in
                switch change {
                case .change(let group, _):
                    changed(Library(group: group))

                case .deleted, .error:
                    break
                }
            }
            return (Library(group: group), token)
        }
    }
}
