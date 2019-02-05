//
//  SyncController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum SyncGroupType {
    case user(Int64)
    case group(Int)

    var apiPath: String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
        case .user(let identifier):
            return "users/\(identifier)"
        }
    }
}

enum SyncObjectType {
    case group, collection, search, item, trash

    var apiPath: String {
        switch self {
        case .group:
            return "groups"
        case .collection:
            return "collections"
        case .search:
            return "searches"
        case .item:
            return "items"
        case .trash:
            return "items/trash"
        }
    }
}

class SyncController {
    let userId: Int64
    let apiClient: ApiClient
    let dbStorage: DbStorage

    init(userId: Int64, apiClient: ApiClient, dbStorage: DbStorage) {
        self.userId = userId
        self.apiClient = apiClient
        self.dbStorage = dbStorage
    }

    func startSync() {
        let groupVersionRequest = VersionsRequest(groupType: .user(self.userId), objectType: .group, version: nil)
        self.apiClient.send(request: groupVersionRequest) { result in
            switch result {
            case .success(let versions):
                NSLog("Versions: \(versions)")
            case .failure(let error):
                NSLog("Error: \(error)")
            }
        }
    }
}
